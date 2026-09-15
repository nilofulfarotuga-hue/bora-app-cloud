"""Forensics read-only do ledger_entries. Só deteta e reporta.

Uso:
  python audit.py
  python audit.py --days 30
  python audit.py --json
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import defaultdict
from pathlib import Path

from _shared import Ctx, log, REPO_ROOT, rest_paginate


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=0, help="0 = todo o histórico")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    path = "ledger_entries?select=id,user_id,user_type,type,amount,order_id,created_at&order=created_at.asc"
    if args.days:
        since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)).isoformat()
        path += f"&created_at=gte.{since}"
    rows = rest_paginate(ctx, path)
    log(f"ledger_entries analisadas: {len(rows)}")

    findings = defaultdict(list)
    seen = set()
    by_order = defaultdict(set)
    for r in rows:
        amt = float(r.get("amount") or 0)
        t, ut, oid, rid = r.get("type"), r.get("user_type"), r.get("order_id"), r.get("id")
        # órfãs (cash_adjustment pode ser legítimo sem order)
        if not oid and t != "cash_adjustment":
            findings["orfas"].append(f"{rid} ({t}/{ut} €{amt:.2f})")
        # duplicados
        k = (r.get("user_id"), oid, t, round(amt, 2))
        if k in seen:
            findings["duplicados"].append(f"{rid} {k}")
        seen.add(k)
        # sinais inesperados
        if t == "earning" and amt < 0:
            findings["earning_negativo"].append(f"{rid} €{amt:.2f}")
        if t == "commission" and amt > 0:
            findings["commission_positiva"].append(f"{rid} €{amt:.2f}")
        if t == "payout" and amt > 0:
            findings["payout_positivo"].append(f"{rid} €{amt:.2f}")
        if amt == 0 and t in ("earning", "commission", "payout"):
            findings["amount_zero"].append(f"{rid} ({t})")
        if oid:
            by_order[oid].add(ut)
    # pedidos sem driver nem platform
    for oid, uts in by_order.items():
        if "driver" not in uts and "platform" not in uts:
            findings["pedido_incompleto"].append(f"{oid} (user_types={sorted(uts)})")

    crit = sum(len(findings[k]) for k in ("orfas", "duplicados", "earning_negativo",
                                          "commission_positiva", "payout_positivo"))
    if args.json:
        print(json.dumps({k: v for k, v in findings.items()}, ensure_ascii=False, indent=2))
    else:
        log("=== Auditoria ledger_entries ===")
        labels = {"orfas": "Órfãs (sem order)", "duplicados": "Duplicados",
                  "earning_negativo": "Earning negativo", "commission_positiva": "Commission positiva",
                  "payout_positivo": "Payout positivo", "amount_zero": "Amount zero",
                  "pedido_incompleto": "Pedido sem driver/platform"}
        for k, lab in labels.items():
            v = findings.get(k, [])
            mark = "[X]" if (k in ("orfas", "duplicados", "earning_negativo",
                                   "commission_positiva", "payout_positivo") and v) else ("[!]" if v else "[OK]")
            log(f"{mark} {lab}: {len(v)}" + (f" — ex.: {v[:5]}" if v else ""))
        log(f"Resultado: {'[X] ' + str(crit) + ' achado(s) crítico(s)' if crit else '[OK] sem achados críticos'}")

    out = REPO_ROOT / ".claude" / "skills" / "audit-ledger-entries" / "_preview"
    out.mkdir(exist_ok=True)
    (out / "ledger_audit.md").write_text(
        "# Auditoria ledger_entries\n\n" + "\n".join(
            f"- **{k}**: {len(v)}" + (f" — {v[:10]}" if v else "") for k, v in findings.items())
        + f"\n\n**Críticos:** {crit}\n", encoding="utf-8")
    return 1 if crit else 0


if __name__ == "__main__":
    sys.exit(main())
