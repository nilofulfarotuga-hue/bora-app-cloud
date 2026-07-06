---
tema: decisoes · escopo: projeto · estado: atual · atualizado: 2026-07-06
---

# Decisões Arquiteturais Persistentes

> Memória episódica de decisões que atravessam sessões, consolidada da auto-memória do Claude Code (arquivada em `_arquivo/MEMORY_pre_cerebro_2026-07-01.md`). Fonte da verdade numérica = `bora_app/.claude/.ai/business_rules.md`. Onde há CONTRADIÇÃO, mantém-se a verdade ATUAL e marca-se a antiga como **superada** (história preservada).

---

## Identidade de dados (IDs)

### `restaurants.id` / `products.id` / `orders.id` são TEXT (legado)
- Migrations fazem cast quando precisam de UUID. Refactor para UUID **planeado e ADIADO** em `decisions/2026-04-29-restaurants-id-uuid-refactor.md`.
- **estado: atual** (TEXT continua; refactor adiado).

### `assigned_driver_id` é TEXT — INTENCIONAL
- NÃO tocar. Decisão deliberada de esquema.
- **estado: atual.**

### `admin_audit_log.entity_id` é UUID; usar `entity_id_text` para entidades TEXT
- Para restaurants/products (id TEXT) → gravar em `entity_id_text`.
- **estado: atual.**

---

## Financeiro / Wallet / Tokens

### Wallet — TOKENS reais é o que vale hoje (NÃO "saldo promocional 80/20")
- **Verdade atual:** o sistema usa **bora_tokens** reais. Valor do token = **€0,005** (`token_value_cents_x100 = 50`). Referral em tokens (`referral_min = 4000`, `fn_referral_reward` usa `add_tokens`). Promo codes via `client_redeem_promo_tokens`. Extras/refund fazem split 80% wallet / 20% tokens (ver `refund-assistant` SHADOW).
- **estado: atual** (tokens €0,005; commits 27cf8c1, 827e784).
- **Nota de contradição:** a referência histórica "saldo promocional 80/20" (business-rules/wallet.md §17) descreve o split de cashback/refund/promo — coexiste com os tokens reais mas NÃO substitui o valor do token. O split 80/20 aplica-se a como um refund/cashback é distribuído (80% wallet, 20% tokens), não a um "saldo promocional" separado. **estado: atual** (split 80/20 = regra de distribuição; tokens = moeda).

### Cancelamento — Edge Function `client-cancel-order` é a ATUAL
- **Verdade atual:** o cancelamento pelo cliente corre via **Edge Function `client-cancel-order`** (Bloco 4, LISTA VERMELHA, net-new; draft em `relatorios/BLOCO4_*.sql`, aguarda flip 1-clique).
- **estado: atual.**
- **Superado:** a RPC `request_order_cancel` está **órfã** (não é o caminho vivo). **estado: superado (por Edge Function client-cancel-order, 2026-06-29).**

### Valor do sinal de serviços/appointments
- €3 sinal → €0,50 Bora + €2,50 parceiro; cancel >24h = reembolso; MVP só cartão; sem `ledger_entries` (auto-contido em `appointments`+`appointment_payouts`).
- **estado: atual** (`project_servicos_barbearias_2026_06_08.md`).

### Caps de lançamento (Bloqueadores B1-B6)
- cap 15km, cap 50% em tokens, cap semanal de saque (RPC nova), alergénios.
- **estado: atual** (4 migrations prod provadas, commit ..067b1c9).

---

## Pricing de catálogo (markup por fonte)

> Regra de negócio de dados, NÃO tocar pricing_service. O markup ×1.15 é aplicado em runtime; a DB guarda preço-base.

- **Continente:** preço Glovo direto ×**0,85** (`price_source = glovo_minus15`; fatura provou markup Glovo ~15%). **estado: atual.**
- **Auchan:** "mesmo preço que loja" — NÃO subtrair 15%. **estado: atual.**
- **Wells (farmácia):** preço Glovo direto, SEM markup (≠ Continente). **estado: atual.**
- **McDonald's:** quiosque = preço EXATO; não-âncora = Glovo ×**0,8261** (NUNCA ÷1,15). **estado: atual.**
- **Fast-food (opções/price_add):** ×**0,8261** (Danilo manteve apesar de base BK/KFC=0,718). **estado: atual.**
- **Açaí (parceiro):** preço REAL (sem markup). **estado: atual.**
- **Restaurantes Glovo (KFC/BK) e 4 lojas retail (Kiwoko/Leroy/Worten/Zippy):** ÷**1,15** (cliente = preço Glovo). **estado: atual.**
- **Pingo Doce / Intermarché / Uber:** PD sem markup (Glovo Lisboa); Uber ×0,85. **estado: atual.**
- **⚠️ Gap conhecido (DECISÃO PRICING B, Danilo):** `product_detail_screen` NÃO aplica ×1.15 non-partner → fast-food via detalhe fica ~15% mais barato que a intenção da Fase 2. Gap conhecido, **ADIADO**. **estado: atual.**

