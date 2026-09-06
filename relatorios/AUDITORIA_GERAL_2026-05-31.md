# 🔍 AUDITORIA GERAL CONSOLIDADA — Bora App
> Data: 2026-05-31 · Modo: PROTECÇÃO TOTAL (read-only + correções 100% seguras) · Orquestrador: CEO-AI
> Método: 15 analistas paralelos (2 workflows + 1 agente dedicado) cruzando código Flutter, Edge Functions, migrations, skills, knowledge, CI e a **DB real** (Supabase `ojykpzwqrtusfeakzrna`).
> Nada em zona proibida foi tocado. Nenhuma migration aplicada. Nenhum ficheiro de código alterado.

---

## 1. CROQUI DE COBERTURA (Passo 0 — auto-revisto)

```
projetosflutter/
├─ bora_app/                         ← RAIZ Flutter + git (branch autonomous-night-2026-04-29)
│  ├─ lib/  (264 .dart)
│  │  ├─ screens/      127  (admin 50 · avulsos 60 · client 8 · partner 8 · market 1)
│  │  ├─ widgets/       45  (+ bora/ + market/ + admin/ + takeaway/)
│  │  ├─ services/      43  (auth, maps, directions, push, upload, admin/*)
│  │  ├─ stores/        11  (order, cart, driver, consent, partner_*, favorite)
│  │  ├─ models/        19  · dispatch/ 4 (NO-OP, zona proibida) · config/ 5 · utils/ 6
│  ├─ supabase/
│  │  ├─ functions/     38 locais  (43 deployed — ver §8 drift)
│  │  └─ migrations/   247 .sql
│  ├─ android/ · codemagic.yaml · .github/workflows/  (CI dual)
│  ├─ .claude/skills/   45 skills + bora-knowledge (knowledge VIVO 01-12)
│  └─ business_rules.md · CLAUDE.md
└─ .claude/.ai/knowledge/            ← knowledge CURADO (congelado 2026-04-25) ⚠️ 2º store
```
**Roles cobertos:** Cliente · Estafeta · Parceiro · Admin · Transversais/Config.
**DB ground-truth:** 78 tabelas (todas RLS on) · 43 Edge Fns deployed · 17 restaurants (2 partner) · 43 773 produtos (324 sem preço) · 2 estafetas (0 pending) · 534 knowledge_chunks · 28 support_skills.
**Auto-revisão:** ✅ os 4 roles, transversais, edge fns, migrations, skills, knowledge, android, CI e mercado estão todos no âmbito. Nada em falta no croqui.

---

## 2. SUMÁRIO EXECUTIVO

O Bora está **maduro e globalmente são**: fluxos cliente/estafeta/parceiro coerentes e bem-ligados à DB; pricing 100% server-autoritativo; as 5 classes críticas do audit de 8-Mai **resolvidas**; design system aplicado em ~70/110 ecrãs. O risco real concentra-se em **(a) um buraco de segurança vivo numa função admin**, **(b) um cron de re-dispatch a falhar 97.8%**, **(c) dívida de higiene de repo/knowledge**, e **(d) lacunas de gestão no admin** (fees por parceiro, ledger, CRUD de catálogo).

### 🔴 TOP 5 RISCOS
1. **`admin_list_orphans()` exposta a anon/authenticated/PUBLIC** (SECURITY DEFINER sem guard) → fuga de `payment_intent_id`/`user_id`/valores. Migration de fecho existe mas **nunca aplicada**.
2. **Cron `bora_dispatch_maintenance` falha 97.8%** (704/720 em 24h) — `extensions.net.http_post` rebenta; re-dispatch de pedidos stale via maintenance não funciona. *(Zona proibida — só reporto.)*
3. **`node_modules` (605 ficheiros) e `testsprite_tests` (33) commitados** no git; bucket Storage **`receipts` público** (PII financeira).
4. **Knowledge desincronizado:** 2 stores divergentes + Obsidian congelado há ~5 semanas; factos-âncora errados ("5 Edge Functions", paleta antiga, blockers já resolvidos).
5. **Admin "falta muito"**: sem fees-por-parceiro, sem UI de `ledger_entries`, CRUD de produtos incompleto, sem moradas/cartões do cliente, sem exportação CSV em todo o admin.

