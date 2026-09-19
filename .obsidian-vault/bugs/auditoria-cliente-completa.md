# Auditoria Cliente — Completa (vs Uber Eats / Glovo / iFood)
> Data: 2026-04-24
> Âmbito: fluxo CLIENTE da Bora App (Flutter + Supabase)
> Método: leitura ficheiro-a-ficheiro de `lib/screens/`, `lib/stores/`, `lib/services/`, `lib/auth/`, `lib/widgets/`

---

## 🔴 BUGS CRÍTICOS

- **[BUG-CL-001] `registerClient()` síncrono ainda usado como fallback** — `lib/auth/auth_store.dart` (método `registerClient`).
  - Descrição: o método síncrono dispara `signUp` em `unawaited(...)` sem aguardar resposta; cria a conta local antes do Supabase confirmar.
  - Impacto: emails duplicados, conta órfã local que falha login real, perda de password. Já existe `registerClientAsync` correto, mas o síncrono **continua público** e qualquer chamada futura volta ao bug original.
  - Fix: marcar `@Deprecated` e fazer chamar internamente `registerClientAsync`, ou remover.

- **[BUG-CL-002] Rating não persiste — confirma BUG-018** — `lib/screens/rating_screen.dart` (`_submit()`).
  - Descrição: o submit faz `Supabase.instance.client.from('ratings').insert(...)` directamente em vez de passar por um `RatingService`. O ficheiro `lib/services/rating_service.dart` **não existe**. Não há agregação client→driver/partner para mostrar média no card do restaurante.
  - Impacto: ratings podem inserir mas não há leitura nem exibição; não fecha o ciclo de UX.
  - Fix: criar `RatingService`, expor `averageStars` e `count` em `RestaurantModel`, mostrar no `restaurants_screen` card.

- **[BUG-CL-003] "Esqueceu a palavra-passe" não está realmente implementado** — `lib/screens/client_login_screen.dart` botão `_forgotPassword`.
  - Descrição: o botão existe mas o handler chama `supabase.auth.resetPasswordForEmail` sem deeplink configurado para `redirectTo`. O utilizador recebe email mas o link abre web — a app Flutter não trata o callback.
  - Impacto: utilizador fica preso, não consegue recuperar conta. Crítico em produção.
  - Fix: configurar deeplink `bora://reset-password`, intent-filter Android, Universal Link iOS, e ecrã `ResetPasswordScreen`.

- **[BUG-CL-004] Validação de password fraca no registo** — `lib/screens/register_client_screen.dart`.
  - Descrição: validator só verifica que não está vazia. Aceita `"1"`, `"abc"`. Supabase Auth rejeita <6 chars mas a UX só falha depois do round-trip.
  - Impacto: friction no onboarding, mensagem de erro genérica em inglês ("Password should be at least 6 characters").
  - Fix: validator local mínimo 8 chars, indicador de força, regra contra senhas comuns.

- **[BUG-CL-005] `registerClientAsync` não verifica formato de telemóvel** — `lib/auth/auth_store.dart`.
  - Descrição: aceita qualquer string em `phone`. Sem prefixo +351, sem 9 dígitos PT.
  - Impacto: SMS de notificação falham; partner não consegue contactar; MBWay rejeita.
  - Fix: regex `^(\+351)?9[1236]\d{7}$` no validator do form e no store.

- **[BUG-CL-006] Cart persistido em SharedPreferences sobrevive logout** — `lib/stores/cart_store.dart` (`_loadCart`/`_saveCart` chave `bora_cart_v1`).
  - Descrição: `clearCart()` é chamado mas não há `await prefs.remove(_kPrefsKey)` no logout. Outro utilizador a usar o mesmo dispositivo vê itens do anterior.
  - Impacto: privacidade + bug funcional. Em loja partilhada (família, casal) é grave.
  - Fix: limpar prefs em `AuthStore.logout()`.

- **[BUG-CL-007] Endereço de entrega aceita string vazia em `finishOrder`** — `lib/stores/cart_store.dart`.
  - Descrição: campos `_dropoffStreet` arrancam em `""`. Não há guard no `finishOrder` que aborte se vazio. Há um `WARNING` debug em `configureSession` mas não bloqueia checkout. `hasValidPickupLocation` existe; equivalente no dropoff não está enforced.
  - Impacto: pedido criado sem morada → driver não sabe onde entregar.
  - Fix: validar `_deliveryLocation != null && _dropoffStreet.isNotEmpty` antes de criar pedido.

