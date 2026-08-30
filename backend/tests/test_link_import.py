import httpx
import pytest

from app import import_link
from app.import_link import ImportedArticle, ImportedFile, LinkImportError
from app.routes import link_import


def test_extracts_a_plain_paul_graham_style_article() -> None:
    article = import_link._article_from_html(
        """
        <html><head><title>How to Do Great Work</title>
        <meta name="author" content="Paul Graham"></head>
        <body><font>How to do great work is an old question.<br><br>
        The first step is to work on something you genuinely care about.<br><br>
        The second step is to keep going long enough to find the hard parts.</font></body></html>
        """,
        "https://paulgraham.com/greatwork.html",
    )

    assert article.title == "How to Do Great Work"
    assert article.author == "Paul Graham"
    assert "genuinely care" in article.text
    assert article.source_name == "paulgraham.com"


def test_rejects_private_or_loopback_destinations(monkeypatch) -> None:
    monkeypatch.setattr(
        import_link.socket,
        "getaddrinfo",
        lambda *_args, **_kwargs: [(None, None, None, None, ("127.0.0.1", 0))],
    )

    with pytest.raises(LinkImportError, match="Local or private"):
        import_link._validate_public_url("http://example.test/article")


def test_html_response_becomes_an_article(monkeypatch) -> None:
    monkeypatch.setattr(import_link, "_validate_public_url", lambda value: value)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=b"<html><title>Field Notes</title><main><h1>Field Notes</h1><p>" + b"A" * 220 + b"</p></main></html>",
            request=request,
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = import_link._fetch(client, "https://example.test/notes")

    assert isinstance(result, ImportedArticle)
    assert result.title == "Field Notes"
    assert len(result.text) > 200


def test_direct_epub_is_validated_but_not_proxied(monkeypatch) -> None:
    monkeypatch.setattr(import_link, "_validate_public_url", lambda value: value)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/epub+zip"},
            content=b"PK\x03\x04",
            request=request,
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = import_link._fetch(client, "https://books.example.test/reading.epub")

    assert isinstance(result, ImportedFile)
    assert result.source_url == "https://books.example.test/reading.epub"
    assert result.content_type == "application/epub+zip"


def test_attachment_filename_identifies_a_pdf_download(monkeypatch) -> None:
    monkeypatch.setattr(import_link, "_validate_public_url", lambda value: value)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={
                "content-type": "application/octet-stream",
                "content-disposition": 'attachment; filename="essay.pdf"',
            },
            content=b"%PDF-1.7",
            request=request,
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = import_link._fetch(client, "https://books.example.test/download?id=123")

    assert isinstance(result, ImportedFile)
    assert result.title == "essay.pdf"


def test_link_import_route_exposes_only_the_reader_safe_article(monkeypatch) -> None:
    monkeypatch.setattr(
        link_import,
        "import_link",
        lambda _url: ImportedArticle(
            title="An essay", author="Author", text="Paragraph one.\n\nParagraph two.",
            source_name="example.com", source_url="https://example.com/essay"),
    )

    response = link_import.create_link_import(link_import.LinkImportRequest(url="https://example.com/essay"))

    assert response.kind == "article"
    assert response.title == "An essay"
    assert response.text == "Paragraph one.\n\nParagraph two."
