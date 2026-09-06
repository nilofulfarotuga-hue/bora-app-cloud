---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, gatilho FALLBACK 30MIN, 2ª disparada)

## Contexto do gatilho
Rede de segurança de 30 min disparou de novo: item `nova` mais antigo parado 72+ min
(`count=2` reportado pelo gatilho — confirmado por SELECT direto). Esta é a **5ª corrida** de
hoje sobre esta fila (após 09:12, 09:57, 10:18/10:07 — ver relatórios anteriores de 2026-07-19).

## Fila lida (SELECT direto, `status='nova'`)
2 itens — **os mesmos 2 já triados nas corridas anteriores de hoje**. Nenhum item genuinamente
novo. `platform_settings.aprovador_vermelho_auto_baldeA = true` (confirmado).

## Triagem

**`77c31fff-0330-4981-813a-f2268c6f7bbe`** (dedup_key `infra:otimizar-queries-cron-lentas`,
criado 09:07 UTC) — **Balde B, reconfirmação nº 4 hoje.** Item agrupa 3 funções: 2 isoladamente
Balde A (`_cron_check_orphan_orders`, `_cron_check_ghost_drivers` — só leitura) + 1 sempre Balde B
(`_appointment_cron_auto_no_show` — decide reter/devolver depósito do cliente no-show). Regra de
item agrupado (confirmada 7x antes): sem aprovação parcial, item inteiro cai em B.

**`29ea4b41-1e28-420e-a7d3-2995c335d7e5`** (dedup_key `infra:otimizar-queries-cron-lentas-v2`,
criado 10:07 UTC) — **Balde B, reconfirmação nº 2 hoje.** Mesma evidência/agrupamento, mesma regra.

Nenhum item isoladamente Balde A nesta corrida — 0 auto-aprovados.

## Telegram — NÃO enviado nesta corrida
Ambos os itens já foram avisados via Telegram em corridas anteriores de hoje (09:12, 09:57, 10:18)
sem qualquer prova nova ou mudança de evidência. Por regra ("não repetir aviso sem prova nova"),
esta corrida regista **reconfirmação silenciosa** em `admin_audit_log`
(`action='robot_suggestion_baldeB_reconfirmado'`, ids `985b3a37-5333-4d4b-bbcc-69987f0f3196` e
`9bcdca61-9451-4612-ae11-081e7671965f`, `created_at=2026-07-19 10:38:03 UTC`,
`telegram_enviado=false` em ambos, com motivo explícito). Ambos os itens permanecem `status='nova'`
— aguardam decisão humana no `AdminRobotSuggestionsScreen` ou "vai" direto no Telegram já enviado.

## Resumo
```
🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, FALLBACK 30MIN #2)
   Balde A (leitura/falso-positivo) — recomendo aprovar:
     (nenhum item isolado Balde A nesta corrida — 0 auto-aprovados)
   Balde B (dinheiro real — precisa de ti):
     • 77c31fff — otimizar query cron agrupada | risco: _appointment_cron_auto_no_show
       decide reter/devolver depósito — reconfirmação silenciosa 4/hoje (Telegram já enviado antes)
     • 29ea4b41 — mesma otimização (item v2) | risco: idem — reconfirmação silenciosa 2/hoje
       (Telegram já enviado antes)
   Auto-Balde-A: ligado (aprovador_vermelho_auto_baldeA=true) — sem efeito, 0 itens elegíveis.
   Telegram: nenhum novo (sem prova nova desde a última corrida às 10:18 UTC).
```

## Handoff
`bibliotecario-cerebro` — `escopo: agente:aprovador-vermelho` — acrescentar linha 2026-07-19
FALLBACK 30MIN #2 a `permanente/procedural/aprovador-vermelho-triagem.md`: mesmos 2 itens Balde B,
8ª/9ª ocorrência geral da regra de item agrupado, sem novo aprendizado — reforça que o watchdog
de 30 min está a funcionar como desenhado (acorda o agente mesmo sem item novo), e que a
"pausa" destes 2 itens em `nova` continua a ser comportamento esperado (não é bug), até o Danilo
decidir.
