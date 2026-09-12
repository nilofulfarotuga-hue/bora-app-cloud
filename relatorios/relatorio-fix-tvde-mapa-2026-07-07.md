# Fix TVDE cliente — mapa heading-up + sugestões de morada — 2026-07-07

Branch: `autonomous-night-2026-04-29` · Escopo: só UI/mapas do TVDE cliente (zonas protegidas intactas)

## 1) 🔴 Mapa do cliente não rodava (heading-up)

**Bug:** no ecrã de acompanhamento da corrida (`tvde_ride_tracking_screen.dart`), a câmara era
plana e fixa north-up: `newLatLngZoom(target, 15)` só no botão mira, sem tilt, sem bearing, sem
seguir o carro. No motorista, o que dá a sensação de "acompanhar" é a combinação: **bearing
calculado pelo delta de posições GPS** (≥5 m, para não amplificar ruído — `tvde_driver_home_screen`
[Item G]) + **câmara de navegação estilo Waze** (zoom 17.5 / tilt 45 — `tvde_ride_active_screen`
[Bloco B]). O cliente não tinha nenhuma das duas partes.

**Fix (paridade com o motorista):**
- `_bearing` calculado a cada poll do motorista (posições cruas, não animadas), mesmo padrão
  ≥5 m / `Geolocator.bearingBetween` do ecrã do motorista.
- **Follow heading-up:** a cada posição nova, a câmara anima para
  `CameraPosition(target: carro, zoom: 17.5, tilt: 45, bearing: _bearing)` — o mapa RODA com a
  direção de marcha. Constantes espelham `tvde_nav_zoom`/`tvde_nav_tilt` do `platform_settings`
  (leitura dinâmica pendente — mesmo TODO já anotado no ecrã do motorista).
- **Gesto pausa, mira religa:** arrastar o mapa desativa o follow (senão o utilizador nunca
  consegue explorar); o botão mira volta a ativar e recentra com a câmara de navegação.
  Distinção gesto vs programático via flag `_progCamMove` em `onCameraMoveStarted`.
- `compassEnabled: true` (antes false) — com o mapa rodado, a bússola nativa deixa repor o norte.

## 2) 🟡 Sugestões de morada "aparecem baixo"

**Causa:** o `AddressAutocompleteField` (partilhado por TVDE, limpeza, etc.) abria o overlay
**sempre para baixo** (`targetAnchor: bottomLeft`). Em campos a meio da página (destino do TVDE),
com o teclado aberto, a lista renderizava atrás/abaixo do teclado. No wizard da limpeza o campo
está no topo, por isso lá sempre mostrou bem — consistente com o que o Danilo viu.

**Fix (só posicionamento, zero mudança de fluxo):** o overlay mede o espaço disponível abaixo do
campo (descontando o teclado via `viewInsets`); se < 180 px e houver mais espaço acima, **abre
para cima** (flip de anchors) com altura adaptada (`clamp 96–220`). Campos no topo mantêm o
comportamento atual.

## 3) 🔎 `est_fare_cents = 0` — NÃO é bug (análise)

- `tvde_calculate_fare` funciona: devolve 500¢ (mínimo €5) para 2 km e 5 km.
- A RPC `tvde_request_ride` grava em `est_fare_cents` o **valor a pagar pelo cliente**, e no ramo
  de corrida **coberta pelo plano** define `v_client_fare := 0` **por design** ("Incluída no
  plano"). Todas as corridas recentes do Danilo têm `used_subscription_ride=true` (plano ativo) —
  por isso 0. As corridas antigas sem plano têm 500/600¢ corretos. `driver_earn_cents=340` /
  `bora_cut_cents=60` batem com a regra coberta×0,85 (CAMPO-01). ✅ Nada a corrigir.
- ⚠️ **Observação de negócio (decidir, não corrigido):** a taxa de cancelamento pós-janela usa
  `est_fare_cents` → numa corrida coberta, cancelar TARDE custa €0 ao cliente (e a corrida do
  plano é consumida? a devolver?). Confirmar se é o comportamento desejado.
- **Admin:** `admin_tvde_rides_screen` mostra `final_fare ?? est_fare` → corridas de plano
  aparecem como €0.00. Correto no sentido "cliente pagou 0", mas pode enganar na leitura de
  receita; sugestão futura: badge "Plano" na linha.

## Outros achados do fluxo (regra "reporta tudo")

- O ecrã de pedido (`tvde_request_ride_screen`) confirma: pagamento em dinheiro ao motorista
  (sem cartão), toggle "Garantir a volta" €8, teaser de planos — tudo coerente com CAMPO-01/02.
- Relatório anterior da corrida noturna dizia "autocomplete não resolve" — **errado** (limitação
  da automação Maestro; teste manual do Danilo confirma que funciona). Corrigido aqui.

## Validação

- `flutter analyze` nos 2 ficheiros alterados: **No issues found**.
- ⚠️ Verificação visual (mapa a rodar + lista acima do teclado) fica para a **próxima build do
  CI** — o Redmi tem a release instalada e build local é proibida (RAM/assinatura). A lógica do
  bearing é port direto do padrão já comprovado no mapa do motorista.

## Ficheiros

- `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` — heading-up follow + mira + bússola
- `lib/widgets/address_autocomplete_field.dart` — flip do overlay quando falta espaço abaixo
