"""Peek pages 1-3 of novidades + cien PDFs to see their text structure."""
import sys, pypdf
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"

for name in ["novidades", "cien"]:
    p = f"{TMP}/lidl_folheto_{name}.pdf"
    print(f"\n====================== {name.upper()} ======================")
    r = pypdf.PdfReader(p)
    print(f"pages: {len(r.pages)}")
    for i in [0, 1, 2, 5]:
        if i >= len(r.pages): continue
        t = r.pages[i].extract_text() or ""
        print(f"\n----- page {i+1} (len={len(t)}) -----")
        print(t[:1200])
