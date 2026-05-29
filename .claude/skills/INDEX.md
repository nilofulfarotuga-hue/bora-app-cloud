# Índice de Skills — Bora App

> Skills versionadas vivem em `bora_app/.claude/skills/` (este diretório).
> Branch: `autonomous-night-2026-04-29`. Atualizado: 2026-05-29 (S2). **19 skills.**
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
| **market-data-sync** | data | Sincronizar catálogo de qualquer loja (Glovo/Uber → site oficial); UPDATE/INSERT sem duplicados. |
| **market-data-cleaner** | data | Limpar catálogo por mercado (sem imagem/marca/preço; tradução ES→PT; soft-delete). |
| **category-mapper-v2** | data | Reclassificar produtos em 22 categorias canónicas (keywords PT+ES+EN+FR, dry-run). |
| **taxonomy-mapper** | data | Classificar produtos em 18 secções canónicas Bora (popular `products.taxonomy_section`). |
| **ask-knowledge-base** | support | Robô B: responder perguntas crosstalk (a_to_b/pending) via knowledge base RAG. |
| **driver-earnings-validator** | finance | Validar `driver_earnings` de um pedido vs fórmula pricing_service; diagnosticar discrepância. |
| **storeshopping-v2-debugger** | debug | Diagnosticar pedido storeShopping V2 não-parceiro (orders+items+receipts+wallet+audit). |
| **storage-bucket-validator** | ops | Auditar bucket Supabase Storage + RLS (uploads a falhar 400/403, validar deploy RLS). |

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
- Logs de auditoria de sessões antigas movidos para `sistema/` (não são skills).
