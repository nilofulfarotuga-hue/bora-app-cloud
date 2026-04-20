# Firebase Push Notifications — Setup Guide

## Estado actual (2026-04-14)

O código está **100% pronto** para Firebase. Só faltam os ficheiros de configuração que tens de gerar na Firebase Console.

O build Android **vai falhar** até adicionares o `google-services.json`. O iOS compila mas as notificações não chegam sem o `GoogleService-Info.plist`.

---

## Passo 1 — Criar projecto Firebase

1. Vai a [console.firebase.google.com](https://console.firebase.google.com)
2. Clica **"Add project"** → Nome: `Bora App`
3. Desactiva Google Analytics (não precisas)
4. Clica **"Create project"**

---

## Passo 2 — Adicionar app Android

1. No teu projecto Firebase, clica no ícone Android (**`</>`**)
2. **Android package name:** verifica em `android/app/build.gradle`, campo `applicationId`
   - Se ainda não mudaste: é provavelmente `com.example.bora_app`
   - Recomendado: muda para `com.boraapp.app` antes de publicar na Play Store
3. App nickname: `Bora App Android`
4. Clica **"Register app"**
5. **Descarrega `google-services.json`**
6. Coloca o ficheiro em: `android/app/google-services.json`

---

## Passo 3 — Adicionar app iOS

1. No teu projecto Firebase, clica **"Add app"** → ícone Apple
2. **Bundle ID:** `com.example.boraApp`
   - Verifica em Xcode → Runner → Bundle Identifier
   - Recomendado: muda para `com.boraapp.app` antes de publicar na App Store
3. App nickname: `Bora App iOS`
4. Clica **"Register app"**
5. **Descarrega `GoogleService-Info.plist`**
6. Abre o Xcode → arrasta o ficheiro para `Runner/` (importante: usar o Xcode, não o Finder)

---

## Passo 4 — Verificar Android Gradle (só uma vez)

Confirma que `android/app/build.gradle` tem o plugin Google Services:

```gradle
// android/app/build.gradle
plugins {
    id 'com.android.application'
    id 'com.google.gms.google-services'  // ← deve existir
}
```

E `android/build.gradle` (raiz) tem o classpath:
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'  // ← deve existir
}
```

Se não tiverem, o `flutterfire configure` (Passo 6) pode adicionar automaticamente.

---

## Passo 5 — Ativar FCM na Firebase Console

1. Na Firebase Console → **Cloud Messaging** (no menu lateral)
2. Confirma que FCM API está activado (normalmente está por defeito)
3. Para iOS: tens de fazer upload do **APNs Authentication Key** ou APNs Certificate
   - Settings → Cloud Messaging → Apple app configuration → Upload APNs key

---

## Passo 6 — (Recomendado) Usar FlutterFire CLI

O FlutterFire CLI gera um ficheiro `firebase_options.dart` que simplifica a inicialização:

```bash
# Instalar FlutterFire CLI (uma vez)
dart pub global activate flutterfire_cli

# Configurar (na raiz do projecto)
flutterfire configure
```

Isto vai:
- Detectar o teu projecto Firebase
- Gerar `lib/firebase_options.dart`
- Confirmar os ficheiros de configuração

Se usares este ficheiro, actualiza `main.dart`:
```dart
// Substituir:
await Firebase.initializeApp();

// Por:
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
// (import 'firebase_options.dart'; no topo)
```

---

## Passo 7 — Gerar Service Account Key (para a Edge Function)

A Edge Function `notify-driver` precisa de uma chave de serviço Firebase para enviar notificações server-side.

1. Firebase Console → **Project Settings** (ícone engrenagem) → **Service accounts**
2. Clica **"Generate new private key"**
3. Guarda o JSON (ex: `firebase-admin-key.json`) — **NUNCA commits este ficheiro**
4. Define os secrets no Supabase:

```bash
# Na raiz do projecto, com Supabase CLI instalado:
supabase secrets set FIREBASE_PROJECT_ID="bora-app-XXXXX"
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-admin-key.json)"
```

O `FIREBASE_PROJECT_ID` encontra-se em: Firebase Console → Project Settings → General → **Project ID**.

---

## Passo 8 — Deploy da Edge Function notify-driver

```bash
supabase functions deploy notify-driver
```

---

## Passo 9 — Aplicar migration da base de dados

```bash
supabase db push
```

Ou via Supabase Dashboard → SQL Editor, corre:
```sql
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS fcm_token TEXT DEFAULT NULL;
```

---

## Passo 10 — Guardar o token FCM do driver

Após o driver fazer login, o token é guardado automaticamente. O código já está implementado em `NotificationService.saveTokenForDriver()`.

**Onde chamar:** adiciona este código ao fluxo de login do driver (ex: em `DriverStore` após auth bem-sucedida):

```dart
// Após driver autenticado com sucesso:
await NotificationService.instance.saveTokenForDriver(driver.id);
```

---

## Resumo — o que já está pronto no código

| Componente | Estado |
|---|---|
| `pubspec.yaml` — firebase_core + firebase_messaging | ✅ Activado |
| `main.dart` — Firebase.initializeApp() | ✅ Activado |
| `notification_service.dart` — FCM completo | ✅ Implementado |
| Edge Function `notify-driver` | ✅ Criada |
| Migration `fcm_token` na tabela `drivers` | ✅ Criada |
| `dispatch-engine` — chama notify-driver após assign | ✅ Integrado |

## O que falta (acções manuais)

- [ ] Criar projecto Firebase Console
- [ ] Descarregar e colocar `google-services.json` → `android/app/`
- [ ] Descarregar e colocar `GoogleService-Info.plist` → `ios/Runner/`
- [ ] Gerar Service Account Key → definir secrets Supabase
- [ ] `supabase functions deploy notify-driver`
- [ ] `supabase db push` (migration fcm_token)
- [ ] Chamar `NotificationService.instance.saveTokenForDriver(driver.id)` após login do driver
- [ ] (iOS) Configurar APNs key na Firebase Console
