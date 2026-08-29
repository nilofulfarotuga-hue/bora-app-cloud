# CONTEXT.md — o vocabulário do Bora

> Glossário do domínio. Escrito na missão `skills-matt-pocock-2026-08-29`, extraído do
> que **já estava escrito**: `.claude/.ai/business_rules.md` (BR), `CLAUDE.md` (CM),
> `.claude/.ai/knowledge/00_BORA_DNA.md`, `permanente/procedural/convencoes.md`.
>
> **Actualizado 2026-08-29** na missão `fecho-context-e-portao`: os `POR CONFIRMAR` foram
> **todos fechados** — os que se resolviam a ler código ou `platform_settings` de produção
> passaram a facto com a prova ao lado; os que dependem mesmo de uma decisão do Danilo
> passaram para o bloco **§14 PARA O DANILO**. Já não há `POR CONFIRMAR` soltos.
>
> **Como ler:** o que vem de fonte escrita está com a fonte ao lado. Um facto marcado ✅
> foi provado contra código ou base de dados — o trecho literal está citado. O que ainda
> precisa de decisão do Danilo está no §14, não espalhado pelo documento.
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

## 7. Reservas de mesa — €3, vivos e intactos

> ✅ **PROVADO 2026-08-29** contra `platform_settings` de produção. Não é dedução.

Pré-pagamento de **€3**, repartido €2 parceiro / €1 Bora. As quatro chaves vivas:

| Chave em `platform_settings` | Valor | O que é |
|---|---|---|
| `reservation_prepayment_cents` | `300` | os €3 que o cliente adianta |
| `reservation_partner_payout_cents` | `200` | €2 que vão para o restaurante |
| `reservation_bora_service_cents` | `100` | €1 que fica na Bora |
| `reservation_cancel_window_hours` | `2` | janela de cancelamento com reembolso |

Estados (BR §1.4): `reservation_requested → restaurant_responding → (accepted |
suggested_alternative | rejected) → confirmed → customer_arrived → completed | no_show`.

Cancelamento — a janela são **2 horas**, não 4:

- **até 2 horas antes:** reembolso total dos €3
- **menos de 2 horas:** perde os €3 (Bora fica com 100%)
- **no-show:** perde os €3
- restaurante rejeita o pedido de reserva: cliente recebe reembolso total

> ✅ **Resolvido o desalinhamento 2 h vs 4 h.** Manda **2 horas**. Três provas
> independentes e concordantes:
> 1. `platform_settings.reservation_cancel_window_hours = 2` em produção;
> 2. `supabase/migrations/20260430230000_categories_reservations_session.sql:25` —
>    `('reservation_cancel_window_hours', '2'::jsonb, 'Horas antes para cancelar com refund', 'reservations')`;
> 3. o código lê a chave com fallback 2 —
>    `supabase/migrations/20260507070100_5f_beta_alpha_b3_other_functions.sql:342`:
>    `v_cancel_window_hours := coalesce(v_cancel_window_hours, 2);`
>
> Ou seja: o `CLAUDE.md` ("<2h") estava certo e o `business_rules.md` ("4 horas") está
> **desatualizado neste ponto**. Fica reportado; a correcção do `business_rules.md` é
> ordem à parte (ver §14).

## 7-A. Marcações de serviços ≠ Reservas de mesa

> ✅ **PROVADO 2026-08-29** contra `platform_settings` de produção + código.
> **São coisas diferentes, com valores diferentes.** Confundi-las é erro.

**Marcação** (`appointment`) — barbearia, cabeleireiro, beleza, unhas. O cliente marca
hora com um profissional. **Reserva** (`reservation`) — mesa num restaurante.

| | Marcação de serviço | Reserva de mesa |
|---|---|---|
| O cliente adianta | **nada** — paga o valor cheio no fim | **€3** de pré-pagamento |
| A Bora ganha | **€0,50 por marcação concluída** | **€1** dos €3 |
| O parceiro recebe | o resto, no **repasse semanal** | **€2** dos €3 |
| Chave viva | `appointment_booking_fee_cents = 50` | `reservation_prepayment_cents = 300` |
| Actualizada em | 2026-06-08 | — |

**Não existe sinal de €3 nas marcações.** Os €3 são das reservas de mesa e continuam
vivos. A confusão vem de o sistema de marcações ter *nascido* com um sinal de €3 em
2026-06-08 e esse sinal ter **acabado a 2026-08-03**.

