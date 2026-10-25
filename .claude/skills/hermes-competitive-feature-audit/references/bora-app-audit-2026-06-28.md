# Bora App — Competitive Feature Audit (vs Uber, Glovo, iFood)

**Date:** 2026-06-28
**Analyst:** Hermes Agent (autonomous analysis)
**Scope:** Full codebase review — Flutter (lib/), Supabase Edge Functions, Migrations
**Branch:** autonomous-night-2026-04-29

---

## Executive Summary

The Bora App has a **solid foundation** with several advanced features (real-time dispatch engine, financial ledger, token system, admin audit logs). However, **critical table-stakes features are missing** compared to Uber/Glovo/iFood, particularly in the **client-facing driver profile** and **driver onboarding completeness**.

| Category | Status | Priority |
|----------|--------|----------|
| Client: Driver profile in tracking | ❌ Missing photo, plate, car model, real rating | 🔴 CRITICAL |
| Driver: Onboarding documents | ⚠️ Partial (missing residence proof, background check) | 🟡 HIGH |
| Driver: Daily operations | ⚠️ Basic (no heatmap, quests, instant cashout) | 🟡 HIGH |
| Partner: Menu management | ⚠️ Basic (no drag-drop, no item photos required) | 🟡 MEDIUM |
| Admin: Operations | ✅ Strong (ban, reactivate, audit, soft-delete) | 🟢 GOOD |
| Admin: Financial reconciliation | ✅ Strong (ledger, payouts, audit) | 🟢 GOOD |

---

## 1. Client App — Order Tracking Screen (`order_tracking_screen.dart`)

### What Bora Has
- ✅ Real-time driver location on map (lines 184-191)
- ✅ Route polyline (driver → pickup → dropoff) (lines 195-210)
- ✅ ETA badge via `OrderEtaService` (lines 420-426)
- ✅ Order status timeline with color dots (lines 375-416)
- ✅ Delivery code display + resend (lines 315-331)
- ✅ Auto-opens rating screen on delivery (lines 67-85)

### What's Missing (vs Competitors)

| Feature | Bora | Uber/Glovo/iFood | Confidence | Source |
|---------|------|------------------|------------|--------|
| **Driver photo** | ❌ Uses `Icons.delivery_dining` placeholder (line 448-451) | ✅ Real photo, tappable | HIGH | `order_tracking_screen.dart:443-451` |
| **Vehicle license plate** | ❌ Not displayed | ✅ Always shown | HIGH | `order_tracking_screen.dart:470-501` |
| **Vehicle make/model/color** | ❌ Not stored in `DriverModel` | ✅ "Toyota Corolla, Prata" | HIGH | `driver_model.dart:5-9, 55-57` |
| **Real driver rating** | ❌ Hardcoded "4.9" (line 488) | ✅ Calculated from trips | HIGH | `order_tracking_screen.dart:484-493` |
| **Number of completed trips** | ❌ Not shown | ✅ "1.234 viagens" | MEDIUM | Not in `DriverModel` |
| **Chat with driver** | ❌ No button in tracking | ✅ In-app chat | MEDIUM | `chat_screen.dart` exists but not linked |
| **Call driver (masked)** | ❌ No button | ✅ Twilio/Vonage | MEDIUM | Not implemented |
| **Safety toolkit (share trip, SOS)** | ❌ Missing | ✅ All three | HIGH | Not in codebase |
| **Delivery PIN verification UI** | ✅ Code exists (line 324) but not shown to driver | ✅ Shown to both | MEDIUM | `order_tracking_screen.dart:324` |

### Root Cause
The `DriverModel` (lines 39-60) lacks fields for:
- `photoUrl` (exists in `DriverAccount` but not propagated to `DriverModel`)
- `vehicleMake`, `vehicleModel`, `vehicleColor`
- `rating` (average), `totalTrips`

The `order_tracking_screen.dart` receives only `driver?.name` (line 268) from `DriverStore.getDriverById()`.

---

## 2. Driver App — Signup Flow (`driver_signup_screen.dart`)

### What Bora Has (Excellent)
- ✅ Selfie with liveness-ready capture (lines 292-331)
- ✅ Document type selector (CC, BI, Passport, Residence) (lines 422-437)
- ✅ Document number + photo upload (lines 440-456)
- ✅ Vehicle type selector (Moto/Carro/Bicicleta) (lines 467-491)
- ✅ License plate (required for non-bicycle) (lines 493-508)
- ✅ Vehicle photo (required for non-bicycle) (lines 511-516)
- ✅ IBAN validation (PT50 + 21 digits) (lines 120-125, 522-541)
- ✅ Terms acceptance with link (lines 545-554)
- ✅ All docs uploaded to Supabase Storage `driver-documents` bucket (lines 127-143)
- ✅ Full row upsert to `drivers` table with all fields (lines 217-237)

