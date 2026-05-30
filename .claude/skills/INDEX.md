# Índice de Skills — Bora App

> Skills versionadas vivem em `bora_app/.claude/skills/` (este diretório).
> Branch: `autonomous-night-2026-04-29`. Atualizado: 2026-05-30 (S4-F). **45 skills.**
> Convenção: invocar via Skill quando o trigger corresponder; **ler `bora-knowledge`
> antes de qualquer ação** (foundation).

| Skill | Tipo | Quando usar |
|-------|------|-------------|
| **bora-knowledge** | foundation | Referência viva do projeto (design, regras, DB, edge fns, widgets). Consulta obrigatória por todas as outras antes de agir. |
| **ceo-ai** | orchestrator | Motor de decisão estratégica; arranca no início de cada tarefa (MODO PROTECÇÃO TOTAL). |
| **prompt-blindado-validator** | validator | Valida estrutura do prompt (MODO PROTECÇÃO, CEO-AI, business_rules, git push, /ctx, admin) antes de executar. |
| **auto-rules-sync** | sync | Sincronizar regras de negócio entre código, CEO-AI e Obsidian quando uma regra muda. |
| **onboard-partner-restaurant** | onboarder | Onboardar restaurante parceiro de pasta (info.yaml+produtos.csv+fotos) via register-partner. Dry-run default. |
| **onboard-partner-store** | onboarder | Onboardar loja parceira (retail). Categorias electrónica/vestuário/casa/beleza/brinquedos. |
| **onboard-partner-pharmacy** | onboarder | Onboardar farmácia parceira (só OTC; bloqueia receita; disclaimer; licença INFARMED). |
| **audit-driver-application** | auditor | Rever candidatura de estafeta (pending) e aprovar/rejeitar com auditoria. Dry-run default. |
| **audit-partner-application** | auditor | Rever candidatura de parceiro (pending) — NIF/IBAN/horário/categoria/assets — aprovar/rejeitar. Dry-run default. |
| **ban-or-reactivate-entity** | operator | Banir/reativar client (Auth) / driver (colunas) / partner (is_active_admin); bloqueia com pedidos em curso. Dry-run default. |
| **force-driver-logout** | operator | Forçar logout de estafeta via Edge Fn admin-force-driver-logout. Preview; --confirm executa. |
| **add-home-category** | codegen | Gerar diff (Modo A) p/ adicionar 8ª categoria à home (gradient+tile+rota). Não toca lib/ sem --apply. Audita 1-laranja. |
| **update-design-token** | codegen | Gerar diff p/ alterar token de cor global + ecrãs afetados. Não toca lib/ sem --apply. Avisos primary/accent. |
| **update-platform-setting** | config | Alterar 1 chave de platform_settings (dry-run SQL+impacto; --commit+auditoria+ADR). Chaves blindadas exigem --i-know-what-im-doing. |
| **pre-launch-checklist** | auditor | Auditoria read-only de prontidão (pending, catálogo sem preço/imagem, settings críticos, audit recente). |
| **sync-market-photos** | data | Dar foto a produtos de mercado (needs_photo) reutilizando fotos donor (Mercadona) por search_normalized. DB-interno, zero scraping/preço. |
| **weekly-market-prices** | data | Orquestrar update semanal de preços; só Continente (Product-Show+JSON-LD, 3.5s/req). Nunca Uber/Glovo. Dry-run default. |
| **dedupe-market-products** | data | Dedupe por search_normalized+loja; soft-delete (is_available=false) do menos completo. Backup CSV. Nunca hard delete/parceiros. |
| **market-data-sync** | data | Sincronizar catálogo de qualquer loja (Glovo/Uber → site oficial); UPDATE/INSERT sem duplicados. |
| **market-data-cleaner** | data | Limpar catálogo por mercado (sem imagem/marca/preço; tradução ES→PT; soft-delete). |
| **category-mapper-v2** | data | Reclassificar produtos em 22 categorias canónicas (keywords PT+ES+EN+FR, dry-run). |
| **taxonomy-mapper** | data | Classificar produtos em 18 secções canónicas Bora (popular `products.taxonomy_section`). |
| **add-support-faq** | support | Acrescentar FAQ ao RAG do support-chatbot (support_knowledge_chunks) + reindex embedding. Bloqueia refund/cancelamento/$ (escalam). Dry-run default. |
| **add-support-skill** | support | Scaffold playbook p/ agente de suporte (support_skills); toca $/auth/Stripe/GDPR → write_shadow+handoff; active=false. Dry-run default. |
| **smoke-test-critical-paths** | qa | Health-check read-only (Edge Fns via OPTIONS, RPCs, tabelas-chave). Zero escrita/pagamentos/pedidos. Correr pré-build. |
| **audit-protected-zones** | qa | Meta-skill read-only: sha256 ficheiros-chave + triggers + Edge Fns pagamento vs baseline. Deteta drift. Correr pré-build. |
| **ask-knowledge-base** | support | Robô B: responder perguntas crosstalk (a_to_b/pending) via knowledge base RAG. |
| **driver-earnings-validator** | finance | Validar `driver_earnings` de um pedido vs fórmula pricing_service; diagnosticar discrepância. |
| **storeshopping-v2-debugger** | debug | Diagnosticar pedido storeShopping V2 não-parceiro (orders+items+receipts+wallet+audit). |
| **storage-bucket-validator** | ops | Auditar bucket Supabase Storage + RLS (uploads a falhar 400/403, validar deploy RLS). |
| **deploy-edge-function** | devops | Deploy seguro de Edge Fn com diff prévio (preserva verify_jwt); funções financeiras exigem --i-know-what-im-doing. Dry-run default. |
| **seed-demo-data** | devops | Criar dados demo isolados (DEMO_/is_test_order, só cash) + cleanup reversível. Nunca Stripe. Dry-run default. |
| **backup-restore-table** | devops | Backup read-only (JSON) + restore UPSERT; tabelas financeiras exigem --i-know-what-im-doing. Dry-run no restore. |
| **generate-release-notes** | devops | git log desde último tag → RELEASE_NOTES_v{N}.md PT-PT (feat/fix/...) + secção testers. Read-only; sem tag/push. |
| **audit-orange-rule** | design | Audita "1 laranja/ecrã" em lib/screens/ (dominante vs semântico); [OK]/[!]/[X]. Read-only. |
| **migrate-screen-to-design** | design | MODO A: re-skin 1 ecrã (hex→AppColors tokens) com diff; --apply backup+flutter analyze. Não toca lógica. |
| **run-weekly-payouts** | financeiro | Relatório de payouts (soma ledger_entries por driver/parceiro) + CSV. Read-only; nunca transfere. |
| **audit-ledger-entries** | financeiro | Forensics read-only do ledger (órfãs/duplicados/sinais inesperados/pedidos incompletos). Só reporta. |
| **notify-broadcast** | operacoes | Push em massa segmentado (push_broadcasts→execute-broadcast). Dry-run; --commit exige --confirm. Audita. |
| **manage-promo-codes** | operacoes | Criar/listar/desativar promos via RPCs admin (promo_codes). Dry-run; --commit chama RPC. Avisa margem. |
| **refund-assistant** | financeiro | SHADOW: propõe refund (fee escalão + split 80/20) + audit; NUNCA executa (Stripe intocado). |
| **reservation-ops** | operacoes | Listar reservas + marcar chegada via RPC partner_mark_arrival (€2 interno). no_show = guidance. Dry-run. |
| **skills-doctor** | meta | Valida todas as skills (frontmatter, name==pasta, depends_on, py_compile, README/req, dry-run). Read-only [OK]/[!]/[X]; exit=nº erros. |
| **update-bora-knowledge** | meta | Deteta drift knowledge vs repo (Edge Fns vs 08; pastas vs INDEX). Read-only: propõe em _preview/, NUNCA edita docs (Knowledge Protocol). |
| **generate-skills-readme** | meta | Gera README.md mestre agrupado por categoria, do frontmatter+corpo. Dry-run → _preview/; --write grava README.md. NÃO toca no INDEX.md curado. |

