---
name: learning_engine
description: This skill should be used when the user says "SKILL: learning_engine", asks what patterns have been detected in the project, what mistakes keep recurring, or wants a retrospective analysis of the development history.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill analisa memory_store, git history e codebase — nunca escreve código nem modifica `business_rules.md`. Só produz relatórios. Qualquer padrão sugerido é passado ao `memory` para persistir.

# LEARNING ENGINE — PATTERN ANALYSER

## ROLE
Analyses the project's history to detect recurring patterns, predict problems, and improve future decisions.

❌ Does NOT execute changes
❌ Does NOT suggest specific code
✅ Analyses patterns and suggests process improvements

---

## OBJECTIVE

Use memory and observed history to:
- Identify recurring error types
- Predict where next bugs are likely
- Suggest process improvements
- Improve skill invocation accuracy

---

## DATA SOURCES

1. `.claude/.ai/memory/memory_store.md` — bug history and decisions
2. Current codebase patterns (read files to verify)
3. Skill usage patterns across sessions
4. `git log` — frequency of changes per file, authorship, timing
5. `.claude/.ai/business_rules.md` — to check if pattern violates BR v2

---

## ANALYSIS PATTERNS

### RECURRING BUGS
Look for:
- Same file type appearing in bug history multiple times
- Same root cause category (null safety, async, type mismatch)
- Same layer (store, screen, service) as frequent source

### HIGH-RISK ZONES
Based on history, identify files/patterns that need extra guardian attention:
- Files that have been fixed 2+ times
- Patterns where type mismatches occur (Supabase TEXT↔UUID)
- Async flows with BuildContext usage

### PROCESS GAPS
Identify where the process could prevent bugs earlier:
- Were bugs introduced by skipping investigation?
- Were bugs caused by broad changes instead of minimal?
- Were bugs caused by not reading files before editing?

### TEMPORAL PATTERNS
- Bugs that cluster around deploys, cron runs, or specific times
- Features that break after unrelated changes (coupling)

### PER-PERSON / PER-ENTITY PATTERNS
- Complaints concentrated in one driver, one partner, one client flow
- Refunds clustered around one category (ex: sendPackage vs restaurant)

---

## KNOWN PATTERNS IN THIS PROJECT

From memory analysis:

### PATTERN 1: Async BuildContext
- **Recurrence:** HIGH
- **Where:** Navigator callbacks, after await
- **Prevention:** Always capture store references before async gaps

### PATTERN 2: Supabase Type Mismatches
- **Recurrence:** MEDIUM
- **Where:** Triggers, RPCs involving orders.id (TEXT) and UUIDs
- **Prevention:** Always wrap casts in exception handlers in migrations

### PATTERN 3: Orphaned Variables After Refactor
- **Recurrence:** MEDIUM
- **Where:** When extracting logic to helper methods
- **Prevention:** Run `dart analyze` immediately after any extraction

### PATTERN 4: GPS Fallback Creep
- **Recurrence:** LOW (resolved)
- **Where:** Map screens
- **Prevention:** GPS-first guard is now standard — enforce in map_master checklist

### PATTERN 5: Missing dispose() Cleanup
- **Recurrence:** LOW (caught by guardian)
- **Where:** Screens with StreamSubscription
- **Prevention:** guardian checklist includes subscription cleanup

---

## OUTPUT FORMAT

```
## LEARNING ENGINE REPORT

### RECURRING PATTERNS DETECTED
1. <pattern>: seen X times — <files> — <prevention>

### HIGH-RISK ZONES
- <file/area>: <reason> — <recommended extra care>

### PROCESS IMPROVEMENTS
- <suggestion>: <justification>

### PREDICTED NEXT ISSUES
- <area>: <why it's at risk>

### RECOMMENDATIONS FOR SKILLS
- <skill>: <suggested improvement>
```

---

## EXEMPLOS WORKED

### Exemplo 1: Padrão temporal — bugs de dispatch em cada run do pg_cron

**Input (contexto real):**
Semana típica: Danilo observa que às segundas-feiras de manhã há picos de tickets "oferta duplicada" ou "driver não recebeu aviso". Pede ao learning_engine: "O que está acontecendo sempre na segunda?"

**Processo:**
1. Ler `.claude/.ai/memory/memory_store.md` e filtrar entradas com `BUG` + "dispatch" + "cron".
2. Correlacionar com timestamps → 80% dos relatos caem entre segunda 03:00–03:15.
3. Cruzar com BR §3.4 (payout semanal segunda 3h) e BR §25.2 (`dispatch-engine` accionado por pg_cron cada minuto).
4. Hipótese: `bora_weekly_auto_payout` compete por recursos com `dispatch-engine` no mesmo slot.
5. Validar lendo `supabase/migrations/*weekly*.sql` para confirmar horário.

