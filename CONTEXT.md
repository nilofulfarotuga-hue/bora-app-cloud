# CONTEXT.md — o vocabulário do Bora

> Glossário do domínio. Escrito na missão `skills-matt-pocock-2026-08-29`, extraído do
> que **já estava escrito**: `.claude/.ai/business_rules.md` (BR), `CLAUDE.md` (CM),
> `.claude/.ai/knowledge/00_BORA_DNA.md`, `permanente/procedural/convencoes.md`.
>
> **Como ler:** o que vem de fonte escrita está com a fonte ao lado. O que é **dedução**
> está marcado **`POR CONFIRMAR`** — isso não é facto, é pergunta à espera de resposta do
> Danilo. Nunca trates um `POR CONFIRMAR` como assente.
>
> Ordem de autoridade (CM): 1.º `business_rules.md` · 2.º código da app ·
> 3.º padrão Glovo/Uber Eats/iFood.

---

## 1. O eixo que mais custa errar: parceiro vs não-parceiro

> ⚠️ BR §2.2 é explícito: confundir parceiro vs não-parceiro é erro grave, e manda
> verificar SEMPRE `is_partner_store`.

**Parceiro** — loja com acordo assinado com a Bora. A distinção **só se aplica a
restaurantes** (CM). O parceiro paga comissão à Bora e a Bora cobra menos ao cliente.

**Não-parceiro** — loja sem acordo. A Bora compra lá como um cliente qualquer e ganha
por markup. **Todos os mercados/supermercados são não-parceiros** (CM), sem excepção.

O interruptor técnico é `is_partner_store` (BR §2.2). Não se adivinha pelo nome da loja.

## 2. As três camadas de dinheiro do parceiro (10 + 5 + 5)

BR §2.4 — total 20%, em três camadas com nomes distintos:

| Camada | Quanto | Quem paga | Vê-se? |
|---|---|---|---|
| **Comissão visível** | 10% | o parceiro, no acerto | sim, o parceiro vê |
| **Markup oculto** | +5% | o cliente, embutido no preço | **não** |
| **Taxa de serviço** | +5% | o cliente, linha no recibo | sim |

Colunas: `partner_commission_visible`, `partner_markup_hidden`,
`partner_service_fee_client` (CM).

**Markup do não-parceiro:** 15% sobre o preço, invisível, lucro da Bora (BR §2.4).
Aplicado **em runtime** por `pricing_calculate` — nunca gravado no preço do produto (BR).

## 3. Taxa de serviço e fee fixo — não são a mesma coisa

BR §2.2:

- **Parceiro:** taxa de serviço = **5% × subtotal** (`client_service_fee_pct = 0.05`)
- **Não-parceiro:** **€2,50 FIXO** — é um *fee fixo*, **não** uma percentagem
  (`delivery_base_fee_cents = 250`)
- **Logística** (`carryGroceries` / `sendPackage`): incluída no `packageFee`, sem taxa
  separada

**Taxa de entrega** é outra coisa ainda (BR §2.1): €2,50 até 4 km, +€0,50/km acima.
Entrega em apartamento: +€1,50, dividido €1,00 estafeta / €0,50 Bora (BR §2.3).

## 4. Estafeta

Quem faz a entrega. Não confundir com *motorista*, que é o TVDE.

Ganho por entrega (BR §2.2.1) — e note-se que **depende do tipo de loja**:

| Caso | Fórmula |
|---|---|
| Parceiro (rest. + retail) | `€3,80 + €0,20×km + apt + (stacking? €3 : 0)` — sem €0,80, sem 30% |
| Não-parceiro `storeShopping` | `€3,80 + €0,80 + €0,20×km + apt + 30%×boraNet` |
| Não-parceiro `restaurant` | `€3,80 + €0,20×km + apt + 30%×boraNet` — sem €0,80 |
| Logística | `€4,00 + €0,50×km + €0,80 + apt` |

`boraNet = (subtotal×0,15 + deliveryFee + serviceFee) − driverFixed` (BR).

O €0,80 existe só quando o estafeta **compra e entrega**; se não compra, não leva (BR).

Pagamento é **semanal**, nunca reembolso instantâneo (CM, BR §5.3).

## 5. Tokens — dois sistemas com o mesmo nome

Confundir os dois é erro. BR §4:

