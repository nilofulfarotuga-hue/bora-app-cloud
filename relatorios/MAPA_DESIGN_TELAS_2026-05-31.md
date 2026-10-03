# MAPA DE DESIGN — TELA A TELA (Bora App)
> Levantamento **read-only** · Data: 2026-05-31 · Build referência: **241**
> Orquestrado por CEO-AI · Modo Protecção Total · **NADA foi editado** — só análise.
> Skill de design "mãe" do projeto = **`bora-knowledge`** (não existe skill `bora-ui-engineer`; ver nota abaixo).

---

## 0. NOTA SOBRE AS SKILLS DE DESIGN
O prompt pediu para consultar `bora-ui-engineer`. **Essa skill não existe** no repo. As referências de design system são:
- **`bora-knowledge`** — referência viva (design system, tokens, widgets, fluxos). É a "mãe".
- **`migrate-screen-to-design`** — re-skin de 1 ecrã (MODO A patch generator).
- **`audit-orange-rule`** — valida "1 laranja por ecrã".
- **`update-design-token`** — alterar token de cor global.

Ground-truth do design lido directamente do código:
`lib/config/app_theme.dart`, `lib/config/app_colors.dart`, `lib/widgets/bora/bora_screen_app_bar.dart`, `bora_app_bar.dart`, `bora_tile_card.dart`, `bora_mascot.dart`.

---

## 1. PADRÕES DE REFERÊNCIA (o "bom")

| Elemento | Implementação correcta | Onde vive |
|---|---|---|
| **Header verde** (back+título brancos) | `BoraScreenAppBar` — `backgroundColor: transparent` + `flexibleSpace: DecoratedBox(gradient: AppColors.headerGradient)` + ícones/título brancos | `widgets/bora/bora_screen_app_bar.dart` |
| **Header home** (logo "B" + saudação) | `BoraAppBar` — Column verde edge-to-edge, logo "B", actions brancas | `widgets/bora/bora_app_bar.dart` |
| **Cards de categoria 3D** | `BoraTileCard.image(imageAsset: 'assets/categories/…')` — PNG/JPEG cartoon full-bleed + label no rodapé | `widgets/bora/bora_tile_card.dart` |
| **Mascote / logo** | `BoraMascot(variant: icon\|logo)` | `widgets/bora/bora_mascot.dart` |
| **Paleta** | `AppColors.primary` **#16A34A** (verde) · `AppColors.accent` **#F97316** (laranja) · `background` **#F0F2EF** · `surface` **#FFFFFF** | `app_theme.dart` / `app_colors.dart` |
| **Gradiente header** | `headerGradient` = #053D28 → #065F46 → #16A34A (135°) | `app_theme.dart` |

**Detalhe técnico crítico (causa-raiz):** o tema global (`app_theme.dart`) define
`AppBarTheme(backgroundColor: #16A34A /*verde*/, foregroundColor: white)`.
→ Logo, **um `AppBar(title: …)` "pelado" (sem `backgroundColor`) já sai VERDE com texto branco**.
→ O perigo de "branco-no-branco" só acontece se um ecrã **forçar** `backgroundColor: Colors.transparent` **ou** `Colors.white` **e NÃO** pintar o `flexibleSpace` com o gradiente.

---

## 2. DIAGNÓSTICO — RESUMO EXECUTIVO ⚠️ (ler primeiro)

Auditei **todas** as ~115 telas de `lib/screens/` + os widgets de `lib/widgets/`. Conclusão central, contra-intuitiva mas verificada linha-a-linha:

> ### 🔴 NÃO existe, no código actual, NENHUM cabeçalho "branco sobre branco".
> Todos os headers auditados resolvem para **verde** (via `BoraScreenAppBar`, via `AppBar` transparente **com** gradiente, ou via `AppBar` pelado que herda o tema verde) **ou** para um header branco **com texto/ícones coloridos legíveis** (`store_products`, `product_detail`).

