# ⚠️ DINHEIRO — dois achados: um já corrigido, outro ainda aberto

> ## LEIA ISTO PRIMEIRO — correcção de 2026-09-08, 15h
>
> Quando escrevi este relatório, disse *"não apliquei nada, está pronto, falta
> o vai"*. **Metade já não é verdade.** Enquanto eu trabalhava, uma **outra
> sessão autónoma** estava a mexer no mesmo ramo e no mesmo assunto:
>
> - `8dc5d011` (13:22) — *"a taxa de serviço das lojas sem contrato já é 0,99"*
> - `799e9523` (14:57) — *"a taxa de pedido pequeno já era cobrada pelo
>   servidor e o cliente não a via"*
>
> O `799e9523` aplicou **exactamente** as duas mudanças que eu descrevo aqui em
> baixo: o `if (lista.isEmpty) … return;` no `small_order_fee.dart` e o
> `SmallOrderFeeService.carregarGlobal(forcar: true)` no `main.dart` (linha
> 357). Verificado no código, não no título do commit.
>
> **Estado real:**
>
> | Achado | Estado |
> |---|---|
> | 1 — taxa de pedido pequeno invisível | ✅ **corrigido** em `799e9523`, por outra sessão |
> | 2 — taxa do não-parceiro a €2,50 em vez de €0,99 | ⚠️ **ainda aberto** |
>
> O achado 2 continua de pé: `payment_method_screen.dart:407` ainda faz
> `value: pricing.serviceFee` (a constante protegida, €2,50) e só o campo
> `riscado` vem do `RemoteFeesService`. O `8dc5d011` atacou este assunto mas
> só o risco chegou ao ecrã.
>
> A captura `07-loja-pagamento.png` que mostra €8,75 é da corrida
> `34229774614`, construída de `150b81e1` — **anterior** ao `799e9523`
> (confirmado com `git merge-base --is-ancestor`). Era verdade para aquele
> build; para o achado 1, já não é para o de agora.

> Escrito a 2026-09-08 na missão `ios-lancamento`, ao investigar porque é que o
> interruptor 5.2.1 não funcionava. **Eu não apliquei nada** — o que está
> aplicado veio da outra sessão.

## O que está a acontecer

O **servidor** cobra a taxa de pedido pequeno. O **cliente** não a mostra.

### Provado, lado do servidor

- `platform_settings`: `small_order_fee_enabled = true`,
  `min_order_cents = 1200` (€12,00), `small_order_fee_cents = 139` (€1,39).
- Função `small_order_fee_calc(service_type, subtotal, restaurant_id)` lê essas
  chaves **dentro da base de dados**, onde a RLS não a trava.
- Gatilho **`orders_aa_small_order_fee`**, `BEFORE INSERT` em `orders`,
  **`tgenabled = O` (ligado)**, chama `fn_small_order_fee` e escreve
  `NEW.small_order_fee`.

Ou seja: toda a encomenda de `restaurant` ou `storeShopping` abaixo de €12 leva
€1,39 acrescentados pelo servidor.

### Provado, lado do cliente

- `lib/main.dart:532` chama `unawaited(SmallOrderFeeService.carregarGlobal())`
  **no arranque, antes de haver sessão**.
- `platform_settings` tem RLS com **uma única** política de leitura, e é para
  **autenticados**. Medido contra a produção:

  ```
  anónimo      GET /rest/v1/platform_settings?key=eq....  ->  HTTP 200, corpo []
  autenticado                                             ->  HTTP 200, [{"value":true}]
  ```

- Um corpo vazio **não é erro**, por isso o `catch` nunca dispara. O mapa
  `valores` fica vazio, e a configuração fica
  `enabled=false, minCents=0, feeCents=0`.
- A seguir faz-se `_globalCarregado = true`, e o método começa por
  `if (_globalCarregado && !forcar) return;` — **nunca mais tenta**.

O comentário do próprio ficheiro diz *"A regra aqui é o espelho exacto da função
`small_order_fee_calc` do servidor — mudar uma obriga a mudar a outra, senão
cliente e servidor deixam de bater ao cêntimo."* É exactamente o que está a
acontecer, sem ninguém ter mudado nada: o espelho nunca chega a ser lido.

### O que ainda NÃO está observado

Não vi, com os meus olhos, um carrinho real a mostrar o total sem os €1,39.
Segue-se do que está acima, mas segue-se por raciocínio, não por fotografia. A
corrida do CI em curso leva um cesto de **€3,65** (uva branca da Auchan) e
fotografa o carrinho e o pagamento — essas duas imagens confirmam ou desmentem
isto de vez.

## A correcção, pronta e por aplicar

É a mesma forma da que já se aplicou ao interruptor 5.2.1 (essa não mexe em
dinheiro e por isso foi aplicada). Em `lib/main.dart`, no
`onAuthStateChange` que já existe:

