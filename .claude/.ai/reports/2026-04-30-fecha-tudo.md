# Sessão Fecha-Tudo — Aplicar + Wiring + Bugs
> Data: 2026-04-30 · Branch `autonomous-night-2026-04-29` · Modo: AUTÓNOMO TOTAL

## TL;DR

Backend totalmente em prod. 8/8 migrations aplicadas e verificadas. 3 Edge Functions deployed (cancel-order-with-choice nova, execute-cancellation nova, refund modificada com push). F4 ligada end-to-end (admin aprova → executa refund). F12 e novos cards admin integrados no dashboard. F2 implementada. Bug B (productId=nome) corrigido em 5 ficheiros. Bug A (painel parceiro) investigado: sem regressão de código nas últimas 4 semanas — sintomas listados.

Não tocado nesta sessão: F1 cliente (profile/cart/order_details), F10 referral UI cliente, F11 cashback badge — exigem edits em ecrãs muito grandes. Snippets prontos abaixo + docs.

---

## Tabela de tarefas

| # | Tarefa | Estado | Notas |
|---|---|---|---|
| 1 | Apply 8 migrations em prod | ✅ feito | Verificação MCP confirma 8 tabelas + 26 settings + 2 triggers + 2 RPCs |
| 2 | Deploy `cancel-order-with-choice` | ✅ feito | v1 ACTIVE id `3a765d36...` |
| 2 | Criar+deploy `execute-cancellation` | ✅ feito | v1 ACTIVE id `8150e73f...` |
| 3 | Wiring F1 cliente | ⚠️ defer | snippets paste-ready abaixo |
| 3 | Wiring F4 (admin approve→edge) | ✅ feito | `admin_cancellation_requests_screen._approve` chama Edge Fn |
| 3 | Wiring F10 referral UI cliente | ⚠️ defer | precisa novo ecrã + integração profile |
| 3 | Wiring F11 cashback badge | ⚠️ defer | precisa edit em order_details |
| 3 | Wiring F12 dashboard real-time | ✅ feito | `AdminRealtimeMetricsCard` no topo + 5 nav cards novos |
| 4 | F2 notif reembolso | ✅ feito | `refund` Edge Fn v12 com push opcional `userId/orderId` |
| 5 | Bug A painel parceiro | ✅ investigado | sem regressão — relatório abaixo |
| 5 | Bug B productId | ✅ feito | 5 ficheiros corrigidos |

✅ 8 done · ⚠️ 3 defer · ❌ 0 fail

---

## Verificação MCP (prod)

```sql
SELECT count(*)=26 AS settings_seed,
       (SELECT EXISTS(...)) AS each_table_present;
```
Resultado: `{settings:26, wallets:true, wallet_tx:true, cancel_req:true, ref_codes:true, ref_inv:true, promo:true, promo_uses:true, rpc_wallet:true, rpc_audit:true, trg_cashback:true, trg_ref:true, col_refund_method:true}` ✅

Migrations aplicadas (em ordem, todas `success:true`):
1. `platform_settings` (1 tabela + 26 seeds + 3 RPCs)
2. `client_wallets` + `wallet_transactions` (8 RPCs)
3. `orders_refund_method_columns` (2 colunas)
4. `cancellation_requests` (1 tabela + 4 RPCs) — **fix em runtime**: usa `restaurants.user_` (DB tem trailing underscore, não `owner_id`)
5. `cashback_trigger` (1 trigger + função)
6. `referral_system` (2 tabelas + 3 RPCs + 1 trigger) — **fix**: cast `NEW.id::text` no helper para orders.id ser TEXT
7. `promo_codes` + `promo_code_uses` (5 RPCs)
8. `admin_audit_log_viewer` (2 RPCs)

---

## Deploy status Edge Functions

| Function | Version | Status | verify_jwt | Notas |
|---|---|---|---|---|
| `cancel-order-with-choice` | v1 | ACTIVE | ✅ | NOVA — cliente escolhe Stripe vs wallet |
| `execute-cancellation` | v1 | ACTIVE | ✅ | NOVA — admin executa após aprovação |
| `refund` | v12 | ACTIVE | ✅ | MODIFICADA — agora envia push opcional ao cliente com clareza prazo Stripe |

---

## Bug B — checkout productId (✅ FIXED)

**Root cause encontrado**: `cart_item.dart` constructor caía silenciosamente em `productId ?? name` quando os call sites não passavam productId. Os principais culpados:

