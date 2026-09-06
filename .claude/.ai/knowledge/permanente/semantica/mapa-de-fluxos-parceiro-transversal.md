---
id: mapa-de-fluxos-parceiro-transversal
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 1 — varredura do código parceiro + transversais]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# Mapa de Fluxos — PARCEIRO + TRANSVERSAL (13 fluxos)

## 1. Onboarding/registo parceiro
- Ficheiros: `register_partner_screen.dart`, `pending_approval_screen.dart`, `auth_store.dart` (`registerPartnerWithDocumentsAsync`), EF `register-partner` + `upload-restaurant-asset`
- Passos: 1. "Dados do Estabelecimento" (nome/endereço/telefone/cozinha/categoria — validações PT) 2. "Documentos (Opcionais)": NIF `9 dígitos`, IBAN `PT + 22 dígitos`, docs via foto/galeria (bucket privado) 3. "Conta de Acesso" (email/senha ≥6, termos) 4. **Criar conta de parceiro** ("conta ficará pendente de análise (24-48h)") → signup + EF insere `restaurants` pending (NÃO faz setRole) 5. → PendingApprovalScreen. Draft persistido em SharedPreferences
- Estado final: `restaurants.approval_status='pending'`

## 2. Login parceiro + persistência
- Ficheiros: `partner_login_screen.dart`, `auth_store.dart`, `session_store.dart`
- Passos: 1. `Email`/`Palavra-passe` (pré-preenche last email; **Entrar com outra conta** limpa) → **Entrar** → `setPartnerRestaurant` → opt-in biometria → `setRole(partner)` 2. Alt: **Entrar com biometria** (fallback: "Sessão biométrica expirada…")
- Estado final: role=partner; PartnerDashboardScreen; sobrevive restart

## 3. Pedido novo → aceitar → preparar → pronto [2-DEVICES]
- Ficheiros: `partner_dashboard_screen.dart`, `order_store.dart` 🔴 (`restaurantAcceptOrder`/`restaurantMarkReady`), `sound_service.dart`, EF `notify-partner`
- Passos: 1. [Cliente] cria pedido → [Parceiro] realtime INSERT + push; som `bora_alert.wav` loop (canal `bora_orders_urgent_v3`, fullScreenIntent, re-arma 2.5s, timeout 60s) 2. **Aceitar pedido** (delivery: **Aceitar com ETA**) → `created→preparing`, "Pedido aceite — #XXXX. Prepare os itens." 3. **Chamar estafeta** → `preparing→callingDriver` (dispara dispatch), "Estafeta a caminho — #XXXX" → botão vira **Aguardando estafeta...** → **Estafeta a caminho** → **Entregue ✓** 4. Takeaway: **Marcar como Pronto** (sem dispatch) → **Cliente apareceu — Confirmar levantamento** → **Levantado ✓** 5. App fechada: ações na notificação **✅ Aceitar**/**❌ Rejeitar** → RPC `partner_accept_order`/`partner_reject_order` (HTTP direto)

## 4. Rejeitar pedido
- **Rejeitar** → (restaurant_dashboard: dialog "Rejeitar pedido?") → `rejected`. ⚠️ SEM captura de motivo (gap registado)

## 5. Falta de item / ajuste
- SÓ toggle **Disponível/Indisponível** por produto. NÃO há fluxo de falta-de-item por pedido nem refund parcial no lado parceiro (backend/admin)

## 6. Gestão de menu (CRUD optimista)
- Ficheiros: `partner_products_screen.dart`, `restaurant_store.dart`
- **Adicionar produto** (insert optimista, catch → rollback) · editar/toggle (snapshot+rollback; falha → "Não foi possível atualizar a disponibilidade.") · eliminar (backup+rollback) · **Gerir opções** (`product_option_groups`)

## 7. Reservas parceiro: chegada (€2)
- Ficheiros: `partner/reservations/partner_reservations_screen.dart`, `partner_reservas_store.dart`, RPC `partner_mark_arrival` 🔴
- Passos: 1. Dashboard → **Reservas Pro** (som + "Nova reserva de <cliente>") 2. card → **Marcar chegada** → "Chegada marcada" (idempotente: "Chegada já marcada.")
- Variante antiga: **Marcar sentado (€2 crédito)** ("Desconta €2 da conta dele" / "Bora paga-te €2 no próximo settlement semanal")
- Estado final: `arrived`; crédito €2 cliente + payout parceiro

## 8. Settlement/comissão
- Ficheiros: `partner_earnings_screen.dart`, `weekly_settlement_card.dart`
- Ganhos → **Comissão €X** + "Ganho líquido (já descontada a comissão)"; Fecho semanal: "Comissão Bora: €X", "A entregar à Bora: €X"/"A receber da Bora: €X", "fecha a semana todas as segundas". UI mostra TOTAL, não o breakdown 10/5/5 (server-side 🔴)

## 9. Push FG / BG / app morto [transversal]
- Ficheiros: `notification_service.dart`, `push_token_service.dart`, EFs `notify-*`
- FG: `onMessage.listen` (cartão + som realtime) · BG data: `onBackgroundMessage` handler `@pragma('vm:entry-point')` cria canal + notificação rica com ações · morto: `getInitialMessage()` + `onMessageOpenedApp` → ecrã correto · CallKit/fullScreenIntent SÓ na oferta de estafeta (`BORA-OFFER`, heartbeat ≥45s → CallKit); parceiro usa notificação rica
- Token por papel: `registerForRole('partner')` → `partner_push_tokens` (multi-device)

## 10. Deep links [transversal]
- `main.dart` routes: `/role` `/login` `/admin` `/admin/crosstalk` `/admin/suggestions/metrics` `/admin/ratings` `/admin/settlements`; `onGenerateRoute`: `/partner/ratings` `/restaurant/ratings` `/driver/ratings` (push low_rating)
- São links INTERNOS de notificação. SEM app_links/uni_links (nenhum URL scheme externo)

## 11. PT-PT [transversal]
- Parceiro/restaurante: 100% PT-PT (labels, snackbars, validações). Única exceção neutra: badge `ONLINE`/`OFFLINE`. (Strings EN só em debugPrint)

## 12. Offline [transversal]
- `order_store.dart` 🔴 (só ler): realtime error/closed → resubscribe em **5s**; fallback polling `Timer.periodic` (~30s); canal extra `client_orders_$uid` para transições perdidas
- Estafeta: `OfflineStatusQueue.enqueue` para pickedUp/onTheWay/delivered sem rede; drena ao reconectar
- SEM banner "sem rede" dedicado — degrada graciosamente

## 13. Sessão entre restarts [transversal]
- `SessionStore` (`bora_app.user_role`) + refresh token/biometria → reabrir app cai direto no dashboard do papel

## Labels-chave (Maestro por texto)
`Criar conta de parceiro` · `Entrar` · `Entrar com biometria` · `Entrar com outra conta` · `Aceitar pedido` · `Aceitar com ETA` · `Rejeitar` · `Rejeitar pedido` · `Chamar estafeta` · `Marcar como Pronto` · `Cliente apareceu — Confirmar levantamento` · `Entregue ✓` · `Levantado ✓` · `Adicionar produto` · `Gerir opções` · `Disponível`/`Indisponível` · `Reservas Pro` · `Marcar chegada` · `Gerir produtos` · `Mudar modo`