- **Tokens do cliente** — ganha **3 tokens por euro**, `GREATEST(1, ROUND(valor×3))`.
  São desconto: 100 tokens = €0,50, validade 60 dias, consumo FIFO, desconto até **50%**
  do valor do pedido.
- **Tokens de fidelidade do estafeta** — **+40** por entrega não-parceiro, **+50** por
  entrega de **loja parceira**.

> ⚠️ BR corrige documentação antiga (2026-07-06): versões antigas diziam cliente "3% do
> valor" e "+50 = stacking". **Ambas erradas.** É 3 tokens/€ e +50 = loja parceira.
> `CLAUDE.md` e a skill `ceo-ai` ainda dizem "3%" — **estão desatualizados**; o
> `business_rules.md` manda.

Tabela `bora_tokens`, trigger `trg_award_tokens_on_delivery` (CM). Zona vermelha.

## 6. Os dois "80/20" — não são o mesmo

Isto engana com frequência:

- **Split de reembolso da wallet:** quando um pedido pago é reembolsado para a carteira,
  o remanescente parte-se em **80% saldo livre + 20% tokens** (BR:1406). Configurável em
  `platform_settings` como `wallet_credit_refund_split` (BR:3873).
- **Gorjeta:** parte-se **80% estafeta / 20% Bora** (BR §4.5). Nada a ver com o anterior.

Guardas do reembolso (BR §8.4): `refund_amount` **nunca** excede
`stripe_charge_cents + wallet_applied_cents + tokens_applied_value_cents`. A RPC
`compute_refund_split(order_id, refund_eur)` devolve as três parcelas.

Excedente ao liquidar dívida da wallet vai **100% para `free_balance_cents`** — esse
**não** segue a regra 80/20 (BR:3858).

## 7. Reservas de mesa

Pré-pagamento de **€3** (CM: €2 parceiro / €1 Bora). Estados (BR §1.4):
`reservation_requested → restaurant_responding → (accepted | suggested_alternative |
rejected) → confirmed → customer_arrived → completed | no_show`.

Cancelamento (BR:591-596):

- **até 4 horas antes:** reembolso total dos €3
- **menos de 4 horas:** perde os €3
- **no-show:** perde os €3
- restaurante rejeita o pedido de reserva: cliente recebe reembolso total

> `POR CONFIRMAR` — `CLAUDE.md` diz "cancel **<2h** = Bora 100%", o `business_rules.md`
> diz **4 horas**. São gémeos desalinhados. O `business_rules.md` tem precedência, mas o
> `CLAUDE.md` devia ser corrigido.

## 8. Favores (errand)

BR §55 (2026-06-16). Cliente pede um favor a um estafeta na Guarda.
`OrderServiceType.errand`, `orders.service_type='errand'`.

| Item | Cliente paga | Estafeta recebe | Bora |
|---|---|---|---|
| Taxa normal (até 3h) | €6,00 | €5,00 | €1,00 |
| Taxa expresso (45–60 min) | €10,00 | €8,00 | €2,00 |
| Paragem em casa do cliente | +€2,00 | +€1,00 | +€1,00 |
| Km extra (>4 km no percurso) | +€0,50/km | +€0,50/km (100%) | €0 |
| Valor da compra (talão) | 1:1 sem markup | reembolso 1:1 | €0 |

O valor da compra **nunca leva markup** — é reembolso puro contra talão.

Buffer de cartão/MB Way: `payment_buffer_total = fees_total + round(estimativa × 1,2)`.
**Nunca ×1,15** (BR).

## 9. Dispatch

O motor que escolhe a quem se oferece o pedido. Edge Function `dispatch-engine`,
server-side; o Flutter é camada reactiva, só lê (CM).

- **Stacking:** até 3 pedidos, FIFO ≤200 m (CM)
- **Timeout de oferta:** 40 s (CM). `POR CONFIRMAR` — o `DispatchEngine` em memória usa
  `_offerTimeout = 10 s` (CM, secção de arquitectura). Dois números para a mesma ideia;
  é provável que sejam camadas diferentes (servidor vs memória), mas não está escrito.
- **`current_driver_offer_id`** é a fonte de verdade de quem tem a oferta em mão (CM)

Regras de lotação em `DriverCapacityService`: logística não empilha; parceiro até 2
(mesma loja ou ≤800 m); não-parceiro até 3, todos da mesma loja (CM).

**Zona vermelha.** Não se toca sem ordem explícita.

## 10. Ordem do pedido (o ciclo de vida)