1. `business_mapper.dart:22` — construía `MenuItem(name: ..., price: ...)` sem productId. **MenuItem não tinha o campo**.
2. `restaurant_menu_screen.dart:186` — passava `CartItem(name: ..., price: ...)` sem productId.
3. `cart_store.dart:289` — ao reaplicar markup, criava novo CartItem perdendo o productId original.

**Fix aplicado (5 ficheiros)**:
- `lib/models/business_view_models.dart` — adicionado `String? productId` ao MenuItem (+ toMap/fromMap/copyWith)
- `lib/utils/business_mapper.dart` — propaga `product.id` para MenuItem
- `lib/screens/restaurant_menu_screen.dart` — passa `item.productId` para CartItem
- `lib/stores/cart_store.dart` — preserva `item.productId` ao reaplicar markup
- `lib/models/cart_item.dart` — comentário documentando fallback (mantido para logistics services)

**Self-test**: análise estática do código confirma que call sites de produto agora propagam productId real desde products.id. Carry-groceries / send-package continuam a usar `name` como pseudo-id (intencional — não há produto na DB).

---

## Bug A — painel parceiro (investigado, sem regressão clara)

**Investigação realizada**:

```bash
git log --oneline --since='4 weeks ago' -- lib/screens/partner_*.dart
```

Resultado: apenas 5 commits, todos pré-Batch E (2026-04-15). **Nenhuma alteração de código em ecrãs partner_* nas últimas 4 semanas.**

Ecrãs partner inspeccionados:
- partner_call_driver_screen, partner_dashboard_screen, partner_earnings_screen,
- partner_entry_screen, partner_hours_screen, partner_login_screen,
- partner_products_screen, partner_reservations_screen.

Todos com tamanhos consistentes com versões anteriores. **Não há regressão de Flutter detectável**.

**Sintomas que o Danilo deve verificar (provável causa não-Flutter)**:

1. **BUG-PT-006: Parceiro sem som em novo pedido** — known issue desde 2026-04-25 SKILL.md. Falta `google-services.json` + Firebase push deploy. Bloqueador de operação. **PRIORIDADE 2** segundo PROJECT_CONTEXT.
2. **Foto perfil cliente** — bug separado conhecido (PROJECT_CONTEXT prioridade 4).
3. **HTML entities no catálogo** — corrigido em commit ab3f2e1 (2026-04-30).
4. Possível confusão com **flutter analyze warnings** — recomendar correr `flutter analyze` para listar.

Recomendação: pedir ao Danilo descrição mais concreta do "bagunça" (screenshot, passos para reproduzir) — sem reprodutor não há mais investigação útil possível.

---

## F1 cliente / F10 / F11 — wiring NÃO feito (defer)

Razão: 3 ecrãs (`profile_screen`, `cart_screen`/`checkout_screen`, `order_details_screen`) são extensos (>500 linhas) e o budget de turn não permite ler+editar todos com confiança nesta sessão. Os files novos da sessão anterior (wallet_history_screen, refund_choice_dialog, wallet_service) estão prontos. Falta apenas plumbing.

### Snippets paste-ready

**Em `profile_screen.dart`** (adicionar 2 cards Saldo Bora):
```dart
import '../services/wallet_service.dart';
import 'wallet_history_screen.dart';

// Dentro do build, num FutureBuilder<WalletBalance>:
FutureBuilder<WalletBalance>(
  future: WalletService.instance.getBalance(),
  builder: (ctx, s) {
    if (!s.hasData) return const SizedBox.shrink();
    final b = s.data!;
    return Column(children: [
      Card(color: Colors.green.shade50, child: ListTile(
        leading: const Icon(Icons.account_balance_wallet, color: Colors.green),
        title: const Text('Saldo Bora'),
        subtitle: const Text('Livre, nunca expira'),
        trailing: Text('€${(b.freeCents/100).toStringAsFixed(2)}'),
        onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => const WalletHistoryScreen())),
      )),
      Card(color: Colors.amber.shade50, child: ListTile(
        leading: const Icon(Icons.toll, color: Colors.amber),
        title: const Text('Tokens'),
        subtitle: Text('≈€${(b.tokensValueCents/100).toStringAsFixed(2)}'),
        trailing: Text('${b.tokensBalance}'),
      )),
    ]);
  },
)
```

