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

### F3 — CLIENTE DELIVERY (fechada 2026-08-17)

Comparação: Glovo / Uber Eats / iFood. Veredito: funil ao nível das referências (menu estilo Glovo com
tabs sticky, mercado com 3 tabs, checkout payment-first blindado). 5 correções aplicadas.

| Tela | Estado | Achados / Correções |
|---|---|---|
| `ClientMainScreen` | 🟢 | 4 tabs IndexedStack; auto-push tracking c/ dedup; terminais excluídos |
| `ClientHomeScreen` | 🟢 | 11 tiles, guard endereço, avaliação pós-entrega anti-spam (2 skips), picker endereços (guardados/GPS/autocomplete). TVDE aberto a todos (superado: "categoria escondida" do mapa Córtex) |
| `RestaurantsScreen` | 🟢 corrigida | **✔ CORRIGIDO: campo de pesquisa** — a barra da home encaminhava para cá e NÃO havia pesquisa (agora filtra por nome + estado "sem resultados" próprio). Já tinha: abertos-primeiro, ETA, taxa, rating, favoritos, dialog carrinho-ativo |
| `RestaurantMenuScreen` | 🟢 corrigida | Nível Glovo: header loja, tabs sticky sincronizadas, carrosséis, pesquisa RPC fuzzy, roteio opções-obrigatórias. **✔ CORRIGIDO: fallback legacy mostrava preço PURO mas cobrava com markup** (B1: exibido=cobrado) |
| `ProductDetailScreen` | 🟢 corrigida | Grupos de opções min/max, alergénios UE, variantes, quantidade. **✔ CORRIGIDO: botão c/ opções somava extras SEM markup** (divergia do cobrado em não-parceiro c/ opções — regra T1) |
| `StoresScreen` | 🟢 | Pesquisa+ordenar, secções, horário gate, carrinho-ativo |
| `MarketStoreScreen` + tabs | 🟢 corrigida | 3 tabs Glovo (Loja/Categorias/Pedir de novo — reorder JÁ implementado). **✔ CORRIGIDO: taxa de entrega '€2,50' hardcoded na stats row + rodapé** → agora `PricingService.estimatedDeliveryFee` (lei: dinheiro exibido vem do servidor/fonte única). 🟡 ETA 2,5min/km hardcode c/ TODO (proposta) |
| `StoreProductsScreen` | 🟢 | Pesquisa RPC full-screen, chips, grelha 2col + variantes stepper, ids E2E. 🟡 `_SkeletonLoader` definido sem uso (dead code, não removido) |
| `CartScreen` | 🟢 | Takeaway, curbside, apartamento, gorjeta, saldo Bora, dívida, coming-soon, CTA pinado. 🟡 subtítulo entrega c/ '€2.50'/4km literais (menor) |
| `PaymentMethodScreen` | 🟢 | **Checklist da missão completo**: cartão (payment-first + guardados + 3DS), MB Way (bail-out cancela órfã), dinheiro (gate €40+dívida), wallet, **slider de tokens c/ marca do teto físico**; breakdown de favores próprio; diagnóstico F4 |
| `OrderTrackingScreen` | 🟢 corrigida | **✔ CORRIGIDO: avaliação do estafeta era '4.9' FIXO** → agora avg_rating real (esconde se não houver — a tela nunca inventa). Já tinha: cancel E1-E4 c/ cortesia ao vivo + escolha reembolso (cartão/carteira 80/20) + "já cancelado=sucesso", breakdown completo, cartão estafeta c/ veículo+matrícula, banners takeaway, textos por service_type |
| `OrdersScreen` | 🟢 | Pull-to-refresh, anti-wipe loader, chip ajustes carteira, "Pedir de novo" p/ favores |
| `OrderDetailsScreen` | 🟢 | Verificado por amostragem (grep): sem hardcodes de dinheiro; 16 displays de valores do servidor |
| `RatingScreen` | 🟢 | RPC idempotente server-side, tags por estrelas, gorjeta escondida em cash, opção privada |

