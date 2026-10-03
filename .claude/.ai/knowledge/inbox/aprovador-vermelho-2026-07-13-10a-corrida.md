---
escopo: agente:aprovador-vermelho
data: 2026-07-13
corrida: 10a (gatilho FALLBACK_30MIN)
estado: atual
---

# Aprovador-vermelho — 10ª corrida (2026-07-13, FALLBACK 30MIN)

## Contexto do gatilho
Fallback de 30 minutos: item `nova` mais antigo parado ≥30 min sem triagem normal (watermark).
Sem canal Telegram/Danilo disponível nesta execução (executor headless). Ordem: re-triar TODA
a fila `status='nova'` do zero, pela prova, não pelo histórico.

## Resultado
Fila `robot_suggestions` status='nova' reconfirmada via `execute_sql` (MCP Supabase, project
`ojykpzwqrtusfeakzrna`) — **exatamente o mesmo lote de 5 itens** das 9 corridas anteriores
(2026-07-12 11:26 UTC → 2026-07-13 00:06 UTC). Zero itens novos, zero resolvidos/expirados,
zero duplicados (5 `dedup_key` distintos — dedupe não se aplica aqui). Flag
`aprovador_vermelho_auto_baldeA` confirmada `true` (consultada em `platform_settings` antes
da triagem, não é suposição).

| id | categoria | nível | título | idade |
|---|---|---|---|---|
| `268aad47` | infra_cron | 3 | otimizar `bora_dispatch_maintenance()` | ~29764 min (~20,7 dias) |
| `abeca5d7` | infra_cron | 3 | otimizar `_appointment_cron_auto_no_show()` | ~29764 min (~20,7 dias) |
| `85d8911b` | operacao_pedidos | 3 | reatribuição automática de pedidos presos (dispatch) | ~1564 min (~26h) |
| `d9df69ed` | operacao_pedidos | 3 | cancelamentos por `dispatch_safety_timeout` | ~784 min (~13h) |
| `bea503a3` | marcacoes | 3 | taxa no-show 16,67% / política de depósito | ~784 min (~13h) |

Todos `nivel=3` (o próprio sistema já os marca como camada dinheiro — N3 🔴 = só propõe).

## Triagem (prova positiva, do zero — não herdada do histórico)
Todos confirmados **Balde B** — cada um tem prova positiva de escrita/lógica protegida, não
é leitura nem falso-positivo de filtro:
- `268aad47` — propõe otimizar `bora_dispatch_maintenance()`: a função (confirmada por leitura
  direta de `supabase/migrations/20260531064411_fix_dispatch_maintenance_net_http_post.sql`)
  faz `UPDATE orders` (cancela pagamentos abandonados), aplica 2 TTLs de auto-cancelamento do
  dispatch e chama `net.http_post` para a Edge Function `dispatch-engine`. Coração do motor de
  dispatch + cancelamento de pagamento. Zona vermelha.
- `abeca5d7` — propõe otimizar `_appointment_cron_auto_no_show()`: escreve
  `deposit_status='retained'` quando aplicável — decide reter dinheiro do cliente. Zona vermelha.
- `85d8911b` — propõe reatribuição automática com TTL para pedidos presos: nova lógica de
  dispatch/matching (escrita em `orders`/atribuição de motorista). Zona vermelha.
- `d9df69ed` — investigar cancelamentos por `dispatch_safety_timeout`: mecanismo TTL do próprio
  `dispatch_engine`, liga a cancelamento de pedido/pagamento. Zona vermelha.
- `bea503a3` — propõe política de depósito/pré-pagamento para reduzir no-show: mexe em
  `deposit_status`/cobrança de parceiros de serviços. Zona vermelha.

Nenhum item passou a prova de "só leitura, sem escrita, sem charge, sem Edge Function que
cobra" → **0 Balde A, 0 auto-aprovados** nesta corrida (consistente com as 9 corridas anteriores
sobre o mesmo lote).

## Ação tomada
- Nenhuma mudança de roteamento (fila idêntica às corridas 3a-9a, decisão idêntica).
- Nenhuma lógica de dinheiro/dispatch/RLS tocada — só leitura (`execute_sql` SELECT) + 1 INSERT
  de auditoria (rasto).
- Telegram: **não enviado** — mesmo lote já surfaçado 9x hoje ao Danilo; reenviar seria spam.
  Sem canal Telegram disponível nesta execução de qualquer forma (executor headless).
- Reconfirmação registada em `admin_audit_log` (id `54eb62fd-89be-4455-9a22-6a03c0f338d6`,
  action=`reconfirmacao_fila_balde_b_sem_novidade`, entity_type=`robot_suggestions`, 5 ids +
  corrida=10a + telegram_enviado=false).

## Balde B — aguarda Danilo (resumo para revisão manual)
Todos os 5 itens ficam em `status='nova'`, sem alteração. Quando o Danilo tiver disponível o
canal (Telegram/Central), cada um precisa do aviso:

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

(aplicável a cada um dos 5 itens acima — nenhum foi aplicado, só a proposta existe na fila)

## Anomalia (já reportada nas corridas 8a e 9a — agora com 3 registos consecutivos)
`FALLBACK_30MIN` continua a disparar em cadência curta (esta corrida: ~6 min depois da 9a)
sobre a mesma fila inalterada. Não é risco de dinheiro — Balde B nunca promovido, prova
positiva reavaliada do zero em cada corrida — mas é execução de agente desperdiçada e ruído
crescente em `admin_audit_log`. Correção sugerida (fora do mandato de roteamento deste agente):
cooldown por-lote no `hermes-aprovador-vermelho.sh` (não re-disparar se o conjunto de ids Balde B
pendentes for idêntico ao da última corrida há <2h, ou usar backoff exponencial). Encaminhar a
`maestro-autonomia` ou ao Danilo — não é decisão de aprovação e este agente não edita o script
do gatilho (fora da fronteira "só roteamento de aprovação").

## HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: agente:aprovador-vermelho
tema-alvo: `permanente/procedural/aprovador-vermelho-triagem.md` (tabela "Histórico de corridas")
conteudo: 2026-07-13, corrida 10a (FALLBACK 30MIN), fila `nova` idêntica às corridas 2026-07-12
(5 itens: `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), todas reconfirmadas
Balde B com prova positiva reavaliada do zero, 0 auto-aprovações. Anomalia de cadência do
FALLBACK_30MIN agora com 3 registos consecutivos (8a, 9a, 10a) sem correção — recomendação de
cooldown/backoff no script segue pendente, encaminhada a `maestro-autonomia`/Danilo.

## Ponteiros
`zonas-protegidas.md`, `business-rules.md`, `aprovador-vermelho-triagem.md`,
`project_aprovador_vermelho_central.md` (memória),
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-12-{3a,4a,5a,6a}-corrida.md`,
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-13-{7a,8a,9a}-corrida.md`.
