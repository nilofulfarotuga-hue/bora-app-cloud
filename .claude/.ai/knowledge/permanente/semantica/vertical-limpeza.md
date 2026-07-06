---
tema: vertical-limpeza · escopo: projeto · estado: atual · atualizado: 2026-07-06
---

# Vertical LIMPEZA (limpeza doméstica) — v1 + auditoria de paridade

> Benchmark Helpling/Oscar. v1 construída na sessão autónoma de 2026-07-05 (branch
> `autonomous-night-2026-04-29`). Relatório completo: `RELATORIO_LIMPEZA_V1.md` (raiz do repo).
> Commits v1: `6e6d066` (F1 backend) · `3bcca93` (F2 Edge Fn) · `c77ce08` (F3 cliente)
> · `c0c84d7` (pagamento LIVE) · `2b66e67` (F4 profissional) · `4842801` (F5 admin).
>
> **Auditoria de paridade + correção (2026-07-06):** commits `912ce6d..4d34a2a`
> (relatório `RELATORIO_AUDITORIA_LIMPEZA.md`). Anti-trapaça `--base f0bd479` = CLEAN
> (0 testes tocados); `dart analyze` por ficheiro limpo. **NÃO pushado** — local, para revisão.

## Backend (verificado em prod via MCP, 2026-07-05)

- **Migrations:** `supabase/migrations/20260705100000..20260705100006` (7 ficheiros
  `*_cleaning_*.sql`) + `20260705120000_cleaning_chat_profiles_kyc.sql`, aplicadas em prod.
- **Tabelas (6):** `cleaners`, `cleaner_availability`, `cleaning_bookings`,
  `cleaner_cancel_events`, `cleaning_recurrence_stops`, `cleaning_messages` (chat).
- **RPCs:** famílias `cleaning_*`, `cleaner_*`, `admin_cleaning_*`, `_cleaning_*` (helpers/cron).
- **RLS:** escrita **só via RPC SECURITY DEFINER** (tabelas fechadas a escrita direta).
- **Isolamento:** vertical isolada de `orders`/`dispatch-engine` (mesmo padrão da TVDE).

## Pagamento 🔴

- **Edge Fn `cleaning-checkout` v2 ACTIVE (2026-07-06, commit `912ce6d`): cartão passa a
  COBRAR NA RESERVA** — cartão E MB Way cobram no ato da reserva. Cancelamento → estorno
  do excedente da taxa via ação `reverse` (mecânica já existente). Ação `capture` mantém-se
  **só para holds legados** criados antes da mudança (`requires_capture`). `estado: atual`.
- **Padrão `tvde-plan-payment`:** Edge Fn isolada, **SEM webhook**. `verify_jwt=true`;
  `cleaning_stripe_enabled=true` em `platform_settings` (audit em `admin_audit_log`).
- ~~Cartão com captura manual (hold até o cliente confirmar)~~ —
  **estado: superado (por cleaning-checkout v2 cobra-na-reserva, 2026-07-06, commit `912ce6d`).**

### Caveats de dinheiro — histórico (fechados pelo v2)
1. ~~Hold de cartão Stripe expira em ~7 dias → reservas por cartão >7 dias perdiam o hold~~ —
   **estado: superado (por v2 cobra-na-reserva, 2026-07-06).**
2. ~~Captura pós auto-confirmação dependia de o cliente reabrir o tracking~~ —
   **estado: superado (por v2 cobra-na-reserva; captura só resta para holds legados, 2026-07-06).**

## Regras de negócio (confirmadas em prod via MCP, 2026-07-06)

- **Split:** `cleaning_bora_pct=15` — profissional 85% / Bora 15%.
- **Preços fixos por tipologia:** T0/T1 €35 · T2 €45 · T3 €55 · T4+ €70.
- **Limpeza profunda +40%** · **pós-obras +60%**.
- **À hora:** €12/h, mínimo 2h.
- **Produtos da profissional:** **+€3** (`cleaning_products_fee_cents=300`, 100% para ela).
  Nota: `business_rules.md` dizia €10 — **corrigido** no commit `4d34a2a` (2026-07-06).
- **Recorrência** semanal/quinzenal: **-10%**; tenta a mesma profissional primeiro
  (`requested_cleaner_id` na rotation).
- **Cancelamento do cliente:** >24h grátis · 24h–2h 50% · <2h 100%.
- **Profissional:** 3 cancelamentos tardios em 30 dias (`late cancel limit 3`) = suspensão automática.
- **No-show do cliente:** taxa 100% (só cobrável após a hora marcada).
- **Rating <4.0 nos últimos 10** serviços = flag para o admin.
- **Cash:** os 15% da Bora ficam `cash_pending` até acerto semanal (`admin_cleaning_mark_cash_settled`).
- **Operacional:** auto-confirm 24h · min lead 12h · offer timeout 30min.

## Tokens — PROPOSTA, NÃO aplicada 🔴

- `supabase/PROPOSTA_20260706_cleaning_tokens.sql` (commit `4233d26`): trigger que atribui ao
  cliente `GREATEST(1, ROUND(total×3/100))` tokens e à profissional **+40** ao concluir.
