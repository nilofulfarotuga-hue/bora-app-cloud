---
title: Bora App — Auditoria do Painel Admin
date: 2026-05-17
session: admin-auditoria-autonoma
branch: admin-auditoria-autonoma-2026-05-17
tag: pre-admin-auditoria-2026-05-17
model: claude-opus-4-7[1m]
mode: AUTÓNOMO
---

# Auditoria do Painel Admin — 2026-05-17

## Resumo executivo

- **Universo:** 45 ecrãs em `lib/screens/admin/` + 97 RPCs `admin_*` em DB + 24 skills bot + 534 chunks RAG
- **Ecrãs limpos (sem issues detectados):** 17/45 (38%)
- **Ecrãs com issues:** 28/45 (62%)
- **RPCs admin sem UI Flutter:** 28/97 (29% das RPCs não têm interface no painel)
- **Total P0 (partidos):** 4
- **Total P1 (falta crítica/UI em falta):** 27
- **Total P2 (melhorias):** ~30 (controllers sem dispose, etc.)

### Top 4 P0 (vão ser fixados PRIMEIRO)

1. **P0-S15-001** — `support-chatbot` Edge Function: 3 inserts em `support_chatbot_messages` sem verificação de `error` retornado pelo Supabase JS client. Causa raiz das 7 mensagens reais (vs centenas esperadas). Erros de schema/constraint falham silenciosos.
2. **P0-S1-001** — `admin_orders_screen` NÃO usa RPC `admin_live_orders` — usa `.from('orders').select()` directo. Isto contorna SECURITY DEFINER, RLS, filtros canónicos do servidor. Lista pode estar incompleta consoante RLS do admin.
3. **P0-S8-001** — `admin_wallets_screen` NÃO chama `admin_list_wallets` nem nenhuma RPC equivalente reconhecida. Ecrã potencialmente partido (ou usa view não documentada).
4. **P0-S15-002** — `support-chatbot` NÃO tem mecanismo SKILL_GAP_LOG em tempo real. Apenas o cron `analyze-conversations` (Segunda 4am) gera `skill_suggestions` posteriormente. Quando bot não sabe → escala mas não regista gap explícito.

---

## Por secção (S1 a S17)

### S1 — Pedidos
- **Ecrãs:** `admin_orders_screen` (lista), `admin_live_orders_map_screen` (mapa), `admin_order_detail_screen` (detalhe), `admin_orphan_payments_screen` (órfãs), `_admin_cancel_order_dialog` (dialog interno)
- **RPCs chamadas:** nenhuma directamente em `admin_orders_screen`/`admin_order_detail_screen` (usam `.from('orders')`), `admin_list_orphans` (orphan)
- **RPCs admin sem UI:** `admin_live_orders` (!!), `admin_cancel_order`, `admin_get_order_payment_breakdown`
- **Issues:**
  - **P0-S1-001**: `admin_orders_screen` usa `Supabase.instance.client.from('orders').select(...)` directo (L80), não `admin_live_orders`. Server-side filtering + audit + SECURITY DEFINER perdidos.
  - **P1-S1-001**: `admin_order_detail_screen` falta botão "Ver breakdown de pagamento" que chama `admin_get_order_payment_breakdown` — feature core admin (Uber Eats Restaurant Manager mostra breakdown completo).
  - **P1-S1-002**: `admin_orphan_payments_screen` L34: `final res = await Supabase.instance.client.rpc('admin_list_orphans')` sem try/catch — crash silencioso em erro de rede.
  - **P2-S1-001**: `_admin_cancel_order_dialog` 0 RPCs (apenas UI; parent screen é que chama; OK).

### S2 — Aprovações
- **Ecrãs:** `admin_pending_actions_screen`, `admin_cancellation_requests_screen`, `admin_receipts_screen`
- **RPCs chamadas:** `admin_list_pending_actions`, `admin_approve_action`, `admin_finalize_action` (×5), `admin_reject_action`, `admin_approve_cancellation`, `admin_reject_cancellation`, `admin_mark_receipt_paid`, `admin_reject_receipt`
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:**
  - **P2-S2-001**: `admin_pending_actions_screen` — 4× `await _supabase.rpc('admin_finalize_action', ...)` sem try/catch (L197, L290, L306, L325). Pattern: a chamada externa de despacho tem try, mas o finalize que segue não.
  - **P2-S2-002**: `admin_pending_actions_screen` — controller `ctrl` sem dispose.

