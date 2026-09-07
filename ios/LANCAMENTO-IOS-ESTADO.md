# LANÇAMENTO iOS — ESTADO DA MISSÃO

> Missão `ios-lancamento-07-09` · run_id `ios-lancamento-2026-09-07`
> Sessão iniciada 2026-09-07 no Claude Code do PC (`C:\BoraLocal\projetosflutter\bora_app`).
> **Este ficheiro diz onde retomar se a sessão cair.** Cada linha tem prova (comando + saída).

---

## 0. PORTÃO DE AMBIENTE — PASSOU

| Verificação | Prova | Estado |
|---|---|---|
| Pasta de trabalho | `pwd` → `/c/BoraLocal/projetosflutter/bora_app` | ✅ PC, não nuvem |
| Skill CEO-AI | `ls .claude/skills/ceo-ai/` → `SKILL.md  references` | ✅ existe |
| Chrome (agente de clique) | `list_connected_browsers` → `Browser 1`, Windows, `isLocal:true` | ✅ ligado |
| RAM disponível | `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes` → **964** | ✅ acima do portão pesado (800 MB) |
| Córtex vivo | `cortex_buscar "dispatch"` → 20 resultados | ✅ responde |

---

## 1. ⚠️ QUATRO PREMISSAS DA ORDEM QUE A MEDIÇÃO DESMENTIU

A ordem escrita a 07/09 assumia coisas que **não** batem com o repositório e a base de dados.
Corrijo aqui para não se trabalhar em cima de premissa errada.

### 1.1 "NÃO existe RPC de auto-eliminação. Sem isto a Apple reprova (5.1.1(v))"

> **🔴 CORRIGIDO 2026-09-07, mais tarde no mesmo dia.**
> A minha primeira leitura disse "já existe, ponta a ponta, e está no ar". **Estava errada.**
> Confirmei que a função estava `ACTIVE` e li o código **local** — nunca li o código
> **deployed**. É exactamente a armadilha que as regras da casa descrevem:
> *"um 200 não prova que o trabalho por dentro correu — verifica o efeito, não o invólucro."*
> A premissa original da ordem estava mais perto da verdade do que a minha correcção.

**O QUE ESTÁ MESMO NO AR: uma página HTML. A conta NUNCA é apagada.**

`get_edge_function('delete-account')` devolve, na íntegra, uma página estática
"Como pedir a eliminação da sua conta" — do tipo que a Google Play exige como URL de
eliminação de dados. **Não tem uma única linha de lógica de eliminação.**

Prova, chamada real ao endpoint de produção:

```
POST /functions/v1/delete-account
HTTP 200
Content-Type: text/html; charset=utf-8
Bytes: 2171

<!DOCTYPE html><html lang="pt"><head>… <title>Eliminar Conta — Bora App</title> …
```

E a app trata isso como sucesso ([profile_screen.dart:1158](../lib/screens/profile_screen.dart)):

```dart
if (response.status >= 400) { … erro … }   // 200 não é >= 400 → passa
context.read<AuthStore>().logout();
… Text('Conta apagada.')                    // MENTIRA ao utilizador
```

**Consequências, por ordem de gravidade:**

1. **Violação de RGPD em produção, agora.** Quem pediu para apagar a conta foi informado
   de que foi apagada e não foi. Os dados continuam todos lá e a pessoa pode voltar a entrar.
2. **Reprovação certa da Apple (5.1.1(v)).** O revisor toca em "Apagar conta", vê
   "Conta apagada.", volta a entrar com as mesmas credenciais e a conta está viva.
3. O código local (`supabase/functions/delete-account/index.ts`) tem a lógica **certa**,
   mas **nunca foi deployed** — o ar tem outra coisa em cima.

### 1.1-b O código local também não está correcto (medido na DB)

Mesmo o ficheiro local, se fosse deployed hoje, falhava. `pg_constraint` sobre `auth.users`:

| Problema | Prova | Efeito |
|---|---|---|
| `drivers` **não tem** FK `user_id → auth.users` | única FK é `drivers_approved_by_fkey` sobre `approved_by` | apagar o utilizador deixa a linha do estafeta **órfã**, com nome, telefone, NIF, IBAN e documentos — o RGPD não fica cumprido |
| `appointments.client_user_id` = **NO ACTION** | consulta a `pg_constraint` | cliente com marcação: o `deleteUser` **rebenta** com violação de chave |
| `cleaning_bookings.client_user_id` = **NO ACTION** | idem | cliente com limpeza marcada: rebenta |
| `service_providers.user_id` / `cleaners.user_id` = **NO ACTION** | idem | prestador nunca consegue apagar a conta |
| `restaurants.user_id` = **CASCADE** | idem | parceiro que apaga a conta **apaga a loja inteira** — é o comportamento actual, a decidir se é o desejado |

