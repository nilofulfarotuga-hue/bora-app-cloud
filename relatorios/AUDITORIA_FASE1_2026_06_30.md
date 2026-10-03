# AUDITORIA FASE 1 — Telemóvel fraco (causa-raiz + plano cirúrgico)
> 2026-06-30 · MODO PROTECÇÃO TOTAL · **SÓ INVESTIGAÇÃO — zero ficheiros editados**
> Versão fonte actual: `pubspec.yaml` → **1.0.1+332** (CI auto-bumpa versionCode por build).

## Tese transversal (vale para A, C, D, E)
O telemóvel "novo" e o "fraco" divergem **client-side**, e o padrão dominante é **SKEW DE BUILD**:
o aparelho fraco corre um APK anterior aos fixes de Junho (b61179c, Bloco 1, vertical TVDE 6679f35).
Vários sintomas reportados **já não existem no código actual** — o que aponta para "instalar build ≥332 e re-confirmar via adb" como passo zero. Abaixo, para cada bug, separo **(i) o que ainda é bug no código vivo** de **(ii) o que é só skew**.

---

## [A] Overlay bloqueia "ir online" (estafeta + TVDE)

**Estado no código vivo:**
- Estafeta `_handleOnlineToggle` ([driver_home_screen.dart:214](lib/screens/driver_home_screen.dart)) **já** usa `ensureMinimumOnlinePermissions` ([permission_gate_service.dart:98](lib/services/permission_gate_service.dart)) que **devolve sempre true** e nunca bloqueia. ✅ O hard-gate `ensureDriverOnlinePermissions` (4 perms, chumba sem overlay) só é chamado em snackbars opcionais ("CORRIGIR"/"MELHORAR").
- **Bug residual 1:** [driver_home_screen.dart:116-119](lib/screens/driver_home_screen.dart) — `_maybeRequestOverlayPermission()` dispara **2 s após montar o ecrã, incondicionalmente** (não gated por "ir online" nem por capability). Abre `Settings.ACTION_MANAGE_OVERLAY_PERMISSION` → em device Go/low-RAM mostra exactamente *"Recurso não disponível — desativado porque causa lentidão"*. **É a origem visível da mensagem.**
- **Bug residual 2:** `areAllGranted()` exige overlay+bateria+FSI ([permission_gate_service.dart:274](lib/services/permission_gate_service.dart)); como overlay **nunca** se concede nestes aparelhos, o banner do initState ([:125-149](lib/screens/driver_home_screen.dart)) e o `_offerReliabilityEnhancements` ([:266](lib/screens/driver_home_screen.dart)) ficam a repetir o aviso → sensação de "preso".
- **TVDE (Bora Motorista):** `_toggleOnline` ([tvde_driver_home_screen.dart:112](lib/screens/driver/tvde/tvde_driver_home_screen.dart)) **não tem gate de permissões nenhum** (nem notif, nem overlay, nem FGS). Confirma a hipótese do CEO ("fluxo TVDE usa gate diferente") — na verdade **não usa gate**. Não é bloqueado por overlay, mas também não garante a notificação persistente.

**Causa-raiz do "fica preso, não fica online":** SKEW — APK pré-b61179c onde `_handleOnlineToggle` ainda corria o hard-gate `ensureDriverOnlinePermissions` → `false` quando overlay greyed-out → online abortado. Encaixa 100 % no sintoma.

**Plano cirúrgico:**
1. Instalar build ≥332 e re-confirmar (passo zero).
2. Gate `_maybeRequestOverlayPermission` atrás de (a) flag "já mostrei" persistida em SharedPreferences + (b) **capability check** — nunca abrir as definições automaticamente; oferecer só sob toque. Ramificar por **capability, não por versão**.
3. Dar ao TVDE o mesmo `ensureMinimumOnlinePermissions(context)` antes de `toggleAvailability(true)`.
- **Ficheiros:** `driver_home_screen.dart`, `tvde_driver_home_screen.dart`, `permission_gate_service.dart`.
- **Risco:** baixo. **Zonas protegidas:** nenhuma.

---

## [B] FCM MISSING_INSTANCEID_SERVICE ×61