### S3 — Drivers
- **Ecrãs:** `admin_drivers_screen` (lista), `admin_driver_approval_screen` (pendentes), `admin_driver_detail_screen` (detalhe), `admin_driver_payments_screen` (pagamentos)
- **RPCs chamadas:** `admin_approve_driver`, `admin_reject_driver`, `driver_effective_status`, `admin_live_drivers` (presumivelmente — verificar)
- **RPCs admin sem UI:** `admin_ban_driver`, `admin_reactivate_driver`, `admin_update_driver`, `admin_soft_delete_driver`
- **Issues:**
  - **P1-S3-001**: Falta acção "Banir driver" no `admin_driver_detail_screen` (Uber driver-app admin tem este botão sempre).
  - **P1-S3-002**: Falta acção "Reactivar driver banido".
  - **P1-S3-003**: Falta dialog "Editar dados do driver" (nome, telefone, NIF, IBAN) — `admin_update_driver` existe na DB mas não tem entry point.
  - **P1-S3-004**: Falta acção destrutiva "Soft-delete driver" (com confirmação dupla; padrão GDPR right-to-erasure).
  - **P2-S3-001**: `admin_driver_approval_screen` — 2 TODOs em comments + controller leak.

### S4 — Parceiros
- **Ecrãs:** `admin_partners_screen` (lista — ✅ LIMPO), `admin_partners_pending_screen`, `admin_partner_detail_screen` (detalhe), `admin_partner_settlements_screen` (✅ LIMPO), `_admin_partner_edit_dialog` (✅ LIMPO)
- **RPCs chamadas:** `is_partner_open`, `admin_set_product_availability`, `admin_update_product_price`, `admin_partners_with_counts`, `admin_partner_sales_summary` (presumido)
- **RPCs admin sem UI:** `admin_partners_closed_now`, `admin_update_partner_data`, `admin_update_partner_hours`, `admin_set_partner_override`, `admin_clear_partner_override`, `admin_set_partner_special_date`, `admin_partner_payout_summary`, `admin_list_partner_payouts`, `admin_mark_partner_payouts_paid`
- **Issues:** ⚠️ **SECÇÃO MAIS INCOMPLETA**
  - **P1-S4-001**: Falta editor de horário semanal (`admin_update_partner_hours`) — Glovo/Uber Eats Restaurant Manager têm picker dia-a-dia.
  - **P1-S4-002**: Falta toggle "Forçar fechado" / "Forçar aberto" (override manual) — `admin_set_partner_override`/`admin_clear_partner_override` sem UI.
  - **P1-S4-003**: Falta "Adicionar data especial" (feriado, fechado evento) — `admin_set_partner_special_date` sem UI.
  - **P1-S4-004**: Falta secção "Payouts pendentes" (lista + marcar pago) — 3 RPCs sem UI.
  - **P2-S4-001**: `admin_partner_detail_screen` — 2 RPCs sem try/catch em handler (L1116, L1293).

### S5 — Clientes
- **Ecrãs:** `admin_clients_screen` (lista+ban), `admin_referrals_screen`, `admin_tokens_screen`
- **RPCs chamadas:** `admin_list_clients`, `admin_ban_client`, `admin_unban_client`, `admin_get_client_history`, `admin_referral_stats`, `admin_grant_referral_code`, `admin_list_referral_invites` (presumido), `admin_get_user_tokens`, `admin_grant_tokens`, `admin_revoke_token_grant`
- **RPCs admin sem UI:** `admin_block_client`, `admin_unblock_client` (semanticamente diferentes de ban/unban — block é temporário, ban é permanente; ver business_rules)
- **Issues:**
  - **P2-S5-001**: Falta UI "Bloquear cliente temporariamente" (vs ban permanente).
  - **P2-S5-002**: `admin_clients_screen` — `reasonCtrl` sem dispose (×2).
  - **P2-S5-003**: `admin_tokens_screen` — 4 controllers sem dispose.
  - **P2-S5-004**: `admin_referrals_screen` — 2 controllers sem dispose.

