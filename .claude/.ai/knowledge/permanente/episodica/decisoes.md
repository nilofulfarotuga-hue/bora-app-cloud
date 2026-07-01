---
tema: decisoes · escopo: projeto · estado: atual · atualizado: 2026-07-01
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

## Comunicação / Automação (Hermes, Robôs, Agent-Reach)

### Ponte Hermes → PC → Claude Code (E2E fechada)
- Telegram → Hermes (VPS, Docker `hermes-agent-fvnc`) → `ssh bora-pc` (tailscale, key) → user `hermes` no PC → `run-claude.cmd` → Claude Code headless. Auth = CONFIG_DIR partilhado `.claude` + ACLs. ⚠️ `tailscaled` não auto-arranca no container → recuperação `/root/bora-bridge-up.sh`.
- Modelo primário Hermes = **gemini-2.5-flash-lite** via provider `gemini` (Google direto, grátis); fallbacks 4 free OpenRouter. GLM-4.5-air:free virou PAGO (404).
- **estado: atual** (`project_ponte_hermes_pc_2026_06_28.md`, `project_hermes_soul_fix_2026_06_30.md`).

### Robot B v4 + BORA_DNA
- DNA em knowledge + Obsidian; EF robot-b v4 (cycle/digest/crosstalk); tabelas `robot_*` + guard + kill switches; ecrã admin inbox. ⚠️ **crons OFF até launch (T7)**. Armadilha: gemini-2.5-flash thinkingBudget=0.
- **estado: atual** (crons desligados até lançamento).

### Agent-Reach
- v1.5.0 no PC + Hermes VPS. Keyless 5/15: Web/YouTube/RSS/V2EX. ⚠️ YouTube bot-bloqueado intermitente no IP do VPS. Pendente Danilo: `gh auth login` (2 sítios) + Exa key opcional.
- **estado: atual.**

---

## Vertical TVDE (Bora Motorista)
- Vertical completa (Fases 1-6), categoria escondida TVDE 100% isolada (backend+dispatch+cliente+estafeta+admin PT-BR+ícone cat_motorista.png). Smoke com ROLLBACK ao vivo (10km €7/€5,60/€1,40). CI VERDE confirmado. Pendente Danilo: device test + Fase7 pagamentos.
- ⚠️ 2 sessões Claude no mesmo working tree = race git → fetch+rebase sempre.
- **Gap crítico ligado:** `driver_signup` força vehicle_type='motorcycle' (ver `bugs-resolvidos.md` #1).
- **estado: atual** (`project_bora_motorista_tvde.md`).