**Causa-raiz:** [notification_service.dart:819](lib/services/notification_service.dart) `_fcmToken = await messaging.getToken();` está **fora de try/catch** (o `catch` anterior fecha em :802). Em GMS degradado/antigo, `getToken()` lança `MISSING_INSTANCEID_SERVICE` → **aborta o resto do `init()`** (o `onTokenRefresh.listen` em :823 nunca é ligado). **Não existe nenhum `GoogleApiAvailability.isGooglePlayServicesAvailable()` em todo o `lib/`** (grep = 0). O retry com backoff existe mas é **limitado a 3x por chamada** em [push_token_service.dart:76-92](lib/services/push_token_service.dart); o "×61" é **agregado** de muitos arranques/sessões/aparelhos, não um loop apertado.

**Plano cirúrgico:**
1. Envolver :819 em try/catch (token null → segue, nunca rebenta o init).
2. Gate `GoogleApiAvailability` no arranque do FCM: se GMS indisponível → log + skip gracioso (nunca hang).
3. Manter o backoff 3x (já correcto).
4. **PROPOSTA (não implementar já):** canal secundário de ofertas via **Supabase Realtime** em foreground para aparelhos com FCM não-fiável. ⚠️ Toca conceptualmente o **dispatch** → exige avaliação de conflito/custo antes de qualquer linha.
- **Ficheiros:** `notification_service.dart`, `push_token_service.dart` (+ proposta realtime separada).
- **Risco:** baixo no guard; **PROPOSTA realtime = a flaggar (zona dispatch).**

---

## [C] Telas brancas — Enviar Encomenda / Levar Compras / Favores

**Estado no código vivo (todos robustos):**
- `send_package_form_screen` body = `ListView`, GPS em background com try/catch/finally + fallback "Guarda, Portugal", **nunca bloqueia** ([:50-77](lib/screens/send_package_form_screen.dart)).
- `carry_groceries_form_screen` idem (body `ListView`, geocode só on-submit) ([:108](lib/screens/carry_groceries_form_screen.dart)).
- `errand_form_screen` (Favores) = `Column`+wizard, quote com estado loading, `_useMyLocationForHome` trata null ([:355-388](lib/screens/errand_form_screen.dart)).
- `LocationService.getCurrentLocation` tem **timeout 15 s** ([location_service.dart:59](lib/services/location_service.dart)). Os autocomplete fields são **todos try/caught** e degradam para "desde €6".

**Conclusão:** no código actual **não existe Future-no-body que nunca resolve**. O corpo renderiza síncrono. ⇒ A tela branca viva é **SKEW** (APK pré-guards do Bloco 1), mesma raiz de [A]/[D]/[E].

**Bug residual real (menor, não causa o branco):** `PaymentService.quoteOrder` (chamado em [quote_price_footer.dart:74](lib/widgets/quote_price_footer.dart) e [errand_form_screen.dart:189](lib/screens/errand_form_screen.dart)) e `MapsService.getDistanceKm` **não têm timeout** → o spinner do preço pode girar para sempre (mas o corpo continua visível, não branco).

**Plano cirúrgico:**
1. Passo zero: confirmar device em build ≥332.
2. Adicionar `.timeout(...)` com fallback às chamadas `quoteOrder` e `getDistanceKm` (estado de erro/retry no rodapé). **Não tocar `pricing_service`/RPC — só o lado cliente da chamada.**
- **Ficheiros:** `quote_price_footer.dart`, `errand_form_screen.dart`, `maps_service.dart`.
- **Risco:** baixo. **Zonas protegidas:** nenhuma (pricing intacto).

---

## [D] Tile "Bora Motorista" não aparece

**Causa-raiz:** [client_home_screen.dart:537](lib/screens/client_home_screen.dart) — `if (context.watch<TvdeStore>().tvdeAccess)` renderiza o tile **só** quando `tvdeAccess == true`. É **categoria escondida por desenho** (entrada discreta de desbloqueio em [:582-586](lib/screens/client_home_screen.dart)). Consistente com "não há feature flag em platform_settings". A diferença entre aparelhos é uma de três: (a) a conta do device fraco **não tem `tvde_access` aprovado**; (b) `TvdeStore` não refrescou; (c) **SKEW** — APK anterior à vertical TVDE (6679f35) onde o tile nem existe.

