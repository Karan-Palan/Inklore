import json, re, sys
src = sys.argv[1]; out = sys.argv[2]
raw = open(src, encoding="utf-8").read()
start = raw.index("*** START OF THE PROJECT GUTENBERG EBOOK")
end = raw.index("*** END OF THE PROJECT GUTENBERG EBOOK")
body = raw[raw.index("\n", start)+1:end]
lines = body.split("\n")
chapters = []; cur = None; part = ""
i = 0
while i < len(lines):
    ln = lines[i].strip()
    if re.match(r"^PART [IVX]+\.$", ln):
        part = ln.rstrip("."); i += 1; continue
    m = re.match(r"^CHAPTER ([IVX]+)\.$", ln)
    if m:
        # title is the next non-empty line
        j = i + 1
        while j < len(lines) and not lines[j].strip(): j += 1
        title = lines[j].strip().rstrip(".").title() if j < len(lines) else ""
        cur = {"part": part, "number": m.group(1), "title": title, "paragraphs": []}
        chapters.append(cur); i = j + 1; continue
    if cur is not None:
        # accumulate paragraph blocks separated by blank lines
        buf = []
        while i < len(lines) and lines[i].strip():
            buf.append(lines[i].strip()); i += 1
        if buf:
            p = " ".join(buf)
            if not p.startswith("Illustration") and len(p) > 1:
                cur["paragraphs"].append(p)
    i += 1
# drop trailing part-heading noise & sanity
for idx, c in enumerate(chapters):
    c["index"] = idx
    c["words"] = sum(len(p.split()) for p in c["paragraphs"])
book = {"id": "study-in-scarlet", "title": "A Study in Scarlet", "author": "Arthur Conan Doyle", "chapters": chapters}
json.dump(book, open(out, "w"), ensure_ascii=False, indent=1)
print(len(chapters), "chapters")
for c in chapters: print(c["part"], c["number"], c["title"], c["words"], "words", len(c["paragraphs"]), "paras")
