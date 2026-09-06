# Google Pay Setup — pendente Danilo

> Status: BUG 9 mitigado em F5 (Google Pay temporariamente escondido no PaymentSheet).
> Pré-requisito antes de re-enable: completar 4 passos abaixo no Stripe Dashboard + Google Play Console.

## Contexto

`bora_app/lib/services/payment_service.dart` configurava previamente `googlePay: PaymentSheetGooglePay(merchantCountryCode: 'PT')`. Em LIVE com a app não-publicada, isto causa falha visível ao utilizador (sheet abre mas Google Pay opção não funciona).

Decisão F5: passar `googlePay: null` até infraestrutura estar verificada. Apple Pay continua activo.

## Passos para reactivar

### 1. Stripe Dashboard
- Login: https://dashboard.stripe.com/
- Settings → Payment methods → Procurar "Google Pay"
- Click "Turn on" / "Activate"
- Confirmar `merchantCountryCode='PT'` está suportado (deve estar — Portugal está na lista de países PT/EU)

### 2. Domain verification (Stripe)
- Stripe → Settings → Payment method domains
- Adicionar o(s) domínio(s) onde a app for usada (web). Para mobile-only NÃO é estritamente necessário em test, mas LIVE recomenda.
- Se app é exclusivamente Android: skip (Google Pay em apps usa SHA-1 não domain).

### 3. Android Play Console
- Login: https://play.google.com/console/
- Bora App → Setup → App signing → copiar **SHA-1 fingerprint** (release).
- Comando alternativo local (release keystore):
  ```bash
  keytool -list -v -keystore /path/to/release.keystore -alias YOUR_ALIAS
  ```
- Em **Stripe Dashboard → Settings → Connect → Apps**, registar o package name `com.example.bora_app` (substituir pelo real) + SHA-1.

### 4. Test no test mode primeiro
- Trocar `STRIPE_PUBLISHABLE_KEY` no `.dart_defines` para `pk_test_...`.
- Re-enable o `googlePay:` em `payment_service.dart` com `testEnv: true` durante test:
  ```dart
  googlePay: const PaymentSheetGooglePay(
    merchantCountryCode: 'PT',
    currencyCode: 'EUR',
    testEnv: kDebugMode, // true em debug, false em release
  ),
  ```
- Testar com Test Card "4242 4242 4242 4242" via Google Pay (test mode aceita).
- Quando OK: rebuild release com `pk_live_...` no `.dart_defines`.

## Smoke test após reactivar
1. Open app em Android device com Google Pay configurado.
2. Add to cart, proceed to checkout, select card.
3. Stripe sheet deve mostrar tile "Pay with Google" no topo.
4. Pagar → order criada via flow novo (BUG 1 / F2).

## Quem reactiva
Danilo após confirmar setup Stripe Dashboard. Avisar CEO-AI para fazer:
1. Edit `payment_service.dart` removendo `googlePay: null` e restaurando `PaymentSheetGooglePay(...)`.
2. Smoke test E2E em dispositivo real.
3. Commit `feat(stripe): re-enable Google Pay after dashboard setup`.

## Tempo estimado
- Stripe Dashboard: 5 min
- SHA-1 + registo: 10 min
- Test test mode: 10 min
- Re-enable + commit: 5 min
- Total: ~30 min
