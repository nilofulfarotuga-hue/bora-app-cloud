---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, corrida FALLBACK_30MIN nº6)

**Gatilho:** `FALLBACK_30MIN` — orquestrador reportou 2 itens `status='nova'` parados ≥572 min.
**Verificado por SELECT direto** (hora da corrida: `2026-07-19 18:41:56 UTC`):
- `77c31fff-0330-4981-813a-f2268c6f7bbe` parado **574,7 min** (criado 09:07:13 UTC)
- `29ea4b41-1e28-420e-a7d3-2995c335d7e5` parado **514,7 min** (criado 10:07:12 UTC)

Fila `robot_suggestions WHERE status='nova'` = **exatamente estes 2 itens** — nenhum item novo
desde a corrida anterior (`fallback30min-5`, ~18:12:37 UTC).

## Balde A (leitura/falso-positivo) — recomendo aprovar
Nenhum item nesta corrida (a fila só tinha os 2 itens agrupados abaixo, ambos Balde B).

## Balde B (dinheiro real — precisa de ti)
Ambos os itens agrupam 3 funções cron na mesma `evidencia.slow_queries_top3`; regra de item
agrupado (confirmada 9x+ em corridas anteriores de 2026-07-18/19): **1 função Balde B no grupo
→ item inteiro cai em Balde B**, sem aprovação parcial.

- **`77c31fff-0330-4981-813a-f2268c6f7bbe`** (dedup_key `infra:otimizar-queries-cron-lentas`,
  reconfirmação nº10) — faz: "otimizar queries lentas de cron" citando
  `_cron_check_orphan_orders` (Balde A: só SELECT+notify) + `_cron_check_ghost_drivers`
  (Balde A: só SELECT+notify) + **`_appointment_cron_auto_no_show`** (Balde B sempre: `UPDATE
  appointments SET status='no_show', deposit_status='retained'` quando pago — decide reter
  dinheiro real do cliente). | risco: qualquer "otimização" desta função pode mudar a lógica de
  quando o depósito é retido vs devolvido.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
- **`29ea4b41-1e28-420e-a7d3-2995c335d7e5`** (dedup_key `infra:otimizar-queries-cron-lentas-v2`,
  reconfirmação nº8) — mesmo padrão exato do item acima (aparente duplicata do gerador upstream,
  já sinalizado em corridas anteriores como possível falha de dedupe do robot-b/evolution-engine,
  fora do meu mandato de roteamento). | risco: idêntico ao item acima.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram — suprimido nesta corrida
Último aviso real enviado há só **29 minutos** (18:12:37 UTC), mesmo veredito, evidência
praticamente idêntica (`slow_queries_top3` com só drift esperado de `calls` do cron rodando).
Seguindo o protocolo anti-spam já aplicado em corridas anteriores (ex. `fallback30min-4`,
gap 6min18s), **não reenviei Telegram** — só registei a reconfirmação em `admin_audit_log`
(`robot_suggestion_baldeB_reconfirmado`, ids `3b6bf864-254b-484c-9583-f4607de99031` para
`77c31fff` e `2c8d81ff-3a31-403a-8689-cc6bdd8aba1a` para `29ea4b41`, `created_at=2026-07-19
18:42:43.282105 UTC`, `telegram_enviado=false`).

## Já decidido antes desta corrida?
Não. Ambos os itens seguem `status='nova'` — nenhuma decisão do Danilo nem do
`robot_emerson_decide` mudou o estado deles desde a corrida anterior. Nenhum item novo apareceu
na fila.

## Resumo
- Balde A auto-aprovados: **0**
- Balde B a aguardar o Danilo: **2** (mesmos de sempre, reconfirmados)
- Telegram enviado: **não** (anti-spam, ver acima)
- Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA = true`, confirmado
  por SELECT nesta corrida)