### Convenções de catálogo
- Rebuilds de mercado = DELETE+INSERT do Glovo (catálogo exato), sempre com backup `_backup_*_pre_rebuild_*`. Soft-delete via `is_available=false`/`removal_reason` — NUNCA hard delete.
- `category = root`; trigger `trg_products_set_category_root` deriva `category_root` (split '/'). Coluna `sort_order` (migration 20260606120000) = ordem Glovo; Flutter `.order(sort_order).order(id)` (requer rebuild APK).
- NÃO usar fotos donor cross-loja (placeholders genéricos causam mismatch); Mercadona = donor de fotos same-store.
- **estado: atual.**

---

## Infra / Build / DevOps

### Migração Codemagic → GitHub Actions (autoridade de build)
- Build/publish no Play (Internal) via **GitHub Actions `build_android.yml`**; Codemagic publish desativado no yaml. CI auto-bumpa versionCode (por-build, NÃO por-commit) → **nunca bumpar pubspec manual**. Build local Windows (release) é inútil (OOM JBR21) — **CI é a autoridade**.
- **ARMADILHA keystore:** upload key correta = `Desktop/bora-app-release.jks` alias `bora-app` SHA1 62:A4:7D — **NÃO** o `bora-release.jks` do repo (BF:11). 6 secrets; `gh` via `GH_TOKEN`.
- **estado: atual** (`project_github_actions_migration_2026_05_30.md`).

### Keystore release
- `bora-app-release.jks` (PKCS12, 30y, SHA256 9E:DC:FC:81…). Commit bb5c6ad.
- **estado: atual** (mas ver armadilha acima: 2 keystores existem, usar o do Desktop).

### Package rename
- applicationId Android `com.example.bora_app` → **`pt.boraapp.bora`** (commit 14b7df2). Firebase Console reg + novo `google-services.json` obrigatório antes de build prod.
- **estado: atual.**

### Build local Windows desbloqueado
- `flutter config --jdk-dir` JDK 17 (era JBR 21) + `gradle.properties` workers.max=1+caching=false + afterEvaluate BaseExtension JVM 17. Doc em `.claude/.ai/knowledge/local-build-windows.md`.
- **estado: atual** (serve só para debug APK; release continua no CI).

### Estrutura do repo
- Repo git está em **`bora_app/`** (não no root `projetosflutter`). Usar `git -C bora_app …`.
- **estado: atual** (`project_structure_repo_root.md`).

### TRAVA de proteção determinística (Fase 1)
- Commit d0e89cd: deny nativo + hooks `protege-dinheiro.sh`/`protege-banco.sh` em `bora_app/.claude/` bloqueiam editar código de dinheiro (pricing_service/order_store/Edge Fns Stripe), DDL money e `git --force`/`reset --hard`. Auto-protege a própria trava. Doc `.claude/HOOKS.md`. Armadilhas: matcher `mcp__claude_ai_Supabase__*`; `.gitattributes eol=lf` para `.sh`.
- **estado: atual** (10/10 testes OK).

---

## Design System

### Paleta e regra "1 laranja por ecrã"
- Paleta #16A34A (primary verde) / #065F46 (secondary deep) / #F97316 (accent laranja); Inter bundled. Regra: **1 elemento laranja por ecrã** (auditada por `audit-orange-rule`). ElevatedButton default = verde; laranja reservado ao CTA principal (`BoraAccentButton`).
- App inteira (~123 ecrãs, 27 re-skinned na Fase 4 + reservas + avulsos + admin) migrada para tokens `AppColors.*` e `BoraScreenAppBar`. Fase 4.4 Parceiro Web = SKIP total (app é Flutter Android/iOS only).
- **estado: atual.**

---

## Robot B / Central de Autonomia (sessão O BANQUETE 2026-07-02)

### Cap de sugestões abertas é configurável
- Era 15 hard-coded em `robot_create_suggestion`; incoerente com `itens_por_ciclo=20` do goal. Agora lê `platform_settings.robot_b_max_open_suggestions` (default 15; definido **30**). Migration `20260702070000`.
- **estado: atual.**