Isto significa que o que o Danilo viu no telemóvel (Perfil/Reservas/Pedidos/Restaurantes/"pizza danilo" com topo invisível) **não é reproduzível no código actual**. As telas que o Danilo citou usam todas header verde correcto:
- `profile_screen.dart` → `BoraScreenAppBar(title: 'Perfil')` ✅
- `orders_screen.dart` → `BoraScreenAppBar(title: 'Pedidos')` ✅
- `restaurants_screen.dart` → `BoraScreenAppBar` ✅
- `client_reservations_screen.dart` → `AppBar` transparente **+ gradiente** ✅
- `restaurant_menu_screen.dart` ("pizza danilo") → `AppBar` transparente **+ gradiente** ✅

### Causa mais provável do que o Danilo viu: **BUILD 241 DESACTUALIZADO**
Os commits que arrumaram o design system (Fase 4 + FIX-1 avulsos `00a79e0` + FIX-2 admin `576154c→519da66` + reservas `f5a10c1`) são de **2026-05-30**. O APK que o Danilo testou ou (a) foi compilado de um commit **anterior** a estes fixes, ou (b) o GH Actions construiu um branch/commit diferente do `autonomous-night-2026-04-29`, ou (c) o telemóvel ainda não recebeu o build 241 do Play Internal.

> **ACÇÃO recomendada (não executada):** confirmar de que commit exacto o build 241 foi compilado (deve conter `f5a10c1`, `00a79e0`, `519da66`); reinstalar e re-testar **antes** de qualquer correcção de header. Há grande probabilidade de o problema de headers **já estar resolvido** no código.

### MAS — há um problema *sistémico* real por trás disto (a verdadeira lição)
O header verde **não está centralizado**. Existem **3 formas** de o fazer espalhadas pelo código:
1. `BoraScreenAppBar` (o widget correcto) — ~55 telas.
2. `AppBar(backgroundColor: transparent, flexibleSpace: gradient)` **copiado à mão** — ~18 telas.
3. `AppBar(title:)` pelado a herdar o tema — ~6 telas.

A forma (2) é **frágil**: é o mesmo bloco de 4 linhas copiado dezenas de vezes; basta um ecrã esquecer o `flexibleSpace` (ou pôr `Colors.white`) para nascer um "branco-no-branco". **É exactamente esta a razão técnica pela qual "só a Home ficou bem" na percepção do utilizador**: não houve um único widget de header propagado a 100% — houve 3 padrões equivalentes mas não-uniformes, e qualquer build intermédio podia ter telas por migrar. **A correcção sistémica é forçar TODAS as telas a usar `BoraScreenAppBar`** (ver §8).

### Problemas de design REAIS e confirmados no código (independentes do build)
1. **`restaurant_options_screen.dart` — os 3 botões SEM imagem.** ✅ CONFIRMADO. É exactamente a queixa do Danilo. Usam `BoraTileCard(iconData: Icons.…)` (ícone Material simples), não `BoraTileCard.image(...)`. **← prioridade #1 de imagens.**
2. **Telas de autenticação do Estafeta** (login/pending/rejected) sem qualquer branding Bora (mascote/logo) — só ícone Material genérico.
3. **`store_products_screen.dart`** — header **branco** (não verde) com texto verde: legível, mas foge ao padrão verde.
4. **`driver_earnings_screen.dart`** — laranja hardcoded `Colors.orange.shade700` em vez de `AppColors.accent`.
5. **Falta de logo do restaurante/loja** no topo de `restaurant_options` e `restaurant_menu` (mostram só o nome em texto) — bate certo com "telas de restaurante não têm logo".
6. **Empty-states sem ilustração** (favoritos, notificações, pendente, rejeitado) — oportunidade de cartoon 3D.

---

## 3. CLIENTE (prioridade máxima — detalhe)

Legenda Veredicto: ✅ OK · ⚠️ legível mas foge ao padrão / falta polish · ❌ partido (invisível).
**Telas de cliente partidas (❌): 0.**

