# Sessão Parte 1 — Fixes de device-test (M-A → M-E)
**Data:** 2026-06-10 · **Branch:** autonomous-night-2026-04-29 · **Modelo:** Fable 5
**Origem:** testes do Danilo em device (T1-T21) + fotos · prompt Claude.ai 2026-06-10

> Nota: a sessão caiu a meio (2 agentes em voo) e foi retomada com recuperação de
> estado completa (git limpo, mapeamentos reaproveitados, zero edits híbridos).

---

## M-A — Grants RPC persistidos em migration ✅
**Commit:** `be9f531` · **Migration:** `supabase/migrations/20260610211505_fix_partner_rpc_grants.sql` (aplicada em produção via MCP)

- Persistidos os 15 grants do hot-fix (14 `partner_*` + `compute_provider_weekly_payout`).
- **Sweep completo** de `.rpc()` em `lib/` (incl. chamadas multi-linha — o grep simples
  perdia ~40 call sites! — e o wrapper dinâmico `AdminDriverService._callRpc`).
- **+47 órfãs encontradas e corrigidas** (total 62): o hardening 2026-06-09 tinha deixado
  sem `GRANT EXECUTE` a `authenticated`:
  - **Cliente/estafeta (9):** `consume_tokens` (desconto tokens no checkout!),
    `register_push_token` (tokens FCM!), `driver_cancel_order`, `request_driver_help`,
    `finalize_storeshopping_purchase(_v2)`, `update_bag_count_bypass`,
    `client_cancel_reservation`, `client_register_with_referral`
  - **Admin (38):** aprovar/rejeitar/banir estafeta, `approve_partner`/`reject_partner`,
    payouts (parceiro/marcações/settlements), ratings, receipts, referrals, broadcasts,
    cancelamentos, reset foto produto, push token admin, etc.
- **Validação de segurança caso a caso:** todas SECURITY DEFINER com guard interno
  (`auth.uid()` / `_admin_op_guard` / `_reservas_pro_assert_admin` / `is_admin`) —
  **exceto `consume_tokens`**, que debitava `p_user_id` arbitrário sem validar o caller.
  A migration adiciona guard: autenticado só consome os PRÓPRIOS tokens (admin e
  service_role/jobs passam). Só depois é concedido o EXECUTE.
- Verificado pós-aplicação: 18/18 amostra com `auth_ok=true`.

## M-B — Header verde em todos os ecrãs ✅
**Commit:** `ac5e297`

**Diagnóstico (importante):** o código atual JÁ estava verde em praticamente tudo —
o M6 (`4483209`, hoje 07:38) mudou o token `headerGradient` para verde sólido, o que
pintou de uma vez o `BoraScreenAppBar` + 12 AppBars inline + o tema global. **Os headers
brancos das fotos do Danilo são de APK pré-M6** (o próprio commit M6 já o registava).
Auditoria aos 46 sites `appBar: AppBar(` nas 4 áreas confirmou:
- 12 inline `transparent+headerGradient` → verdes ✓
- 8 herdam o tema global verde ✓ · 3 viewers pretos intencionais (fotos) ✓
- **1 divergente real:** `store_products_screen` (header BRANCO explícito com texto verde)
  → migrado para `BoraScreenAppBar` (carrinho `_CartBadge` herda branco).
- +4 padronizados para `BoraScreenAppBar` (wallet_history, market_store loader,
  client_favorites, reservation_flow).
- Restaurantes / Serviços / admin "Sugestões do Robot" usam `BoraScreenAppBar` → verdes
  no build novo. **Critério "zero headers ilegíveis" cumprido no código; confirmar em
  device com build ≥276.**

## M-C — Página de loja padrão Glovo ✅
**Commit:** `e4be019` (+594/−114 em `restaurant_menu_screen.dart`)

`RestaurantMenuScreen` (componente único de TODOS os restaurantes — McD/BK/KFC vão
direto para cá por serem não-parceiros) reconstruído:
- **Header de loja:** capa (`hero_image_url`, fallback gradiente verde) + **logo circular
  sobreposto** (`photo_url`) + nome + chips **rating ⭐ / ETA / taxa de entrega**
  (mesmas fórmulas `OrderEtaService`/`PricingService.estimatedDeliveryFee` das listagens).
- **Tab bar horizontal sticky** de categorias (ordem da fonte preservada — M9), tap →
  scroll à secção; scroll → tab ativa (sem dependências novas).
- **Secções com carrosséis horizontais** de product cards (foto, nome, preço, botão `+`)
  no lugar da grelha de pastas. "Ver todos" → ecrã de secção existente.
- **Zero mudanças de pricing:** display não-parceiro ×1.15 e gate `hasRequiredOptions`
  do `+` copiados literalmente do código existente; `_addToCart` idêntico. Pesquisa RPC,
  fallback legacy e botão "Reservar mesa" intactos. Página de produto não tocada (já no padrão).