### Bug conhecido: dedup do robot-b v3 falhava por dedup_key variável
- Sugestões com o MESMO título nasciam com dedup_keys diferentes → 10 duplicados na fila (timeouts HTTP ×6, RLS backup ×5…). Higiene 2026-07-02 expirou duplicados mantendo 1 por título. Ao evoluir o robot-b: dedup_key deve derivar do TÍTULO normalizado, não de timestamp/ciclo.
- **estado: atual** (corrigir na próxima evolução do robot-b).

## Segurança / Storage

### Buckets `receipts` + `order-photos` são PRIVADOS (fix P0 aplicado 2026-07-02)
- Estavam públicos (auditoria 360°). Virados para privado + removidas 4 policies anon de escrita não-scoped. Leitura era já 100% por URLs assinados (`PrivateBucketImage` re-assina até URLs `public/` antigos); uploads via Edge Fns (service_role). Rollback: `UPDATE storage.buckets SET public=true …`. Migration `20260702071000`.
- **estado: atual.**

## TVDE / Compliance

### Documentos TVDE têm tabela própria com revisão por documento
- `tvde_driver_documents` (6 doc_types: carta_conducao, certificado_tvde_imt, dut, seguro, inspecao, registo_criminal) + RPCs `admin_list/review_tvde_document` + `AdminTvdeDocsReviewScreen`. Upload no lado do motorista = **follow-up pendente**. Migration `20260702072000`.
- **estado: atual.**

## GDPR

### Anonimização preserva integridade fiscal
- `admin_gdpr_anonymize` substitui campos pessoais (users, client_addresses apagados, orders sem moradas/nome) mas NUNCA apaga linhas financeiras. Exige confirmação textual "APAGAR DADOS" + razão. Conta Auth: desativação manual no dashboard. Export via `admin_gdpr_export` (auditado). Migration `20260702073000`.
- **estado: atual.**

---

## Comunicação / Automação (Hermes, Robôs, Agent-Reach)

### Ponte Hermes → PC → Claude Code (E2E fechada)
- Telegram → Hermes (VPS, Docker `hermes-agent-fvnc`) → `ssh bora-pc` (tailscale, key) → user `hermes` no PC → `run-claude.cmd` → Claude Code headless. Auth = CONFIG_DIR partilhado `.claude` + ACLs. ⚠️ `tailscaled` não auto-arranca no container → recuperação `/root/bora-bridge-up.sh`.
- Modelo primário Hermes = **gemini-2.5-flash-lite** via provider `gemini` (Google direto, grátis); fallbacks 4 free OpenRouter. GLM-4.5-air:free virou PAGO (404).
- **estado: atual** (`project_ponte_hermes_pc_2026_06_28.md`, `project_hermes_soul_fix_2026_06_30.md`).

### Robot B v4 + BORA_DNA
- DNA em knowledge + Obsidian; EF robot-b v4 (cycle/digest/crosstalk); tabelas `robot_*` + guard + kill switches; ecrã admin inbox. ⚠️ **crons OFF até launch (T7)**. Armadilha: gemini-2.5-flash thinkingBudget=0.
- **estado: atual** (crons desligados até lançamento).

### Fase 5 — O Loop + Central de Autonomia (arquitetura HÍBRIDA)
- **Decisão do Danilo:** NÃO duplicar a fila. Robot B v4 já entregava ~70% (`robot_suggestions` = fila com nível 1/2/3, `AdminRobotSuggestionsScreen` = inbox, kill switch `robot_b_enabled`, dial `robot_b_auto_level1_enabled`, caps duros no SQL, push `notify-admin-urgent` v12 modo generic). A Fase 5 acrescenta só a **camada de goals** por cima — não reescreve o Robot B.
- **Delta (aplicado em prod ojykpzwqrtusfeakzrna, 2026-07-01):**
  - Migrations `20260701170000_autonomy_goals_fase5.sql` + seed `20260701170100_autonomy_goal_paridade_admin_seed.sql`. Tabelas `autonomy_goals` (o `/goal` + placar de paridade + tetos: `itens_por_ciclo`/`teto_max_turns`/`teto_orcamento_tokens`/`cadencia_min`) e `autonomy_backlog_items` (os 20 domínios, aponta para `robot_suggestions` + guarda `juiz_veredito`). RLS fechado. RPCs SECURITY DEFINER: `admin_autonomy_dashboard`, `admin_list_autonomy_backlog`, `admin_autonomy_set_switch` (só `robot_b_*` — não-financeiro), `maestro_next_backlog_item`, `maestro_link_suggestion`. Seed: goal `paridade-admin-360`, placar 1/20 (6🟢/4🟡/9🔴 + Parceiros feito).
  - Agente 26.º `maestro-autonomia` 🟡 (`.claude/agents/maestro-autonomia.md`) — dono do ciclo, evolui `robot-b`. Ver `exercito.md`.
  - Flutter `lib/screens/admin/admin_autonomy_center_screen.dart` (Central: placar, kill switch "PARAR TUDO", dial cauteloso/auto, backlog) + card em `admin_dashboard_screen.dart`. `flutter analyze` limpo.
  - Docs `docs/fase5/ENVELOPE_SEGURANCA.md` (5 paredes: Trava · Juiz · Tetos · Humano-acima-do-L1 · Kill switch) + `docs/fase5/GOAL_PARIDADE_ADMIN.md`. CLAUDE.md + agents/README (25→26 agentes).
