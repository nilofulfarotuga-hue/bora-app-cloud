"""Download the weekly Promoções PDF and check if it has an extractable text layer."""
import os, sys, time, requests, subprocess
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
url = "https://object.storage.eu01.onstackit.cloud/leaflets/pdfs/019d96ba-f920-76a6-bd89-dfa45929e51d/Promocoes-A-partir-de-20-04-01.pdf"
pdf_path = f"{TMP}/lidl_promocoes_20260420.pdf"

# Download
print(f"Downloading {url}")
r = requests.get(url, headers={"User-Agent": UA}, timeout=120, stream=True)
print(" status", r.status_code, "size", r.headers.get("content-length"))
with open(pdf_path, "wb") as f:
    for chunk in r.iter_content(64*1024):
        f.write(chunk)
print(" saved", pdf_path, os.path.getsize(pdf_path), "bytes")

# Check for text layer via pypdf / pdfminer if available
try:
    import pypdf
    reader = pypdf.PdfReader(pdf_path)
    pages = len(reader.pages)
    print(f" pages={pages}")
    total_chars = 0
    first_text = ""
    for i, p in enumerate(reader.pages):
        try:
            txt = p.extract_text() or ""
        except Exception:
            txt = ""
        total_chars += len(txt)
        if i < 3: first_text += f"\n--- page {i+1} ---\n" + txt[:400]
    print(f" total_text_chars={total_chars}")
    print(" first pages text preview:")
    print(first_text[:1500])
except ImportError:
    print(" pypdf not installed — trying pip install...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pypdf", "--quiet"])
    import pypdf
    reader = pypdf.PdfReader(pdf_path)
    pages = len(reader.pages)
    print(f" pages={pages}")
    total_chars = 0
    first_text = ""
    for i, p in enumerate(reader.pages):
        try:
            txt = p.extract_text() or ""
        except Exception:
            txt = ""
        total_chars += len(txt)
        if i < 3: first_text += f"\n--- page {i+1} ---\n" + txt[:400]
    print(f" total_text_chars={total_chars}")
    print(" first pages text preview:")
    print(first_text[:1500])
