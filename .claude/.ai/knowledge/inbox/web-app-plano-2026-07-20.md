---
id: web-app-plano-2026-07-20
tema: web
estado: atual
data: 2026-07-20
autor: CEO-AI (sessão autónoma)
---

# Bora no browser — plano de guards (FASE 0)

Objetivo: **o mesmo código Flutter** a servir clientes de iPhone (comprar/marcar/pedir
pelo site) e parceiros (gerir o negócio pelo browser com o login deles). Zero reescrita,
zero fork, mesmo Supabase, mesmas regras de negócio.

## 1. Terreno encontrado (não era zero)

| Facto | Estado |
|---|---|
| Flutter | 3.41.2 stable · web **enabled por defeito** (`--enable-web` default on) |
| Pasta `web/` | **já existe** (index.html, manifest.json, favicon, 4 ícones) — scaffold cru do `flutter create`, textos "bora_app"/"A new Flutter project" |
| Script Google Maps JS | **já presente** no `web/index.html` com `libraries=places,directions` |
| `.github/workflows/e2e-web.yml` | já existe (workflow_dispatch, build web release + mede tamanho) — **sem upload de artifact** |
| `build/web` | nunca produzido localmente |
| Guards `kIsWeb` | já em **15 ficheiros**, incluindo o bloco Stripe+Firebase+ForegroundService do `main()` |
| Roteamento por papel | `_RootNavigator` → `RoleScreen` → login por papel → `PartnerEntryScreen` para parceiro. **Web-safe, zero trabalho extra.** |
| Painel admin | é o mesmo app Flutter (ecrãs `admin/*`) → abre no browser pelo mesmo URL |

**Conclusão:** o bloqueio não é arquitetura — é `dart:io` e um punhado de plugins mobile-only.

## 2. Auditoria de plugins (36 diretos, classificados via pub cache)

### ✅ Web nativo (sem trabalho)
`supabase_flutter` · `shared_preferences` · `geolocator` · `google_maps_flutter` (web endorsed)
· `url_launcher` · `audioplayers` · `image_picker` · `firebase_core` · `firebase_messaging`
· `share_plus` · `printing` · `flutter_secure_storage` · `flutter_map` · `provider` · `http`
· `uuid` · `latlong2` · `fl_chart` · `cached_network_image` · `csv` · `table_calendar`
· `cupertino_icons` · `image` · `pdf` · `flutter_polyline_points`

### ⚠️ Sem web — precisam de stub honesto (no-op + log)
| Plugin | Usado em | Decisão web |
|---|---|---|
| `flutter_local_notifications` | main, notification_service, incoming_job_alert, permission_gate, driver_permissions | stub no-op — feedback web é in-app |
| `flutter_foreground_task` | foreground_service, heartbeat_service, notification_service, permission_gate, driver_permissions | stub no-op (não existe FGS no browser) |
| `flutter_overlay_window` | foreground_service, notification_service, permission_gate, driver_order_overlay, driver_permissions | stub no-op (Android-only por natureza) |
| `floating_bubble_overlay` | floating_bubble_service | stub no-op |
| `local_auth` | biometric_auth_service | stub → biometria indisponível na web |
| `geocoding` | map_screen | stub → sem reverse-geocode nativo; autocomplete Places cobre |
| `vibration` | driver_home, partner_dashboard | stub no-op |
| `path_provider` | admin_export_service | já `kIsWeb`-guardado |

**Nota técnica importante:** um plugin sem implementação web **não quebra o build** — o
Flutter só o omite e ele lança `MissingPluginException` em runtime. O que **quebra o
build** é código Dart que importa `dart:io`. Por isso o trabalho real da FASE 1 é o §3.

### 🔴 `flutter_stripe` — regra 4
Declara `web` no pubspec mas o PaymentSheet **não é fiável no browser**. Decisão:
não usar PaymentSheet na web. Rota web separada por **redirect** (Stripe Checkout Session
criada server-side por Edge Function nova `web-checkout`), atrás do kill switch
`web_card_payments_enabled=false` em `platform_settings`. **Nunca tocar no
`stripe-webhook` existente.** Se ficar grande/arriscado → só esqueleto + flag OFF.
**Dinheiro (cash) funciona 100% em todos os fluxos desde o dia 1** — não depende do Stripe.

## 3. O bloqueador real: `dart:io` em 20 ficheiros de `lib/`

Distribuição dos símbolos (levantamento mecânico):

- **`File` (16 ficheiros)** — quase sempre o mesmo padrão: `File(xfile.path)` vindo do
  `image_picker`, para (a) `readAsBytes()` antes de upload, (b) preview via
  `FileImage`/`Image.file`.
- **`Platform` (4 ficheiros)** — `Platform.isAndroid` / `isIOS` em main, admin_push_service,
  floating_bubble_service, push_token_service.
- **`SocketException` (1)** — main.dart, no logger de crash.