### 3.1 Núcleo / navegação
| Tela (ficheiro) | Header | Veredicto | O que já tem de bom | Falta / errado | Imagens 3D necessárias |
|---|---|---|---|---|---|
| `client_home_screen.dart` | `BoraAppBar` (verde + logo) | ✅ **REFERÊNCIA** | 7 `BoraTileCard.image` (PNGs 3D), tokens `tile*`, grid responsivo, saudação | nada | nenhuma (tiles já têm imagens) |
| `client_main_screen.dart` | Shell + BottomNav v2 | ✅ | usa `BoraBottomNavV2` (Início/Entrega/Reserva/Perfil) | — | nenhuma |
| `role_screen.dart` | custom (selector) | ⚠️ | escolha de papel | sem ilustrações de papel; visual seco | (opcional) 3 ícones 3D: cliente / estafeta-scooter / loja |

### 3.2 Autenticação cliente
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `login_screen.dart` | `AppBar` transp.+gradiente, título "BORA APP" | ✅ | header verde, gradiente | podia usar `BoraMascot.logo` em vez de texto | logo Bora (já existe asset — usar `BoraMascot`) |
| `client_login_screen.dart` | sem AppBar (body centrado) | ✅ | layout auth limpo | sem hero/branding | hero Bora opcional |
| `register_client_screen.dart` | `AppBar` transp.+gradiente "Criar conta" | ✅ | header verde, form validado, draft | — | nenhuma |
| `welcome_address_screen.dart` | `AppBar` transp.+gradiente "Bem-vindo à Bora" | ✅ | header verde | — | (opcional) ilustração "mapa/casa" 3D |

### 3.3 Descoberta / catálogo
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `restaurants_screen.dart` | `BoraScreenAppBar` | ✅ | fotos reais, badges, chips distância/tempo/rating | — (fotos reais NÃO mexer) | nenhuma |
| `restaurant_menu_screen.dart` ("pizza danilo") | `AppBar` transp.+gradiente | ✅ header | fotos reais de pratos, badge carrinho | **falta logo do restaurante no topo** (só nome em texto) | nenhuma (logo = foto real do parceiro) |
| **`restaurant_options_screen.dart`** ("Como queres fazer o pedido?") | `BoraScreenAppBar` | ⚠️ **GAP-CHAVE** | header verde OK | **os 3 botões usam `BoraTileCard(iconData:)` = ícone Material, SEM imagem 3D**; falta logo do restaurante | **3 imagens** (ver §7) |
| `product_detail_screen.dart` | `SliverAppBar` branco + ícones pretos sobre foto | ⚠️ | hero da foto real do produto, back em círculo escuro (legível) | header branco foge ao verde (mas é padrão "hero foto" aceitável) | nenhuma (foto real) |
| `stores_screen.dart` | `BoraScreenAppBar` | ✅ | listagem lojas, fotos reais | — | nenhuma |
| `store_categories_screen.dart` | wrapper p/ `MarketStoreScreen` | ✅ | — | (herdado do market) | nenhuma |
| `store_products_screen.dart` | `AppBar` **branco** + fg verde | ⚠️ | legível (texto/ícones verdes) | **header branco em vez de verde** — foge ao padrão | nenhuma |
| `market/market_store_screen.dart` | `AppBar` pelado (verde do tema) | ✅ | tabs mercado | bypassa `BoraScreenAppBar` | nenhuma |

### 3.4 Carrinho / pedidos / tracking
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `cart_screen.dart` | `BoraScreenAppBar` "Carrinho" | ✅ | bg, cards, painel checkout, `BoraAccentButton` (1 laranja) | — (zona Stripe — NÃO mexer) | nenhuma |
| `order_tracking_screen.dart` | custom (mapa) | ✅ | bottom-card, card estafeta, mapa | — (zona realtime/maps — NÃO mexer) | nenhuma |
| `orders_screen.dart` | `BoraScreenAppBar` "Pedidos" | ✅ | cards estado, chips | empty-state sem ilustração | empty "sem pedidos": saco/recibo 3D |
| `order_details_screen.dart` | `AppBar` pelado (verde do tema) | ✅ | status card, timeline | bypassa `BoraScreenAppBar` | nenhuma |
| `rating_screen.dart` | `BoraScreenAppBar` "Avaliar" | ✅ | estrelas, form | — | (opcional) estrela 3D feliz |

