"""Fetch kimbino Intermarche main folheto page + PDF."""
import json, os, re, sys, time, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})

report = {}

# 1. Main Intermarché page
urls = [
    ("hub", "https://www.kimbino.pt/intermarche/"),
    ("main_folheto", "https://www.kimbino.pt/intermarche/intermarche-folheto-de-quinta-feira-16-04-2026-5045114/"),
]
for name, u in urls:
    r = s.get(u, timeout=30, allow_redirects=True)
    t = r.text
    open(f"{TMP}/kimbino_im_{name}.html", "w", encoding="utf-8").write(t)
    # all PDF refs
    pdfs = sorted(set(re.findall(r'https?://[^\s"<>]+\.pdf', t)))
    # JPEG/PNG pages
    imgs = sorted(set(re.findall(r'https?://[^\s"<>]+\.(?:jpg|jpeg|png)(?:\?[^\s"<>]*)?', t)))
    # detail links
    detail = sorted(set(re.findall(r'href="(/intermarche/[a-z0-9\-]+/)"', t)))
    # NUXT blob size
    m = re.search(r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', t, flags=re.S)
    nuxt_len = len(m.group(1)) if m else 0
    if m:
        open(f"{TMP}/kimbino_im_{name}_nuxt.json", "w", encoding="utf-8").write(m.group(1))
    report[name] = {
        "status": r.status_code, "final_url": str(r.url), "len": len(t),
        "pdf_links": pdfs[:10],
        "image_sample": [i[:120] for i in imgs[:3]],
        "detail_links_count": len(detail),
        "detail_sample": detail[:10],
        "nuxt_len": nuxt_len,
    }
    time.sleep(3)

# 2. Save main folheto PDF if found
pdfs = report["main_folheto"].get("pdf_links") or []
if pdfs:
    main_pdf = pdfs[0]
    report["main_pdf_url"] = main_pdf
    r = s.get(main_pdf, timeout=120, stream=True)
    pdf_path = f"{TMP}/intermarche_folheto_main.pdf"
    with open(pdf_path, "wb") as f:
        for c in r.iter_content(128*1024): f.write(c)
    report["main_pdf_size"] = os.path.getsize(pdf_path)
    # Quick text layer check
    try:
        import pypdf
        reader = pypdf.PdfReader(pdf_path)
        report["main_pdf_pages"] = len(reader.pages)
        total_chars = 0
        first_text = ""
        for i, p in enumerate(reader.pages):
            try: txt = p.extract_text() or ""
            except Exception: txt = ""
            total_chars += len(txt)
            if i < 2: first_text += f"\n--- page {i+1} ---\n" + txt[:600]
        report["main_pdf_total_text_chars"] = total_chars
        report["main_pdf_first_pages_sample"] = first_text[:2000]
    except Exception as e:
        report["main_pdf_text_err"] = str(e)[:200]
else:
    report["main_pdf_err"] = "no PDF link on main_folheto page"

with open(f"{TMP}/kimbino_im_main.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps(report, ensure_ascii=False, indent=2)[:3500])
