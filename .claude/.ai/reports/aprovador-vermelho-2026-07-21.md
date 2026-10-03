# Aprovador-Vermelho — Triagem da fila 🔴 (2026-07-21)

**Gatilho:** watermark `red_queue_watermark()` avançou — newest=2026-07-21T05:07:12.469719+00:00,
count=1. Confirmado por SELECT direto: `robot_suggestions WHERE status='nova'` tem exatamente
**1 item** (não havia acúmulo escondido).

## Fila lida (status='nova')

| id | dedup_key | categoria | nível | criado |
|---|---|---|---|---|
| `3adc1b43-3276-4d0f-94ed-f2e35657a5ce` | `infra:queries-lentas-cron` | `infra_cron` | 3 | 2026-07-21T05:07:12 UTC |

Título: "Investigar e otimizar queries lentas no cron". Proposta: investigar plano de execução de
`_cron_check_orphan_orders()`, `_appointment_cron_auto_no_show()` e `_cron_check_ghost_drivers()`.
Evidência: `slow_queries_top3` (140/4061/139 chamadas, 65.4/62.2/61.5 ms médios).

## Triagem

### Balde A (leitura/falso-positivo) — nenhum item nesta corrida
0 itens.

### Balde B (dinheiro real — precisa do Danilo)

- **`3adc1b43-3276-4d0f-94ed-f2e35657a5ce`** — "Investigar e otimizar queries lentas no cron"
  **Faz:** agrupa 3 funções cron numa única proposta. `_cron_check_orphan_orders()` e
  `_cron_check_ghost_drivers()` são isoladamente Balde A (só `SELECT` + `notify_admin_event`,
  confirmado em corridas anteriores por `pg_get_functiondef`). Mas `_appointment_cron_auto_no_show()`
  faz `UPDATE appointments SET status='no_show', deposit_status = CASE WHEN deposit_status='paid'
  THEN 'retained' ELSE deposit_status END` — decide reter ou não o depósito real do cliente em
  no-show. **Risco:** pela regra do item agrupado (confirmada 15x+ em corridas de 2026-07-18/19/20
  para a mesma família de funções), quando uma linha da fila junta ≥1 função Balde B, o item
  **inteiro** cai em Balde B — sem aprovação parcial por função. Este é um **dedup_key novo**
  (`infra:queries-lentas-cron`, distinto de `infra:otimizar-queries-cron-lentas[-v2/-v3]`, que já
  foram todos decididos: rejeitada/rejeitada/aprovada) e **primeira ocorrência** (zero entradas
  prévias em `admin_audit_log` para este id).

  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

  **Ação tomada:** encaminhado ao Danilo via Telegram (ponte SSH PC→VPS, chat_id `6731890157`,
  `Sent to telegram home channel`, exit 0). Registado em `admin_audit_log`
  (`action='robot_suggestion_baldeB_surfaced'`, id `9a25c3f9-0243-4d2f-971e-d92292c0b07a`,
  `created_at=2026-07-21 05:13:19.602361 UTC`). **Não** alterado `status` (continua `nova`).

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado), confirmado por SELECT
antes da triagem — sem efeito prático nesta corrida (0 itens Balde A na fila).

## Itens da mesma família já resolvidos (contexto, não re-triados)
- `8ccc09bb-e5b7-458e-89f9-f179df67f942` (`operacao_pedidos:pedido-preso-sem-atribuicao`) —
  `status='rejeitada'`, `reviewed_at=2026-07-20 11:56:14 UTC`.
- `77c31fff` / `29ea4b41` / `01a67895` (`infra:otimizar-queries-cron-lentas[/-v2/-v3]`) —
  `rejeitada` / `rejeitada` / `aprovada` (decisão humana real via `robot_approve_plan`).

## Anti-spam Telegram
Não suprimido — primeira ocorrência genuína deste id/dedup_key (sem envio anterior a suprimir
contra).