## M-D — Logos + capas das lojas não-parceiras ✅ (DB)
Sem mudanças de código — dados em produção:
- **Kiwoko, Leroy Merlin, Worten, Zippy:** `photo_url` + `hero_image_url` preenchidos com
  as imagens de loja oficiais do Glovo (formato `stores-glovo/stores/{hash}` — o mesmo
  padrão do Wells; IDs/slug reais reaproveitados da sessão `.ai_4lojas_*`). 4/4 URLs
  validadas (200, 1242×690+).
- **Wells:** já tinha (sessão anterior) ✓.
- **Burger King:** ganhou capa oficial (CDN burgerking.pt — Whopper + lettering, 2000×1333,
  verificada visualmente).
- McDonald's/KFC: ficam com logo existente + fallback verde no header (SSR Glovo carrega
  imagens client-side; sem capa oficial fiável disponível — admin pode subir via painel).

## M-E — Transparência de preço carry/send ✅
**Commit:** (este) — `cart_store.dart`, `payment_method_screen.dart`, `cart_screen.dart`

**Root cause (provada no código):** o resumo usava distância **haversine** (linha reta,
`CartStore._recalculateDistance`) enquanto a cobrança usa a **rota Google**
(`MapsService.getDistanceKm` em `createOrder`/`startCardPaymentDraft` → `create_order`
grava o buffer que o Stripe cobra). Linha reta < rota ⇒ Guarda: 2.8 km (≤4 ⇒ €6.00 no
resumo) vs rota 5.58 km (⇒ €6.79 no Stripe). **Não era só carry/send:** qualquer fluxo
com km extra tinha o mesmo gap (restaurante/mercado incluídos).
**Porque o B1 do prompt FAVORES "não pegou":** o breakdown por-km no resumo FOI
implementado (existe em `payment_method_screen` ~linha 256) — mas alimentado pela
distância errada, mostrava sempre "0 km extra".

**Fix (server == display):**
- `CartStore.refreshRouteDistance()` novo — busca a rota Google (a MESMA da cobrança),
  atualiza `_distanceKm`, invalida o cache do quote server e notifica. Fallback: mantém
  haversine se offline/erro.
- Chamado ao entrar no `PaymentMethodScreen` (resumo carry/send/checkout) e no painel
  do `CartScreen`. O breakdown por-km existente passa a mostrar `base €6.00 + €0.79
  (1.58 km extra)` e o total exato €6.79 — o Stripe cobra exatamente o que se vê.

---

## Pendências / notas
1. **`payment_method_screen.dart` tinha um diff NÃO COMMITADO de 2026-06-04** (try/catch
   checkout + snackbar cash "A preparar o seu pedido…") de sessão anterior — completo e
   são; segue incluído no commit M-E (mesmo ficheiro). ✓ analyze limpo.
2. **Agente de trace M-E não regressou** (background); root cause foi provado diretamente
   no código/DB — sem dependência do agente.
3. Capas McD/KFC: fallback verde (logo mantém-se). Opcional pós-launch via admin.
4. Hero/logo das lojas usam URLs Glovo dhmedia (padrão Wells/produtos) — se um dia
   morrerem, migrar para bucket `restaurant-assets` (path canónico `{id}/{kind}.{ext}`).
5. Edge Functions chamadas com service_role não foram alvo do sweep (grants de
   `authenticated` não se aplicam); RPCs nunca chamadas pela app ficaram fechadas
   (least privilege): `file_complaint`, `request_order_cancel`,
   `restaurant_respond_to_rating`, `client_apply_promo_code`, etc.

## Checklist T para o Danilo (device, build ≥276)
- [ ] **T-A (grants):** painel parceiro — mesas/walk-in/takeaway/floor-plan sem 42501;
      admin: aprovar estafeta + payouts abrem sem erro; cliente: usar TOKENS no checkout
      (era 42501 silencioso!); cancelar uma reserva de cliente.
- [ ] **T-B (headers):** Restaurantes, Serviços, Saldo Bora, Favoritos, produtos de loja
      (Continente → categoria), admin "Sugestões do Robot" — TODOS com header verde
      #16A34A e título/seta brancos.
- [ ] **T-C (página Glovo):** abrir McDonald's lado a lado com o Glovo — capa/logo/nome/
      métricas + tabs de categorias sticky + carrosséis horizontais com `+`; tocar numa
      tab salta à secção; produto com menu obrigatório abre detalhe no `+`.
- [ ] **T-D (logos):** listagem de lojas — Kiwoko/Leroy/Worten/Zippy/Wells com imagem
      real (sem letras K/L/W/Z); abrir cada uma → capa no topo. Burger King com capa.
- [ ] **T-E (preço):** Levar Compras com moradas reais >4 km de rota — o resumo mostra
      o TOTAL EXATO (ex.: €6.79 com breakdown base+extra) e o Stripe cobra esse valor.
      Repetir em Enviar Encomenda.