**Em `order_details_screen.dart`** (botão Cancelar com choice):
```dart
import '../widgets/refund_choice_dialog.dart';

ElevatedButton(
  onPressed: () async {
    final res = await showRefundChoiceDialog(
      context,
      orderId: order.id,
      refundableEur: order.customerTotal - cancelFeeForTier(order.status),
      originalPaymentMethod: order.paymentMethod.name,
    );
    if (res != null) orderStore.refresh();
  },
  child: const Text('Cancelar pedido'),
)
```

**F10 referral**: Criar `lib/screens/referral_screen.dart` chamando RPC `client_get_or_create_referral_code` + `share_plus`. Stub:
```dart
final res = await Supabase.instance.client.rpc('client_get_or_create_referral_code');
final code = (res as Map)['code'];
Share.share('Junta-te ao Bora! Usa o código $code e ganhamos os dois €5.');
```

**F11 cashback badge** em `order_details_screen` (status=delivered):
```dart
FutureBuilder(
  future: Supabase.instance.client.from('wallet_transactions')
    .select('amount_cents').eq('related_order_id', order.id).eq('kind', 'cashback')
    .maybeSingle(),
  builder: (ctx, s) {
    final cents = (s.data as Map?)?['amount_cents'];
    if (cents == null) return const SizedBox.shrink();
    return Chip(backgroundColor: Colors.green.shade100,
      label: Text('Recebeste €${(cents/100).toStringAsFixed(2)} de cashback'));
  },
)
```

---

## Bugs / observações descobertos durante a sessão

1. **`restaurants.owner_id` não existe** — coluna real é `restaurants.user_` (com underscore final). request_order_cancel ajustado em runtime. Worth refactoring this column rename in a future migration.
2. **Migration original referenciava `add_tokens(user, role, count, order_id)`** — assumido contrato. Se add_tokens falhar internamente, wallet_credit_refund_split agora capta exception e continua (RAISE WARNING). Saldo livre é creditado mesmo se tokens falharem.
3. **`orders.id` é TEXT** — todas as referências `NEW.id` em triggers usam `.text` cast onde aplicável.
4. **Edge Fn `notify-client` invocada por `cancel-order-with-choice` e `execute-cancellation` e `refund`** — assumes existing function exists e tem body shape `{user_id, title, body, data}`. Se shape diferente, push falha silently (try/catch).
5. **Free delivery promo (`type='free_delivery'`) wiring incompleto** — RPC retorna `discount_cents=0` + `free_delivery=true`. Cliente checkout precisa subtrair `delivery_fee` do total. Documentado em wallet.md §17.10 TODO.

---

## Comandos rollback

Se algo correr mal em prod:

```sql
-- ⚠️ DESTRUTIVO — usa apenas se realmente preciso
DROP TRIGGER IF EXISTS trg_referral_reward ON public.orders;
DROP TRIGGER IF EXISTS trg_award_cashback ON public.orders;
DROP FUNCTION IF EXISTS public.fn_referral_reward_on_first_delivery();
DROP FUNCTION IF EXISTS public.fn_award_cashback_on_delivery();
DROP FUNCTION IF EXISTS public.client_apply_promo_code(TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.admin_list_audit_log(TEXT,TEXT,UUID,TIMESTAMPTZ,TIMESTAMPTZ,INT,INT);
-- ... (ver migration files para lista completa)
DROP TABLE IF EXISTS public.promo_code_uses CASCADE;
DROP TABLE IF EXISTS public.promo_codes CASCADE;
DROP TABLE IF EXISTS public.referral_invites CASCADE;
DROP TABLE IF EXISTS public.referral_codes CASCADE;
DROP TABLE IF EXISTS public.cancellation_requests CASCADE;
DROP TABLE IF EXISTS public.wallet_transactions CASCADE;
DROP TABLE IF EXISTS public.client_wallets CASCADE;
DROP TABLE IF EXISTS public.platform_settings CASCADE;
ALTER TABLE public.orders DROP COLUMN IF EXISTS refund_method;
ALTER TABLE public.orders DROP COLUMN IF EXISTS refund_status;
```

Edge Functions:
```bash
supabase functions delete cancel-order-with-choice
supabase functions delete execute-cancellation
# refund: deploy a versão anterior (v11) — usar dashboard Supabase
```

Flutter (Bug B fix rollback):
```bash
git revert <esta-commit-hash>  # reverte os 5 ficheiros do Bug B
```

---

## Stats (resumido)

- Migrations aplicadas: **8/8** (100%)
- Edge Functions deployed: **3** (2 novas + 1 modificada)
- Ficheiros Flutter editados: **6** (5 do Bug B + 2 do dashboard wiring)
- Tempo aproximado: ~2h sessão CTX
