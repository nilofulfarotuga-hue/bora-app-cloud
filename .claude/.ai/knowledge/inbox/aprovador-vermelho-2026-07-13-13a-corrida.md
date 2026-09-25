---
escopo: agente:aprovador-vermelho
data: 2026-07-13
corrida: 13a (gatilho FALLBACK_30MIN)
estado: atual
---

# Aprovador-vermelho — 13ª corrida (2026-07-13, FALLBACK 30MIN)

## Contexto do gatilho
Fallback de 30 minutos: item `nova` mais antigo (`268aad47`) parado ~29944 min (~20,8 dias) sem
triagem normal (watermark não dispara em item já visto). Ordem: re-triar TODA a fila
`status='nova'` do zero, pela prova, não pelo histórico.

## Verificação prévia
- Flag `platform_settings.aprovador_vermelho_auto_baldeA` = **`true`** (confirmada por query direta).
- Fila `robot_suggestions status='nova'` lida via `execute_sql` (MCP Supabase, projeto
  `ojykpzwqrtusfeakzrna`): **5 itens**, exatamente o mesmo lote das 12 corridas anteriores hoje
  (2026-07-12 19:40 UTC → 2026-07-13 02:42 UTC). Zero itens novos, zero resolvidos/expirados.

| id | categoria | nível | título |
|---|---|---|---|
| `268aad47` | infra_cron | 3 | otimizar `bora_dispatch_maintenance()` |
| `abeca5d7` | infra_cron | 3 | otimizar `_appointment_cron_auto_no_show()` |
| `85d8911b` | operacao_pedidos | 3 | reatribuição automática de pedidos presos (dispatch) |
| `d9df69ed` | operacao_pedidos | 3 | cancelamentos por `dispatch_safety_timeout` |
| `bea503a3` | marcacoes | 3 | taxa no-show 16,67% / política de depósito |

Todos `nivel=3` (o próprio sistema de origem já os marca como camada dinheiro/propose-only).

## Triagem (prova positiva, do zero)
Reli `evidencia`/`proposta`/`payload_execucao` de cada item (todos `payload_execucao=null` — só
diagnóstico em texto, nenhum SQL/patch pronto para aplicar):

- `268aad47` — evidência = `pg_stat_statements` (performance pura), mas a proposta é otimizar
  `bora_dispatch_maintenance()`, função que faz `UPDATE orders` (cancela pagamentos abandonados) +
  chama `dispatch-engine` via `net.http_post`. Sem prova de "sem escrita" → **Balde B**.
- `abeca5d7` — mesma forma, mas a função grava `deposit_status='retained'` (retenção de depósito
  de cliente). **Balde B**.
- `85d8911b` — proposta é nova lógica de reatribuição/matching automático (escrita em
  atribuição de motorista). Núcleo de dispatch. **Balde B**.
- `d9df69ed` — investiga cancelamentos ligados ao TTL de segurança do próprio `dispatch_engine`.
  **Balde B**.
- `bea503a3` — propõe política de depósito/pré-pagamento para parceiros de serviços. **Balde B**.

Nenhum item passa o teste "só leitura, sem escrita, sem charge, sem Edge Function que cobra" →
**0 Balde A, 0 auto-aprovados** — 13ª corrida seguida a chegar à mesma conclusão, reavaliada de
forma independente (não copiada do histórico).

## Ação tomada
- Nenhuma mudança de roteamento (fila idêntica às corridas 1a-12a, decisão idêntica).
- Nenhuma lógica de dinheiro/dispatch/RLS tocada — só leitura (SELECT) + 1 INSERT de auditoria.
- Telegram: **não enviado** — mesmo lote já surfaçado 12x hoje ao Danilo; reenviar seria spam.
- Auditoria: `admin_audit_log` id `a77b8138-fc10-4567-b889-38403e26debd` (03:13:03 UTC),
  action=`robot_suggestion_baldeB_reconfirmado`, 5 ids, corrida="13a do dia, 7a reconfirmação
  consolidada", trigger=FALLBACK_30MIN.

## Balde B — aguarda Danilo
Todos os 5 itens ficam em `status='nova'`, sem alteração:

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

(aplicável a `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3` — nenhum aplicado, só a
proposta existe na fila, aguardando decisão via `AdminRobotSuggestionsScreen` ou "vai" no Telegram)

## ANOMALIA — escalar agora, não só registar (7ª vez consecutiva)
`FALLBACK_30MIN` disparou **13 vezes hoje** sobre o **mesmo lote inalterado de 5 itens**, a
cadência de ~30 min (última reconfirmação: 02:42 UTC; esta: 03:13 UTC — 31 min de intervalo,
exatamente o `STALE_MIN` do design). Isto não é risco de dinheiro (Balde B nunca promovido, prova
reavaliada do zero em cada corrida), mas é **desperdício real de execução de agente + ruído
crescente em `admin_audit_log`/inbox** — 13 relatórios quase idênticos em ~8h para uma fila que só
o Danilo pode desbloquear. Já sinalizado nas corridas 8a-12a sem correção aplicada.

**Recomendação concreta (fora do mandato de roteamento deste agente, mas reforçada pela 6ª vez):**
`hermes-aprovador-vermelho.sh` deveria aplicar backoff/cooldown quando o conjunto de ids Balde B
pendentes é idêntico ao da corrida anterior (ex.: não re-disparar FALLBACK_30MIN sobre o mesmo
lote por <2h, ou até haver mudança de estado). Encaminhar a `maestro-autonomia` ou decisão direta
do Danilo — a pendência já foi adiada 6 vezes.

## HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: agente:aprovador-vermelho
tema-alvo: `permanente/procedural/aprovador-vermelho-triagem.md` (tabela "Histórico de corridas")
conteudo: 2026-07-13, corrida 13a (FALLBACK 30MIN), fila `nova` idêntica às 12 corridas anteriores
(5 itens: `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`), todas reconfirmadas Balde B
com prova positiva reavaliada do zero, 0 auto-aprovações. Anomalia de cadência do FALLBACK_30MIN
agora com **7 registos consecutivos** (7a-13a) sem correção — recomendação de backoff/cooldown no
script encaminhada a `maestro-autonomia`/Danilo pela 6ª vez, ainda pendente.

## Ponteiros
`zonas-protegidas.md`, `business-rules.md`, `aprovador-vermelho-triagem.md`,
`project_aprovador_vermelho_central.md` (memória),
`.claude/.ai/knowledge/inbox/aprovador-vermelho-2026-07-13-12a-corrida.md`.