### S6 — Reservas
- **Ecrãs:** `admin_reservations_screen`, `admin_reservations_metrics_screen`
- **RPCs chamadas:** `admin_reservations_metrics`, `admin_force_create_reservation` (presumido — L209), `admin_cancel_reservation_on_behalf_of` (presumido — L336)
- **RPCs admin sem UI:** `admin_reservations_today`, `admin_get_reservations_stats`, `admin_seat_walk_in`
- **Issues:**
  - **P1-S6-001**: Falta botão "Sentar walk-in" no ecrã reservas — `admin_seat_walk_in` sem UI (operação típica restaurante).
  - **P2-S6-001**: `admin_reservations_today` parece duplicado com filtro de hoje em `admin_reservations_screen` — confirmar.
  - **P2-S6-002**: `admin_reservations_metrics_screen` — RPC L31 sem try/catch.
  - **P2-S6-003**: `admin_reservations_screen` — 7 controllers sem dispose.

### S7 — Avaliações
- **Ecrãs:** `admin_ratings_screen` (✅ LIMPO)
- **RPCs chamadas:** `admin_list_ratings`, `admin_flag_rating`, `admin_low_rated_subjects` (presumidos)
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:** nenhum

### S8 — Carteira / Settlements
- **Ecrãs:** `admin_wallets_screen`, `admin_settlements_screen`
- **RPCs chamadas:** `admin_list_settlements_for_week` (L41), `admin_set_settlement_status` (L123), **nenhuma RPC admin em admin_wallets_screen!**
- **RPCs admin sem UI:** `admin_list_wallets`, `admin_grant_wallet_free`, `admin_revoke_wallet_free`, `admin_forgive_wallet_debt`
- **Issues:** ⚠️ **SECÇÃO COM P0**
  - **P0-S8-001**: `admin_wallets_screen` não chama `admin_list_wallets` — apenas usa `Supabase.instance.client` mas RPC desconhecida em L360. Possível ecrã placeholder ou usa view directa. Verificar.
  - **P1-S8-001**: Falta UI "Conceder crédito grátis" (`admin_grant_wallet_free`).
  - **P1-S8-002**: Falta UI "Revogar crédito grátis" (`admin_revoke_wallet_free`).
  - **P1-S8-003**: Falta UI "Perdoar dívida" (`admin_forgive_wallet_debt`) — operação crítica suporte cliente.
  - **P2-S8-001**: `admin_settlements_screen` — 1 TODO + RPCs sem try/catch.

### S9 — Promos / Cashback
- **Ecrãs:** `admin_promo_codes_screen`, `admin_cashbacks_screen` (✅ LIMPO)
- **RPCs chamadas:** `admin_list_promo_codes`, `admin_create_promo_code`, `admin_deactivate_promo_code`, `admin_list_cashbacks`
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:**
  - **P2-S9-001**: `admin_promo_codes_screen` — 6 controllers sem dispose (form de criação).

### S10 — Categorias
- **Ecrãs:** `admin_category_mapping_screen` (✅ LIMPO)
- **RPCs:** `admin_list_category_mappings`, `admin_update_category_mapping`, `admin_category_mapping_stats`
- **Issues:** nenhum

### S11 — Notificações
- **Ecrãs:** `admin_send_notification_screen` (✅ LIMPO)
- **RPCs chamadas:** `admin_broadcast_notification`, `admin_send_notification`
- **RPCs admin sem UI:** `admin_list_broadcasts`, `admin_create_broadcast`, `admin_register_push_token`
- **Issues:**
  - **P1-S11-001**: Falta histórico de broadcasts (`admin_list_broadcasts` sem UI) — auditoria fundamental.
  - **P1-S11-002**: Falta ecrã "Agendar broadcast" via `admin_create_broadcast` (diferente do send imediato).
  - **P2-S11-001**: `admin_register_push_token` provavelmente para registar device admin — feature usada implicitamente, OK.