**Propostas F3** (ver secção Propostas): P3 atalho "pedir de novo" na HOME (existe por loja no mercado;
falta transversal) · P4 pesquisa global da home (hoje só restaurantes) · P5 ETA do mercado por settings.

### F4 — ESTAFETA DELIVERY (fechada 2026-08-17)

Comparação: Uber Driver / Glovo courier. Área madura, com TODOS os fixes do 1º dia real presentes
(recuperação da foto pós-morte do processo, preços base na caixa, tokens honestos 50/40).
4 correções aplicadas.

| Tela | Estado | Achados / Correções |
|---|---|---|
| `DriverHomeScreen` (3086L) | 🟢 corrigida | Idle map estilo Uber, gate mínimo de permissões (nunca bloqueia), heartbeat resiliente, ofertas FIFO c/ dedup e guard oferta-vencida (H6), som gerido, safety-net ban/suspensão. **✔ CORRIGIDO: banner "Apartment delivery requested — +€1 bonus" em INGLÊS** → PT-PT; **✔ botão "Teste" c/ ícone de bug → "Mudar modo"** (2 sítios, paridade c/ cliente). 🟡 `stackedEarnings` replicado em Dart (comentado como espelho da BR — proposta P7); 🟡 '+€3.00 +50 tokens' literal no popup |
| `DriverMapScreen` (3622L) | 🟢 corrigida | Waze-cam, reroute off-route, multi-stop c/ botão por pedido, banners RECEBER €X / PAGAR AO ESTABELECIMENTO, lista de compras c/ fotos+zoom+adicionar produto+sacos cap 5, **caixa = preços BASE** (F2), talão só-câmara c/ **recuperação pós-crash** (F4) + upload via EF c/ erro PT. **✔ CORRIGIDO: no stacking, o diálogo do código validava contra o focusOrder — código certo do OUTRO pedido era recusado** (agora valida contra o pedido da ação) |
| `DriverEarningsScreen` | 🟢 corrigida | **JÁ usa a RPC unificada `driver_earnings_summary`** (F6 de 16/08 — o pedido da missão está feito; falta o fix da RPC, ver P1 que fica MAIS urgente). **✔ CORRIGIDO: compra de prioridade consumia tokens mas o UPDATE de `priority_until` usava `.eq('id')`** — conta id≠user_id pagava e não recebia (agora tolera as duas chaves, como o SELECT F5.4). Conversão tokens→€ atómica server-side c/ cap semanal |
| `driver_order_action_helper` | 🟢 | Resolve ação por estado (52L) |
| Fluxo de favores | 🔴 só-ler | `errand_execution_sheet` é zona protegida — não tocado |