- **[BUG-CL-008] Falta exibir restaurante "Aberto/Fechado" e tempo médio nos cards** — `lib/screens/restaurants_screen.dart`.
  - Descrição: ordena por `isOpenNow()` mas o card do `BoraTileCard` não mostra ETA estimada ("~25 min"), preço de entrega, nem rating. A auditoria UX prévia já identificou; **continua não fixado**.
  - Impacto: cliente desiste se não vê tempo/avaliação. Uber/Glovo/iFood mostram sempre.
  - Fix: integrar `OrderEtaService` + `RatingService` no card.

- **[BUG-CL-009] Pesquisa do home não pesquisa nada** — `lib/screens/client_home_screen.dart` (`BoraSearchField`).
  - Descrição: `BoraSearchField` na home tem `onChanged` que apenas faz scroll/animação, não filtra restaurantes nem produtos. Toda a entrada do utilizador é descartada.
  - Impacto: feature aparente mas inexistente. Glovo/Uber pesquisam produtos transversalmente.
  - Fix: implementar pesquisa unificada em `RestaurantStore.search(query)` cruzando nomes de restaurantes + nomes de produtos via `PartnerProductStore`.

- **[BUG-CL-010] Polling MBWay sem timeout máximo claro / cancel handler** — `lib/screens/payment_method_screen.dart` (`_showMBWayWaitingDialog`).
  - Descrição: o dialog espera webhook actualizar estado. Sem informação se há timeout >2 min e sem botão "Cancelar e tentar outro método" durante a espera.
  - Impacto: utilizador fica preso em loading; pedido em `payment_status=pending` órfão se MBWay nunca for confirmado.
  - Fix: timer 90 s, botão cancelar, cancelar PaymentIntent server-side via Edge Function.

- **[BUG-CL-011] Stripe `processPayment` não trata 3DS / fallback de cartão** — `lib/services/payment_service.dart`.
  - Descrição: chama apenas `presentPaymentSheet()`. Em cartões com 3DS challenge fraco a Sheet trata, mas não há retry nem mensagem específica para "saldo insuficiente" vs "cartão inválido".
  - Impacto: utilizador não sabe porque falhou; SnackBar genérico "Pagamento por cartão indisponível".
  - Fix: parse `StripeException.error.code` (`card_declined`, `insufficient_funds`, `expired_card`) e i18n correspondente.

- **[BUG-CL-012] `delete-account` Edge Function consultada mas não validada localmente** — `lib/screens/profile_screen.dart` (`_confirmDeleteAccount`).
  - Descrição: sem retry, sem invalidate de sessão se Edge Function devolve sucesso parcial. O fluxo GDPR §20.2 requer apagar pedidos, ratings, mensagens; não há verificação client-side.
  - Impacto: conta "fantasma" — Auth user removido mas dados em `orders`/`ratings` mantidos.
  - Fix: edge function devolve `{deleted_records: {...}}` e UI valida.

---

## 🟡 BUGS MÉDIOS

- **[BUG-CL-013] `FavoriteStore` não distingue produto vs restaurante** — `lib/stores/favorite_store.dart`.
  - Único `Set<String> _ids`. Se um produto e um restaurante partilharem ID (UUID seguro mas não garantido em demo data) há colisão. Falta `toggleProduct`/`toggleRestaurant`. Não está integrado em ecrã algum (não vi `isFavorite()` em `restaurant_menu_screen.dart` consumido visualmente).

- **[BUG-CL-014] Banner promocional `BoraPromoBanner` é estático/hardcoded** — `lib/screens/client_home_screen.dart`.
  - Texto "Entregas rápidas e seguras" no código. Sem tabela `banners` no Supabase, sem rotação, sem deep-link configurável. Uber/iFood servem campanhas dinâmicas.

- **[BUG-CL-015] `ConsentStore` não enforce nada** — `lib/stores/consent_store.dart`.
  - Comentário próprio admite: "Technical enforcement of the opt-out (actually disabling FCM/Geolocator/analytics when rejected) is a separate task". Logo, **rejeitar não desactiva**. Risco GDPR concreto.