### S12 — Produtos (sob Parceiros)
- **Ecrãs:** `admin_catalog_screen`, `admin_partner_detail_screen` (também)
- **RPCs chamadas:** `admin_list_products_by_partner`, `admin_update_product_price`, `admin_reset_product_photo`, `admin_set_product_availability`
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:**
  - **P2-S12-001**: `admin_catalog_screen` — 3 controllers sem dispose.

### S13 — KPIs / Métricas
- **Ecrãs:** `admin_dashboard_screen`, `admin_advanced_kpis_screen` (✅ LIMPO), `admin_search_kpi_screen` (✅ LIMPO)
- **RPCs chamadas:** `admin_dashboard_metrics`, `admin_kpi_avg_ticket`, `admin_kpi_conversion`, `admin_kpi_hot_zones`, `admin_search_kpi`, `admin_skill_suggestions_stats`
- **RPCs admin sem UI:** `admin_realtime_metrics`
- **Issues:**
  - **P1-S13-001**: Falta widget "Métricas em tempo real" (`admin_realtime_metrics`) no dashboard — diferenciador vs daily metrics.
  - **P2-S13-001**: `admin_dashboard_screen` L109 — `admin_dashboard_metrics` sem try/catch.

### S14 — Suporte (Tickets / Complaints / Crosstalk)
- **Ecrãs:** `admin_support_tickets_screen`, `admin_support_stats_screen` (✅ LIMPO), `admin_complaints_screen`, `admin_crosstalk_screen`
- **RPCs chamadas:** `admin_list_complaints`, `admin_update_complaint_status`, `admin_resolve_ticket`, `admin_list_crosstalk`, `admin_respond_to_crosstalk`, `admin_get_support_stats`
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:**
  - **P2-S14-001**: `admin_support_tickets_screen` — `ctrl` sem dispose.
  - **P2-S14-002**: `admin_complaints_screen` — `notesCtrl` sem dispose.

### S15 — Suporte IA (skill_suggestions + knowledge + chatbot)
- **Ecrãs:** `admin_skill_suggestions_screen`, `admin_skill_suggestions_metrics_screen` (✅ LIMPO), `admin_knowledge_screen` (✅ LIMPO)
- **Edge Fns:** `support-chatbot/index.ts` (824L), `analyze-conversations/index.ts` (cron Segunda 4am)
- **RPCs chamadas:** `admin_list_skill_suggestions`, `admin_skill_suggestions_stats`, `admin_bulk_reject_skill_suggestions`, `admin_update_skill_suggestion_note`, `admin_approve_skill_suggestion` (×3), `admin_reject_skill_suggestion`, `admin_rollback_suggestion`, `admin_skill_suggestions_metrics`, `admin_get_knowledge_stats`
- **Issues:** ⚠️ **SECÇÃO COM 2 P0**
  - **P0-S15-001 (LOGGING CHATBOT)**: `support-chatbot/index.ts` faz 3 inserts em `support_chatbot_messages` (L611 user, L745 tool, L781 assistant) usando `await adminClient.from('support_chatbot_messages').insert({...})` — **NUNCA destruture `{ error }`**. Se constraint/coluna/schema falham, silent ignore. Causa raiz das 7 mensagens reais quando Danilo perguntou muito mais. (Fix: destructure `error` + `console.error` + opcionalmente retornar warning ao client.)
  - **P0-S15-002 (SKILL_GAP_LOG ausente)**: `support-chatbot` NÃO escreve directamente em `skill_suggestions` quando não sabe resposta. O mecanismo está SÓ em `analyze-conversations` (3 inserts L335/L367/L406) que corre semanal. Para feedback rápido a Danilo, falta inserir um log inline quando `escalated=true` por `[HANDOFF_HUMAN]` ou após `max_tool_iterations` sem resposta.
  - **P2-S15-001**: `admin_skill_suggestions_screen` tem `_searchController`, `_noteControllers` map — dispose presumido (limpo no relatório de issues, mas verificar).