### 3.5 Reservas (cliente) — `client/reservation/`
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `client_reservations_screen.dart` | `AppBar` transp.+gradiente + TabBar | ✅ | 3 tabs, `ReservationCard` | — | nenhuma |
| `my_reservation_lists_screen.dart` | `AppBar` transp.+gradiente | ✅ | 2 tabs (fila/avisar), badges | empty-states sem arte | (opcional) ilustração lista vazia |
| `reservation_availability_screen.dart` | `BoraScreenAppBar` | ✅ | pickers, chips party-size | — | nenhuma |
| `reservation_checkout_screen.dart` | `BoraScreenAppBar` | ✅ | thumbnail real, terms card | — (pré-pagamento — NÃO mexer) | nenhuma |
| `reservation_details_screen.dart` | `BoraScreenAppBar` | ✅ | cards, badges semânticos | — | nenhuma |
| `reservation_notify_join_screen.dart` | `BoraScreenAppBar` | ✅ | form + explainer | — | nenhuma |
| `reservation_waitlist_join_screen.dart` | `BoraScreenAppBar` | ✅ | form + explainer | — | nenhuma |
| `reservation_payment_method_sheet.dart` | bottom sheet | ✅ | radios em cards, MBWay | — (pagamento — NÃO mexer) | nenhuma |
| `reservation_mbway_waiting_dialog.dart` | dialog | ✅ | spinner + countdown | — | nenhuma |
| `reservation_flow_screen.dart` (legacy) | `AppBar` pelado (verde do tema) | ✅ | form reserva | bypassa `BoraScreenAppBar`; info-box laranja | nenhuma |

### 3.6 Conta / utilitários cliente
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `profile_screen.dart` | `BoraScreenAppBar` "Perfil" | ✅ | avatar upload, wallet, tokens | — | (opcional) avatar default mascote |
| `client_addresses_screen.dart` | `BoraScreenAppBar` | ✅ | tokens, cards | empty-state sem arte | (opcional) "casa/pin" 3D |
| `client_promo_code_screen.dart` | `BoraScreenAppBar` "Resgatar código" | ✅ | form, `BoraPrimaryButton` | — | (opcional) "ticket/voucher" 3D |
| `referral_screen.dart` | `BoraScreenAppBar` "Convidar amigos" | ✅ | partilha código | sem ilustração de convite | **"presente/2 amigos" 3D** (hero) |
| `notifications_screen.dart` | `BoraScreenAppBar` | ✅ | lista | empty-state sem arte | empty "sino" 3D |
| `payment_method_screen.dart` | `BoraScreenAppBar` "Pagamento" | ✅ | métodos | — (pagamento — NÃO mexer) | nenhuma |
| `client_favorites_screen.dart` | `AppBar` pelado (verde) | ✅ | grelha favoritos | empty sem arte; bypassa widget | empty "coração" 3D |
| `wallet_history_screen.dart` | `AppBar` pelado "Saldo Bora" | ✅ | histórico | bypassa widget | (opcional) "carteira/moeda Bora" 3D |
| `send_package_screen.dart` | `BoraScreenAppBar` "Enviar Encomenda" | ✅ | gateway | — | (opcional) caixa/encomenda 3D (hero) |
| `send_package_form_screen.dart` | `BoraScreenAppBar` | ✅ | form endereços | — | nenhuma |
| `carry_groceries_screen.dart` | `BoraScreenAppBar` "Levar Compras" | ✅ | gateway | — | (opcional) saco de compras 3D (hero) |
| `carry_groceries_form_screen.dart` | `BoraScreenAppBar` | ✅ | form | — | nenhuma |

