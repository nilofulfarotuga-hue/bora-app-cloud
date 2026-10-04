# cliente-app — relatório (04/10/2026)

Ramo: `agente-cliente-app` (1 commit `2adfca36`, base `origin/autonomous-night-2026-04-29` @ `4e474973`).
CI: ramo `analise-cliente-app` = mesmo código + o workflow estrito "Analise rapida" (só nesse ramo).
- Run 37229556577 (mesma árvore, antes do squash): VERDE — analyze sem erros, avisos 7 (= base 7, nenhum novo), 949 testes passam (base 941 + 8 novos).
- Run final (commit a92468c4 = 2adfca36 + workflow): **37229807254 VERDE** — analyze sem erros, 7 avisos (= base), 949 testes passam.

## FEITO

1. **Suporte** — `lib/screens/support_screen.dart:24-47`. Duas respostas erradas corrigidas:
   - Cancelamento: grátis sem estafeta; com estafeta atribuído continua possível COM taxa (valor aparece antes de confirmar); depois de recolhido não se cancela pela app. (Bate com produção: `cancel_fee_before_dispatch_cents=0`, `cancel_fee_after_accept_cents=250`.)
   - "Como contactar o estafeta": não há botão de chamada no seguimento — é a conversa (ChatBubbleButton). Texto corrigido.
   - "Na tela … clica" → "No ecrã … carrega". EN acrescentado.
   - `support_chat_screen.dart`: `if (!mounted) return;` antes dos 3 `setState` depois do `await` (sucesso, FunctionException, catch) + no `_showHandoff` atrasado.
2. **Calendário das reservas** — `client/reservation/reservation_details_screen.dart:107`: o "em breve" foi trocado por `_addToCalendar()` que abre o "novo evento" do Google Calendar já preenchido (hora da reserva, 1h30, nome do restaurante). Funciona Android/iPhone/web.
3. **"(BR §…)" visíveis** — tirados de `client_home_screen.dart` ("Escolhe um restaurante para reservar mesa.") e `send_package_form_screen.dart` (foto obrigatória). Chaves EN/JSON atualizadas. O de `cart_screen.dart:391` é do checkout → PEDIDO abaixo.
4. **Favoritos** — `lib/stores/favorite_store.dart`: lojas guardadas por **id** (`store_<id>`), sincronizadas com a conta (`client_favorites` + RPC `client_toggle_favorite`, à prova de "alternar"), migração dos antigos `restaurant_<nome>` → id. ♥ na lista de restaurantes, no cabeçalho do restaurante e no cabeçalho da loja (market) passam a usar o id. `client_favorites_screen.dart` reescrito (carregar/erro/vazio, abre a loja por `DeepLinkStoreScreen`, tira favorito). Nova entrada "Lojas favoritas" no perfil do cliente (`profile_screen.dart`, secção do cliente).
5. **Listas vazias a carregar/falhar** — `RestaurantStore` ganhou `restaurantsLoading/LoadFailed/LoadedOnce` (`restaurant_store.dart` ~342). Novo `lib/widgets/bora/lista_estado.dart` (A carregar / Erro + "Tentar outra vez"). Aplicado em `restaurants_screen.dart`, `stores_screen.dart` (e ambos carregam a lista se ninguém a carregou) e `notifications_screen.dart` (`listOrThrow` novo no serviço). Tocar numa notificação marca lida e, se `related_id` for um pedido, abre o `OrderDetailsScreen` (procura no OrderStore, senão lê `orders` — RLS do cliente).
6. **PT-PT** — endereço→morada em moradas, casa, envio de encomendas, compras, detalhe do pedido, perfil e campo de morada; "Informe"→"Indica"; "Aguardando o estafeta…"→"À espera que o estafeta…"; "vocês recebem"→"cada um recebe"; "produtos cadastrados"→"Esta loja ainda não tem produtos."; títulos que não tinham `.tr` passaram a ter. Erros crus: reservas (`client_reservations_screen`, `reservation_details_screen`) usam `mensagemDeFalhaDeAcao`; foto do favor com frase simples. 70 traduções EN novas em `strings_en.dart` (bloco "cliente-app" no topo do mapa) + `tool/l10n/traducoes/pt-en-10-cliente-app.json`. Varredura local igual à do teste: 0 frases sem EN.
7. **mounted** — support_chat (3 sítios + handoff), errand_form (`_pickRequestPhoto`: depois da folha e do picker), notificações (todos os awaits), reservas.
8. **Pedir de novo / Marcar de novo** — `orders_screen.dart`: botão "Pedir de novo" em pedidos de restaurante/loja já fechados (entregue/cancelado/rejeitado) → `ReorderService.applyTo` (preço de hoje, aviso de preços mudados) → carrinho; se a loja já não existe, aviso. "Marcar de novo": barbearia (`my_appointments_screen` → `BookingFlowScreen(repeatOf:)`, serviço+profissional pré-escolhidos, entra no passo do dia, pagamento normal), limpeza (`cleaning_bookings_screen` → `CleaningWizardScreen(repeatOf:)` com serviço, morada, notas e profissional se disponível), lavagem (`carwash_service_screen` → `CarwashRequestScreen(repeatOf:)` com matrícula/carro/cor/telefone/notas).
9. **Reportar problema** — novo `lib/widgets/reportar_problema_pedido.dart` no detalhe do pedido entregue: motivos (faltou produto, produto errado, frio/danificado, nunca chegou, outro) + detalhes + foto opcional (upload `upload-order-photo`), trava de toque duplo + spinner, grava com `file_complaint` (categoria `order_issue`). O cliente vê as suas queixas desse pedido com o estado (Recebido / Em análise / Resolvido / Fechado) e a hora de Lisboa.
   - **Achado em produção:** `file_complaint` tinha perdido o EXECUTE para `authenticated` (só postgres/service_role) — ninguém conseguia usá-la — e aceitava qualquer pedido. **Migration `20261004194440_cliente_reportar_problema_file_complaint`** (aplicada + ficheiro no ramo): mesma assinatura, volta o GRANT a authenticated, e valida que o pedido é do cliente / do estafeta atribuído / da loja do parceiro.
   - Prova SQL (desfeita): `PROVA: order=4a3bb2ca-… res_ok=true queixas_visiveis_ao_cliente=1 status=open pedido_alheio=recusado: order_not_yours`.
