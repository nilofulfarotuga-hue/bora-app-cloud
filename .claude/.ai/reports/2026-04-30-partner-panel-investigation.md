# Partner Panel — Investigação T4.1

> 2026-04-30, sem screenshots do Danilo. Investigação automática.

## Estado estático do código

- `lib/screens/partner_dashboard_screen.dart` — 1073 linhas
- `flutter analyze` retorna **1 issue** (info, não-bloqueante):
  - `partner_dashboard_screen.dart:1001` — `activeColor` deprecated (Material 3)
- Imports OK. Provider chain OK (`OrderStore`, `PartnerProductStore`, `RestaurantStore`).
- Realtime: usa `context.watch<OrderStore>()` que reage a `orders_channel` realtime updates (idempotente em `OrderStore._subscribeRealtime`).

## Git history (4 semanas)

```
9e9d7aa fix: activeThumbColor → activeColor (compat Flutter 3.27.4)
d4c25fd fix: pagamentos, markup 15%, botão valor final estafeta
0f599e3 Batch E: partner onboarding solid + product mutations with rollback
17c49ce update
2a34981 bora app ready
```
Sem regressões evidentes. `Batch E` reforçou o painel.

## Hipóteses para "bagunça" (root cause provável)

### 1. Push Firebase não configurado → sem som em pedido novo (Bug A)
- `SoundService` usa `audioplayers` localmente — apenas toca quando o evento dispara em runtime do partner app
- Sem push Firebase, parceiro só ouve som **se a app estiver em foreground** (realtime channel entrega o evento)
- App em background → sem push → sem som → "perdi o pedido"
- **Fix:** resolver T3.2 (`google-services.json` iOS + Firebase secrets) — ver [`2026-04-30-firebase-status.md`](2026-04-30-firebase-status.md)

### 2. `--dart-define-from-file=.dart_defines` em falta no shortcut do Danilo
- Se Danilo correu `flutter run` sem o flag, a app inicia com `String.fromEnvironment('SUPABASE_URL')=='`'
- Resultado: client Supabase não autentica → painel parece vazio + crashes silenciosos
- Comando correcto: `flutter run --dart-define-from-file=.dart_defines`

### 3. UI: Switch deprecation `activeColor`
- Não-bloqueante. Pode tornar a cor "off" no Material 3 mas não quebra runtime.
- Fix trivial: `activeColor: c` → `activeThumbColor: c` (1 linha).

### 4. Possível cache desactualizado
- Se Danilo nunca correu `flutter clean` desde Batch E, pode haver state stale no Hot Restart.
- Fix: `flutter clean && flutter pub get && flutter run --dart-define-from-file=.dart_defines`

## Acção tomada nesta sessão

- Fix do deprecation `activeColor` no line 1001 (cosmético, 1 linha).
- Demais 3 hipóteses dependem de teste em device real com Firebase configurado.

## Próximos passos (Danilo)

1. Resolver T3.2 (Firebase) — destrava som + push
2. Correr `flutter clean && flutter run --dart-define-from-file=.dart_defines` no device parceiro
3. Se ainda houver "bagunça", capturar screenshots + `adb logcat | grep -i flutter` (Android) ou Xcode console (iOS) e partilhar log
