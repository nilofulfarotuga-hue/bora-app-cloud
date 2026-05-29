"""Gera um playbook de suporte (markdown) e opcionalmente insere em support_skills.

Dry-run por defeito (escreve _preview/<name>.md). --commit insere (active=false).
Gate de segurança: toca $/auth/Stripe/GDPR → mode=write_shadow + requires_human_handoff.

Uso:
  python scaffold_skill.py --name check_reservation --category reservations \
    --trigger "estado da reserva" --tool agent_get_reservation_status
  python scaffold_skill.py ... --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from _shared import Ctx, log, audit_log, touches_sensitive, VALID_MODES


def build_playbook(name, category, trigger, tools, mode, handoff) -> str:
    fm = (f"---\nname: {name}\ntrigger: \"{trigger}\"\ncategory: {category}\n"
          f"mode: {mode}\nrequires_human_handoff: {str(handoff).lower()}\n"
          f"allowed_tools: {json.dumps(tools)}\n---\n")
    body = f"""# Playbook: {name}

## Quando usar
Quando a mensagem do utilizador corresponde a: **{trigger}**.

## Passos
1. Confirmar a intenção do utilizador (1 pergunta, se ambíguo).
2. Recolher dados via ferramentas permitidas: {', '.join(tools) or '(nenhuma — só resposta)'}.
3. Responder em **PT-PT**, claro e curto.
4. Se a ação alterar dados/dinheiro → **propor em shadow-mode** (admin aprova; nunca auto).

## Escalar quando
- Pedido de reembolso, cancelamento pós-compra, disputa, tema legal/GDPR.
- Qualquer dúvida sobre dinheiro, pagamento, carteira ou tokens.
- Utilizador insatisfeito ou caso fora deste âmbito.
→ Criar ticket humano (handoff) com `requires_human_handoff`.

## Notas
- Idioma: PT-PT. Tom: simpático e objetivo.
- Não prometer valores nem prazos que não controlamos.
"""
    return fm + body


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--category", default="faq")
    ap.add_argument("--trigger", required=True)
    ap.add_argument("--tool", action="append", default=[], help="repetível → allowed_tools")
    ap.add_argument("--mode", choices=VALID_MODES)
    ap.add_argument("--handoff", action="store_true", help="forçar requires_human_handoff")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    sensitive = touches_sensitive(" ".join([args.name, args.category, args.trigger] + args.tool))
    if sensitive:
        mode, handoff = "write_shadow", True
        log(f"🔒 Toca zona sensível {sensitive} → mode=write_shadow + handoff obrigatório.", "WARN")
    else:
        mode = args.mode or "read_only"
        handoff = args.handoff

    playbook = build_playbook(args.name, args.category, args.trigger, args.tool, mode, handoff)
    preview = Path("_preview"); preview.mkdir(exist_ok=True)
    dest = preview / f"{args.name}.md"
    dest.write_text(playbook, encoding="utf-8")
    log(f"Playbook gerado: {dest} (mode={mode}, handoff={handoff})")

    if not args.commit:
        log("Valida com validate_skill.py e usa --commit para inserir (active=false).")
        return 0

    # unicidade
    ex = ctx.rest("GET", f"support_skills?skill_name=eq.{args.name}&select=id,active", ctx.service_role_key)
    if ex.status_code < 300 and ex.json():
        log(f"Já existe support_skill '{args.name}'. Não duplico (idempotente).", "WARN")
        return 0

    row = {"skill_name": args.name, "version": 1, "category": args.category, "mode": mode,
           "requires_human_handoff": handoff, "playbook_md": playbook,
           "allowed_tools": args.tool, "examples": [], "active": False,
           "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
           "updated_at": dt.datetime.now(dt.timezone.utc).isoformat()}
    resp = ctx.rest("POST", "support_skills", ctx.service_role_key, [row])
    if resp.status_code >= 300:
        log(f"INSERT support_skills falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
        return 1
    audit_log(ctx, "support_skill_added", "support_skill", args.name,
              {"mode": mode, "handoff": handoff, "sensitive": sensitive, "active": False})
    log(f"✅ support_skill '{args.name}' inserido (active=false). Admin ativa após rever. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