Provas do fim do sinal, no código:

- `lib/screens/admin/admin_platform_settings_screen.dart:150-160` — as três chaves do
  sinal estão declaradas como **obsoletas**:
  > *"FIM DO SINAL (2026-08-03) — chaves do sinal de €3 que a regra de negócio já não
  > usa. `client_book_appointment` deixou de as ler e `compute_provider_weekly_payout`
  > deixou de as somar. Ficam na tabela por histórico, mas não têm de poluir o painel."*
  > `_obsoleteDepositKeys = { appointment_deposit_cents,
  > appointment_deposit_partner_cut_cents, appointment_deposit_bora_cut_cents }`
- `supabase/migrations/20260608000003_appointments_platform_settings.sql:6` — a taxa por
  marcação nasce a 50 cêntimos:
  `('appointment_booking_fee_cents', to_jsonb(50), 'appointments', 'Taxa Bora por marcação concluída (cents). €0,50')`
- `supabase/migrations/20260608000005_appointments_rpcs_admin_cron.sql:74` — o cálculo do
  repasse lê essa chave:
  `SELECT COALESCE((value::text)::int,50) INTO v_booking_fee FROM platform_settings WHERE key='appointment_booking_fee_cents';`

> ⚠️ Se encontrares `appointment_deposit_cents` na tabela, é **história**, não regra.
> O `business_rules.md` **está desatualizado neste ponto** — ainda não tem rasto do fim
> do sinal. Fica reportado; corrigi-lo é ordem à parte (ver §14).

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
- **Timeout de oferta:** ✅ **resolvido 2026-08-29 — os dois números estão certos, são
  camadas diferentes.** Não é contradição:

  | Camada | Valor | Onde |
  |---|---|---|
  | Servidor (a que manda) | **40 s**, configurável | `supabase/functions/dispatch-engine/index.ts:33` — `const DEFAULT_OFFER_TIMEOUT_SECONDS = 40`, sobreposto por `platform_settings.dispatch_offer_timeout_seconds` (linhas 57 e 69) |
  | Flutter em memória | **10 s**, valor por omissão do construtor | `lib/dispatch/dispatch_engine.dart:18` — `Duration offerTimeout = const Duration(seconds: 10)` |

  O número que decide se a oferta expira de verdade é o do **servidor** — é ele que
  escreve `expiresAt` (`index.ts:276`). O do Flutter só governa o ciclo em memória.
  A chave é editável no painel (`lib/screens/admin/admin_dispatch_settings_screen.dart:35`).
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
- **Ordem** — ✅ **definição canónica encontrada 2026-08-29**, no cabeçalho do
  `carteiro.sh` (linhas 23-26), sob o título *"REGRA DE TAMANHO DE ORDEM (anti
  rate-limit)"*:
  > *"1 ordem = 1 objetivo pequeno (≤15 min de trabalho). Trabalho grande = PÁGINA DE
  > MISSÃO com passos pequenos encadeados. Tarefa que estoura 900s → TIMEOUT + sugestão
  > de dividir, NUNCA a mesma coisa 5x."*

  Ou seja: uma ordem **não** é "uma tarefa qualquer" — é a unidade de trabalho
  deliberadamente pequena da fila, identificada por um `run_id`. Trabalho grande não é
  uma ordem grande; é uma **missão** com ordens pequenas encadeadas (campo `missao:`).
  A regra completa vive em `orquestracao/convencoes.md`.
- **Carteiro** — ✅ **definição canónica encontrada 2026-08-29**, na linha 2-3 do
  próprio `carteiro.sh`:
  > *"dispatcher determinístico do loop de orquestração (corre no HOST do VPS).
  > Campainha → este script → pc-loop (executor) + pc-judge (juiz) → escreve na fila."*

  As paredes de segurança que ele aplica, **pela ordem em que travam** (linhas 5-11):
  `.pausa-total` (o Danilo trava tudo) → `.pausa-rate-limit` (automática) → kill switch
  `_controlo.md` → `zona_vermelha()` (dinheiro + intenção de escrita → humano) → teto de
  5 tentativas → tectos de budget/turns/tools nos `.cmd` do PC.
  Só reabre uma ordem por veredito do Juiz.

## 13. TVDE ida-e-volta — DUAS regras de preço vivas ao mesmo tempo