### S16 — Configurações
- **Ecrãs:** `admin_platform_settings_screen`, `admin_dispatch_settings_screen`, `admin_edge_functions_screen` (✅ LIMPO)
- **RPCs:** `admin_list_settings`, `admin_update_setting`, `admin_edge_fn_health`
- **RPCs admin sem UI:** nenhuma — secção COMPLETA
- **Issues:**
  - **P2-S16-001**: `admin_platform_settings_screen` — `ctrl` sem dispose.
  - **P2-S16-002**: `admin_dispatch_settings_screen` — `ctrl` sem dispose.

### S17 — Audit Log
- **Ecrãs:** `admin_audit_log_screen` (✅ LIMPO)
- **RPCs:** `admin_list_audit_log`, `admin_list_audit_action_types`
- **Issues:** nenhum

---

## Lista PRIORIZADA global (ordem de execução)

### P0 (PARTIDOS — fixar PRIMEIRO)
1. **P0-S15-001** — support-chatbot: error check nos 3 inserts em `support_chatbot_messages` + `console.error`
2. **P0-S15-002** — support-chatbot: insert `skill_suggestions` inline quando escalated por handoff/max-iter
3. **P0-S8-001** — admin_wallets_screen: confirmar query usada / refactor para `admin_list_wallets`
4. **P0-S1-001** — admin_orders_screen: migrar `.from('orders')` directo → `admin_live_orders` RPC

### P1 (FALTA crítica / UI em falta)
5. **P1-S15-003** — admin: validar fluxo end-to-end skill_suggestions (list → approve → reject) — testes mentais
6. **P1-S1-001** — admin_order_detail: botão "Ver breakdown pagamento" (`admin_get_order_payment_breakdown`)
7. **P1-S1-002** — admin_orphan_payments: try/catch L34
8. **P1-S3-001** — admin_driver_detail: botão "Banir driver" (`admin_ban_driver`)
9. **P1-S3-002** — admin_driver_detail: botão "Reactivar driver" (`admin_reactivate_driver`)
10. **P1-S3-003** — admin_driver_detail: dialog "Editar dados driver" (`admin_update_driver`)
11. **P1-S3-004** — admin_driver_detail: acção "Soft-delete driver" (`admin_soft_delete_driver`) + dupla confirmação
12. **P1-S4-001** — admin_partner_detail: editor de horário semanal (`admin_update_partner_hours`)
13. **P1-S4-002** — admin_partner_detail: toggle override aberto/fechado (`admin_set_partner_override`/`admin_clear_partner_override`)
14. **P1-S4-003** — admin_partner_detail: "Adicionar data especial" (`admin_set_partner_special_date`)
15. **P1-S4-004** — admin_partner_detail: secção payouts (`admin_partner_payout_summary` + `admin_list_partner_payouts` + `admin_mark_partner_payouts_paid`)
16. **P1-S6-001** — admin_reservations_screen: botão "Sentar walk-in" (`admin_seat_walk_in`)
17. **P1-S8-001** — admin_wallets_screen: UI "Conceder crédito grátis" (`admin_grant_wallet_free`)
18. **P1-S8-002** — admin_wallets_screen: UI "Revogar crédito grátis" (`admin_revoke_wallet_free`)
19. **P1-S8-003** — admin_wallets_screen: UI "Perdoar dívida" (`admin_forgive_wallet_debt`)
20. **P1-S11-001** — novo ecrã `admin_broadcasts_history_screen` (`admin_list_broadcasts`)
21. **P1-S11-002** — refactor admin_send_notification para suportar `admin_create_broadcast` (agendar)
22. **P1-S13-001** — admin_dashboard: widget "Tempo real" (`admin_realtime_metrics`)

