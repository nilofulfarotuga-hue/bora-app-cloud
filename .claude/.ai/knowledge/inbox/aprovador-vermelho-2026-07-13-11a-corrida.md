---
escopo: agente:aprovador-vermelho
data: 2026-07-13
corrida: 11a (gatilho FALLBACK_30MIN)
estado: atual
---

# Aprovador-vermelho — 11ª corrida (2026-07-13, FALLBACK 30MIN)

## Contexto do gatilho
Fallback de 30 minutos: item `nova` mais antigo parado ≥30 min sem triagem normal (watermark).
Ordem: re-triar TODA a fila `status='nova'` do zero, pela prova, não pelo histórico das 10
corridas anteriores (2026-07-12 → 2026-07-13).

## Resultado
Fila `robot_suggestions` status='nova' reconfirmada via `execute_sql` (MCP Supabase, project
`ojykpzwqrtusfeakzrna`) — **exatamente o mesmo lote de 5 itens** das 10 corridas anteriores.
Zero itens novos, zero resolvidos/expirados. Flag `platform_settings.aprovador_vermelho_auto_baldeA`
reconfirmada `true` antes da triagem (consulta direta, não suposição).

| id | categoria | nível | título |
|---|---|---|---|
| `268aad47` | infra_cron | 3 | otimizar `bora_dispatch_maintenance()` |
| `abeca5d7` | infra_cron | 3 | otimizar `_appointment_cron_auto_no_show()` |
| `85d8911b` | operacao_pedidos | 3 | reatribuição automática de pedidos presos (dispatch) |
| `d9df69ed` | operacao_pedidos | 3 | cancelamentos por `dispatch_safety_timeout` |
| `bea503a3` | marcacoes | 3 | taxa no-show 16,67% / política de depósito |

Todos `nivel=3` (o próprio sistema já os marca como camada dinheiro).

## Triagem (prova positiva, do zero — evidência lida de novo, não herdada)
Reli `evidencia`/`proposta`/`payload_execucao` (este último `null` nos 5 — nenhum tem SQL/patch
pronto para aplicar, só diagnóstico + proposta em texto) de cada item com olhos frescos:

- `268aad47` — evidência é `pg_stat_statements` puro (420 chamadas, 106,7ms médios) — leitura
  de performance, **mas** a proposta é "otimizar `bora_dispatch_maintenance()`", função que
  (confirmada anteriormente por leitura de `20260531064411_fix_dispatch_maintenance_net_http_post.sql`)
  faz `UPDATE orders` + chama `net.http_post` para a Edge Function `dispatch-engine`. Sem prova
  positiva de "sem escrita" na mudança proposta → **Balde B**.
- `abeca5d7` — mesma forma (evidência = performance), mas a função grava `deposit_status='retained'`
  (retém dinheiro do cliente em no-show de agendamento). **Balde B**.
- `85d8911b` — proposta é literalmente nova lógica de reatribuição/matching automático
  (escrita em `orders`/atribuição de motorista). Núcleo de dispatch. **Balde B**.
- `d9df69ed` — investiga cancelamentos ligados ao TTL de segurança do próprio `dispatch_engine`
  (cancelamento de pedido/pagamento). **Balde B**.
- `bea503a3` — propõe política de depósito/pré-pagamento para reduzir no-show — mexe em cobrança
  de parceiros de serviços. **Balde B**.

Nenhum item passa o teste "só leitura, sem escrita, sem charge, sem Edge Function que cobra" →
**0 Balde A, 0 auto-aprovados** nesta corrida. Classificação das 10 corridas anteriores
**confirmada, não corrigida** — reavaliei a evidência bruta de cada item e cheguei à mesma
conclusão de forma independente (nenhuma herdada às cegas).

## Ação tomada
- Nenhuma mudança de roteamento (fila idêntica às corridas 3a-10a, decisão idêntica).
- Nenhuma lógica de dinheiro/dispatch/RLS tocada — só leitura (`execute_sql` SELECT) + 1 INSERT
  de auditoria (rasto).
- Telegram: **não enviado** — mesmo lote já surfaçado 10x hoje ao Danilo; reenviar seria spam.
- Reconfirmação registada em `admin_audit_log` (id `ef5e33c6-2189-4ebd-aac9-9a293d598f6a`,
  action=`reconfirmacao_fila_balde_b_sem_novidade`, entity_type=`robot_suggestions`, 5 ids +
  corrida=11a + telegram_enviado=false).

## Balde B — aguarda Danilo (resumo para revisão manual)
Todos os 5 itens ficam em `status='nova'`, sem alteração. Quando o Danilo tiver disponível o
canal (Telegram/Central), cada um precisa do aviso:

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

(aplicável a cada um dos 5 itens acima — nenhum foi aplicado, só a proposta existe na fila)

## Anomalia (já reportada nas corridas 8a-10a — agora com 4 registos consecutivos)
`FALLBACK_30MIN` continua a disparar em cadência curta sobre a mesma fila inalterada (11
corridas desde 2026-07-12 sobre o mesmo lote de 5). Não é risco de dinheiro — Balde B nunca
promovido, prova positiva reavaliada do zero em cada corrida — mas é execução de agente
desperdiçada e ruído crescente em `admin_audit_log`. Correção sugerida (fora do mandato de
roteamento deste agente): cooldown por-lote no `hermes-aprovador-vermelho.sh` (não re-disparar
se o conjunto de ids Balde B pendentes for idêntico ao da última corrida há <2h, ou backoff
exponencial). Encaminhar a `maestro-autonomia` ou ao Danilo.

## HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: agente:aprovador-vermelho
tema-alvo: `permanente/procedural/aprovador-vermelho-triagem.md` (tabela "Histórico de corridas")
conteudo: 2026-07-13, corrida 11a (FALLBACK 30MIN), fila `nova` idêntica às corridas anteriores
(5 itens: `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), todas reconfirmadas Balde B
com prova positiva reavaliada do zero, 0 auto-aprovações. Anomalia de cadência do FALLBACK_30MIN
agora com 4 registos consecutivos (8a-11a) sem correção — cooldown/backoff no script segue
pendente, encaminhado a `maestro-autonomia`/Danilo.

## Ponteiros
`zonas-protegidas.md`, `business-rules.md`, `aprovador-vermelho-triagem.md`,
`project_aprovador_vermelho_central.md` (memória),
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-13-10a-corrida.md`.
