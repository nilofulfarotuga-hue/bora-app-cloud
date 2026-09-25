# TVDE (BORA MOTORISTA) — RELATÓRIO FINAL DA SESSÃO

> Auditoria profunda + correção dos 3 P0 confirmados em prod + paridade Uber.
> · 2026-07-02 · CEO-AI / Claude Code · branch `autonomous-night-2026-04-29`.
> Isolamento mantido: tudo em paths `tvde_*`; **zero** toques em zonas protegidas
> (dispatch_engine, pricing, finalizePurchase, Stripe, ledger/orders, tokens).

---

## 1. FASE A — P0 CORRIGIDOS (os 3, com gate `flutter analyze` 0 erros)

### P0-1 · Mapa do motorista não renderizava ✅
- **Causa real:** o ecrã `tvde_driver_home_screen` **nunca teve mapa** — era só um
  ícone + toggle. Não era "tela branca"; era ausência de mapa.
- **Fix:** mapa `GoogleMap` em tela cheia com a posição própria (marker + blue dot),
  câmara a seguir o motorista, e o cartão de estado/toggle **flutuante por cima**
  (num `Stack`, logo renderiza sempre — fallback defensivo se a platform view demorar).
  Centro por omissão (Guarda) + chip "a localizar" até ao 1.º fix de GPS.
- Ficheiro: `lib/screens/driver/tvde/tvde_driver_home_screen.dart`.

### P0-2 · Oferta não tocava / não aparecia ✅
- **Estado:** `notify-tvde-driver` v3 (canal urgente `bora_orders_urgent_v3` + som +
  TTL reancorado) e a subscrição realtime já existiam. Confirmado em prod:
  `tvde_rides` **está** na publicação realtime e a RLS deixa o motorista ofertado ver
  a linha — o caminho realtime é são.
- **Reforço (fallback triplo):** (1) o push `new_tvde_ride_offer` agora **força
  `TvdeDriverStore.loadCurrent()`** (chegada + tap) via hook `NotificationService.
  tvdeOfferReload` — a tela de oferta abre mesmo que o realtime caia; (2) tap na
  notificação (foreground/background/cold) roteia para a oferta; (3) **poll de 10s**
  enquanto online e ocioso, como rede de segurança final.
- Modal de oferta full-screen com countdown + aceitar/recusar já existia (gate ok).
- Ficheiros: `lib/services/notification_service.dart`, `tvde_driver_home_screen.dart`.

### P0-3 · Cliente preso na tela "sem motorista" ✅
- **Causa raiz:** `TvdeRide.isLive` incluía `isNoDriver` **e** `loadActiveRide`
  incluía `'sem_motorista'` na lista de estados "ativos" → ao reabrir "Bora Motorista"
  o `_bootstrap` retomava o tracking antigo (€/endereço velhos).
- **Fix:** `sem_motorista` passa a **terminal para o resume** (alinhado com o guard do
  backend `tvde_request_ride`, que nunca o considera "em curso"). `isLive` = apenas
  `{solicitada, atribuído/a caminho/chegou, em andamento}`; `loadActiveRide` já não
  carrega `sem_motorista`. Cancelamento agora **limpa o estado local + navega de volta
  de forma determinística** (não espera o realtime). A tela sem-motorista mantém
  "Tentar de novo" (corrida nova) + "Fechar".
- Ficheiros: `lib/models/tvde_ride.dart`, `lib/stores/tvde_store.dart`,
  `lib/screens/client/tvde/tvde_ride_tracking_screen.dart`.

---

## 2. FASE B — MATRIZ DE PARIDADE
Ver **`TVDE_PARIDADE_UBER.md`** (matriz completa ✅/🟡/❌ por eixo motorista/cliente/
admin/backend, priorizada P0/P1/P2). Estado de prod confirmado por MCP: realtime on,
RLS 7/7 tabelas, sweep cron 15s, 13 chaves de tarifa configuráveis, 0 ERROR advisors.

---

## 3. FASE C — GAPS IMPLEMENTADOS (P1)

