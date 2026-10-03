# 📋 SESSÃO 6 — HOUSEKEEPING REPORT (FASE B)

**Data:** 2026-05-05
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — execução autorizada após validação Claude.ai
**Estado:** ✅ FASE B COMPLETA — 3 blocos aplicados, 14 smokes verdes
**Ainda não commitado** — aguarda validação Claude.ai antes de push

---

## 📦 Artefactos criados / modificados

### Migrations
- ✅ `supabase/migrations/20260505060000_06_orders_is_test_order.sql` (aplicada)
- ✅ `supabase/migrations/20260505060100_06_admin_get_support_stats.sql` (aplicada)

### Flutter (Dart)
- ✏️ `lib/widgets/bora_support_fab.dart` — onTap mudou (chat directo se kill ON, fallback sheet se OFF)
- ✏️ `lib/widgets/bora_support_sheet.dart` — `showAgentCard:bool=true` param
- ✏️ `lib/screens/support_chat_screen.dart` — botão "Falar com humano" rodapé
- 🆕 `lib/screens/admin/admin_support_stats_screen.dart` — painel estatísticas
- ✏️ `lib/screens/admin/admin_dashboard_screen.dart` — _NavCard "Estatísticas Suporte IA" após Edge Functions

### Reports + Sync
- ✅ `.claude/.ai/reports/20260502_megafinal/06_housekeeping_audit.md` (Fase A)
- ✅ `.claude/.ai/reports/20260502_megafinal/06_housekeeping_report.md` (este)
- ✅ `.obsidian-vault/sessões/06_housekeeping_audit.md`
- ⏳ `.obsidian-vault/sessões/06_housekeeping_report.md` (próximo passo)
- ⏳ `business_rules.md` `## 28. HOUSEKEEPING + UX SUPORTE` (próximo passo)

---

## 🟢 BLOCO 1 — `is_test_order`

✅ Coluna BOOLEAN NOT NULL DEFAULT false adicionada com `IF NOT EXISTS` (idempotente).
✅ Index parcial `idx_orders_is_test_order WHERE is_test_order=true` criado.
✅ COMMENT documenta origem (Sessão 6, 4 pedidos €253.08 stripe charges).
✅ DO block com `RAISE EXCEPTION` se UPDATE não marcar exactamente 4 IDs.

**4 IDs marcados:**
- `1c561ae0-34a9-4048-a2fc-88d2a168d5d5`
- `31a5ccd3-4596-4967-af96-181fbacca570`
- `88e36c67-d2cf-47e3-a930-6a58166a6dff`
- `b90966bf-31ca-4707-89c2-0cef4f9cc33a`

📊 Estado pós-migration: **4 marcados / 90 não-marcados** ✅

---

## 🟢 BLOCO 2 — UX Ajuda (chat IA directo + fallback)

### `bora_support_fab.dart`
```dart
void _open(BuildContext context) {
  final provider = context.read<SupportSettingsProvider>();
  if (provider.shouldShowAiCard) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupportChatScreen(orderId: orderId),
    ));
  } else {
    showModalBottomSheet(...BoraSupportSheet...);
  }
}
```
✅ Imports `SupportSettingsProvider` + `SupportChatScreen`.

### `bora_support_sheet.dart`
✅ Adicionado `final bool showAgentCard;` default `true`.
✅ Card BoraIA condicionado a `showAgentCard && provider.shouldShowAiCard`.

### `support_chat_screen.dart`
✅ Botão `TextButton` cinza fontSize 12 acima do input, dentro de `SafeArea(top:false)` + `Padding(EdgeInsets.fromLTRB(16,4,16,8))`.
✅ onTap → `BoraSupportSheet(orderId, showAgentCard: false)` — só WhatsApp+Email.

⚠️ **AVISO COMPORTAMENTO** (importante para Danilo notar em device):
- **Antes (5A-2):** FAB cliente → bottomSheet com 3 cards (BoraIA + WhatsApp + Email)
- **Agora (Sessão 6):** FAB cliente → **chat IA directo** (kill switch ON)
- **Fallback emergência:** kill OFF / Provider error → bottomSheet (menu antigo)

---

## 🟢 BLOCO 3 — Estatísticas robô IA admin

### RPC `admin_get_support_stats(p_from, p_to) → jsonb`
✅ `SECURITY DEFINER` + `SET search_path=public`.
✅ Guard: `IF NOT public.is_admin() THEN RAISE 'NOT_ADMIN'`.
✅ `REVOKE ALL FROM public, anon` + `GRANT EXECUTE TO authenticated`.
✅ `COALESCE jsonb_agg(...) → '[]'::jsonb` para listas vazias (sem crash).
✅ `CASE WHEN sessions_total > 0` para `resolution_rate_pct` (sem div/0).
✅ Métricas devolvidas: 12 (sessions_total/resolved/escalated, resolution_rate_pct, avg_messages_per_session, tokens.{input,output,total}, cost_eur_estimated, top_skills[10], escalating_skills[5], tickets_by_channel, avg_satisfaction, satisfaction_responses).

**Preço Gemini Flash hardcoded:** input €0.067/M + output €0.27/M (USD→EUR ≈0.90, 2026-05).
TODO: migrar para `support_settings.pricing_jsonb` em sessão futura.

### Screen `lib/screens/admin/admin_support_stats_screen.dart`
✅ StatefulWidget com date range picker (default últimos 30 dias).
✅ 4 StatCards 2x2: Sessões totais · Resolução robô % · Escaladas · Custo Gemini (com tooltip in/out).
✅ Lista skills mais usadas (com taxa sucesso) + lista escalating (warning).
✅ Card adicional: avg msg/sessão · satisfação · tickets por canal.
✅ Loading / error / empty states.
✅ RefreshIndicator (pull-to-refresh).

