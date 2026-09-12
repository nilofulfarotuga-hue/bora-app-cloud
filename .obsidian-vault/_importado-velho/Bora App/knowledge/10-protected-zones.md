# 10 — Zonas Protegidas (NÃO TOCAR)

> Ler SEMPRE antes de qualquer edit. Estas áreas só se mexem quando a tarefa é
> **exatamente** sobre elas, e com aprovação (MODO PROTECÇÃO TOTAL).

## Código produtivo — não tocar sem aprovação
- `bora_app/lib/screens/` — **Fase 4 fechada** (27 ecrãs re-skinned).
- `bora_app/lib/widgets/bora/` — **Fase 3 fechada**.
- `bora_app/lib/config/` — paleta, tema, business_rules.dart.
- `bora_app/lib/services/` — dispatch, **pricing_service**, FCM, payment.
- Edge Functions existentes — **chamar**, nunca recriar/editar nesta classe de tarefas.

## Sistemas críticos
- **dispatch-engine** (Edge Fn) — fonte de verdade do dispatch. O `DispatchEngine`
  Flutter é **NO-OP** (desativado); não reativar sem aprovação.
- **pricing_service / pricing_calculate** — todo o cálculo de fees. Nunca duplicar
  lógica de preço noutro sítio. Markup 15% non-partner é aplicado aqui em runtime.
- **Triggers DB** — ex. `trg_award_tokens_on_delivery`, `orders_financial_lock`
  (imutabilidade financeira pós-criação). Não alterar.
- **bora_tokens** — economia de tokens. Não mexer em saldos/regras sem aprovação.
- **Stripe / pagamentos / dinheiro real** — create-payment-intent, refund, webhook,
  MB WAY LIVE. Zero-tolerance: validações server-side são propositadas.
- **Realtime channels** — `orders_channel`, `public:drivers`. Não mudar nomes/lógica.

## Dados
- **Fotos reais de produto** — nunca alterar/substituir. Scraping mantém imagem da fonte.
- **Preço dos mercados** — sempre **puro** (sem markup embutido). Markup só em runtime.
- **Mercados são sempre não-parceiros** (`is_partner=false`, `user_=NULL`).
- Soft-delete sempre que possível (`is_available=false` / `is_active=false`), **nunca DELETE físico** em catálogo.

## Segurança / credenciais
- Nunca hardcoded creds em `lib/` — usar `String.fromEnvironment` + `.dart_defines` (gitignored).
- `SERVICE_ROLE_KEY` / `OPENAI_API_KEY` só em `backend/.env` e `scripts/scraper/.env`.
- RLS policies — não enfraquecer.

## Regra para skills/onboarders
As onboarders **chamam** Edge Functions (que já têm RLS e lógica correta). **Não**
fazem `apply_migration` nem escrevem direto em tabelas sensíveis. dry-run é default.

## Fontes adicionais
- `.claude/.ai/knowledge/architecture/disabled-systems.md` (DispatchEngine Flutter NO-OP).
- `bora_app/CLAUDE.md` (Validation Gate + Karpathy "Surgical Changes").
- CEO-AI `SKILL.md` §1.6 (Autonomy Principle) e §7 (NUNCA).