### 🟢 TOP 5 QUICK-WINS
1. **Aplicar a migration já existente** `20260518200000_admin_list_orphans_guard.sql` → fecha o buraco #1. *(decisão Danilo — §5)*
2. `.gitignore` + `git rm --cached node_modules/ testsprite_tests/` → tira 638 ficheiros do repo.
3. `order_details_screen.dart:284-308` ler `platform_settings.cancel_fee_*` em vez de hardcoded.
4. Apagar widget morto `bora_bottom_nav.dart` (v1, 0 callers) e resolver ecrã órfão `store_shopping_purchase_screen.dart`.
5. Correr `update-bora-knowledge` + corrigir paleta/contagem edge-fns nos docs congelados; deprecar `taxonomy-mapper` (conflito com `category-mapper-v2`).

---

## 3. AUDITORIA POR ÁREA

### 1) FLUXO CLIENTE — ✅ maduro
- ✅ Cartão payment-first sem orphans (`payment_method_screen.dart:623`); pricing server-autoritativo (`order_store.dart:749`); rating idempotente (`rating_screen.dart:59`).
- ⚠️ Duplo prompt de rating (`order_tracking_screen.dart:152`); copy da FAQ de cancelamento desatualizada (`support_screen.dart:42`).

### 2) FLUXO ESTAFETA — ✅ coerente
- ✅ Registo "nunca bloqueia" (Glovo) alinhado com RPC `driver_register_or_update` (14 params, overload único, PGRST203 resolvido); Accept com optimistic lock correto (`current_driver_offer_id`); storeShopping V2 inline real; PIN determinístico idêntico nos 2 lados.
- ⚠️ **"OCR" do talão NÃO existe** — o estafeta **digita** o total manualmente (`driver_map_screen.dart:3036`); a descrição "talão foto OCR" é aspiracional.
- ⚠️ `acceptOrderById` (`order_store.dart:1510`) faz UPDATE sem optimistic lock — não é o caminho principal, mas auditar callers.
- ❌ `store_shopping_purchase_screen.dart` é **ecrã órfão** (0 callers) que duplica o fluxo V2 com lógica morta `_allItemsResolved`.
- ⚠️ `deliveryCode` (`order_model.dart:580`) faz `int.parse(...,radix:16)` — crasha para ids não-UUID (legado/test); seguro em prod (tudo UUID).

### 3) FLUXO PARCEIRO — ✅ funcional
- ✅ As 12 RPCs `partner_*` invocadas existem todas em prod; strings inglesas do `restaurant_dashboard` **já corrigidas** (PT-PT).
- ❌ **`restaurant_dashboard_screen.dart` mostra rótulos de comissão ERRADOS "20%/80%"** (linhas 614/619/721/726) enquanto a matemática real usa **10%** (`partner_visible_commission_pct=0.10`). Mitigado por ser código morto (0 callers), mas enganoso se reativado.
- ⚠️ Threshold do modal de dispatch hardcoded 1200s (`partner_dashboard_screen.dart:259`) em vez de setting; cascata laranja viola "1 laranja/ecrã" (`:1847-1923`).

### 4) COBERTURA ADMIN — ⚠️ amplo mas com lacunas reais (ver MATRIZ §3-bis)
- ✅ 50+ ecrãs, ~107 RPCs `admin_*`; cobre tokens, aprovações, reservas, recibos, selfie, ban/reativar, payouts, skill_suggestions, crosstalk, support_pending_actions.
- ❌ Sem cobertura: `pending_charges` (cobranças Stripe falhadas — invisíveis), `product_update_runs` (saúde do scraper), `reservation_waitlist`/`reservation_notify_list`.