## Resumo
- Balde A auto-aprovados: **0**.
- Balde B encaminhados: **1** — `3adc1b43-3276-4d0f-94ed-f2e35657a5ce` ("Investigar e otimizar
  queries lentas no cron"), motivo: agrupa função que decide retenção de depósito real
  (`_appointment_cron_auto_no_show`).
- Telegram: **enviado** (não suprimido).

---

## Addendum — 2ª corrida (05:19:37 UTC)
Mesmo watermark (`newest=2026-07-21T05:07:12.469719+00:00, count=1`), mesmo item, zero mudança de
evidência ou estado. Registado `admin_audit_log` `action='robot_suggestion_baldeB_surfaced'`,
`reconfirmacao_numero=2`, id não capturado neste ficheiro na altura (ver `execute_sql` desta
corrida). Telegram **suprimido** (anti-spam — mesmo id/watermark já notificado 6 min antes, às
05:13:19 UTC). Balde A: 0. Balde B: 1 (mesmo item, mesmo motivo).

## Addendum — 3ª corrida (05:23:11 UTC, esta sessão — loop autónomo noturno, sem canal Telegram
direto)
Gatilho recebido: mesmo watermark exato (`newest=2026-07-21T05:07:12.469719+00:00, count=1`).
Confirmado por SELECT direto: `robot_suggestions WHERE status='nova'` continua com exatamente
**1 item** — o mesmo `3adc1b43-3276-4d0f-94ed-f2e35657a5ce`, `status='nova'`, `reviewed_at=NULL`.
Nenhum item novo apareceu.

**Triagem (reconfirmação, sem re-derivar a análise):** mesmo veredito Balde B — item agrupado
(`_cron_check_orphan_orders` + `_cron_check_ghost_drivers` = Balde A isolado; `_appointment_cron_auto_no_show`
= Balde B sempre, decide reter depósito real). Regra do item agrupado (confirmada 2026-07-18/19/20):
item inteiro cai em Balde B, sem aprovação parcial. **Não auto-aprovado.**

**Ação tomada:** registado em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`,
id `218c5ec3-1445-4aaa-b386-761328e5319d`, `created_at=2026-07-21 05:23:11.185788 UTC`,
`reconfirmacao_numero=3`). `status` do item **não alterado** (continua `nova`).

**Telegram:** **suprimido** (protocolo anti-spam) — última notificação real foi há ~9 min (05:13:19
UTC) e a reconfirmação anterior há ~3 min (05:19:37 UTC); mesma prova, mesmo watermark, mesmo id,
zero informação nova. Reenviar agora seria ruído. Esta sessão do loop autónomo não tinha ponte
Telegram direta disponível (SSH PC→VPS) para este item de qualquer forma — decisão de supressão
seria a mesma independentemente disso, pelo protocolo de checkpoint (~59-60min) já usado na família
`operacao_pedidos`.

**Auto-Balde-A:** `platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado, confirmado
por SELECT nesta corrida) — sem efeito prático (0 itens Balde A na fila).

### Resumo desta corrida (3ª)
- Itens processados: **1**.
- Balde A auto-aprovados: **0**.
- Balde B encaminhados/reconfirmados: **1** — mesmo item, mesma razão; Telegram suprimido por
  anti-spam (já notificado 2x nesta mesma janela).
- Erros/bloqueios: nenhum. RPC `robot_approve_plan`/reject exige JWT admin que o MCP não tem —
  não relevante aqui pois o item é Balde B (não se aprova, só se regista roteamento via
  `admin_audit_log` INSERT direto, mesmo mecanismo das corridas anteriores).

## Addendum — 4ª corrida (FALLBACK 30MIN, ~05:42:29 UTC, gap ~19min desde a 3ª)
Gatilho: FALLBACK 30MIN do watchdog (item `nova` mais antigo parado ≥30min). Mesmo watermark, mesmo
item único na fila (`3adc1b43-3276-4d0f-94ed-f2e35657a5ce`), zero evidência nova. Mesmo veredito
Balde B (item agrupado, regra inalterada). `admin_audit_log` `action='robot_suggestion_baldeB_reconfirmado'`,
id `a3ccfb2e-efec-4f25-91b5-d3edb7c15f96`, `created_at=2026-07-21 05:42:29.641399 UTC`,
`reconfirmacao_numero=4`. Telegram **suprimido** (gap desde o envio real de 05:13:19 UTC = ~29min,
ainda abaixo do checkpoint ~59-60min). Verificado o gap conhecido `robot_emerson_decide` (projeto
`robot_emerson_decide_gap_nivel_evidencia`): revistos os 2 únicos itens `aprovada-emerson` das
últimas 48h (`86dc8990`/`88bebaed`, categoria `catalogo`, ambos já confirmados Balde A legítimo em
corridas anteriores) — nenhuma promoção indevida detectada. Balde A: 0. Balde B: 1 (mesmo item).
Sem relatório próprio; consolidado em `aprovador-vermelho-historico-corridas.md` (linha 2026-07-21).

