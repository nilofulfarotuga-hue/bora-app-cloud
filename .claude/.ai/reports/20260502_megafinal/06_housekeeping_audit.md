# 📋 SESSÃO 6 — HOUSEKEEPING AUDIT (FASE A)

**Data:** 2026-05-05
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** Claude Opus 4.7 (1M context)
**Modo:** PROTECÇÃO TOTAL — STOP após A8, aguardar luz verde
**Estado:** ✅ FASE A COMPLETA (read-only). Nada foi modificado.

---

## A0 — Regressão check (Sessões 1-5A-2-β + 4C)

| Item | Esperado | Encontrado | Estado |
|---|---|---|---|
| Tabelas `support_*` | 7 | 7 (`support_agent_actions`, `support_chatbot_messages`, `support_chatbot_quota`, `support_chatbot_sessions`, `support_settings`, `support_skills`, `support_tickets`) | ✅ |
| RPCs agente IA (6) | `support_chatbot_*` | **Renomeados** — ver §A0.1 | ✅ funcional |
| RPC admin | `admin_resolve_ticket` | `admin_resolve_ticket(p_ticket_id uuid, p_notes text)` | ✅ |
| Edge Fns suporte | 2 ACTIVE | `support-chatbot` v1, `support-submit-ticket` v1 | ✅ |
| Skills active | 9 | 9 (`APP_TROUBLESHOOTING`, `GENERAL_FAQ`, `HUMAN_REQUEST`, `ORDER_HISTORY`, `ORDER_STATUS`, `REFUND_STATUS`, `TOKENS_INFO`, `WALLET_BLOCKED_HELP`, `WALLET_INFO`) | ✅ |
| Wallet CHECK ≥-2000 | em `driver_wallet` | em `client_wallets.free_balance_cents >= -2000` | ✅ (tabela diferente da assumida) |
| `trg_zz_final_total_dual_write` | activo | activo | ✅ |
| `is_test_order` column | ausente (a criar) | ausente | ✅ pronto p/ B1 |
| Coords NULL pós-0503 | 0 | **N/A** — colunas reais: `pickup_lat/lng`, `dropoff_lat/lng`, `driver_lat/lng` (não `delivery_lat`) | ⚠️ check skipped |

### A0.1 — RPCs agente IA: nomes reais

📋 **Drift detectado vs prompt** — RPCs existem com nomes diferentes do esperado:

| Prompt (esperado) | DB real |
|---|---|
| `support_chatbot_start_session` | (não existe — provavelmente lógica em Edge Fn `support-chatbot`) |
| `support_chatbot_log_message` | (idem) |
| `support_chatbot_end_session` | (idem) |
| `support_chatbot_load_skill` | (idem) |
| `support_chatbot_escalate` | `file_support_ticket(p_role text, p_question text)` |
| — | `agent_get_order_status(p_order_id text)` |
| — | `agent_get_refund_status(p_order_id text)` |
| — | `agent_get_user_orders_summary(p_limit integer)` |
| — | `agent_get_user_tokens_summary()` |
| — | `agent_get_user_wallet_summary()` |
| Bonus | `admin_kpi_avg_ticket(p_days_back integer)`, `increment_chatbot_quota()` |

**Conclusão:** backend 5A-1 implementado como **5 RPCs agent_get_*** (read-only) + **1 RPC `file_support_ticket`** + lógica de sessão/messages dentro da Edge Fn `support-chatbot`. Total funcional: 7 RPCs + 2 Edge Fns. **Não bloqueante.**

### A0.2 — Numeração `business_rules.md`

📋 **Drift vs prompt** — formato real é `## N.` (1-27 + duplicado 18) e `### N.M`, **NÃO** `§N`. Prompt esperava §33 (ausente). Última secção topo: `## 27. ATUALIZAÇÃO AUTOMÁTICA DE PRODUTOS DOS MERCADOS`. Há duplicação `## 18. RESERVAS — PRÉ-PAGAMENTO` (linha 1092) vs `## 18. LIMPEZA DE CASAS` (linha 799).

**Proposta:** apêndice como `## 28. HOUSEKEEPING + UX SUPORTE (Sessão 6)` com subsecções `### 28.1 .. 28.4` — preserva formato existente. (Nenhuma alteração na Fase A; aplicar em Fase B + secção dedicada de update.)