**Plano cirúrgico (maioritariamente verificação):** confirmar build ≥ vertical TVDE; confirmar a linha `tvde_access` do utilizador; confirmar refresh do `TvdeStore` no foco da home. Só editar se se encontrar bug de refresh.
- **versionCode:** base fonte 332; comparar com o do aparelho.
- **Risco:** baixo. **Zonas protegidas:** nenhuma.

---

## [E] Logo/ícone + splash antigos

**Splash:** **não existe `flutter_native_splash`** no `pubspec.yaml`. [launch_background.xml](android/app/src/main/res/drawable/launch_background.xml) (+ `drawable-v21`) é **branco puro, sem logo**. Logo o "splash antigo" **não vem deste config** — vem do **splash de sistema Android 12+**, que usa o **ícone do launcher**. ⇒ ícone stale ⟹ splash stale.

**Ícone:** [mipmap-anydpi-v26/ic_launcher.xml](android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml) correcto (foreground `@drawable/ic_launcher_foreground` inset 16 %, background `@color/ic_launcher_background` = `#FFFFFF` em [colors.xml](android/app/src/main/res/values/colors.xml)). Os mipmaps/foreground PNG (mdpi→xxxhdpi) estão **commitados/gerados**. O logo antigo persiste porque: (a) os PNG gerados estão **desactualizados** (`flutter_launcher_icons` não foi re-corrido depois de trocar `assets/branding/bora_app_icon.png`), e/ou (b) **cache do launcher** no device (skew).

**Plano cirúrgico:**
1. Confirmar que `assets/branding/bora_app_icon.png` é o logo NOVO.
2. Re-correr `dart run flutter_launcher_icons` → regenera mipmap-*/drawable-* em todas as densidades; confirmar git diff nos PNG.
3. (Opcional, recomendado) adicionar `flutter_native_splash` com o logo para um splash com marca em vez de branco.
- **Ficheiros:** PNG gerados (mipmap-*/ic_launcher.png, drawable-*/ic_launcher_foreground.png) + opcional `pubspec.yaml`.
- **Risco:** baixo. **Zonas protegidas:** nenhuma.

---

## [F] Logger de crash sem contexto

**Causa-raiz:** [main.dart:108-121](lib/main.dart) `_logCrashToSupabase` envia `p_route: null`, `p_app_version: null` **hardcoded**, e `p_screen` só a partir do `FlutterError.context` (quase sempre null). Sem device, versão Android, GMS, nem user_id. **É exactamente por isto que todas as linhas de `debug_crash_logs` vêm null.**

**Plano cirúrgico (PROPOR enriquecer):**
- `p_app_version` ← `package_info_plus`.
- `p_screen`/`p_route` ← `RouteObserver` ligado ao `navigatorKey` global.
- novos campos: modelo + versão Android (`device_info_plus`), `GoogleApiAvailability`, `auth.currentUser.id`.
- estender assinatura do RPC `log_client_crash` (tabela de debug, **não financeira**).
- **Ficheiros:** `main.dart`, deps novas (`package_info_plus`, `device_info_plus`), **migration `log_client_crash`**.
- **Risco:** baixo. **Zona protegida:** alteração de **schema DB** (não-financeira) → por protocolo, **pede aprovação** antes de aplicar.

---

## Ordem sugerida (custo/impacto)
1. **Passo zero:** instalar build ≥332 no aparelho fraco e re-confirmar A/C/D/E via adb (resolve provavelmente a maioria por skew).
2. **B** (guard `getToken` + GMS) — crítico, baixo risco, desbloqueia push em aparelhos fracos.
3. **A** (gate overlay condicional + TVDE) — baixo risco.
4. **E** (re-gerar ícones + splash) — baixo risco.
5. **C** (timeouts de quote/distância) — baixo risco.
6. **F** (enriquecer logger) — precisa aprovação DB.
7. **B-proposta** (Realtime offer channel) — só avaliar; toca dispatch.

**FIM DA FASE 1 — aguarda aprovação do Danilo antes de editar qualquer ficheiro.**
