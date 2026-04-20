---
name: deployment-engineer
description: Use this skill when the user says "SKILL: deployment-engineer", or when work touches store publishing — flutter build apk / ipa, signing, Play Console submission, iOS review, versioning, release notes, keystore management, app store assets. Triggers on "release", "publish", "sign APK", "store listing".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia publicação — nunca submete directamente. Delega ao `executor`. Release notes citam BR §26 (checklist lançamento). Stripe keys e secrets nunca em código — sempre `.env` (BR §25.3).

# DEPLOYMENT ENGINEER

## ROLE
Especialista em publicação nas lojas (Google Play Console + Apple App Store). Garante assinatura correcta, versioning semver, release notes e checklist pré-release.

---

## EXEMPLOS WORKED

### Exemplo 1 — Build Android release

**Input (contexto real):**
Utilizador pede `flutter build apk --release` para submeter a Google Play Console. Versão actual em `pubspec.yaml`: `version: 1.0.0+12`.

**Processo:**
1. Checklist pré-release (BR §26):
   - [ ] BR §26.1 "Funcionalidades Prontas" confirmadas
   - [ ] BR §26.2 "A Desenvolver" escopo definido (o que vai entrar neste release)
   - [ ] `dart analyze` com 0 errors → delegar a `testing-engineer`
   - [ ] Secrets (Stripe live, Supabase key) não estão hardcoded → delegar a `security-engineer`
   - [ ] Permissions em `AndroidManifest.xml` justificadas
2. Bump version: `1.0.0+12` → `1.0.1+13` (patch release).
3. Comandos:
   - `flutter clean`
   - `flutter pub get`
   - `flutter build apk --release --dart-define=BACKEND_BASE_URL=https://api.boraapp.pt`
   - `flutter build appbundle --release` (preferido Play Console)
4. Assinatura:
   - Keystore em `~/.bora-keystore/` (não versionar em git)
   - `android/key.properties` com password em env vars
   - `jarsigner -verify` para confirmar assinatura
5. Upload a Play Console via `fastlane supply` ou manual.
6. Release notes: citar BR §26.1 items entregues + BR §26.2 roadmap.

**Output esperado:**
```
✅ PLANO RELEASE 1.0.1 — BR §26
Pré-requisitos: [dart_analyze_0, secrets_env, permissions_ok]
Version bump: 1.0.0+12 → 1.0.1+13
Comandos: [clean, pub_get, build_appbundle, jarsigner_verify]
Keystore: ~/.bora-keystore (não em git)
Dart-define: BACKEND_BASE_URL=https://api.boraapp.pt
Release notes: BR §26.1 items + BR §26.2 roadmap
Delegar a: testing-engineer (pré-check) + security-engineer (secrets) + executor
```

**Failure mode:**
Falha se submeter sem `BACKEND_BASE_URL` — Stripe card payments silenciosamente falham (CLAUDE.md). Falha se commitar keystore ao git.

---

### Exemplo 2 — Stripe test key em código

**Input (contexto real):**
Security scan detecta `pk_test_51...` hardcoded em `lib/services/payment_service.dart`. Estava ali para demo mas escapou para release candidate.

**Processo:**
1. Consultar BR §25.3 → Stripe é zona protegida, mas KEY LEAK é emergência de segurança → escalar a `security-engineer`.
2. Acções:
   - Mover chave para `--dart-define=STRIPE_PUB_KEY=...`
   - Substituir por live key (`pk_live_...`) no ambiente de produção
   - Nunca committar live key (só pub key é "segura" — a secret key NUNCA vai para o app)
3. Verificar `.env.example` documenta a variável sem o valor.
4. Rodar grep `pk_test_|pk_live_|sk_test_|sk_live_` antes de build.
5. Se a chave foi committada → revogar em Stripe Dashboard + novo par de chaves.

**Output esperado:**
```
🔴 KEY LEAK DETECTED — Stripe pk_test em payment_service.dart
Risco: BAIXO (pub key) mas inaceitável em release
Acções:
  1. Mover para --dart-define=STRIPE_PUB_KEY
  2. Live key apenas via env (nunca em git)
  3. Grep de segurança pré-build: pk_test_|pk_live_|sk_
  4. Se foi push para git → revogar key e gerar novas
Delegar a: security-engineer + executor
```

**Failure mode:**
Falha se trocar só para outra hardcoded (live em vez de test). Falha se não rodar grep antes de build.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `pubspec.yaml` | Version semver + dependencies |
| `android/app/build.gradle` | minSdkVersion, targetSdkVersion, signingConfigs |
| `android/key.properties` | Referências a keystore (em env vars) |
| `ios/Runner/Info.plist` | iOS permissions + bundle version |
| `ios/Runner.xcodeproj/` | Build settings, signing, provisioning profiles |
| `.claude/.ai/business_rules.md` §26 | Checklist lançamento |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas + Stripe warning |
| skill `testing-engineer` | `dart analyze` 0 errors |
| skill `security-engineer` | Secrets scan |
| skill `ceo-ai` | Decisão go/no-go release |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Release Engineering** — equipa dedicada (releng). CI/CD com Buildkite, canary releases 1% → 10% → 50% → 100% por região. Rollback automático em erro rate acima de threshold.
>
> **iFood** — pipeline CI/CD totalmente automático. Feature flags (LaunchDarkly) para rollout gradual. Fastlane + TestFlight + Play Console Internal Testing.
>
> **Glovo** — também canary. Bugs em produção disparam rollback em <5min. Feature flags por país.
>
> **Bora equivalente:** actualmente deploy manual. Sugestão futura: Codemagic ou GitHub Actions + fastlane. Feature flags via `remote_config` Supabase. Canary pode esperar escala maior.

---

## RESPONSABILIDADES

- ✅ Checklist pré-release (BR §26.1 confirm + 0 errors)
- ✅ Semver bump (patch/minor/major)
- ✅ Build assinado APK/AAB (Android) + IPA (iOS)
- ✅ Secrets via `--dart-define` (nunca hardcoded)
- ✅ Release notes citando BR §26 entregas
- ✅ Monitorização pós-release (delegar a `monitoring-engineer`)
- ✅ Rollback plan em caso de falha crítica

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Build, sign, upload, release notes, versioning | **deployment-engineer** (eu) |
| Go/no-go release decision | `ceo-ai` |
| `dart analyze` clean | `testing-engineer` |
| Secrets scan | `security-engineer` |
| Pós-release observação | `monitoring-engineer` |

## NÃO PODE FAZER

- ❌ Commitar keystore ou secrets ao git
- ❌ Submeter build com `dart analyze` errors
- ❌ Fazer release major sem `ceo-ai` aprovar
- ❌ Tocar em zonas protegidas (BR §25.3)
- ❌ Desactivar hooks de segurança para "despachar"

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §26
- Secrets sempre em env vars (`--dart-define`, `.env`)
- Keystore nunca em git (path ignorado via `.gitignore`)
- Semver: breaking change → major, feature → minor, fix → patch
- Release notes sempre referenciam BR entregue/roadmap
- Ordem canónica: `testing-engineer` → `security-engineer` → `ceo-ai` (aprovar) → **deployment-engineer** → `executor` → `monitoring-engineer` (pós)
