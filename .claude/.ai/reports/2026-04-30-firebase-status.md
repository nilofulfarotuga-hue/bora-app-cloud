# Firebase Push — Estado actual (T3.2)

> Verificação automática 2026-04-30. Bloqueadores claros para Danilo.

## ✅ O que está bem

- `android/app/google-services.json` presente (676 bytes)
  - Project: `boraapp-d2bea`
  - Project number: `765097014497`
  - Mobile SDK app id: `1:765097014497:android:e8d6670257e0e7b84ef3a0`
- Plugin `com.google.gms.google-services` aplicado em `android/app/build.gradle.kts`
- pubspec inclui `firebase_core: ^3.0.0` + `firebase_messaging: ^15.0.0`
- 3 Edge Functions deployed: `notify-driver` v9, `notify-client` v5, `notify-partner` v5

## ❌ Bloqueadores

### 1. iOS — `GoogleService-Info.plist` não existe
- Path esperado: `ios/Runner/GoogleService-Info.plist`
- **Acção Danilo:**
  1. Firebase Console → Project `boraapp-d2bea` → Settings → Adicionar app iOS
  2. Bundle ID: usar o do Xcode (provavelmente `com.bora.app` se renomeado, senão `com.example.bora_app`)
  3. Download `GoogleService-Info.plist`
  4. Drag para `ios/Runner/` no Xcode (NÃO copiar à mão — tem de estar registado no projeto)

### 2. `applicationId` ainda é `com.example.bora_app` (default Flutter)
- File: `android/app/build.gradle.kts:applicationId`
- Para produção deve ser único (ex: `com.bora.app` ou `com.borapp.delivery`)
- **Atenção:** se mudar, o `google-services.json` actual fica inválido — tem de re-download do Firebase Console com novo package name
- **Acção Danilo:** decidir bundle ID definitivo agora (afecta também App Store + Play Store)

### 3. Firebase service account JSON ausente nas Edge Function env vars
Verificado: `vault.decrypted_secrets` não tem nenhum secret com `firebase`/`fcm`/`google`.

As 3 Edge Functions `notify-*` precisam destes secrets para chamar a Firebase Cloud Messaging API:
- `FIREBASE_PROJECT_ID` = `boraapp-d2bea`
- `FIREBASE_CLIENT_EMAIL` = email do service account
- `FIREBASE_PRIVATE_KEY` = private key raw (com `\n` reais, **não** `\\n`)

**Acção Danilo:**
1. Firebase Console → Project Settings → Service Accounts → "Generate new private key"
2. Download JSON (guardar offline, é confidencial)
3. Supabase Dashboard → Project Settings → Edge Functions → Secrets:
   - Add `FIREBASE_PROJECT_ID` = `boraapp-d2bea`
   - Add `FIREBASE_CLIENT_EMAIL` = valor do JSON `client_email`
   - Add `FIREBASE_PRIVATE_KEY` = valor do JSON `private_key` (substituir `\n` literais por newlines reais)
4. Re-deploy as 3 funções:
   ```bash
   supabase functions deploy notify-driver
   supabase functions deploy notify-client
   supabase functions deploy notify-partner
   ```

### 4. Smoke test E2E push real (após pontos 1-3)
**Acção Danilo:**
1. Criar pedido cliente (real ou demo) com cliente que tem `fcm_token` populado
2. Verificar driver app recebe push real
3. Aceitar pedido → cliente recebe push "estafeta a caminho"
4. Push parceiro: aceitar pedido → som no painel parceiro

Se push não chega:
- `select * from mbway_debug_errors order by created_at desc limit 5` (tem log de Edge Fn errors)
- Verificar `users.fcm_token` populado para o user
- Verificar permissions concedidas no device

## Bug A (parceiro sem som) — relação com push

Bug A reportado: parceiro não toca som em pedido novo.
Causa provável (sem screenshots): Edge Function `notify-partner` falha silenciosamente porque os secrets Firebase não estão configurados — o som dispara via push, sem push não há som.

Ao resolver pontos 1-3 acima, Bug A é provavelmente fixado em paralelo.

## Decisão de scope desta sessão (T3.2)

Não tocar em código Firebase mais — bloqueadores 1+2+3 exigem acções manuais Danilo. Após Danilo resolver, re-correr smoke test ponto 4.