### 5) CÓDIGO ↔ DB — ✅ são
- ✅ **Todos os ~95 RPCs** chamados em `lib/` existem em `pg_proc`; as 5 Edge Fns invocadas estão deployed+ACTIVE.
- ❌ `order_details_screen.dart:284-308` calcula taxa de cancelamento com **valores hardcoded** (€1.00/€2.50/100%) em vez de `platform_settings.cancel_fee_*_cents`. Hoje COINCIDEM com a DB → sem discrepância visível, mas quebra silenciosamente num futuro update de pricing. *(débito autoritativo é server-side e correto.)*
- ⚠️ Comentários estale na `stripe-webhook/index.ts:317-319` contradizem os fees reais.
- ⚠️ 6 orders legado com coords dropoff/pickup NULL (5 `created` + 1 `delivered`) — sem impacto em pedidos novos.

### 6) CONTRADIÇÕES REGRAS DE NEGÓCIO — ⚠️ tokens estafeta
- ✅ Fees (10+5+5% / 15%), driver pay, sacos, reservas €3 (€2/€1), wallet refund 80/20, cash €40 **consistentes** entre `business_rules.md`, `.ts`, `platform_settings` e RPCs. ✅ **Nenhum mercado é partner** (invariante mantida).
- ❌ **UI do estafeta mostra tokens = earnings × 10**, que NÃO bate com o award real **flat 40/50** por entrega (`driver_map_screen.dart:1390` vs trigger `fn_award_tokens_on_delivery`).
- ❌ Semântica do "+50" contraditória: `business_rules.md:252` diz "+50 stacking" mas o trigger em prod dá "+50 PARTNER". Critérios diferentes.
- ⚠️ `business_rules.md:254` diz cliente "3% do valor" mas a fórmula real é `ROUND(price×3)`; constante-fantasma `DRIVER_TOKENS_PER_EUR` (`business_rules.dart:67`).

### 7) DESIGN SYSTEM — ✅ amplo, gaps de pureza
- ✅ Os **3 contratos pedidos estão corretos**: bottom nav V2 4 tabs (Início/Entrega/Reserva/Perfil), card Restaurantes usa `cat_restaurantes.png`, tiles home `BoraTileCard.image` full-bleed.
- ⚠️ Gaps de *pureza de tokens* (não visuais): `cart_screen.dart:363` usa `Colors.green`; `client_favorites`/`wallet_history` com AppBar nu; status colors do estafeta hardcoded; cascata laranja no `partner_dashboard`.

### 8) QUEBRADO / RISCO — ❌ achado de segurança
- ❌ **CRÍTICO:** `admin_list_orphans()` — SECURITY DEFINER, **sem guard**, EXECUTE a anon/authenticated/PUBLIC (verificado via `pg_get_functiondef`+`aclexplode`). Migration de fecho `20260518200000_admin_list_orphans_guard.sql` **não aplicada**. O código (`admin_orphan_payments_screen.dart:16`) documenta-a erradamente como "service_role only".
- ❌ `admin_mark_partner_credits_paid` em prod usa guard antigo `raw_user_meta_data->>'bora_role'` em vez do `app_metadata.role` pretendido pela migration.
- ⚠️ `confirm-mbway-payment` (obsoleta, 0 callers) ainda no repo; `upload-order-photo` invocada (`order_photo_upload_service.dart:48`) mas **sem fonte local**.
- ⚠️ RPCs app-facing órfãos (dead): `restaurant_respond_to_rating`, `admin_get_order_payment_breakdown`, `client_get_assigned_driver`, `request_order_cancel`, `set_delivered_at`, `file_complaint`, `file_support_ticket`.

