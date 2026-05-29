---
name: add-support-skill
description: Cria um playbook (skill markdown) para o agente de suporte (tabela support_skills). Scaffold com frontmatter + validação de segurança — skills que tocam $/auth/Stripe/GDPR forçam mode=write_shadow + requires_human_handoff + active=false (nunca auto). Dry-run default.
metadata:
  type: support
  category: knowledge
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Add Support Skill

Cria um **playbook** para o agente de suporte (Gemini + function calling). Os playbooks
vivem em **`support_skills`** (`skill_name, version, category, mode, requires_human_handoff,
playbook_md, allowed_tools, examples, active`). 28 skills atuais; `shadow_mode` global = true.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/06-flows.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Modelo (confirmado via MCP)
- **mode** ∈ `{read_only, write_shadow, escalate}`.
- **categories** usadas: faq, orders, order_management, refunds, wallet, tokens, reservations,
  storeshopping, account_support, technical_support, app, escalation, Driver Support, …
- **allowed_tools**: JSON array (ex.: `["agent_get_order_status"]`).

## Uso
```bash
python scripts/scaffold_skill.py --name check_reservation --category reservations \
  --trigger "ver reserva|estado da reserva" --tool agent_get_reservation_status   # → _preview/<name>.md
python scripts/validate_skill.py --file _preview/check_reservation.md             # gate de segurança
python scripts/scaffold_skill.py --name check_reservation ... --commit            # INSERT support_skills (active=false)
```

## Modos
- **DEFAULT (scaffold)**: gera `_preview/<name>.md` (frontmatter + passos + bloco de escalada).
  NÃO escreve em `support_skills`.
- **`--commit`**: corre a validação; INSERT em `support_skills` com **`active=false`**
  (admin ativa depois) + `admin_audit_log`.

## 🔒 Regra de segurança (gate)
`validate_skill.py` marca **shadow obrigatório** se o playbook/allowed_tools tocar em
**$ / auth / Stripe / GDPR / refund / cancel / wallet / token** → força
`mode=write_shadow` + `requires_human_handoff=true` + `active=false` (**nunca auto**,
aprovação do Danilo). FAQ/UI/leitura → `read_only`/`escalate`, ainda assim `active=false` no insert.
Todo o playbook **tem de ter fallback humano** (bloco "Escalar quando").

## Salvaguardas
- Não reescreve a lógica do agente — só adiciona 1 playbook (`active=false`).
- `version=1` em novos; nome único (recusa se já existe um skill ativo com o nome).
- Dry-run default.
