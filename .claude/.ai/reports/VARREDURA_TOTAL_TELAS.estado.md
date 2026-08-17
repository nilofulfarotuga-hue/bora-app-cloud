# VARREDURA TOTAL TELA-A-TELA — ESTADO (retomável)

> Missão iniciada 2026-08-16 (noite) · Motor: Fable 5 · Branch: `autonomous-night/fase2-cortex-tasks`
> Regra: após cada área → MARCO + commit + push + gravação no Córtex (adendo do Danilo).
> Retoma: continuar do último MARCO. Nada se refaz.

## Plano de áreas
- [x] **F0 — INVENTÁRIO** (árvore de navegação dos 4 papéis)
- [x] **F1 — MOTORISTA/TVDE** (prioridade nº1)
- [x] **F2 — CLIENTE TVDE**
- [x] **F3 — CLIENTE DELIVERY**
- [ ] **F4 — ESTAFETA DELIVERY**
- [ ] **F5 — MARCAÇÕES + RESERVAS + LIMPEZA + FAVORES**
- [ ] **F6 — PARCEIRO + ADMIN**
- [ ] **F-OLHO — golden tests + juiz de visão + Firebase Test Lab**
- [ ] **F7 — FECHO** (relatório + Córtex + platform_settings + digest Hermes)

## MARCOS

### MARCO: F0 FEITO — 2026-08-17
Prova: `VARREDURA_TOTAL_TELAS.inventario.md` gerado por script (414 ficheiros dart, 196 classes `*Screen`,
179 alcançáveis por BFS a partir das raízes; 18 candidatas a órfãs para confirmar por área).
Raízes por papel (main.dart `_RootNavigator`, linhas ~675-699):
- sem papel → `RoleScreen`
- client → `ClientMainScreen` (IndexedStack 4 tabs) / `ClientLoginScreen`
- driver `carPassengers` → `TvdeDriverHomeScreen` · outros → `DriverHomeScreen` · draft → `DriverSignupScreen` / `DriverLoginScreen`
- partner → `PartnerEntryScreen`
- admin → via rotas `/admin` + `profile_screen.dart` (2 emails hardcoded)
Base de conhecimento: 5 mapas de fluxos do Córtex lidos (mapa-de-fluxos*, 2026-07-10) — servem de
inventário funcional; correções a registar no fecho (F7): sinal €3 marcações EXTINTO, TVDE ida-e-volta
preço dinâmico (fim €8 fixo), carteira única de cartão, tokens TVDE 2/3 caminhos live.
Contagem por área: driver 28 · cliente 39 · parceiro 29 · partilhados 50 · admin 82 ficheiros.

### MARCO: F1 FEITO — 2026-08-17
Prova: 7 telas TVDE motorista lidas integralmente (home 968L, store 452L, oferta 295L, ativa 1459L,
avaliação 113L, ganhos 242L + 2 widgets). 2 correções aplicadas: mini-mapa na oferta (liteMode,
gap nº1 vs Uber/Bolt/99) + cartão scrollable; estado de erro nos ganhos. `flutter analyze` 0 erros.
🔴 achado real: RPC `driver_earnings_summary` (BD viva) filtra status='concluida' inexistente →
TVDE soma 0 nos ganhos unificados. SQL de fix pronto no relatório (P1); aplicação = Claude.ai/`vai`.
Proposta P2: heatmap de procura. Matriz completa no relatório §F1.

### EVENTO DE RUMO — merge da produção (2026-08-17, durante F2)
A branch da missão estava DIVERGENTE da produção `autonomous-night-2026-04-29` (fixes do 1º dia real
16/08 — espelho servidor 9d205d0, cêntimo, webhook v34, reconciliador — não estavam cá). Merge feito:
c86c5fa (3 conflitos resolvidos a favor da produção; EF tvde-payment ficou idêntica à produção).
CI só dispara na `autonomous-night-2026-04-29` → pushes da varredura NÃO geram builds.
⚠️ `supabase/functions/tvde-plan-payment/index.ts` tinha alterações de DINHEIRO pendentes de "vai":
NÃO committadas — guardadas em `git stash` ("tvde-plan-payment v10 tokens PENDENTE-VAI") + backup em
scratchpad. No fecho: merge varredura→produção arrasta commits tvde-payment v9 → decisão Danilo.

### MARCO: F2 FEITO — 2026-08-17
Prova: 9 ficheiros do cliente TVDE lidos (request 1810L, tracking 1620L pós-merge, store 1125L,
rate/history/plans/dialogs/chat/fare_view). 1 correção: ETA (~min) na estimativa (commit c2506e4).
Pós-merge confirmado no código: espelho no abrir+resume, Pagar de novo, ride_already_terminal→sucesso.
Superado p/ F7: TvdeUnlockScreen extinto (tile gated por users.tvde_access). Matriz no relatório §F2.

### MARCO: F3 FEITO — 2026-08-17
Prova: funil completo lido (main/home/restaurantes/menu/ficha/lojas/mercado-tabs/grelha/carrinho/
pagamento/tracking/pedidos/detalhe/avaliacao ~11k linhas). 5 correcoes: pesquisa na lista de
restaurantes; B1 no fallback legacy do menu; T1 no botao com opcoes; taxa de entrega dinamica no
mercado (era €2,50 fixo); avaliacao real do estafeta no tracking (era '4.9' fixo). analyze 0 erros.
Propostas P3-P5. Superado p/ Cortex: reorder por loja JA existe; TVDE aberto a todos.

## Notas de retoma
- Inventário completo (ficheiro→classes→arestas + BFS caminhos de clique): `.claude/.ai/reports/VARREDURA_TOTAL_TELAS.inventario.md`
- Relatório principal (matriz 🔴🟡🟢 por área, crescente): `.claude/.ai/reports/VARREDURA_TOTAL_TELAS.md`
- Órfãs a confirmar: LoginScreen, MapScreen, RestaurantDashboardScreen, SendPackageScreen, WelcomeAddressScreen, CleaningChatScreen, DriverRatingsListScreen, RestaurantRatingsListScreen, ClientFavoritesScreen, NotificationsScreen (várias podem ser alcançadas por rota nomeada/dinâmica — verificar na área respetiva).
- Perímetro: UI/estados/navegação/textos SIM; dinheiro/dispatch/EFs protegidas = PROPOSTA no relatório.
- Córtex: gravar marco por área (zona verde). Página da missão: `missao-varredura-telas` (criar no 1º marco se não existir).