### 9) SEGURANÇA & PERFORMANCE — ✅ base sólida, dívida de perf
- ✅ As **5 classes críticas de 8-Mai resolvidas**; das 32 funções `search_path` mutável, **ZERO são SECURITY DEFINER** → risco real nulo (só hardening defensivo).
- ⚠️ **Bucket `receipts` público** sem restrições (PII financeira) — prioridade. Listing público em `avatars`/`product-images`/`restaurant-assets`.
- ⚠️ Perf (dívida real): 277 `multiple_permissive_policies`, 109 `auth_rls_initplan` (envolver `auth.*()` em subquery) nas tabelas quentes `products`/`orders`/`ledger_entries`; 27 FK sem índice; 52 índices não usados.
- ⚠️ Leaked-password protection (HIBP) desligada.

---

## 3-bis. MATRIZ ADMIN × FLUXOS (o "falta muito" do Danilo)

Capacidades: Ver · Editar · Criar · Banir/Cancelar · Configurar · Exportar · Auditar.

### CLIENTE
| Entidade | Estado | Ecrã / lacuna |
|---|---|---|
| Conta/perfil | ✅ ver/ban/auditar · ⚠️ editar · ❌ exportar | `admin_clients_screen`, `admin_client_detail_screen` |
| **Moradas** (`client_addresses`) | ❌ **NENHUM** | sem UICliente — impossível corrigir morada errada |
| **Métodos pagamento (cartões Stripe)** | ❌ **NENHUM** | zero visibilidade |
| Pedidos | ✅ ver/cancelar/auditar | `admin_orders_screen`, `admin_order_detail_screen` |
| Tracking live | ✅ | `admin_live_orders_map_screen` |
| Wallet/tokens | ✅ grant/revoke | `admin_wallets_screen` |
| **Transcript chatbot** | ⚠️ vê tickets, ❌ conversa | falta `admin_support_chat_detail` |
| Ratings · Referrals · Reservas · Notificações | ✅/⚠️ | vários ecrãs |

### ESTAFETA
| Entidade | Estado | Ecrã / lacuna |
|---|---|---|
| Candidatura/aprovação · Documentos · Force-logout · Ban/reativar · Earnings · Performance | ✅ | `admin_driver_approval`, `admin_driver_detail`, `admin_driver_payments` |
| **Ofertas/dispatch timeline por estafeta** | ❌ | sem visibilidade de quem rejeitou |
| **Tokens estafeta** (`driver_token_transactions`) | ⚠️ | sem ecrã dedicado |

### PARCEIRO
| Entidade | Estado | Ecrã / lacuna |
|---|---|---|
| Aprovação · Horários · Pedidos · Payouts · Ratings · Ban · Assets | ✅ | `admin_partners_pending`, `admin_partner_detail`, `admin_partner_payouts` |
| **Menu/produtos** | ⚠️ só preço/avail · ❌ criar/apagar/editar nome·foto·desc | `admin_catalog_screen` |
| **Comissões/fees POR parceiro** | ❌ **NENHUM** | só globais — sem override por loja |
| Reservas PRO (floor plan/pacing/turn_times) | ⚠️ parcial | sem UI de floor plan |

### TRANSVERSAIS
| Entidade | Estado |
|---|---|
| `platform_settings` · Promos (sem **editar**) · Broadcasts · skill_suggestions · robot_crosstalk · support_pending_actions · Audit log | ✅/⚠️ |
| **`ledger_entries`** (forensics) | ❌ **NENHUM** (só skill CLI) |
| **`pending_charges`** | ⚠️ só `orphan_payments` parcial |
| **Fila de refunds standalone** | ❌ (só acoplado a cancelamento) |
| **CRUD de FAQs** (`support_knowledge_chunks`) | ⚠️ só stats — criar/editar é CLI-only |
| **Exportação CSV/Excel** | ❌ **ausente em TODO o admin** |

### ❌ TOP 15 LACUNAS ADMIN (priorizado)
1. **Fees/comissões por parceiro** (sem coluna/RPC override) — crítico negócio.
2. **`ledger_entries` sem UI** — forensics só por skill.
3. **CRUD de produtos incompleto** (só preço/avail).
4. Cartões Stripe do cliente sem visibilidade.
5. Moradas do cliente sem UI.
6. Transcript do chatbot de suporte.
7. `pending_charges` sem fila própria.
8. Fila de refunds standalone.
9. CRUD de FAQs in-app.
10. Timeline de ofertas/dispatch por estafeta.
11. Editar promo code (só criar/desativar).
12. Floor plan/pacing/turn_times de reservas PRO.
13. **Exportação CSV transversal** (contabilidade).
14. Tokens do estafeta (ecrã dedicado).
15. Resgates de promo por utilizador (anti-fraude).

