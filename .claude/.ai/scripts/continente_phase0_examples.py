"""Lê o JSON da amostra e imprime as maiores divergências base(PVPR/venda) vs BD(glovo/1.15)."""
import json, os
BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
data = json.load(open(os.path.join(BASE, "tmp", "phase0_sample150.json"), encoding="utf-8"))
rows = [r for r in data["results"] if r.get("base") and r.get("bd")]
for r in rows:
    r["div"] = (r["base"] - r["bd"]) / r["bd"]
rows.sort(key=lambda r: abs(r["div"]), reverse=True)
print("TOP 14 DIVERGENCIAS (base correta vs BD atual glovo/1.15):")
print(f"{'div%':>7} {'BD':>7} {'base':>7} {'promo':>5}  nome")
for r in rows[:14]:
    print(f"{r['div']*100:>6.0f}% {r['bd']:>7.2f} {r['base']:>7.2f} {str(r['had_promo']):>5}  {(r['name'] or '')[:46]}")
print(f"\nTotal com preco: {len(rows)} | promo c/ base>bd: "
      f"{sum(1 for r in rows if r['had_promo'] and r['base']>r['bd'])} | "
      f"sem promo c/ base!=bd >5%: {sum(1 for r in rows if not r['had_promo'] and abs(r['div'])>0.05)}")
