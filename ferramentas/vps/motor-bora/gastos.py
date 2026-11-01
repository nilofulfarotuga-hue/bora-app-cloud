import json
import sys
robo = sys.argv[1] if len(sys.argv) > 1 else None
n = int(sys.argv[2]) if len(sys.argv) > 2 else 4
ls = [json.loads(l) for l in open("/opt/motor-bora/ia_gastos.jsonl", encoding="utf-8") if l.strip()]
if robo:
    ls = [g for g in ls if (g.get("robo") or "").startswith(robo)]
for g in ls[-n:]:
    print(g["quando"], g.get("robo"), g.get("perfil"), g.get("modelo"), "ent=%s cw=%s cr=%s sai=%s" % (g.get("tokens_entrada"), g.get("tokens_cache_escrita"), g.get("tokens_cache_leitura"), g.get("tokens_saida")), "usd=%s" % g.get("custo_usd"), "ok=%s" % g.get("ok"), (g.get("erro") or "")[:80])
