---
escopo: agente:aprovador-vermelho
data: 2026-07-13
corrida: 8a (gatilho FALLBACK_30MIN)
estado: atual
---

# Aprovador-vermelho — 8ª corrida (2026-07-13, FALLBACK 30MIN)

## Resultado
Fila `robot_suggestions` status='nova' reconfirmada via `execute_sql` (MCP Supabase,
project `ojykpzwqrtusfeakzrna`) — **exatamente o mesmo lote de 5 itens** das 7 corridas
anteriores (2026-07-12 11:26 UTC → 2026-07-12 23:42 UTC). Zero itens novos, zero
resolvidos/expirados. Flag `aprovador_vermelho_auto_baldeA` confirmada `true` antes da
triagem (não é suposição).

| id | categoria | nível | título | idade |
|---|---|---|---|---|
| `268aad47` | infra_cron | 3 | otimizar `bora_dispatch_maintenance()` | ~29752 min (~20,7 dias) |
| `abeca5d7` | infra_cron | 3 | otimizar `_appointment_cron_auto_no_show()` | ~29752 min (~20,7 dias) |
| `85d8911b` | operacao_pedidos | 3 | reatribuição automática de pedidos presos (dispatch) | ~1552 min (~26h) |
| `d9df69ed` | operacao_pedidos | 3 | cancelamentos por `dispatch_safety_timeout` | ~772 min (~13h) |
| `bea503a3` | marcacoes | 3 | taxa no-show 16,67% / política de depósito | ~772 min (~13h) |

Todos `nivel=3` (o próprio sistema já os marca como camada dinheiro — N3 🔴 = só propõe).
Todos confirmados **Balde B**, motivo inalterado:
- `268aad47`/`abeca5d7`: tocam o coração do `dispatch_engine` e a retenção de depósito de
  agendamento (`_appointment_cron_auto_no_show` escreve `deposit_status='retained'`).
- `85d8911b`: propõe alterar lógica de reatribuição/TTL do dispatch — zona protegida.
- `d9df69ed`: cancelamento ligado ao `dispatch_safety_timeout` (mecanismo TTL do dispatch).
- `bea503a3`: propõe política de depósito/pré-pagamento — dinheiro.

Nenhum item com prova positiva de "só leitura sem escrita/cobrança" → **0 Balde A, 0 auto-aprovados**.

## Ação tomada
- Nenhuma mudança de roteamento (fila idêntica à 7ª corrida, decisão idêntica).
- Telegram: **não reenviado** — mesmo lote já surfaçado 7x hoje ao Danilo; reenviar seria spam.
- Reconfirmação leve gravada em `admin_audit_log` (id `6c00001c-0a61-4b5a-aa0e-6081b91c0581`,
  action=`reconfirmacao_fila_balde_b_sem_novidade`, entity_type=`robot_suggestions`, 5 ids +
  corrida=8a + telegram_enviado=false + anomalia registada).
- Nenhuma lógica de dinheiro/dispatch/RLS tocada — só leitura + 1 INSERT de auditoria.

## Anomalia a reportar (fora do escopo de roteamento deste agente)
`FALLBACK_30MIN` disparou **8 vezes em ~13 horas** (11:26, ~19:40, 21:58, 23:01, 23:20, 23:38,
23:42, agora 00:01 UTC) sobre a **mesma fila inalterada** — o último disparo antes deste ficou
a **~18-19 minutos** do anterior, não ~30min. Isto sugere que `STALE_MIN` no
`hermes-aprovador-vermelho.sh` não tem backoff crescente quando a fila não muda: o item mais
antigo (`268aad47`, parado há 20+ dias) satisfaz sempre a condição "≥30min parado" e o gatilho
volta a disparar quase de imediato após cada corrida terminar. Consequência prática: nenhum
risco de dinheiro (a decisão continua correta — Balde B nunca promovido), mas gasto
desnecessário de execuções de agente + spam de `admin_audit_log`. Correção sugerida (fora do
meu mandato de roteamento): o script precisa de um cooldown por-lote (ex.: não re-disparar se
o conjunto de ids Balde B pendentes for idêntico ao da última corrida há <2h), a implementar
pelo `maestro-autonomia` ou pelo Danilo diretamente no script bash — não é alteração de lógica
de dinheiro nem de aprovação, é housekeeping do gatilho cron.

## Ponteiros
`zonas-protegidas.md`, `business-rules.md`, `project_aprovador_vermelho_central.md` (memória),
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-12-{3a,4a,5a,6a}-corrida.md`,
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-13-7a-corrida.md`.