**Tabelas sem UI admin (órfãs de gestão):** `client_addresses`, `client_favorites`, `ledger_entries`, `order_purchase_items_v2`/`order_receipts_v2`, `pending_charges`, `payouts`, `product_variants`, `restaurant_floor_plans`/`pacing_rules`/`turn_times`, `reservation_waitlist`/`notify_list`, `support_chatbot_messages/sessions`, `support_skills`, `driver_token_transactions`, `product_update_runs`, `messages` (chat não moderável).
**RPCs `admin_*` definidas sem botão:** `admin_realtime_metrics`, `admin_partner_sales_summary`, `admin_partner_payout_summary`, `admin_reset_product_photo`, `admin_low_rated_subjects`, `admin_reservations_today`, `admin_set_partner_special_date`, `admin_mark_receipt_paid`, `admin_reject_receipt`, entre outras.

---

## 4. HIGIENE: LIMPEZA · DUPLICAÇÕES · SKILLS · KNOWLEDGE

### Limpeza / dead code
- ✅ **APLICADO:** 61 ficheiros de lixo apagados (logs de build/flutter/JVM/logcat + 2 screenshots) — untracked/gitignored, 0.63 MB.
- ❌ **`node_modules/` (605) e `testsprite_tests/` (33) commitados** — `.gitignore` só cobre `scripts/scraper/node_modules`.
- ⚠️ `device_screenshot_*.png` escapam ao `.gitignore` (regra só cobre `flutter_*.png`).
- 🟢 **Dead code seguro:** widget `bora_bottom_nav.dart` v1 (@Deprecated, **0 callers**, 101 linhas).
- 🔒 **Dead-mas-proibido:** `lib/dispatch/` (`dispatch_service`+`driver_assignment_service`+barrel) é auto-referencial e NO-OP, MAS `dispatch_engine.dart` é load-bearing no provider chain → **não tocar**.
- ⚠️ ~9 relatórios `.md` soltos na raiz (FINAL_REPORT, HEARTBEAT, PROGRESS, TEST_*, WELLS_*, WORTEN_*) — mover para `docs/`.

### Duplicações
- 🔴 **`taxonomy-mapper` (18 secções) vs `category-mapper-v2` (22)** escrevem AMBAS em `products.taxonomy_section` com taxonomias incompatíveis → deprecar uma (decisão sobre ~43K produtos).
- 🔴 **DRY falso:** os 3 `onboard-partner-*` têm cópia completa dos 7 scripts cada; o INDEX afirma reutilização — **é falso**.
- ⚠️ `services/driver_assignment_service.dart` **NÃO é duplicado** (é barrel de 3 linhas) — falso positivo desmentido.
- ⚠️ Paleta de marca em 3 sítios divergentes: `ceo-ai/SKILL.md:12` e `stack.md:32` (`#2E7D32/#E65100`) vs código real (`#16A34A/#F97316`).

### Skills (45, em `bora_app/.claude/skills`)
- ⚠️ 7MB+ de scratch + 36 `__pycache__` commitados em `taxonomy-mapper/scripts`.
- ⚠️ 10 skills antigas sem `type`/README/`depends_on bora-knowledge` (os `[!]` do skills-doctor).
- 💡 Melhorias: extrair `_shared` dos onboard-*; `.gitignore` para `__pycache__`/scratch; skills novas `cleanup-repo-junk` e `sync-edge-functions-local`; ligar a cron `weekly-market-prices`/`run-weekly-payouts`/`audit-protected-zones`.

