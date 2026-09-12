---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · data: 2026-07-13
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-13, 12ª corrida consolidada)

## Gatilho desta corrida
Pedido manual, madrugada, loop headless. Relato do invocador: "o gatilho normal por item-novo
falhou" e a fila `nova` tinha 5 itens parados ~30092+ min (~20.9 dias). **Confirmado via COUNT
direto (Supabase MCP, projeto `ojykpzwqrtusfeakzrna`): fila `status='nova'` = exatamente 5 itens.**
Não há itens escondidos além dos "5 óbvios" — a contagem real bate com o relato.

## Fila completa re-triada do zero (prova positiva por item)

### Balde A (leitura/falso-positivo) — recomendo aprovar
**Nenhum item nesta corrida.** 0 de 5.

### Balde B (dinheiro real — precisa do Danilo)
| id | título | motivo (prova concreta) |
|---|---|---|
| `268aad47` | Investigar/otimizar `bora_dispatch_maintenance` | Função cancela pagamentos abandonados (`UPDATE orders`), aplica TTLs de auto-cancelamento do dispatch, chama Edge Fn `dispatch-engine` via `net.http_post`. Escreve em orders + dispara dispatch. |
| `abeca5d7` | Investigar/otimizar `_appointment_cron_auto_no_show` | Decide reter ou libertar `deposit_status` do cliente (`'paid'→'retained'`) = decisão direta sobre dinheiro do cliente. |
| `85d8911b` | Reatribuir automaticamente pedidos presos | Proposta pede reatribuição automática com TTL dentro do `dispatch_engine` — mexe em atribuição de estafeta/pedido, dinheiro-adjacente (ganhos do estafeta, cobrança do cliente). |
| `d9df69ed` | Analisar cancelamentos por `dispatch_safety_timeout` | Causa raiz vive no `dispatch_engine`; qualquer correção proposta mexe no motor de despacho protegido. |
| `bea503a3` | Reduzir taxa de no-show em agendamentos | Proposta cita "políticas de depósito" como mitigação — toca `deposit_status`/dinheiro retido de agendamentos. |

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico (por item, não por lote).

**Auto-Balde-A:** ligado (`platform_settings.aprovador_vermelho_auto_baldeA = true`) — sem efeito
nesta corrida porque 0 itens caíram em Balde A.

## Verificação de teto/deadlock
`admin_audit_log` tinha 11 reconfirmações `robot_suggestion_baldeB_reconfirmado` anteriores para
este mesmo lote (2026-07-12/13). Esta corrida grava a **12ª** — longe do teto de 30 mencionado na
memória de sessão; **dedupe não foi necessário**.

## Problema técnico reportado (não é decisão deste agente)
Mesma anomalia já reportada 11× antes: `hermes-aprovador-vermelho.sh` (FALLBACK 30MIN) refire a
cada ~30min sempre que estes 5 itens Balde B continuam por decidir — reconfirmação idêntica,
zero risco de dinheiro, mas execução desperdiçada + ruído em `admin_audit_log`. Fica sinalizado
para `maestro-autonomia`/decisão direta do Danilo (backoff/cooldown no script, ou decidir os 5 na
`AdminRobotSuggestionsScreen`). Não corrigido aqui — fora do mandato de roteamento deste agente
(não mexo em scripts do loop sem gatilho humano explícito).

Sem novo Telegram por item — mesmo backlog já surfaçado 11× hoje ao Danilo; evita-se spam. Se o
Danilo estiver a ler isto agora: os 5 itens acima aguardam a tua decisão em
`AdminRobotSuggestionsScreen` (Central do Córtex).

## Ação em admin_audit_log
Inserido 1 registo `robot_suggestion_baldeB_reconfirmado` (`reconfirmacao_numero: 12`) com os 5
IDs + motivo por item.

## Handoff
`bibliotecario-cerebro` — escopo `agente:aprovador-vermelho`. Sem facto novo a gravar (o padrão já
está consolidado em `permanente/procedural/aprovador-vermelho-triagem.md`); sugestão: se este loop
continuar a refirar sem decisão humana, considerar registar a anomalia de cadência como item de
ação para o `maestro-autonomia` em vez de re-narrar a cada corrida.