Quantos utilizadores reais ficariam presos hoje: **5** (4 marcações + 5 limpezas,
5 clientes distintos).

### 1.1-c Quem sequer consegue chegar ao botão

| Perfil | Tem o botão? | Prova |
|---|---|---|
| Cliente | ✅ | `ProfileScreen()` em `client_main_screen.dart:88` |
| Estafeta | ✅ | `ProfileScreen()` em `driver_home_screen.dart:1166` |
| **Parceiro** | ❌ **não existe caminho nenhum** | `grep -rl "Apagar conta" lib/screens/` → só `profile_screen.dart`; o parceiro aterra em `PartnerEntryScreen` → `PartnerDashboardScreen` / `PartnerServicesHubScreen`, nenhum deles com perfil ou definições de conta |
| Web | mesmo código Flutter | logo: cliente e estafeta sim, parceiro não |

**Este é agora o bloqueador nº 1 da missão** — e é maior do que o iOS: está a mentir a
utilizadores reais em produção, hoje.

### 1.2 "Se houver QUALQUER login social ativo, a Apple obriga a Sign in with Apple (4.8)"
**NÃO SE APLICA — os botões estão desligados por defeito, medido.**

- [register_client_screen.dart:52](../lib/screens/register_client_screen.dart):
  `static const bool _socialAuthEnabled = bool.fromEnvironment('SOCIAL_AUTH_ENABLED');`
- Prova de que a chave não existe: `grep -c 'SOCIAL_AUTH_ENABLED' .dart_defines` → **0**
- Chaves realmente presentes no `.dart_defines`: `GOOGLE_MAPS_API_KEY`,
  `STRIPE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_URL` — a flag social não está lá.
- `bool.fromEnvironment` sem definição = **false** → os botões nunca são construídos.
- E mesmo se aparecessem, `_signInWithApple()` é um *stub* que só mostra
  "Apple Sign-In — em configuração." → seria reprovação 2.1 (funcionalidade partida),
  não 4.8.

**Consequência:** guideline 4.8 não se aplica à v1. **Nada a fazer** — mas há um risco
a fechar: garantir que o build iOS **nunca** define `SOCIAL_AUTH_ENABLED=true`.

### 1.3 "`bora://` já existe para o reset de palavra-passe"
**O esquema real é outro.** [Info.plist](Runner/Info.plist) declara:
`CFBundleURLSchemes = pt.boraapp.bora` (não `bora`).
O `returnURL` do Stripe 3DS tem de usar **`pt.boraapp.bora://stripe-redirect`**.
Nota: `grep -rniE 'returnURL|urlScheme' lib/` → **sem resultados** — o `returnURL`
não está configurado em lado nenhum. No iOS isso parte o 3DS.

### 1.4 "`assets/img/apple-touch-icon.png` do bora-site é 1024? mede"
Nesse caminho **não existe nada** (`ls assets/img/*.png` → sem saída;
`find . -iname 'apple-touch-icon*'` → sem resultados neste repo).
O ícone real da app é `tool/branding/bora_app_icon.png`:

```
largura 1024 altura 1024 bitdepth 8 colortype 6 (6=RGBA com alfa)
```

**É 1024×1024 ✅ mas TEM CANAL ALFA ❌.** A App Store recusa ícones com transparência.
Tem de ser achatado sobre fundo opaco antes de subir.

---

## 2. ESTADO DA PASTA `ios/` — NUNCA FOI COMPILADA

| Facto | Prova |
|---|---|
| Pasta existe (do `flutter create`) | `ls ios/` → `Flutter Runner Runner.xcodeproj Runner.xcworkspace RunnerTests` |
| **Não há Podfile** | `cat ios/Podfile` → `No such file or directory` |
| Nunca correu `pod install` | consequência directa do acima |
| Última alteração | `git log -1 -- ios/` → `2026-07-22 fix(auth): deep link de recuperacao de senha` |
| Nunca houve build iOS no CI | `ls .github/workflows/` → `build_android, build_web_deploy, dart, e2e-web, olho_golden, testlab_robo` — nenhum iOS |

### 2.1 O que está ERRADO no projeto Xcode (tudo por corrigir)

Prova: `grep -nE 'IPHONEOS_DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER|TARGETED_DEVICE_FAMILY' ios/Runner.xcodeproj/project.pbxproj`