- **[BUG-CL-016] FCM token só guardado para drivers e partners** — `lib/services/notification_service.dart`.
  - Existe `saveTokenForDriver` e `saveTokenForPartner` mas **não** `saveTokenForClient`. O cliente nunca recebe push de "Pedido a caminho", "Driver chegou", "Avaliar pedido".
  - Fix: criar coluna `clients.fcm_token` (ou em `auth.users.user_metadata`) e função análoga.

- **[BUG-CL-017] `place_autocomplete_service` sem debounce** — `lib/services/place_autocomplete_service_io.dart`.
  - Faz HTTP request a cada keystroke. Cache só é hit se a string for igual à última. Bilha o quota Google e mostra resultados desordenados.
  - Fix: debounce 300 ms no widget consumidor.

- **[BUG-CL-018] `ChatStore.sendMessage` faz optimistic insert mas sem retry** — `lib/stores/chat_store.dart`.
  - Em offline a mensagem é removida silenciosamente. Sem fila offline, sem ícone "envio falhado, tocar para tentar de novo".

- **[BUG-CL-019] `OrderTrackingScreen` rebuilds excessivos pelo `_maybeOpenRating`** — `lib/screens/order_tracking_screen.dart`.
  - Chamado dentro de `build`. Embora `select` esteja scoped, `_maybeOpenRating` pode tentar abrir route 2× se rebuild antes de Navigator concluir.
  - Fix: guard com flag `_ratingShown`.

- **[BUG-CL-020] `orders_screen` recarrega na auth state listener mas não filtra past/current** — `lib/screens/orders_screen.dart`.
  - Lista única misturando entregues + activos. Uber/iFood separam tabs "Em curso" / "Histórico".

- **[BUG-CL-021] `support_screen` usa email/phone sem fallback** — `lib/screens/support_screen.dart`.
  - `_launchEmail`/`_launchPhone` via `url_launcher`; se device sem app email, falha silenciosa. Sem chat real-time com agente, FAQ é estático em código.

- **[BUG-CL-022] Cancelamento BUG-017 marcado como resolvido mas falta-lhe UI de "motivo"** — `lib/screens/order_tracking_screen.dart`.
  - Cliente cancela mas não escolhe motivo (mudei de ideias / demora / erro de morada). Concorrência exige razão para analytics + reembolso diferenciado.

- **[BUG-CL-023] `tipSelector` insere `_tipCents` mas tip não é cobrado depois do pagamento** — `lib/widgets/tip_selector.dart` (referenciado em `rating_screen.dart`).
  - Após o pagamento principal já estar fechado, adicionar tip implica novo PaymentIntent ou ajuste — não vi código a fazê-lo.

- **[BUG-CL-024] `restaurants_screen` falha graciosamente fechado mas não permite "marcar para lembrar quando abrir"** — UX gap (Uber/Glovo).

- **[BUG-CL-025] `cart_screen` não avisa quando muda de vendor** — `lib/stores/cart_store.dart` `configureSession` faz `_items.clear()` se mudar de partner mas no UI não há diálogo de confirmação.

- **[BUG-CL-026] `product_detail_screen` quantidade limitada apenas inferiormente (>=1) sem upper bound** — pode adicionar 999 ovos e o backend rejeitar tarde demais.

- **[BUG-CL-027] `reservation_flow_screen` é MVP — sem confirmação por email/SMS, sem cancelamento, sem lembrete** — `lib/screens/reservation_flow_screen.dart`.

- **[BUG-CL-028] `restaurant_store.loadProductsFromSupabase()` paginação 1000-em-1000 sem filtro por restaurante** — `lib/stores/restaurant_store.dart`.
  - Carrega TODOS os produtos de TODOS os restaurantes na app cliente. Em produção com 50 lojas × 200 produtos = 10 000 rows na boot. Lento + dados.
  - Fix: lazy-load por `restaurantId` quando o cliente abre o menu.

- **[BUG-CL-029] `client_home_screen._detectLocation` não pede permissão GPS — só usa se já concedida** — friction; deveria explicar valor (Uber pede explicitamente).

- **[BUG-CL-030] `BoraSearchField` não suporta voice search** — competitivo (Glovo tem).

---

