---
name: hermes-competitive-feature-audit
description: Systematically analyze a codebase against competitor products (Uber, Glovo, iFood, etc.) to identify feature gaps, UX inconsistencies, and missing functionality across user roles (client, driver, partner, admin).
category: software-development
---

# Competitive Feature Audit

**Purpose:** Systematically analyze a codebase against competitor products (Uber, Glovo, iFood, etc.) to identify feature gaps, UX inconsistencies, and missing functionality across user roles (client, driver, partner, admin).

## Trigger
- User asks to "compare with Uber/Glovo/iFood" or "what's missing"
- New feature area needs validation against market leaders
- Pre-release audit to ensure competitive parity

## Methodology

### 1. Map Current State (Codebase OR Knowledge Base)
- **Models** → What data structures exist (`DriverModel`, `OrderModel`, etc.)
- **Screens** → What UI flows exist per role (list all `*_screen.dart`)
- **Services** → What business logic exists (`DispatchService`, `PricingService`, etc.)
- **Admin** → What management tools exist (`admin_*_screen.dart`)
- **Database** → Full schema via migrations + `schema.sql`
- **For Bora**: prefer `cortex "<topic>"` over reading raw files when available — Córtex pages are condensed and canonical. Use `cortex INDEX` to discover available pages.

### 1b. Map Market State (Web Research — for gap Analysis)

Two flavors of audit:
- **Codebase-vs-competitor** (original): read Flutter/Supabase source, compare to known competitor feature sets.
- **Market gap analysis** (broader): inventory ALL current verticals from the knowledge base, then research what market leaders (Grab, WeChat, Uber Eats, DoorDash, Instacart, Tata Neu) offer in 2025 via web research. Produces a full feature-gap matrix across the whole product, not just one role's UI.

For the market variant:
1. Read internal knowledge (`cortex`) to inventory what the product already has per vertical.
2. Web research sequence (verified working 2026-08-11):
   - `terminal: websearch "<query>"` first (fast, SearXNG).
   - If `readpage`/Jina fails a specific site (CAPTCHA, 403), fall back to DuckDuckGo: `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/https://duckduckgo.com/html/?q=<query>"` → harvest result links. Jina Reader/Görli block `google.com` domain due to abuse — do NOT use Google search URLs.
   - Read each promising article: `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/<article-url>"` → full markdown.
3. Cross-correlate internal inventory with market feature lists → gap matrix.
4. Classify gaps: **table-stakes** (all leaders have), **differentiators** (leaders pushing), **out-of-scope** (not aligned with product market).
5. Prioritize by impact (Alto/Médio/Baixo) vs. effort (Baixo/Médio/Alto).

### 2. Define Competitor Baseline
For each role, list what market leaders provide:
- **Client app:** Real-time tracking, driver photo/plate/car model, rating, ETA, chat/call, safety features
- **Driver app:** Earnings breakdown, heatmap, quests/bonuses, document management, support chat
- **Partner app:** Order management, menu editing, analytics, payout schedule
- **Admin panel:** Full CRUD, audit logs, financial reconciliation, fraud tools, map view

### 3. Gap Analysis Matrix
| Area | Bora Has | Uber Has | Glovo Has | iFood Has | Gap Severity |
|------|----------|----------|-----------|-----------|--------------|
| Driver photo in tracking | ❌ | ✅ | ✅ | ✅ | HIGH |
| Vehicle plate in tracking | ❌ | ✅ | ✅ | ✅ | HIGH |
| Driver rating display | Hardcoded 4.9 | ✅ Real | ✅ Real | ✅ Real | HIGH |
| Chat/Call driver | ❌ | ✅ | ✅ | ✅ | MEDIUM |
| Proof of residence (signup) | ❌ | ✅ | ✅ | ✅ | MEDIUM |
| Criminal background check | ❌ | ✅ | ❌ | ✅ | MEDIUM |
| Admin: document viewer | ✅ (approval) | ✅ | ✅ | ✅ | LOW |
| Admin: trip history per driver | ❌ | ✅ | ✅ | ✅ | MEDIUM |
| Admin: financial reports | Partial | ✅ | ✅ | ✅ | MEDIUM |

### 4. Report Output
Deliver a structured report with:
1. **Branch/PR** (if fixes applied)
2. **Fixed** (file + what + why + confidence)
3. **Found but NOT fixed** (zone red / low confidence)
4. **Top 3 recommendations** for stakeholder decision

## Pitfalls
- ❌ Don't guess competitor features — verify from actual apps or public docs
- ❌ Don't conflate "nice to have" with "table stakes" — classify by severity
- ❌ Don't skip database schema — many gaps are backend columns not exposed in Flutter
- ❌ Don't modify code during audit — this is ANALYSIS ONLY unless explicitly asked
- ✅ Always cite source files (line numbers) for every claim
- ✅ Classify confidence: HIGH (seen in code), MEDIUM (inferred), LOW (speculative)

## References
- `references/bora-app-audit-2026-06-28.md` — Full audit of Bora App vs Uber/Glovo/iFood (codebase-vs-competitor variant)
- `references/super-app-market-gap-2026-08-11.md` — Bora vs. 2025 super-app market leaders (market gap variant, full vertical inventory + web research)
- `references/competitor-baseline.md` — Documented competitor feature sets (update quarterly)