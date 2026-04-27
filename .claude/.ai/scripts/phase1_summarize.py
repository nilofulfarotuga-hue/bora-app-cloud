"""
Sumariza phase1_prices_2026-04-21.json sem dumpar tudo no context.
Imprime apenas agregados + amostras pequenas.
"""
import json, os, statistics, collections

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
INPUT = os.path.join(BASE, "tmp", "phase1_prices_2026-04-21.json")

with open(INPUT, "r", encoding="utf-8") as f:
    data = json.load(f)

results = data["results"]
total = data["total"]
processed = data["products_processed"]
stopped = data["stopped_reason"]

print(f"=== FASE 1 SUMMARY ===")
print(f"Total target:    {total}")
print(f"Processed:       {processed}")
print(f"Stopped reason:  {stopped}")
print()

# Status distribution
by_status = collections.Counter(r["status_label"] for r in results)
print("=== STATUS BREAKDOWN ===")
for st, cnt in by_status.most_common():
    pct = 100.0 * cnt / processed
    print(f"  {st:25s} {cnt:5d}  ({pct:5.1f}%)")
print()

# Price stats
prices = [float(r["price_eur"]) for r in results if r["price_eur"]]
print("=== PRICE STATS (only OK results) ===")
if prices:
    prices.sort()
    print(f"  count:   {len(prices)}")
    print(f"  min:     {min(prices):.2f} EUR")
    print(f"  max:     {max(prices):.2f} EUR")
    print(f"  mean:    {statistics.mean(prices):.2f} EUR")
    print(f"  median:  {statistics.median(prices):.2f} EUR")
    print(f"  p90:     {prices[int(len(prices)*0.9)]:.2f} EUR")
    print(f"  p99:     {prices[int(len(prices)*0.99)]:.2f} EUR")
print()

# Buckets
buckets = [(0, 1), (1, 2), (2, 5), (5, 10), (10, 20), (20, 50), (50, 100), (100, 999)]
print("=== PRICE BUCKETS ===")
for lo, hi in buckets:
    n = sum(1 for p in prices if lo <= p < hi)
    print(f"  {lo:>4}-{hi:<4} EUR: {n:5d}")
print()

# Top expensive (10)
print("=== TOP 10 MAIS CAROS ===")
top = sorted([r for r in results if r["price_eur"]], key=lambda r: float(r["price_eur"]), reverse=True)[:10]
for r in top:
    name = r["final_url"].rsplit("/", 1)[-1].replace(".html", "").replace("-", " ")[:80]
    print(f"  {float(r['price_eur']):8.2f} EUR  pid={r['pid']}  {name}")
print()

# Top cheap (10)
print("=== TOP 10 MAIS BARATOS ===")
bottom = sorted([r for r in results if r["price_eur"]], key=lambda r: float(r["price_eur"]))[:10]
for r in bottom:
    name = r["final_url"].rsplit("/", 1)[-1].replace(".html", "").replace("-", " ")[:80]
    print(f"  {float(r['price_eur']):8.2f} EUR  pid={r['pid']}  {name}")
print()

# Failures sample
fails = [r for r in results if not r["price_eur"]]
print(f"=== FAILURES SAMPLE (total {len(fails)}, primeiros 20) ===")
for r in fails[:20]:
    print(f"  pid={r['pid']} status={r['status_label']:18s} url={r['final_url'][:90]}")
print()

# Performance
elapsed = [r["elapsed_s"] for r in results]
print("=== TIMING ===")
print(f"  fetch médio:    {statistics.mean(elapsed):.2f} s")
print(f"  fetch p99:      {sorted(elapsed)[int(len(elapsed)*0.99)]:.2f} s")
print(f"  fetches > 5s:   {sum(1 for e in elapsed if e > 5)}")

# Save list of failed PIDs for SQL lookup
fails_pids = [r["pid"] for r in fails]
fails_path = os.path.join(BASE, "tmp", "phase1_failed_pids.txt")
with open(fails_path, "w", encoding="utf-8") as f:
    f.write("\n".join(fails_pids))
print(f"\n[saved] {len(fails_pids)} failed PIDs -> {fails_path}")