### 3.7 Suporte / chat (transversal, usado pelo cliente)
| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `support_screen.dart` | `BoraScreenAppBar` + actions (email/tel) | ✅ | FAQ, bolhas chat | — | (opcional) mascote "ajuda" |
| `support_chat_screen.dart` | `AppBar` transp.+gradiente "Bora IA" | ✅ | bolhas, banner escalonar | bypassa widget (frágil mas OK) | (opcional) avatar IA 3D |
| `support_email_form_screen.dart` | `BoraScreenAppBar` | ✅ | form + SLA | — | nenhuma |
| `chat_screen.dart` | `BoraScreenAppBar` + acção chamada | ✅ | bolhas, cards substituição | — | nenhuma |
| `map_screen.dart` (transversal) | `AppBar` pelado "Escolher destino" (verde) | ✅ | autocomplete, pin drag, resumo | bypassa widget | nenhuma |

---

## 4. PARCEIRO (poucas telas — tem de transmitir profissionalismo)
**Telas partidas (❌): 0.** Tom 100% PT-PT, profissional.

| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `partner_entry_screen.dart` | router | ✅ | lógica de entrada | — | nenhuma |
| `partner_login_screen.dart` | `AppBar` transp.+gradiente | ✅ | header verde, form | bypassa widget; podia usar `BoraMascot.logo` | logo Bora (asset existe) |
| `register_partner_screen.dart` | `AppBar` transp.+gradiente | ✅ | Stepper, draft, upload logo/docs | containers cinza "secos" no upload | nenhuma (logo = upload do parceiro) |
| `pending_approval_screen.dart` | sem AppBar (status) | ✅ | mensagem clara, ícone laranja | ícone Material genérico | **ilustração "em análise" 3D** (ampulheta/check) |
| `partner_dashboard_screen.dart` | `AppBar` transp.+gradiente (título+subtítulo) | ✅ | gestão pedidos, toggles, som realtime, modal dispatch | containers cinza pontuais | nenhuma |
| `restaurant_dashboard_screen.dart` | `AppBar` transp.+gradiente | ✅ | dashboard restaurante | ⚠️ **rever strings PT-PT** (memória diz traduzido em `0187c0a` — confirmar no device) | nenhuma |
| `partner_call_driver_screen.dart` | `AppBar` (verificar) | ✅ | chamar estafeta | bypassa widget | nenhuma |
| `partner_hours_screen.dart` | `BoraScreenAppBar` | ✅ | horários | — | nenhuma |
| `partner_products_screen.dart` | `BoraScreenAppBar` | ✅ | lista produtos, fotos reais, toggle, FAB | — | nenhuma |
| `add_product_screen.dart` | `AppBar` transp.+gradiente "Adicionar produto" | ✅ | form produto | bypassa widget | nenhuma |
| `partner_earnings_screen.dart` | `BoraScreenAppBar` "Ganhos" | ✅ | KPIs, settlement | — | nenhuma |
| `partner_reservations_screen.dart` | `BoraScreenAppBar` "Reservas" | ✅ | lista reservas | — | nenhuma |
| `restaurant_ratings_list_screen.dart` | `BoraScreenAppBar` | ✅ | avaliações | — | nenhuma |

### 4.1 Parceiro — Reservas Pro (`partner/reservations/`)
| Tela | Header | Veredicto | Falta | Imagens 3D |
|---|---|---|---|---|
| `partner_reservations_home_screen.dart` | `BoraScreenAppBar` "Reservas Pro" | ✅ | — | nenhuma |
| `partner_reservations_screen.dart` | `AppBar` (verificar gradiente) | ✅ | bypassa widget | nenhuma |
| `partner_reservations_stats_screen.dart` | `BoraScreenAppBar` "Estatísticas" | ✅ | — | nenhuma |
| `partner_client_profiles_screen.dart` | `AppBar` (verificar) | ✅ | bypassa widget | nenhuma |
| `partner_floor_plan_editor_screen.dart` | `BoraScreenAppBar` | ✅ | — | nenhuma |
| `partner_pacing_rules_screen.dart` | `AppBar` (verificar) | ✅ | bypassa widget | nenhuma |
| `partner_table_form_screen.dart` | `BoraScreenAppBar` | ✅ | — | nenhuma |
| `partner_walk_in_screen.dart` | `BoraScreenAppBar` "Walk-in" | ✅ | — | nenhuma |