> 🔴 **ACHADO 2026-08-29.** Isto não é documentação desalinhada: são **dois caminhos de
> código a calcular o preço do mesmo produto de maneiras diferentes**, ambos vivos.
> Não foi corrigido nesta ordem (corrigir cálculo de preço é acto do Danilo).

Existem duas chaves em `platform_settings`, as duas vivas:

| Chave | Valor | Actualizada |
|---|---|---|
| `tvde_roundtrip_price_cents` | `800` (€8 fixo) | 2026-07-03 |
| `tvde_roundtrip_discount_pct` | `20` (% de desconto) | **2026-08-01** (mais recente) |

A pergunta certa não é "qual delas vale" — é **quem lê cada uma**. Provado por leitura
de código:

### Caminho A — o preço que o CLIENTE VÊ usa o desconto (dinâmico, por rota)

`lib/screens/client/tvde/tvde_request_ride_screen.dart:316-324`:

```dart
Future<void> _fetchRoundtripQuote(double km) async {
  final store = context.read<TvdeStore>();
  final quote = await store.quoteRoundtrip(km);
  if (!mounted || quote == null) return;
  setState(() {
    _roundtripPriceCents = (quote['price_cents'] as num?)?.toInt() ?? 0;
    _roundtripSavingCents = (quote['saving_cents'] as num?)?.toInt() ?? 0;
  });
}
```

`lib/stores/tvde_store.dart:1316-1319`:

```dart
Future<Map<String, dynamic>?> quoteRoundtrip(double distanceKm) async {
  try {
    final res = await _sb.rpc('tvde_quote_roundtrip',
        params: {'p_distance_km': distanceKm}).timeout(kAcaoTimeout);
```

A RPC `tvde_quote_roundtrip(p_distance_km)` devolve
`{one_way_cents, full_cents, discount_pct, price_cents, saving_cents}` — é ela que aplica
o `tvde_roundtrip_discount_pct`. O ecrã mostra *"Ida + volta por €X · poupas €Y"*.

> ✅ **Confirmado no corpo da função, em produção** (verificação independente 2026-08-29,
> por quem não escreveu esta secção). `pg_get_functiondef` da RPC contém
> `tvde_roundtrip_discount_pct` e **não** contém `tvde_roundtrip_price_cents`:
>
> ```
> proname              | le_discount_pct             | le_price_cents | tamanho_def
> tvde_quote_roundtrip | tvde_roundtrip_discount_pct | null           | 706
> ```
>
> Isto fecha a pergunta "quem lê cada chave": a cotação do cliente lê **só** a
> percentagem; a cobrança e o push ao motorista lêem **só** o valor fixo. São mesmo dois
> caminhos separados, não uma leitura partilhada.

Foi decisão explícita do Danilo a 2026-08-01 tornar essa % editável no painel
(`admin_platform_settings_screen.dart:78-83`).

### Caminho B — o que a Stripe COBRA usa os €8 fixos

`supabase/functions/tvde-plan-payment/index.ts:117-122` — a Edge Function que cria o
PaymentIntent do pacote **ignora a cotação** e vai buscar a chave antiga:

```ts
      const { data: priceRow } = await rtAdmin
        .from('platform_settings').select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle();
      const amountCents = Number(priceRow?.value ?? 800);
      if (!amountCents || amountCents < 50) {
        return json({ error: 'roundtrip_price_unavailable' }, 400);
      }
```

…e é esse `amountCents` que entra no `stripe.paymentIntents.create({ amount: amountCents, … })`,
tanto no cartão como no MB Way. O Flutter até **envia** a distância a contar que o
servidor recalcule — `tvde_store.dart:1229-1233` manda `'distance_km': distanceKm` — mas
o código da função **não a usa**.

### Caminho C — o que o MOTORISTA é mandado recolher usa os €8 fixos

`supabase/functions/notify-tvde-driver/index.ts:133-141`:

```ts
          if (creditCash && !ride.is_return_leg) {
            let rtPrice = 800
            try {
              const { data: p } = await supabase.from('platform_settings')
                .select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle()
              const v = Number(String(p?.value ?? '800').replace(/\"/g, ''))
              if (Number.isFinite(v) && v > 0) rtPrice = v
            } catch (_e) { /* default */ }
            body = `Nova parada (+€${eur(stopFeeCents)}). Total a cobrar em dinheiro: €${eur(rtPrice + stopsFee)}.`
```

