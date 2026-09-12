# 11 — Convenções

## Idioma
- **PT-PT** em todo o conteúdo user-facing (UI, mensagens, templates, descrições de produto).
  Glossário: "telemóvel", "morada", "encomenda", "carrinho", "fatura", "código postal".
- **PT-BR** aceite em comentários de dev / relatórios internos (Danilo lê).
- Chaves Supabase, enums e comentários de código técnico: **inglês** (ex. `ledger_entries`, `user_id`).
- 🚩 Bug pré-launch documentado: strings inglês em `restaurant_dashboard` — **resolvido** (commit 0187c0a).

## Design
- **1 laranja por ecrã** (CTA único). Ver [01](01-design-system.md).
- Importar widgets via barrel `widgets/bora/bora.dart`.
- Tokens `AppColors.*` / `AppTheme.*` — nunca hex hardcoded em ecrãs (Fase 2 limpou 71 ocorrências).

## Estado / arquitetura
- Model → Store → Screen. Provider chain definido em `main.dart` (ordem de dependência).
- `OrderStatus` enum (nunca String). Transições escrevem DB primeiro.
- `_RootNavigator` widget-rebuild (sem `Navigator.push` para ecrãs principais).

## Git
- **Repo git: `bora_app/`** (NÃO o root `projetosflutter`). Usar `git -C bora_app ...`.
- Branch de trabalho atual: `autonomous-night-2026-04-29`.
- Push após cada commit lógico: `git -C bora_app push origin autonomous-night-2026-04-29`.
- Skills versionadas vivem em `bora_app/.claude/skills/` (não no root `.claude/skills/`).

## Commits
- Estilo: `tipo(scope): descrição` — ex. `feat(skill): bora-knowledge`, `fix(...)`, `docs(...)`.
- Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Mudanças cirúrgicas; cada linha alterada traça ao pedido.

## Build / release
- `flutter analyze` deve devolver **0 erros** antes de commit de código.
- `versionCode` Android: incrementar **só** quando há build. Esta sessão de skills **NÃO** incrementa.
- Release: `--dart-define-from-file=.dart_defines`; `pk_live_...` no Stripe.

## Prompt / processo
- Tarefas começam com `⚠️ MODO PROTECÇÃO TOTAL ⚠️` + invocam CEO-AI.
- `prompt-blindado-validator` valida estrutura do prompt antes de executar.
- Validation Gate (CLAUDE.md): pagamentos/DB/segurança/effort>1h → parar e validar.
- Fim de sessão: `/ctx doctor` + `/ctx stats`.

## Fontes adicionais
- `bora_app/CLAUDE.md` (PRIORITY CONTEXT, Karpathy, Validation Gate).
- CEO-AI `SKILL.md` (§7 Regras permanentes, §8 Workflow).
