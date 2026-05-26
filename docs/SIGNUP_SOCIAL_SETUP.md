# Signup — Apple/Google Sign-In + SMS OTP Setup

Checklist de configuração externa para activar:
- **Apple Sign-In** (mandatório se houver outro social no iOS — App Store guideline 4.8)
- **Google Sign-In**
- **SMS OTP** (verificação de telemóvel ao estilo Uber/Glovo)

UI já está implementada atrás de feature flags:
- `--dart-define=SOCIAL_AUTH_ENABLED=true` → mostra botões Apple/Google no RegisterClientScreen
- `--dart-define=SMS_OTP_ENABLED=true` → activa step SMS OTP (a implementar quando Twilio estiver configurado)

---

## 1. Apple Sign-In

### Apple Developer Console
1. Sign in em https://developer.apple.com
2. Certificates, IDs & Profiles → Identifiers → seleccionar o App ID `pt.boraapp.bora` (Android) ou `com.bora.app` (iOS bundle id)
3. Activar capability **Sign In with Apple** + Save
4. Criar **Services ID** (Identifiers → + → Services IDs):
   - Description: `Bora App Web`
   - Identifier: `pt.boraapp.bora.web`
   - Activar Sign In with Apple
   - Configure → adicionar Domain `ojykpzwqrtusfeakzrna.supabase.co` + Return URL `https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/callback`
5. Criar **Key**: Keys → + → Sign in with Apple → Configure → seleccionar App ID
   - Download `.p8` (só uma vez!)
   - Anotar Key ID + Team ID

### Gerar Client Secret JWT
Apple exige JWT ES256 assinado com a key `.p8`. Validade máxima 6 meses.

```bash
# Usar https://github.com/oscarotero/applesignin-js ou implementação manual
# OU usar https://gist.github.com/m-mitsuhide/5410039a5a1ea8e7e3c1
```

Guardar JWT gerado — vai como Supabase Auth Apple provider `Secret Key`.

### Supabase Dashboard
1. Authentication → Providers → Apple → Enable
2. Client IDs: `pt.boraapp.bora.web,pt.boraapp.bora` (vírgula entre web service id e bundle id)
3. Secret Key (for OAuth): JWT gerado
4. Save

### iOS (lib/Runner)
1. Xcode → Runner → Signing & Capabilities → + Capability → Sign In with Apple
2. `ios/Runner/Runner.entitlements`:
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array><string>Default</string></array>
   ```

### Android (deeplink)
1. `android/app/src/main/AndroidManifest.xml` adicionar dentro do `<activity android:name=".MainActivity">`:
   ```xml
   <intent-filter android:autoVerify="true">
     <action android:name="android.intent.action.VIEW" />
     <category android:name="android.intent.category.DEFAULT" />
     <category android:name="android.intent.category.BROWSABLE" />
     <data android:scheme="pt.boraapp.bora" android:host="login-callback" />
   </intent-filter>
   ```

### Código Flutter (a adicionar quando activar)
Adicionar `sign_in_with_apple: ^6.1.4` ao `pubspec.yaml`. Substituir o TODO em `register_client_screen.dart::_signInWithApple` por:

```dart
final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
);
await Supabase.instance.client.auth.signInWithIdToken(
  provider: OAuthProvider.apple,
  idToken: credential.identityToken!,
);
```

---

## 2. Google Sign-In

### Google Cloud Console
1. https://console.cloud.google.com → criar/seleccionar projecto `bora-app`
2. APIs & Services → Credentials → + CREATE CREDENTIALS → OAuth client ID
3. Criar 3 clients:
   - **Web application** (vai para Supabase): URI redirect = `https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/callback`
   - **Android**: package `pt.boraapp.bora` + SHA-1 do keystore release (ver `project_keystore_release_2026_05_20` — SHA256 9E:DC:FC:81... — precisa também de SHA-1 que se obtém via `keytool -list -v -keystore bora-app-release.jks -alias bora-app-release`)
   - **iOS**: bundle id `com.bora.app`
4. OAuth consent screen → External → preencher logo, suporte, política privacidade

### Supabase Dashboard
1. Authentication → Providers → Google → Enable
2. Client ID (for OAuth): client ID do **Web** acima
3. Client Secret (for OAuth): secret do **Web**
4. Authorized Client IDs (comma-separated): Android client ID, iOS client ID, Web client ID

### iOS (Info.plist)
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>com.googleusercontent.apps.XXXXXXXX</string></array>
  </dict>
</array>
```
(substituir XXXXXXXX pelo reversed client ID do iOS OAuth client)

### Código Flutter
Adicionar `google_sign_in: ^6.2.1` ao pubspec. Substituir TODO em `_signInWithGoogle`:

```dart
final googleUser = await GoogleSignIn(
  serverClientId: 'WEB_CLIENT_ID.apps.googleusercontent.com', // Web client ID
).signIn();
final auth = await googleUser!.authentication;
await Supabase.instance.client.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: auth.idToken!,
  accessToken: auth.accessToken,
);
```

---

## 3. SMS OTP (Twilio)

### Twilio
1. https://console.twilio.com → criar conta (sandbox grátis)
2. Phone Numbers → Buy → comprar número PT (~€1/mês) OU usar Messaging Services (recomendado para PT)
3. Account SID + Auth Token → copiar
4. Verify → criar Service `bora-verify`

### Supabase Dashboard
1. Authentication → Providers → Phone → Enable
2. SMS Provider: Twilio
3. Twilio Account SID
4. Twilio Auth Token
5. Twilio Message Service SID OU From Phone Number
6. (opcional) Custom SMS template: `O teu código Bora: {{ .Code }}`

### Código Flutter (a adicionar)
1. Adicionar novo step no `RegisterClientScreen`: após user submeter dados, em vez de chamar `registerClientAsync` directo, primeiro chamar `supabase.auth.signInWithOtp(phone: '+351...')` para enviar OTP. Mostrar ecrã `OtpVerifyScreen` para receber 6 dígitos.
2. Validar com `supabase.auth.verifyOTP(type: OtpType.sms, phone, token)`.
3. Após verifyOTP OK, fazer `registerClientAsync` com password.

### Custos PT
- Twilio Verify: ~€0.07/SMS PT
- Estimar conversão: se 1000 signups/mês, custo ~€70/mês

---

## 4. Activação

Após config externa completa:

```bash
flutter run \
  --dart-define-from-file=.dart_defines \
  --dart-define=SOCIAL_AUTH_ENABLED=true \
  --dart-define=SMS_OTP_ENABLED=true
```

Para Codemagic, adicionar variáveis no workflow:
```yaml
environment:
  vars:
    SOCIAL_AUTH_ENABLED: "true"
    SMS_OTP_ENABLED: "true"
```

---

## 5. Test plan

Após cada provider activado:
1. APK fresh install → tela signup
2. Botão Apple/Google → completar OAuth → conta criada em Supabase
3. Verificar `auth.users.raw_user_meta_data.provider` = `apple` / `google`
4. Verificar `public.users` row criada via trigger ou no app
5. Admin panel → cliente aparece com foto + nome do provider
