# APROVADOR-VERMELHO — Triagem da fila 🔴 (2026-07-12, gatilho FALLBACK 30MIN)

Contexto do disparo: `robot_suggestions status='nova'` com item mais antigo parado ~29490 min
(desde 2026-06-22) — o gatilho normal por item-novo não bloqueava nada (Balde B fica sempre em
`nova` até o Danilo decidir), mas a rede de segurança de 30min disparou mesmo assim para garantir
nova passagem de olhos sobre TODA a fila.

**Flag `platform_settings.aprovador_vermelho_auto_baldeA` = `true` (ligada)** → auto-aprovação de
Balde A permitida nesta corrida.

Fila `status='nova'` no momento da triagem: **6 itens**.

## Balde A — auto-aprovado (1 item)

- **670a4840-db67-4f70-b089-3c8201954f2d** — "Investigar e otimizar função `_cron_check_orphan_orders`"
  (categoria `performance`, severidade 3, criado 2026-07-12 15:07 UTC, nunca triado antes).
  **Motivo/prova positiva:** li `pg_get_functiondef(_cron_check_orphan_orders)` — o corpo só faz
  `SELECT` sobre `orders` e `PERFORM notify_admin_event(...)` (insert em `admin_notifications`).
  Zero `UPDATE`/`DELETE`, zero escrita em `orders/wallets/ledger`, zero chamada a Edge Function que
  cobra ou ao `dispatch-engine`. É puramente diagnóstico/alerta — falso-positivo de "toca dispatch"
  (a função só *observa* pedidos órfãos, não decide nada sobre eles).
  → `status` mudado para `aprovada`, `reviewed_at=now()`. Audit log:
  `robot_suggestion_approved_baldeA` (entity_id acima).

## Balde B — fica para o Danilo (5 itens, nenhum promovido)

Todos os 5 já tinham sido classificados Balde B numa corrida anterior de hoje (2026-07-12
11:26–11:27 UTC, mesmo gatilho FALLBACK 30MIN) — motivo confirmado e inalterado nesta nova
passagem. Continuam em `status='nova'`, sem promoção automática:

- **268aad47** (criado 2026-06-22, ~20.5 dias parado) — "Otimizar `bora_dispatch_maintenance`".
  Faz: função central do motor de dispatch (cancela pagamentos abandonados, chama
  `dispatch-engine` via `net.http_post`, aplica TTLs de cancelamento). Risco: qualquer "otimização"
  toca zona protegida do dispatch/pagamento.
- **abeca5d7** (criado 2026-06-22, ~20.5 dias parado) — "Otimizar `_appointment_cron_auto_no_show`".
  Faz: marca `no_show` e muda `deposit_status: paid → retained` (retenção de depósito = dinheiro).
  Risco: erro na lógica pode reter/libertar depósito incorretamente.
- **85d8911b** (criado 2026-07-11) — "Reatribuir automaticamente pedidos presos" (TTL de
  reatribuição). Faz: propõe nova lógica de reatribuição no motor de dispatch. Risco: zona
  protegida (dispatch_engine).
- **d9df69ed** (criado 2026-07-12 11:07) — "Analisar cancelamentos por `dispatch_safety_timeout`".
  Faz: investigar cancelamentos gerados pelo próprio TTL de segurança do dispatch. Risco: domínio
  dispatch, resolução provável mexe no motor.
- **bea503a3** (criado 2026-07-12 11:07) — "Reduzir no-show em agendamentos". Faz: propõe
  lembretes E "políticas de depósito/pré-pagamento" — toca dinheiro (depósito de reserva).

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch e/ou depósito). Está tudo pronto — os 5 itens
aguardam o Danilo decidir via Central (`AdminRobotSuggestionsScreen`) ou dizer "vai" por Telegram.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **ligado** (`true`).

## Rasto (admin_audit_log)
- `robot_suggestion_approved_baldeA` para 670a4840 (novo).
- `robot_suggestion_baldeB_reconfirmado` (entrada consolidada, evita duplicar as 5 entradas
  detalhadas já gravadas na corrida das 11:26–11:27 UTC de hoje).

## Addendum — 3ª corrida do dia (2026-07-12, ~21:58 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` re-lida: **os mesmos 5 itens Balde B** de cima (`268aad47`, `abeca5d7`,
`85d8911b`, `d9df69ed`, `bea503a3`) — nenhum item novo, nenhum item promovido. `670a4840` já não
aparece na fila (confirma que a auto-aprovação anterior persistiu). `platform_settings.aprovador_vermelho_auto_baldeA`
continua `true`. Sem novo aviso Telegram para os 5 (backlog já surfaçado nas corridas de
11:26–11:27 e 19:40 UTC — reavisar seria spam). Audit log: nova entrada consolidada
`robot_suggestion_baldeB_reconfirmado` (`eb619da5-2dc6-4fca-be00-a9101d99e989`, 21:58:14 UTC).

