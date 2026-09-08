# ⚠️ ISTO MEXE EM DINHEIRO — taxa de pedido pequeno invisível no cliente

> Encontrado a 2026-09-08 na missão `ios-lancamento`, de caminho, ao investigar
> porque é que o interruptor 5.2.1 não funcionava. **Nada foi aplicado.**
> Está tudo pronto; falta o "vai" do Danilo.

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

## Nota de rumo

Vale a pena procurar **outros** sítios com o mesmo padrão: qualquer coisa que
leia `platform_settings` no arranque tem este problema. Já se sabe de dois — o
interruptor 5.2.1 e esta taxa. Um terceiro passaria despercebido da mesma
maneira, porque nenhum deles dá erro.
