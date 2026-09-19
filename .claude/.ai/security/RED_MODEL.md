---
id: red-model
title: Lista Vermelha Autoritativa (Zonas $)
zona: vermelha
tipo: security
atualizado: 2026-08-09
fontes: cortex-mcp/server.mjs:22, hooks/protege-banco.sh:50-52, hooks/protege-dinheiro.sh:41-56, .claude/settings.json deny, .claude/juiz/zonas_diff.py
---

# Lista Vermelha Autoritativa (RED_MODEL)

> **Source-of-truth único** das zonas vermelhas (`$`) do Bora/Cortex. Todos os guardiões (settings.deny, hooks `protege-dinheiro.sh`/`protege-banco.sh`, `cortex-mcp/server.mjs` RED/RED_ORDER, juiz `zonas_diff.py`, e o futuro Model Router) **devem espelhar** esta lista. Se mudares aqui, sincroniza os mirrors (F1 introduz a consolidação; drift = bug).

A Trava tem **duas camadas**:
1. **Camada dura (inbypassável):** `permissions.deny` em `.claude/settings.json` (+ réplica no user home `~/.claude/settings.json`). Bloqueia antes de qualquer hook.
2. **Camada de mensagem + defesa em profundidade:** hooks `protege-dinheiro.sh` (Edit/Write/MultiEdit) e `protege-banco.sh` (Bash/MCP Supabase). `exit 2` + stderr.

As regras SQL do `protege-banco.sh` só disparam em **contexto SQL** (MCP Supabase `execute_sql`/`apply_migration` ou psql/`pg_dump`), para não bloquear commits que mencionem "drop".

---

## 1. Palavras-chave vermelhas (conteúdo de propostas/ordens)

### `RED` — escrita direta recusada no cortex-mcp (`server.mjs:22`)
Usado por `t_escrever` e `t_propor` para recusar conteúdo `$` sem aprovação.
```
dispatch | pricing | finalizepurchase | bora_tokens | stripe | \brls\b | wallet | ledger | refund | comiss | markup | service_fee
```

### `RED_ORDER` — palavras-chave que tornam uma ordem vermelha (`server.mjs:22`)
Usado por `t_nova_ordem`; **ordem vermelha NUNCA entra no loop** — vai para a fila de aprovação do admin (como `cortex_propor`). Override manual só escala para vermelha, nunca desce.
```
dispatch_engine | dispatch | pricing | finalizepurchase | bora_tokens | stripe | payment | webhook | wallet | ledger | refund | payout | comiss | commission | markup | service_fee | platform_settings | \brls\b | force.?push
```

> **Princípio:** match por palavra-chave → zona vermelha → proposta (não execução). Um agente worker que tente despachar algo `$` é recusado na porta de entrada do cortex-mcp e mandado propor.

---

## 2. Ficheiros de código de DINHEIRO (negados a Edit/Write/MultiEdit)

Deny em `.claude/settings.json` + regex em `protege-dinheiro.sh:41-56`. Caminhos normalizados (backslash→`/`, prefixo `(^|/)`).

### Ficheiros Dart
| Caminho | Razão |
|---|---|
| `lib/services/pricing_service.dart` | cálculo de preços |
| `lib/stores/order_store.dart` | `finalizePurchase` |
| `lib/widgets/errand_execution_sheet.dart` | `_finalizePurchase` |

### Edge Functions protegidas (diretório `supabase/functions/<slug>/`)
```
dispatch-engine  | stripe-webhook  | finalize-order-from-intent
create-payment-intent  | create-mbway-payment-intent
refund  | reprocess-refund  | charge-extra
```

### Auto-proteção da Trava
```
.claude/hooks/**           (a própria trava)
.claude/settings.json      (config da trava)
.claude/settings.local.json (config da trava)
```

> **Fase 1 acrescenta** (multiagente — workers não se automodifiquem):
> `agents/critic.md`, `agents/consensus.md`, `.ai/cortex-mcp/router.mjs`

---

## 3. Funções SQL de dinheiro (protegidas de DDL)

