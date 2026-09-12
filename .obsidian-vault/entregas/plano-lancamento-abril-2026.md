# Plano de Lançamento — Bora App
**Data do plano:** 2026-04-17

---

## Lote 1 — GDPR & Cancelamento (CRÍTICO — bloqueador legal)

| # | Tarefa | Ficheiros | Esforço | Aprovação |
|---|---|---|---|---|
| 1.1 | Checkbox consentimento no registo | `register_*_screen.dart` + migration | Pequeno | — |
| 1.2 | Apagar conta (GDPR) | `profile_screen.dart` + Edge Function `delete-account` | Média | — |
| 1.3 | Banner de cookies | `lib/widgets/consent_banner.dart` + `main.dart` | Pequeno | — |
| 1.4 | Cancelamento pelo cliente | `order_model.dart`, `order_store.dart`, `stripe-webhook` | Média-grande | **OBRIGATÓRIA** |

---

## Lote 2 — Avaliações + Tips + Fotos (Alta — UX)

| # | Tarefa | Esforço | Aprovação |
|---|---|---|---|
| 2.1 | Foto obrigatória sendPackage/carryGroceries | Média | — |
| 2.2 | Ecrã de avaliação com etiquetas | Média | — |
| 2.3 | Gorjetas/Tips | Média-grande | **OBRIGATÓRIA** |

---

## Lote 3 — Driver Help + Reservas + Takeaway

| # | Tarefa |
|---|---|
| 3.1 | Botão "Preciso de Ajuda" (driver) |
| 3.2 | Reservas em restaurante parceiro |
| 3.3 | Takeaway (ir buscar) |

---

## 3 Maiores Riscos para Lançamento

### 🔴 Risco 1 — Stripe sem URL de produção
- `BACKEND_BASE_URL` defaultValue é `localhost:3000`
- Pagamento por cartão falha silenciosamente em produção
- **Ação:** configurar `BACKEND_BASE_URL` no build de produção + erro visível ao utilizador

### 🔴 Risco 2 — Realtime sync entre dispositivos
- Driver e cliente podem não ver o mesmo estado do pedido
- Identificado como "Current Focus" no CLAUDE.md
- **Ação:** resolver antes do lançamento

### 🔴 Risco 3 — Push Notifications desativadas
- Drivers com app em background não recebem ofertas
- Firebase desativado — dependem de polling/realtime com app aberta
- **Ação:** ativar Firebase com `google-services.json` antes do lançamento

---

## Estado das Features (Auditoria Abril 2026)

| Feature | Estado |
|---|---|
| Cardápio digital + Reservas | ❌ Falta |
| Takeaway em parceiros | ❌ Falta |
| Gorjetas / Tips | ❌ Falta |
| Avaliações com etiquetas | 🟡 Parcial |
| Driver Help | ❌ Falta |
| Cancelamento pelo cliente | ❌ Falta |
| Painel admin completo | 🟡 Parcial |
| GDPR | ❌ Falta |
| Foto sendPackage/carryGroceries | ❌ Falta |
| Câmara do mapa com bearing | 🟡 Parcial (sem QA físico) |