## Addendum — 4ª corrida do dia (~23:01 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` re-lida via SQL direto (`ojykpzwqrtusfeakzrna`): **exatamente os mesmos 5
itens Balde B** (`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), mesmo veredito e
mesmo motivo de cada corrida anterior — zero itens novos, zero promoções. Confirmado por leitura
direta de `robot_suggestions` (não só do relatório anterior). Sem novo aviso Telegram (backlog já
surfaçado 3x hoje — reavisar seria spam). Audit log: nova entrada consolidada
`robot_suggestion_baldeB_reconfirmado` (`eec96676-312f-4e02-a00d-d0c26ab95dab`, 23:01:25 UTC).

**Observação para o Danilo (não é ação, é sinal):** este é o 4º disparo idêntico de FALLBACK
30MIN hoje para os mesmos 5 itens. Isso é o comportamento *desenhado* do
`hermes-aprovador-vermelho.sh` (força-dispara a cada ≥30min enquanto houver item `nova` parado —
ver `STATE_FORCE` no script) — não é bug, é rede de segurança. Mas como estes 5 itens são todos
Balde B (dinheiro/dispatch) e só o Danilo os resolve, o disparo vai continuar a repetir-se a cada
~30min indefinidamente até haver decisão na Central. Se o custo de reconfirmar a cada 30min for
indesejado, considerar aumentar o `STALE_MIN` (ex.: backoff para 2h/4h após a 1ª reconfirmação) —
fica como sugestão, não alterado nesta corrida (fora do escopo "só roteamento de aprovação").

## Addendum — 5ª corrida do dia (2026-07-12/13, ~23:20 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` re-lida via SQL direto (`ojykpzwqrtusfeakzrna`): **exatamente os mesmos 5
itens Balde B** (`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), mesmo veredito e
mesmo motivo de todas as corridas anteriores — zero itens novos, zero promoções. Flag
`platform_settings.aprovador_vermelho_auto_baldeA` confirmada `true`. Sem novo aviso Telegram
(backlog já surfaçado 4x hoje — reavisar seria spam). Audit log: nova entrada consolidada
`robot_suggestion_baldeB_reconfirmado` (`f8b4eee1-e831-4752-bbd9-0fdc26152871`, 23:20:30 UTC).

Reforço da observação da 4ª corrida: são já **5 disparos idênticos** hoje para o mesmo conjunto de
5 itens Balde B. Nenhum é falso-positivo — todos tocam dispatch/depósito/dinheiro real e por
desenho só o Danilo os resolve. O padrão de repetição a cada ~30min é esperado do
`hermes-aprovador-vermelho.sh` (`STATE_FORCE`), não um bug. Sugestão de backoff crescente do
`STALE_MIN` mantém-se como pendência aberta para o Danilo decidir — fora do escopo desta corrida.

## Addendum — 6ª corrida do dia (2026-07-12/13, ~23:37 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` re-lida via SQL direto (`ojykpzwqrtusfeakzrna`, `information_schema` +
`robot_suggestions`): **exatamente os mesmos 5 itens Balde B** (`268aad47`, `abeca5d7`, `85d8911b`,
`d9df69ed`, `bea503a3`), mesmo veredito e mesmo motivo de todas as corridas anteriores — zero itens
novos, zero promoções. Item mais antigo (`268aad47`/`abeca5d7`) já ~29730 min parado (~20.6 dias).
Flag `platform_settings.aprovador_vermelho_auto_baldeA` reconfirmada `true`. Sem novo aviso
Telegram (backlog já surfaçado 5x hoje — reavisar seria spam). Audit log: nova entrada consolidada
`robot_suggestion_baldeB_reconfirmado` (`9cff153a-0ced-4861-8601-ee681579ac84`, 23:38:03 UTC).

São já **6 disparos idênticos** do mesmo gatilho FALLBACK 30MIN no mesmo dia, sempre para o mesmo
conjunto de 5 itens Balde B, sempre com o mesmo veredito. O comportamento do agente continua
correto (Balde B nunca promovido sozinho), mas o volume de reconfirmações idênticas reforça — pela
6ª vez — a pendência de backoff crescente do `STALE_MIN` em `hermes-aprovador-vermelho.sh`
(sugestão registada desde a 4ª corrida, não aplicada — fora do escopo deste agente).

## Addendum — 8ª reconfirmação consolidada (2026-07-13, ~03:52 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` relida via SQL direto (`ojykpzwqrtusfeakzrna`): **os mesmos 5 itens Balde B**
(`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), item mais antigo agora ~29984 min
parado (~20.8 dias). Flag `platform_settings.aprovador_vermelho_auto_baldeA` reconfirmada `true`.
Prova positiva reavaliada do zero para os 5 (evidencia/proposta/payload_execucao) — nenhum passa o
teste sem-escrita/sem-charge/sem-EdgeFn-de-cobrança: `268aad47` e `abeca5d7` mexem no coração do
dispatch/no-show+depósito; `85d8911b` propõe lógica nova de reatribuição no dispatch_engine;
`d9df69ed` investiga cancelamentos gerados pelo TTL de segurança do dispatch;
`bea503a3` propõe políticas de depósito/pré-pagamento em agendamentos. Zero itens novos, zero
promoções, 0 Balde A nesta corrida. Sem novo aviso Telegram (backlog já surfaçado 7x hoje — evitar
spam). Audit log: nova entrada consolidada `robot_suggestion_baldeB_reconfirmado`
(`3f47e6a0-80d4-4f2e-9614-7c80ec14e039`, 03:52:33 UTC).

Esta é já a **8ª reconfirmação consolidada** para o mesmo lote de 5 itens Balde B — reforça (mais
uma vez) a recomendação, ainda pendente, de aplicar backoff/cooldown crescente ao `STALE_MIN` do
`hermes-aprovador-vermelho.sh`, para não repetir a mesma triagem idêntica a cada ~30min enquanto
não houver decisão do Danilo na Central.

## Addendum — 9ª reconfirmação consolidada (2026-07-13, ~04:24 UTC, gatilho FALLBACK 30MIN)
Fila `status='nova'` relida via SQL direto (`ojykpzwqrtusfeakzrna`, colunas corretas confirmadas de
novo: `titulo`/`proposta`/`evidencia`, não `title`/`description`). Item mais antigo (`268aad47` /
`abeca5d7`, criados 2026-06-22 08:07 UTC) já **~30017 min parado (~20.8 dias)**. Flag
`platform_settings.aprovador_vermelho_auto_baldeA` reconfirmada `true`.

Prova positiva reavaliada do zero para os 5 itens (independente do relatório anterior, direto da
tabela):
- `268aad47` — `bora_dispatch_maintenance`: cancela pagamentos abandonados + chama `dispatch-engine`
  via `net.http_post` + TTLs de auto-cancelamento. Não passa o teste sem-escrita/sem-EdgeFn-cobrança.
- `abeca5d7` — `_appointment_cron_auto_no_show`: `UPDATE appointments` que decide reter depósito
  (`deposit_status: paid → retained`). Escrita real em dinheiro de reserva.
- `85d8911b` — "Reatribuir automaticamente pedidos presos": propõe nova lógica de reatribuição no
  `dispatch_engine` (zona protegida), não é leitura.
- `d9df69ed` — "Analisar cancelamentos por `dispatch_safety_timeout`": investigação sobre o próprio
  TTL de segurança do dispatch; resolução provável mexe no motor — dúvida → desce para B.
- `bea503a3` — "Reduzir no-show em agendamentos": proposta inclui explicitamente "políticas de
  depósito/pré-pagamento" — toca dinheiro de reserva + risco de receita citado na própria proposta.

Nenhum dos 5 passa o teste sem-escrita/sem-charge/sem-EdgeFn-de-cobrança → **0 Balde A, 0
promoções, 0 itens novos** na fila. Sem novo aviso Telegram (backlog já surfaçado 8x hoje —
reavisar seria spam). Audit log: nova entrada consolidada `robot_suggestion_baldeB_reconfirmado`
(`55a91d6f-8bcb-45ef-b277-c932af69470a`, 04:24:30 UTC, `reconfirmacao_numero: 9`).

**Sinal reforçado ao Danilo (9ª vez, não é ação minha):** são já 9 disparos idênticos do
`FALLBACK 30MIN` no mesmo dia (~19:40 UTC de 12/07 até ~04:24 UTC de 13/07, quase 9h seguidas),
sempre para o mesmo conjunto de 5 itens Balde B, sempre com o mesmo veredito correto. Nada disto é
bug de triagem — é o comportamento desenhado (Balde B nunca promovido sozinho) mais o `STATE_FORCE`
do `hermes-aprovador-vermelho.sh` a disparar a cada ~30min enquanto a fila tiver item `nova`
parado. Continua a pendência, aberta desde a 4ª corrida e nunca aplicada: dar backoff/cooldown
crescente ao `STALE_MIN`, ou simplesmente decidir os 5 itens na Central (`AdminRobotSuggestionsScreen`)
para a fila deixar de estar `nova` e o gatilho parar de disparar sozinho.
