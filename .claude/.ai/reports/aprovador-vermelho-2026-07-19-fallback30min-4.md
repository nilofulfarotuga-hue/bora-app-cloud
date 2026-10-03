---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, FALLBACK 30MIN #4)

**Gatilho:** FALLBACK 30MIN — item mais antigo (`77c31fff`) parado 102+ min no momento do disparo
(confirmado por SELECT: 115,46 min desde `created_at=2026-07-19 09:07:13.49 UTC` até `now()=11:03:51 UTC`).
Fila `robot_suggestions status='nova'` recontada = **2 itens** (confirmado por COUNT direto, sem itens
novos surgidos desde a corrida anterior).

## Achado principal: esta corrida sobrepôs-se quase totalmente à corrida FALLBACK anterior
A última reconfirmação registada em `admin_audit_log` era de **10:57:33 UTC** — só **6min18s** antes
desta corrida (`now()=11:03:51 UTC`, confirmado por `SELECT now() - '2026-07-19 10:57:33...'`). Zero
evidência nova nos dois itens (payload `evidencia.slow_queries_top3` idêntico ao das corridas
anteriores). Aplicada a regra #4 do gatilho: **não re-litigar do zero** — só confirmar e seguir.

## Fila (2 itens, ambos Balde B — mesmo veredito de 6+ corridas anteriores)

### Balde A (leitura/falso-positivo) — recomendo aprovar
Nenhum. Fila = 0 itens Balde A nesta corrida.

### Balde B (dinheiro real — precisa do Danilo)
- **`77c31fff-0330-4981-813a-f2268c6f7bbe`** — "Investigar e otimizar queries lentas de cron"
  (dedup_key `infra:otimizar-queries-cron-lentas`, criado 09:07:13 UTC).
  Faz: propõe otimizar 3 queries de cron lentas agrupadas na mesma evidência —
  `_cron_check_orphan_orders` (Balde A, só SELECT+notify) + `_cron_check_ghost_drivers`
  (Balde A, só SELECT+notify) + **`_appointment_cron_auto_no_show`** (Balde B sempre — `UPDATE
  appointments SET status='no_show', deposit_status=...'retained'`, decide reter ou devolver
  depósito de cliente).
  Risco: **regra de item agrupado** (confirmada 7+ vezes desde 2026-07-18) — quando uma única linha
  da fila junta funções de balde diferente, o item inteiro cai em Balde B, sem aprovação parcial.
  Reconfirmação nº6 hoje, idêntica às 5 anteriores.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
- **`29ea4b41-1e28-420e-a7d3-2995c335d7e5`** — mesmo padrão, variante "v2" (dedup_key
  `infra:otimizar-queries-cron-lentas-v2`, criado 10:07:12 UTC, mesma evidência top-3).
  Reconfirmação nº4 hoje, idêntica.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram
**Suprimido nesta corrida** — última reconfirmação idêntica há só 6min18s (10:57:33 UTC), sem
evidência nova. Enviar de novo seria ruído puro (protocolo anti-spam já documentado no Cérebro,
`aprovador-vermelho-triagem.md`). Último envio real bem-sucedido: 10:18:29 UTC (45 min atrás).

## Registo (auditoria)
2 novas linhas em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`):
- `76eb3878-e294-42e2-b217-e91e54b120d9` (`77c31fff`, `reconfirmacao_numero=6`, `created_at=2026-07-19 11:04:21.54 UTC`)
- `9a09452f-5e87-41ea-86e7-5a3781fa712c` (`29ea4b41`, `reconfirmacao_numero=4`, `created_at=2026-07-19 11:04:21.54 UTC`)

Confirmado por `RETURNING` real da query INSERT (não fabricado).

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado, confirmado por SELECT direto).
Sem efeito nesta corrida (0 itens Balde A na fila).

## Observação para quem revisitar (não é decisão de triagem)
Esta corrida disparou apenas 6min18s depois da corrida anterior (10:57 UTC), bem abaixo do
`STALE_MIN=30min` documentado em `loops.md`/`aprovador-vermelho-triagem.md`. Consistente com a
"Anomalia conhecida" já registada no Cérebro: o backoff exponencial do FALLBACK 30MIN está
corrigido no ficheiro canónico do repo mas **pendente de deploy** em
`/usr/local/bin/hermes-aprovador-vermelho.sh` na VPS — por isso o gatilho continua a disparar mais
frequentemente do que o esperado enquanto o lote de 2 itens Balde B não for decidido pelo Danilo.
Não é uma nova capacidade nem uma nova lição de triagem; só reforça a pista já arquivada.