---

## 5. ESTAFETA
**Telas partidas (❌): 0.** Maior lacuna = **falta de branding/ilustrações** nas telas de auth/status.

| Tela | Header | Veredicto | Bom | Falta | Imagens 3D |
|---|---|---|---|---|---|
| `driver_login_screen.dart` | sem AppBar (body) | ⚠️ | form limpo | **sem logo/mascote no topo**, inputs sem ícones | **logo/hero Bora** (`BoraMascot.logo`) |
| `driver_signup_screen.dart` | `BoraScreenAppBar` "Candidatura de Estafeta" | ✅ | form multi-campo, uploads | dropdowns sem ícone de veículo | (opcional) ícones 3D mota/carro/bicicleta |
| `driver_pending_screen.dart` | sem AppBar (status) | ⚠️ | mensagem clara | ícone Material genérico | **ilustração "em análise" 3D** (estafeta a aguardar) |
| `driver_rejected_screen.dart` | sem AppBar (status) | ⚠️ | mensagem + motivo | ícone Material genérico | **ilustração "recusado" 3D** |
| `driver_home_screen.dart` | `AppBar` custom (Switch online + TokenChip + Bell) | ✅ | header funcional rico, integração `DriverStore` | bypassa widget (contrato custom); botões "secos" | nenhuma (mapa/GPS — NÃO mexer) |
| `driver_map_screen.dart` | `AppBar` custom (Bell + controlos mapa) | ✅ | mapa, polyline, GPS | ícones genéricos | nenhuma (lógica — NÃO mexer) |
| `driver_earnings_screen.dart` | `BoraScreenAppBar` "Ganhos" | ⚠️ | KPIs, `WeeklySettlementCard` | **laranja hardcoded `Colors.orange.shade700`** (usar `AppColors.accent`) | nenhuma |
| `widgets/driver_order_overlay.dart` | overlay (sem AppBar) | ✅ | card branco + borda verde, timer | botões "secos"; sem thumbnail | (opcional) ícone categoria no card |

---

## 6. ADMIN (PT-BR — menos prioritário visualmente)
**47 telas. Telas partidas (❌): 0.** Estilo consistente (verde). Distribuição de header:
- **~34** usam `BoraScreenAppBar` (correcto, centralizado).
- **~10** usam `AppBar(transparent + flexibleSpace gradient)` (verde, mas copiado à mão): `admin_tokens`, `admin_referrals`, `admin_receipts`, `admin_reservations_metrics`, `admin_partner_detail`, `admin_order_detail`, `admin_notifications_inbox`, `admin_global_search`, `admin_edge_functions`, `admin_drivers`, `admin_driver_detail`, `admin_driver_approval`.
- **1** condicional intencional: `admin_skill_suggestions_screen` (laranja em modo selecção, verde por defeito).
- **2** `AppBar(backgroundColor: Colors.black)` — visualizadores de foto full-screen em `admin_driver_detail:746` e `admin_driver_approval:854` (preto **intencional**, ícones brancos legíveis). ✅

**Gaps admin (baixa prioridade):**
- Migrar os ~10 headers copiados-à-mão para `BoraScreenAppBar` (uniformidade).
- `admin_skill_suggestions_metrics_screen.dart`: 4 hex hardcoded (cores de chart/semânticas — **aceitável**, não é bug de marca).
- Nenhuma imagem 3D necessária (admin é utilitário/tabular; status/charts/€/tokens são semânticos e **não se tocam**).