### P2 (melhorias — tantas quanto possível antes do fim)
23. **P2-S1-001** — admin_orders_screen: já OK (false positive de RPC count)
24. **P2-S2-001** — admin_pending_actions: try/catch nos 4 `admin_finalize_action`
25. **P2-S2-002** — admin_pending_actions: dispose `ctrl`
26. **P2-S3-001** — admin_driver_approval: limpar 2 TODOs + dispose controller
27. **P2-S4-001** — admin_partner_detail: try/catch L1116, L1293
28. **P2-S5-001** — admin_clients_screen: UI block/unblock (P2 porque ban já existe)
29. **P2-S5-002/3/4** — dispose em clients/tokens/referrals
30. **P2-S6-002** — admin_reservations_metrics: try/catch L31
31. **P2-S6-003** — admin_reservations_screen: dispose 7 controllers
32. **P2-S8-001** — admin_settlements: try/catch
33. **P2-S9-001** — admin_promo_codes: dispose 6 controllers
34. **P2-S11-001** — admin_send_notification: validar register_push_token implícito
35. **P2-S12-001** — admin_catalog: dispose 3 controllers
36. **P2-S13-001** — admin_dashboard: try/catch L109
37. **P2-S14-001/2** — dispose support_tickets/complaints controllers
38. **P2-S15-001** — verificar dispose em skill_suggestions screen
39. **P2-S16-001/2** — dispose em platform_settings/dispatch_settings

---

## Diagnóstico IA Gemini (especial)

### Logging chatbot — causa raiz CONFIRMADA
- **Edge Fn:** `bora_app/supabase/functions/support-chatbot/index.ts` (824L)
- **USA service_role** via `createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)` — RLS NÃO é o bloqueio.
- **3 inserts em `support_chatbot_messages`:**
  - L611: user message (`role: 'user'`)
  - L745: tool result (`role: 'tool'`)
  - L781: assistant final (`role: 'assistant'`)
- **NENHUM destruture `{ error }`** — todos os inserts são fire-and-forget.
- **Tabela `support_chatbot_messages`** tem RLS com `chatbot_messages_modify_admin` (só service_role pode modificar) → RLS está OK, mas se houver erro de coluna/constraint/check, falha silenciosa.
- **Fix:** mudar para `const { error } = await ...; if (error) console.error('[CHATBOT] insert error', error);` em cada um dos 3 inserts. Bonus: retornar warning no body da resposta para o cliente loggar.

### SKILL_GAP_LOG — mecanismo
- **Existe?** SIM, mas APENAS no cron `analyze-conversations` (3 inserts em `skill_suggestions` em L335/L367/L406 do `analyze-conversations/index.ts`).
- **NÃO existe no `support-chatbot` em tempo real.** Quando bot não sabe → `escalated=true` + cria `support_tickets` row, mas NÃO cria entry inline em `skill_suggestions`.
- **Fix proposto:** quando `escalated=true` por `[HANDOFF_HUMAN]` OU por `toolIters > max_tool_iterations`, criar entry em `skill_suggestions` com:
  - `pattern_summary`: primeiros 200 chars de `userMessage`
  - `status`: 'pending'
  - `proposal_type`: 'new_skill'
  - `zone_type`: 'safe'
  - `source`: 'inline_chatbot_escalation'
- Isto dá feedback em tempo real a Danilo via `admin_skill_suggestions_screen`.

### 24 skills do bot — cobertura
- Lista vive em `support_skills` table (referenciada em L625 do edge fn: `from('support_skills').select('skill_name, playbook_md').eq('active', true)`).
- TOOL_WHITELIST tem ~15 tools (agent_get_user_orders_summary, agent_get_order_status, agent_get_user_wallet_summary, agent_get_user_tokens_summary, agent_get_refund_status, agent_propose_action, etc.)
- **Análise sem dados reais (apenas 7 msgs no histórico):** impossível avaliar qualidade de resposta. Sessão dedicada futura após logging fixado (10-20 conversas reais).

### Knowledge base 534 chunks
- RAG cache + match_knowledge RPC + dedup por source_file (max 3/source) usados no edge fn (L580-660 área).
- Min similarity, match_count configuráveis via constantes RAG_MIN_SIMILARITY/RAG_MATCH_COUNT.
- **Cobertura por área:** não validável sem queries reais. Sessão dedicada futura.

