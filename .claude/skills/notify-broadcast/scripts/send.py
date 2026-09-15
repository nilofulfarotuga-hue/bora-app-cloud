"""Envia um broadcast: INSERT push_broadcasts + chama execute-broadcast.

Dry-run por defeito. --commit EXIGE --confirm. Audita.

Uso:
  python send.py --segment clients --title "..." --body "..."                     # dry-run
  python send.py --segment clients --title "..." --body "..." --commit --confirm
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log, audit_log
import preview_audience

SEGMENTS = ["all", "clients", "drivers", "partners"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--segment", required=True, choices=SEGMENTS)
    ap.add_argument("--title", required=True)
    ap.add_argument("--body", required=True)
    ap.add_argument("--commit", action="store_true")
    ap.add_argument("--confirm", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    n = preview_audience.audience(ctx, args.segment)
    log(f"Segmento '{args.segment}': {n} destinatário(s).")
    log(f"Título: {args.title}")
    log(f"Corpo : {args.body}")

    if not args.commit:
        log("[DRY-RUN] nada inserido/enviado. Use --commit --confirm para enviar.")
        return 0
    if not args.confirm:
        log("--commit exige TAMBÉM --confirm (push em massa é irreversível).", "ERROR")
        return 1

    ins = ctx.rest("POST", "push_broadcasts", ctx.service_role_key,
                   [{"segment": args.segment, "title": args.title, "body": args.body, "status": "pending"}])
    if ins.status_code >= 300:
        log(f"INSERT push_broadcasts falhou: {ins.status_code} {ins.text[:160]}", "ERROR")
        return 1
    bid = (ins.json() or [{}])[0].get("id")
    log(f"push_broadcasts criado: {bid}")

    r = requests.post(f"{ctx.supabase_url}/functions/v1/execute-broadcast", timeout=300,
                      headers={"Authorization": f"Bearer {ctx.service_role_key}",
                               "apikey": ctx.anon_key, "Content-Type": "application/json"},
                      json={"broadcast_id": bid})
    log(f"execute-broadcast → {r.status_code}: {r.text[:200]}")
    audit_log(ctx, "broadcast_sent", "push_broadcast", str(bid),
              {"segment": args.segment, "recipients": n, "title": args.title})
    log("✅ Broadcast despoletado. Auditado.")
    return 0 if r.status_code < 300 else 1


if __name__ == "__main__":
    sys.exit(main())
