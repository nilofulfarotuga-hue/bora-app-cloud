# TVDE — POLIMENTO FINAL (pós-teste no device)

> 2026-07-02 · CEO-AI / Claude Code (Opus 4.8) · branch `autonomous-night-2026-04-29`
> Regra de ouro respeitada: **NADA às cegas** — cada mudança cita o código do
> ESTAFETA (delivery) reutilizado. dispatch-engine v58 = **ZONA PROTEGIDA TOTAL**
> (não tocada). Única mudança de tarifa permitida (B1: fonte da distância) fica
> em **PROPOSE-ONLY** por mexer em dinheiro real.

---

## PASSO 0 — Trava: matcher do hook de banco (proposta)
`bora_app/.claude/settings.json` tinha o matcher `Bash|mcp__.*[Ss]upabase.*`, que
**não** apanha o conector Supabase desta sessão (nome UUID `mcp__cb62ddfa-…__execute_sql`).
- Ficheiro gerado: **`.claude/settings.proposto.json`** (idêntico ao atual, só o matcher
  passa a `Bash|mcp__.*[Ss]upabase.*|mcp__.*__(execute_sql|apply_migration|deploy_edge_function)`
  — igual à pasta-mãe).
- Aplicar (1 passo, PowerShell em `bora_app\`):
  `Copy-Item .claude\settings.proposto.json .claude\settings.json -Force`
- Não apliquei eu (ficheiro trava-protegido). Enquanto não copiares, tratei **todo** o
  SQL desta sessão como fora da Trava (só leituras + 1 UPDATE não-financeiro em settings).

---

## BLOCO A — OFERTA 100% CONFIÁVEL ✅ (gate `flutter analyze` 0 erros)
Ficheiro: `lib/screens/driver/tvde/tvde_offer_screen.dart` (+ setting no prod).

| # | O quê | Copiado do estafeta | Fix |
|---|---|---|---|
| A1 | **Som contínuo** na oferta | `SoundService.playLoop()` + `sounds/bora_alert.wav` (o mesmo loop que o delivery usa; ver `notification_service.dart` `_invokeAcceptOffer`/`_sound.stop`) | Instância própria de `SoundService` no ecrã de oferta: `playLoop()` no `initState`, `stop()` em aceitar/recusar/expirar/`dispose`. Antes tocava 1× (heads-up) e o ecrã não fazia loop. |
| A2 | **Deep-link do push** | Já existia (`NotificationService.tvdeOfferReload` em FG/BG/cold + `onMessageOpenedApp` + `getInitialMessage`) | Verificado: tap abre a oferta via `loadCurrent()`→`_syncNav()`. |
| A3 | **Recusar morto** | — | Causa: o botão partilhava `store.busy` do Aceitar. Agora tem guard **local** `_acting`; `tvde_reject_ride` (confirmado em prod) faz rotação/`sem_motorista`. |
| A4 | **Modal preso em oferta morta** | — | `_autoClose` (para o som + `maybePop`) já dispara por `offeredRide==null` (realtime) e por countdown ≤0; Recusar é a saída garantida. **Nunca fica sem escape.** |
| A5 | **Timeout ≠ delivery** | `dispatch_offer_timeout_seconds=40` | `tvde_offer_ttl_seconds` **25 → 40** (prod, setting não-financeiro) + fallback do ecrã 25→40. `notify-tvde-driver` já reancora `offer_expires_at` com este valor. |

## BLOCO B — MAPA, KM E NAVEGAÇÃO ✅ (UI) / 🔴 B1 PROPOSE-ONLY
Serviço reutilizado (mesma chave Google, zero config nova):
`lib/services/directions_service.dart` → `fetchRoute(origin,dest)` → `DirectionsRoute{distanceKm,durationMinutes,points}` (usa `googleApiKey` de `maps_config.dart`).

- **B2 — polyline grossa** ✅ recolha→destino, `width:12`, cor `AppColors.primary`, nos **dois**
  lados: `tvde_ride_active_screen.dart` (motorista) e `tvde_ride_tracking_screen.dart` (cliente).
  Pontos via `route.points.toGMaps()` (extensão de `utils/map_utils.dart`, a do delivery).
- **B4 — pin azul → bolinha** ✅ motorista: removido o marker azure manual; `myLocationEnabled:true`
  (bolinha nativa, igual ao estafeta/`tvde_driver_home_screen`).
- **B5 — botão mira** ✅ motorista **e** cliente (FAB `Icons.my_location` → `animateCamera`).
- **B6 — ETA do motorista** ✅ pela **rota real** (`route.durationMinutes`): "Recolha em ~X min" /
  "Chegada ao destino em ~X min". (O cliente já tinha C5.)
- **B3 — navegação in-app** 🟡 rota desenhada + recentrar + botão **Navegar** externo
  (`NavigationService.openNavigationOptions`, Google Maps/Waze) — **paridade com o estafeta**,
  que também usa navegação externa (não há turn-by-turn in-app no delivery).

### 🔴 B1 — KM POR ROTA REAL NA TARIFA — **PROPOSE-ONLY (mexe em dinheiro)**
Estado atual (verificado em prod via MCP):
- `tvde_calculate_fare(p_distance_km)` é **só coeficientes** (base 500c, 6km incl., +50c/km) —
  não calcula distância; recebe-a.
- A **estimativa** (`tvde_request_ride_screen._distanceKm`) usa `Distance().as()` = haversine.
- A **tarifa final** usa `p_final_distance_km` que o app passa em
  `tvde_ride_active_screen._finish` → hoje `store.finishRide(ride.id, ride.estDistanceKm)`
  (a estimativa haversine).

Proposta (coeficientes **inalterados**, só a FONTE da distância muda para rota real):
1. **Cliente (estimativa):** substituir `_distanceKm` haversine por
   `DirectionsService().fetchRoute(pickup,dest).distanceKm` (fallback haversine se falhar) →
   `estimateFareCents` e `requestRide(distanceKm: …)` passam a usar a rota.
2. **Motorista (final):** `_finish` passa a distância de rota (já a temos no ecrã ativo via
   `_maybeFetchRoute`) em vez de `ride.estDistanceKm`.

> ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO.** Muda o valor cobrado ao cliente e pago ao motorista
> (no teste, os €5/€4 sobem para a distância real, ex.: Av. do Rio Diz 26 → Rua do Torreão 4).
> Está tudo pronto — **confirma que eu aplico** (responde "vai no B1"). Só então aplico + Juiz + gate.

## BLOCO H2 — DOC DRIFT ✅
`BORA_MOTORISTA_PLANO.md` §8: "checklist §9" (inexistente) → aponta para
`TVDE_PARIDADE_UBER.md` (checklist canónico). (H1 — Trava na pasta-mãe — fechado na sessão anterior.)

---

## PENDENTE NESTA SESSÃO (C, D, E, F, G) — especificado, NÃO implementado
Fica com a fonte do estafeta já localizada, para continuar sem “às cegas”:

- **C1/C2 — mapa + recolha editável** (`tvde_request_ride_screen.dart`): hoje só 2 campos.
  Reutilizar `GoogleMap` + `AddressAutocompleteField` (já importado p/ destino) para a recolha +
  arrastar pin → `LocationService.reverseGeocode(loc, googleApiKey)` (a mesma do `_detectPickup`).
- **C3/C4 — planos visíveis + clicáveis** (`tvde_plans_screen.dart`): entrada visível na home +
  botão "Quero aderir" → **nova tabela** `tvde_plan_requests` (pedido) + badge no admin
  (`admin_tvde_subscriptions_screen`). Pagamento online do plano = **decisão do Danilo**.
- **D1 — card do motorista (foto+carro)**: `drivers` tem `license_plate`, `vehicle_photo_url`,
  `photo_url`, mas **falta cor/marca/modelo** → migration aditiva `drivers.vehicle_color`,
  `drivers.vehicle_make_model` + campo no onboarding TVDE + editável no admin + render no
  `tvde_ride_tracking_screen` `_StatusPanel` (já mostra nome+⭐).
- **D2 foto do cliente p/ motorista** · **D3 botões arredondados** (radius do design system).
- **E — chat + ligar**: reutilizar o chat bidirecional do delivery (tabela `messages` existe;
  scoping por `tvde_ride_id`) + botão `tel:` nos dois lados + push (`notify-chat-message`).
- **F — home do motorista**: varrer a home do estafeta (`driver_home_screen`) e adaptar suporte,
  tempo online do dia (M4), avaliação média (M14), histórico com detalhe.
- **G — admin PT-BR**: fotos em todas as gestões (clientes/estafetas/TVDE/parceiros),
  aprovar adesão a planos (C4), campos do carro (D1), tabela de paridade.

## DECISÕES DO DANILO (pendentes)
- 🔴 **B1** — aplicar km por rota na tarifa (responde "vai no B1").
- Pagamento online de planos TVDE (Fase 7).
- Cobrança de no-show (`tvde_cancel_fee_cents=0`, fluxo pronto).

---

## CHECKLIST DE TESTE NO DEVICE (itens desta sessão)
1. **Som (A1):** pede corrida como cliente → no motorista a oferta **toca em loop** até
   aceitar/recusar/expirar (não 1× só).
2. **Recusar (A3):** na oferta, "Recusar" responde sempre; fecha o modal e liberta o dispatch.
3. **Oferta morta (A4):** deixa a oferta expirar (40 s) ou é levada por outro → o modal
   **fecha sozinho**, sem ecrã preso.
4. **Timeout (A5):** o countdown da oferta arranca em ~40 s (igual ao delivery).
5. **Rota grossa (B2):** no mapa do motorista **e** do cliente aparece a linha grossa
   recolha→destino (cor verde).
6. **Bolinha (B4):** no mapa do motorista a tua posição é a **bolinha azul** (sem pin extra).
7. **Mira (B5):** botão 🎯 recentra o mapa (motorista e cliente).
8. **ETA (B6):** no painel do motorista aparece "Recolha em ~X min" / "Chegada ao destino em ~X min".
9. **Navegar (B3):** botão Navegar abre Google Maps/Waze (recolha a caminho / destino em viagem).
10. **Doc (H2):** `BORA_MOTORISTA_PLANO.md` §8 já não cita "§9".

## OBJETOS ALTERADOS
- Flutter: `tvde_offer_screen.dart`, `tvde_ride_active_screen.dart`,
  `tvde_ride_tracking_screen.dart` · doc `BORA_MOTORISTA_PLANO.md`.
- Prod (não-financeiro): `platform_settings.tvde_offer_ttl_seconds` 25→40.
- Proposta: `.claude/settings.proposto.json` (PASSO 0).
- **Não** tocado: dispatch-engine, pricing, `tvde_calculate_fare`, Stripe, ledger/tokens.
