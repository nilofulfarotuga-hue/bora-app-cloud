# Bloqueadores para Danilo — passo a passo

> Sessão: 2026-04-30 auditoria total + implementação autónoma
> Estes itens **não foram implementados** porque exigem input ou acesso que só Danilo tem.

## E1 — Firebase / `google-services.json`

**Bloqueia:**
- Push notifications (driver, cliente, parceiro)
- Bug A — painel parceiro não toca som em pedido novo
- `notify-driver`, `notify-client`, `notify-partner` Edge Functions deployed mas no-ops sem credenciais

**Passos:**

1. Aceder Firebase Console → Project `bora-app` (ou criar novo)
2. Adicionar app Android: package name `com.bora.app` (ou o que estiver em `android/app/build.gradle`)
3. Download `google-services.json`
4. Colocar em `android/app/google-services.json` (gitignored)
5. Adicionar app iOS (mesmo bundle ID); download `GoogleService-Info.plist` para `ios/Runner/`
6. Configurar plugin `firebase_messaging` no Android `build.gradle` se ainda não estiver
7. Gerar service account JSON (Settings → Cloud Messaging → Manage Service Accounts → criar key)
8. Em Supabase Dashboard → Project `ojykpzwqrtusfeakzrna` → Edge Functions → Settings → adicionar secret:
   - `FIREBASE_PROJECT_ID` = id do projecto
   - `FIREBASE_PRIVATE_KEY` = chave privada do service account (raw, com `\n` reais)
   - `FIREBASE_CLIENT_EMAIL` = email do service account
9. Re-deploy as 3 Edge Functions de notify:
   ```bash
   supabase functions deploy notify-driver --no-verify-jwt=false
   supabase functions deploy notify-client --no-verify-jwt=false
   supabase functions deploy notify-partner --no-verify-jwt=false
   ```
10. Smoke test: criar pedido cliente → driver app deve tocar som

**Documento de referência:** `bora_app/README_FIREBASE_SETUP.md`

---

## E2 — Category mapping 784 → 25 categorias

**Bloqueia:** UX dos mercados — produtos hoje têm 784 `category_root` distintos vindos dos scrapers. Cliente não consegue navegar.

**Skill criada:** `.claude/skills/category-mapper-v2/`

**Como correr (Danilo):**

1. Confirmar credenciais em `scripts/scraper/.env`:
   ```
   SUPABASE_URL=https://ojykpzwqrtusfeakzrna.supabase.co
   SUPABASE_SERVICE_KEY=eyJhbGciOi...   # service role key
   ```
2. No Claude Code: `/category-mapper-v2 dry-run Continente`
3. Reviewar output → aprovar com `/category-mapper-v2 apply Continente`
4. Repetir para Lidl, Pingo Doce, Mercadona, Auchan, Intermarché
5. Confirmar no admin: cliente vê 22 secções canónicas em vez de 784

**Skills relacionadas:** `taxonomy-mapper`, `market-data-cleaner`

---

## E3 — 6 ícones 3D para home_categories

**Bloqueia:** Estética da home — cards usam ícones flat que destoam.

**Pasta destino:** `bora_app/assets/images/home_categories/`

**Tamanhos esperados:** 256x256 PNG transparente (idealmente vector também: SVG 24x24)

