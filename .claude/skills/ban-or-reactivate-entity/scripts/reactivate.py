"""Reativa cliente / estafeta / parceiro. Dry-run por defeito; --commit aplica.

driver: limpa colunas de ban. partner: is_active_admin=true. client: Auth ban_duration='none'.
Idempotente.

Uso:
  python reactivate.py --type driver --id <uuid> --reason "Resolvido" --commit
  python reactivate.py --type partner --id <text-id> --reason "..." --commit
  python reactivate.py --type client --id <uuid> --reason "..." --commit
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log, audit_log, admin_identity, ENTITY_MAP


def _auth_unban(ctx: Ctx, user_id: str) -> bool:
    r = requests.put(
        f"{ctx.supabase_url}/auth/v1/admin/users/{user_id}", timeout=30,
        headers={"Authorization": f"Bearer {ctx.service_role_key}",
                 "apikey": ctx.service_role_key, "Content-Type": "application/json"},
        json={"ban_duration": "none"})
    if r.status_code >= 300:
        log(f"Auth unban falhou: {r.status_code} {r.text[:160]}", "ERROR")
    return r.status_code < 300


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=["client", "driver", "partner"])
    ap.add_argument("--id", required=True)
    ap.add_argument("--reason", required=True)
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    admin_id, _ = admin_identity()
    if args.commit and not admin_id:
        log("BORA_ADMIN_USER_ID em falta — necessário p/ auditoria.", "ERROR")
        return 1

    cfg = ENTITY_MAP[args.type]
    r = ctx.rest("GET", f"{cfg['table']}?{cfg['id_col']}=eq.{args.id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"{args.type} {args.id} não encontrado.", "ERROR")
        return 1
    ent = rows[0]

    if args.type == "driver" and not ent.get("is_banned"):
        log("Estafeta não está banido. Nada a fazer (idempotente).")
        return 0
    if args.type == "partner" and ent.get("is_active_admin") is not False:
        log("Parceiro já ativo. Nada a fazer (idempotente).")
        return 0

    if not args.commit:
        log(f"[DRY-RUN] REACTIVATE {args.type} {args.id} — motivo: {args.reason}")
        log("Use --commit para aplicar.")
        return 0

    if args.type == "driver":
        patch = {"is_banned": False, "banned_at": None, "banned_until": None,
                 "ban_reason_code": None, "ban_reason": None}
        resp = ctx.rest("PATCH", f"drivers?id=eq.{args.id}", ctx.service_role_key, patch)
        if resp.status_code >= 300:
            log(f"UPDATE drivers falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
            return 1
    elif args.type == "partner":
        resp = ctx.rest("PATCH", f"restaurants?id=eq.{args.id}", ctx.service_role_key,
                        {"is_active_admin": True})
        if resp.status_code >= 300:
            log(f"UPDATE restaurants falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
            return 1
    else:  # client
        if not _auth_unban(ctx, args.id):
            return 1

    audit_log(ctx, "entity_reactivated", args.type, args.id,
              {"reason": args.reason}, text_id=cfg["text_id"])
    log(f"✅ {args.type} {args.id} reativado. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
