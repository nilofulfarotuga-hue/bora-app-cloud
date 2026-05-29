"""Compara _preview/prices_before.csv vs prices_after.csv → relatório de diferenças.

Uso: python price_diff_report.py [--before f1.csv --after f2.csv]
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import log


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as f:
        return {r["product_id"]: r for r in csv.DictReader(f)}


def fnum(v):
    try:
        return float(str(v).replace(",", "."))
    except (TypeError, ValueError):
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", default="_preview/prices_before.csv")
    ap.add_argument("--after", default="_preview/prices_after.csv")
    args = ap.parse_args()
    before, after = load(Path(args.before)), load(Path(args.after))
    if not after:
        log("Sem prices_after.csv — corre run_continente_update.py primeiro.", "ERROR")
        return 1

    up = down = same = 0
    lines = ["# Diff de preços (Continente)", "", "| Produto | Antes | Depois | Δ |", "|---|---|---|---|"]
    for pid, a in after.items():
        old = fnum(before.get(pid, {}).get("price"))
        new = fnum(a.get("price"))
        if new is None:
            continue
        if old is None:
            lines.append(f"| {a.get('name','')[:40]} | — | {new:.2f} | novo |")
            continue
        d = round(new - old, 2)
        if d > 0:
            up += 1
        elif d < 0:
            down += 1
        else:
            same += 1
        if d != 0:
            lines.append(f"| {a.get('name','')[:40]} | {old:.2f} | {new:.2f} | {d:+.2f} |")
    lines += ["", f"Subiram: {up} · Desceram: {down} · Iguais: {same}"]
    out = Path("_preview"); out.mkdir(exist_ok=True)
    (out / "price_diff.md").write_text("\n".join(lines), encoding="utf-8")
    log(f"Subiram {up} · Desceram {down} · Iguais {same}. Relatório: _preview/price_diff.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