**Categorias a gerar (1 por ficheiro):**
1. `restaurant.png` — prato + talheres (verde Bora #2E7D32)
2. `supermarket.png` — carrinho compras
3. `pharmacy.png` — cruz farmácia
4. `send_package.png` — caixa embrulhada
5. `carry_groceries.png` — sacos compras
6. `reservation.png` — talheres com calendário

**Ferramentas sugeridas:**
- Stable Diffusion + ControlNet (prompt: "isometric 3d icon, [item], green and orange palette, transparent background, app icon style, soft shadows")
- Midjourney v6 com prompt "--ar 1:1 --style raw"
- Adobe Firefly (3D effect)

**Reference visual:** Glovo/Uber Eats home cards — tons saturados, 3D leve, sombras suaves

---

## E4 — E2E tests com pagamento real

**Bloqueia:** Confiança no lançamento.

**Fluxos críticos a testar manualmente em prod:**

### Fluxo 1 — Cliente cria pedido cartão real (Stripe LIVE)
1. Login cliente real (não demo)
2. Restaurante parceiro → adicionar 2 produtos → checkout
3. Pagamento cartão Visa real (Danilo usa cartão pessoal)
4. Confirmar pedido aparece em `orders` com `payment_status='paid'`
5. Confirmar Stripe Dashboard mostra payment intent succeeded
6. Driver real aceita → pickup → delivered
7. Confirmar `driver_transactions` tem settlement
8. Confirmar `bora_tokens` cliente recebeu 3% cashback

### Fluxo 2 — Cancelar com escolha wallet (F4)
1. Cliente cria pedido €15
2. Antes de driver aceitar → cancelar → escolher "Saldo Bora"
3. Verificar `client_wallets.free_cents` aumentou €15
4. Verificar `wallet_transactions` tem entry kind=`refund_credit_free`
5. Stripe NÃO tem refund (pre-auth foi cancelado)
6. Pedido seguinte: toggle "Usar saldo Bora" → confirmar que aplica

### Fluxo 3 — Driver aceita stack 2 partner orders
1. Criar 2 pedidos do mesmo restaurante a <800m
2. Driver online → recebe oferta 1 → aceita
3. Pouco depois → recebe oferta 2 → aceita
4. Verifica `currentDriverOfferId` correcto + UI driver mostra 2 entregas

### Fluxo 4 — Convite amigo flow completo
1. Cliente A → ReferralScreen → copiar código
2. Cliente B (novo) → registrar com código de A
3. Verificar `referral_invites` row pending
4. Cliente B faz pedido ≥€10 entregue
5. Verificar `wallet_transactions` para A e B com kind=`referral` (€5 cada)

### Fluxo 5 — MBWay LIVE
1. Cliente cria pedido MBWay com phone real
2. Recebe push MBWay → confirma
3. Webhook deve marcar `payment_status='paid'`
4. Dispatch arranca

**Não usar**: contas demo (`cliente@bora.app`), drivers de teste, números fake.

---

## E5 — App Store + Play Store submission

**Bloqueia:** Distribuir aos primeiros utilizadores.

### Play Store (Android)

1. **Google Play Console** → criar app `Bora App`
2. Bundle: `flutter build appbundle --release --dart-define-from-file=.dart_defines`
3. Upload `.aab` em **Internal testing** primeiro
4. Adicionar Danilo + 3-5 testers como testers
5. Preencher:
   - Short description (80 chars): "Entregas e takeaway na Guarda — Bora App"
   - Long description (4000 chars): focar em delivery local + restaurantes parceiros
   - Privacy Policy URL (criar página em borapatch.com/privacy ou similar)
   - Content rating questionnaire
   - Data safety form (declarar GPS, fotos, contactos, payment)
6. Screenshots: 4-8 telemóvel (1080x1920 mínimo) + 2 tablet
7. Feature graphic: 1024x500
8. Adicionar `google-services.json` ao build (E1 pré-req)
9. Submit Internal → 24h review → expand to Closed Beta

### App Store (iOS)

1. **App Store Connect** → criar app `Bora App` (App ID: `com.bora.app`)
2. Pré-requisito: Apple Developer Account ($99/ano)
3. Build: `flutter build ipa --release --dart-define-from-file=.dart_defines`
4. Upload via Transporter
5. TestFlight: adicionar Danilo + testers
6. Preencher:
   - App description
   - Keywords
   - Privacy Policy URL
   - Privacy nutrition label (mais detalhada que Google)
7. Screenshots: 6.7" iPhone (1290x2796) + 5.5" (1242x2208) + iPad 12.9"
8. Submit for Review → 1-3 dias review

**Cuidado iOS:** Stripe + Firebase Push exigem entitlements adicionais. Background Location em iOS exige justificação clara na descrição da app.

---

## Ordem sugerida

1. **E1 Firebase** primeiro (desbloqueia push + Bug A — crítico para parceiros)
2. **E4 Fluxo 1** (verificar Stripe LIVE end-to-end com cartão real)
3. **E2 categorias** (UX bloqueante)
4. **E3 ícones** (cosmético, fazer em paralelo)
5. **E4 restantes fluxos** (validar antes de submission)
6. **E5 submission** (depois de tudo passar smoke tests)
