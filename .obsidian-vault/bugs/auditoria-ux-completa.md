# 🔍 AUDITORIA UX COMPLETA — BORA APP
> Comparação tela a tela com Uber Eats, iFood e Glovo  
> Data: 2026-04-24 · Gerado por CEO-AI  
> Base: leitura completa de lib/screens/ + lib/widgets/

---

## ÍNDICE

- [FLUXO DO CLIENTE](#fluxo-do-cliente)
- [FLUXO DO ESTAFETA](#fluxo-do-estafeta)
- [FLUXO DO PARCEIRO](#fluxo-do-parceiro)
- [RESUMO EXECUTIVO](#resumo-executivo)
- [TOP 10 CRÍTICOS](#top-10-críticos)

---

# FLUXO DO CLIENTE

---

## C1 · Selecção de papel / Onboarding

**Ficheiro:** `role_screen.dart`

### O que existe no Bora
- Ecrã de selecção de papel: Cliente / Estafeta / Parceiro
- 3 botões com ícones básicos
- Sem animações, sem texto explicativo por papel
- Sem onboarding tutorial
- Sem splash screen com branding

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Login social (Google, Apple, Facebook) | Uber, iFood, Glovo | 🔴 Crítico | Integrar `google_sign_in` + `sign_in_with_apple` via Supabase OAuth |
| Verificação por SMS / OTP | iFood, Glovo | 🔴 Crítico | Supabase Phone Auth ou Twilio |
| Onboarding animado (3-4 slides) | Uber, iFood, Glovo | 🟡 Importante | `PageView` com ilustrações + skip |
| Splash screen com logo | Todos | 🟡 Importante | `flutter_native_splash` |
| Recuperação de password na tela | Todos | 🔴 Crítico | Botão "Esqueceu a palavra-passe?" com Supabase resetPasswordForEmail |
| Opção "Continuar como convidado" | Uber | 🟢 Nice to have | Modo guest limitado |

---

## C2 · Registo de Cliente

**Ficheiro:** `register_client_screen.dart`

### O que existe no Bora
- Campos: nome, email, password, telefone
- Upload de foto de perfil (câmara ou galeria) — **BUG CONHECIDO: não salva**
- Validação básica de formulário
- Supabase signUp + criação de row em `clients`
- Aceitar termos (link)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Verificação de email (link de confirmação) | Todos | 🔴 Crítico | Ativar Supabase email confirm + ecrã "Confirma o teu email" |
| Verificação de telemóvel por SMS | iFood, Glovo | 🟡 Importante | Supabase Phone OTP |
| BUG: foto de perfil não guarda | — | 🔴 Crítico | Fix já em launch blockers — corrigir upload para `profiles` bucket + `user_metadata` |
| Registo passo-a-passo (step wizard) | Uber, iFood | 🟡 Importante | Dividir em 2 passos: dados pessoais → morada padrão |
| Endereço de entrega padrão no registo | iFood, Glovo | 🟡 Importante | Adicionar campo de morada ou pedir após login |
| Referral code / código de convite | Todos | 🟢 Nice to have | Campo opcional + lógica de créditos |

---

## C3 · Login de Cliente

**Ficheiro:** `client_login_screen.dart`

### O que existe no Bora
- Email + password
- Toggle mostrar/ocultar password
- Botão "Entrar"
- Link para registo

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| "Esqueceu a palavra-passe?" | Todos | 🔴 Crítico | `TextButton` → modal com email → `resetPasswordForEmail` |
| Login social (Google / Apple) | Uber, iFood, Glovo | 🔴 Crítico | Supabase OAuth providers |
| Login por telemóvel (OTP) | iFood, Glovo | 🟡 Importante | Tab switch: Email ↔ Telemóvel |
| Biometria (Face ID / Touch ID) | Uber | 🟡 Importante | `local_auth` package após primeiro login |
| Lembrar sessão / "Manter sessão iniciada" | Todos | 🟢 Nice to have | Já funciona via SharedPreferences, mas sem toggle visível |

---

## C4 · Ecrã Inicial do Cliente (Home)

**Ficheiro:** `client_home_screen.dart`

### O que existe no Bora
- Barra de endereço de entrega (autocomplete + GPS)
- Campo de pesquisa (`BoraSearchField`)
- Categorias: Restaurantes, Mercados, Carregar Compras, Enviar Pacote
- Lista de restaurantes (cards com foto, nome)
- Banner promocional (`BoraPromoBanner`)
- Detecção automática de localização (GPS / morada guardada)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Tempo estimado de entrega em cada card de restaurante | Uber, Glovo | 🔴 Crítico | Calcular com Google Directions API e mostrar "~20 min" |
| Avaliação média (estrelas) no card do restaurante | Todos | 🔴 Crítico | Agregar `ratings` table e mostrar avg + count |
| Indicador "Aberto / Fechado" em tempo real | Todos | 🔴 Crítico | Campo `opening_hours` no restaurante + lógica de horário |
| Filtros (distância, avaliação, tipo de cozinha, tempo de entrega) | Todos | 🟡 Importante | Bottom sheet com FilterChips |
| Secção "Recentemente visitado" | Uber, iFood | 🟡 Importante | Persistir últimos 5 restaurantes em SharedPreferences |
| Secção "Restaurantes favoritos" em destaque | Todos | 🟡 Importante | `FavoriteStore` já existe — criar secção no home |
| Promoções/banners dinâmicos (configuráveis no admin) | Uber, iFood | 🟡 Importante | Tabela `banners` no Supabase + admin toggle |
| Pesquisa de produtos (não só restaurantes) | Glovo | 🟡 Importante | Pesquisa unificada em produtos + restaurantes |
| Taxa de entrega visível no card | Todos | 🟢 Nice to have | Mostrar "Entrega €2.50" ou "Grátis" no card |
| Ordenação (mais próximo, mais bem avaliado, mais rápido) | Todos | 🟢 Nice to have | Dropdown sort |

---

## C5 · Ecrã do Restaurante / Menu

**Ficheiro:** `restaurant_menu_screen.dart`

### O que existe no Bora
- Foto do restaurante no topo
- Categorias com emojis e scroll horizontal
- Lista de produtos por categoria
- Favoritar restaurante
- Botão para reserva (se habilitado)
- Navegar para `product_detail_screen.dart`
- Cart FAB com contador de items

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Sticky header de categorias (scroll) | Todos | 🔴 Crítico | `SliverPersistentHeader` com categorias que fixam ao scroll |
| Avaliação do restaurante visível | Todos | 🔴 Crítico | Mostrar avg rating + número de reviews na header |
| Tempo de entrega + distância na header | Uber, Glovo | 🔴 Crítico | Calcular e mostrar "25 min · 1.2 km" |
| Indicador "Mais pedido" / "Popular" nos produtos | Todos | 🟡 Importante | Tag baseada em contagem de pedidos |
| Busca dentro do menu | Uber, iFood | 🟡 Importante | TextField de filtro dentro do menu |
| Informação nutricional e alergénicos | Uber Eats (PT/EU) | 🟡 Importante | Campo extra em `partner_products` + ícones |
| Promoções/combos em destaque no topo | Todos | 🟡 Importante | Secção "Promoções" antes das categorias |
| Foto obrigatória para todos os produtos | Todos | 🟡 Importante | Validar no `add_product_screen` |
| "Adicionar ao carrinho" directo do card (sem entrar no detalhe) | Glovo | 🟢 Nice to have | Botão "+" inline no card |
| Informação de embalagem / taxa de saco visível | — | 🟢 Nice to have | Mostrar €0.30 saco na header |

---

## C6 · Detalhe de Produto

**Ficheiro:** `product_detail_screen.dart`

### O que existe no Bora
- Foto do produto (hero image)
- Nome + descrição
- Variantes com preços (AnimatedSwitcher)
- Botão "Adicionar ao carrinho · €X.XX"

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Modificadores / extras (molhos, toppings, remover ingrediente) | Todos | 🔴 Crítico | Modelo `modifiers` table + UI de checkboxes/radio |
| Seletor de quantidade antes de adicionar | Todos | 🔴 Crítico | Counter widget (−/+) antes do botão add |
| Campo de nota especial ("sem cebola") | Todos | 🟡 Importante | `TextField` opcional por item |
| Alergénicos e informação nutricional | Glovo, Uber Eats | 🟡 Importante | Campos extra no produto |
| "Clientes que pediram isto também pediram" | Uber | 🟢 Nice to have | Recomendações baseadas em dados |

---

## C7 · Carrinho

**Ficheiro:** `cart_screen.dart`

### O que existe no Bora
- Lista de items com quantidade
- Subtotal, taxa de entrega, taxa de serviço, markup
- `TipSelector` (gorjeta ao estafeta)
- Morada de entrega editável
- Toggle takeaway
- Toggle apartamento (taxa extra)
- Botão "Ir para pagamento"

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Campo de código promocional / cupão | Todos | 🔴 Crítico | Input + validação na `promo_codes` table |
| Instrução especial para o restaurante | Todos | 🔴 Crítico | `TextField` no carrinho → persistido no pedido |
| Instrução especial para o estafeta | Uber | 🟡 Importante | Campo "Nota para entrega" |
| Estimativa de tempo de entrega antes de confirmar | Todos | 🔴 Crítico | ETA calculado e mostrado no carrinho |
| Agendar entrega (entregar mais tarde) | Uber, iFood | 🟡 Importante | DateTimePicker para hora futura |
| Tokens Bora visíveis e aplicáveis no carrinho | — | 🟡 Importante | Mostrar saldo de tokens + slider de desconto |
| "Adicionar mais itens" (voltar ao menu) | Todos | 🟡 Importante | Botão "Continuar a comprar" |
| Salvar carrinho entre sessões | Uber | 🟢 Nice to have | Persistir em SharedPreferences |
| Mínimo de pedido visível | Todos | 🟢 Nice to have | Avisar se subtotal < mínimo |

---

## C8 · Pagamento

**Ficheiro:** `payment_method_screen.dart`

### O que existe no Bora
- Cartão via Stripe (payment sheet com Google Pay / Apple Pay automático)
- MBWay real (Stripe + webhook)
- Dinheiro / Cash (máx €40)
- Tokens Bora (máx 50% desconto)
- Validação de limite cash

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Guardar cartão para próximas compras | Uber, Glovo | 🔴 Crítico | Stripe Customer + PaymentMethod save |
| Múltiplos cartões guardados | Uber | 🟡 Importante | Listar cartões salvos + selecionar |
| Referência MB (Multibanco) | iFood PT, mercado PT | 🟡 Importante | Stripe Multibanco source |
| Vale / crédito de conta visível | Todos | 🟡 Importante | Campo `credit_balance` no cliente |
| Resumo final antes de confirmar (tudo numa página) | Todos | 🟡 Importante | Review screen com morada + itens + total + método |
| NIF para fatura na confirmação | PT específico | 🟢 Nice to have | Campo NIF opcional |

---

## C9 · Tracking do Pedido

**Ficheiro:** `order_tracking_screen.dart`

### O que existe no Bora
- Mapa Google Maps com posição do estafeta em tempo real
- Polyline da rota (Google Directions)
- Estados do pedido (created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered)
- Chat com estafeta
- Navega automaticamente para `RatingScreen` após entrega

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| ETA countdown em tempo real (relógio a descontar) | Todos | 🔴 Crítico | Calcular ETA com Directions + Timer que atualiza |
| Nome + foto + rating do estafeta no tracking | Todos | 🔴 Crítico | Mostrar card com info do driver quando aceite |
| Notificações push em cada mudança de estado | Todos | 🔴 Crítico | Firebase push já estruturado — falta deploy |
| Botão "Contactar estafeta" (ligar / chat) com 1 toque | Todos | 🔴 Crítico | Botão tel: URI + chat já existe |
| Barra de progresso visual dos estados (tipo timeline) | Uber, Glovo | 🟡 Importante | `Stepper` horizontal com ícones por estado |
| Partilhar tracking com terceiros | Uber | 🟡 Importante | Link único de tracking shareable |
| Animação do ícone do estafeta no mapa | Uber, Glovo | 🟡 Importante | `AnimatedPositioned` ou Tween na posição do marker |
| Botão "Cancelar pedido" disponível antes do pickup | Todos | 🔴 Crítico | Ver C10 abaixo |
| Notificação "Estafeta a chegar" (geofence) | Uber | 🟢 Nice to have | Geolocator distance check + push |

---

## C10 · Cancelamento e Reembolso

**Ecrã dedicado:** ❌ NÃO EXISTE

### O que existe no Bora
- `PaymentService.refund()` existe no código
- Sem ecrã de cancelamento para o cliente
- Sem botão "Cancelar" no tracking
- Sem política de reembolso visível

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Botão "Cancelar pedido" no tracking (antes de pickedUp) | Todos | 🔴 CRÍTICO | Adicionar botão ao `order_tracking_screen` com modal de confirmação |
| Ecrã de cancelamento com motivo | Todos | 🔴 CRÍTICO | Criar `cancel_order_screen.dart` com RadioList de motivos |
| Reembolso automático para cartão/MBWay | Todos | 🔴 CRÍTICO | Ligar `PaymentService.refund()` ao fluxo de cancelamento |
| Política de cancelamento visível (janela de tempo) | Todos | 🟡 Importante | Texto informativo antes de confirmar cancelamento |
| Estado de reembolso no histórico | Uber, Glovo | 🟡 Importante | `OrderStatus.refunded` mostrado no `OrderDetailsScreen` |
| Chat de suporte para disputas | iFood | 🟢 Nice to have | `SupportScreen` já existe — ligar a problemas de pedido |

---

## C11 · Avaliação

**Ficheiro:** `rating_screen.dart`

### O que existe no Bora
- Estrelas 1-5
- Tags rápidas (positivas/negativas conforme estrelas)
- Campo de comentário opcional
- Tip extra ao estafeta
- Avaliação de driver ou restaurante (RatingSubjectType)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Avaliação separada: restaurante + estafeta + app | Todos | 🔴 Crítico | Múltiplas etapas de rating: 1) restaurante 2) estafeta |
| Foto da entrega no ecrã de avaliação | Uber | 🟡 Importante | Mostrar foto tirada pelo driver (proof of delivery) |
| Resposta do restaurante ao review | iFood | 🟢 Nice to have | `ratings.partner_reply` field |
| Rating obrigatório para desbloquear próximo pedido | — | 🟢 Nice to have | Bloqueio soft até avaliar |
| Animação de "Obrigado!" pós-avaliação | Todos | 🟢 Nice to have | Lottie animation |

---

## C12 · Histórico de Pedidos

**Ficheiro:** `orders_screen.dart`, `order_details_screen.dart`

### O que existe no Bora
- Lista de pedidos com estado
- `OrderDetailsScreen`: items, total, estado, estafeta (se atribuído), chat

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| "Repetir pedido" com 1 clique | Todos | 🔴 Crítico | Botão "Reordenar" que adiciona items ao carrinho |
| Filtros no histórico (data, restaurante, estado) | Uber, iFood | 🟡 Importante | Bottom sheet de filtros |
| Download de recibo / fatura PDF | iFood PT | 🟡 Importante | Gerar PDF com `pdf` package |
| Separação visual: Ativos / Concluídos / Cancelados | Todos | 🟡 Importante | TabBar com 3 tabs |
| Montante total gasto (estatística pessoal) | Uber | 🟢 Nice to have | Agregar no topo do histórico |

---

## C13 · Perfil do Cliente

**Ficheiro:** `profile_screen.dart`

### O que existe no Bora
- Foto de perfil (com bug)
- Email, telefone (só leitura)
- Tipo de veículo + matrícula (só driver)
- Saldo de tokens
- Link para suporte
- Logout

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Editar dados inline (nome, telemóvel) | Todos | 🔴 Crítico | Campos editáveis com botão "Guardar" |
| Múltiplos endereços guardados com labels (Casa/Trabalho) | Todos | 🔴 Crítico | `addresses` table + gestão no perfil |
| BUG foto de perfil não guarda | — | 🔴 Crítico | Fix no upload + metadata do Supabase user |
| Métodos de pagamento guardados | Todos | 🟡 Importante | Lista de cards Stripe + MBWay |
| Preferências de notificação | Todos | 🟡 Importante | Toggle push notifications por tipo |
| NIF para faturas | PT específico | 🟡 Importante | Campo NIF em `clients` |
| Histórico de tokens ganhos/usados | — | 🟡 Importante | Link para `bora_tokens` log |
| Modo escuro / tema | Uber | 🟢 Nice to have | ThemeMode toggle |
| Eliminar conta | RGPD obrigatório | 🔴 CRÍTICO LEGAL | Botão "Eliminar conta" → Supabase user delete |

---

# FLUXO DO ESTAFETA

---

## E1 · Registo do Estafeta

**Ficheiro:** `driver_signup_screen.dart`

### O que existe no Bora
- Nome, email, password, telefone, tipo de veículo (bicicleta/moto/carro), matrícula (obrigatória exceto bicicleta)
- IBAN (para pagamentos)
- Selfie do estafeta (upload obrigatório)
- Foto do veículo (upload obrigatório)
- Upload para Supabase Storage `driver-documents`
- Aceitar termos
- Estado inicial: `approval_status = pending`

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Formulário passo-a-passo (wizard steps) | Uber, Glovo | 🟡 Importante | `Stepper` widget — dados pessoais → veículo → documentos |
| Upload do Bilhete de Identidade / CC | Todos | 🟡 Importante | Adicionar campo `id_document` ao formulário |
| Upload da carta de condução | Uber, Glovo | 🟡 Importante | Campo `driving_license` |
| Upload do seguro do veículo | Glovo | 🟡 Importante | Campo `insurance_doc` |
| Verificação de IBAN em tempo real | — | 🟡 Importante | Validar formato PT50 + checksum |
| Timeline estimada de aprovação ("3-5 dias úteis") | Todos | 🟡 Importante | Texto informativo pós-registo |
| Notificação push quando aprovado | Todos | 🔴 Crítico | Firebase push após admin aprovação |

---

## E2 · Aprovação / Rejeição

**Ficheiros:** `driver_pending_screen.dart`, `driver_rejected_screen.dart`

### O que existe no Bora
- Ecrã de pendente com mensagem de espera
- Ecrã de rejeitado com motivo (se fornecido) e botão "Tentar novamente" → `DriverSignupScreen`
- Estado no DB: `approval_status` (pending/approved/rejected)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Timeline de aprovação com passos visíveis | Glovo | 🟡 Importante | Stepper: Documentos enviados → Em análise → Aprovado |
| Notificação push automática | Todos | 🔴 Crítico | Firebase push desde admin approval |
| Email de confirmação de aprovação | Todos | 🟡 Importante | Email automático via Supabase Edge Function |
| Chat com suporte durante aprovação | Glovo | 🟢 Nice to have | Link para suporte |

---

## E3 · Ecrã Inicial do Estafeta (Online/Offline)

**Ficheiro:** `driver_home_screen.dart`

### O que existe no Bora
- Mapa idle em full-screen quando sem pedidos
- Toggle online/offline (bloqueado se tem pedidos ativos)
- Token chip com saldo de tokens
- Transição automática para `DriverMapScreen` quando tem pedidos
- Alert card `_DriverOrderAlertCard` com countdown (40s) para aceitar/rejeitar

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Ganhos do dia visíveis no ecrã idle | Uber, Glovo | 🔴 Crítico | Card "Hoje: €X.XX · N entregas" no idle overlay |
| Heatmap de zonas de alta procura | Uber | 🟡 Importante | Overlay de polígonos coloridos no mapa |
| Modo "Pausa" (vs. offline total) | Uber | 🟡 Importante | Estado intermédio — sem novas ofertas mas não offline |
| Aviso de zona de alta procura (surge) | Uber | 🟡 Importante | Notificação local quando há muitos pedidos na área |
| Botão de acesso rápido a ganhos / perfil | Todos | 🟡 Importante | FABs flutuantes no mapa |
| Estatísticas de aceitação / cancelamento | Uber | 🟢 Nice to have | Taxa de aceitação visível |

---

## E4 · Oferta de Pedido (Accept/Reject)

**Ficheiro:** `driver_home_screen.dart` → `_DriverOrderAlertCard`

### O que existe no Bora
- Modal com: nome do vendedor, morada de pickup, morada de entrega
- Countdown de 40s (barra de progresso)
- Botões Aceitar / Rejeitar
- Auto-rejeição por timeout

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| **Valor ganho na oferta** | Todos | 🔴 CRÍTICO | Mostrar "€3.80 + €0.40/km = ~€4.20" na oferta |
| Distância até ao pickup | Todos | 🔴 Crítico | Calcular e mostrar "1.2 km ao restaurante" |
| Tipo de pedido destacado (restaurante vs mercado) | Uber, Glovo | 🟡 Importante | Ícone + cor diferente por tipo |
| Mini mapa na oferta com rota visual | Glovo | 🟡 Importante | `GoogleMap` estático na oferta |
| Notificação sonora ao receber oferta | Todos | 🔴 Crítico | `audioplayers` package + vibração |
| Número de items / complexidade do pedido | Uber | 🟢 Nice to have | "3 items" mostrado na oferta |

---

## E5 · Mapa e Navegação

**Ficheiro:** `driver_map_screen.dart`

### O que existe no Bora
- Google Maps full-screen
- Polyline com rota otimizada
- Múltiplas paragens (pickup + delivery, stacking)
- `RouteOptimizer` greedy nearest-neighbour
- Painel draggable com próxima paragem, ação, duração
- Marcadores custom de pickup e delivery
- Chat com cliente/parceiro

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Botão "Navegar" que abre Google Maps / Waze nativo | Todos | 🔴 Crítico | `url_launcher` com `geo:` ou `comgooglemaps://` URI |
| Turn-by-turn directions integradas | Uber | 🟡 Importante | Instrução por instrução na barra superior |
| Tráfego em tempo real no mapa | Todos | 🟡 Importante | `trafficEnabled: true` no GoogleMap widget (1 linha) |
| Número de telefone do cliente com 1 toque | Todos | 🔴 Crítico | Botão "Ligar" no painel → `tel:` URI |
| Confirmação por código PIN (segurança na entrega) | Glovo | 🟡 Importante | Cliente vê PIN → estafeta insere no app |
| Foto da entrega (proof of delivery) | Uber | 🟡 Importante | Camera picker ao confirmar entrega |

---

## E6 · Pickup e Confirmação de Entrega

**Ficheiro:** `driver_order_action_helper.dart`

### O que existe no Bora
- Botões de ação por estado: "Cheguei ao restaurante", "Recolhei o pedido", "Entregue"
- Fluxo: `preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered`

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Confirmação por código do cliente | Glovo | 🟡 Importante | PIN de entrega |
| Foto da entrega (proof of delivery) | Uber | 🟡 Importante | ImagePicker antes de confirmar entrega |
| Estimativa de tempo de preparação do restaurante | Uber | 🟡 Importante | Parceiro define tempo → estafeta vê "Pronto em ~15 min" |
| Contacto rápido (ligar / mensagem) ao cliente | Todos | 🔴 Crítico | Botões de contacto visíveis no painel |

---

## E7 · Ganhos e Histórico

**Ficheiro:** `driver_earnings_screen.dart`

### O que existe no Bora
- Saldo atual (`driver_balances`)
- Ganhos semanais + número de entregas
- Lista de transações
- Tokens Bora + converter tokens em dinheiro
- Prioridade boost (comprar tempo de prioridade com tokens)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Ganhos por dia (breakdown diário) | Uber, Glovo | 🔴 Crítico | Agrupar `driver_transactions` por dia |
| Ganhos por mês / gráfico de evolução | Uber | 🟡 Importante | Chart com `fl_chart` package |
| Pedido de levantamento (transferência IBAN) | Todos | 🔴 CRÍTICO | Botão "Levantar saldo" → criar `withdrawal_requests` table |
| Relatório para IRS (exportar CSV/PDF) | PT específico | 🟡 Importante | Export de `driver_transactions` |
| Gorjetas separadas dos ganhos base | Uber | 🟡 Importante | Coluna `tip_amount` separada no ecrã |
| Ganhos em tempo real durante o turno | Uber, Glovo | 🟡 Importante | Actualizar ganhos do dia sem recarregar |

---

## E8 · Perfil do Estafeta

**Ficheiro:** `profile_screen.dart` (partilhado com cliente)

### O que existe no Bora
- Email, telefone, tipo de veículo, matrícula (só leitura)
- Saldo de tokens
- Logout

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Rating médio visível | Todos | 🔴 Crítico | Agregar `ratings` do driver e mostrar no perfil |
| Editar dados do veículo | Todos | 🟡 Importante | Editar tipo + matrícula |
| Editar IBAN | Todos | 🟡 Importante | Campo editável com verificação |
| Documentos (estado + renovação) | Glovo | 🟡 Importante | Lista de documentos + estado (válido/expirado) |
| Disponibilidade semanal (horário preferido) | Uber | 🟢 Nice to have | Calendário de disponibilidade |
| Número de entregas totais (estatísticas de carreira) | Uber | 🟢 Nice to have | Card com total de km, pedidos, avaliação |

---

# FLUXO DO PARCEIRO

---

## P1 · Registo do Parceiro

**Ficheiro:** `register_partner_screen.dart`

### O que existe no Bora
- Nome do restaurante, endereço (autocomplete), telefone, email, password
- URL da foto (campo de texto — não upload direto)
- Tipo de negócio (categoria)
- Aceitar termos
- Criação no Supabase `restaurants` table

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Upload direto da foto/logo | Todos | 🔴 Crítico | ImagePicker + upload para Supabase Storage (não URL manual) |
| Upload de documentos do negócio (NIF, certidão) | Glovo, Uber | 🟡 Importante | Campos de documentos |
| Horários de funcionamento no registo | Todos | 🔴 Crítico | Picker de horas por dia da semana |
| Tipo de cozinha / especialidade | Todos | 🟡 Importante | Multi-select de categorias |
| Raio de entrega configurável | Uber | 🟢 Nice to have | Slider de km máx |
| Onboarding guiado (wizard) | Todos | 🟡 Importante | Passo-a-passo com validação em cada passo |

---

## P2 · Login do Parceiro

**Ficheiro:** `partner_login_screen.dart`, `partner_entry_screen.dart`

### O que existe no Bora
- `PartnerEntryScreen` com dois botões: "Entrar" / "Criar conta"
- Login por email + password
- Auth via Supabase (role: partner)

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| "Esqueceu a password?" | Todos | 🔴 Crítico | Reset por email |
| Biometria para parceiros (Face ID) | Uber Eats (partner) | 🟢 Nice to have | `local_auth` |
| Login com número de telefone | Glovo | 🟢 Nice to have | OTP |

---

## P3 · Dashboard do Parceiro / Pedidos

**Ficheiro:** `partner_dashboard_screen.dart`

### O que existe no Bora
- Lista de pedidos do restaurante
- Aceitar / Rejeitar / Marcar como pronto / Chamar estafeta
- Toggle para reservas (habilitado/desabilitado)
- Navegação para `PartnerProductsScreen` e `PartnerReservationsScreen`

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| **Notificação sonora ao receber pedido** | Todos | 🔴 CRÍTICO | `audioplayers` + vibração ao novo pedido |
| Tempo de preparação configurável por pedido | Todos | 🔴 Crítico | Picker "Pronto em: 15 / 20 / 30 / 45 min" ao aceitar |
| Counter de pedidos pendentes visível (badge) | Todos | 🔴 Crítico | Badge no ícone/tab com count de pedidos pending |
| Filtrar pedidos por estado | Todos | 🟡 Importante | TabBar: Novos / Em preparação / Prontos / Entregues |
| Estatísticas do dia (pedidos, faturação) | Todos | 🟡 Importante | Card no topo: "Hoje: N pedidos · €X.XX" |
| Imprimir ticket do pedido (impressora térmica) | iFood | 🟢 Nice to have | Plugin Bluetooth printer |
| Chat com estafeta quando chama driver | — | 🟡 Importante | `partner_call_driver_screen` já existe mas sem chat |
| Painel de controlo com métricas da semana | Todos | 🟡 Importante | Gráfico simples de vendas |

---

## P4 · Menu Digital (Produtos)

**Ficheiro:** `partner_products_screen.dart`, `add_product_screen.dart`

### O que existe no Bora
- Lista de produtos do restaurante
- Adicionar produto (`AddProductScreen`)
- Editar / eliminar produto

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Toggle "Indisponível hoje" (sold out) por produto | Todos | 🔴 CRÍTICO | Boolean `is_available` + toggle rápido na lista |
| Arrastar para reordenar produtos | Todos | 🟡 Importante | `ReorderableListView` |
| Promoções / desconto por produto (% ou valor) | Todos | 🟡 Importante | Campo `discount_pct` + visual de preço riscado |
| Horário de disponibilidade por produto (ex: só ao jantar) | Uber Eats | 🟢 Nice to have | `available_from` / `available_until` por item |
| Bulk edit (preços, disponibilidade em massa) | iFood | 🟢 Nice to have | Multi-select + acção em massa |
| Gestão de categorias (criar/renomear/eliminar) | Todos | 🟡 Importante | CRUD de categorias no parceiro |
| Cópia de produto (duplicar) | iFood | 🟢 Nice to have | Botão duplicar |
| Preview de como o produto aparece ao cliente | Todos | 🟡 Importante | Botão "Ver como cliente" |

---

## P5 · Histórico e Ganhos do Parceiro

**Ecrã dedicado:** ❌ NÃO EXISTE

### O que existe no Bora
- Nada. Parceiro não tem visibilidade dos seus ganhos.

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| **Ecrã de ganhos do parceiro** | Todos | 🔴 CRÍTICO | Criar `partner_earnings_screen.dart` com query em `orders` |
| Relatório financeiro (vendas, comissões, líquido) | Todos | 🔴 CRÍTICO | Breakdown: subtotal − comissão Bora = líquido |
| Histórico de pedidos entregues | Todos | 🔴 CRÍTICO | Lista filtrável de pedidos `delivered` |
| Export CSV / PDF para contabilidade | iFood | 🟡 Importante | Botão de export |
| Calendário de pagamentos (quando recebe) | Todos | 🟡 Importante | Info sobre ciclo de pagamento |
| Métricas de desempenho (rating médio, % aceitação) | Uber Eats | 🟡 Importante | Agregar dados de `ratings` e `orders` |

---

## P6 · Reservas

**Ficheiro:** `partner_reservations_screen.dart`

### O que existe no Bora
- Lista de reservas ordenada por data/hora
- Confirmar / Cancelar reserva
- Marcar chegada do cliente

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| Configuração do número de mesas / capacidade | Todos | 🔴 Crítico | Admin screen para capacidade por turno |
| Gestão de horários disponíveis para reservas | Todos | 🔴 Crítico | Picker de slots horários disponíveis |
| Lista de espera (waitlist) | Restaurantes PT | 🟢 Nice to have | Queue quando não há mesas |
| Notificação ao cliente 1h antes | Todos | 🟡 Importante | Push/SMS de lembrete automático |
| Vista de calendário (não só lista) | Todos | 🟡 Importante | CalendarView com slots ocupados |
| Notas especiais por reserva (aniversário, alergias) | Todos | 🟡 Importante | Campo de notas no `ReservationModel` |

---

## P7 · Perfil do Parceiro / Horários

**Ecrã dedicado:** ❌ NÃO EXISTE (usa ProfileScreen genérico)

### O que existe no Bora
- ProfileScreen com dados básicos (email, telefone)
- Sem gestão de horários
- Sem edição de dados do restaurante

### O que falta vs Uber Eats / iFood / Glovo

| Gap | Plataforma de referência | Prioridade | Como corrigir |
|-----|--------------------------|------------|---------------|
| **Horários de funcionamento** | Todos | 🔴 CRÍTICO | Criar ecrã com picker de horas por dia da semana |
| **Editar dados do restaurante** | Todos | 🔴 CRÍTICO | Editar nome, morada, telefone, foto, categoria |
| **Modo férias / restaurante fechado** | Todos | 🔴 CRÍTICO | Toggle "Encerrado temporariamente" |
| Raio de entrega configurável | Uber | 🟡 Importante | Slider de distância máxima de entrega |
| Informações legais (NIF, CAE) | PT específico | 🟡 Importante | Campos de dados fiscais |
| Fotos do restaurante (galeria) | Todos | 🟡 Importante | Upload de múltiplas fotos |

---

# RESUMO EXECUTIVO

## Pontuação por Fluxo (100 = paridade com Uber/iFood/Glovo)

| Fluxo | Pontuação Atual | Nível |
|-------|----------------|-------|
| Cliente — Auth/Onboarding | 35/100 | 🔴 Crítico |
| Cliente — Home/Pesquisa | 50/100 | 🟡 Médio |
| Cliente — Restaurante/Menu | 55/100 | 🟡 Médio |
| Cliente — Carrinho/Checkout | 60/100 | 🟡 Médio |
| Cliente — Pagamento | 70/100 | 🟡 Médio |
| Cliente — Tracking | 65/100 | 🟡 Médio |
| Cliente — Cancelamento | 10/100 | 🔴 CRÍTICO |
| Cliente — Avaliação | 60/100 | 🟡 Médio |
| Cliente — Histórico | 45/100 | 🔴 Crítico |
| Cliente — Perfil | 40/100 | 🔴 Crítico |
| Estafeta — Registo/Docs | 60/100 | 🟡 Médio |
| Estafeta — Online/Offline | 65/100 | 🟡 Médio |
| Estafeta — Oferta de Pedido | 50/100 | 🔴 Crítico |
| Estafeta — Mapa/Navegação | 65/100 | 🟡 Médio |
| Estafeta — Ganhos | 55/100 | 🟡 Médio |
| Estafeta — Perfil | 30/100 | 🔴 Crítico |
| Parceiro — Dashboard | 55/100 | 🟡 Médio |
| Parceiro — Menu/Produtos | 45/100 | 🔴 Crítico |
| Parceiro — Ganhos | 0/100 | 🔴 CRÍTICO |
| Parceiro — Reservas | 50/100 | 🟡 Médio |
| Parceiro — Perfil/Horários | 0/100 | 🔴 CRÍTICO |

---

# TOP 10 CRÍTICOS

> Ordenados por impacto no lançamento. Resolver antes de ir live.

| # | Problema | Ficheiro | Prioridade | Fix Estimado |
|---|----------|----------|------------|--------------|
| 1 | **Sem ecrã de cancelamento** — cliente não consegue cancelar | `order_tracking_screen.dart` | 🔴 BLOCKER | 1-2 dias |
| 2 | **Sem ganhos do parceiro** — parceiro não vê o que recebe | Novo ecrã | 🔴 BLOCKER | 2-3 dias |
| 3 | **Sem horários do parceiro** — restaurante nunca aparece "fechado" | Novo ecrã | 🔴 BLOCKER | 1-2 dias |
| 4 | **Bug foto de perfil** — não guarda (launch blocker conhecido) | `profile_screen.dart` | 🔴 BLOCKER | 1 dia |
| 5 | **Sem "Esqueceu a password?"** — cliente fica bloqueado para sempre | `client_login_screen.dart` | 🔴 BLOCKER | 2h |
| 6 | **Valor ganho não mostrado na oferta** — estafeta aceita sem saber o valor | `driver_home_screen.dart` | 🔴 CRÍTICO | 2h |
| 7 | **Sem ETA countdown no tracking** — cliente não sabe quando chega | `order_tracking_screen.dart` | 🔴 CRÍTICO | 4h |
| 8 | **Sem notificação sonora para parceiro** — pedidos passam despercebidos | `partner_dashboard_screen.dart` | 🔴 CRÍTICO | 4h |
| 9 | **Sem tempo de entrega estimado no card do restaurante** — clientes não sabem quanto esperam | `restaurants_screen.dart`, `client_home_screen.dart` | 🔴 CRÍTICO | 1 dia |
| 10 | **Sem "Reordenar" no histórico** — fricção enorme para clientes recorrentes | `orders_screen.dart` | 🔴 CRÍTICO | 4h |

---

## ITENS PÓS-LANÇAMENTO (não bloqueia)

- Login social Google/Apple
- Onboarding animado
- Heatmap de zonas para estafetas
- Upload de documentos do estafeta (BI, seguro)
- Foto proof of delivery
- Modificadores de produto (molhos, extras)
- Agendar entrega futura
- Exportar relatório IRS estafeta
- CalendarView de reservas
- Bulk edit de produtos

---

*Auditoria gerada por CEO-AI com base na leitura completa de lib/screens/ (43 ficheiros) e lib/widgets/ (17 ficheiros)*  
*Comparação com Uber Eats PT, iFood BR/PT, Glovo ES/PT*  
*Última actualização: 2026-04-24*
