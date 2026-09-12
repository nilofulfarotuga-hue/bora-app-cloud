---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-16
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM DA FILA 🔴 (2026-07-16, FALLBACK 30MIN)

**Gatilho:** FALLBACK 30MIN — item `nova` mais antigo parado 1972+ min (~33h), gatilho normal
por item-novo pode ter falhado. Pedido: rever TODA a fila do zero, sem assumir que é o mesmo
lote de 5 Balde B conhecido (2026-07-12/13).

## Confirmação da fila — MUDANÇA REAL face às corridas anteriores
Fila `robot_suggestions status='nova'` relida via SQL direto: **9 itens**, nenhum dos quais é
o lote histórico (`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`). Verificado por
SELECT direto: esses 5 já estão `status='rejeitada'` desde **2026-07-14 05:33:09 UTC** (motivo
registado por item, ex.: "Toca bora_dispatch_maintenance (zona protegida dispatch) — requer
revisão humana"). Ou seja: o lote antigo já foi decidido/fechado; os 9 itens de hoje são um
lote **genuinamente novo**, gerado por um job periódico (categorias `catalogo`/`performance`/
`marcacoes`/`operacao_pedidos`/`teste-circuito`) entre 2026-07-14 21:07 e 2026-07-16 05:59 UTC.

## Balde A (leitura/falso-positivo) — AUTO-APROVADOS (7)
`aprovador_vermelho_auto_baldeA` = **true** confirmado via SELECT direto → auto-aprovação aplicada
(`UPDATE robot_suggestions SET status='aprovada'` + `admin_audit_log` action
`robot_suggestion_approved_baldeA` por item):

- **`6a38f26a`** — Priorizar revisão de backlog de produtos (2890). Catálogo puro, evidência =
  contagem read-only, proposta = plano de revisão faseada. Sem dinheiro/dispatch.
- **`f25a38c1`** — Adicionar fotos a produtos sem imagem (60). Proposta explícita "sem alterar
  código de produção". Sem dinheiro/dispatch.
- **`f0651a3c`** — Categorizar produtos sem categoria (3073). Idem acima.
- **`1097b4a4`** — Otimizar query `_cron_check_orphan_orders`. Prova fresca:
  `pg_get_functiondef` lido agora mostra só `SELECT` sobre `orders` + `PERFORM
  notify_admin_event`; zero UPDATE/DELETE, zero escrita em orders/wallets/ledger, zero Edge Fn
  de cobrança. Confirma precedente de 2026-07-12 (mesma função, item `670a4840`).
- **`bfe65453`** — Otimizar query `_cron_check_ghost_drivers`. Prova fresca (função nunca antes
  triada): `pg_get_functiondef` mostra só `SELECT` sobre `drivers` + `PERFORM
  notify_admin_event`; zero UPDATE/DELETE, zero dinheiro, zero chamada ao dispatch-engine.
- **`b91ec56b`** — Notificar motorista sem token de push para reinstalar app. Ação de
  notificação pura, evidência = contagem (count=1). Sem dinheiro/dispatch.
- **`1242c17e`** — TESTE 13d do circuito (auto-descrito como falso-positivo do filtro T3:
  menciona "Stripe" mas evidência = `tipo:falso-positivo-teste`, proposta = verificação
  READ-ONLY). Resultado esperado já documentado no próprio item.

## Balde B (dinheiro real — precisa do Danilo) — NOVOS (2)

- **`8c9e9d08`** — Otimizar query `_appointment_cron_auto_no_show`.
  Faz: a mesma função (lida agora, fresca) faz `UPDATE appointments SET deposit_status =
  'retained'` quando marca no-show — decide reter dinheiro do cliente. Precedente idêntico
  (`abeca5d7`, rejeitado 2026-07-14) já classificou esta função como Balde B sempre.
  Risco: qualquer edição, mesmo "otimização", mexe numa função de zona protegida dinheiro.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`20248533`** — Monitorizar e reduzir taxa de no-show em agendamentos.
  Faz: propõe medidas incluindo "políticas de depósito" — mudança de política de depósito é
  dinheiro real do cliente/parceiro.
  Risco: qualquer política de retenção nova é decisão financeira, não técnica.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Ambos ficam `status='nova'` (não tocados) — surfaçados via `admin_audit_log` action
`robot_suggestion_baldeB_surfaced` (novo, `item_novo:true`), à espera de decisão na
`AdminRobotSuggestionsScreen`/Telegram.

## Resumo para Telegram
```
🚦 Aprovador-vermelho — 2026-07-16 (FALLBACK 30MIN)
Fila nova = 9 itens (lote ANTIGO de 5 já foi decidido em 2026-07-14, rejeitado). Todos os 9
são novos.
✅ 7 Balde A auto-aprovados (catálogo/fotos/categorias/2 otimizações de query read-only/
   notificação de push/teste de circuito) — flag auto_baldeA=true.
🔴 2 Balde B ficam para ti: otimizar _appointment_cron_auto_no_show (mexe em retenção de
   depósito) e reduzir taxa de no-show (propõe política de depósito). Precisam da tua decisão
   em AdminRobotSuggestionsScreen.
```

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado), confirmado via SELECT
direto antes de cada auto-aprovação.

## Auditoria
7× `admin_audit_log` action `robot_suggestion_approved_baldeA` (um por item, `created_at`
~2026-07-16, motivo individual citado acima) + 2× action `robot_suggestion_baldeB_surfaced`.
Fila `nova` final confirmada por SELECT: só os 2 itens de Balde B permanecem.

## HANDOFF
→ `bibliotecario-cerebro`, escopo: `agente:aprovador-vermelho`. Atualizar
`aprovador-vermelho-triagem.md`: (1) lote histórico de 5 (`268aad47` etc.) foi REJEITADO em
2026-07-14 05:33:09 UTC — já não está em `nova`, parar de reconfirmá-lo; (2) `_cron_check_ghost_drivers`
confirmado Balde A (read-only, mesma família de `_cron_check_orphan_orders`); (3) `_appointment_cron_auto_no_show`
reconfirmado Balde B mesmo quando a proposta é só "otimizar query" — qualquer toque nessa função
é Balde B por escrever `deposit_status`.
