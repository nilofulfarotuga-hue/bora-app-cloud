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
**ERRADO — já existe, ponta a ponta, e está no ar.**

- UI: [profile_screen.dart:905](../lib/screens/profile_screen.dart) botão "Apagar conta";
  `_confirmDeleteAccount()` em [profile_screen.dart:1124](../lib/screens/profile_screen.dart)
  com diálogo de confirmação em PT-PT.
- Chama `supabase.functions.invoke('delete-account')`.
- Edge Function **DEPLOYED e ACTIVE**, versão 21 — prova por MCP `list_edge_functions`:
  `{"slug":"delete-account","status":"ACTIVE","version":21}`
- O código local anonimiza pedidos, apaga mensagens de chat, apaga tokens não usados,
  apaga a linha `auth.users` (cascata para `drivers`), e **não toca** no rasto fiscal.

**Consequência:** o Bloco 2.6 (construir a eliminação de conta) **não é preciso de raiz**.
Fica só por **verificar** que funciona nos três perfis e na web, e que o ecrã é alcançável
no perfil estafeta e parceiro (medição por fazer).

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
- [ ] **Bloco 1** — conta Apple (a arrancar)
- [ ] **Bloco 2** — projeto iOS
- [ ] **Bloco 3** — testes
- [ ] **Bloco 4** — vídeo + YouTube
- [ ] **Bloco 5** — loja
- [ ] **Bloco 6** — submissão
- [ ] **Bloco 7** — pós-aprovação

### Paragens à espera do Danilo
_(nenhuma ainda — primeira mensagem por enviar)_
