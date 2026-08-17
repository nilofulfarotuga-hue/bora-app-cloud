# VARREDURA TOTAL TELA-A-TELA — Relatório vivo

> Missão noturna 2026-08-16/17 · "O código é o olho" · 4 papéis · Matriz 🔴 bug real / 🟡 abaixo do padrão / 🟢 ok
> Inventário técnico completo: `VARREDURA_TOTAL_TELAS.inventario.md` (414 ficheiros, 196 ecrãs, BFS de alcançabilidade)
> Base funcional: mapas de fluxos do Córtex (35 fluxos, 2026-07-10) — atualizados no fecho.

## Tabela mestre de áreas (F0)

| Área | Raiz | Ecrãs (aprox.) | Referência de comparação |
|---|---|---|---|
| F1 Motorista TVDE | `TvdeDriverHomeScreen` (root p/ `carPassengers`) | tvde_offer, tvde_ride_active, tvde_driver_rate, ganhos, planos, histórico | Uber Driver, Bolt Driver, 99 |
| F2 Cliente TVDE | tile Bora Motorista → `TvdeRequestRideScreen` | request, tracking, plans, unlock, histórico | Uber, Bolt, 99 |
| F3 Cliente Delivery | `ClientMainScreen` (4 tabs) | home, restaurantes, mercados, produto, carrinho, checkout, tracking, histórico, avaliação | Glovo, Uber Eats, iFood |
| F4 Estafeta Delivery | `DriverHomeScreen` | home/mapa, oferta, compra em loja, talão, entrega, ganhos | Uber Driver, Glovo courier |
| F5 Marcações/Reservas/Limpeza/Favores | tiles do home cliente + hubs parceiro | wizard limpeza, availability reservas, appointments, errand form | Fresha/Booksy, TheFork, Helpling |
| F6 Parceiro + Admin | `PartnerEntryScreen` / rotas `/admin` | dashboard, produtos, horários, ganhos; 82 ecrãs admin | iFood parceiro, painéis internos |

Caminho de clique de cada ecrã: secção "Árvore de alcançabilidade" do inventário (BFS caminho mais curto).

## Matriz por área (preenchida ao fechar cada área)

### F1 — MOTORISTA/TVDE (fechada 2026-08-17)

Comparação: Uber Driver / Bolt Driver / 99. Veredito geral: área FORTE — a arquitetura espelha o servidor
(store 100% RPC + realtime com reload ao religar canal + poll de segurança 10s + refetch no foreground).

| Tela | Estado | Achados / Correções |
|---|---|---|
| `TvdeDriverHomeScreen` | 🟢 | Mapa full-screen c/ seta bearing, ganhos do dia, avaliação média, relógio online, toggle Online espelha servidor (heartbeat+GPS+ping driver_locations), gate pending/rejected c/ refresh no resume, ofertas delivery como overlay. 🟡 sem zona de calor/demanda (Uber/99 têm) → proposta P2 |
| `TvdeOfferScreen` | 🟢 corrigida | **✔ CORRIGIDO: mini-mapa recolha→destino** (liteMode, marcadores verde/laranja, linha tracejada, fit bounds) — era o gap nº1 vs Uber/Bolt/99; **✔ cartão agora rola em ecrãs baixos** (Expanded+SingleChildScrollView; Aceitar/Recusar sempre visíveis). Já tinha: líquido em destaque, timer server-side c/ expiração local, badge pagamento, aviso pacote, distância até recolha |
| `TvdeRideActiveScreen` | 🟢 | Nível Uber: câmara heading-up estilo Waze c/ pausa por gesto, rota real grossa + ETA, navegação externa (Maps/Waze), paradas c/ espera grátis e countdown server-side, no-show c/ janela configurável, cartão passageiro + chat c/ badge + ligar, lembrete de cobrança (fonte única TvdeFareView), back-to-back banner. 🟡 menor: FAB mira fixo bottom:200 pode ficar sob a sheet expandida |
| `TvdeDriverRateScreen` | 🟢 | Ganho visível, 5 estrelas, comentário, "Agora não" |
| `TvdeDriverEarningsScreen` | 🟢 corrigida | **✔ CORRIGIDO: estado de erro + "Tentar novamente"** (antes, falha de rede mostrava "Ainda não tens corridas" — tela a assumir). Dia/semana + histórico c/ breakdown Cobrado/Bora. 🟡 usa consulta direta a tvde_rides; migrar p/ RPC unificada QUANDO a RPC for corrigida (ver 🔴 abaixo) |
| `TvdePayBadge` / `TvdeRoundtripDriverNotice` | 🟢 | Fonte única (TvdeFareView + paid_cents do vale); copy PT-PT separa "o que ganhas" de "o que cobras" |
| `_GateScreen` (pending/rejected) | 🟢 | Espelha approval_status; refresh automático no resume |

**🔴 BUG REAL (fora do perímetro — BD, dinheiro exibido):** a RPC `driver_earnings_summary()` (BD viva, não está no repo)
filtra corridas TVDE por `status='concluida'`, mas o estado terminal real é `'finalizada'` (12 em prod, 0 'concluida')
→ **a parte TVDE dos ganhos unificados soma sempre ZERO**. Além disso a linha TVDE usa `final_fare_cents` (bruto)
enquanto as telas mostram `driver_earn_cents` (líquido) — gémeos desalinhados. SQL pronto (secção Propostas).

### F2 — CLIENTE TVDE (fechada 2026-08-17)

