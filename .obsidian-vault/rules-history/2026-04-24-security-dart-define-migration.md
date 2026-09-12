---
date: 2026-04-24
type: tech-rule
files_affected:
  - lib/config/maps_config.dart
  - lib/main.dart
  - lib/services/notification_service.dart
  - .gitignore
  - .dart_defines.example
commit: 9eee9a7
ceo_ai_section: "7. REGRAS PERMANENTES → Segurança de credenciais"
approved_by: Danilo
tags: [rules, tech-rule, security, credentials, dart-define]
---

# Security migration — credenciais hardcoded removidas do código Flutter

## Antes

5 credenciais **hardcoded** em `lib/` — todas expostas no GitHub (repo estava **público**):

| Credencial | Ficheiro | Linha |
|------------|----------|-------|
| `googleApiKey` (`AIzaSyBYLjK1...`) | `lib/config/maps_config.dart` | 1 |
| `_supabaseUrl` + `_supabaseAnonKey` (JWT) | `lib/main.dart` | 31–33 |
| `stripeDebugFallback` (`pk_test_51T8MG0...`) | `lib/main.dart` | 47–48 |
| `supabaseUrl` + `anonKey` duplicados | `lib/services/notification_service.dart` | 180–182 |

Stripe live key já usava `--dart-define` correctamente (único caso OK).

## Depois

Todas as credenciais injectadas em build time via `String.fromEnvironment(...)` + ficheiro `.dart_defines` local (gitignored):

```dart
const String googleApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
```

`notification_service.dart` deixou de duplicar e usa duas `static const` com `String.fromEnvironment`.

Comando padrão de run/build:
```bash
flutter run --dart-define-from-file=.dart_defines
flutter build apk --dart-define-from-file=.dart_defines \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
```

## Motivo

Auditoria de segurança (sessão 2026-04-24) descobriu credenciais hardcoded num repo GitHub **público**. Qualquer pessoa podia extrair:
- `googleApiKey` → usar para geocoding à custa do Danilo (risco alto, cobrança Google Cloud)
- `supabaseAnonKey` → fazer requests directos à API (RLS protege os dados, mas má prática)
- Stripe test key → risco baixo mas confusão com prod

Repo foi tornado **privado** e o código migrado para eliminar hardcoded.

## Impacto

- **Sem breaking** — nenhum módulo PRONTO afectado
- **flutter analyze** = 0 erros (só 3 infos pré-existentes sobre `dart:js`/`dart:html`)
- **Novo requisito de developer onboarding**: copiar `.dart_defines.example` → `.dart_defines` e preencher
- **Risco residual**: `googleApiKey` esteve pública — Danilo precisa de **restringir na Google Cloud Console** (SHA-1 Android) ou regenerar

## Ficheiros

- `lib/config/maps_config.dart` — removido hardcoded, usa `String.fromEnvironment('GOOGLE_MAPS_API_KEY')`
- `lib/main.dart` — Supabase URL/anonKey via env, removido `stripeDebugFallback` (pk_test)
- `lib/services/notification_service.dart` — removida duplicação, `_supabaseUrl`/`_anonKey` como `static const` via env
- `.gitignore` — adicionado `.dart_defines`
- `.dart_defines.example` — novo template com placeholders
- `.claude/skills/ceo-ai/SKILL.md` — nova regra em § 7 "REGRAS PERMANENTES → Segurança de credenciais"

## Acções pendentes (Danilo)

1. 🔴 **Restringir `GOOGLE_MAPS_API_KEY`** na Google Cloud Console — Application restrictions → Android apps + SHA-1. Chave esteve pública.
2. 🟡 Considerar rodar `SUPABASE_ANON_KEY` (RLS protege, baixa prioridade)
3. 🟢 Para release: substituir `STRIPE_PUBLISHABLE_KEY` no `.dart_defines` por `pk_live_...`

## Commit

`9eee9a7` — `security: migrate hardcoded credentials to --dart-define` (5 files changed, 81 insertions, 10 deletions)
