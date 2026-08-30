"""Safe, server-side link classification and article extraction for Inkflow.

The phone never has to guess whether a pasted URL is a web article or a book
file.  HTML is fetched and reduced to reader-friendly text here; file links
are validated and handed back to the client for its existing local PDF/EPUB
importer.  Keeping the actual book file on the device preserves the native
PDF/EPUB reader and avoids proxying large copyrighted files through the API.
"""

from __future__ import annotations

from dataclasses import dataclass
from html import unescape
import ipaddress
import re
import socket
from typing import Union
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit

from bs4 import BeautifulSoup
import httpx


MAX_ARTICLE_BYTES = 5 * 1024 * 1024
MAX_REDIRECTS = 5
FETCH_TIMEOUT = httpx.Timeout(connect=7.0, read=15.0, write=7.0, pool=7.0)
USER_AGENT = "Inkflow/1.0 (+https://inkflow.app/link-import)"

_DOCUMENT_EXTENSIONS = {"pdf", "epub", "docx", "rtf", "txt", "md", "markdown", "html", "htm"}
_BINARY_DOCUMENT_EXTENSIONS = {"pdf", "epub", "docx", "rtf"}
_HTML_CONTENT_TYPES = {"text/html", "application/xhtml+xml"}
_TEXT_CONTENT_TYPES = {
    "text/plain",
    "text/markdown",
    "text/x-markdown",
    "application/markdown",
}
_FILE_CONTENT_TYPES = {
    "application/pdf",
    "application/epub+zip",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/rtf",
    "text/rtf",
}


class LinkImportError(Exception):
    """An error that can safely be returned to the person importing a link."""

    def __init__(self, message: str, status_code: int = 422):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


@dataclass(frozen=True)
class ImportedArticle:
    title: str
    author: str
    text: str
    source_name: str
    source_url: str


@dataclass(frozen=True)
class ImportedFile:
    title: str
    source_name: str
    source_url: str
    content_type: str | None


ImportedLink = Union[ImportedArticle, ImportedFile]