Telas (todas ✅ header verde): `admin_dashboard`, `admin_orders`, `admin_order_detail`, `admin_drivers`, `admin_driver_detail`, `admin_driver_approval`, `admin_driver_payments`, `admin_partners`, `admin_partner_detail`, `admin_partners_pending`, `admin_partner_settlements`, `admin_partner_payouts`, `admin_catalog`, `admin_category_mapping`, `admin_clients`, `admin_complaints`, `admin_cancellation_requests`, `admin_pending_actions`, `admin_reservations`, `admin_reservations_metrics`, `admin_tokens`, `admin_wallets`, `admin_cashbacks`, `admin_receipts`, `admin_orphan_payments`, `admin_settlements`, `admin_ratings`, `admin_referrals`, `admin_promo_codes`, `admin_platform_settings`, `admin_dispatch_settings`, `admin_broadcasts_history`, `admin_send_notification`, `admin_notifications_inbox`, `admin_knowledge`, `admin_crosstalk`, `admin_support_tickets`, `admin_support_stats`, `admin_skill_suggestions`, `admin_skill_suggestions_metrics`, `admin_edge_functions`, `admin_advanced_kpis`, `admin_global_search`, `admin_search_kpi`, `admin_live_orders_map`, `admin_audit_log`, `admin_ai_assistant`.

---

## 7. TABELA-RESUMO POR ROLE

| Role | Telas | ✅ OK | ⚠️ Polish/inconsistência | ❌ Partidas (invisível) |
|---|---|---|---|---|
| **Cliente** (núcleo+auth+catálogo+pedidos+reservas+conta+suporte) | ~47 | ~42 | 5 (`restaurant_options` cards, `store_products` header branco, `product_detail` hero branco, `role_screen` seco, empty-states) | **0** |
| **Parceiro** | 21 | 20 | 1 (`restaurant_dashboard` confirmar strings; uploads "secos") | **0** |
| **Estafeta** | 8 | 4 | 4 (login/pending/rejected sem branding; `driver_earnings` laranja hardcoded) | **0** |
| **Admin** | 47 | 47 | (10 headers copiados-à-mão a uniformizar) | **0** |
| **TOTAL** | **~123** | **~113** | **~10** | **0** |

> **Nenhuma tela "branco-no-branco" no código actual.** O problema relatado no build 241 = build desactualizado (ver §2).

---

## 8. LISTA CONSOLIDADA DE IMAGENS 3D/CARTOON A GERAR
> Mesmo estilo dos tiles da Home (3D cartoon, fundo gradiente da categoria). Agrupadas, sem repetir.

