# Competitor Feature Baseline (Uber / Glovo / iFood)

**Last updated:** 2026-06-28
**Source:** Public documentation, app store screenshots, driver/partner portals, industry knowledge.
**Review quarterly.**

---

## Client App (Rider/Customer)

### Core Tracking & Visibility
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Real-time driver location on map | ✅ | ✅ | ✅ | WebSocket / Realtime |
| Driver photo | ✅ | ✅ | ✅ | Circle avatar, tappable for full size |
| Driver name | ✅ | ✅ | ✅ | Full name |
| Vehicle license plate | ✅ | ✅ | ✅ | Critical for verification at pickup |
| Vehicle make/model/color | ✅ | ✅ | ✅ | "Toyota Corolla, Prata, ABC-1234" |
| Driver rating (numeric + stars) | ✅ 4.92 | ✅ 4.8 | ✅ 4.7 | Calculated from last 500 trips |
| Number of trips completed | ✅ | ✅ | ✅ | "1,234 viagens" |
| ETA (min) + dynamic update | ✅ | ✅ | ✅ | Recalculates every 10-30s |
| Route polyline (driver → pickup → dropoff) | ✅ | ✅ | ✅ | Different colors per segment |
| Chat with driver (in-app) | ✅ | ✅ | ✅ | Pre-defined quick messages + free text |
| Call driver (masked number) | ✅ | ✅ | ✅ | Twilio / Vonage / SIP |
| Safety toolkit (share trip, emergency button) | ✅ | ✅ | ✅ | iFood: "Botão do Pânico" |
| Order status timeline | ✅ | ✅ | ✅ | Preparando → A caminho → Entregue |
| Delivery code / PIN verification | ✅ | ✅ | ✅ | 4-digit code shown to driver |

### Post-Delivery
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Rate driver (1-5 stars + tags) | ✅ | ✅ | ✅ | Tags: "Simpático", "Rápido", "Veículo limpo" |
| Tip driver (preset + custom) | ✅ | ✅ | ✅ | Before/after delivery |
| Receipt with breakdown | ✅ | ✅ | ✅ | Subtotal, taxa, gorjeta, total |
| Order history with filters | ✅ | ✅ | ✅ | Por data, restaurante, valor |

---

## Driver App (Courier)

### Onboarding & Documents
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Selfie / face match | ✅ | ✅ | ✅ | Liveness detection |
| CNH / Driver's license upload | ✅ | ✅ | ✅ | Front + back, OCR validation |
| Vehicle registration (CRLV/DUA) | ✅ | ✅ | ✅ | Photo or PDF |
| Vehicle inspection photo | ✅ | ✅ | ✅ | 4 angles + odometer |
| Proof of residence | ✅ | ✅ | ✅ | Utility bill ≤ 3 months |
| Criminal background check | ✅ | ❌ | ✅ | Uber: Checkr; iFood: parceiro local |
| Bank account / IBAN / PIX | ✅ | ✅ | ✅ | Validated via micro-deposit |
| Insurance proof (optional) | ✅ | ❌ | ✅ | App-based insurance partners |

### Daily Operations
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Go online/offline toggle | ✅ | ✅ | ✅ | Large button, haptic feedback |
| Heatmap / demand zones | ✅ | ✅ | ✅ | Real-time, color-coded |
| Quest / bonus tracker | ✅ | ✅ | ✅ | "Complete 10 trips = R$ 50" |
| Earnings dashboard (daily/weekly) | ✅ | ✅ | ✅ | Gross, fees, tips, bonuses |
| Trip history with filters | ✅ | ✅ | ✅ | Por data, tipo, valor |
| Instant cashout / daily payout | ✅ | ✅ | ✅ | Taxa fixa ou % |
| Support chat (in-app) | ✅ | ✅ | ✅ | Bot + human handoff |
| Navigation (integrated) | ✅ | ✅ | ✅ | Google Maps / Waze deep link |
| Order details before accept | ✅ | ✅ | ✅ | Distância, valor estimado, restaurante |
| Multi-order stacking (batching) | ✅ | ✅ | ✅ | Visual: shows both pickups/dropoffs |

### Vehicle & Profile
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Multiple vehicles per driver | ✅ | ❌ | ✅ | Switch in app |
| Vehicle requirements by category | ✅ | ✅ | ✅ | Moto: ≤ 5 anos; Carro: ≤ 10 anos |
| Profile photo management | ✅ | ✅ | ✅ | Camera + gallery |
| Document expiration alerts | ✅ | ✅ | ✅ | Push 30/15/7 days before |

---

## Partner App (Restaurant/Store)