- **Os 3 níveis (× Trava × Juiz × dial):** N1 🟢 auto reversível (só se o dial permitir) · N2 🟡 1 toque (fila + push) · N3 🔴 dinheiro = **só propõe** (a Trava bloqueia aplicar; ato humano).
- **Envelope de segurança (5 paredes):** Trava · Juiz obrigatório · Tetos · Humano-acima-do-L1 · Kill switch.
- **Testes provados (teto baixo, sem tocar dinheiro):** (1) loop pega 🟢 "Visualizador de auditoria" → Juiz aprova → fila `aguarda_ti`; (2) 🔴 "Zonas de entrega" só propõe, suggestion fica `nova` nunca `aplicada`; (3) kill switch → `maestro_next` devolve `KILL_SWITCH_ATIVO`; (4) teto `max_turns` atingido → `PARA_E_AVISA`; (5) push wiring (`admin_push_tokens` + `notify-admin-urgent` generic) validado.
- **Estado final seguro em prod:** `robot_b_enabled=true` (loop permitido), dial **cauteloso** (`robot_b_auto_level1_enabled=false`), placar 1/20. **Cron robot-b continua OFF até launch (T7)** — não contradiz a entrada Robot B v4 acima; a Fase 5 é a camada de goals, não liga crons.
- **estado: atual** (Fase 5, 2026-07-01; ligações: Cérebro Fase 2, Trava Fase 1, Juiz Fase 4, Auditoria 360°).

### Agent-Reach
- v1.5.0 no PC + Hermes VPS. Keyless 5/15: Web/YouTube/RSS/V2EX. ⚠️ YouTube bot-bloqueado intermitente no IP do VPS. Pendente Danilo: `gh auth login` (2 sítios) + Exa key opcional.
- **estado: atual.**

---

## Vertical TVDE (Bora Motorista)
- Vertical completa (Fases 1-6), categoria escondida TVDE 100% isolada (backend+dispatch+cliente+estafeta+admin PT-BR+ícone cat_motorista.png). Smoke com ROLLBACK ao vivo (10km €7/€5,60/€1,40). CI VERDE confirmado. Pendente Danilo: device test + Fase7 pagamentos.
- ⚠️ 2 sessões Claude no mesmo working tree = race git → fetch+rebase sempre.
- **Gap crítico ligado:** `driver_signup` força vehicle_type='motorcycle' (ver `bugs-resolvidos.md` #1).
- **estado: atual** (`project_bora_motorista_tvde.md`).

---

## Chat por vertical — tabela dedicada (padrão TVDE E1)

### Chat da Limpeza usa `cleaning_messages`, NÃO a tabela `messages` do delivery
- **Decisão (2026-07-06, commits `a374f13`/`4233d26`):** cada vertical isolada tem a sua tabela
  de chat (padrão TVDE E1). A tabela `messages` do delivery está acoplada a `orders` (id TEXT) e
  a RLS/Edge Fn de push só resolvem participantes por `orders` — reutilizá-la exigiria acoplar a
  Limpeza ao delivery.
- Implementação: `cleaning_messages` (RLS participantes-only, INSERT só em estados ativos),
  RPC `cleaning_mark_messages_read`, trigger `_cleaning_chat_push`
  (migration `20260705120000_cleaning_chat_profiles_kyc.sql`).
- **estado: atual** (detalhe em `semantica/vertical-limpeza.md`).

### Cartão da Limpeza cobra NA RESERVA (fim do hold manual)
- **Decisão (2026-07-06, commit `912ce6d`):** `cleaning-checkout` v2 — cartão E MB Way cobram
  no ato da reserva; cancelamento estorna via `reverse`. Motivo: hold Stripe expirava em ~7 dias
  e a captura pós auto-confirmação dependia de o cliente reabrir o tracking.
- Ação `capture` mantida **só** para holds legados (`requires_capture`).
- **Superado:** cartão com captura manual/hold —
  **estado: superado (por cleaning-checkout v2, 2026-07-06).**
