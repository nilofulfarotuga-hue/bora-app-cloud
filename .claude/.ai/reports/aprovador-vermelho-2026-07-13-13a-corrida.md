---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-13
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM DA FILA 🔴 (2026-07-13, 13ª corrida)

**Gatilho:** FALLBACK 30MIN reportado pelo invocador — item `nova` mais antigo parado 30092+ min
(~20,9 dias), gatilho normal por item-novo aparentemente falhou (staleness enorme). Pedido: triar
TODA a fila `status='nova'` do zero, não deixar nada preso só por staleness.

## Confirmação da fila
Fila `robot_suggestions` `status='nova'` relida via SQL direto: **5 itens** (contagem real
confirmada, não 20 dias de item "preso" — cada um foi re-triado do zero nesta corrida). Todos com
`nivel=3` já atribuído pelo próprio maestro-autonomia (nível dinheiro/só-propõe), sinal consistente
com Balde B antes mesmo da minha triagem. Zero itens duplicados (5 `dedup_key` distintos entre si).

## Balde A (leitura/falso-positivo) — recomendo aprovar
**Nenhum.** 0 itens caem em Balde A nesta corrida.

## Balde B (dinheiro real — precisa do Danilo) — reconfirmados (5)

- **`268aad47`** — Investigar/otimizar `bora_dispatch_maintenance()`.
  Faz: função cron cancela pagamentos abandonados (`UPDATE orders` status/payment_status) + aplica
  2 TTLs de auto-cancelamento do dispatch + chama Edge Fn `dispatch-engine` via `net.http_post`.
  Risco: qualquer "otimização" mexe no coração do dispatch + cancelamento de pagamento.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`abeca5d7`** — Investigar/otimizar `_appointment_cron_auto_no_show()`.
  Faz: decide reter ou não o depósito do cliente (`deposit_status='paid'→'retained'`) ao marcar
  no-show automático. Risco: erro na lógica afeta cobrança direta ao cliente.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`85d8911b`** — Reatribuir automaticamente pedidos presos (proposta de TTL de reatribuição).
  Faz: propõe alterar a atribuição automática de estafeta a pedidos travados no `dispatch_engine`.
  Risco: dinheiro-adjacente (motor de dispatch é zona protegida; qualquer implementação mexe lá).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`d9df69ed`** — Analisar cancelamentos por `dispatch_safety_timeout`.
  Faz: propõe investigar/corrigir a causa-raiz no `dispatch_engine` (timeout de segurança sem
  estafeta atribuído). Risco: perda de receita + qualquer fix mexe no motor protegido.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`bea503a3`** — Reduzir taxa de no-show em agendamentos (16,67% vs benchmark 5%).
  Faz: propõe medidas incluindo "políticas de depósito" — toca diretamente dinheiro do cliente.
  Risco: qualquer política de depósito nova é decisão financeira, não técnica.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

**Prova positiva por item** (por que nenhum passa para Balde A): todos os 5 falham o teste
sem-escrita/sem-charge/sem-EdgeFn-de-cobrança — ou escrevem diretamente em `orders`/`appointments`
com efeito financeiro, ou propõem mudar lógica dentro do `dispatch_engine`/depósitos (zonas 🔴 da
Trava). Nenhuma dúvida remanescente → mantidos em Balde B, como nas 12 reconfirmações anteriores.

## Resumo para Telegram (o invocador repassa como RESULTADO do loop autónomo)
```
🚦 Aprovador-vermelho — 13ª corrida (2026-07-13)
Fila nova = 5 itens, TODOS Balde B (dinheiro real), 0 Balde A, 0 auto-aprovações.
Mesmo lote reconfirmado 13x desde 2026-06-22/07-12 — precisam da tua decisão em
AdminRobotSuggestionsScreen: bora_dispatch_maintenance, appointment_no_show,
reatribuir-pedidos-presos, dispatch_safety_timeout, no-show-agendamentos.
Nenhum novo, nenhum promovido sozinho. Gatilho normal por item-novo continua "mudo" —
considera decidir os 5 de uma vez ou ajustar o script (ver anomalia conhecida).
```
Nota: Telegram por item NÃO reenviado nesta corrida (backlog idêntico já surfaçado 12x
consecutivas — evitar spam repetido; anomalia de cadência do FALLBACK_30MIN já registada em
`permanente/procedural/aprovador-vermelho-triagem.md`). O resumo acima fica pronto para o
invocador repassar.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — confirmado via SELECT
direto. Sem efeito prático nesta corrida (0 itens Balde A na fila).

## Auditoria
`admin_audit_log` id `276a64f6-bdd2-4f02-9491-fbaa19537cf1`, action
`robot_suggestion_baldeB_reconfirmado`, `reconfirmacao_numero=13`, `created_at=2026-07-13 05:49:40 UTC`.

## Anomalia pendente (já reportada 9+ vezes, fora do meu mandato)
O script `hermes-aprovador-vermelho.sh` refire `FALLBACK 30MIN` a cada ~30 min enquanto os 5 itens
Balde B continuarem por decidir (mesmo `STALE_MIN` serve de gatilho e de cooldown). Zero risco de
dinheiro, mas é execução de agente desperdiçada. Candidato a ordem para `maestro-autonomia` ou
decisão direta do Danilo (backoff crescente no script, ou simplesmente decidir os 5 itens na
Central). Ver `permanente/procedural/aprovador-vermelho-triagem.md` para histórico completo.

## HANDOFF
→ `bibliotecario-cerebro`, escopo: `agente:aprovador-vermelho`. Atualizar
`aprovador-vermelho-triagem.md` linha "Histórico de corridas" com esta 13ª reconfirmação (mesmo
resultado: 0 Balde A, 5 Balde B reconfirmados, sem novos itens).
