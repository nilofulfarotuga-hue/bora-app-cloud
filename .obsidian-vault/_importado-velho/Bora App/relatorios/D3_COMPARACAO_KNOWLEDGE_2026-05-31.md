# 🔬 D3 — Comparação dos 2 CEO-AI e dos 2 Knowledge Stores
> Data: 2026-05-31 · Fase 1 (read-only + relatório). **NADA fundido/arquivado** — só comparação + recomendação.
> Backup completo em `_backup_knowledge_2026-05-31/` (curado 83 + vivo 14 + 2 SKILLs).

---

## A) OS DOIS `ceo-ai/SKILL.md`

| | **ROOT** `projetosflutter/.claude/skills/ceo-ai/SKILL.md` | **BORA_APP** `bora_app/.claude/skills/ceo-ai/SKILL.md` |
|---|---|---|
| Tamanho / data | 13126 bytes · **19 Mai** (mais recente) | 10107 bytes · **8 Mai** (mais antigo) |
| Frontmatter YAML | ❌ **NÃO tem** (começa com `# CEO-AI`) | ✅ **tem** (`name: ceo-ai` + `description` rica) |
| Carregado pelo harness | ✅ **SIM** (base dir desta sessão = root) | ❌ não |
| Conteúdo | **Mais rico:** §1.5 Knowledge Protocol, §1.6 Autonomy Principle (resolve vs pergunta), sub-agent specs, pipeline mercados (Wells/Worten/…), regras 10+5+5%, MBWay flow, segurança credenciais, estado sessão autónoma 19 Mai | **Mais pobre/antigo:** Purpose, Owner Profile, Priority Ranking, Decision Rules, Launch Checklist (Mai 8), "Edge Functions (8)" |
| Factos | "5 Edge Functions" → **já corrigido hoje para 43** | "Edge Functions (8)", paleta `#2E7D32/#E65100` (stale) |

### Recomendação CEO-AI canónico
- **CONTEÚDO canónico = ROOT** (mais recente, mais completo, é o que o harness realmente lê, e já foi corrigido hoje).
- **MAS o ROOT não tem frontmatter YAML** → o `bora_app` tem um `name/description` bom. **Ação na Fase 2:** portar o frontmatter do `bora_app` para o ROOT (para discovery/skills-doctor), e **arquivar** o `bora_app` (stale) em `_archive/` (nunca apagar).
- 🔴 **Decisão estrutural para o Danilo:** as **45 skills vivem em `bora_app/.claude/skills`**, mas o harness desta sessão leu o `ceo-ai` da **raiz**. Há dois diretórios de skills. Duas opções:
  - **(A) Consolidar tudo em `bora_app/.claude/skills`** (onde estão as 45) — mover o conteúdo fresco do ROOT para lá, arquivar o stale. Requer confirmar/apontar o harness para `bora_app`. *(Recomendado — fonte única.)*
  - **(B) Manter o ROOT como casa do ceo-ai** (como está) e arquivar só o duplicado `bora_app`. Mais simples, mas mantém 2 diretórios de skills.
  - **Recomendo (A)**, mas precisa da tua confirmação de qual `.claude/skills` o harness deve ler em produção.

---

## B) OS DOIS KNOWLEDGE STORES

| | **CURADO** `projetosflutter/.claude/.ai/knowledge` | **VIVO** `bora_app/.claude/skills/bora-knowledge/knowledge` |
|---|---|---|
| Ficheiros | **83** | **14** (00-auto-facts + 01–12) |
| Estado | Congelado **25 Abr** (INDEX last_synced) — factos técnicos stale (já corrigi stack.md hoje) | Atualizado até **30 Mai** (00-auto-facts) |
| Lido por | CEO-AI (Knowledge Protocol) | **As 45 skills** (`bora-knowledge` é consulta obrigatória) |
| Conteúdo único | `decisions/` (ADRs), `roadmap/` (tier1-4), `references/` (competitors, compliance-portugal), `business-rules/*.md`, `architecture/`, **`from-obsidian/`** (importação do vault) | `01-design-system`, `02-home-categories`, `03-navigation`, `04-widgets`, `05-business-rules`, `06-flows`, `07-db-key-tables`, `08-edge-functions`, `09-platform-settings`, `10-protected-zones`, `11-conventions`, `12-recipes` |
| Natureza | **Estratégico/histórico** | **Técnico/operacional** |

### Divergências principais
- **Edge Functions:** curado dizia "5" (stack.md, corrigido→43 hoje); vivo dizia "44"→corrigido 43 + nota drift. `00-auto-facts` diz "38 local" (✅ correto — é o nº local, não deployed).
- **Paleta:** curado `#2E7D32/#E65100` (corrigido→`#16A34A/#F97316`); vivo `01-design-system` já tinha a paleta nova (provável — é a fonte técnica).
- **Sobreposição:** ambos cobrem business-rules + architecture, mas com **números diferentes** → fonte de confusão.
- **Só no curado:** ADRs, roadmap, competitors, compliance, from-obsidian. **Só no vivo:** design tokens, widgets, recipes operacionais.

### Recomendação de reconciliação (para Fase 2)
- **VIVO = fonte técnica única** (edge fns, tabelas, design, fluxos, zonas protegidas, platform_settings). É o que as skills leem — deve ser a verdade técnica.
- **CURADO = só estratégia/roadmap/decisions/competitors/compliance + `from-obsidian`.** **Arquivar** (mover para `_archive/`, nunca apagar) os ficheiros técnicos do curado que duplicam o vivo e envelhecem mal (ex.: `architecture/stack.md` edge-fns/paleta → apontar para o vivo `08`/`01`).
- **Factos técnicos contáveis** (edge fns, tabelas, skills) → sempre via `00-auto-facts.md` (skill `update-bora-knowledge` MODO A), **nunca à mão nos 01-12**.

---

## C) RECOMENDAÇÃO RESUMIDA
1. **CEO-AI canónico:** conteúdo do **ROOT** + frontmatter do bora_app; arquivar o stale. Decisão estrutural (A vs B) é tua.
2. **Knowledge:** VIVO = técnico; CURADO = estratégia (arquivar duplicados técnicos). Reconciliar via `update-bora-knowledge` MODO A.
3. **Nunca apagar** — tudo o que sai vai para `_archive/`.
