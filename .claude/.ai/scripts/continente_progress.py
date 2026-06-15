"""Resumo de progresso da corrida PVPR (le os shards continente_pvpr_s*.json)."""
import json, glob, os

TMP = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\tmp"
fs = sorted(glob.glob(os.path.join(TMP, "continente_pvpr_s*.json")))
tot = ok = promo = noprice = 0
rows = []
for f in fs:
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception:
        rows.append((os.path.basename(f), "?", "(a escrever)")); continue
    res = d.get("results", [])
    tot += len(res)
    for r in res:
        s = r.get("status", "")
        if s in ("ok_no_promo", "ok_promo"):
            ok += 1
            if s == "ok_promo":
                promo += 1
        else:
            noprice += 1
    rows.append((os.path.basename(f), len(res), d.get("total")))

print(f"Shards: {len(fs)}")
for n, p, t in rows:
    print(f"  {n}: {p}/{t}")
print(f"TOTAL: {tot}/11884 = {round(100*tot/11884, 1)}%")
print(f"  com preco: {ok} | em promo: {promo} | sem-preco: {noprice}")
rem = 11884 - tot
eta = round(rem / 2.05 / 60) if rem > 0 else 0   # ~2 produtos/s com 8 workers
print(f"Restantes: {rem} | ETA aprox: {eta} min")