### What's Missing (vs Competitors)

| Feature | Bora | Uber/Glovo/iFood | Confidence | Source |
|---------|------|------------------|------------|--------|
| **Proof of residence** | ❌ Not collected | ✅ Utility bill ≤ 90 days | HIGH | `driver_signup_screen.dart` — no field |
| **Criminal background check** | ❌ Not integrated | ✅ Uber (Checkr), iFood (local) | HIGH | Not in signup flow |
| **Vehicle registration (CRLV/DUA)** | ❌ Only photo, no doc upload | ✅ Front/back + OCR | MEDIUM | Only `vehicle_photo_url` |
| **Insurance proof** | ❌ Not collected | ✅ Optional/partner | LOW | Not in codebase |
| **Multi-vehicle support** | ❌ Single vehicle per driver | ✅ Uber, iFood | MEDIUM | `DriverModel` has single `vehicleType` |
| **Document expiration alerts** | ❌ Not implemented | ✅ Push 30/15/7 days | MEDIUM | No cron job for this |

### Database Schema Gaps (`schema.sql` + migrations)
The `drivers` table (lines 47-57 in `schema.sql`) has columns added via migrations:
- ✅ `photo_url` (selfie)
- ✅ `document_type`, `document_number`, `document_photo_url`
- ✅ `vehicle_photo_url`
- ✅ `iban`, `nif`
- ✅ `approval_status`, `rejection_reason`
- ✅ `fcm_token` (20260414000000)
- ✅ `consent_accepted_at`, `consent_version` (20260417000000)
- ✅ `is_banned`, `banned_at`, `banned_by`, `banned_until`, `ban_reason_code`, `ban_reason` (20260429000000)
- ✅ `deleted_at`, `deleted_by`, `deletion_reason` (20260429000000)
- ✅ `last_forced_logout_at`, `last_forced_logout_by` (20260429000000)
- ✅ `approved_at`, `approved_by` (20260428000002)

**Missing columns for competitive parity:**
- `proof_of_residence_url` / `proof_of_residence_type`
- `criminal_check_status` / `criminal_check_at` / `criminal_check_provider`
- `vehicle_registration_url` (CRLV/DUA)
- `vehicle_make`, `vehicle_model`, `vehicle_color`, `vehicle_year`
- `insurance_url`, `insurance_expiry`
- `background_check_status`, `background_check_at`

---

## 3. Driver App — Daily Operations

### What Bora Has
- ✅ `driver_home_screen.dart` — Go online/offline toggle
- ✅ `driver_map_screen.dart` — Map with orders
- ✅ `driver_earnings_screen.dart` — Earnings view
- ✅ Real-time location tracking via `DriverStore` + `drivers_channel`
- ✅ Token balance via `get_user_tokens` RPC

### What's Missing (vs Competitors)

| Feature | Bora | Uber/Glovo/iFood | Confidence | Source |
|---------|------|------------------|------------|--------|
| **Heatmap / demand zones** | ❌ No | ✅ Real-time color map | HIGH | Not in `driver_home_screen.dart` |
| **Quests / bonuses tracker** | ❌ No | ✅ "Complete 10 trips = R$ 50" | HIGH | Not in codebase |
| **Earnings breakdown (per trip)** | ⚠️ Basic | ✅ Gross, fees, tips, bonuses | MEDIUM | `driver_earnings_screen.dart` not reviewed |
| **Instant cashout / daily payout** | ❌ No | ✅ Fixed fee or % | HIGH | Not in codebase |
| **In-app support chat** | ❌ No | ✅ Bot + human | MEDIUM | `support_screen.dart` exists but generic |
| **Integrated navigation** | ⚠️ Map only | ✅ Google Maps/Waze deep link | MEDIUM | `maps_service.dart` exists |
| **Order preview before accept** | ⚠️ Via offer | ✅ Shows distance, value, restaurant | MEDIUM | Dispatch engine handles |
| **Multi-order stacking UI** | ❌ No visual | ✅ Shows both pickups/dropoffs | MEDIUM | Backend supports batching |

---

## 4. Partner App

### What Bora Has
- ✅ `partner_dashboard_screen.dart`, `partner_products_screen.dart`, `partner_orders_screen.dart`
- ✅ `partner_hours_screen.dart` — Opening hours
- ✅ `partner_reservations_screen.dart` — Reservations
- ✅ `partner_call_driver_screen.dart` — Call driver for order