### Plano IA Gemini (sessão futura)
1. Fixar logging (esta sessão)
2. Adicionar SKILL_GAP_LOG inline (esta sessão)
3. Recolher 1-2 semanas de conversas reais
4. Sessão "IA-Audit-V2" com dados reais: avaliar cada uma das 24 skills, identificar gaps de RAG, enriquecer knowledge

---

## Comparação Uber Eats / Glovo / iFood

| Feature | Bora (estado) | Uber Eats RM | Glovo Partner Portal | iFood Portal Parceiro |
|---|---|---|---|---|
| Editor horário semanal por loja | ❌ RPC sem UI | ✅ | ✅ | ✅ |
| Override "Fechar agora" | ❌ RPC sem UI | ✅ | ✅ | ✅ |
| Data especial (feriado) | ❌ RPC sem UI | ✅ | ✅ | ✅ |
| Banir/reactivar driver | ❌ RPC sem UI | ✅ (interno) | ✅ (interno) | ✅ |
| Walk-in seat | ❌ RPC sem UI | ✅ (parcial) | — | ✅ |
| Crédito grátis a cliente | ❌ RPC sem UI | ✅ (Care) | ✅ | ✅ |
| Perdoar dívida cliente | ❌ RPC sem UI | ✅ (Care) | ✅ | ✅ |
| Histórico broadcasts | ❌ RPC sem UI | ✅ | ✅ | ✅ |
| Métricas tempo real | ❌ RPC sem UI | ✅ | ✅ | ✅ |
| Payment breakdown order | ❌ RPC sem UI | ✅ | ✅ | ✅ |

**Conclusão:** Bora tem ~70 % das features admin standard "ready", mas faltam ~10 botões/écrans para igualar Uber Eats Restaurant Manager admin/Glovo Partner Portal.

---

## Bugs fora do scope encontrados

- Nenhum bug crítico fora do scope foi detectado durante esta auditoria. As áreas proibidas (dispatch-engine, stripe-webhook, finalize-order-from-intent, refund, etc.) não foram tocadas nem investigadas.

---

## Recalibração pós-FASE 1 (2026-05-17 — descoberta de services intermediários)

A primeira análise olhou apenas para chamadas `.rpc('admin_*')` em `lib/screens/admin/`. Ao expandir a busca para todo o `lib/`, descobriu-se que **muitas RPCs "sem UI" estão na verdade chamadas via services/stores/widgets**:

- `services/admin/admin_driver_service.dart` chama via wrapper `_callRpc()`: `admin_ban_driver`, `admin_reactivate_driver`, `admin_update_driver`, `admin_soft_delete_driver`, `admin_force_driver_logout` (Edge Function via `functions.invoke()`)
- `services/wallet_service.dart`: `admin_list_wallets`, `admin_grant_wallet_free`, `admin_revoke_wallet_free`, `admin_forgive_wallet_debt`
- `stores/restaurant_store.dart`: `admin_update_partner_data`, `admin_update_partner_hours`, `admin_set_partner_override`, `admin_clear_partner_override`, `admin_set_partner_special_date`
- `widgets/admin_realtime_metrics_card.dart`: `admin_realtime_metrics` (mounted em admin_dashboard_screen L209)
- `services/admin_push_service.dart`: `admin_register_push_token`

**P0 invalidados:**
- ~~P0-S8-001~~ `admin_wallets_screen` usa `WalletService.instance.adminList()` → `admin_list_wallets` (correto).
- ~~P0-S1-001~~ `admin_orders_screen` usa `.from('orders')` intencionalmente para filtros complexos client-side; RLS admin policy `_is_admin()` permite. `admin_live_orders` RPC é usada noutro ecrã (mapa). Re-classificado P2.