`protege-banco.sh:50` `MONEYFN` — `CREATE OR REPLACE`/`DROP`/`ALTER` recusado em contexto SQL:
```
enforce_financial_immutability
create_order | apply_order_financial_split
quote_order_pricing | pricing_calculate | pricing_calculate_errand
compute_refund_split | _enforce_refund_cap
wallet_credit_refund_split | wallet_credit_refund_full
wallet_debit_for_order | wallet_debit_cancel_fee
wallet_credit_generic | wallet_apply_post_delivery_adjustment
add_tokens | consume_tokens | mark_token_failed
fn_award_tokens_on_delivery | trg_award_tokens_on_delivery
driver_convert_tokens | client_redeem_promo_tokens
finalize_errand_purchase
finalize_storeshopping_purchase | finalize_storeshopping_purchase_v2
compute_partner_weekly_settlement | compute_driver_settlement
compute_provider_weekly_payout | create_payout | auto_payout_pending
```

---

## 4. Tabelas financeiras (protegidas de DROP/TRUNCATE/DISABLE RLS)

`protege-banco.sh:51` `FINTABLE`:
```
orders | wallets | ledger | ledger_entries | bora_tokens
wallet_transactions | tvde_driver_balances | driver_balances
order_financials | order_financial_transactions
driver_weekly_settlements | partner_weekly_settlements
appointment_payouts | partner_reservation_payouts | pending_charges
```

### Edge functions protegidas de redeploy (`protege-banco.sh:52` `PROTSLUG`)
```
stripe-webhook | dispatch-engine | finalize-order-from-intent
create-payment-intent | create-mbway-payment-intent
reprocess-refund | charge-extra | (^|[^-])refund
```

---

## 5. Operações destrutivas SEMPRE bloqueadas

| Comando | Onde | Razão |
|---|---|---|
| `git push --force:*` / `git push -f:*` / `--force-with-lease:*` | settings.deny + protege-banco.sh | reescreve histórico |
| `git reset --hard:*` | settings.deny + protege-banco.sh | descarta trabalho |
| `supabase db reset:*` | settings.deny + protege-banco.sh | destrói a base |
| `DISABLE ROW LEVEL SECURITY` sobre tabela $ | protege-banco.sh (ctx SQL) | abre dados $ |

**Deixa passar:** SELECT, migrations normais, `git push` normal, `git reset --soft`, deploy de edge function não protegida.

---

## 6. Tabelas do Cortex (protegidas à priori — nascem em F2-F7)

> Quando criadas, **não** devem ser DROPadas/TRUNCATE/DISABLE RLS por um agente. `F1.4` estende `protege-banco.sh` `FINTABLE` com estas (harmless até existirem — só não vão bater em nada). Marcadas para que o hook as candy assim que existam.

| Tabela | Fase | Proteção |
|---|---|---|
| `cortex_tasks` | F2 | DROP/TRUNCATE/DISABLE RLS |
| `llm_call_log` | F3 | DROP/TRUNCATE |
| `cortex_task_messages` | F4 | DROP/TRUNCATE/DISABLE RLS |
| `cortex_task_consensus_meta` | F5 | DROP/TRUNCATE |
| `worktree_registry` | F6 | DROP/TRUNCATE |
| `agent_events` | F7 | DROP/TRUNCATE/DISABLE RLS |

> **RLS destas tabelas Cortex:** service_role full + admin via `is_admin()`. Nunca `anon`/`authenticated` leitura direta — só via RPC `SECURITY DEFINER` (padrão já seguido por `robot_*`/`autonomy_*`/`cortex_red_proposals`).

---

## 7. Sincronização dos mirrors (fluxo de manutenção)

Quando esta lista mudar, propagar para:

1. `bora_app/.claude/settings.json` → `permissions.deny` (camada dura).
2. `~/.claude/settings.json` → `permissions.deny` (réplica user home).
3. `bora_app/.claude/hooks/protege-dinheiro.sh` → regex paths (`has '...' && deny`).
4. `bora_app/.claude/hooks/protege-banco.sh` → `MONEYFN`/`FINTABLE`/`PROTSLUG`.
5. `bora_app/.claude/.ai/cortex-mcp/server.mjs` → `RED`/`RED_ORDER` (`:22`).
6. `bora_app/.claude/juiz/zonas_diff.py` → ler esta página em vez de regex hardcoded (consolidação F1).
7. Futuro `router.mjs` (F3) → nada autoexecuta se zona vermelha.

> **Teste de drift (a adicionar ao `skills-doctor`):** comparar estas listas contra os mirrors; falhar se divergirem.

---

*Esta lista é a verdade das verdades $ do sistema. Bug aqui = fuga de dinheiro ou destruição de BD.*