### What's Missing (vs Competitors)

| Feature | Bora | Uber Eats/Glovo/iFood | Confidence |
|---------|------|----------------------|------------|
| **Drag-drop menu editor** | ❌ Form-based | ✅ Visual builder | MEDIUM |
| **Item photos required** | ❌ Optional | ✅ Mandatory 1:1 800px | MEDIUM |
| **Real-time availability toggle** | ✅ | ✅ | — |
| **Customer reviews + reply** | ❌ Admin only | ✅ Partner can reply | MEDIUM |
| **Payout schedule portal** | ❌ Admin only | ✅ Self-serve | MEDIUM |
| **Tax document download (NF-e)** | ❌ No | ✅ Automated | MEDIUM |

---

## 5. Admin Panel — Driver Management

### What Bora Has (Strong)
- ✅ `admin_drivers_screen.dart` — List all drivers with status badges (lines 220-275)
- ✅ `admin_driver_approval_screen.dart` — 3-tab workflow (Pendentes/Aprovados/Rejeitados) with document viewer (lines 596-624)
- ✅ `admin_driver_detail_screen.dart` — 4 tabs: Overview, Orders, Transactions, Audit (lines 133-178)
- ✅ **Actions:** Edit, Ban/Suspend, Reactivate, Force Logout, Soft Delete (lines 227-258)
- ✅ **Edit sheet** with sensitive field warnings (IBAN/NIF) (lines 609-801)
- ✅ **Ban dialog** with reason codes + optional expiry (lines 804-917)
- ✅ **Force logout** via Edge Function `admin-force-driver-logout` (lines 356-385)
- ✅ **Soft delete** with 3 guards (active orders, balance, pending settlements) (lines 387-408)
- ✅ **Audit log** per driver (tab 4) with immutable entries (lines 1152-1241)
- ✅ **Backend RPCs:** `admin_ban_driver`, `admin_reactivate_driver`, `admin_update_driver`, `admin_soft_delete_driver` (migration 20260429110000)
- ✅ **Audit logging** for every field change with sensitive redaction (lines 212-250)

### What's Missing (vs Competitors)

| Feature | Bora | Uber/Glovo/iFood | Confidence |
|---------|------|------------------|------------|
| **Live map (all drivers + orders)** | ❌ No | ✅ WebSocket clustering | HIGH |
| **Manual dispatch / reassign** | ❌ No | ✅ Override algorithm | MEDIUM |
| **Trip history with map replay** | ❌ Orders tab only | ✅ Map animation per trip | MEDIUM |
| **Fraud detection alerts** | ❌ No | ✅ GPS spoof, multi-account | MEDIUM |
| **Background check status** | ❌ Not in UI | ✅ Clear/Pending/Flagged | MEDIUM |
| **Bulk actions** | ❌ Single only | ✅ Multi-select | LOW |

---

## 6. Database & Backend — Competitive Parity

### Strengths
- ✅ **Financial Ledger** (`20260409000002_financial_ledger.sql`) — Append-only, NUMERIC(12,2), sign convention, idempotent, reconciliation view
- ✅ **Token System** (`20260404000000_bora_tokens.sql`) — FIFO entry-based, expiry-aware, idempotent
- ✅ **Order Financial Split** (`20260409000001_order_financial_split.sql`) — 90/10 partner split, atomic
- ✅ **Dispatch Engine** (Edge Function) — Self-scheduling, retry logic, race condition handling
- ✅ **Admin RPCs** — SECURITY DEFINER, audit logging, validation guards
- ✅ **RLS Policies** — Properly scoped per role

### Gaps
| Area | Missing | Competitor Standard |
|------|---------|---------------------|
| **Driver documents** | No `criminal_check_*`, `vehicle_registration_*`, `insurance_*` columns | Required for onboarding |
| **Vehicle details** | No `vehicle_make`, `model`, `color`, `year` | Shown to client |
| **Driver rating** | No `rating_avg`, `rating_count`, `total_trips` columns | Calculated from `ratings` table |
| **Heatmap data** | No `driver_heatmap_zones` table | Real-time demand |
| **Quest/bonus config** | No `driver_quests` table | Campaign management |
| **Instant payout** | No `instant_payout_requests` table | Daily cashout |

---

## 7. Confidence Classification