| Item | O quê | Ficheiros / objetos |
|---|---|---|
| **B7/C9/M10** | **Push ao passageiro** (motorista a caminho/chegou/viagem/sem motorista/cancelada) — edge fn `notify-tvde-client` (deploy v1, verify_jwt) + trigger `tr_notify_tvde_client_on_status` | `supabase/functions/notify-tvde-client/`, migration `20260702120000` |
| **M9** | **Botão Navegar** (Google Maps/Waze) no ecrã ativo do motorista — recolha (a caminho) / destino (em viagem) | `tvde_ride_active_screen.dart` (reusa `NavigationService`) |
| **M17/A8** | **Preferências de trabalho** (só corridas vs tudo): coluna `drivers.work_mode` + RPC `tvde_set_work_mode` (motorista) + `admin_set_driver_work_mode` (admin) + toggle na home do motorista + espelho no painel admin | migrations `20260702130000`/`130001`, `tvde_driver_home_screen.dart`, `admin_tvde_drivers_screen.dart`, `tvde_driver_store.dart` |
| **M3** | **Ganhos do dia** no cartão da home do motorista (soma `driver_earn_cents` das finalizadas de hoje) | `tvde_driver_store.dart`, `tvde_driver_home_screen.dart` |
| **M6** | **Distância até à recolha** no cartão de oferta ("recolha a X km de ti") | `tvde_offer_screen.dart` |
| **C6/C4** | **Cartão do motorista** no tracking do cliente (nome + ⭐) **e correção de bug**: o poll do motorista usava `drivers.id` mas `tvde_rides.driver_id` = `user_id` → o marker/cartão nunca aparecia para motoristas reais. Agora resolve por `user_id`. | `tvde_ride_tracking_screen.dart` |

Todos com `flutter analyze` 0 erros e advisors de segurança 0 ERROR.

---

## 4. ⚠️ DECISÃO DO DANILO — integração do toggle no dispatch de ENTREGAS

O toggle "só corridas vs tudo" está **completo** no lado das corridas (guardado, UI do
motorista, espelho admin, auditado). O **default é `everything`** → **zero regressão**
para os estafetas de entrega atuais.

O que **falta** e é **decisão tua** (não foi tocado porque cai em zona protegida e no
design "dual-driver" adiado — R2 do plano):

1. **Filtro no matching do delivery** (aditivo, provado não-regressivo): excluir do
   matching de entregas quem escolher `rides_only`. É **1 cláusula WHERE** —
   `AND COALESCE(work_mode,'everything') <> 'rides_only'` — na seleção de estafetas
   elegíveis. **Não** mexe no core do `dispatch_engine`, mas como a elegibilidade vive
   dentro da função protegida, **deixo como proposta para tua aprovação** (a regra da
   sessão é: dinheiro pára; dispatch é 🔴 propose-only).
2. **Dual-driver pleno** (um motorista `carro_passageiros` receber **também** entregas):
   exige o `supportsService()` + routing de veículo aceitarem `carro_passageiros` no
   delivery. É uma mudança estrutural — **design a decidir**. Hoje `vehicle_type` roteia
   1 modo, por isso o `everything` de um motorista de passageiros ainda não lhe traz
   entregas. O toggle deixa o caminho aberto e seguro.

Diz **"vai no filtro de entregas"** e aplico o ponto 1 (com Juiz + gate).

---

## 5. OUTROS BUGS ENCONTRADOS (reportados)

- **[Corrigido nesta sessão]** Tracking do cliente: poll do motorista por `drivers.id`
  em vez de `user_id` → marker do motorista invisível para motoristas reais.
- **[Pré-existente, fora de scope — flag]** `admin_tvde_drivers_list`: as contagens
  `active_rides`/`total_rides` cruzam `r.driver_id = d.id`, mas `tvde_rides.driver_id`
  guarda o `user_id` do motorista → para motoristas reais estas contagens dão 0.
  Correção sugerida: `r.driver_id = d.user_id`. (Não alterado — é display admin, não P0.)

---

## 6. P2 PENDENTES (listados, não implementados)
- C5 ETA do motorista no tracking · C4 animação suave do carro
- M11 resumo do ganho pós-corrida · M12 ecrã de ganhos da semana + histórico do motorista
- M16 nome/contacto do passageiro no ecrã do motorista · M14 rating recebido visível
- M18 som contínuo na oferta (hoje toca 1×) · C13/C14 chat + ligar
- Deep-link do push `tvde_ride_status` para o tracking (hoje informa; abrir o ecrã fica P2)

---

## 7. PENDENTES DE SEMPRE (decisão/ação do Danilo)
- Pagamentos cartão/MB Way (Fase 7) — hoje só cash + assinatura por admin.
- Valor da taxa de cancelamento (`tvde_cancel_fee_cents=0`, configurável).
- Licença IMT / legislação TVDE.
- **Teste no device físico** (build do CI) — mapa a renderizar, oferta a tocar/aceitar,
  push do passageiro a chegar, estado sem-motorista sem prender.

---

## 8. MIGRATIONS APLICADAS EM PROD (via MCP) + FICHEIROS NO DISCO
- `20260702120000_tvde_notify_client_on_status.sql` — trigger push passageiro.
- `20260702130000_tvde_driver_work_mode.sql` — coluna + 2 RPCs de preferência.
- `20260702130001_admin_tvde_drivers_list_work_mode.sql` — expõe work_mode no admin.
- Edge function deployed: `notify-tvde-client` (v1, ACTIVE, verify_jwt=true).