`created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered`
(CM). Nunca `String` para estado — sempre o enum `OrderStatus` (CM, regra dura).

Toda a transição escreve **primeiro na base de dados** e só depois muda o estado local.
A comparação é **por id**, nunca por referência de objeto: o realtime substitui o objeto
por uma instância nova (CM).

## 11. Zona verde e zona vermelha

Como o sistema decide o que um agente pode aplicar sozinho:

- **🟢 zona verde** — executa ponta-a-ponta sem perguntar (bugs, ecrãs, features, infra,
  admin não-financeiro) (CM, CEO-AI §1.6)
- **🔴 zona vermelha** — **dinheiro real**: Stripe, preços, comissões, `finalizePurchase`,
  `bora_tokens`, `platform_settings` financeiros, migrations que alterem valores cobrados
  a clientes ou pagos a estafetas/parceiros. O agente prepara tudo mas **não aplica**;
  escreve em português que aquilo mexe em dinheiro e espera o Danilo dizer "vai"
  (CEO-AI §1.6)
- **🟡 sensível** — entre as duas (CM)

**O classificador não pisa em casca de ovo com palavras** (convencoes.md, 2026-07-11):
mencionar `stripe` ou `pricing_service` não pinta vermelho. Só pinta se houver **intenção
de escrita** junto (verbo `mudar/atualizar/aplicar/…` ou SQL
`UPDATE/INSERT/DELETE/ALTER/DROP`), ou uma acção destrutiva por si só (`--force`,
`reset --hard`, `disable row level`).

## 12. A maquinaria de orquestração

- **Córtex** — a memória e a fila central do projeto, acessível por MCP (`cortex_buscar`,
  `cortex_ler`, …). **É a fila real do Bora** — não se abre uma segunda (CM global).
- **Juiz** (`juiz-revisor`) — o portão anti-trapaça. Nenhum trabalho é aceite sem passar
  o chão determinístico (`.claude/juiz/anti_trapaca.py`) mais três camadas: mecânica
  (TestSprite); `flutter analyze` + `flutter test` + zonas protegidas + business rules; e
  rubrica de UI. Rejeição gera lição, que vai para o Cérebro (CM).
- **Cérebro** — `.claude/.ai/knowledge/`. Só o `bibliotecario-cerebro` escreve lá; os
  outros agentes entregam-lhe um *handoff* no fim da tarefa (CM).
- **Hermes** — o sócio-agente que corre na VPS, com perfis próprios (`escriba`,
  `batedor`, `fiscal`) e alma em `SOUL.md`. Vive em `/docker/hermes-agent-fvnc/data/`
  (verificado ao vivo 2026-08-29).
- **Ordem** — uma tarefa da fila de trabalho autónomo, identificada por um `run_id`.
  `POR CONFIRMAR` — o termo usa-se em todo o lado, mas não encontrei uma definição
  escrita canónica.
- **Carteiro** — o processo que pega a próxima ordem da fila, classifica a zona e a
  entrega ao executor (`carteiro.sh`); só reabre uma ordem por veredito do Juiz.
  `POR CONFIRMAR` na definição exacta.

## 13. Coisas que mudaram e a documentação ainda não acompanhou

> Tudo nesta secção é `POR CONFIRMAR` — precisa de decisão ou confirmação do Danilo.

- **TVDE ida-e-volta:** `CLAUDE.md` ainda descreve **€8 fixo** (motorista da ida €4, da
  volta €3,50, Bora ~€0,50). A memória do projeto diz que isso foi **superado** por preço
  dinâmico por rota, calculado por corrida. Qual manda?
- **Sinal de €3 nas Marcações/Serviços** (barbearias, beleza): a memória diz que acabou a
  2026-08-03 — cliente paga o valor cheio, Bora fica com €0,50, repasse semanal. O
  `business_rules.md` não tem rasto dessa mudança. Falta actualizar a fonte de verdade.
  Nota: é diferente das **Reservas de mesa** (§7), onde os €3 continuam.
- **Timeout de dispatch:** 40 s ou 10 s? (ver §9)
- **Tokens do cliente:** `CLAUDE.md` e a skill `ceo-ai` dizem "3% do valor"; o
  `business_rules.md` corrige para 3 tokens/€. Os dois primeiros deviam ser corrigidos.
- **Cancelamento de reserva:** 2 h ou 4 h? (ver §7)