## 🟢 BUGS BAIXOS

- **[BUG-CL-031] Mensagens em mistura PT/EN** — vários ecrãs ("Email inválido." vs Stripe "Pagamento por cartão indisponível").
- **[BUG-CL-032] Sem skeleton loaders** — listas piscam vazias antes de aparecer.
- **[BUG-CL-033] Sem haptic feedback ao adicionar ao carrinho** — Uber/iFood usam.
- **[BUG-CL-034] `profile_screen` carrega foto da Supabase Storage mas sem cache busting** — foto antiga aparece após upload.
- **[BUG-CL-035] `register_client_screen` não permite registo via Google/Apple Sign-In** — gap competitivo.
- **[BUG-CL-036] `client_login_screen` não detecta caps lock**.
- **[BUG-CL-037] Sem indicador "novo!" em produtos recentemente adicionados pelo partner**.
- **[BUG-CL-038] `order_details_screen` não permite contactar o partner directamente** (apenas o driver).
- **[BUG-CL-039] `BoraPromoBanner` não tem `Semantics` para acessibilidade** — leitor de ecrã não anuncia.
- **[BUG-CL-040] Sem dark mode forçado** — só usa `ThemeMode.system`; no Stripe Sheet acaba inconsistente.
- **[BUG-CL-041] `support_screen` FAQ é estático em código** — qualquer alteração obriga a nova release. Devia vir do Supabase.
- **[BUG-CL-042] `reorder_service` avisa preços alterados via list mas o caller (orders_screen) pode não mostrar a toast — verificar callsite**.

---

## 🔴 MELHORIAS CRÍTICAS (UX competitivo)

- **[MEL-CL-001] ETA dinâmica nos cards de restaurante** — Uber/Glovo/iFood mostram "20-30 min" em cada card. Bora não. Aproveitar `OrderEtaService` que já existe para o tracking e expor função `estimateForVendor(vendor, userLocation)`.

- **[MEL-CL-002] Rating médio + nº de reviews em cada card** — todos os concorrentes. Já temos modelo `RatingModel`; falta agregação SQL view + leitura.

- **[MEL-CL-003] Filtros e ordenação na lista de restaurantes** — Uber Eats: "Tempo de entrega", "Preço", "Avaliação", "Distância", "Tipo de cozinha". Bora ordena só por aberto + alfabético.

- **[MEL-CL-004] Tabs "Em curso" / "Histórico" em `orders_screen`** — separação básica de UX, todos os concorrentes têm.

- **[MEL-CL-005] Notificações push para o cliente (mudança de status)** — actualmente cliente apenas vê via realtime quando a app está aberta. Glovo/Uber notificam: "O teu pedido está a ser preparado", "Driver a caminho", "Driver chegou", "Avalia o teu pedido".

- **[MEL-CL-006] Login social (Google + Apple)** — Uber/Glovo/iFood têm. Reduz fricção drasticamente. Apple obrigatório para release iOS.

- **[MEL-CL-007] Reset password com deep-link** — actual fluxo está partido (BUG-CL-003).

- **[MEL-CL-008] "Voltar a pedir" promovido** — `ReorderService` existe mas não tem botão proeminente em `order_details_screen` nem secção "Os teus favoritos" na home. Uber Eats mostra em destaque.

- **[MEL-CL-009] Pesquisa unificada (produtos + restaurantes + categorias)** — Glovo é o referencial; Bora tem campo decorativo.

- **[MEL-CL-010] Tracking visual robusto com timeline** — actualmente `order_tracking_screen` mostra estado mas sem timeline visual ("Recebido → A preparar → A caminho → Entregue") com timestamps. Concorrência tem.

---

## 🟡 MELHORIAS MÉDIAS