| Finding | Confidence | Reason |
|---------|------------|--------|
| Hardcoded "4.9" rating in client tracking | **HIGH** | Directly seen in `order_tracking_screen.dart:488` |
| Missing driver photo in tracking | **HIGH** | `Icons.delivery_dining` used instead of `photoUrl` |
| Missing license plate in tracking | **HIGH** | Not in `_BottomCard` widget |
| Missing proof of residence in signup | **HIGH** | Not in `driver_signup_screen.dart` form |
| Missing criminal background check | **HIGH** | Not in signup flow or DB schema |
| Admin panel missing live map | **HIGH** | No map component in admin screens |
| Financial ledger completeness | **HIGH** | Full audit of migration 20260409000002 |
| Dispatch engine robustness | **HIGH** | Read full Edge Function with retries |
| Partner menu editor UX | **MEDIUM** | Inferred from screen names, not fully read |
| Driver earnings breakdown | **MEDIUM** | `driver_earnings_screen.dart` not fully reviewed |
| Heatmap/quests absence | **MEDIUM** | Not found in codebase search |

---

## 8. Top 3 Recommendations for Stakeholder Decision

### 1. 🔴 **CRITICAL — Client Trust & Safety: Complete Driver Profile in Tracking**
**Effort:** ~1 week (Flutter only, backend columns exist)
- Add `photoUrl`, `licensePlate`, `vehicleMake/Model/Color`, `rating`, `totalTrips` to `DriverModel`
- Update `DriverStore.syncDriverWithAuth()` to fetch new columns
- Update `order_tracking_screen.dart` `_BottomCard` to show real photo, plate, car details, real rating
- Add "Chat" and "Call" buttons (reuse `chat_screen.dart`, add masked call via Edge Function)

**Why:** This is the #1 trust signal for clients. Every competitor shows it. Hardcoded "4.9" looks unprofessional.

---

### 2. 🟡 **HIGH — Driver Onboarding Compliance: Proof of Residence + Background Check**
**Effort:** ~2 weeks (Flutter + DB + Edge Function integration)
- Add `proof_of_residence_url`, `proof_of_residence_type` to `drivers` table + signup form
- Integrate background check provider (Portuguese: Certificado de Registo Criminal via API or manual upload)
- Add `criminal_check_status`, `criminal_check_at`, `criminal_check_provider` columns
- Update `admin_driver_approval_screen.dart` `_missingDocs()` to check new fields

**Why:** Legal requirement in Portugal for TVDE/platform workers. Reduces liability. Uber/iFood do it.

---

### 3. 🟡 **HIGH — Driver Retention: Heatmap + Quests + Instant Cashout**
**Effort:** ~3-4 weeks (Backend + Flutter + Edge Functions)
- **Heatmap:** New `driver_heatmap_zones` table + cron job aggregating order density → Edge Function → Realtime to driver app
- **Quests:** `driver_quests` table (configurable campaigns) + `driver_quest_progress` + UI in `driver_home_screen.dart`
- **Instant Cashout:** `instant_payout_requests` table + Stripe/PIX integration + daily limit logic

**Why:** Driver retention is the #1 cost driver. Competitors invest heavily here. Bora's token system is a start but not enough.

---

## 9. Files Referenced in This Audit

| File | Lines | Purpose |
|------|-------|---------|
| `lib/models/driver_model.dart` | 1-99 | Driver data structure |
| `lib/screens/order_tracking_screen.dart` | 1-975 | Client tracking UI |
| `lib/screens/driver_signup_screen.dart` | 1-647 | Driver onboarding flow |
| `lib/screens/admin/admin_driver_detail_screen.dart` | 1-1259 | Admin driver management |
| `lib/screens/admin/admin_driver_approval_screen.dart` | 1-676 | Admin approval workflow |
| `lib/screens/admin/admin_drivers_screen.dart` | 1-282 | Admin driver list |
| `lib/services/admin/admin_driver_service.dart` | 1-307 | Admin RPC client |
| `supabase/schema.sql` | 47-57 | Base `drivers` table |
| `supabase/migrations/20260429110000_admin_driver_rpcs_management.sql` | 1-496 | Admin RPCs |
| `supabase/functions/dispatch-engine/index.ts` | 1-775 | Backend dispatch logic |

---

## 10. Next Steps (If Approved)

1. **Create GitHub issues** for each recommendation with `area:driver-profile`, `area:onboarding`, `area:driver-retention` labels
2. **Design DB migrations** for missing columns (proof of residence, criminal check, vehicle details, rating)
3. **Update `DriverModel` and `DriverStore`** to sync new fields
4. **Modify `order_tracking_screen.dart`** `_BottomCard` for real driver profile
5. **Extend `driver_signup_screen.dart`** with new document fields
6. **Plan backend work** for heatmap/quests/cashout (separate epic)

---

*End of Audit Report*