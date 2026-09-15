# Provas — painel-admin-limpo — 14/09/2026 (hora de Lisboa)

Todas as consultas correram por MCP Supabase (projeto ojykpzwqrtusfeakzrna). Onde diz
"JWT simulado" usou-se `set_config('request.jwt.claims', ...)` com `app_metadata.role=admin`,
na mesma sessão SQL, para passar o `_admin_op_guard()` — técnica da prova em rollback.

## 1. Cada cartão de cima bate com a base (01:34 Lisboa / 00:34 UTC)

| o quê | base (SQL directo) | RPC admin_dashboard_metrics_v2 |
|---|---|---|
| hoje label | 14/09 | 14/09 |
| entregas hoje (sem demo, Lisboa) | 0 | 0 |
| entregas em curso | 0 | 0 |
| TVDE hoje | 0 | 0 |
| marcações por confirmar | 0 | 0 |
| retido por falta (cents) | 0 | 0 |
| acerto fechado 07–13/09: a pagar (3 tabelas) | 4034 | 4034 |
| · estafetas (driver_weekly_settlements) | 704 | 704 |
| · Goola Açaí (partner_weekly_settlements) | 2180 | 2180 |
| · Barbearia Ouro e Prata (appointment_payouts) | 1150 | 1150 |
| receita semana em curso, entregas (ledger sem demo) | 0 | 0 |
| cartão ANTIGO "A pagar — drivers" (ledger inteiro) | 12,15 € | deixou de existir |

Às 00:53 Lisboa (23:53 UTC), com o dia 13/09 ainda vivo em UTC, o RPC v2 já dava
`entregas.hoje = 0` para 14/09 e o gráfico dos 7 dias com 13/09 = 0 (o único pedido de
13/09 é o demo `36e6812a`). O RPC antigo, à mesma hora, contava esse demo como "hoje".

## 2. Demo (00:47 Lisboa)

- `is_demo_email('ouro.prata@bora.app')` → false (parceiro REAL) · `mr.kebab@bora.app` → false
- `demo-estafeta@bora.app` → true · `prova.taxa099@bora.app` → true · `e2e_client_a@boraapp.test` → true
- `alefernandesdemoura03@gmail.com` → false (cliente real)
- `is_demo_driver('dede…0001')` → true · Valdemir `e355fde0…` → false · barbeiro `82e3162c…` → false
- `is_demo_order(36e6812a)` → true · `is_demo_order(20f2d21e, Danilo real)` → false
- linha de acerto demo `9d33ae48` → apagada; `driver_weekly_settlements` semana 06/09 = Danilo 1,10 · Valdemir 5,94
- recálculo `compute_driver_settlement(demo, semana 06/09, persist=true)` → `settlement_id: null`
  (trigger bloqueou) + `admin_audit_log.acerto_demo_ignorado`
- recálculo do Danilo → `settlement_id a28d6ad1`, net 1,10 (inalterado)
- **fecho real das 01:05 (cron 26) já com o trigger:** tentou o demo, ficou registado
  `acerto_demo_ignorado` às 00:05:00 UTC; as linhas da semana continuam só Danilo e Valdemir
- **digest real das 01:20 (cron 63):** 4 recibos `sent` (Danilo, Valdemir, Goola, Ouro e Prata), zero demo
- `weekly_closeout_excluidos('2026-09-06')` → Estafeta Demo, 1 entrega de teste, 5,69 €, fora do fecho

## 3. Marcações (rollback com RAISE EXCEPTION)

- marcação confirmada há 3 h, 12 € pagos → `_appointment_cron_auto_no_show()` →
  `por_confirmar_novas=1`, status `awaiting_confirmation`, `deposit_status` continua `paid`,
  `no_show_at` nulo, aviso no painel criado, push ao parceiro na fila (`notify-service-provider`)
- falta marcada pelo parceiro (retained) → `admin_list_appointments_retained` lista 1 item / 1200 c →
  `admin_appointment_revert_no_show` → `completed`, `paid`, `week_start 2026-09-06T23:00Z`,
  `admin_audit_log` = 1 linha (`appointment_no_show_reverted_by_admin`)
- estado do cron 42 depois da migration: `marked_no_show` é sempre 0 por desenho

## 4. Semana 2026-09-06 (07–13/09 Lisboa) depois de tudo

estafetas: Danilo 1,10 · Valdemir 5,94 (= 7,04) · Goola Açaí 21,80 · Barbearia Ouro e Prata **11,50**
(payout `79c35a51`, 12,00 − 0,50). Total a pagar 40,34 €. Demo: nada.

## 5. Código

`flutter analyze` → 0 erros (218 infos/avisos pré-existentes) · `flutter test` → 518 verdes antes
das fotos; `test/painel_admin_limpo_test.dart` 17 + `test/golden/painel_admin_limpo_test.dart` 3.
Fotos nesta pasta.