## Notas
- **Onboarders** (`onboard-partner-*`) dependem de `bora-knowledge` e chamam as Edge Fns
  `register-partner` + `upload-restaurant-asset` (não recriam infra). Scripts partilhados
  (`_shared`/`geocode`/`process_images`) vivem no `onboard-partner-restaurant` e são
  reutilizados por store/pharmacy (DRY).
- **Auditores/operadores S2** (`audit-*`, `ban-or-reactivate-entity`, `force-driver-logout`)
  dependem de `bora-knowledge`, escrevem em `admin_audit_log` (quem/quando/razão) e reutilizam
  o motor S1 (`_shared`). dry-run é default; ações destrutivas exigem `--commit`/`--confirm`.
- **Pendências de schema** (S2): `restaurants` e `users` sem colunas de ban (driver tem);
  `licenca_infarmed` ausente em `restaurants`. Ver `bora-knowledge/knowledge/12-recipes.md`.
- **Codegen/config S3** (`add-home-category`, `update-design-token`, `update-platform-setting`,
  `pre-launch-checklist`): **Modo A** — geram diff/SQL em `_preview/` para revisão; só tocam
  `lib/`/DB com `--apply`/`--commit` (backup + `admin_audit_log` + nota ADR em `decisions/`).
  `pre-launch-checklist` é read-only. `REPO_ROOT` = `parents[4]` (bora_app).
