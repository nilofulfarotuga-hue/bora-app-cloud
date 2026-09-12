---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — Triagem da fila 🔴 (2026-07-19)

## Fila lida
`SELECT ... FROM robot_suggestions WHERE status='nova' ORDER BY created_at ASC` → **1 item**
(coincide com o watermark do gatilho: `newest=2026-07-19T09:07:13.491514+00:00`, `count=1`).
Nenhum acúmulo — sem risco de teto 30.

## Item triado

**`77c31fff-0330-4981-813a-f2268c6f7bbe`** — "Investigar e otimizar queries lentas de cron"
(`dedup_key: infra:otimizar-queries-cron-lentas`, `nivel=3`, `severidade=4`, `categoria=infra_cron`)

Evidência (top 3 queries lentas): `_cron_check_orphan_orders()` (140 chamadas, 65.4ms média),
`_appointment_cron_auto_no_show()` (3885 chamadas, 63.5ms média), `_cron_check_ghost_drivers()`
(139 chamadas, 61.5ms média).

**Classificação: Balde B (item agrupado)** — mesma regra confirmada em 4 corridas independentes
de 2026-07-18 (ver `permanente/procedural/aprovador-vermelho-triagem.md`): a linha agrupa 3
funções, das quais 2 são isoladamente Balde A (`_cron_check_orphan_orders` e
`_cron_check_ghost_drivers` — só `SELECT` + `notify_admin_event`, zero escrita) mas a 3ª,
`_appointment_cron_auto_no_show`, é **Balde B sempre**: `UPDATE appointments SET status='no_show',
deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END` — decide
reter ou devolver dinheiro do cliente. Qualquer edição a esta função (mesmo "só otimizar a query")
toca zona protegida de dinheiro. **Não há aprovação parcial de uma linha da fila** — o item
inteiro fica Balde B.

**Ação:** NÃO auto-aprovado. Encaminhado ao Danilo via Telegram (bridge SSH PC→VPS,
`hermes send -t telegram`) — confirmado `Sent to telegram home channel (chat_id: 6731890157)`.
Registado em `admin_audit_log` (`action='robot_suggestion_baldeB_surfaced'`, id
`454cc80e-1e59-40f4-99a9-8835a6d7eb70`, `created_at=2026-07-19 09:12:16 UTC`). Item permanece
`status='nova'` — aguarda decisão humana (AdminRobotSuggestionsScreen ou "vai" no Telegram).

## Formato de output
```
Balde A (leitura/falso-positivo) — recomendo aprovar:
  (nenhum nesta corrida)
Balde B (dinheiro real — precisa de ti):
  • 77c31fff-0330-4981-813a-f2268c6f7bbe — faz: otimizar 3 queries de cron lentas (item agrupado)
    | risco: uma das 3 funções (_appointment_cron_auto_no_show) decide reter/devolver depósito
    de cliente; edição de query pode alterar essa lógica sem querer.
    ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
Auto-Balde-A: ligado (platform_settings.aprovador_vermelho_auto_baldeA=true) — sem efeito nesta
corrida porque não houve item Balde A puro.
```

## Handoff
`bibliotecario-cerebro` — `escopo: agente:aprovador-vermelho` — atualizar histórico de corridas em
`permanente/procedural/aprovador-vermelho-triagem.md` com esta linha (2026-07-19, item
`77c31fff`, mesma regra de item agrupado, 5ª ocorrência confirmada do padrão).