| Chave | Valor actual | Valor alvo | Porquê |
|---|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | **`com.example.boraApp`** | `pt.boraapp.bora` | é o placeholder do `flutter create`; com isto não assina nem sobe |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` (iPhone+iPad) | `"1"` | iPad obriga a capturas e revisão de iPad |
| `IPHONEOS_DEPLOYMENT_TARGET` | `13.0` | `15.0` | `flutter_stripe` 11.x e SDK iOS 26 |
| `SWIFT_VERSION` | `5.0` | manter | ok |

### 2.2 O que já está BEM no `Info.plist` (melhor do que a ordem assumia)

Já existem, **em PT-PT e específicas**:
- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`
- `BGTaskSchedulerPermittedIdentifiers` (flutter_foreground_task)
- `CFBundleURLTypes` (esquema `pt.boraapp.bora`)
- `CFBundleDisplayName = Bora App`

### 2.3 O que FALTA / está a mais no `Info.plist`

| Item | Estado | Acção |
|---|---|---|
| `ITSAppUsesNonExemptEncryption` | **ausente** (`grep` → 0) | acrescentar `false` — evita a pergunta de exportação a cada build |
| `PrivacyInfo.xcprivacy` | **não existe** (`find ios -iname '*.xcprivacy'` → nada) | criar (Required Reason APIs) |
| `UIBackgroundModes` | tem **4**: `location`, `fetch`, `remote-notification`, `processing` | 2.5.4 diz "só os usados" — justificar ou cortar `fetch`/`processing` |
| `LSApplicationQueriesSchemes` | só `tel` | juntar `whatsapp`, `maps`, `comgooglemaps` |
| `UISupportedInterfaceOrientations` | permite **landscape** | trancar em retrato |
| Retrato no código | `grep 'SystemChrome.setPreferredOrientations' lib/main.dart` → **sem saída** | a app não tranca orientação |

---

## 3. PAGAMENTOS — APPLE PAY ESTÁ LIGADO (risco para a v1)

`Stripe.merchantIdentifier = 'merchant.com.boraapp.app'` em [main.dart:435](../lib/main.dart)
e `PaymentSheetApplePay(merchantCountryCode: 'PT')` em **6 sítios**:
`payment_service.dart:117,365` · `reservation_checkout_screen.dart:188` ·
`reservation_flow_screen.dart:183` · `services_store.dart:455`.

No iOS isto exige Merchant ID + certificado Apple Pay. Sem isso, o botão aparece e falha
→ reprovação 2.1. **Decisão: esconder por flag no iOS na v1**, Apple Pay fica para a v1.1.

---

## 4. BASE DE DADOS — ESTADO REAL (MCP Supabase, projeto `ojykpzwqrtusfeakzrna`)

| Facto | Valor | Nota |
|---|---|---|
| `demo@bora.app` | **existe**, confirmado, `bora_role=client`, "Cliente Demo Bora" | id `d5b0c0a1-f49e-4593-a919-147edfc069c2`, criado 2026-07-06 |
| `demo-estafeta@bora.app` | **NÃO existe** | criar (Bloco 2.10) |
| `guest@bora.com` | existe | sessão de convidado |
| Lojas | **19** total, **4** parceiras | a ordem falava em 17 — são 19 |
| Estafetas | 8 | |
| Pedidos da conta demo | **0** | nunca foi usada |
| Coluna `orders.platform` | **não existe** | criar (Bloco 2.9) |
| Tabela `addresses` | **não existe** | as moradas vivem noutro sítio — por localizar |
| Edge Functions no ar | **74** | o `CLAUDE.md` diz 53 locais e a skill CEO-AI diz 51 — ambos *stale* |

---

## 5. FERRAMENTAS DO PC

| Ferramenta | Estado |
|---|---|
| Flutter | **3.47.2** stable · Dart 3.13.2 (`flutter --version`) |
| `olho_golden.yml` | fixa Flutter **3.41.2** — diferente do local; a fixar no workflow iOS |
| Firebase CLI | **não instalado** (`firebase: command not found`) |
| `GoogleService-Info.plist` (iOS) | **não existe** |
| `google-services.json` (Android) | existe |
| Testes | 53 ficheiros em `test/` + 2 em `integration_test/` |

---

## 6. GIT — LIMPO PARA ARRANCAR

```
git rev-list --left-right --count origin/autonomous-night-2026-04-29...HEAD  →  0  0
```
Sincronizado com o remoto: **nada por enviar de outras sessões**, nada para arrastar.
(80 ficheiros modificados/não seguidos no working tree, de sessões anteriores — não entram
em commits desta missão.)

