---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# APROVADOR-VERMELHO — Triagem FALLBACK 30MIN (2026-07-19, ~18:12 UTC)

## Gatilho
`FALLBACK 30MIN` — item `nova` mais antigo (`77c31fff`) parado há 542+ minutos no alerta
recebido; confirmado por SQL fresco: **545,4 min** (`77c31fff`, criado 09:07:13 UTC) e
**485,4 min** (`29ea4b41`, criado 10:07:12 UTC). Gap grande desde a última corrida documentada
(`aprovador-vermelho-2026-07-19-corrida-11h52.md`, ~11:53 UTC) — quase 6h20min sem triagem,
consistente com o backoff exponencial (teto `MAX_BACKOFF_MIN=360`) descrito em
`permanente/procedural/aprovador-vermelho-triagem.md`.

## Contagem real
`SELECT ... WHERE status='nova'` devolveu **2 itens** (o "2" do alerta confere, o "542+" também
confere — item mais antigo está a 545 min, não 542, mas dentro da margem esperada entre o disparo
do alerta e a execução desta triagem).

## Itens e triagem

### 1. `77c31fff-0330-4981-813a-f2268c6f7bbe` — Balde B
- **dedup_key:** `infra:otimizar-queries-cron-lentas` · **categoria:** `infra_cron`
- **Título:** "Investigar e otimizar queries lentas de cron"
- **Evidência:** top-3 queries lentas citadas: `_cron_check_orphan_orders` (65,4ms),
  `_appointment_cron_auto_no_show` (63,5ms), `_cron_check_ghost_drivers` (61,5ms)
- **Prova positiva (corpo relido fresco via `pg_get_functiondef` nesta corrida):**
  - `_cron_check_orphan_orders` — só `SELECT orders` + `PERFORM notify_admin_event`. Zero escrita. **Balde A isolado.**
  - `_cron_check_ghost_drivers` — só `SELECT drivers` + `PERFORM notify_admin_event`. Zero escrita. **Balde A isolado.**
  - `_appointment_cron_auto_no_show` — `UPDATE appointments SET status='no_show', deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END`. **Decide reter depósito real do cliente. Balde B sempre.**
- **Regra de item agrupado** (confirmada 2026-07-18, 8x em 2026-07-19 anteriores): a linha da
  fila agrupa as 3 funções numa única evidência — não há aprovação parcial. Item inteiro cai em
  **Balde B**.
- **Ação:** mantido `status='nova'`. Reconfirmação nº9 registada em `admin_audit_log`
  (`id=e37ba74a-1c29-4a20-b5d1-c36707574b5d`, `action=robot_suggestion_baldeB_reconfirmado`).

### 2. `29ea4b41-1e28-420e-a7d3-2995c335d7e5` — Balde B
- **dedup_key:** `infra:otimizar-queries-cron-lentas-v2` · **categoria:** `infra_cron`
- Mesmo padrão agrupado (mesma evidência top-3), variante `-v2` do item acima (possível não-dedupe
  do gerador upstream, já anotado como observação fora do mandato de triagem).
- **Ação:** mantido `status='nova'`. Reconfirmação nº7 registada em `admin_audit_log`
  (`id=235da2f0-fa1f-466b-99a5-267970d45a3c`).

## Balde A
Nenhum item Balde A nesta corrida (fila só tinha os 2 itens agrupados acima, ambos Balde B).

## Telegram
Enviado com sucesso via bridge SSH PC→VPS (`ssh id_ed25519_vps` → `docker exec hermes send -t
telegram`) — output real: `Sent to telegram home channel (chat_id: 6731890157)`. Ambas as
entradas de `admin_audit_log` atualizadas com `telegram_enviado=true` (confirmado por
UPDATE...RETURNING).

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA = true` (confirmado por SELECT antes da
triagem) — irrelevante nesta corrida pois não houve item Balde A.

## Zonas/tabelas tocadas
- **Leitura:** `robot_suggestions`, `platform_settings`, `pg_proc` (via `pg_get_functiondef`).
- **Escrita (só auditoria, fora da Trava):** `admin_audit_log` (2 INSERT + 2 UPDATE de metadado
  `telegram_enviado`). **Nenhuma** escrita em `robot_suggestions`, `appointments`, `orders`,
  `wallets`, `ledger_entries`, dispatch ou pricing.

## Handoff
`bibliotecario-cerebro` — escopo `agente:aprovador-vermelho` — atualizar
`permanente/procedural/aprovador-vermelho-triagem.md` (tabela "Histórico de corridas") com esta
9ª/7ª reconfirmação; nenhum aprendizado novo de triagem, só reforço do padrão já documentado.