### Guard escolhido: shim por conditional export (padrão já usado no repo)

Segue o padrão que o repo já usa em `place_autocomplete_service.dart`:

```
lib/utils/io_compat.dart        →  export 'io_compat_io.dart'
                                   if (dart.library.js_interop) 'io_compat_web.dart';
lib/utils/io_compat_io.dart     →  export 'dart:io' show File, Directory, Platform, SocketException;
                                   ImageProvider boraLocalImage(String p) => FileImage(File(p));
lib/utils/io_compat_web.dart    →  class File  { path; readAsBytes() → XFile(path).readAsBytes(); … }
                                   class Platform { static isAndroid=false; isIOS=false; … }
                                   class SocketException implements Exception { … }
                                   ImageProvider boraLocalImage(String p) => NetworkImage(p);
```

Porquê assim:
1. **Zero risco para o Android** — no mobile o shim reexporta o `dart:io` verdadeiro; os
   call-sites (`Platform.isAndroid`, `File(x).readAsBytes()`) ficam **byte-a-byte iguais**.
   A única mudança em 20 ficheiros é a linha do `import`.
2. Na web, `XFile(blobUrl).readAsBytes()` **lê mesmo os bytes** (o `image_picker` web
   devolve `blob:` URLs) → upload de fotos funciona a sério, não é fingido.
3. `NetworkImage(blobUrl)` renderiza o preview local na web sem hacks.
4. `cross_file`/`XFile` já vem com o `image_picker` — **nenhuma dependência nova**.

Exceções que precisam de edição de call-site (7 no total, cirúrgicas):
- `FileImage(File(p))` → `boraLocalImage(p)` (5 sítios)
- `Image.file(File(p), …)` → `Image(image: boraLocalImage(p), …)` (2 sítios)

`admin_export_service` (escrita de ficheiro para CSV/PDF) **já está atrás de `kIsWeb`** —
o shim web só precisa de lançar `UnsupportedError`, que nunca é alcançado.

## 4. Notificações e tempo-real na web

- **FCM na web: NÃO** nesta fase (exigiria service worker + VAPID + `firebase-config` web).
  `Firebase.initializeApp()` fica fora do caminho web (já está, via `if (!kIsWeb)`).
- **Tempo-real: Supabase Realtime**, que o app já usa (`orders_channel`, `public:drivers`).
  Com o separador aberto, o parceiro **vê o pedido novo ao vivo**.
- **Feedback web** = in-app: som via `audioplayers` (tem web) + banner + **título do
  separador a piscar** quando entra oferta/pedido.

## 5. Zonas protegidas — como não lhes tocar

`dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`,
`stripe-webhook`, RLS de `orders`/`wallets`/`ledger` **não são editados**.
Toda a adaptação web é **à volta**: conditional imports, stubs e guards `kIsWeb` no
arranque e nas camadas de apresentação. Nenhum `if (kIsWeb)` entra dentro de lógica de
preço ou de dinheiro.

## 6. Caminho de build (Lei do Pré-Voo)

RAM da máquina: **3,9 GB total · 328 MB livres** no arranque da sessão.
`flutter build web --release` (dart2js) é o passo mais pesado → previsão de OOM local.

Plano: iterar os **erros de compilação** localmente (fase de kernel, barata — os erros de
`dart:io` aparecem antes do dart2js) e, se o dart2js morrer por memória, criar
`.github/workflows/build_web.yml` (checkout → flutter → build web → **upload artifact**) e
trazer o resultado com `gh run download`. O deploy continua local via wrangler.
O caminho efetivamente usado fica registado no relatório final.

## 7. Fases e critério de feito

| Fase | Critério de feito |
|---|---|
| 0 | Este documento commitado |
| 1 | `flutter build web --release` termina sem erros |
| 2 | Cada vertical completa um fluxo em DINHEIRO no browser |
| 3 | Manifest/ícones/meta iOS Bora + banner "adicionar ao ecrã principal" + splash |
| 4 | URL pública a servir o app (verificado por fetch) |
| 5 | bora-site com botões reais a apontar ao web app |
| 6 | Playwright 1280px + 390px com prova por `SELECT` no Supabase |
| 7 | Push + relatório + `/ctx doctor` |

## 8. TODOs conhecidos à partida

- `TODO_DANILO_ATIVAR_MAPS_JS_API` — a key do `web/index.html` precisa da **Maps
  JavaScript API** ativa no Google Cloud Console (o Android usa a Maps SDK for Android,
  que é outro produto). Se não estiver ativa, o mapa não carrega → fallback digno em
  lista, sem bloquear o pedido.
- Supabase Auth Redirect URLs: login email+password **não precisa** de redirect. Só o
  fluxo de recuperação de palavra-passe precisaria do domínio novo adicionado.
- Chave Maps está **hardcoded** no `web/index.html` (herdado). Restringir por HTTP
  referrer ao domínio do web app.