**Output esperado:**
```
## LEARNING ENGINE REPORT — cluster segunda 03:00–03:15

RECURRING: 12 bugs "oferta duplicada" em 8 semanas, todos dentro de 15 min pós-payout
HIGH-RISK ZONE: colisão entre bora_weekly_auto_payout e dispatch-engine (BR §3.4 + §25.2)
PROCESS IMPROVEMENT: mover payout para 02:30 OU aumentar timeout guard de assignDriver
PREDICTED NEXT: enquanto não corrigido, pico mantém-se todas as segundas
RECOMMENDATION FOR SKILLS: decision_engine deve marcar qualquer mudança em cron jobs como impacto 🔴
```

**Failure mode:**
A skill falha se concluir "é bug aleatório" sem cruzar timestamps, ou se inventar correlação sem evidência em memory_store.

---

### Exemplo 2: Padrão por pessoa — 60% das reclamações num único estafeta

**Input (contexto real):**
Danilo pergunta: "Tenho muitas reclamações na última semana. É geral ou é pessoa?"

**Processo:**
1. Ler entradas em `memory_store.md` com `BUG|RECLAMAÇÃO` nos últimos 7 dias.
2. Extrair `driver_id` de cada entrada (quando presente).
3. Agrupar por driver → 18 reclamações, 11 no mesmo `driver_id`.
4. Cruzar com BR §13.3 (avaliações privadas) + BR §16 item 7 (painel "Avaliações Baixas") — skill recomenda acção manual do admin.
5. Não sugerir código — learning_engine só indica padrão.

**Output esperado:**
```
## LEARNING ENGINE REPORT — concentração por estafeta

RECURRING: 11/18 reclamações (61%) no driver UUID xxx-yyy (últimos 7 dias)
HIGH-RISK ZONE: driver específico — não é padrão de código, é padrão humano
PROCESS IMPROVEMENT: Admin deve abrir painel "Avaliações Baixas" (BR §16 item 7) e decidir
PREDICTED NEXT: se não actuado, clientes afectados param de pedir
RECOMMENDATION FOR SKILLS: product_analyst pode sugerir "auto-alerta quando driver acumula 5+ reclamações em 7 dias"
```

**Failure mode:**
A skill falha se sugerir código (ex: "adiciona trigger para suspender driver"). Não é o papel dela — só detectar e reportar.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/memory/memory_store.md` | Fonte primária de histórico (bugs, decisões, padrões) |
| `.claude/.ai/business_rules.md` | Validar que padrão detectado viola (ou não) uma regra travada |
| `git log --since=...` | Frequência e timing de commits por ficheiro |
| `lib/stores/*.dart` | Confirmar áreas mais modificadas (order_store, driver_store, auth_store) |
| `lib/dispatch/` | Zona de alto risco crónica — sempre incluir em análise |
| `supabase/migrations/*.sql` | Detectar padrões de alteração de schema |
| skill `memory` | Persistir padrões novos detectados |
| skill `decision_engine` | Receber recomendações derivadas de padrões |

**NOTA:** esta skill nunca modifica ficheiros — apenas lê e emite relatório. Persistir padrões novos é sempre delegado a `memory`.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **iFood** mantém dashboards de "Post-Mortem Trends" — agrupa bugs repetidos por padrão (temporal, por serviço, por região) e alimenta o backlog de qualidade. Relatórios semanais obrigatórios.
>
> **Glovo** realiza "Incident Retrospectives" mensais — cada incidente é classificado por causa-raíz e alimenta uma base queryable: "quantas vezes vimos este mesmo bug?".
>
> **Uber** usa "Chronology Analysis" — correlaciona bugs com deploys, cron runs, e releases de apps para detectar padrões temporais invisíveis a olho nu.
>
> **Bora App equivalente:** `learning_engine` lê `memory_store.md` + `git log` + codebase e produz relatório sob demanda. Sem dashboard permanente, mas cobre as três angulações (temporal, causa-raíz, entidade) com fracção do custo. Resultados alimentam `memory` e `decision_engine`.

---

## RESPONSABILIDADES

- ✅ Analisar `.claude/.ai/memory/memory_store.md` para detectar padrões recorrentes
- ✅ Identificar zonas de alto risco com base em histórico
- ✅ Sugerir melhorias de processo (não de código)
- ✅ Alimentar `memory` com novos padrões detectados (via delegação — nunca escreve directamente)

## NÃO PODE FAZER

- ❌ Sugerir código específico (delegar a skill especialista)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Modificar `business_rules.md`
- ❌ Modificar `memory_store.md` directamente (delegar a `memory`)
- ❌ Criar conclusões sem evidência em `memory` ou codebase

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Análise de padrões históricos e processo | **learning_engine** (eu) |
| Decisão de risco/impacto antes de execução | `decision_engine` |
| Persistir nova decisão ou bug | `memory` |
| Sugestão de feature/UX | `product_analyst` |
| Consultar decisão travada | `decision_registry` |

## RULES

- Apenas analisa — nunca sugere código
- Todas as conclusões baseadas em evidência real (`memory` + codebase + git)
- Ser específico: nomear arquivos, padrões, timestamps
- Delegar persistência de novos padrões à skill `memory`
- Source of truth: `.claude/.ai/business_rules.md` v2
