# Sessão — Sistema de Agentes Nativos (Lote 1)

> Data: 2026-06-23 · Branch: autonomous-night-2026-04-29 · Modelo: Opus 4.8
> Estado: **NÃO commitado** (Danilo decide). Staging feito.

## O que foi construído
Criado `bora_app/.claude/agents/` (não existia) como diretório formal de agentes.

- **4 specs migrados** de `projetosflutter/.claude/skills/ceo-ai/sub-agents-specs/` → `agents/`
  com frontmatter consolidado (name/description/version/migrated_from/migration_date/tools):
  `checkout-fixer`, `design-system-applier`, `e2e-test-builder`, `notifications-integrator`.
- **5 agentes novos**: `obsidian-sync`, `catalogo-visual`, `db-migrations`, `admin-sync`,
  `seguranca-rls` (contrato: Identidade/Objetivo/Limites/Ferramentas/Protocolo/Output/Memória/Admin-Check).
- **Suporte**: `README.md` (SKILL vs AGENTE), `template.md`, `agent-memory.md` (6 regras globais).
- **Editados**: `CLAUDE.md` (secção "Sistema de Agentes") e `skills/INDEX.md` (distinção skill/agente).

## Decisões
- **Local dos agentes** = `bora_app/.claude/agents/` (escolha do Danilo via AskUserQuestion).
  Motivo: dentro do git, junto a `CLAUDE.md`/`business_rules.md`; combina com `git add .claude/`.
  Os 4 specs originais foram **copiados** (continuam em `projetosflutter/.claude/...`, fora do git).
- **Frontmatter `tools`**: agentes que precisam de MCP (catalogo-visual, db-migrations, seguranca-rls)
  **omitem** o allowlist (herdam tudo → alcançam Supabase/nano-banana). File-based declaram tools
  canónicos (`Bash, Read, Write, Edit, Grep, Glob`) — não os nomes minúsculos do prompt (não resolvem).

## Factos verificados
- **44 Edge Functions locais** (`supabase/functions/*/index.ts`). CEO-AI SKILL.md diz "43 deployed/38 locais" → **stale**.
- `admin_database_screen` e `admin_security_screen` **NÃO existem** → flag CRIAR (db-migrations / seguranca-rls).
- `admin_catalog_screen` + `admin_category_mapping_screen` existem (catalogo-visual → actualizar).

## Pendente
- **nano-banana (FASE 4) NÃO testado**: `.mcp.json` está em `bora_app/` mas a sessão corre de
  `projetosflutter/`; tools MCP carregam no arranque. → Abrir nova sessão **a partir de `bora_app/`**
  e correr o teste (pasta `C:\Users\danil\Desktop\Bora\` existe).
- Confirmar nº de Edge Functions **deployed** via MCP `list_edge_functions` e atualizar CEO-AI SKILL.md (com aprovação).
- design-system-applier: hex no corpo (`#2E7D32`/`#E65100`) está stale vs atual (`#16A34A`/`#F97316`) — corpo preservado por instrução; corrigir em lote futuro.