```dart
if (state.event == AuthChangeEvent.signedIn ||
    state.event == AuthChangeEvent.initialSession ||
    state.event == AuthChangeEvent.tokenRefreshed) {
  unawaited(PushTokenService.registerCurrentDeviceAutoDetect());
  unawaited(carregarIosHideNonPartnerLogos(forcar: true));   // já aplicado
  unawaited(SmallOrderFeeService.carregarGlobal(forcar: true)); // ⚠️ POR APLICAR
}
```

E, em `lib/services/small_order_fee.dart`, não marcar como carregado quando a
resposta vem vazia — senão a primeira leitura falhada continua a fechar a porta:

```dart
if (valores.isEmpty) {
  debugPrint('[SmallOrderFee] sem linhas (sem sessão?) — tenta-se depois de entrar.');
  return;                       // ⚠️ POR APLICAR: não marcar como carregado
}
```

## Porque não apliquei

`CLAUDE.md`, Lista Vermelha: **preços, taxas e comissões** não se alteram sem o
"vai" do Danilo. Aplicar isto faz aparecer €1,39 num carrinho onde hoje não
aparece — muda o que o cliente vê que vai pagar. É uma correcção que torna o
cliente honesto com o servidor, mas é dinheiro, e dinheiro espera.

**⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu
aplico.**

## Isto já mordeu antes, e em dinheiro

Não é teoria. O commit **`5bdc7379`** chama-se
*"fix(cliente): a taxa de servico das lojas sem contrato ja e 0,99 -- a app e
que ainda dizia 2,50"*: a app mostrava €2,50 quando a taxa real era €0,99,
porque as definições eram lidas antes de haver sessão. A cura foi exactamente
esta — acrescentar `RemoteFeesService.carregar(forcar: true)` ao
`onAuthStateChange` — e o comentário que lá ficou diz *"Mesma cicatriz, mesma
cura"*.

O `SmallOrderFeeService` ficou para trás com o mesmo defeito. Não é um risco
hipotético: é a repetição de um erro que já custou uma correcção.

## ⚠️ SEGUNDO ACHADO, E MAIOR — a taxa do não-parceiro está €1,51 acima

**Observado, não deduzido.** A captura `07-loja-pagamento.png` da corrida
`34229774614` mostra, num cesto da Auchan (loja **sem contrato**):

```
Subtotal            3,65
Taxas               2,50      <-- aqui
Entrega             2,50
Saco para viagem    0,10
Total a pagar       8,75
```

O que o servidor diz que se cobra hoje:
`platform_settings.non_partner_service_fee_cents = **99**` (€0,99), com
`non_partner_service_fee_strikethrough_cents = 250` a ser apenas o valor
**antigo, para mostrar riscado**.

O cabeçalho de `lib/services/remote_fees_service.dart` explica porquê, e é o
próprio ficheiro que o assume: a taxa desceu de €2,50 para €0,99 a 08/09, *"o
servidor já cobra 0,99 €"*, mas o número que a app usa vive na constante
`_nonPartnerPurchaseFee = 2.5` dentro de `lib/services/pricing_service.dart`,
que é **zona protegida — a Trava proíbe editá-la**. O `RemoteFeesService` foi
o caminho de fuga, mas em `payment_method_screen.dart:404-412` só alimenta o
**valor riscado**; o valor a sério continua a vir do `PricingService`:

```dart
_SummaryRow(label: 'Taxas'.tr,
           value: pricing.serviceFee,          // <- constante velha, 2,50
           riscado: cartStore.taxaServicoRiscada)
```

**Porque é que isto é pior do que parecer feio:** o método escolhido é
**dinheiro**. Em dinheiro, o total do ecrã é o que o estafeta cobra à porta.
O cliente paga €8,75 quando, pela tabela do servidor, seriam €7,24.

**Não toquei em nada.** `pricing_service.dart` é zona protegida e taxas são
Lista Vermelha — as duas coisas ao mesmo tempo. A dívida técnica já estava
assumida por escrito no `remote_fees_service.dart`; o que é novo é a prova de
que ela chega ao ecrã de pagamento e ao total.

## Haverá um terceiro? Fui ver — não há

Fora dos ecrãs de admin, cinco ficheiros lêem `platform_settings`
directamente. Só três é que importam, porque só esses correm fora de um ecrã:

| Ficheiro | Quando lê | Estado |
|---|---|---|
| `config/ios_launch_flags.dart` | arranque | **corrigido** hoje |
| `services/remote_fees_service.dart` | arranque | **corrigido** em `5bdc7379` |
| `services/small_order_fee.dart` | arranque | ⚠️ **é este relatório** |
| `services/payment_service.dart` | na hora de pagar, com sessão | sem problema |
| `stores/carwash_store.dart` | ao abrir a lavagem, com sessão | sem problema |

A lista das chamadas do arranque está toda em `lib/main.dart`, nos
`unawaited(...)` — são cinco, e nenhuma outra toca em `platform_settings`.
**Não há um terceiro caso escondido.** Com este resolvido, o padrão fica
fechado.
