# 📋 Sessão 6 — TODOs adiados

**Data:** 2026-05-05
**Sessão:** 6 (Housekeeping + UX Suporte + Estatísticas IA)

## 🔴 URGENTE pré-launch

- **Filtro admin "Esconder pedidos teste"** em 3 dashboards:
  - `lib/screens/admin/admin_orders_screen.dart`
  - `lib/screens/admin/admin_order_detail_screen.dart`
  - `lib/screens/admin/admin_driver_detail_screen.dart`
  - Filtro WHERE `is_test_order=false` por default + toggle "Mostrar testes".

- **7 ordens órfãs históricas** (4C TODO — diferentes dos 4 desta sessão):
  - Decisão Danilo: refund, cleanup, ou ignorar?
  - Sessão dedicada para análise + acção.

## 🟡 Próximas sessões

- **4B geo-push** (Firebase Service Account — bloqueado)
- **Admin support_skills CRUD** (5B)
- **Admin support_settings editor** (kill switch UI) (5B)
- **Push admin→cliente quando responde** (5B)
- **Resend / SMTP outbound email** (5B)
- **5A-2-γ smokes UI device** (Danilo configura)
- **Validar `tokens_used` discriminado por role** (precisa dados reais — vazio hoje)
- **Gemini pricing dinâmico** via `support_settings.pricing_jsonb` (hoje hardcoded RPC)
- **`withOpacity` polish** em `bora_support_sheet.dart:152` (warning pré-existente sessão 5A-2)
- **Auditoria `business_rules.md` formatos mistos** (`§N` vs `## N.` — drift silencioso documentação)
- **/ctx-upgrade npm PATH** (v1.0.89 → v1.0.111 não aplica via CLI)
- **MarketProduct dead code cleanup**
- **§32.4 tokens fórmula** docs vs código

## 🔵 Runtime testing pós-device

- Tap FAB cliente → chat IA abre directo (Navigator.push)
- Botão "Falar com humano" no chat → sheet WhatsApp+Email (showAgentCard:false)
- Admin abre stats screen → dados carregam (RPC + `is_admin()` real)
- Toggle kill switch OFF → fallback bottomSheet (menu antigo)