### Order Management
| Feature | Uber Eats | Glovo | iFood | Notes |
|---------|-----------|-------|-------|-------|
| New order sound + vibration | ✅ | ✅ | ✅ | Customizable |
| Accept/Reject with timer | ✅ | ✅ | ✅ | 60-120s default |
| Preparation time editor | ✅ | ✅ | ✅ | "Pronto em 15 min" |
| Order status: Confirm → Preparing → Ready | ✅ | ✅ | ✅ | One-tap transitions |
| Direct chat with customer | ✅ | ✅ | ✅ | Pre-defined messages |
| Direct chat with driver | ✅ | ✅ | ✅ | After assignment |
| Cancel order (with reason) | ✅ | ✅ | ✅ | Impacts metrics |

### Menu & Catalog
| Feature | Uber Eats | Glovo | iFood | Notes |
|---------|-----------|-------|-------|-------|
| Menu editor (categories, items, modifiers) | ✅ | ✅ | ✅ | Drag-drop, bulk edit |
| Photos for items (required) | ✅ | ✅ | ✅ | Guidelines: 1:1, 800px |
| Availability toggle (item/category) | ✅ | ✅ | ✅ | Real-time |
| Pricing rules (markup, promo) | ✅ | ✅ | ✅ | Platform handles promos |
| Nutritional info / allergens | ✅ | ❌ | ✅ | iFood: obrigatório p/ alguns |

### Analytics & Finance
| Feature | Uber Eats | Glovo | iFood | Notes |
|---------|-----------|-------|-------|-------|
| Sales dashboard (real-time) | ✅ | ✅ | ✅ | Orders, revenue, avg ticket |
| Customer ratings & reviews | ✅ | ✅ | ✅ | Reply to reviews |
| Payout schedule & history | ✅ | ✅ | ✅ | Weekly, daily, instant |
| Commission breakdown | ✅ | ✅ | ✅ | Per order, per period |
| Tax documents (NF-e, DARF) | ✅ | ✅ | ✅ | Download portal |

---

## Admin Panel (Platform Operations)

### Driver Management
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| List/search all drivers | ✅ | ✅ | ✅ | Filters: status, city, vehicle, rating |
| Driver detail view | ✅ | ✅ | ✅ | Docs, trips, earnings, audit log |
| Approve/Reject with reason | ✅ | ✅ | ✅ | Bulk actions |
| Ban / Suspend / Reactivate | ✅ | ✅ | ✅ | Temporary or permanent |
| Force logout (revoke sessions) | ✅ | ✅ | ✅ | Immediate |
| Document viewer (zoom, rotate) | ✅ | ✅ | ✅ | Side-by-side comparison |
| Background check status | ✅ | ❌ | ✅ | Clear / Pending / Flagged |
| Trip history per driver | ✅ | ✅ | ✅ | Map replay, earnings per trip |
| Earnings & payout management | ✅ | ✅ | ✅ | Manual adjustments, bonuses |

### Order & Operations
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Live map (all drivers + orders) | ✅ | ✅ | ✅ | WebSocket, clustering |
| Order search & detail | ✅ | ✅ | ✅ | By ID, phone, email, status |
| Manual dispatch / reassign | ✅ | ✅ | ✅ | Override algorithm |
| Cancellation with fee logic | ✅ | ✅ | ✅ | Configurable per stage |
| Incident / support tickets | ✅ | ✅ | ✅ | SLA tracking |
| Fraud detection (GPS spoof, multi-account) | ✅ | ✅ | ✅ | ML-based alerts |

### Financial & Reconciliation
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Partner payout ledger | ✅ | ✅ | ✅ | Per restaurant, per period |
| Driver payout ledger | ✅ | ✅ | ✅ | Gross, fees, tips, adjustments |
| Platform revenue dashboard | ✅ | ✅ | ✅ | Take rate, GMV, net revenue |
| Tax compliance (NF-e, ISS, IR) | ✅ | ✅ | ✅ | Automated generation |
| Chargeback / dispute management | ✅ | ✅ | ✅ | Evidence submission |

### Audit & Compliance
| Feature | Uber | Glovo | iFood | Notes |
|---------|------|-------|-------|-------|
| Admin audit log (immutable) | ✅ | ✅ | ✅ | Who did what, when, before/after |
| Role-based access (RBAC) | ✅ | ✅ | ✅ | Superadmin, ops, finance, support |
| GDPR / LGPD tools | ✅ | ✅ | ✅ | Data export, deletion, consent log |
| API rate limiting & monitoring | ✅ | ✅ | ✅ | Grafana / Datadog |

---

## Scoring Legend
- ✅ = Fully implemented, production-grade
- ⚠️ = Partial / basic implementation
- ❌ = Missing entirely
- 🔄 = In development / planned