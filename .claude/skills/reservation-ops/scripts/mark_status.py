"""Marca estado de uma reserva. Dry-run default; --commit chama a RPC.

arrived → partner_mark_arrival(p_reservation_id) (aplica €2 internamente).
no_show → não há RPC single; imprime orientação (cron auto_close / admin). Não executa.

Uso:
  python mark_status.py --reservation-id <uuid> --status arrived
  python mark_status.py --reservation-id <uuid> --status arrived --commit
"""
from __future__ import annotations

import argparse
import sys

from _shared import Ctx, log, get_admin_jwt, rpc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reservation-id", required=True)
    ap.add_argument("--status", required=True, choices=["arrived", "no_show"])
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    if args.status == "no_show":
        log("no_show: não existe RPC single dedicada.", "WARN")
        log("Mecanismo existente: cron `auto_close_no_show_reservations` (após grace) ou painel admin.")
        log("Esta skill NÃO fabrica no_show (evita reimplementar lógica de pré-pagamento).")
        return 0

    # arrived
    log(f"Reserva {args.reservation_id}: marcar CHEGADA via partner_mark_arrival "
        "(aplica €2 desconto internamente).")
    if not args.commit:
        log("[DRY-RUN] use --commit para chamar a RPC.")
        return 0
    r = rpc(ctx, "partner_mark_arrival", {"p_reservation_id": args.reservation_id}, get_admin_jwt(ctx))
    log(f"partner_mark_arrival → {r.status_code}: {r.text[:200]}")
    return 0 if r.status_code < 300 else 1


if __name__ == "__main__":
    sys.exit(main())
