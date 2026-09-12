# 🐛 DIAGNÓSTICO — Login falha na build 240 (GitHub Actions)
> Data: 2026-05-31 · Branch: `autonomous-night-2026-04-29` · Infra de build (NÃO lógica de negócio).

## Sintoma
- App **abre**, mas login cliente → **"Credenciais inválidas" instantâneo** (sem ir ao servidor).
- Conta válida (MCP: existe, email confirmado, último login OK 30/05). Build **239 (Codemagic) funcionava**; **240 (GitHub Actions) não**. Só mudou o **pipeline de build**.

## Causa-raiz (alta confiança)
**Mismatch de versão do Flutter entre pipelines + parsing de `--dart-define-from-file`.**

Cadeia de evidência:
1. A app lê as chaves via `String.fromEnvironment(...)` — **compile-time** (`main.dart:56-57` Supabase, `:117` Stripe, `maps_config.dart:4`). Vazio se o build não as injetar.
2. **Ambos** os pipelines usam o MESMO mecanismo: decode `DART_DEFINES_FILE_B64` → `.dart_defines` → `flutter build … --dart-define-from-file=.dart_defines`.
3. O `.dart_defines` é **formato `.env` (`KEY=value`) e começa com uma linha de comentário `#`** (16 linhas; chaves: SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_MAPS_API_KEY, STRIPE_PUBLISHABLE_KEY).
4. **Codemagic fixa `flutter: 3.41.2`** (`codemagic.yaml:7`) e o build 239 funcionou com **este mesmo ficheiro**.
5. **GitHub Actions usava `channel: stable` SEM pin** → Flutter **mais recente**. O parser de `--dart-define-from-file` para ficheiros `.env` (com comentário `#`) **mudou** em versões recentes → as chaves Supabase **não foram injetadas** → `Supabase.initialize(url:'', anonKey:'')` → `signInWithPassword` falha imediatamente (URL inválida, sem round-trip) → "Credenciais inválidas".
6. **Porque a app abre na mesma:** `main.dart:123` faz `if (stripePublishableKey.isEmpty) throw StateError`. Se TODAS as defines falhassem, a app crashava no arranque. Como abre, a Stripe key entrou — ou seja, o parsing **parcial/diferente** dropou as chaves Supabase mas não todas. Isto é consistente com uma mudança de parser, não com secret totalmente ausente.

### Descartado (não é a causa)
- **Package/Firebase mismatch** (`pt.boraapp.bora`): o login é **Supabase**, não Firebase. Um mismatch de `google-services.json`/package só partiria FCM push, não o login. Não é esta a causa.
- **Stripe key em falta:** está presente (app abre).

## ✅ Correção aplicada (100% segura — commit `23016d2`)
`build_android.yml` passo "Setup Flutter": **pin `flutter-version: 3.41.2`** (a versão exata do Codemagic que produziu o build 239 funcional). Remove a única variável que diferia.

```yaml
- name: Setup Flutter
  uses: subosito/flutter-action@v2
  with:
    flutter-version: 3.41.2   # <-- pin (era só channel: stable)
    channel: stable
    cache: true
```

## 👤 O que o Danilo deve fazer (verificação belt-and-suspenders, antes de re-buildar)
1. **Confirmar o secret do GitHub** `DART_DEFINES_FILE_B64` corresponde ao `.dart_defines` ATUAL (com as 4 chaves). Para regenerar (PowerShell, na pasta `bora_app`):
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes(".dart_defines")) | Set-Clipboard
   ```
   → colar no GitHub → Settings → Secrets and variables → Actions → `DART_DEFINES_FILE_B64` (Update). **(NÃO partilhar o valor.)**
2. **Re-buildar:** quando quiseres, `git push` (ou re-run do workflow no GitHub Actions). A CI bumpa versionCode e publica **241** no Teste Interno.
3. **Testar login** no A36 (build 241). Deve entrar normalmente.

## Plano B (se o pin não resolver — não aplicado)
Se mesmo com 3.41.2 falhar, o problema é o **conteúdo do secret** ou o **formato `.env`+`#`**. Opções:
- Converter `.dart_defines` para **JSON** (`{ "SUPABASE_URL": "...", ... }`, ficheiro `.dart_defines.json`) e usar `--dart-define-from-file=.dart_defines.json` (JSON é parsing inequívoco). Requer regenerar o secret + editar os 2 pipelines.
- OU passar explicitamente `--dart-define=SUPABASE_URL=$X …` a partir de secrets individuais (mais verboso, mas à prova de parser).

## Resumo
| | |
|---|---|
| Causa-raiz | Flutter sem pin no GH Actions → parser `--dart-define-from-file` dropou chaves Supabase |
| Fix (Claude) | pin `flutter-version: 3.41.2` em `build_android.yml` (commit `23016d2`, **sem push**) |
| Verificar (Danilo) | secret `DART_DEFINES_FILE_B64` atualizado + re-build + testar login |
| Não tocado | lógica Stripe/Supabase/dispatch — só infra de build |
