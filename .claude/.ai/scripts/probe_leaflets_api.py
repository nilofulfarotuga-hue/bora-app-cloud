"""Probe Schwarz leaflets API using discovered patterns."""
import json, os, re, sys, time
import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

# UUIDs from hub page (most recent ones, ignore the old 2022 one)
UUIDS = [
    ("promocoes-a-partir-de-20-04", "019d30fe-9e8f-712f-ba36-dcedd910f503"),
    ("novidades-a-partir-de-20-04", "019d9077-7863-73dd-a263-be2166671ede"),
    ("folheto-especial-cien",       "019d96ba-7d3a-7572-a513-c784f18f60be"),  # or 019d96ba-f920-76a6-bd89-dfa45929e51d
]

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
                  "Origin": "https://lidl.leaflets.schwarz",
                  "Referer": "https://lidl.leaflets.schwarz/"})

report = {"per_uuid": {}}
for name, u in UUIDS:
    rec = {}
    for pat in [
        f"https://endpoints.leaflets.schwarz/{u}/view/flyer/page/1",
        f"https://endpoints.leaflets.schwarz/{u}/view/flyer/page/1?country=PT",
        f"https://endpoints.leaflets.schwarz/{u}/view/flyer/page/1?country=PT&region=HHZ",
        f"https://endpoints.leaflets.schwarz/{u}/view/flyer/page/1?region=HHZ",
        f"https://endpoints.leaflets.schwarz/{u}/view/flyer",
        f"https://endpoints.leaflets.schwarz/{u}",
        f"https://endpoints.leaflets.schwarz/flyer/{u}",
        f"https://endpoints.leaflets.schwarz/{u}/pages",
        f"https://endpoints.leaflets.schwarz/{u}/pages/1",
        f"https://endpoints.leaflets.schwarz/{u}/offers",
        f"https://endpoints.leaflets.schwarz/{u}/products",
    ]:
        try:
            r = s.get(pat, timeout=20)
            rec[pat] = {"status": r.status_code, "len": len(r.text), "ctype": r.headers.get("content-type","")[:60],
                        "body0": r.text[:200].replace("\n"," ") if r.status_code<500 else None}
        except Exception as e:
            rec[pat] = {"err": type(e).__name__}
        time.sleep(1.5)
    report["per_uuid"][name] = rec
    time.sleep(1)

# Also test productService patterns
u0 = UUIDS[0][1]
for pat in [
    f"https://endpoints.leaflets.schwarz/productService/{u0}/productsForOverviewDisplay/EN/",
    f"https://endpoints.leaflets.schwarz/productService/{u0}/productsForOverviewDisplay/PT/",
    f"https://endpoints.leaflets.schwarz/productService/{u0}/productsForOverviewDisplay/pt_PT/",
    f"https://endpoints.leaflets.schwarz/productService/{u0}/productsForOverviewDisplay/pt/",
]:
    try:
        r = s.get(pat, timeout=20)
        report.setdefault("productService", {})[pat] = {
            "status": r.status_code, "len": len(r.text), "body0": r.text[:200].replace("\n"," ")}
    except Exception as e:
        report.setdefault("productService", {})[pat] = {"err": type(e).__name__}
    time.sleep(1.5)

with open(f"{TMP}/lidl_api_probes.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

# Summarize: list all 2xx
print("=== 200 OK endpoints ===")
for uuid_name, rec in report["per_uuid"].items():
    for url, info in rec.items():
        if isinstance(info, dict) and info.get("status") in (200, 201):
            print(f"[{uuid_name}] {url} -> {info.get('status')} ctype={info.get('ctype')} len={info.get('len')}")
for url, info in report.get("productService", {}).items():
    if isinstance(info, dict) and info.get("status") in (200, 201):
        print(f"[productService] {url} -> {info.get('status')} len={info.get('len')}")
print()
print("=== non-404 with content ===")
for uuid_name, rec in report["per_uuid"].items():
    for url, info in rec.items():
        if isinstance(info, dict) and info.get("status") not in (None, 404) and info.get("status") != 200:
            print(f"[{uuid_name}] {url} -> {info.get('status')} body0: {info.get('body0')}")