Comparação: Uber / Bolt / 99. Veredito: área MUITO FORTE pós-merge da produção — todas as lições do
1º dia real estão no código (espelho do servidor ao abrir + no resume, "Pagar de novo" para sheet
abandonada, `ride_already_terminal` tratado como sucesso, retry honesto cash vs online).

| Tela | Estado | Achados / Correções |
|---|---|---|
| `TvdeRequestRideScreen` | 🟢 corrigida | **✔ CORRIGIDO: tempo estimado (~min) na estimativa** (rota real já trazia a duração; padrão Uber/Bolt). Já tinha: mapa c/ pin arrastável + autocomplete, estimativa por rota real c/ retry, cobertura do plano em preview (grátis/excesso/extra c/ fim-de-semana), payment-first (corrida estacionada até servidor confirmar), vale-volta, folha de pagamento c/ teclado tratado |
| `TvdeRideTrackingScreen` | 🟢 | Pós-merge: refetch no abrir + foreground (lifecycle observer), estados terminais tiram a tela sozinha (`_TerminalView`), "Pagar de novo" quando sheet cartão abandonada, cancel c/ preview de taxa (grátis na janela / total depois) e `ride_already_terminal`→sucesso, cartão do motorista completo (foto+carro+matrícula+rating+ligar+chat c/ badge), paradas pagas inline (cartão/MB Way), animação suave do carro, heading-up Waze |
| `TvdeStore` | 🟢 | 100% RPC/EF; `refreshActiveRide` sem filtro de status; `confirmRidePayment` server-side é a única verdade; `retryRide` recusa online (nunca inventa método); defesas contra linha-de-NULLs |
| `TvdeRateScreen` | 🟢 | FareView fonte única (pacote/plano/dinheiro no copy) |
| `TvdeRidesHistoryScreen` | 🟢 | 🟡 menor: sem distinção loading/erro/vazio (flash de "Ainda não tens corridas" durante o load) |
| `TvdePlansScreen` | 🟢 | Fix F5 já presente (retry de preço 8s, botão desativado até preço real); aviso Seg-Sex; MB Way + cartão |
| `TvdeRideMbwayWaitingDialog` | 🟢 | 300s corrida / 120s parada+pacote; distingue "não pagou" de "sem rede"; não-dispensável |
| `TvdeChatScreen` (partilhado) | 🟢 | Badge não-lidas, mark-read, ligar, bolhas limpas |
| `TvdeFareView` | 🟢 | Fonte única cliente+motorista; regra do pacote (final=só paradas) documentada e testável |

**Superado no mapa do Córtex:** `TvdeUnlockScreen` já não existe — o tile é gated por `users.tvde_access`
(pedido via RPC `tvde_request_access`); atualizar mapa-de-fluxos-cliente §8 no F7.

### F3 — CLIENTE DELIVERY
_(pendente)_

### F4 — ESTAFETA DELIVERY
_(pendente)_

### F5 — MARCAÇÕES + RESERVAS + LIMPEZA + FAVORES
_(pendente)_

### F6 — PARCEIRO + ADMIN
_(pendente)_

### F-OLHO — automação de visão
_(pendente)_

## Propostas grandes (fora do perímetro — para Claude.ai/Danilo)

### P1 (F1) — Corrigir a RPC `driver_earnings_summary` (BD viva) — ⚠️ ISTO MEXE EM NÚMEROS DE DINHEIRO EXIBIDOS. Está tudo pronto — confirma que aplico (ou a Claude.ai aplica por MCP).
Bug: filtra TVDE por `status='concluida'` (estado que NÃO existe; o real é `'finalizada'`) → ganhos TVDE
unificados sempre 0. Decisão incluída: alinhar a linha TVDE ao LÍQUIDO (`driver_earn_cents`), a mesma
semântica das telas do motorista (hoje a RPC usa o bruto `final_fare_cents`, contradizendo o ecrã).
```sql
-- Em driver_earnings_summary(), trocar o ramo TVDE:
    SELECT r.updated_at, 'tvde',
           COALESCE(r.origin_label,'Corrida') || ' → ' || COALESCE(r.dest_label,''),
           COALESCE(r.driver_earn_cents, 0),   -- antes: COALESCE(r.final_fare_cents, r.est_fare_cents, 0)
           0
    FROM tvde_rides r
    WHERE r.driver_id = v_uid AND r.status = 'finalizada'   -- antes: 'concluida'
      AND r.updated_at > now() - interval '7 days'
```
Depois de aplicada: ligar `TvdeDriverEarningsScreen` e `driver_earnings_screen` à RPC (follow-up Flutter, eu faço).
Nota: se preferires manter o BRUTO na linha TVDE (racional: em dinheiro o motorista recolhe o bruto e o acerto
semanal fecha a taxa), aplica só a correção do status — o bug real é o status.

### P2 (F1) — Zona de calor/demanda no mapa do motorista (paridade Uber Driver/99)
Requer agregação backend (ex.: RPC `tvde_demand_cells(bbox)` sobre pedidos dos últimos 30-60 min, células ~500 m,
só contagens — sem dados pessoais) + heatmap/círculos no `TvdeDriverHomeScreen`. Esforço: ~1 dia (RPC + UI + RLS).
Valor: motoristas posicionam-se onde há procura; nº1 dos pedidos de paridade que faltam no mapa.

## Digest Hermes (8 linhas — preenchido no F7)
_(pendente)_