---

## A1 — 4 pedidos teste cancelados (€253.08 stripe)

✅ **Confirmação exacta** dos 4 IDs:

| ID | created_at | stripe_charge_cents | total | subtotal |
|---|---|---|---|---|
| `b90966bf-31ca-4707-89c2-0cef4f9cc33a` | 2026-05-01 09:48 | 668 | 22.16 | 17.16 |
| `1c561ae0-34a9-4048-a2fc-88d2a168d5d5` | 2026-04-30 23:57 | 16369 | 163.69 | 158.69 |
| `88e36c67-d2cf-47e3-a930-6a58166a6dff` | 2026-04-30 23:51 | 6450 | 64.50 | 59.50 |
| `31a5ccd3-4596-4967-af96-181fbacca570` | 2026-04-30 23:50 | 1821 | 18.21 | 13.21 |

Soma `stripe_charge_cents = 25 308 = €253.08` ✅. `refund_amount` NULL em todos (refund decisão futura, fora scope sessão 6).

**Admin dashboards orders (TODO sessão futura — filtro `is_test_order=false`):**
- `lib/screens/admin/admin_orders_screen.dart`
- `lib/screens/admin/admin_order_detail_screen.dart`
- `lib/screens/admin/admin_driver_detail_screen.dart`

---

## A2 — UI suporte actual (FAB + Sheet + Chat)

### A2.1 — `lib/widgets/bora_support_fab.dart` (43 linhas)
- Comportamento actual: `onPressed: () => _open(context)` → `showModalBottomSheet(BoraSupportSheet)`
- **Não** lê `SupportSettingsProvider` directamente (o sheet é que lê).
- B2 vai mudar este comportamento → ler provider + Navigator.push directo se kill ON.

### A2.2 — `lib/widgets/bora_support_sheet.dart` (170 linhas)
- Já importa `SupportChatScreen` (linha 10).
- Usa `provider.shouldShowAiCard` para condicional do card BoraIA.
- B2 vai adicionar param `showAgentCard: bool = true` — combinar com `shouldShowAiCard`.

### A2.3 — `lib/screens/support_chat_screen.dart` (361 linhas)
- Já importa `BoraSupportSheet` (linha 11) ✅ — botão "Falar com humano" reutiliza.
- TextField input no _ChatInput (linha ~330). B2 inserirá `Padding(EdgeInsets.fromLTRB(16, 8, 16, 24))` + TextButton acima do input.

### A2.4 — `lib/providers/support_settings_provider.dart`
- ✅ Confirmed `enum SupportSettingsState { loading, loaded, error }` (linha 8).
- Getter `shouldShowAiCard` retorna `loaded && _supportAgentEnabled`.
- B2 fallback emergência: usar mesma lógica `state == loaded && support_agent_enabled` para Navigator.push; senão showModalBottomSheet.

### A2.5 — Catálogo screens com BoraSupportFab

⚠️ **Prompt disse 21, encontrei 22** (lista alfabética):

```
client_favorites_screen.dart, client_home_screen.dart, client_reservations_screen.dart,
driver_earnings_screen.dart, driver_home_screen.dart, driver_map_screen.dart,
notifications_screen.dart, order_details_screen.dart, order_tracking_screen.dart,
orders_screen.dart, partner_dashboard_screen.dart, partner_earnings_screen.dart,
partner_products_screen.dart, partner_reservations_screen.dart, profile_screen.dart,
referral_screen.dart, restaurant_dashboard_screen.dart, restaurant_menu_screen.dart,
restaurants_screen.dart, store_products_screen.dart, stores_screen.dart,
wallet_history_screen.dart
```

B2 NÃO altera assinatura `BoraSupportFab(orderId, position, heroTag)` — 22 screens não afectadas.

---

## A3 — Tokens discriminados por role

📊 Query retornou **vazio** (`SELECT role, COUNT(*) … FROM support_chatbot_messages`).

**Interpretação:** zero mensagens logadas — sistema 5A-2 nunca foi exercitado em runtime (pré-launch). Esperado.