- **Mercados S4-A** (`sync-market-photos`, `weekly-market-prices`, `dedupe-market-products`):
  só lojas em `MARKET_STORES` (recusam parceiros/fast-food); **nunca preço de Uber/Glovo**;
  soft-delete = `is_available=false` (products não tem `is_deleted/deleted_at` — pendência);
  dry-run default. Preço por scraping só Continente (auchan/pingodoce bloqueados por robots.txt).
- **Suporte/QA S4-B** (`add-support-faq`, `add-support-skill`, `smoke-test-critical-paths`,
  `audit-protected-zones`): FAQs vivem em `support_knowledge_chunks` (RAG; não há `support_faqs`),
  embedding via Edge Fn `reindex-knowledge` (Gemini 768d, admin-only); playbooks em `support_skills`
  (mode {read_only,write_shadow,escalate}); skills que tocam $/auth/Stripe/GDPR → write_shadow+handoff,
  active=false. QA é read-only (smoke via OPTIONS; audit vs baseline). **Admin UI** p/ editar FAQs/skills = pendência.
- **DevOps S4-C** (`deploy-edge-function`, `seed-demo-data`, `backup-restore-table`,
  `generate-release-notes`): Edge Fns financeiras protegidas no deploy; seed só cash + reversível
  por `DEMO_`/`is_test_order`; restore de tabelas financeiras gated; release-notes read-only sobre git.
  Backups em `bora_app/.claude/.ai/backups/`. Fix Windows: subprocess UTF-8 + log resistente a cp1252.
- **Design/Financeiro S4-D** (`audit-orange-rule`, `migrate-screen-to-design`, `run-weekly-payouts`,
  `audit-ledger-entries`): design audita/migra (migrate em MODO A, só cores, nunca lógica);
  financeiro é read-only (payouts soma ledger sem executar; audit-ledger só deteta). Fórmulas
  lidas de `05-business-rules` (não recalculadas). `_shared.log` central agora resiliente a cp1252.
- **Cliente/Operações S4-E** (`notify-broadcast`, `manage-promo-codes`, `refund-assistant`,
  `reservation-ops`): usam infra existente (Edge Fn `execute-broadcast` via `push_broadcasts`;
  RPCs `admin_*_promo_code`, `partner_mark_arrival`). **refund-assistant é SHADOW** (só propõe,
  nunca executa — regra 5B). dry-run default; broadcast exige `--commit --confirm`. **Admin UI**
  p/ promos e broadcast = pendência clara.
- **Consolidação S4-F** (`skills-doctor`, `update-bora-knowledge`, `generate-skills-readme`):
  meta-skills read-only/preview, **stdlib-only**, todas reusam o `_shared.py` de `skills-doctor`
  (parser de frontmatter + descoberta de skills). `skills-doctor` valida tudo (exit code = nº de
  erros); `update-bora-knowledge` **nunca** edita docs curados — `detect_drift` propõe em `_preview/`
  e `apply_updates` (MODO A) só escreve o ficheiro auto-gerido `00-auto-facts.md` (Knowledge Protocol);
  `generate-skills-readme` gera `README.md` mestre sem tocar no `INDEX.md` curado.
  **Estado S4-F:** `skills-doctor` corre limpo — **0 `[X]`**, 34 `[OK]`, 11 `[!]` (skills antigas
  sem README/`type`/`depends_on` — avisos aceitáveis, não bloqueiam). Corrigido: `prompt-blindado-validator`
  ganhou frontmatter YAML + README (era o único `[X]`). **Pendência (precisa aprovação):** Edge Fns —
  `confirm-mbway-payment` não documentada em 08, e `execute-broadcast`/`admin-cancel-reservation`/`robot-b`/
  `gemini-diagnostic`/`restaurant-assets`/`upload-driver-document`/`upload-order-photo` citadas no doc sem
  pasta (confirmar remota/renomeada/planeada — não auto-editado por ser doc curado).
- Logs de auditoria de sessões antigas movidos para `sistema/` (não são skills).