- **[MEL-CL-011] Secção "Recentemente visitados" na home** (Uber/iFood).
- **[MEL-CL-012] Banner dinâmico configurável via admin/Supabase** (BUG-CL-014).
- **[MEL-CL-013] Promoções/cupões/códigos** — sistema de tokens existe; falta aplicar como "código promocional" no checkout.
- **[MEL-CL-014] Histórico de moradas** — ao escrever endereço sugerir os 3 últimos usados além de "Casa".
- **[MEL-CL-015] Multi-endereço guardado (Casa/Trabalho/Outros)** — `SessionStore` só tem `homeAddress`.
- **[MEL-CL-016] Notas para o driver** ("Tocar à campainha", "Deixar à porta") — campo livre antes do checkout.
- **[MEL-CL-017] Notas para o restaurante** ("Sem cebola", "Bem passado") — por item.
- **[MEL-CL-018] Indicador de delivery grátis dinâmico** ("Faltam €3 para delivery grátis").
- **[MEL-CL-019] Recuperação de carrinho abandonado** — push 1 h depois.
- **[MEL-CL-020] Suporte por chat em tempo real** (não só FAQ + email).
- **[MEL-CL-021] Categorias de cozinha visuais com emojis** (Pizza 🍕, Sushi 🍣) — Glovo style.
- **[MEL-CL-022] Recompensas/programa de fidelidade** — Uber Eats Pro, iFood VIP.
- **[MEL-CL-023] Partilhar pedido com amigos** (split bill) — Uber tem.
- **[MEL-CL-024] Pré-encomenda agendada** ("entregar às 20h00").
- **[MEL-CL-025] Estado offline gracioso** — cache de últimos restaurantes vistos.
- **[MEL-CL-026] Tutorial onboarding 3-passos no primeiro uso**.
- **[MEL-CL-027] Foto de prova de entrega** — driver tira foto, cliente vê em `order_details_screen`.

---

## 🟢 MELHORIAS BAIXAS

- Modo escuro completo coerente com Stripe Sheet.
- Voice search.
- Animações Lottie nas transições de status.
- Widget Home no Android (Glovo tem).
- Apple/Google Wallet integration além do PaymentSheet.
- Avaliação rápida com 1 toque (sem texto).
- Histórico de chat com driver mantido após entrega.
- Modo daltónico (status dot tem só cor).
- Convidar amigo (referral) — cupão para ambos.

---

## Pontuação vs concorrentes

| Eixo | Bora | Uber Eats | Glovo | iFood |
|---|---|---|---|---|
| Funcionalidade core (catálogo, carrinho, checkout, tracking) | 65/100 | 95 | 92 | 93 |
| Pagamentos (Stripe/MBWay/cash/tokens) | 75/100 | 95 | 90 | 95 |
| Fluxo de autenticação (login/registo/reset/social) | 40/100 | 95 | 95 | 95 |
| Push & notifications | 25/100 (cliente sem token FCM) | 95 | 90 | 95 |
| UX home (search, filtros, ETA, rating no card) | 30/100 | 95 | 95 | 92 |
| Histórico & reorder | 50/100 | 90 | 80 | 85 |
| Suporte e chat | 45/100 | 80 | 80 | 85 |
| Programa fidelidade / promoções | 20/100 | 85 | 80 | 90 |
| Acessibilidade & i18n | 30/100 | 80 | 75 | 80 |
| Estabilidade & código | 70/100 (pós-fixes BUG-012/13/14/16/17) | — | — | — |

- **TOTAL: 45/100** (vs Uber Eats ~92, Glovo ~88, iFood ~91).

Nota: o motor (modelos, stores, realtime, dispatch, pagamento server-trusted) é sólido. Os pontos fracos estão no **fim do funil** (autenticação completa, push ao cliente, UX competitiva no card e checkout, programa de fidelidade).

---

## Recomendação — top 5 a atacar primeiro

1. **Push notifications para o cliente** (BUG-CL-016 + MEL-CL-005) — sem isto a app é silenciosa. 1-2 dias.
2. **Reset password com deep-link** (BUG-CL-003 + MEL-CL-007) — bloqueador real em produção. 0.5 dia.
3. **ETA + rating + estado nos cards de restaurante** (BUG-CL-008 + MEL-CL-001 + MEL-CL-002) — primeira impressão. 1-2 dias.
4. **Pesquisa funcional unificada** (BUG-CL-009 + MEL-CL-009) — feature aparente que hoje é placebo. 1 dia.
5. **Login social Google/Apple** (MEL-CL-006) — Apple obrigatório para review da App Store. 1 dia.

Bónus rápido (<1 h cada): limpar carrinho no logout (BUG-CL-006), validar morada no checkout (BUG-CL-007), validador de password (BUG-CL-004), validador de telemóvel (BUG-CL-005).
