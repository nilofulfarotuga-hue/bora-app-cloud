# 🔒 TRAVA BORA — Proteção Determinística (Hooks + permissions.deny)

> **Instalada:** 2026-07-01 (Fase 1) · **Tipo:** proteção física, não um pedido em texto.
> Um `deny` em `permissions` + hook com `exit 2` **bloqueia a ação de verdade** — não pode
> ser furado nem com `--dangerously-skip-permissions`. Nenhum agente (nem esta sessão)
> consegue editar código de dinheiro ou correr comando destrutivo.

## Por que existe

A trava **só ADICIONA proteção EM VOLTA** do código de dinheiro que já existe. **Não altera
uma única linha de lógica financeira.** É a fundação de segurança do sistema autónomo: mesmo
que um agente "decida" mexer no pricing, no Stripe ou apagar uma tabela, a ação é barrada
antes de acontecer.

## Duas camadas (defesa em profundidade)

1. **`permissions.deny` em `.claude/settings.json` — camada dura, nativa, inbypassável.**
   Não depende de bash/python. `deny` vence sempre `allow` e não pode ser sobreposto.
   Cobre: edição de ficheiros de dinheiro, edição da própria trava, e git destrutivo por prefixo.
2. **Hooks `PreToolUse` (`.claude/hooks/*.sh`) — camada de conteúdo + mensagem clara.**
   Fazem o que o `deny` nativo não consegue: inspecionar o **conteúdo do SQL** e do comando.
   Contrato: `exit 2` + mensagem no `stderr` ⇒ o Claude Code bloqueia a ferramenta.

## O que está protegido

### A) Ficheiros de código de dinheiro (hook `protege-dinheiro.sh` + `deny`)
Bloqueado `Edit`/`Write`/`MultiEdit` em:

| Ficheiro | Porquê |
|---|---|
| `lib/services/pricing_service.dart` | cálculo de todos os preços/taxas |
| `lib/stores/order_store.dart` | contém `finalizePurchase*` (finalização de compra) |
| `lib/widgets/errand_execution_sheet.dart` | `_finalizePurchase` (favores) |
| `supabase/functions/dispatch-engine/**` | motor de dispatch |
| `supabase/functions/stripe-webhook/**` | webhook Stripe (marca pago) |
| `supabase/functions/finalize-order-from-intent/**` | finalização server-side |
| `supabase/functions/create-payment-intent/**` | cobrança cartão |
| `supabase/functions/create-mbway-payment-intent/**` | cobrança MB WAY |
| `supabase/functions/refund/**` · `reprocess-refund/**` · `charge-extra/**` | reembolsos / cobrança extra |

> ⚠️ **Nota sobre `order_store.dart`:** o `finalizePurchase` vive dentro deste ficheiro grande e
> muito editado. A trava bloqueia o ficheiro **inteiro** (não dá para bloquear só um método por
> path). Se isto travar trabalho legítimo (realtime/dispatch/status também vivem lá), o Danilo
> pode remover só esta linha do `deny` e do `protege-dinheiro.sh` à mão. As garantias de dinheiro
> reais desses fluxos estão, de qualquer forma, no lado do servidor (ledger append-only,
> `enforce_financial_immutability`, RPCs protegidas na camada de banco abaixo).

### B) Auto-proteção — a trava protege a própria trava
Bloqueado `Edit`/`Write`/`MultiEdit` em `.claude/hooks/**`, `.claude/settings.json`,
`.claude/settings.local.json`. **Desativar a trava exige o Danilo editar à mão, fora do agente.**

### C) Banco de dados / SQL (hook `protege-banco.sh`)
Matcher: `Bash` + MCP Supabase (`mcp__*Supabase*` — `execute_sql`/`apply_migration`/`deploy_edge_function`).
As regras SQL só disparam em **contexto SQL** (MCP Supabase ou `psql`/`supabase db` no Bash),
para não bloquear mensagens de commit que contenham palavras como "drop". Bloqueia:

- **DDL** (`CREATE OR REPLACE` / `DROP` / `ALTER`) sobre **funções/triggers de dinheiro**:
  `enforce_financial_immutability`, `create_order`, `apply_order_financial_split`,
  `quote_order_pricing`, `pricing_calculate(_errand)`, `compute_refund_split`,
  `_enforce_refund_cap`, família `wallet_*`, `add_tokens`, `consume_tokens`, `mark_token_failed`,
  `*_award_tokens_on_delivery`, `driver_convert_tokens`, `client_redeem_promo_tokens`,
  `finalize_errand_purchase`, `finalize_storeshopping_purchase(_v2)`,
  `compute_*_settlement`/`payout`, `create_payout`, `auto_payout_pending`.
- **DROP / TRUNCATE** de tabelas financeiras: `orders`, `wallets`, `ledger(_entries)`,
  `bora_tokens`, `wallet_transactions`, `tvde_driver_balances`, `driver_balances`,
  `order_financials`, `order_financial_transactions`, `*_weekly_settlements`,
  `appointment_payouts`, `partner_reservation_payouts`, `pending_charges`.
- **`ALTER ... DISABLE ROW LEVEL SECURITY`** em qualquer tabela financeira.
- **deploy/redeploy** das edge functions protegidas (MCP `deploy_edge_function` ou
  `supabase functions deploy`).
- **`supabase db reset`** (destrói a base).

### D) Git destrutivo (hook `protege-banco.sh` + `deny`)
Bloqueado: `git push --force` / `git push -f` / `--force-with-lease`, `git reset --hard`.
**`git push` normal PASSA** (o workflow termina com push).

## O que NÃO é bloqueado (de propósito)
`SELECT`, migrations/DDL normais fora das zonas de dinheiro, `git push` normal,
`git reset --soft`, editar qualquer ecrã/feature não-financeiro. A trava é cirúrgica.

## Testes (2026-07-01) — todos ✅
`scratchpad/test_trava.sh` injeta JSON no stdin dos hooks (igual ao Claude Code):
editar ficheiro protegido → bloqueado; editar README → passa; editar a própria trava →
bloqueado; `CREATE OR REPLACE pricing_calculate` → bloqueado; `SELECT orders` → passa;
`DROP TABLE ledger_entries` → bloqueado; `git push --force` → bloqueado; `git push` normal
→ passa; commit com "drop orders" na mensagem → passa (sem falso positivo); deploy
`stripe-webhook` → bloqueado.

## Como desativar (só o Danilo, à mão)
1. Abrir `.claude/settings.json` num editor de texto (fora do Claude Code).
2. Remover a(s) entrada(s) de `permissions.deny` e/ou o bloco `hooks`.
3. (Opcional) apagar/renomear `.claude/hooks/protege-*.sh`.
O agente **não consegue** fazer isto por si — é essa a intenção.

## Notas de plataforma (Windows)
- Os hooks correm via `bash .claude/hooks/*.sh` (Git Bash na PATH) com `cwd` = raiz do projeto.
- Usam `python` só para ler o JSON do stdin (mesmo padrão do hook já existente
  `auto-rules-sync-notify.sh`). Fail-safe: se o parse falhar, varrem o payload cru.
- Se algum dia os hooks não dispararem (bash fora da PATH), a camada `permissions.deny` nativa
  continua a proteger ficheiros e git destrutivo — a garantia mínima nunca cai.

---
*Fase 1 de A TRAVA. Fica pronto para virar parte do "Cérebro" na Fase 2.*
