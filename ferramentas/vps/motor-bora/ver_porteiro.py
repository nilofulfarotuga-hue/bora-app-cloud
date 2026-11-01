import json
import sys
import urllib.request

url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8792/porteiro"
hdr = {}
if len(sys.argv) > 2:
    hdr["X-Porteiro-Token"] = open(sys.argv[2]).read().strip().split("=", 1)[1]
try:
    with urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=8) as r:
        d = json.load(r)
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read()[:200])
    raise SystemExit(0)
c = d.get("contas") or {}
print(json.dumps({"ligado": d.get("ligado"), "racao": d.get("racao"), "regra": d.get("regra"), "tem_chave": d.get("tem_chave"),
                  "dormido_ate": d.get("dormido_ate"), "pausa_ate": d.get("pausa_ate"), "pausa_motivo": d.get("pausa_motivo"),
                  "simular": d.get("simular"),
                  "resta_usd_estimado": c.get("resta_usd"), "gasto_hoje_usd": c.get("gasto_hoje_usd"), "proximo_credito": c.get("proximo_credito"),
                  "decisoes": d.get("decisoes")}, ensure_ascii=False, indent=1))
