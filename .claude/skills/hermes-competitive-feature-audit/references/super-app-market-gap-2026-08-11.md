# Bora App — Super-App Market Gap Analysis (2026-08-11)

**Date:** 2026-08-11
**Analyst:** Hermes Agent
**Method:** Internal knowledge (Córtex) + web research on 2025 super-app market leaders
**Scope:** Full vertical inventory vs. best-in-class super-apps (Grab, WeChat, Uber Eats, DoorDash, Instacart, Tata Neu)

---

## Context

Unlike the 2026-06-28 audit (codebase-only, focused on driver/client UI), this analysis
inventories **all Bora verticals** and compares against **market-level super-app features**
surfaced via web research (appscrip.com, octalsoftware.com, edana.ch, grepixit.com).

The super-app market is projected to grow from $127B (2025) to $915B (2033), CAGR ~27%.
Bora already operates as a 6-vertical super-app — above 90% of local-market competitors.

---

## Bora's Current Vertical Inventory (from Córtex)

| Vertical | Maturity | Status |
|---|---|---|
| Food delivery (parceiro) | 🟢 Produção | ACEITAR/PREPARAR/PRONTO/CHAMAR ESTAFETA complete |
| Mercado (não-parceiro) | 🟢 Produção | Scraping preço oficial, markup 15% |
| Favores/errands | 🟢 Produção | Fila de catálogo (Gemini) |
| TVDE (motorista) | 🟡 80% | Mapa giro, payment offline (kill switch) |
| Limpeza doméstica | 🟢 Produção | v1: booking, pagamento, chat, recorrência |
| Reservas (Restaurante) | 🟢 Produção | Floor plan, mesas, waitlist, €2 chegada |
| Serviços/Agendamentos | 🟢 Produção | Barbeiro etc., staff/provider |
| Wallet + Tokens | 🟢 Produção | 80/20, cashback, referral, promos |
| Dispatch engine | 🟢 Produção | Stacking 3, FIFO ≤200m, timeout 40s |
| Stripe (cartão + MB Way) | 🟢 Produção | Live, refund, charge-extra |
| Push (FG/BG/morto) | 🟢 Produção | CallKit, fullScreenIntent, notificação rica |

---

## Feature Gaps vs. Market Leaders

### Table-stakes (market leaders ALL have these)

| # | Feature | Bora? | Impact |
|---|---|---|---|
| 1 | GPS tracking em tempo real do estafeta (delivery) | ⚠️ Parcial (TVDE sim) | Alto |
| 2 | Reembolso parcial (item em falta) | ❌ Só full refund | Alto |
| 3 | Agendamento de pedidos ("para as 19h") | ❌ | Médio |
| 4 | Apple Pay / Google Pay | ❌ (só cartão + MB Way) | Alto |
| 5 | IA: recomendações personalizadas | ❌ | Alto |
| 6 | Substituição automática de item fora de stock | ❌ (toggle só) | Médio |
| 7 | Chat cliente ↔ estafeta in-app | ⚠️ Existe, não confirmado no fluxo | Médio |
| 8 | Onboarding guiado (tutorial primeiro uso) | ❌ | Médio |

### Differentiators (market leaders are pushing in 2025)

| # | Feature | Bora? | Impact |
|---|---|---|---|
| 9 | Gamification (missões, selos, streaks) | ❌ | Médio |
| 10 | Grupo/pedidos em conjunto (group orders) | ❌ | Médio |
| 11 | Programa de subscrição (Bora Pass) | ⚠️ Só TVDE | Alto |
| 12 | Analytics ao parceiro (vendas, picos) | ⚠️ Básico | Médio |
| 13 | Social: partilhar pedido, comentário público | ❌ | Baixo |
| 14 | Avaliação por item (não só por pedido) | ❌ | Baixo |
| 15 | Pesquisa com filtros avançados (dieta, preço, tempo) | ⚠️ Básico | Médio |

### Out-of-scope for Bora's market (not recommended now)

| # | Feature | Notes |
|---|---|---|
| 16 | Healthcare/Telemedicina | Super-apps asiáticas (Tata Neu); não alinhado com Bora |
| 17 | Pagamentos de contas (água, luz) | Paytm/WeChat; não alinhado |
| 18 | Rastreamento de encomendas 3rd party | Grab; não alinhado |
| 19 | Marketplace multi-vendedor (não restaurante) | Tata Neu; médio interesse para Bora |
| 20 | Carbon offset / embalagem sustentável | Tendência 2025; baixo para Guarda |

---

## Top 5 Prioritized (impact vs. effort)

| Pri | Feature | Why | Effort |
|---|---|---|---|
| 🔴 P1 | GPS tracking em tempo real (delivery) | Reduz ansiedade, menos cancels, estilo Uber | Médio |
| 🔴 P2 | Reembolso parcial (item em falta) | Guarda dinheiro, mercado faz por item | Médio |
| 🔴 P3 | Agendamento de pedidos | Captura clientes que planeiam, +ticket | Baixo |
| 🟠 P4 | Apple Pay / Google Pay | Reduz fricção no checkout | Médio |
| 🟠 P5 | IA: recomendações personalizadas | "Baseado nos teus pedidos: experimenta X" | Médio-alto |

---

## Internal Technical Gaps (from Córtex, flagged for attention)

| Gap | Risk | State |
|---|---|---|
| TVDE: race condition em `tvde_request_ride` (duas overloads) | Pode bloquear corridas CASH em prod | 🟡 PROPOSTA, sem "vai" |
| TVDE: tokens não aplicados no pagamento | Desconto falha | 🟡 PROPOSTA, sem "vai" |
| Limpeza: tokens aplicados em prod SEM migration no repo | Drift repo↔prod | 🟡 |
| 78 crashes/7d em agosto | Pode reprovar Play Store | 🔴 Alta |
| `auth.users` — Admin API HTTP 500 | Latente | 🟡 |
| `socio_kpi_tvde.corridas_completas=0` | Filtro de status errado | 🟡 |

---

## Sources Consulted

- appscrip.com/blog/super-app-for-multiple-services/ (2025-12-24) — super-app market size, revenue models
- octalsoftware.com/blog/rise-of-super-apps-key-features-driving-engagement (2025-10-09) — 5 key features
- edana.ch (2025-11-29) — delivery app UX/loyalty features
- grepixit.com — user retention strategies 2025
- Internal: Córtex pages — business-rules.md, mapa-de-fluxos, backend-map-tabelas, vertical-limpeza, tvde-tokens-payment-proposta

---

## Method

1. `cortex "business-rules"` + `cortex "mapa-de-fluxos"` + `cortex "vertical-limpeza"` + `cortex "TVDE"` → inventory Bora's current state
2. `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/https://duckduckgo.com/html/?q=..."` → find best 2025 super-app articles
3. `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/<article-url>"` → read each article in full
4. Cross-correlate Bora inventory with market feature lists → gap matrix
5. Classify by impact (Alto/Médio/Baixo) and effort

*End of analysis*