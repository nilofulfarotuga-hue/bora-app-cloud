# Bora App — Knowledge Index

> Entry point. CEO-AI lê este ficheiro **antes** de qualquer task significativa.
> Apenas referência — conteúdo vive nos sub-documentos e ficheiros canónicos.

## Fontes da verdade

| Fonte | Ficheiro | Quando consultar |
|---|---|---|
| **Regras de negócio** | `bora_app/.claude/.ai/business_rules.md` | Decisões de pricing, tokens, dispatch, refund, fees, cancelamento |
| **Schema declarativo** | `bora_app/supabase/schema.sql` | Estrutura canónica das tabelas core |
| **Migrations aplicadas** | `bora_app/supabase/migrations/*.sql` | Histórico cronológico de alterações DB |
| **Decisões arquitecturais** | `bora_app/.claude/.ai/decisions/` | Refactors planeados, drafts HIGH-RISK |
| **Relatórios sessão** | `bora_app/.claude/.ai/reports/` | Estado pós-sessão, audits, validações |
| **Skill CEO-AI** | `.claude/skills/ceo-ai/SKILL.md` | Identidade, prioridades, workflow |

## Convenções importantes

- **`restaurants.id`, `products.id`, `orders.id` são TEXT** (legado). Migrations cast quando precisam UUID. Refactor planeado em `decisions/2026-04-29-restaurants-id-uuid-refactor.md`.
- **`assigned_driver_id` é TEXT** intencional. NÃO tocar.
- **`admin_audit_log.entity_id` é UUID**. Para entidades TEXT (restaurants, products) usar `entity_id_text`.
- **Todos os RPCs admin usam `_admin_op_guard()`** + INSERT em `admin_audit_log`.
- **Storage `avatars`** path é `{userId}/avatar.jpg`. RLS em 4 policies.

## Sub-documentos relevantes (a serem criados conforme a app cresce)

- `business-rules/wallet.md` — §17 Wallet 80/20 + Cashback + Referral + Promos (2026-04-30)
- `from-obsidian/` — sync unidirecional do vault Obsidian (NÃO editar à mão).
- `sessions/` — notas por sessão de trabalho.

## Roadmap conhecido (ler decisions/ correspondentes)

- JWT vault cutover (`2026-04-29-jwt-vault-cutover.md`) — pos-aprovação Danilo
- restaurants.id UUID refactor (`2026-04-29-restaurants-id-uuid-refactor.md`) — pos-launch
- BR §6.7 dispatch+refund (`2026-04-29-dispatch-partner-open.md`) — depende BUG-MN-004