O push diz ao motorista *"Total a cobrar em dinheiro: €X"* com o **€8 fixo**, enquanto o
vale em dinheiro foi criado com o preço dinâmico (`tvde_create_roundtrip_credit_cash`
grava o `paid_cents` real). Os ecrãs do motorista já lêem o `paid_cents` do vale
(`lib/widgets/tvde/tvde_roundtrip_driver_notice.dart:19-24`) — **só a notificação é que
não**.

### O que isto significa, em português

- **O ecrã e a notificação podem mostrar números diferentes ao motorista** para a mesma
  corrida: o aviso no ecrã lê o vale (dinâmico), o push de parada lê os €8.
- **A cobrança online pode não bater com o preço mostrado ao cliente**, se o preço
  dinâmico da rota não der exactamente €8.
- O fallback `800` está **cravado em três sítios** (`index.ts:119`, `index.ts:134`,
  `tvde_roundtrip_driver_notice.dart:17`) — logo, apagar a chave não resolve; o €8
  voltaria à mesma.

> ⚠️ **PARA O DANILO — decisão de dinheiro, não aplicada.** Isto é regra de preço
> duplicada. A correcção (fazer os caminhos B e C lerem a cotação dinâmica) mexe em
> valor cobrado ao cliente e em valor recolhido pelo motorista → 🔴 Lista Vermelha.
> Está diagnosticado e provado; **não foi corrigido**. Espera "vai".

**Atenuante conhecido, não é solução:** o caminho online está atrás de um interruptor —
`allowOnline: _cardEnabled` (`tvde_request_ride_screen.dart:788`), e `_cardEnabled` nasce
`false` (linha 93), só ligando por definição. E o próprio ecrã regista (linhas 792-806)
que a `tvde-plan-payment` local **está bloqueada para deploy** (chama
`tvde_create_roundtrip_credit` com 6 argumentos e produção tem 4). O caminho C (push ao
motorista) **não** tem atenuante nenhum.

## 14. O que continua por decidir — bloco PARA O DANILO

> Só fica aqui o que **depende mesmo de uma decisão dele**. Tudo o que se resolvia a ler
> código ou base de dados foi resolvido a 2026-08-29 e está em cima, como facto.

1. **TVDE ida-e-volta — qual das duas regras fica?** (ver §13). Não é dúvida de
   documentação, é código a divergir. 🔴 dinheiro.
2. **Corrigir o `business_rules.md`**, que está desactualizado em **três** pontos já
   provados: a janela de cancelamento de reserva (diz 4 h, é **2 h** — §7); o fim do
   sinal de €3 nas marcações (não tem rasto — §7-A); e o €8 fixo do TVDE. O
   `business_rules.md` é a 1.ª autoridade, por isso corrigi-lo é ordem própria — **não
   foi tocado nesta ordem**, por instrução expressa.
3. **Corrigir os tokens do cliente no `CLAUDE.md` e na skill `ceo-ai`** — ambos ainda
   dizem *"3% do valor"*. Está **provado** que é **3 tokens por euro**: o trigger passou
   de `ROUND(NEW.price * 0.03)` (`20260404000000_bora_tokens.sql:163`) para
   `GREATEST(1, ROUND(NEW.price * 3)::INTEGER)`
   (`20260425000002_batch_d_tokens.sql:44`, mantido em
   `20260507223228_fix_7e_b_bug_005_bug_007_tokens_uuid_to_text.sql:79`). O
   `business_rules.md` já está certo. 🔴 mexe em tokens → só o Danilo aplica.

### Já resolvidos nesta ordem (não voltar a abrir)

| Era `POR CONFIRMAR` | Resolução | Onde |
|---|---|---|
| Sinal €3 nas marcações | Não existe. Taxa viva = €0,50 por marcação concluída | §7-A |
| Cancelamento de reserva 2 h ou 4 h | **2 h** | §7 |
| Timeout de dispatch 40 s ou 10 s | Ambos: 40 s servidor, 10 s Flutter em memória | §9 |
| Definição de "Ordem" | ≤15 min, 1 objetivo; trabalho grande = missão | §12 |
| Definição de "Carteiro" | Dispatcher determinístico no host do VPS | §12 |
| Tokens do cliente 3% ou ×3 | **×3** (provado no trigger, não só na doc) | §14.3 |
