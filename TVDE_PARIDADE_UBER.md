# TVDE (BORA MOTORISTA) — MATRIZ DE PARIDADE COM A UBER

> Auditoria profunda do vertical de transporte de passageiros vs **Uber Driver**
> (app do motorista) + **Uber** (app do passageiro). Base = leitura do código real
> (Flutter cliente/motorista/admin + RPCs/edge fns/triggers `tvde_*` + prod DB via MCP).
> · 2026-07-02 · CEO-AI / Claude Code · Sessão "TVDE Auditoria + P0 + Paridade".
>
> Legenda: ✅ existe · 🟡 parcial · ❌ falta · Prioridade: **P0** bloqueia teste real ·
> **P1** antes do launch · **P2** depois. Regra: só o que existe na Uber/Bolt; não inventar;
> não estragar o que funciona; TVDE continua 100% isolado (`tvde_*`).

---

## 0. ESTADO CONFIRMADO EM PROD (MCP)

- Realtime: `tvde_rides` **está** na publicação `supabase_realtime` ✅
- RLS: **todas** as 7 tabelas `tvde_*` com RLS ativa ✅ (`tvde_rides`, `tvde_access_requests`,
  `tvde_ride_events`, `tvde_subscriptions`, `tvde_ride_counters`, `tvde_driver_balances`,
  `tvde_driver_documents`)
- RLS `tvde_rides_select`: cliente **ou** motorista atribuído **ou** `current_offer_driver_id`
  **ou** admin → a oferta chega ao motorista por realtime ✅
- Sweep de ofertas expiradas: cron `tvde_dispatch_sweep` a cada **15s** ✅
- Tarifas/planos/TTL **todos** em `platform_settings` (13 chaves `tvde_*`) ✅
- Guard de "corrida em curso" no backend = `{solicitada, motorista_atribuido,
  motorista_a_caminho, motorista_chegou, em_andamento}` — `sem_motorista` **não** conta ✅

---

## 1. LADO MOTORISTA (ref.: Uber Driver)

| # | Capacidade Uber Driver | Bora | Estado | Prio | Nota |
|---|---|---|---|---|---|
| M1 | Mapa online com a posição própria | `tvde_driver_home_screen` | ✅ (FASE A) | P0 | **Corrigido nesta sessão** — antes era só ícone+toggle, sem mapa |
| M2 | Indicador online/offline claro | Cartão flutuante + Switch | ✅ | — | |
| M3 | Ganhos do dia visíveis na home | — | ❌ | P1 | Uber mostra €hoje no topo. `tvde_driver_balances` existe, sem UI |
| M4 | Resumo de corridas do dia | — | ❌ | P2 | nº de viagens/tempo online |
| M5 | Oferta: modal tela cheia + som + countdown | `tvde_offer_screen` + canal urgente | ✅ | P0 | Full-screen, countdown, aceitar/recusar |
| M6 | Oferta: **distância até ao pickup** | só mostra km da viagem + €valor | 🟡 | P1 | Falta "a X km / Y min de ti" (distância motorista→recolha) |
| M7 | Oferta chega/toca no telemóvel | `notify-tvde-driver` v3 + push-reload + realtime + poll 10s | ✅ (FASE A) | P0 | **Reforçado nesta sessão** (fallback triplo) |
| M8 | Fluxo: a caminho→cheguei→iniciar→finalizar | `tvde_ride_active_screen` | ✅ | P0 | Transições por RPC |
| M9 | Botão **Navegar** (abre Google Maps/Waze) | — | ❌ | P1 | Sem `url_launcher`/`google.navigation:` — motorista navega às cegas |
| M10 | "Cheguei" **notifica** o passageiro | RPC muda estado; sem push ao cliente | 🟡 | P1 | Falta `notify-tvde-client` (ver B-BACKEND) |
| M11 | Finalizar → resumo do ganho da corrida | Vai direto ao ecrã de avaliar | 🟡 | P1 | Uber mostra "ganhaste €X" antes/depois |
| M12 | Ecrã de ganhos (dia/semana) + histórico | — | ❌ | P1 | Sem ecrã de ganhos nem histórico do motorista |
| M13 | Avaliações: dar | `tvde_driver_rate_screen` + `tvde_rate` | ✅ | — | |
| M14 | Avaliações: receber + média visível | `drivers.avg_rating` existe; não mostrado no modo TVDE | 🟡 | P2 | |
| M15 | Cancelar / no-show do passageiro | Popup no ecrã ativo (`no_show`/`motorista`) | ✅ | — | |
| M16 | Ver nome/contacto do passageiro | Só origem→destino; sem nome/telefone | 🟡 | P1 | Uber mostra nome + botão ligar/chat |
| M17 | **Preferências de trabalho** (só corridas vs tudo) | — | ❌ | **P1** | **Decisão do Danilo** — implementar Fase C (toggle + admin) |
| M18 | Som **contínuo** enquanto a oferta toca | Heads-up toca 1x (bora_alert) | 🟡 | P2 | Uber toca em loop até responder |

## 2. LADO CLIENTE (ref.: Uber passageiro)