- O Danilo disse "vai", mas a **Trava mecânica (protege-banco.sh) bloqueia DDL de tokens vinda
  do agente** — a aplicação é **ato humano**. `estado: proposta (pendente aplicação humana)`.
- **Hoje a Limpeza NÃO atribui tokens** (tal como TVDE e marcações; só o delivery atribui).

## Chat bidirecional cliente↔profissional (FASE 2, commits `a374f13`/`4233d26`)

- **Tabela dedicada `cleaning_messages`** (booking_id UUID, sender_role client|cleaner, read,
  created_at). RLS participantes-only; INSERT só em estados `accepted/on_the_way/in_progress/done`.
- RPC `cleaning_mark_messages_read(p_booking_id, p_my_role)` · push via trigger `_cleaning_chat_push`.
- **Decisão de arquitetura:** seguiu o padrão TVDE E1 (**tabela por vertical**), NÃO a tabela
  `messages` do delivery (acoplada a `orders` TEXT; RLS/Edge Fn de push só resolvem por `orders`).
  Ver `episodica/decisoes.md`.
- **Flutter:** `CleaningChatStore` (refcount por booking), `CleaningChatScreen`
  (`lib/screens/shared/`), `CleaningChatButton` (badge vermelho 9+ + preview).
  Botão **LIGAR** (`tel:`) nos 2 lados.

## Identidade / perfis (FASE 2)

- Card do **cliente** para a profissional: RPC `cleaning_booking_client_public(p_booking_id)` —
  nome/foto/telefone **só depois de aceitar** (padrão privacidade TVDE D2).
- `cleaning_booking_cleaner_public` v2 devolve `phone` **só em estados ativos**.

## KYC + foto no cadastro (FASE 2-C, commit `472ff58`)

- `CleanerUploadService` (`lib/services/cleaner_upload_service.dart`): foto → bucket público
  `avatars` (`$uid/avatar.jpg`); documento → **bucket privado NOVO `cleaner-documents`**
  (4 policies own-folder + admin).
- Candidatura (`cleaner_apply`) agora **EXIGE foto + documento de ID**; paths em `cleaners.docs` jsonb.
- `PrivateBucketImage` passou a reconhecer `cleaner-documents` e `restaurant-documents`.

## Paridade home da profissional (commit `472ff58`)

- Atalho **Suporte** (`BoraSupportSheet`) + `CleanerHistoryScreen` (concluídos/cancelados).
- **Avaliação bidirecional:** UI "Avaliar o cliente" na agenda → `cleaning_submit_rating`
  (a RPC deteta o sujeito: `subject_type` = `cleaner` vs `cleaning_client`).

## Paridade admin (FASE 3, commit `14a7f78`)

- Admin vê a conversa de qualquer limpeza (**read-only**) via `admin_list_cleaning_messages`
  (+ `log_admin_action`).
- Review da profissional mostra **foto + documentos** (signed URL).
- `admin_ratings_screen` ganhou filtros `cleaner`, `cleaning_client`, `tvde_passenger`.

## Crons (5 ativos em `cron.job`, confirmado em prod 2026-07-05)

| Cron | Schedule |
|---|---|
| `cleaning-offer-timeout` | `*/5` |
| `cleaning-auto-confirm` | `*/30` |
| `cleaning-reminders-24h` | `5 * * * *` |
| `cleaning-reminders-2h` | `*/30` |
| `cleaning-generate-recurring` | `0 8 * * *` |

Push via `_cleaning_notify_user` (in-app + `notify-client` FCM, secrets no Vault) —
**sem deep-link ainda** (ver pendência do `notify-client` abaixo).

## Flutter (verificado no repo, 2026-07-06)

- **Stores:** `CleaningStore` + `CleanerStore` + `CleaningChatStore` em `lib/main.dart`.
- **Modelos:** `lib/models/cleaning_models.dart`.
- **Cliente:** `lib/screens/client/cleaning/` — `cleaning_bookings_screen`,
  `cleaning_wizard_screen` (3 passos), `cleaning_tracking_screen` (agora com chat + card
  da profissional), `cleaning_payment_flow`.
- **Profissional:** `lib/screens/cleaner/` — `cleaner_apply_screen` (foto+KYC),
  `cleaner_home_screen` (chat, suporte, avaliar cliente), `cleaner_availability_screen`,
  `cleaner_earnings_screen`, `cleaner_history_screen`. Entrada no perfil: "Sou profissional de limpeza".
- **Admin (paridade ✅):** `admin_cleaning_bookings_screen` (+ conversas) +
  `admin_cleaning_cleaners_screen` (+ docs KYC) — secção "Limpeza doméstica" no dashboard.
- **Lição associada:** `procedural/licoes/licao-context-watch-getter.md`.

## Pendências fora de scope (reportadas 2026-07-06, NÃO corrigidas)

1. `notify-client` hardcoda `type:'order_status'` → bloqueia deep-link por tipo (afeta o chat da limpeza).
2. Edge Fns `upload-driver-document`/`upload-order-photo` deployed **sem fonte local** (drift repo↔prod).
3. `_myRole` unused em `chat_bubble_button` (lint menor).
4. DDL de chat (`tvde_messages`, colunas) em prod **sem migration no repo**.
- **Recomendação registada:** sessão de sincronização repo↔prod.
