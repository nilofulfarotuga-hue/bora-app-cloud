"""Probe /v4/flyer endpoint with discovered pattern."""
import json, sys, time, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

UUID_PROMOS = "019d30fe-9e8f-712f-ba36-dcedd910f503"
UUID_NOVIDADES = "019d9077-7863-73dd-a263-be2166671ede"

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
                  "Accept": "application/json, text/plain, */*",
                  "Origin": "https://lidl.leaflets.schwarz",
                  "Referer": "https://lidl.leaflets.schwarz/"})

base = "https://endpoints.leaflets.schwarz/v4"

tests = [
    f"{base}/flyer?flyer_identifier={UUID_PROMOS}",
    f"{base}/flyer?flyer_identifier={UUID_PROMOS}&region_id=0",
    f"{base}/flyer?flyer_identifier={UUID_PROMOS}&region_id=1",
    f"{base}/flyer?flyer_identifier={UUID_PROMOS}&region_id=HHZ",
    f"{base}/flyer/{UUID_PROMOS}",
    f"{base}/flyer/{UUID_PROMOS}?region_id=0",
    f"{base}/flyer-fallback?domain=www.lidl.pt",
    f"{base}/flyer-fallback?domain=lidl.leaflets.schwarz",
    f"{base}/flyer-fallback?domain=lidl.pt",
]

report = {}
for u in tests:
    try:
        r = s.get(u, timeout=20)
        ctype = r.headers.get("content-type","")
        body0 = r.text[:300].replace("\n"," ")
        rec = {"status": r.status_code, "len": len(r.text), "ctype": ctype[:70], "body0": body0}
        # If json, parse
        if "application/json" in ctype and r.status_code == 200:
            try:
                d = r.json()
                rec["keys"] = list(d.keys()) if isinstance(d, dict) else f"list[{len(d)}]"
            except Exception: pass
        report[u] = rec
        print(r.status_code, len(r.text), u[:120])
    except Exception as e:
        report[u] = {"err": type(e).__name__ + ":" + str(e)[:80]}
        print("ERR", u[:120])
    time.sleep(1.5)

# If any succeeded, save the full response of first success for inspection
ok = [(u, i) for u, i in report.items() if isinstance(i, dict) and i.get("status") == 200 and "json" in (i.get("ctype") or "")]
if ok:
    u0 = ok[0][0]
    r = s.get(u0, timeout=30)
    open(f"{TMP}/lidl_v4_flyer_sample.json", "w", encoding="utf-8").write(r.text)
    print("\nSaved sample:", u0, "->", f"{TMP}/lidl_v4_flyer_sample.json")

with open(f"{TMP}/lidl_v4_probes.json", "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
