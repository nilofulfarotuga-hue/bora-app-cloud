# FASE 2 — Implementação (bugs aprovados) · 2026-06-30
> MODO PROTECÇÃO TOTAL · /surgical+/safe-mode em [A][B] · /minimal-change resto.
> `flutter analyze lib`: **0 errors** (global). Zonas protegidas intactas. NÃO commitado/pushed.

## [B] FCM resiliente ✅ (/surgical /safe-mode)
`lib/services/notification_service.dart`
- **:822** onTokenRefresh registado ANTES e independente do getToken (apanha o token quando o GMS recuperar).
- **+`_fetchTokenResilient()`** (novo): getToken em try/catch com backoff 2/5/15s; em erro de GMS (MISSING_INSTANCEID_SERVICE/SERVICE_NOT_AVAILABLE) pára cedo (não martela). Nunca lança.
- **fetch inicial agora `unawaited`** dentro de `init()` — `init()` é aguardado em `Future.wait` antes do `runApp`; o throw antigo do getToken podia **rebentar todo o arranque** em aparelhos com GMS fraco (causa adicional de splash/branco). Agora degrada, sem hang, sem atrasar o splash.
- **+`fcmHealth`** (getter) — saúde GMS inferida, consumida por [F]. Sem dependência nativa nova (CI-safe). **Dispatch intacto.**

## [A] Overlay 100% opcional + gate único ✅ (/surgical /safe-mode)
`lib/services/permission_gate_service.dart` · `driver_home_screen.dart` · `driver/tvde/tvde_driver_home_screen.dart`
- **+`OverlayPermissionGate.maybeOfferOnce()`** (helper ÚNICO): oferece overlay **uma vez na vida** (escolha persistida em SharedPreferences `bora.overlay_offer_handled_v1`); nunca abre Definições sozinho; nunca bloqueia. Resolve o nag "Recurso não disponível" em telemóveis Go.
- **estafeta:** substituído o `_maybeRequestOverlayPermission()` incondicional (removido, ~45 linhas) pelo gate único.
- **TVDE:** `_toggleOnline` going-online passa a chamar `ensureMinimumOnlinePermissions` (notif best-effort) + `OverlayPermissionGate.maybeOfferOnce` — **antes não tinha gate nenhum**. Ir online nunca depende de overlay.

## [C] Timeouts + ecrã pós-solicitação ✅ (/minimal-change)
- **`payment_service.dart:137`** `quoteOrder` → `.timeout(12s)` (cai no catch → null → fallback "desde €6").
- **`maps_service.dart:17`** `getDistanceKm` → `.timeout(12s)` (→ null → Haversine).
- **`quote_price_footer.dart`** `fetchRoute` → `.timeout(12s)` (→ fallback 1 km). O spinner do preço já não gira para sempre.
- **Ecrã pós-"solicitar entregador" = `OrderTrackingScreen`** — auditado: body é `Stack`(GoogleMap+bottom sheet) síncrono, sem FutureBuilder/await bloqueante; directions são fire-and-forget com requestId guard; estados loading/empty já vêm de `order.status` ("À procura de estafeta"). Maps Android key presente no Manifest. **Sem hung Future → o branco vivo é skew.** Nada a alterar lá.

## [D] TvdeStore refresh ✅ (já correcto — sem alteração)
`TvdeStore.refreshAccess()` já é chamado no **arranque** (`client_home_screen.dart:68`) e no **resume** (:93). Para o Danilo (`tvde_access=TRUE`) o tile aparece no próximo open/resume → o miss vivo é **skew de build**. Não há `RefreshIndicator` na home; adicionar um seria reestruturar o body (fora de /minimal-change). **Nenhuma mudança de código.**

## [E] Ícone/splash — NÃO regenerado (surfacing) ⚠️
O asset `assets/branding/bora_app_icon.png` é de **2026-05-28**; os mipmaps/foreground já foram **regenerados a 2026-06-24** a partir dele. **Não existe asset NOVO** ("moto com capacete/mochila") no repo, Desktop ou Downloads. Re-correr `flutter_launcher_icons` seria **no-op**. O logo antigo no aparelho fraco = **skew + cache do launcher**. → **Danilo: larga o PNG novo nessa pasta e eu regenero** (mipmap-anydpi-v26 + mdpi→xxxhdpi). Splash nativo acompanha o ícone (Android 12+).

## [F] Logger de crash com contexto ✅ (/minimal-change)
- `MainActivity.kt` **+`getDeviceDiagnostics`** (app_version, device_model, android_version) via `android.os.Build`+`getPackageInfo` — **sem deps novas**.
- `main.dart`: **+`_CrashRouteObserver`** (route actual) ligado a `navigatorObservers`; **+`_loadDeviceDiagnostics()`** (fire-and-forget no arranque); `_logCrashToSupabase` agora envia `p_route`, `p_app_version`, `p_device_model`, `p_android_version`, `p_gms_status` (=`NotificationService.fcmHealth`), `p_user_id`. (Antes: tudo null.)
- **Migration SQL** → `relatorios/MIGRATION_F_crash_logs_contexto_2026_06_30.sql` (4 colunas + RPC 10-args backward-compatible + índices). **Aplicar via MCP.**

## Painel admin
- **[D] ✅ já existe:** `admin_tvde_access_requests_screen.dart` (conceder/revogar via `admin_set_tvde_access`, lista `tvde_access`).
- **[F] TODO:** não há ecrã admin para `debug_crash_logs`. Adiar para ciclo próprio **após aplicar a migration** (filtro por screen/route/device/versão/gms).

## Pendentes para o Danilo
1. Aplicar `MIGRATION_F_*.sql` via MCP.
2. Larga o PNG do logo novo (se houver) → eu regenero ícones.
3. Build novo (≥332) no aparelho fraco → re-confirmar A/C/D/E (maioria era skew).
4. Agendar ecrã admin de crash logs [F-TODO].