**Implicação para B3:** RPC `admin_get_support_stats` deve devolver zeros sem crash quando não há dados. Critério de feito: período sem dados → JSON com `sessions_total: 0, tokens: {input:0,output:0,total:0}, cost_eur_estimated: 0, top_skills: null, escalating_skills: null`.

📋 **Não validável agora se `tokens_used` é discriminado por role** (sem dados). Sessão 5A-2 código indica que log_message guarda `tokens_used` em mensagens `assistant` (output) e potencialmente também em `user` (input). RPC B3 usa `FILTER (WHERE role='user')` / `(WHERE role='assistant')` — funciona se backend popula correctamente; se só `assistant` for populada, input_tokens=0 e custo só de output (subestimado). **TODO pós-launch:** validar com dados reais e ajustar fórmula.

---

## A4 — BLOCO 1 plano detalhado

✅ Validado contra estado actual:

```sql
-- 20260505_06_orders_is_test_order.sql
ALTER TABLE public.orders
  ADD COLUMN is_test_order BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX idx_orders_is_test_order
  ON public.orders(is_test_order) WHERE is_test_order=true;

COMMENT ON COLUMN public.orders.is_test_order IS
  'Marca pedidos teste pré-launch. Sessão 6, 2026-05-05.';

DO $$
DECLARE v_marked int;
BEGIN
  WITH updated AS (
    UPDATE public.orders SET is_test_order=true
    WHERE id IN (
      'b90966bf-31ca-4707-89c2-0cef4f9cc33a',
      '1c561ae0-34a9-4048-a2fc-88d2a168d5d5',
      '88e36c67-d2cf-47e3-a930-6a58166a6dff',
      '31a5ccd3-4596-4967-af96-181fbacca570'
    )
    RETURNING id
  )
  SELECT COUNT(*) INTO v_marked FROM updated;
  IF v_marked != 4 THEN
    RAISE EXCEPTION 'Expected 4 marked, got %. Aborting.', v_marked;
  END IF;
END$$;
```

**Risco:** baixíssimo. ALTER TABLE com DEFAULT false é metadata-only no Postgres 11+. Migration idempotente via `ADD COLUMN IF NOT EXISTS` — adicionar para safety.

---

## A5 — BLOCO 2 plano detalhado

### A5.1 — `bora_support_fab.dart` mudança onPressed

```dart
import 'package:provider/provider.dart';
import '../providers/support_settings_provider.dart';
import '../screens/support_chat_screen.dart';

void _open(BuildContext context) {
  final provider = context.read<SupportSettingsProvider>();
  if (provider.shouldShowAiCard) {
    // kill switch ON + state=loaded → chat IA directo
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportChatScreen(orderId: orderId),
      ),
    );
  } else {
    // fallback emergência: kill OFF / loading / error
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BoraSupportSheet(orderId: orderId),
    );
  }
}
```

### A5.2 — `bora_support_sheet.dart` adicionar param

```dart
class BoraSupportSheet extends StatelessWidget {
  const BoraSupportSheet({super.key, this.orderId, this.showAgentCard = true});
  final String? orderId;
  final bool showAgentCard;
  // ...
  // condição actual:
  if (provider.shouldShowAiCard) → if (showAgentCard && provider.shouldShowAiCard)
}
```

### A5.3 — `support_chat_screen.dart` botão "Falar com humano"

Inserir `Container` com `Padding(EdgeInsets.fromLTRB(16, 8, 16, 24))` + `TextButton(style: foregroundColor grey[600], fontSize 12)` **acima** do input TextField (cerca da linha ~325). onTap → `showModalBottomSheet(BoraSupportSheet(orderId, showAgentCard: false))`.

⚠️ **Aviso comportamento (importante para Danilo):** FAB do cliente passa a abrir CHAT IA directo. Quem espera o menu antigo vai notar — fallback BoraSupportSheet só aparece se kill switch OFF ou Provider em state=error/loading.

---

## A6 — BLOCO 3 plano detalhado

### A6.1 — Migration RPC `admin_get_support_stats`

Conforme prompt — SECURITY DEFINER, admin-only via `is_admin()`, REVOKE FROM public/anon, GRANT TO authenticated. Fórmula custo Gemini hardcoded: `(input/1M)*0.067 + (output/1M)*0.27` EUR (Flash 2026-05, USD→EUR ≈0.90).