def import_link(url: str) -> ImportedLink:
    """Resolve a public URL into an article or a client-downloadable file.

    Every redirect destination is parsed and DNS-checked before it is fetched.
    Requests only use HTTP(S), disallow credentials/nonstandard ports, and
    reject loopback, RFC1918, link-local, multicast, and otherwise non-global
    addresses. This is deliberately synchronous: FastAPI runs normal `def`
    handlers in its worker pool, so a bounded network fetch cannot block its
    event loop.
    """

    normalized = _validate_public_url(url)
    parsed = urlsplit(normalized)
    if _is_x_status_url(parsed):
        try:
            return _fetch_x_status(normalized)
        except LinkImportError:
            # An oEmbed request may be disabled for a public post; continue to
            # the original page where article URLs and regular HTML still work.
            pass

    with httpx.Client(
        timeout=FETCH_TIMEOUT,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml,text/plain,application/pdf,application/epub+zip,*/*;q=0.2"},
        follow_redirects=False,
    ) as client:
        return _fetch(client, normalized)


def _fetch(client: httpx.Client, initial_url: str) -> ImportedLink:
    current = initial_url
    for _ in range(MAX_REDIRECTS + 1):
        _validate_public_url(current)
        try:
            with client.stream("GET", current) as response:
                if response.status_code in {301, 302, 303, 307, 308}:
                    location = response.headers.get("location")
                    if not location:
                        raise LinkImportError("That link redirected without a destination.")
                    current = _validate_public_url(urljoin(current, location))
                    continue
                if response.status_code in {401, 403}:
                    raise LinkImportError("That page is private or blocks imports. Try its public article URL instead.", 403)
                if response.status_code == 404:
                    raise LinkImportError("We couldn't find anything at that link.", 404)
                if not 200 <= response.status_code < 300:
                    raise LinkImportError("That link could not be opened right now.", 502)

                content_type = _content_type(response.headers.get("content-type"))
                disposition_name = _filename_from_disposition(response.headers.get("content-disposition"))
                is_file = (
                    _is_document_url(current)
                    or _is_document_filename(disposition_name)
                    or content_type in _FILE_CONTENT_TYPES
                )
                if is_file:
                    return ImportedFile(
                        title=_clean_title(disposition_name or _title_from_url(current)),
                        source_name=_source_name(current),
                        source_url=current,
                        content_type=content_type or None,
                    )

                # A text file is already reader-ready; HTML is reduced to its
                # primary article content. Limit streaming before materializing
                # bytes so a hostile page cannot consume the Vercel worker.
                declared_length = _content_length(response.headers.get("content-length"))
                if declared_length is not None and declared_length > MAX_ARTICLE_BYTES:
                    raise LinkImportError("That webpage is too large to turn into a reading item.", 413)
                body = _read_limited(response, MAX_ARTICLE_BYTES)
        except httpx.TimeoutException as exc:
            raise LinkImportError("That site took too long to respond. Please try again.", 504) from exc
        except httpx.HTTPError as exc:
            raise LinkImportError("We couldn't reach that link. Check that it is public and try again.", 502) from exc

        if content_type in _TEXT_CONTENT_TYPES:
            text = _normalize_text(_decode_text(body))
            if len(text) < 40:
                raise LinkImportError("There wasn't enough readable text at that link.")
            return ImportedArticle(
                title=_clean_title(_title_from_url(current)),
                author="Web",
                text=text,
                source_name=_source_name(current),
                source_url=current,
            )

        # Servers often omit or mislabel content-type. Only inspect bodies that
        # look like HTML; never turn arbitrary binary data into a text book.
        decoded = _decode_text(body)
        if content_type in _HTML_CONTENT_TYPES or _looks_like_html(decoded):
            return _article_from_html(decoded, source_url=current)
        if _is_document_url(current):
            return ImportedFile(
                title=_clean_title(_title_from_url(current)), source_name=_source_name(current),
                source_url=current, content_type=content_type or None)
        raise LinkImportError("That link is not a readable article or supported document.")

    raise LinkImportError("That link redirected too many times.")


def _fetch_x_status(source_url: str) -> ImportedArticle:
    """Use X's public oEmbed endpoint for public status URLs.

    X pages are usually JavaScript shells, while oEmbed contains the post text
    and author without needing credentials. Article URLs on x.com intentionally
    fall through to normal HTML extraction instead.
    """

    endpoint = "https://publish.twitter.com/oembed?" + urlencode(
        {"url": source_url, "omit_script": "1", "dnt": "1"}
    )
    with httpx.Client(timeout=FETCH_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
        try:
            response = client.get(endpoint)
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise LinkImportError("That X post could not be imported as a public article.") from exc
    html = str(payload.get("html") or "")
    text = _normalize_text(BeautifulSoup(html, "html.parser").get_text("\n"))
    if len(text) < 20:
        raise LinkImportError("That X post did not include readable text.")
    author = _clean_title(str(payload.get("author_name") or "X"))
    first_line = next((line for line in text.splitlines() if line.strip()), "Post")
    return ImportedArticle(
        title=_clean_title(f"{author} on X: {first_line[:72]}"),
        author=author,
        text=text,
        source_name="X",
        source_url=source_url,
    )


def _article_from_html(html: str, source_url: str) -> ImportedArticle:
    soup = BeautifulSoup(html, "html.parser")
    title = _meta(soup, "property", "og:title") or _meta(soup, "name", "twitter:title")
    title = title or (soup.title.get_text(" ", strip=True) if soup.title else None)
    author = (
        _meta(soup, "name", "author")
        or _meta(soup, "property", "article:author")
        or _meta(soup, "name", "byl")
        or "Web"
    )
    for node in soup.select("script, style, noscript, template, nav, footer, header, aside, form, svg, iframe, [aria-hidden='true']"):
        node.decompose()

    root = _article_root(soup)
    text = _extract_readable_text(root)
    if len(text) < 180 and root is not soup.body and soup.body is not None:
        text = _extract_readable_text(soup.body)
    if len(text) < 40:
        raise LinkImportError("We couldn't find enough readable text in that page.")
    return ImportedArticle(
        title=_clean_title(title or _title_from_url(source_url)),
        author=_clean_title(author),
        text=text,
        source_name=_source_name(source_url),
        source_url=source_url,
    )


def _article_root(soup: BeautifulSoup):
    for selector in ("article", "main", "[role='main']", ".article", ".post", ".entry-content", ".post-content"):
        candidate = soup.select_one(selector)
        if candidate and len(candidate.get_text(" ", strip=True)) >= 120:
            return candidate
    candidates = soup.find_all(["section", "div"])
    if candidates:
        return max(candidates, key=lambda node: len(node.get_text(" ", strip=True)))
    return soup.body or soup


def _extract_readable_text(root) -> str:
    blocks: list[str] = []
    for node in root.find_all(["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote", "pre"]):
        value = _normalize_text(node.get_text(" ", strip=True))
        if not value:
            continue
        if node.name and node.name.startswith("h") and node.name[1:].isdigit():
            blocks.append("# " + value)
        elif len(value) >= 20 or node.name in {"blockquote", "pre"}:
            blocks.append(value)
    text = _normalize_text("\n\n".join(blocks))
    if len(text) >= 160:
        return text
    # Paul Graham-style minimal pages often use bare text + <br>, not <p>.
    return _normalize_text(root.get_text("\n"))


def _validate_public_url(value: str) -> str:
    try:
        parsed = urlsplit(value.strip())
    except ValueError as exc:
        raise LinkImportError("That doesn't look like a valid web link.") from exc
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise LinkImportError("Use a public http or https link.")
    if parsed.username or parsed.password:
        raise LinkImportError("Links with embedded credentials can't be imported.")
    try:
        port = parsed.port
    except ValueError as exc:
        raise LinkImportError("That link has an invalid port.") from exc
    if port is not None and port not in {80, 443}:
        raise LinkImportError("Only standard public web links can be imported.")
    hostname = parsed.hostname.rstrip(".").lower()
    if hostname in {"localhost", "localhost.localdomain"} or hostname.endswith(".local"):
        raise LinkImportError("Local or private addresses can't be imported.")
    _require_public_hostname(hostname)
    path = parsed.path or "/"
    return urlunsplit((parsed.scheme.lower(), parsed.netloc, path, parsed.query, ""))


def _require_public_hostname(hostname: str) -> None:
    try:
        addresses = socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise LinkImportError("We couldn't resolve that public website.") from exc
    if not addresses:
        raise LinkImportError("We couldn't resolve that public website.")
    for _, _, _, _, sockaddr in addresses:
        try:
            address = ipaddress.ip_address(sockaddr[0])
        except ValueError as exc:
            raise LinkImportError("That address is not supported.") from exc
        if not address.is_global:
            raise LinkImportError("Local or private addresses can't be imported.")


def _is_x_status_url(parsed) -> bool:
    host = (parsed.hostname or "").lower().removeprefix("www.")
    if host not in {"x.com", "twitter.com", "mobile.twitter.com"}:
        return False
    return bool(re.search(r"/[^/]+/status/\d+", parsed.path, flags=re.IGNORECASE))


def _is_document_url(url: str) -> bool:
    path = urlsplit(url).path.lower()
    return any(path.endswith("." + extension) for extension in _BINARY_DOCUMENT_EXTENSIONS)


def _is_document_filename(value: str | None) -> bool:
    if not value:
        return False
    lowered = value.lower()
    return any(lowered.endswith("." + extension) for extension in _BINARY_DOCUMENT_EXTENSIONS)


def _content_type(value: str | None) -> str:
    return (value or "").split(";", 1)[0].strip().lower()


def _content_length(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _read_limited(response: httpx.Response, maximum: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    for chunk in response.iter_bytes():
        total += len(chunk)
        if total > maximum:
            raise LinkImportError("That webpage is too large to turn into a reading item.", 413)
        chunks.append(chunk)
    return b"".join(chunks)


def _decode_text(value: bytes) -> str:
    for encoding in ("utf-8", "utf-16", "windows-1252", "latin-1"):
        try:
            return value.decode(encoding)
        except UnicodeDecodeError:
            continue
    return value.decode("utf-8", errors="replace")


def _looks_like_html(value: str) -> bool:
    head = value.lstrip()[:600].lower()
    return "<html" in head or "<!doctype html" in head or "<body" in head


def _meta(soup: BeautifulSoup, attribute: str, value: str) -> str | None:
    node = soup.find("meta", attrs={attribute: re.compile("^" + re.escape(value) + "$", re.I)})
    content = node.get("content") if node else None
    return _normalize_text(str(content)) if content else None


def _normalize_text(value: str) -> str:
    value = unescape(value).replace("\r\n", "\n").replace("\r", "\n")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in value.split("\n")]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(line for line in lines if line)).strip()


def _title_from_url(url: str) -> str:
    parsed = urlsplit(url)
    path = parsed.path.rstrip("/").split("/")[-1]
    if path and path.lower().split(".")[-1] not in _DOCUMENT_EXTENSIONS:
        return path.replace("-", " ").replace("_", " ")
    return _source_name(url)


def _source_name(url: str) -> str:
    host = (urlsplit(url).hostname or "Web").lower().removeprefix("www.")
    return host or "Web"


def _filename_from_disposition(value: str | None) -> str | None:
    if not value:
        return None
    match = re.search(r"filename\*?=(?:UTF-8''|[\"'])?([^;\"']+)", value, flags=re.I)
    return unescape(match.group(1)).strip() if match else None


def _clean_title(value: str) -> str:
    value = _normalize_text(value)
    value = re.sub(r"\s+[-|]\s+(?:X|Twitter|Medium|Substack)$", "", value, flags=re.I)
    return value[:300] if value else "Imported reading"