**🔴 P0 CONHECIDO (continua aberto):** PIN de entrega validado client-side (BUG #15 do mapa anti-regressão)
— cash até salta o código (BUG 33 deliberado). Exige RPC server-side + mudança no order_store 🔴 → P6.

### F5 — MARCAÇÕES + RESERVAS + LIMPEZA + FAVORES (fechada 2026-08-17)

Comparação: Fresha/Booksy (marcações), TheFork (reservas NOVA), Helpling (limpeza). Método: scanner de
red-flags (EN/€-literal/espera-sem-refresh) em 25 ficheiros (12,4k linhas) + leitura dirigida dos ecrãs
de espera. 1 correção transversal aplicada.

| Tela/Fluxo | Estado | Achados / Correções |
|---|---|---|
| `CleaningTrackingScreen` | 🟢 | Realtime no CleaningStore (trackBooking) + hook global de resume (main.dart) + "já cancelada=sucesso" (16/08); preview de taxa por janelas do servidor |
| `ReservationDetailsScreen` + listas | 🟢 corrigida | Realtime via `.stream()` (subscribeMyReservations) JÁ existia; **✔ CORRIGIDO: faltava o refetch no foreground** — ReservationStore.fetchMyReservations() adicionado ao hook global de resume |
| `MyAppointmentsScreen` (marcações) | 🟢 corrigida | Realtime via `.stream()` (subscribeMyAppointments) + pull-to-refresh JÁ existiam; **✔ mesmo fix: ServicesStore.fetchMyAppointments() no hook global de resume**. FIM DO SINAL €3 refletido no copy (preço=valor cobrado) |
| Diálogos MB Way (marcação/reserva) | 🟢 | Poll 3s/120s próprio, não-dispensáveis (mesma família do TVDE) |
| `ReservationCheckoutScreen` / `BookingFlowScreen` | 🟢 | Verificados por scanner + histórico (consolidação F5 16/08 no merge: reservas NOVA únicas, legacy arquivada); pagamento padrão canónico |
| `CleaningWizardScreen` / bookings / payment_flow | 🟢 | Preços do wizard vêm das RPCs; fixes f3b/f5 (webhook held, limpeza presa com guarda) no merge |
| Lado limpadora (`cleaner_*`) | 🟢 | CleanerStore com realtime; RefreshIndicator; candidatura própria |
| `ErrandFormScreen` (favores) | 🟢 | Verificado por scanner (sem flags reais); tela-branca e footer já corrigidos em missões passadas; execution sheet é zona 🔴 (não tocada) |

Nota de método: nesta área a leitura foi dirigida (scanner + ecrãs de espera por inteiro), não integral
tela-a-tela como F1-F4 — as 3 verticais receberam consolidação pesada há 24h (f3a/f3b/f5 no merge).


### F6 — PARCEIRO + ADMIN
_(pendente)_

### F-OLHO — automação de visão
_(pendente)_

## Propostas grandes (fora do perímetro — para Claude.ai/Danilo)

### P6 (F4) — PIN de entrega server-side (P0 conhecido, BUG #15)
RPC nova `driver_confirm_delivery(p_order_id, p_code)` que valida o código NO SERVIDOR e só então
transita para delivered; `order_store` 🔴 passa a chamá-la no lugar da transição direta. Cash hoje
salta o código (BUG 33) — decidir se mantém. Esforço: ~2-3h + teste 2-devices. Zona 🔴 → Danilo/Claude.ai.

### P7 (F4) — Oferta empilhada: ganho calculado no servidor
`stackedEarnings` é replicado em Dart no popup de oferta (espelho manual da BR §6.4 — comentário admite).
O dispatch podia gravar `driver_offer_earnings_cents` na própria oferta. Esforço: ~2h (dispatch 🔴 = propor).

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

### P3 (F3) — Atalho "Pedir de novo" na HOME do cliente (Glovo/iFood têm)
O reorder JÁ existe por loja (`MarketReorderTab` + `ReorderService`) e por favor (OrdersScreen).
Falta uma fila horizontal na home ("Os teus habituais") reutilizando o ReorderService. Esforço: ~2-3h UI.

### P4 (F3) — Pesquisa global na home (hoje o campo encaminha só para Restaurantes)
Pesquisar lojas+produtos de todas as lojas (a RPC `search_products` já aceita restaurant_id — precisaria
de variante global ou fan-out). Esforço: ~1/2 dia (RPC + ecrã de resultados).

### P5 (F3) — ETA do mercado por platform_settings (hoje 2,5 min/km hardcode c/ TODO no código)
Chave nova `market_eta_min_per_km` + leitura no `MarketStoreTab._etaText`. Esforço: ~1h.

### P2 (F1) — Zona de calor/demanda no mapa do motorista (paridade Uber Driver/99)
Requer agregação backend (ex.: RPC `tvde_demand_cells(bbox)` sobre pedidos dos últimos 30-60 min, células ~500 m,
só contagens — sem dados pessoais) + heatmap/círculos no `TvdeDriverHomeScreen`. Esforço: ~1 dia (RPC + UI + RLS).
Valor: motoristas posicionam-se onde há procura; nº1 dos pedidos de paridade que faltam no mapa.

## Digest Hermes (8 linhas — preenchido no F7)
_(pendente)_
