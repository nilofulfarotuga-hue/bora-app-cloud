# VARREDURA TOTAL TELA-A-TELA — ESTADO (retomável)

> Missão iniciada 2026-08-16 (noite) · Motor: Fable 5 · Branch: `autonomous-night/fase2-cortex-tasks`
> Regra: após cada área → MARCO + commit + push + gravação no Córtex (adendo do Danilo).
> Retoma: continuar do último MARCO. Nada se refaz.

## Plano de áreas
- [x] **F0 — INVENTÁRIO** (árvore de navegação dos 4 papéis)
- [ ] **F1 — MOTORISTA/TVDE** (prioridade nº1)
- [ ] **F2 — CLIENTE TVDE**
- [ ] **F3 — CLIENTE DELIVERY**
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

## Notas de retoma
- Inventário completo (ficheiro→classes→arestas + BFS caminhos de clique): `.claude/.ai/reports/VARREDURA_TOTAL_TELAS.inventario.md`
- Relatório principal (matriz 🔴🟡🟢 por área, crescente): `.claude/.ai/reports/VARREDURA_TOTAL_TELAS.md`
- Órfãs a confirmar: LoginScreen, MapScreen, RestaurantDashboardScreen, SendPackageScreen, WelcomeAddressScreen, CleaningChatScreen, DriverRatingsListScreen, RestaurantRatingsListScreen, ClientFavoritesScreen, NotificationsScreen (várias podem ser alcançadas por rota nomeada/dinâmica — verificar na área respetiva).
- Perímetro: UI/estados/navegação/textos SIM; dinheiro/dispatch/EFs protegidas = PROPOSTA no relatório.
- Córtex: gravar marco por área (zona verde). Página da missão: `missao-varredura-telas` (criar no 1º marco se não existir).