### Knowledge & Obsidian
- 🔴 **Dois knowledge stores divergentes** + **dois `.claude`**: curado (`projetosflutter/.claude/.ai/knowledge`, **congelado 2026-04-25**) vs vivo (`bora_app/.claude/skills/bora-knowledge`, até maio).
- 🔴 Factos errados: "5 Edge Functions" (real 43), paleta antiga, pontuações 55/100, 6 blockers já resolvidos (Firebase push, foto perfil, BUG-PT-006).
- 🔴 **Obsidian unidirecional, último sync 2026-04-25** → ~5 semanas de trabalho **nunca chegaram ao vault**. Dois paths em uso: `Desktop\Bora` (sync) vs `Desktop\bora\rules-history` (auto-rules-sync).

---

## 5. ⚠️ PENDENTE — VALIDAR COM DANILO (ordenado por impacto · NADA aplicado)

### 🔴 P1 — SEGURANÇA (alta)
**Fechar `admin_list_orphans` exposta.** A migration `supabase/migrations/20260518200000_admin_list_orphans_guard.sql` já existe (adiciona guard `app_metadata.role='admin'` + `REVOKE` a anon/authenticated). **Decisão: aplicar à DB?** → ver pergunta no fim. *(Zona proibida: segurança/DB — requer a tua autorização.)*

### 🔴 P2 — DISPATCH CRON (alta, zona proibida — só reporto)
`bora_dispatch_maintenance()` linha ~140 usa `extensions.net.http_post` (cross-database ref que rebenta); os crons que funcionam usam `net.http_post`. **97.8% de falha.** Correção = trocar a chamada qualificada — mas toca dispatch → **exige a tua decisão explícita**, não toco.

### 🟠 P3 — REPO (média, seguro mas é mudança de repo)
```
# .gitignore (raiz bora_app) — adicionar:
/node_modules/
/testsprite_tests/
device_screenshot_*.png
**/__pycache__/
# depois:
git rm -r --cached node_modules testsprite_tests
```
Remove 638 ficheiros do índice sem apagar do disco. Reversível.

### 🟠 P4 — UI fees hardcoded (média, zona sensível pricing)
`order_details_screen.dart:284-308`: substituir `1.00/2.50/100%` por leitura de `platform_settings.cancel_fee_*_cents` (mesma fonte da Edge Fn). Só estimativa de UI — débito real já é correto. **Toca pricing UI → validar.**

### 🟠 P5 — Tokens estafeta UI enganosa (média, zona proibida tokens)
`driver_map_screen.dart:1390`: estimador mostra `earnings×10`; o real é flat 40/50. Corrigir o **texto estimado** (não o award). **Toca tokens → validar.**

### 🟡 P6 — Knowledge sync (média)
Correr `update-bora-knowledge` (MODO A, só toca `00-auto-facts.md`); corrigir paleta `#2E7D32→#16A34A` e "5→43 Edge Fns" em `ceo-ai/SKILL.md:12` e `stack.md:32`; marcar blockers resolvidos. *(Toca SKILL.md → pede confirmação.)*

### 🟡 P7 — Dead code & duplicação (baixa)
- Apagar `bora_bottom_nav.dart` v1 (0 callers).
- Resolver órfão `store_shopping_purchase_screen.dart` (apagar ou religar) — toca storeShopping V2 → validar.
- Deprecar `taxonomy-mapper` (confirmar taxonomia em prod antes).
- `restaurant_dashboard_screen.dart:614` rótulos "20%"→"10%" (ou @Deprecated).

### 🟡 P8 — Edge Fns sem fonte local (baixa)
Versionar/confirmar fonte das 6 deployed-sem-repo (ver §8); remover `confirm-mbway-payment` obsoleta.

---