**Validar `is_admin()` existe** em DB antes de aplicar — se ausente, fallback `auth.jwt() ->> 'email' IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')`.

### A6.2 — Screen `lib/screens/admin/admin_support_stats_screen.dart`

StatefulWidget. Date range default últimos 30 dias. Layout:
- AppBar "Estatísticas Suporte IA"
- DateRangePicker (default `now() - INTERVAL '30 days'` → `now()`)
- Grid 2x2: Sessões Totais · Taxa Resolução (% + barra verde) · Tickets Escalados · Custo Gemini (€ + tooltip in/out)
- Lista 1: top_skills (nome · usos · taxa sucesso)
- Lista 2: escalating_skills (nome · escalações · "atenção: melhorar")
- Loading/error/empty states

### A6.3 — Acesso à screen

Adicionar entrada no admin dashboard (a confirmar local exacto em B3 — provavelmente `admin_dashboard_screen.dart` ou similar).

---

## A7 — Análise de impacto

| Categoria | Quantidade | Risco |
|---|---|---|
| Migrations DB | 2 (BLOCO 1 + RPC BLOCO 3) | 🟢 baixo |
| Ficheiros Dart novos | 1 (`admin_support_stats_screen.dart`) | 🟢 baixo |
| Ficheiros Dart editados | 3 (fab, sheet, chat_screen) + 1 dashboard (route) | 🟡 médio (fluxo UX muda) |
| Smokes | 14 (S1-S14) | 🟢 baixo |

**Plano rollback:**
- BLOCO 1: `UPDATE orders SET is_test_order=false; DROP COLUMN is_test_order; DROP INDEX idx_orders_is_test_order;`
- BLOCO 2: revert 3 ficheiros Dart (`git checkout HEAD~1 -- lib/widgets/bora_support_fab.dart lib/widgets/bora_support_sheet.dart lib/screens/support_chat_screen.dart`)
- BLOCO 3: `DROP FUNCTION admin_get_support_stats;` + `git rm lib/screens/admin/admin_support_stats_screen.dart`

**Riscos colaterais identificados:**
1. Cliente clica FAB e espera menu antigo → vê chat IA. Mitigação: kill switch OFF retorna fluxo antigo.
2. RPC `admin_get_support_stats` falha se `is_admin()` ausente → validar antes de aplicar.
3. Tokens discriminados podem estar mal populados (zero msgs hoje impede validar) → custo aproximado.

---

## A8 — Skills + Sync + Próximos passos

📦 **Skills identificadas:** nenhuma nova nesta sessão.

📋 **Reports + Sync Obsidian** (pendente após luz verde):
- `06_housekeeping_audit.md` (este ficheiro) → cópia em `.obsidian-vault/sessões/`
- `06_housekeeping_report.md` (após Fase B) → idem
- Cópia prompt → `.obsidian-vault/sessões/06_prompt.md`

⏭ **TODOs adiados** (`todos/sessao_06_pending.md`):
- 4B geo-push (Firebase Service Account)
- Filtro admin "Esconder pedidos teste" em 3 dashboards (URGENTE — pré-launch)
- Admin support_skills CRUD + support_settings editor (5B)
- Push admin→cliente quando responde (5B), Resend SMTP outbound (5B)
- 5A-2-γ smokes UI device
- /ctx-upgrade npm PATH (v1.0.89 → v1.0.111 não aplica via CLI)
- MarketProduct dead code cleanup
- §32.4 tokens fórmula docs vs código
- 7 ordens órfãs históricas (4C TODO — refund? cleanup? — diferentes destes 4)
- Gemini pricing dinâmico via `support_settings.pricing_jsonb`
- Validar `tokens_used` discriminado por role (precisa dados reais)
- Validar `is_admin()` SQL function antes B3

---

## ⛔ STOP — Aguardar luz verde Danilo

**Próxima acção:** apenas após "go" do Danilo executar Fase B (B1 → B2 → B3 → smokes → relatório → sync).

**3 commits atómicos OU 1 atómico — Danilo decide depois.**