10. **Partilhar seguimento** — novo `lib/widgets/partilhar_seguimento.dart` (texto: loja, código, estado e "Chegada prevista por volta das HH:MM" em hora de Lisboa, a partir do `OrderEtaService`) + botão no ecrã de seguimento (`order_tracking_screen.dart`, ao lado do ponto de estado; as mudanças da manhã ficaram intactas).
11. **RGPD antes das notificações** — `main.dart`: `ConsentStore.load()` passou para ANTES do arranque do Firebase/notificações. `ConsentStore.load()` sem resposta → `NotificationService.aguardarConsentimento()` (não pede permissão nem apaga tokens). `applyNotificationConsent(true)` depois da resposta arranca o `init()` (se o Firebase existir). Quem já respondeu: igual a antes.
12. **Cores** — azul Google `#1A73E8` (rota no seguimento → verde da marca; "substituído" → `AppColors.info`), bandeiras das lojas (azul/roxo/cinza → `primary`/`primaryDeep`/`textSecondary`), roxo da "Carteira" em pedidos → verdes da marca, carteira (roxo/rosa/laranja/azul → tokens), selo "Premium" → `AppColors.info`, listas de reserva, morada de entrega `#1C6EF2` → `AppColors.mapDropoff`. Rosa das Festas mantido (é a paleta oficial da categoria, `AppColors.tileFestas`). Fotos não mexidas.
13. **Loja em pausa** — `RestaurantModel.pausaAte` (lido de `restaurants.pausa_ate`, tolerante: coluna ainda NÃO existe em produção → null), `emPausa()`, `pausaVoltaAs` (Lisboa). `isOpenNow()` devolve falso em pausa → o carrinho já trava (`vendorFechada`) com o aviso "X está fechada temporariamente. Volta às HH:MM."; também nas Festas. Lista de restaurantes (selo do estado), lista de lojas (chip) e dentro da loja (novo `BannerPausaLoja` no restaurante e no market) mostram "Fechada temporariamente — volta às HH:MM". `copyWith` mantém o campo. Testes: `test/loja_em_pausa_test.dart` (pausa + favoritos por id/migração).

## NÃO FEITO
- "Endereço de entrega errado" (motivo de cancelamento em `order_tracking_screen`) ficou como está: é texto gravado no pedido e lido pelo painel.
- `map_screen.dart` não mexido: não tem chamadores (código morto).
- Formas "Escolha/Tente/Confirme" (formal, válido em PT-PT) em lavagem/palavra-passe ficaram — só se trocou o que a missão nomeou.

## PRECISA DE CONFIRMAÇÃO
Nada.

## PEDIDOS A OUTROS AGENTES
- PEDIDO A checkout: `lib/screens/cart_screen.dart:391` tirar " (BR §14.9)" de `'Sem taxa de entrega. Recebes aviso quando estiver pronto. (BR §14.9)'.tr` e a chave correspondente em `strings_en.dart`/`pt-en-05.json`.
- PEDIDO A parceiro: criar `restaurants.pausa_ate timestamptz` (a app do cliente já a lê como `pausa_ate`, ISO; null = sem pausa). Se lhe der outro nome/tipo, avisar.
- PEDIDO A admin-geral: no `admin_complaints_screen.dart` mostrar o corpo completo e, se tiver a linha "Foto: <url>", mostrar a foto (`PrivateBucketImage`, bucket `order-photos`); filtro por categoria `order_issue`.
- Conflito previsível no merge: `lib/l10n/strings_en.dart` (o meu bloco está no TOPO do mapa, para não colidir com o fim) e `lib/main.dart` (só mexi na ordem do consentimento, ~linha 577 e ~669).

## RISCOS
- RGPD: num aparelho novo, as notificações só ficam ativas depois de responder ao aviso (é o pedido). Estafeta que nunca responder ao aviso não recebe push — igual ao que já acontecia a quem recusava.
- `RestaurantStore.loadRestaurantsFromSupabase()` agora faz `notifyListeners()` no início (estado "a carregar").
- Favoritos: a sincronização com a conta é "melhor esforço" (sem rede fica só no aparelho até ao próximo toque).
- A foto da queixa vai no texto (a tabela `complaints` não tem coluna de foto); o painel precisa do pedido acima para a mostrar bonita.
