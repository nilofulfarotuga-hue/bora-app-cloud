"""Histórico de bans (atual + passado) de uma entidade.

- Estado atual: driver (colunas ban), partner (is_active_admin), client (Auth banned_until).
- Histórico: linhas em admin_audit_log (action entity_banned/entity_reactivated/driver_force_logout).

Uso: python history.py --type driver --id <uuid>
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log, ENTITY_MAP


def _auth_status(ctx: Ctx, user_id: str):
    r = requests.get(f"{ctx.supabase_url}/auth/v1/admin/users/{user_id}", timeout=30,
                     headers={"Authorization": f"Bearer {ctx.service_role_key}",
                              "apikey": ctx.service_role_key})
    if r.status_code >= 300:
        return None
    u = r.json()
    return u.get("banned_until")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=["client", "driver", "partner"])
    ap.add_argument("--id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    cfg = ENTITY_MAP[args.type]

    # Estado atual
    if args.type == "client":
        bu = _auth_status(ctx, args.id)
        log(f"Estado (Auth): banned_until = {bu or 'não banido'}")
    else:
        r = ctx.rest("GET", f"{cfg['table']}?{cfg['id_col']}=eq.{args.id}&select=*", ctx.service_role_key)
        rows = r.json() if r.status_code < 300 else []
        if not rows:
            log(f"{args.type} {args.id} não encontrado.", "ERROR")
            return 1
        e = rows[0]
        if args.type == "driver":
            log(f"Estado: is_banned={e.get('is_banned')} · until={e.get('banned_until')} · "
                f"code={e.get('ban_reason_code')} · reason={e.get('ban_reason')}")
        else:
            log(f"Estado: is_active_admin={e.get('is_active_admin')} (false = desativado/banido)")

    # Histórico de auditoria
    id_col = "entity_id_text" if cfg["text_id"] else "entity_id"
    q = (f"admin_audit_log?{id_col}=eq.{args.id}"
         f"&action=in.(entity_banned,entity_reactivated,driver_force_logout)"
         f"&select=action,admin_email,created_at,details&order=created_at.desc")
    r = ctx.rest("GET", q, ctx.service_role_key)
    hist = r.json() if r.status_code < 300 else []
    if not hist:
        log("Sem histórico de moderação em admin_audit_log.")
    else:
        log(f"{len(hist)} evento(s) de moderação:")
        for h in hist:
            log(f"  - {h['created_at']} | {h['action']} | por {h.get('admin_email','?')} | {h.get('details')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