| # | Capacidade Uber passageiro | Bora | Estado | Prio | Nota |
|---|---|---|---|---|---|
| C1 | Pickup GPS + destino Places + preço ANTES | `tvde_request_ride_screen` | ✅ | P0 | GPS + autocomplete + `tvde_calculate_fare` |
| C2 | Solicitar corrida | `tvde_request_ride` | ✅ | — | |
| C3 | Procura c/ estado claro + cancelar durante busca | Spinner "À procura…" + botão Cancelar | ✅ | — | |
| C4 | Tracking: carro no mapa + posição a atualizar | poll `drivers.lat/lng` 5s + marker | 🟡 | P1 | Funciona, mas sem **ETA** e sem animação suave |
| C5 | Tracking: **ETA** do motorista | — | ❌ | P1 | Uber mostra "chega em X min" |
| C6 | Cartão do motorista (nome, carro, matrícula, ⭐) | — | ❌ | P1 | Tracking só mostra estado+€+rota; sem identidade do motorista |
| C7 | Estados a caminho/chegou/em curso/fim + tarifa final | `statusLabel` + painel | ✅ | — | |
| C8 | **Sem motorista**: msg clara + tentar de novo | `_StatusPanel` no-driver + Retry/Fechar | ✅ (FASE A) | P0 | **Estado preso corrigido nesta sessão** (P0-3) |
| C9 | Push "o teu motorista está a chegar/chegou" | — | ❌ | P1 | Sem `notify-tvde-client`; cliente depende de realtime/poll |
| C10 | Avaliação do motorista | `tvde_rate_screen` | ✅ | — | |
| C11 | Histórico de viagens | `tvde_rides_history_screen` | ✅ | — | |
| C12 | Planos/assinatura + contador diário | `tvde_plans_screen` + `tvde_ride_counters` | ✅ | — | Concedida por admin (sem Stripe — Fase 7) |
| C13 | Chat com o motorista | tabela `messages` existe; não wired no TVDE | ❌ | P2 | |
| C14 | Contactar motorista (ligar) | — | ❌ | P2 | |

## 3. ADMIN (PT-BR)

| # | Capacidade | Bora | Estado | Prio | Nota |
|---|---|---|---|---|---|
| A1 | Corridas ao vivo | `admin_tvde_rides_screen` + `admin_tvde_rides_list` | ✅ | — | |
| A2 | Histórico + financeiro (motorista/Bora) + CSV | idem | ✅ | — | |
| A3 | Gestão de motoristas (banir/rever) | `admin_tvde_drivers_screen` (+ heartbeat/GPS/token) | ✅ | — | Reforçado no commit 2effe8d |
| A4 | Pedidos de acesso (perfil + aprovar/recusar/revogar) | `admin_tvde_access_requests_screen` | ✅ | — | |
| A5 | Assinaturas (conceder) | `admin_tvde_subscriptions_screen` | ✅ | — | |
| A6 | Revisão de documentos (KYC) | `admin_tvde_docs_review_screen` + RPCs | ✅ | — | |
| A7 | Tarifas/planos/taxas configuráveis | `admin_platform_settings_screen` (13 chaves) | ✅ | — | |
| A8 | Ver/editar **preferência de trabalho** do motorista | — | ❌ | **P1** | Espelho de M17 (Fase C) |

## 4. BACKEND

| # | Capacidade | Estado | Prio | Nota |
|---|---|---|---|---|
| B1 | Estados completos e consistentes | ✅ | — | 10 estados; guard alinhado app↔backend (P0-3) |
| B2 | Sweep pg_cron de ofertas expiradas | ✅ | — | `tvde_dispatch_sweep` 15s |
| B3 | Recusa → rotação ao próximo (`tried_driver_ids`) | ✅ | — | Fase 2 |
| B4 | Liquidação cash isolada | ✅ | — | `tvde_driver_balances` (nunca ledger/orders) |
| B5 | RLS em tudo `tvde_*` | ✅ | — | 7/7 tabelas |
| B6 | Elegibilidade por frescura (heartbeat∨GPS) | ✅ | — | commit 2effe8d |
| B7 | **Push ao passageiro** (`notify-tvde-client`) | ❌ | **P1** | Edge fn + trigger em falta; alimenta C9/M10 |
| B8 | Auditoria do resultado FCM da oferta | ✅ | — | `tvde_ride_events` push_enviado/push_falhou |

---

## 5. FASE C — PLANO DE IMPLEMENTAÇÃO (P0 já feitos; P1 a fazer)

Ordem (maior valor/menor risco primeiro), gate por item (`flutter analyze` 0 erros):

1. **B7/C9/M10 — `notify-tvde-client`** (edge fn + trigger em `tvde_rides`): push ao
   passageiro em `motorista_atribuido`/`motorista_a_caminho`/`motorista_chegou`
   (+`sem_motorista`). Molde `notify-tvde-driver`, isolado. **Não** toca `notify-driver`.
2. **M9 — Botão Navegar** no `tvde_ride_active_screen` (abre Google Maps/Waze via
   `url_launcher`, `google.navigation:` / `geo:`). Flutter puro.
3. **M17/A8 — Preferências de trabalho** (`só corridas` vs `tudo`): coluna em `drivers`,
   toggle nas definições do motorista, espelho no admin, **filtro aditivo no matching**
   (nunca no core do `dispatch_engine`). Detalhe de segurança no relatório final.
4. **M3 — Ganhos do dia** no cartão da home do motorista (lê `tvde_driver_balances`).
5. **C6/M16 — Identidade** (cartão do motorista no tracking do cliente; nome do
   passageiro no ecrã do motorista).
6. **C5/C4 — ETA + animação** do carro no tracking (reusa `directions_service`).

### P2 (pós-launch, listar não implementar)
- M4 resumo do dia · M11 resumo do ganho pós-corrida · M14/M18 rating recebido + som
  contínuo · M12 ecrã ganhos semana + histórico motorista · C13/C14 chat + ligar ·
  dual-driver pleno (1 motorista a receber corridas **e** entregas em simultâneo — hoje
  o `vehicle_type` roteia 1 modo; o toggle abre o caminho, o pleno fica design futuro).