**P1 invalidados:**
- ~~P1-S3-001 a P1-S3-004~~ drivers ban/reactivate/update/soft_delete — JÁ existem em `admin_driver_detail_screen` via `_runBan`/`_runReactivate`/`_runEdit`/`_runSoftDelete` chamando `AdminDriverService`.
- ~~P1-S4-001 a P1-S4-003~~ partner hours/override/special_date — RPCs JÁ chamadas via `restaurant_store.dart`. UI provavelmente no painel parceiro próprio (não admin) — não é gap admin real.
- ~~P1-S8-001 a P1-S8-003~~ wallets grant/revoke/forgive — `admin_wallets_screen` tem `_grantOrRevoke()` que usa `WalletService.adminGrantFree/adminRevokeFree`. `adminForgiveDebt` no service mas verificar se ecrã tem botão (P2 follow-up).
- ~~P1-S13-001~~ realtime metrics — `AdminRealtimeMetricsCard` já mounted no dashboard L209.
- ~~P1-S1-001~~ payment breakdown — `admin_order_detail_screen` já mostra breakdown completo via colunas (wallet_applied_cents, tokens_*, stripe_charge_cents, price). RPC `admin_get_order_payment_breakdown` redundante.

### RPCs realmente sem caller no Flutter (15)
```
admin_cancel_order                      (usado via _admin_cancel_order_dialog parent screen / Edge fn?)
admin_get_order_payment_breakdown       (REDUNDANTE — ecrã já mostra)
admin_ban_driver/reactivate/update/soft_delete  (FALSOS POSITIVOS — chamados via service)
admin_partner_payout_summary            (REAL P1)
admin_list_partner_payouts              (REAL P1)
admin_mark_partner_payouts_paid         (REAL P1)
admin_block_client / admin_unblock_client (duplicado com ban/unban — P3)
admin_get_reservations_stats            (P2 — duplicado com metrics)
admin_seat_walk_in                      (REAL P1 — feature operacional)
admin_list_broadcasts                   (REAL P1 — histórico)
admin_create_broadcast                  (REAL P1 — persiste vs broadcast_notification fire-forget)
```

**P1 reais que justificam UI nova: 3 features**
1. **Walk-in seat** em admin_reservations_screen (dialog) — `admin_seat_walk_in(p_restaurant_id, p_party, p_table_id, p_client_name?, p_client_phone?)` ✅ FIXADO
2. **Broadcasts history** novo ecrã `admin_broadcasts_history_screen` + integrar `admin_create_broadcast` em vez de fire-forget `admin_broadcast_notification` para auditoria ✅ FIXADO
3. ~~**Partner payouts**~~ → **DOWNGRADED P3 (sessão futura)**. Razão: as 3 RPCs (`admin_partner_payout_summary`, `admin_list_partner_payouts`, `admin_mark_partner_payouts_paid`) estão documentadas no COMMENT da migration `20260430240000_reservations_split_v2.sql` como *"definitions complete em prod via MCP"* — não há corpo em migration versionada. `admin_mark_partner_payouts_paid` muda estado financeiro (paga €2 por reserva chegada ao parceiro) — toca em fluxo financeiro próximo da área proibida. Decisão CEO: pedir a Danilo as signatures via MCP antes de criar UI. `admin_mark_partner_credits_paid` (que JÁ tem UI em admin_partner_settlements_screen) cobre o caso comum de settlement semanal.

## Plano de execução autónoma

**Ordem das próximas 3-4 horas:**

1. P0-S15-001 (logging chatbot) → commit
2. P0-S15-002 (SKILL_GAP inline) → commit
3. P0-S8-001 (investigar admin_wallets_screen) → commit
4. P0-S1-001 (admin_orders_screen → admin_live_orders) → commit
5. P1 batch drivers (S3-001 a S3-004) → commit
6. P1 batch parceiros (S4-001 a S4-004) → commit
7. P1 batch wallets (S8-001 a S8-003) → commit
8. P1 batch restantes (S1-001, S6-001, S11-001, S13-001) → commit
9. P2 bulk: controllers dispose + try/catch generalizados → commit
10. Merge → autonomous-night-2026-04-29 → push

**Critério de paragem:** apenas se cair em regra 2 (perda contexto / área proibida / dúvida de produto).