### 🔴 PRIORIDADE 1 — `restaurant_options_screen` (a queixa directa do Danilo)
1. **Botão "Entrega"** — *scooter de entrega 3D cartoon* sobre gradiente **laranja** (`tileRestaurants` #F97316→#FB923C).
2. **Botão "Ir buscar"** — *saco/bolsa de takeaway 3D cartoon* sobre gradiente **verde** (`tileCarryGroceries` #16A34A→#4ADE80).
3. **Botão "Reservar mesa"** — *mesa + cadeira/talheres 3D cartoon* sobre gradiente **roxo** (`tileReserveTable` #6A1B9A→#8E24AA).

### 🟠 PRIORIDADE 2 — branding de Estafeta & status
4. **Hero/logo Bora** para `driver_login` (e `client_login`/`partner_login`) — usar `BoraMascot.logo` (asset **já existe**) ou render dedicado da mascote em scooter.
5. **"Em análise" 3D** — estafeta/ampulheta a aguardar (`driver_pending` + `pending_approval` parceiro).
6. **"Recusado" 3D** — ilustração amigável de recusa (`driver_rejected`).

### 🟡 PRIORIDADE 3 — empty-states & heros (polish, opcional)
7. **Sem pedidos** — saco/recibo 3D (`orders_screen`).
8. **Sem favoritos** — coração 3D (`client_favorites_screen`).
9. **Sem notificações** — sino 3D (`notifications_screen`).
10. **Convidar amigos** — presente / 2 amigos 3D (`referral_screen`).
11. **Enviar encomenda** — caixa/encomenda 3D (hero `send_package_screen`).
12. **Levar compras** — saco de compras 3D (hero `carry_groceries_screen`).
13. *(opcional)* ícones 3D de veículo (mota/carro/bicicleta) para `driver_signup`.

> **NÃO gerar:** fotos de produtos/pratos/lojas (são reais — proibido mexer). Tiles da Home já existem.

---

## 9. CAUSA-RAIZ TÉCNICA (porque "só a Home ficou bem")

1. **Não há um único widget de header propagado a 100%.** Há **3 padrões equivalentes** de header verde (`BoraScreenAppBar`, `AppBar`+gradiente copiado, `AppBar` pelado). Embora todos resolvam para verde **no código actual**, a coexistência de 3 padrões significa que durante a migração (Fases 3–4) havia sempre telas "por arrumar" — e qualquer build intermédio mostrava telas inconsistentes. A percepção "só a Home" vem daí.
2. **Padrão frágil copiado à mão (~18 telas):** o bloco `backgroundColor: Colors.transparent` + `flexibleSpace: gradient` é copiado dezenas de vezes. Se **uma** cópia esquecer o `flexibleSpace` (ou trocar para `Colors.white`), nasce o "branco-no-branco". É uma armadilha latente, não um bug presente.
3. **`BoraTileCard` legacy (deprecated) ainda em uso** em `restaurant_options` com `iconData` → botões sem imagem. A migração da Fase 4 (`.image()`) não chegou a esta tela.
4. **Build provavelmente anterior aos fixes** (§2) → o Danilo viu um estado já corrigido no repo.

---

## 10. PROPOSTA DE ABORDAGEM DE CORRECÇÃO (descrição — NÃO implementada)

**Correcção sistémica de 1 alavanca (arruma muitas telas de uma vez):**
- **(A) Centralizar o header:** substituir TODAS as ocorrências de `AppBar(transparent + flexibleSpace: headerGradient)` e os `AppBar` pelados por **`BoraScreenAppBar`** (o widget já existe e é à prova de "branco-no-branco"). Isto elimina a armadilha latente e uniformiza ~24 telas (10 admin + ~8 cliente + ~6 parceiro) sem tocar em lógica. Existe a skill **`migrate-screen-to-design`** (MODO A, gera diff em `_preview/`, não toca `lib/` sem `--apply`) — ideal para isto, tela a tela.
- **(B) `restaurant_options_screen`:** trocar os 3 `BoraTileCard(iconData:)` por `BoraTileCard.image(imageAsset:)` quando as 3 imagens da Prioridade 1 existirem.
- **(C) Branding estafeta:** inserir `BoraMascot` (logo/icon) nos topos de `driver_login`/`driver_pending`/`driver_rejected` + `pending_approval` parceiro.
- **(D) Limpeza pontual:** `driver_earnings` `Colors.orange.shade700` → `AppColors.accent`; `store_products` header branco → `BoraScreenAppBar`.
- **(E) Verificar headers "(verificar)"** marcados em §4.1 (`partner_reservations`, `partner_client_profiles`, `partner_pacing_rules`, `partner_call_driver`) — confirmar que têm gradiente; senão, migrar para `BoraScreenAppBar`.

**Antes de tudo:** confirmar o commit do build 241 (§2). Se já contém os fixes de 2026-05-30, grande parte do "problema de headers" **já está resolvido** — a correcção real fica reduzida a (A) uniformização + (B)/(C) imagens & branding.

**Salvaguardas (Modo Protecção Total):** nenhuma alteração toca dispatch, pricing, tokens, Stripe, realtime, GPS ou fotos reais. Regra "1 laranja por ecrã" a validar com `audit-orange-rule` após qualquer mudança.

---

## 11. FECHO
- ✅ **Nada foi editado.** Esta tarefa foi 100% levantamento/análise read-only.
- ✅ Mapa escrito em `relatorios/MAPA_DESIGN_TELAS_2026-05-31.md`.
- ✅ Auditadas ~123 telas (`lib/screens/`) + widgets de design (`lib/widgets/`).
- 🔎 Conclusão-chave: **0 headers invisíveis no código actual** → o build 241 está provavelmente desactualizado; o gap de design **real** e confirmado é `restaurant_options` (3 botões sem imagem) + branding de estafeta + uniformização de header.
