---
escopo: agente:aprovador-vermelho
data: 2026-07-13
corrida: 14a (gatilho FALLBACK_30MIN), 10ª reconfirmação consolidada
estado: atual
---

# Aprovador-vermelho — 14ª corrida (2026-07-13, FALLBACK 30MIN)

## Contexto do gatilho
Executor autónomo do loop noturno (headless). FALLBACK 30MIN disparou de novo — item `nova` mais
antigo (`268aad47`) parado ~30025 min (~20,9 dias, desde 2026-06-22) sem triagem normal (watermark
não dispara em item já visto). Ordem recebida: re-triar TODA a fila `status='nova'` do zero, pela
prova, não pelo histórico — mesmo que itens já tenham sido vistos antes.

## Verificação prévia
- Flag `platform_settings.aprovador_vermelho_auto_baldeA` = **`true`** (query direta, confirmada).
- Fila `robot_suggestions status='nova'` lida via `execute_sql` (MCP Supabase, projeto
  `ojykpzwqrtusfeakzrna`): **5 itens**, exatamente o mesmo lote das 13 corridas anteriores hoje.
  Zero itens novos, zero resolvidos/expirados, zero duplicados (dedup_key únicos).

| id | categoria | nível | minutos parado | título |
|---|---|---|---|---|
| `268aad47` | infra_cron | 3 | ~30025 (~20,9 dias) | otimizar `bora_dispatch_maintenance()` |
| `abeca5d7` | infra_cron | 3 | ~30025 (~20,9 dias) | otimizar `_appointment_cron_auto_no_show()` |
| `85d8911b` | operacao_pedidos | 3 | ~1825 | reatribuição automática de pedidos presos (dispatch) |
| `d9df69ed` | operacao_pedidos | 3 | ~1045 | cancelamentos por `dispatch_safety_timeout` |
| `bea503a3` | marcacoes | 3 | ~1045 | taxa no-show 16,67% / política de depósito |

## Triagem (prova positiva, reavaliada do zero)
Todos `payload_execucao=null` — só diagnóstico em texto, nenhum SQL/patch pronto para aplicar
automaticamente. Ainda assim, cada proposta descreve mudança futura em zona protegida:

- `268aad47` — evidência = `pg_stat_statements` (perf pura), mas a proposta é otimizar
  `bora_dispatch_maintenance()`, função que faz `UPDATE orders` (cancela pagamentos abandonados) +
  chama `dispatch-engine` via `net.http_post`. Sem prova de "sem escrita" → **Balde B**.
- `abeca5d7` — mesma forma; a função grava `deposit_status='retained'` (retenção de depósito de
  cliente). **Balde B**.
- `85d8911b` — propõe nova lógica de reatribuição/matching automático de motorista (núcleo
  dispatch_engine). **Balde B**.
- `d9df69ed` — investiga cancelamentos ligados ao TTL de segurança do `dispatch_engine`, com risco
  explícito de "perda de receita". **Balde B**.
- `bea503a3` — propõe política de depósito/pré-pagamento para parceiros de serviços — dinheiro
  direto. **Balde B**.

Nenhum item passa o teste "só leitura, sem escrita, sem charge, sem Edge Function que cobra" →
**0 Balde A, 0 auto-aprovados** — 14ª corrida seguida a chegar à mesma conclusão, reavaliada de
forma independente.

## Ação tomada
- Nenhuma mudança de roteamento; nenhuma lógica de dinheiro/dispatch/RLS tocada — só SELECT + 1
  INSERT de auditoria.
- Telegram: **não enviado** — mesmo lote já surfaçado ao Danilo 9x hoje via Telegram/relatório;
  reenviar seria spam sem informação nova.
- Auditoria: `admin_audit_log` action=`robot_suggestion_baldeB_reconfirmado`,
  reconfirmacao_numero=**10**, criado 2026-07-13 ~04:32 UTC, 5 ids, trigger=FALLBACK_30MIN.

## Balde B — aguarda Danilo
Todos os 5 itens ficam em `status='nova'`, sem alteração:

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

(aplicável a `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3` — nenhum aplicado, só a
proposta existe na fila, aguardando decisão via `AdminRobotSuggestionsScreen` ou "vai" no Telegram)

## ANOMALIA — escalar com mais força (8ª vez consecutiva registada)
`FALLBACK_30MIN` já disparou **≥14 vezes hoje** (9 reconfirmações de auditoria antes desta) sobre
o **mesmo lote inalterado de 5 itens**, cadência ~30 min. O item mais antigo (`268aad47`) está
parado desde **2026-06-22 — 20,9 dias**, muito antes do próprio mecanismo FALLBACK_30MIN existir
(criado 2026-07-12). Isto não é risco de dinheiro (Balde B nunca promovido; prova reavaliada do
zero em cada corrida), mas confirma dois problemas reais fora do meu mandato de roteamento:
1. **Desperdício de execução de agente** — 14 corridas quase idênticas em ~9h de loop noturno.
2. **O próprio kill-switch de visibilidade não está a resolver o deadlock original** — surfaçar
   9x ao Danilo sem resposta sugere que o canal de notificação (Telegram) não está a chegar, ou
   que os itens precisam de decisão humana explícita que só acontece em horário acordado.

**Recomendação (reforçada pela 8ª vez, fora do meu mandato de aplicar):** `hermes-aprovador-vermelho.sh`
deveria aplicar backoff/cooldown quando o conjunto de ids Balde B pendentes é idêntico ao da corrida
anterior (ex.: não re-disparar FALLBACK_30MIN sobre o mesmo lote por <2h, ou até haver mudança de
estado), e considerar 1 Telegram diário-resumo (não silêncio total) para itens Balde B parados
>24h, distinto do spam de 30/30min. Encaminhar a `maestro-autonomia` ou decisão direta do Danilo.

## HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: agente:aprovador-vermelho
tema-alvo: `permanente/procedural/aprovador-vermelho-triagem.md` (tabela "Histórico de corridas")
conteudo: 2026-07-13, corrida 14a (FALLBACK 30MIN, 10ª reconfirmação de auditoria), fila `nova`
idêntica às 13 corridas anteriores (5 itens: `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`,
`bea503a3`), todas reconfirmadas Balde B com prova positiva reavaliada do zero, 0 auto-aprovações.
Anomalia de cadência do FALLBACK_30MIN agora com **8 registos consecutivos** sem correção —
item mais antigo já 20,9 dias parado. Recomendação de backoff/cooldown + resumo diário no script
encaminhada a `maestro-autonomia`/Danilo pela 8ª vez, ainda pendente.

## Ponteiros
`zonas-protegidas.md`, `business-rules.md`, `aprovador-vermelho-triagem.md`,
`project_aprovador_vermelho_central.md` (memória),
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-13-13a-corrida.md`.
