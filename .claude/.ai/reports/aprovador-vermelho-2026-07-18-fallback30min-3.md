---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-18
---

# Aprovador-Vermelho — corrida FALLBACK 30MIN (2026-07-18, ~21:12 UTC)

Gatilho: `FALLBACK 30MIN` — item `nova` mais antigo parado 62+ min (gatilho normal por
item-novo pode ter falhado).

## Fila (SELECT direto, `ojykpzwqrtusfeakzrna`)
- `status='nova'`: **1 item** (confirmado por COUNT + SELECT, idêntico às 4 corridas anteriores
  do mesmo dia — zero itens novos, zero duplicados, dedupe não necessário).

## Triagem
- **`9db0124a-964e-4b67-b098-c81a57c576a4`** — "Otimizar queries lentas de cron jobs"
  (categoria performance, nível 3, `dedup_key performance:otimizar-cron-queries-lentas`,
  criado 2026-07-18 20:07:15 UTC, idade ~65 min no momento desta triagem).
  Evidência: agrupa `_cron_check_orphan_orders()` + `_appointment_cron_auto_no_show()` +
  `_cron_check_ghost_drivers()` (as 3 queries mais lentas do cron).
  **Veredito: Balde B (item inteiro), reavaliado do zero.** Prova positiva reconferida:
  `_cron_check_orphan_orders()` e `_cron_check_ghost_drivers()` são só `SELECT` + `notify_admin_event`
  (Balde A isoladamente), mas `_appointment_cron_auto_no_show()` executa
  `UPDATE appointments SET status='no_show', deposit_status=CASE WHEN deposit_status='paid'
  THEN 'retained' ELSE deposit_status END` — escreve dinheiro real (retenção de depósito do
  cliente). Pela regra de item agrupado (confirmada 4x independentes em 2026-07-18, ver
  `permanente/procedural/aprovador-vermelho-triagem.md`), quando uma linha da fila agrupa função
  Balde B com funções Balde A, **o item inteiro** cai em Balde B — não há aprovação parcial.
  Esta é a **5ª reconfirmação no mesmo dia**, mesmo veredito, zero mudança na prova.
  - Auto-Balde-A: não aplicável (item não é puro Balde A; flag `aprovador_vermelho_auto_baldeA=true`
    confirmada por SELECT direto, sem efeito prático aqui).
  - Ação: NÃO promovido, NÃO auto-aprovado. `admin_audit_log` id
    `344f7fc7-45d5-4067-9bbb-530f90b3cb61` (action `robot_suggestion_baldeB_reconfirmado`,
    `reconfirmacao_numero=5`, `created_at=2026-07-18 21:12:43 UTC`).
  - Telegram: **não reenviado** — mesmo item já surfacado com sucesso na 3ª (20:28 UTC) e 4ª
    (20:42 UTC) corridas do mesmo dia; reenviar pela 3ª vez em ~45 min sem nenhuma mudança de
    prova seria spam (lição `licao-spam-ordens-autoreferencial.md`). Resumo pronto para Telegram
    abaixo, para o Danilo decidir/reenviar se quiser.

## Balde A
Nenhum item Balde A nesta corrida (fila `nova` = só o item acima). Nada para auto-aprovar.

## Resumo pronto para Telegram (não enviado nesta corrida, reenvio opcional)
```
🚦 Aprovador-vermelho — fila vermelha (5ª reconfirmação hoje)
Item: "Otimizar queries lentas de cron jobs" (9db0124a)
Balde B — precisa de ti: agrupa 2 funções só-leitura + _appointment_cron_auto_no_show,
que RETÉM depósito do cliente (dinheiro real). Sem aprovação parcial.
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico (ou rejeita).
```

## Flag
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (confirmado por SELECT).

## Nota
Nenhuma lógica de dinheiro tocada — só roteamento (leitura + `admin_audit_log`). Não editei
`_appointment_cron_auto_no_show`, `pricing_service`, `dispatch_engine`, migrations, nem
`platform_settings` financeiros. RPC `robot_emerson_decide`/reject não chamada (nada para
aprovar/rejeitar via essa via nesta corrida).

## Handoff — bibliotecario-cerebro
`escopo: agente:aprovador-vermelho`. Nada de novo a gravar no Cérebro — 5ª reconfirmação
idêntica às 4 anteriores do mesmo dia, já documentadas em
`permanente/procedural/aprovador-vermelho-triagem.md` (linha 2026-07-18). Se uma 6ª corrida
repetir o mesmo veredito sem o Danilo ter decidido, considerar atualizar essa linha com a
contagem consolidada em vez de criar mais um relatório separado.