---

## 7. ONDE RETOMAR

- [x] **Bloco 0** — reconhecimento (este ficheiro)
- [ ] **Bloco 1** — conta Apple → **BLOQUEADO, ver §8.1**
- [~] **Bloco 2** — projeto iOS → base feita e commitada (`f9778dae`); falta
      Firebase iOS, chave Maps iOS, `returnURL` do Stripe, conta demo estafeta,
      coluna `platform`, interruptor de logótipos
- [ ] **Bloco 3** — testes → depende do primeiro build verde
- [ ] **Bloco 4** — vídeo + YouTube → depende do Bloco 3
- [ ] **Bloco 5** — loja → textos e capturas podem avançar sem conta
- [ ] **Bloco 6** — submissão
- [ ] **Bloco 7** — pós-aprovação

### O que ficou feito e provado (commit `f9778dae`, branch `ios-lancamento`)

| Alteração | Prova |
|---|---|
| Bundle ID `com.example.boraApp` → `pt.boraapp.bora` | `grep -c 'com\.example' project.pbxproj` → **0** |
| Só iPhone (`TARGETED_DEVICE_FAMILY = "1"`) | grep no pbxproj |
| Alvo iOS 15.0 | grep no pbxproj |
| `Info.plist`: retrato só, `ITSAppUsesNonExemptEncryption=false`, 5 esquemas de URL | `plistlib.load()` → XML válido, 27 chaves |
| `PrivacyInfo.xcprivacy` criado **e registado nas 4 secções** do pbxproj | grep → linhas 17, 61, 120, 224 |
| `Podfile` criado (nunca existiu), plataforma 15.0 | ficheiro novo |
| Apple Pay desligado no iOS em 6 sítios | `grep 'applePay:'` → 5 usam `boraApplePay`, 0 literais |
| Alfa do ícone removido só no iOS | `remove_alpha_ios: true` no pubspec |
| `build_ios.yml` (Job A simulador + Job B release) | `yaml.safe_load` → válido, 2 jobs |
| Nada compilado partiu | `flutter analyze` → **0 erros**; nenhum aviso nos ficheiros tocados |
| `versionCode` intacto | `version: 1.0.1+599` |
| Push não publica nada | `build_android` e `build_web_deploy` só disparam em `autonomous-night-2026-04-29` (lido dos YAML) |

---

## 8. PARAGENS — o que espera pelo Danilo

### 8.1 🔴 A conta Apple tem de ser criada por ele (limite de segurança, não escolha minha)

A ordem dizia "conta, formulários, termos… és tu". **Criar contas e escrever
palavras-passe está fora do que eu posso fazer**, mesmo com autorização escrita.
Não é o guardrail do repo nem falta de ferramentas — é um limite fixo meu.

O que **não** posso: criar o Apple ID, escrever a palavra-passe, escrever o
número do cartão de cidadão, escrever dados do cartão de crédito.

O que **posso** e faço: abrir as páginas certas no separador certo, preencher o
que não é credencial, ler os códigos que chegam ao Gmail, vigiar o estado da
inscrição, e tratar de **tudo** o resto (build, testes, vídeo, capturas, textos,
loja, submissão, respostas à Apple).

Na prática muda pouco no calendário: em vez de 4 momentos dele, são 5, e três
deles são na mesma sentada (criar conta → inscrever → pagar).

### 8.2 🟡 O push da branch está bloqueado pelo guardrail

```
BLOQUEADO pelo guardrail de git: push para 'ios-lancamento';
so e permitido: autonomous-night-2026-04-29
```

O hook está em `.claude/settings.json:137` e aponta para
`C:/Users/danil/Desktop/projetosflutter/bora_app/.claude/hooks/git-guardrails.sh`
(a árvore **antiga**, não esta). `.claude/settings.json` é zona protegida — não
se toca sem ordem.

O commit está **seguro localmente** (`f9778dae`). Sem o push, o primeiro build
iOS da história do projeto não corre. Comando para o Danilo:

```bash
git -C C:/BoraLocal/projetosflutter/bora_app push -u origin ios-lancamento
```

Alternativa **recusada**: fazer merge para `autonomous-night-2026-04-29` para
contornar. Isso dispararia build Android para a Play e deploy web — publicação
real — só para poder testar iOS. Não se faz.

### 8.3 Decisão de dinheiro que fica com ele
O Supabase está em plano grátis e já pausou a app a 28/08. Se pausar durante a
revisão, a Apple reprova. Plano Pro = 25 USD/mês. **Não é decisão minha.**
