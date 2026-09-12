"""Cria (ou desativa) um promo code via RPC admin. Dry-run default; --commit chama RPC.

Uso:
  python create_promo.py --code BORA10 --type pct --value 10 --max-uses 100 --expires 2026-12-31
  python create_promo.py --code BORA10 --type pct --value 10 --expires 2026-12-31 --commit
  python create_promo.py --code BORA10 --deactivate --reason "fim campanha" --commit
"""
from __future__ import annotations

import argparse
import sys

from _shared import Ctx, log, get_admin_jwt, rpc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--code", required=True)
    ap.add_argument("--type", choices=["pct", "fixed"])
    ap.add_argument("--value", type=float, help="pct: %; fixed: euros")
    ap.add_argument("--max-uses", type=int)
    ap.add_argument("--max-uses-per-user", type=int, default=1)
    ap.add_argument("--min-order", type=float, default=0, help="euros")
    ap.add_argument("--expires", help="YYYY-MM-DD ou ISO")
    ap.add_argument("--deactivate", action="store_true")
    ap.add_argument("--reason", default="")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    if args.deactivate:
        log(f"Desativar promo '{args.code}' — motivo: {args.reason or '(nenhum)'}")
        if not args.commit:
            log("[DRY-RUN] use --commit para desativar via admin_deactivate_promo_code.")
            return 0
        r = rpc(ctx, "admin_deactivate_promo_code",
                {"p_code": args.code, "p_reason": args.reason}, get_admin_jwt(ctx))
        log(f"admin_deactivate_promo_code → {r.status_code}: {r.text[:160]}")
        return 0 if r.status_code < 300 else 1

    if not (args.type and args.value is not None):
        log("Criação exige --type e --value (ou usa --deactivate).", "ERROR")
        return 2
    payload = {
        "p_code": args.code, "p_type": args.type,
        "p_value_pct": args.value if args.type == "pct" else None,
        "p_value_cents": int(round(args.value * 100)) if args.type == "fixed" else None,
        "p_max_uses": args.max_uses, "p_max_uses_per_user": args.max_uses_per_user,
        "p_min_order_cents": int(round(args.min_order * 100)),
        "p_valid_until": args.expires,
    }
    log(f"Promo '{args.code}': {args.type} {args.value}{'%' if args.type=='pct' else '€'} "
        f"· max_uses {args.max_uses} · min €{args.min_order:.2f} · até {args.expires}")
    if args.type == "pct" and args.value >= 20 and args.min_order == 0:
        log("⚠️ Desconto pct alto sem min_order → impacto na margem Bora. Confirmar.", "WARN")
    if not args.commit:
        log(f"[DRY-RUN] payload RPC: {payload}. Use --commit para criar.")
        return 0
    r = rpc(ctx, "admin_create_promo_code", payload, get_admin_jwt(ctx))
    log(f"admin_create_promo_code → {r.status_code}: {r.text[:200]}")
    return 0 if r.status_code < 300 else 1


if __name__ == "__main__":
    sys.exit(main())