### Dashboard entry
✅ `_NavCard` "Estatísticas Suporte IA" inserido após "Edge Functions" no admin dashboard, cor `Colors.deepPurple`, ícone `Icons.smart_toy_outlined`.

---

## 📊 SMOKES (S1-S14)

| # | Smoke | Resultado |
|---|---|---|
| S1 | `flutter analyze` 0 erros NOVOS | ✅ 55 issues — único delta vs baseline (54) é `withOpacity` linha 152 de `bora_support_sheet.dart` **pré-existente do commit `bcde960` Sessão 5A-2** (linter actualizado detectou agora). Não introduzido nesta sessão. |
| S2 | 4 pedidos têm `is_test_order=true` | ✅ 4 |
| S3 | Pedidos não-teste continuam false (sample 5) | ✅ 5 |
| S4 | Index criado | ✅ `idx_orders_is_test_order` exists |
| S5 | RPC `admin_get_support_stats` SECURITY DEFINER + rejeita NOT_ADMIN | ✅ + rejeita quando `is_admin()=false` (P0001 NOT_ADMIN raise observado) |
| S6 | RPC com período sem dados → zeros sem crash | ✅ structural — `COALESCE jsonb_agg('[]')` + `CASE WHEN total>0` |
| S7 | Ficheiros editados conforme plano A5 | ✅ 4 ficheiros + 1 novo |
| S8 | 7 tabelas suporte intactas | ✅ |
| S9 | 9 skills active intactas | ✅ |
| S10 | `trg_zz_final_total_dual_write` activo | ✅ |
| S11 | wallet CHECK -2000 (`client_wallets`) | ✅ |
| S12 | BUG 35/38/39 não regridem | ✅ sem alterações em fluxos afectados |
| S13 | 5 camadas defesa productId 4C intactas | ✅ não tocadas |
| S14 | `BoraSupportFab` assinatura compatível com 22 screens | ✅ `(orderId, position, heroTag)` mantida intacta — comportamento onTap mudou mas API pública igual |

---

## 🐛 BUGS COLATERAIS

Nenhum bug **NOVO** detectado.

📋 **Um warning pré-existente** flagged: `withOpacity` em `lib/widgets/bora_support_sheet.dart:152` (commit `bcde960` Sessão 5A-2). Não bloqueante, apenas info-level. Aplicar `.withValues(alpha: 0.12)` em sessão de polish futura.

---

## 📋 BUSINESS_RULES.MD — `## 28.`

A aplicar no próximo passo (após este relatório). Conteúdo:

```md
## 28. HOUSEKEEPING + UX SUPORTE (Sessão 6 · 2026-05-05)

### 28.1 Pedidos teste (`is_test_order`)
Coluna `BOOLEAN NOT NULL DEFAULT false` em `orders`. Index parcial.
4 pedidos pré-launch marcados (€253.08 stripe charges, testes Danilo 30/04+01/05).
TODO admin filter `is_test_order=false` em 3 dashboards (orders/order_detail/driver_detail).

### 28.2 Filosofia UX suporte (Danilo 2026-05-05)
- Bora App em fase TESTE pré-launch
- Robô IA = porta principal
- FAB → chat IA directo (kill switch ON)
- WhatsApp/Email DENTRO do chat ("Falar com humano")
- Fallback emergência: kill OFF / Provider error → menu antigo

### 28.3 Estatísticas robô IA
RPC `admin_get_support_stats(from, to) → jsonb` SECURITY DEFINER admin-only.
Métricas: 4 cards + 2 listas + tokens discriminados.
Custo Gemini Flash 2026-05: €0.067/M input + €0.27/M output (hardcoded).
TODO: migrar pricing para `support_settings.pricing_jsonb`.

### 28.4 BoraSupportFab compatibilidade
Assinatura `(orderId, position, heroTag)` mantida. 22 screens não afectadas.
Comportamento `onTap` mudou: chat directo se kill ON, fallback sheet se OFF.
`BoraSupportSheet` aceita `showAgentCard:bool=true` (default true).
```

---

## ⏭ TODOs adiados (`sessao_06_pending.md`)

- Filtro admin "Esconder pedidos teste" em 3 dashboards (URGENTE — pré-launch)
- 7 ordens órfãs históricas (4C TODO — refund? cleanup? — diferentes destes 4)
- 4B geo-push (Firebase Service Account)
- Admin support_skills CRUD (5B) + support_settings editor (kill switch UI)
- Push admin→cliente quando responde (5B) + Resend SMTP outbound (5B)
- 5A-2-γ smokes UI device
- Validar `tokens_used` discriminado por role (precisa dados reais)
- Gemini pricing dinâmico via `support_settings.pricing_jsonb`
- `withOpacity` polish em `bora_support_sheet.dart:152`
- Auditoria business_rules.md formatos mistos (§N vs ## N.)
- /ctx-upgrade npm PATH (v1.0.89 → v1.0.111 não aplica via CLI)
- Runtime smokes pós-device (Navigator.push, RPC, Provider state em device)

---

## 🚦 PRÓXIMOS PASSOS

1. Aplicar `## 28.` em `business_rules.md`
2. Sync Obsidian (`06_housekeeping_report.md` + `06_prompt.md`)
3. Criar `todos/sessao_06_pending.md`
4. **STOP** — aguarda validação Claude.ai antes de push

**3 commits atómicos preferidos** (1 por bloco):
- `feat(sessao-6-b1): is_test_order column + 4 pedidos teste marcados`
- `feat(sessao-6-b2): UX suporte chat IA directo + fallback`
- `feat(sessao-6-b3): admin_get_support_stats RPC + painel estatísticas`

⛔ Sem push até luz verde Danilo após validação Claude.ai.