## 6. SUGESTÕES MERCADO (Glovo → Uber Eats → iFood)
Só lacunas que existem nos 3 apps (não inventadas):
1. **"Pedir de novo" (reorder 1-toque)** — `market_reorder_tab.dart:6` é só placeholder "Em breve". Modelo já suporta reorder.
2. **Nota/instruções para o estafeta no checkout** — `customerNotes` existe no modelo (`cart_store.dart:531`) mas **nunca é recolhido** na UI → vai sempre null.
3. **Preferência de substituição** no checkout (mercados) — o modelo já suporta `substitution_requests` do lado do estafeta.
4. Pesquisa + ordenação na **listagem de lojas** (`stores_screen.dart:114`).
5. **Entrega agendada** (scheduled delivery).
6. ETA + taxa de entrega dinâmicos no stats row (zona pricing — cautela).

---

## 7. SUGESTÕES AUTOMAÇÃO
- ✅ CI/CD **funcional**: `build_android.yml` (GH Actions) bump versionCode + AAB assinado + auto-publish Play Internal no branch `autonomous-night-2026-04-29`.
- ⚠️ **Dois pipelines publicam no mesmo track** (`build_android.yml:124` + `codemagic.yaml:73`) → risco de double-publish. Desativar o Codemagic.
- ✅ Auto-melhoria a fluir: 22 pg_cron (robot-b, analyze-conversations, execute-broadcast, auto-payout); ciclo `analyze-conversations → skill_suggestions → robot-b` activo (5 crosstalk, 9 sugestões).
- 💡 Automatizável já: **payouts** (skill `run-weekly-payouts` → ligar a cron + execução Stripe Connect), **aprovações** (`audit-driver/partner-application`), **refunds MBWay** (skill `refund-assistant` em shadow → inbox admin).
- 💡 Fechar loop crosstalk A↔B (auto-resposta `robot-b`); ligar canal de notificação aos alertas de cron (wallet_overdue, orphan/stripe/ghost checks).

---

## 8. TABELA DE DRIFT — Edge Functions (38 local vs 43 deployed)

| Categoria | Funções | Fonte da verdade |
|---|---|---|
| **Deployed SEM fonte local (6)** ⚠️ risco | `admin-cancel-reservation`, `execute-broadcast`, `gemini-diagnostic`, `robot-b`, `upload-driver-document`, `upload-order-photo` | **Só Supabase** — não revisáveis/redeployáveis a partir do repo. `upload-order-photo` é invocada em fluxo $ (`order_photo_upload_service.dart:48`). |
| **Local SEM deploy (1)** | `confirm-mbway-payment` | Repo — **obsoleta**, 0 callers → apagar |
| **Em ambos (37)** ✅ | dispatch-engine v56, stripe-webhook v30, create-payment-intent v32, notify-driver v32, notify-partner v21, register-partner v3, … | Sincronizadas |

**Reconciliação:** a memória dizia "38 local / 44 deployed" → realidade **38 local / 43 deployed**. Ação: exportar o código das 6 deployed-only para `supabase/functions/` (skill nova `sync-edge-functions-local`) para eliminar o risco de "função deployed sem fonte".

---

## 9. CORREÇÕES APLICADAS (seguras, fora de zonas proibidas)
1. ✅ **Apagados 61 ficheiros de lixo** (0.63 MB) na raiz `bora_app/`: `build-exec6.*.log`, `build_*.log`, `flutter_*.log`, `hs_err_pid*.log`, `logcat*.log` e 2 `device_screenshot_*.png`. Todos untracked/gitignored → **zero alteração no git, nada a commitar**.

> Tudo o resto (lib/, DB, migrations, security, tokens, pricing, knowledge, repo-tracking) ficou em **§5 PENDENTE** por respeito ao MODO PROTECÇÃO TOTAL.

---

## 10. LEMBRETE ADMIN (regra obrigatória)
As maiores correspondências de painel admin em falta (a construir): **fees por parceiro**, **UI de `ledger_entries`**, **CRUD completo de produtos**, **moradas + cartões do cliente**, **transcript de chatbot**, **exportação CSV transversal**, **fila de `pending_charges`/refunds**, **saúde do scraper (`product_update_runs`)** e **waitlist de reservas**. Idioma admin = PT-BR.
