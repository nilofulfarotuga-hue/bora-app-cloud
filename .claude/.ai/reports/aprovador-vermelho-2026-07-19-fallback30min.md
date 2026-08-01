---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, gatilho FALLBACK 30MIN)

## Contexto do gatilho
Rede de segurança de 30 minutos: o item `nova` mais antigo estava parado ~49 min (criado
`2026-07-19 09:07:13.491514 UTC`, corrida a `09:57:20 UTC`) sem decisão — o watchdog disparou
review manual de TODA a fila `nova`, independente do watermark, exatamente como desenhado em
`.claude/scripts/hermes-aprovador-vermelho.sh` (ver `permanente/procedural/aprovador-vermelho-triagem.md`,
secção "Rede de segurança de 30 minutos").

## Fila lida
`SELECT ... FROM robot_suggestions WHERE status='nova' ORDER BY created_at ASC` → **1 item**, o
mesmo já triado na corrida anterior de hoje (relatório `aprovador-vermelho-2026-07-19.md`,
surfaced `09:12:16 UTC`). Nenhum item novo apareceu entretanto. Sem risco de teto 30 (1/30).

## Item reconfirmado

**`77c31fff-0330-4981-813a-f2268c6f7bbe`** — "Investigar e otimizar queries lentas de cron"
(`dedup_key: infra:otimizar-queries-cron-lentas`, `nivel=3`, `severidade=4`, `categoria=infra_cron`)

Prova positiva reavaliada do zero (não copiada da corrida anterior): a evidência agrupa 3 funções —
`_cron_check_orphan_orders()` e `_cron_check_ghost_drivers()` (isoladamente Balde A: só `SELECT` +
`notify_admin_event`, zero escrita, zero dinheiro) e `_appointment_cron_auto_no_show()`
(**Balde B sempre**: `UPDATE appointments SET status='no_show', deposit_status = CASE WHEN
deposit_status='paid' THEN 'retained' ELSE deposit_status END` — decide reter ou devolver dinheiro
do cliente). Regra de item agrupado (confirmada em 4 corridas de 2026-07-18 + 1ª corrida de hoje):
**não há aprovação parcial** — o item inteiro cai em Balde B.

**Classificação: Balde B (reconfirmado, 2ª vez hoje).** Não é bug o item continuar `nova` — é o
comportamento esperado até o Danilo decidir (ver lição "item Balde B parado não é bug" no ficheiro
de triagem).

**Ação:** NÃO auto-aprovado (nem auto, nem manual). Reconfirmação registada em `admin_audit_log`:
`action='robot_suggestion_baldeB_reconfirmado'`, `id=6862e0d6-3694-4685-be91-37502d742f45`,
`created_at=2026-07-19 09:57:20.541483 UTC`, `details.reconfirmacao_numero=2`,
`details.surfaced_anterior_id=454cc80e-1e59-40f4-99a9-8835a6d7eb70`. Novo aviso Telegram enviado
via bridge SSH PC→VPS (`hermes send -t telegram`) — confirmado `Sent to telegram home channel
(chat_id: 6731890157)`. Item permanece `status='nova'`.

## Formato de output
```
Balde A (leitura/falso-positivo) — recomendo aprovar:
  (nenhum nesta corrida)
Balde B (dinheiro real — precisa de ti):
  • 77c31fff-0330-4981-813a-f2268c6f7bbe — faz: otimizar 3 queries de cron lentas (item agrupado)
    | risco: uma das 3 funções (_appointment_cron_auto_no_show) decide reter/devolver depósito
    de cliente; edição de query pode alterar essa lógica sem querer. [reconfirmação 2/hoje]
    ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
Auto-Balde-A: ligado (platform_settings.aprovador_vermelho_auto_baldeA=true) — sem efeito nesta
corrida porque não houve item Balde A puro.
```

## Handoff
`bibliotecario-cerebro` — `escopo: agente:aprovador-vermelho` — acrescentar linha ao histórico de
corridas em `permanente/procedural/aprovador-vermelho-triagem.md` (2026-07-19 FALLBACK 30MIN,
mesmo item `77c31fff`, reconfirmação 2/2 do dia, mesma regra de item agrupado — 6ª ocorrência geral
confirmada). Nenhum novo aprendizado de triagem; só reforça padrão já documentado.
