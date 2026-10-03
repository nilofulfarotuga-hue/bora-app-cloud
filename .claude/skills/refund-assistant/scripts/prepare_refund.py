"""Prepara PROPOSTA de refund (SHADOW). NUNCA executa refund.

Lê pedido + settings → fee por escalão → refund elegível → split 80/20 →
_preview/refund_<id>.md + admin_audit_log 'refund_proposed'.

Uso: python prepare_refund.py --order-id <id>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from _shared import Ctx, log, audit_log, get_settings, REPO_ROOT

BEFORE = {"created", "preparing", "callingDriver"}
AFTER = {"driverAccepted", "pickedUp"}
ENROUTE = {"onTheWay", "delivered"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--order-id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    r = ctx.rest("GET", f"orders?id=eq.{args.order_id}"
                        f"&select=id,status,payment_method,payment_status,total,customer_total,"
                        f"cancel_fee,refund_amount,refund_status,user_id", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"Pedido {args.order_id} não encontrado.", "ERROR")
        return 1
    o = rows[0]
    paid = float(o.get("customer_total") or o.get("total") or 0)
    status = o.get("status")

    s = get_settings(ctx, ["cancel_fee_before_dispatch_cents", "cancel_fee_after_accept_cents",
                           "cancel_fee_after_pickup_ratio", "wallet_split_free_pct"])
    before_fee = float(s.get("cancel_fee_before_dispatch_cents", 100)) / 100
    after_fee = float(s.get("cancel_fee_after_accept_cents", 250)) / 100
    pickup_ratio = float(s.get("cancel_fee_after_pickup_ratio", 1))
    free_pct = float(s.get("wallet_split_free_pct", 0.80))

    if status in BEFORE:
        fee, tier = before_fee, "antes de dispatch"
    elif status in AFTER:
        fee, tier = after_fee, "após aceite/pickup"
    elif status in ENROUTE:
        fee, tier = paid * pickup_ratio, "em rota/entregue (ratio %.0f%%)" % (pickup_ratio * 100)
    else:
        fee, tier = after_fee, f"estado '{status}' (assumido após aceite)"

    eligible = max(0.0, round(paid - fee, 2))
    wallet_free = round(eligible * free_pct, 2)
    tokens_part = round(eligible - wallet_free, 2)

    lines = [f"# PROPOSTA de Refund — pedido {o['id']}", "",
             "> ⚠️ SHADOW: proposta para aprovação humana. NADA foi executado.", "",
             f"- estado: **{status}** ({tier})",
             f"- pagamento: {o.get('payment_method')} / {o.get('payment_status')}",
             f"- total pago: €{paid:.2f}",
             f"- fee de cancelamento: €{fee:.2f}",
             f"- **refund elegível: €{eligible:.2f}**",
             f"  - saldo livre ({free_pct*100:.0f}%): €{wallet_free:.2f}",
             f"  - tokens (~{(1-free_pct)*100:.0f}%, expira 60d): €{tokens_part:.2f}",
             f"- refund_amount atual no pedido: {o.get('refund_amount')} · refund_status: {o.get('refund_status')}",
             "", "## Para executar (humano)",
             "Rever e processar via painel admin / Edge Fn `refund` (NÃO automático).",
             "Regra 5B: refund pós-compra escala sempre a humano."]
    out = REPO_ROOT / ".claude" / "skills" / "refund-assistant" / "_preview"
    out.mkdir(exist_ok=True)
    dest = out / f"refund_{o['id']}.md"
    dest.write_text("\n".join(lines), encoding="utf-8")
    log(f"Proposta: {dest}")
    log(f"Refund elegível €{eligible:.2f} (livre €{wallet_free:.2f} + tokens €{tokens_part:.2f}) — {tier}")

    audit_log(ctx, "refund_proposed", "order", o["id"],
              {"paid": paid, "fee": fee, "eligible": eligible, "wallet_free": wallet_free,
               "tokens": tokens_part, "status": status, "executed": False})
    log("Auditado como 'refund_proposed'. NUNCA executado por esta skill.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