## Addendum — 5ª corrida (FALLBACK 30MIN, ~05:47:39 UTC, gap ~5min16s desde a 4ª)
**Gatilho recebido (conforme contexto da tarefa):** rede de segurança de 30 minutos do watchdog —
item `nova` mais antigo (`3adc1b43-3276-4d0f-94ed-f2e35657a5ce`, criado 05:07:12 UTC) parado
**39.7 minutos** (≥32min reportado), `count=1`. Confirmado por SELECT direto:
`robot_suggestions WHERE status='nova'` continua com exatamente **1 item** — nenhum item novo
apareceu, nenhum acúmulo escondido.

**Triagem (reavaliada, não só reconfirmada por preguiça):** mesmo veredito Balde B. Item agrupado
cita `_cron_check_orphan_orders()` (Balde A isolado — só `SELECT`+`notify_admin_event`, confirmado
por `pg_get_functiondef` em corridas anteriores) + `_cron_check_ghost_drivers()` (Balde A isolado,
mesma prova) + `_appointment_cron_auto_no_show()` (**Balde B sempre** — `UPDATE appointments SET
status='no_show', deposit_status=CASE WHEN deposit_status='paid' THEN 'retained' ELSE
deposit_status END`, decide reter dinheiro real de depósito de cliente no-show). Pela regra do item
agrupado (confirmada 15x+ em corridas 2026-07-18 a 2026-07-21 para esta família): quando ≥1 função
citada é Balde B, o item **inteiro** cai em Balde B — **sem aprovação parcial**. Dúvida zero aqui
(prova positiva de escrita financeira já confirmada por leitura direta do corpo da função em
corridas anteriores) — não há promoção possível deste item, mesmo com `auto_baldeA_flag=true`.

**Ação tomada:** registado em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`,
id `6feb688c-8422-4f9d-bda9-389034022478`, `created_at=2026-07-21 05:48:01.682748 UTC`,
`reconfirmacao_numero=5`, `surfaced_anterior_id=a3ccfb2e-efec-4f25-91b5-d3edb7c15f96`) — confirmado
por `RETURNING` real da query INSERT. `status` do item **não alterado** (continua `nova`,
`reviewed_at` continua `NULL`). Não foi feita nenhuma edição de código, migration, ou lógica de
negócio — só o roteamento/registo de auditoria, conforme o mandato deste agente.

**Telegram:** **suprimido** — gap desde o último envio real (05:13:19 UTC) = **~34.3 min**, ainda
abaixo do checkpoint periódico (~59-60min) usado nesta mesma família de regra nas corridas de
2026-07-19/20. Mesma prova, mesmo watermark, mesmo id, zero informação nova desde a 4ª corrida
(19 min antes) — reenviar agora seria ruído. Esta sessão não tinha ponte SSH PC→VPS disponível
para reenvio de qualquer forma; a decisão de suprimir seria a mesma por protocolo mesmo se tivesse.

**Auto-Balde-A:** `platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado, reconfirmado
por SELECT nesta corrida) — sem efeito prático (0 itens Balde A na fila; a flag só afeta itens
comprovadamente Balde A, e este item não é).

### Resumo desta corrida (5ª — FALLBACK 30MIN)
- Itens na fila `status='nova'`: **1** (mesmo de sempre).
- Balde A promovidos/recomendados: **0**.
- Balde B encaminhados/reconfirmados: **1** — `3adc1b43-3276-4d0f-94ed-f2e35657a5ce`, motivo
  inalterado (agrupa `_appointment_cron_auto_no_show`, decide retenção de depósito real). Aguarda
  decisão do Danilo via Central/Telegram/"vai".
- Telegram: suprimido (anti-spam, gap 34.3min < checkpoint ~59-60min).
- Erros/bloqueios: nenhum. Nenhuma lógica de dinheiro, dispatch, pricing ou migration foi tocada.
