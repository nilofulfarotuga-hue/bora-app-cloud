# BLOCO D4 — Chamada em falta no checkout: `garantirContactoDoCliente()` ⚠️→✅

> Missão: ligar ao botão de checkout um helper já escrito e validado, identificado no
> relatório `TUDO-04-09-NOITE-2026-09-04.md` (BLOCO C, item "Por fazer: C.3").
> Executor: agente `cliente` (proposto como opus por tocar checkout — confirmado NÃO
> financeiro antes de aplicar).

## O que estava em falta

O relatório de 2026-09-04 (`.claude/.ai/reports/TUDO-04-09-NOITE-2026-09-04.md`, linhas
143-144 e 238) registava:

> **Por fazer: C.3** — ligar o `garantirContactoDoCliente()` ao checkout. O helper está
> escrito e testado pelo analisador; falta a chamada no botão de fechar pedido.

O helper `garantirContactoDoCliente(BuildContext)` vive em
`lib/screens/complete_profile_screen.dart:182-195`. É a "porta única" de validação de
contacto (nome ≥3 letras + telemóvel PT 9 dígitos) que reservas, limpeza e corridas já
chamam — só faltava o checkout de delivery/loja (`cart_screen.dart`).

Só existia um aviso não-bloqueante uma vez por arranque em `client_main_screen.dart`
(`_pedirContactoUmaVez`) — comentário no próprio ficheiro já dizia "o bloqueio a sério é
no checkout — ver `garantirContactoDoCliente`", confirmando que a intenção sempre foi
chamá-lo ali.

## Verificação: zona sensível?

**NÃO.** `garantirContactoDoCliente()`:
- Lê `AuthStore.currentClient` (nome/telefone).
- Se incompleto, abre `CompleteProfileScreen` (UI de formulário) e devolve `true/false`.
- Não calcula preço, não chama `PricingService`, não toca `finalizePurchase`, Stripe,
  `bora_tokens` ou qualquer coluna monetária.

É validação de dados de contacto/UI — fora da Lista Vermelha. Avançou-se sem pedir
confirmação ao Danilo, conforme a instrução do bloco.

Confirmei também que **nenhum teste automatizado dedicado existe** para este helper
(`test/` não tem ficheiro `contact_validators`/`complete_profile` — pesquisado por
`garantirContactoDoCliente`, `contactoDoClienteCompleto`, `contact_validators`, todos sem
match). "Testado pelo analisador" no relatório de origem refere-se ao `flutter analyze`
limpo, não a testes unitários — não havia suite a correr.

## Onde a chamada foi ligada

`lib/screens/cart_screen.dart`, botão **"Finalizar pedido"** (`_CheckoutPanelState`,
`BoraAccentButton` que navega para `PaymentMethodScreen`). É o único CTA de fecho de
pedido do fluxo de delivery/loja/mercado — o "botão de fechar pedido" do relatório.

Chamada inserida como **primeiro passo** do `onPressed`, antes de qualquer lógica de
carteira/pricing/festas, para bloquear cedo:

```dart
import 'complete_profile_screen.dart' show garantirContactoDoCliente;
...
onPressed: cartStore.items.isEmpty
    ? null
    : () async {
        // BLOCO C.3 (2026-09-05) — porta única de contacto: sem
        // nome/telemóvel válidos, o cliente é bloqueado aqui
        // antes de seguir para pagamento (ver
        // garantirContactoDoCliente em complete_profile_screen.dart).
        final contactoOk = await garantirContactoDoCliente(context);
        if (!contactoOk || !context.mounted) return;

        cartStore.setWalletApplied(
            _useWalletBalance ? walletAppliedCents : 0);
        ... (fluxo existente, intocado)
```

Se o cliente tiver nome/telefone completos, `contactoDoClienteCompleto(...)` devolve
`true` de imediato e o helper nem abre ecrã — sem fricção para quem já está em dia.
Se faltar, abre `CompleteProfileScreen(bloqueante: true)`; só continua para
`PaymentMethodScreen` se o utilizador completar o perfil (`ok == true`).

Nada mais no botão foi tocado — pricing, wallet, festas e navegação pós-pagamento
mantêm-se exactamente como estavam.

## Prova

### `flutter analyze`
0 erros (categoria `error`). 213 issues no total, todas `info`/`warning` pré-existentes
(deprecations, const constructors, imports não usados noutros ficheiros) — nenhuma nova
issue nas linhas alteradas de `cart_screen.dart` (só 3 `info` de `activeColor` deprecated
em linhas 337/358/422, pré-existentes e não relacionadas com esta mudança).

```
$ flutter analyze 2>&1 | grep -c "^error"
0
```

### Testes
Não há teste unitário/widget dedicado ao helper `garantirContactoDoCliente` nem a
`contact_validators.dart` no repo (`test/` pesquisado, sem match) — não havia suite para
correr. Não é regressão desta tarefa: o helper já não tinha cobertura própria antes.

### Diff aplicado
```diff
diff --git a/lib/screens/cart_screen.dart b/lib/screens/cart_screen.dart
index 044046b4..e463b1ae 100644
--- a/lib/screens/cart_screen.dart
+++ b/lib/screens/cart_screen.dart
@@ -13,6 +13,7 @@ import '../stores/restaurant_store.dart';
 import '../widgets/bora/bora.dart';
 import '../widgets/takeaway/curbside_inputs.dart';
 import '../widgets/tip_selector.dart';
+import 'complete_profile_screen.dart' show garantirContactoDoCliente;
 import 'festas_quando_screen.dart';
 import 'orders_screen.dart';
 import 'payment_method_screen.dart';
@@ -541,6 +542,14 @@ class _CheckoutPanelState extends State<_CheckoutPanel> {
               onPressed: cartStore.items.isEmpty
                   ? null
                   : () async {
+                      // BLOCO C.3 (2026-09-05) — porta única de contacto: sem
+                      // nome/telemóvel válidos, o cliente é bloqueado aqui
+                      // antes de seguir para pagamento (ver
+                      // garantirContactoDoCliente em complete_profile_screen.dart).
+                      final contactoOk =
+                          await garantirContactoDoCliente(context);
+                      if (!contactoOk || !context.mounted) return;
+
                       cartStore.setWalletApplied(
                           _useWalletBalance ? walletAppliedCents : 0);
```

## Fecho

- **Ecrã tocado:** `lib/screens/cart_screen.dart` (botão "Finalizar pedido" do
  `_CheckoutPanel`).
- **Regra aplicada:** porta única de contacto (`garantirContactoDoCliente`) — mesma regra
  já usada por reservas/limpeza/corridas, agora também no checkout de delivery.
- **Zona:** não-financeira — validação de perfil, sem tocar `pricing_service`, Stripe,
  `finalizePurchase` ou `bora_tokens`. Aplicado directamente, sem necessidade de
  confirmação do Danilo.
- **Admin?** Não gera necessidade de painel novo — é gate de UI sobre dados que o admin
  já vê (perfil de cliente). Sem ação adicional.
- **Estado:** ✅ aplicado e validado (`flutter analyze` 0 erros).
