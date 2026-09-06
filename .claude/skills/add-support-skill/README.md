# README — add-support-skill

Cria playbooks para o agente de suporte (`support_skills`). Gate de segurança shadow.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/scaffold_skill.py --name check_reservation --category reservations \
  --trigger "estado da reserva" --tool agent_get_reservation_status   # → _preview/check_reservation.md
python scripts/validate_skill.py --file _preview/check_reservation.md  # gate
python scripts/scaffold_skill.py --name check_reservation --category reservations \
  --trigger "estado da reserva" --tool agent_get_reservation_status --commit   # INSERT active=false
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` |
| `scaffold_skill.py` | gera playbook markdown (frontmatter + passos + escalada); `--commit` → support_skills |
| `validate_skill.py` | gate: fallback humano? toca $? → força write_shadow + requires_human_handoff |

## Regras
- mode ∈ {read_only, write_shadow, escalate}. Novo skill entra **`active=false`** (admin ativa).
- Toca $/auth/Stripe/GDPR/refund/cancel/wallet/token → **write_shadow + handoff obrigatório**.
- Todo playbook precisa de bloco "Escalar quando" (fallback humano).
- **Admin UI** (pendência): vista admin para Danilo editar/ativar skills — anotado, não criado.
