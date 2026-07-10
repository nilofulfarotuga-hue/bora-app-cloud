# Relatório — 3 bugs de crash (2026-07-10)

Branch: `autonomous-night-2026-04-29` · Zona: 🟢 verde/UI (nenhuma zona vermelha tocada).
Triados via `debug_crash_logs`. Cada bug = commit separado.

---

## Bug #1 — GPS desligado rebenta o app 🟢 RESOLVIDO
**Sintoma:** "location service disabled" (5× na build 396). `Geolocator.getPositionStream`
sem `onError` deixava a `LocationServiceDisabledException` por tratar quando o utilizador
desligava o GPS a meio do stream → crash.

**Correção (commit `37e6109` + afinação nesta sessão):**
- Adicionado `onError` aos **3 streams** de GPS (mapa TVDE, home estafeta, mapa estafeta):
  apanha `LocationServiceDisabledException` e mostra SnackBar PT-PT amigável
  ("GPS desativado. Ative a localização…") com botão **Ativar** → `Geolocator.openLocationSettings`.
- **Pré-checks** (`isLocationServiceEnabled` antes de chamar) em todos os pontos:
  - `driver_map_screen.dart` (`_startLocationTracking`) — SnackBar + botão Ativar ✓
  - `driver_home_screen.dart` (`_startPositionStream`) — SnackBar + botão Ativar ✓
  - `driver_home_screen.dart` (`_fetchInitialGpsCenter`) — fallback silencioso (one-shot centragem) ✓
  - `tvde_driver_home_screen.dart` (`_startGps`) — **afinado nesta sessão**: SnackBar
    passou a ter botão **Ativar** (antes era aviso simples sem ação), para paridade com os restantes.
- **Criar pedido com morada / discovery:** passam por `LocationService.getCurrentLocation`,
  que **nunca lança** (devolve `null` em serviço desligado / permissão negada / timeout).
  Não há exceção para rebentar → coberto.

**Ficheiros:** `lib/screens/driver_map_screen.dart`, `lib/screens/driver_home_screen.dart`,
`lib/screens/driver/tvde/tvde_driver_home_screen.dart`.

---

## Bug #2 — Image picker "already_active" 🟢 RESOLVIDO
**Sintoma:** crash "already_active" (3×). Toques repetidos no botão de foto (ou dois pickers
em ecrãs diferentes) abriam um 2.º `pickImage` antes do 1.º terminar. O plugin nativo só
permite um pedido de seleção ativo em toda a app.

**Correção (commit `6ef7218`):**
- `lib/utils/safe_image_picker.dart` — wrapper com flag global `_isPicking` reposta num
  `finally`. Toque repetido enquanto um pick decorre → devolve `null` em vez de lançar.
- Migrados **todos os pontos editáveis** que abrem picker: avatar (`profile_screen`),
  upload de documento (`driver_signup_screen`, `driver_role_apply_screen`, `cleaner_apply_screen`,
  `mandatory_photo_picker`), favores (`errand_form_screen`), add produto (`add_product_screen`),
  admin (`admin_partner_detail_screen`), registo parceiro (`register_partner_screen`),
  talão no mapa (`driver_map_screen`).

**Fora do escopo (PROPOSTA — zona Trava, não editável pelo executor):**
- `lib/widgets/errand_execution_sheet.dart` (execução de favor). Recomenda-se migrar para
  `SafeImagePicker` quando um humano puder aplicar na zona protegida.

---

## Bug #3 — "Null check operator used on a null value" ao finalizar árvore de widgets 🟡 PROVAVELMENTE RESOLVIDO
**Sintoma:** crash na finalização da árvore de widgets (`finalizeTree`), 2× na build **357** (antiga).

**Investigação:**
- Build 357 é ~40 builds antiga (atual ~396–399), com 2 merges pelo meio.
- Varrido `lib/` pelo padrão clássico de crash em `finalizeTree` — `!` sobre campo late/nullable
  dentro de `dispose()/deactivate()` (`!.dispose()/cancel()/close()/removeListener()/unsubscribe()`).
- Único resultado: `driver_store.dart:836` (`_driverLocationChannel!.unsubscribe()`), mas está
  **guardado** por `if (_driverLocationChannel != null)` → seguro, não é o culpado.
- Sem stack trace com ficheiro/linha, não há ponto único a apontar; não reproduz na build atual.

**Decisão:** registado como **provavelmente-resolvido** (conforme instrução: se não reproduz na
build atual, registar e seguir). Nenhum `!` inseguro em finalização de widgets sobreviveu.
Se voltar a aparecer numa build recente com stack trace, trocar o `!` culpado por `?.`/guard.

---

## Resumo
| Bug | Estado | Commit |
|---|---|---|
| #1 GPS desligado | 🟢 Resolvido | `37e6109` + afinação TVDE nesta sessão |
| #2 picker already_active | 🟢 Resolvido | `6ef7218` |
| #3 null check finalizeTree | 🟡 Provavelmente resolvido (não reproduz) | — |

**Fora do escopo:** `errand_execution_sheet.dart` (picker) fica como proposta para zona Trava.
**Não tocado:** zonas vermelhas, versionCode. `flutter analyze` + `flutter test` corridos.
