---
name: memory
description: This skill should be used when the user says "SKILL: memory", asks to save an important decision, record a confirmed pattern, update the operational rules, or preserve knowledge that must persist across sessions.
version: 1.1.0
protection_mode: read-write-append-only
---

> **MODO PROTECÇÃO:** read-write-append-only. Esta skill só ESCREVE em `.claude/.ai/memory/memory_store.md` e sempre em modo append. Nunca apaga nem sobrescreve. Nunca toca em código, BR ou outras skills. Registos devem referenciar `business_rules.md` v2 (BR §X) quando a informação estiver travada.

# MEMORY — PERSISTENT KNOWLEDGE STORE

## ROLE
Manages the project's long-term memory.

Reads and writes (append-only) to `.claude/.ai/memory/memory_store.md`.

---

## WHAT TO STORE

✅ Store:
- Confirmed architectural decisions (com ref BR §X quando aplicável)
- Resolved bugs (root cause + solution)
- Pricing rates and business rules (sempre com ref BR §X)
- Operational patterns and flows
- Technical decisions with reasoning
- Patterns detected by learning_engine

❌ Never store:
- Temporary debug output
- Failed attempts
- Speculative ideas (use product_analyst for that)
- Data that changes frequently (use Supabase)
- Duplicates of what already exists in BR v2 (prefer a BR ref, not a copy)

---

## WRITE PROTOCOL

Before writing, verify:
1. The information is confirmed (not tentative)
2. It belongs to one of the stable categories above
3. It will be useful in a future session
4. It does not duplicate uma entrada existente — `grep` no memory_store antes

---

## WRITE FORMAT

### For bugs:
```
---
BUG: <description>
CAUSA: <root cause>
SOLUÇÃO: <what was done>
FICHEIROS: <lib/... paths afectados>
RESULTADO: resolved
DATA: <YYYY-MM-DD>
---
```

### For decisions:
```
DECISÃO: <what was decided>
RAZÃO: <why>
BR REF: §X (quando aplicável)
DATA: <YYYY-MM-DD>
```

### For patterns:
```
PADRÃO: <pattern name>
ONDE: <files/areas>
PREVENÇÃO: <how to avoid>
DETECTADO POR: learning_engine | manual
```

### For operational rules:
```
REGRA: <rule>
ÂMBITO: <when it applies>
BR REF: §X (se existe)
```

---

## READ PROTOCOL

When a session starts or a task is complex:
1. Read memory.md to recover context
2. Apply relevant decisions and patterns
3. Do not re-ask questions already answered in memory
4. Cross-check memory vs BR v2 — se divergir, BR vence e memory é corrigido (novo append a apontar o erro)

---

## EXEMPLOS WORKED

### Exemplo 1: Registar decisão "SLA crítico = 7 min (BR v2)"

**Input (contexto real):**
Danilo pergunta ao Claude: "Qual é o SLA crítico mesmo?". Claude responde "7 min" e Danilo confirma: "sim, guarda isso com referência à BR v2 para não ter de explicar outra vez".

**Processo:**
1. Verificar BR §9.1 → "SLA de alerta (crítico): 7 minutos — pedido sobe na fila de prioridade". Confirmado.
2. `grep SLA crítico` em `memory_store.md` → não existe entrada actual.
3. Escrever em modo append no final de `memory_store.md` (nunca editar linhas existentes).

**Output esperado (append em memory_store.md):**
```
DECISÃO: SLA crítico = 7 minutos (faz o pedido subir na fila de prioridade)
RAZÃO: política de qualidade de serviço — evita pedidos paralisados
BR REF: §9.1 · constante SLA_CHECK_MINUTES = 7 (BR §25.2)
DATA: 2026-04-17
```

**Failure mode:**
A skill falha se guardar o valor 7 sem referenciar BR §9.1 — fica solto e futuro agente não sabe onde confirmar. Também falha se sobrescrever entrada anterior em vez de append.

---

### Exemplo 2: Registar bug resolvido "map_master não centralizava"

**Input (contexto real):**
Após fix, Danilo diz: "Guarda que o mapa do estafeta não centralizava quando clicava no botão de centrar. A fix foi em location_service."

**Processo:**
1. Confirmar que o fix está de facto no código — ler `lib/services/location_service.dart` e `lib/screens/driver_map_screen.dart`.
2. Confirmar BR §7.2 → "Botão de centralizar → centra câmara no driver". Comportamento esperado documentado.
3. `grep "map_master.*centraliz"` no memory_store → novo.
4. Escrever append com estrutura BUG.

**Output esperado (append em memory_store.md):**
```
---
BUG: Botão de centralizar do driver_map_screen não movia a câmara para o driver
CAUSA: listener do LocationService era debounced mas o debounce reiniciava a cada frame,
       impedindo o emit final que accionava o animate.
SOLUÇÃO: separar debounce de "stream contínua" do "one-shot centralizar",
         adicionar método `centerNow()` que ignora debounce.
FICHEIROS: lib/services/location_service.dart · lib/screens/driver_map_screen.dart
RESULTADO: resolved
DATA: 2026-04-17
BR REF: §7.2 (botão de centralizar deve centrar câmara)
---
```

**Failure mode:**
A skill falha se guardar só "botão não funcionava" sem causa-raíz ou ficheiros — futuro agente não consegue prevenir a regressão.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/memory/memory_store.md` | Destino único de escrita (append-only) |
| `.claude/.ai/business_rules.md` v2 | Sempre cruzar antes de escrever — se BR cobre, referenciar §X em vez de copiar |
| `lib/` (qualquer ficheiro referenciado num BUG) | Confirmar que a correcção existe realmente antes de guardar "resolved" |
| `git log` | Confirmar data real da correcção (pode estar diferente da data do pedido de guardar) |
| skill `learning_engine` | Delega aqui a persistência de padrões que detectou |
| skill `decision_engine` | Pode delegar aqui para persistir decisão após aprovação |
| skill `decision_registry` | Memory NÃO substitui — registry é índice travado, memory é histórico cronológico |

**NOTA:** esta skill escreve apenas em `memory_store.md`. Nunca toca em BR, nunca em código, nunca em outras skills.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** mantém "Decision Log" permanente em docs internos — cada decisão técnica crítica fica registada com data, contexto, razão e owner. É consultada antes de qualquer refactor.
>
> **iFood** usa "Knowledge Base" interna indexada por tópico (dispatch, fraude, pagamentos) — bugs resolvidos e workarounds ficam documentados para prevenir regressões.
>
> **Glovo** tem "Incident Journal" append-only, complementar ao sistema de tickets — cada incidente deixa um registo perene mesmo depois de o ticket fechar.
>
> **Bora App equivalente:** `memory` escreve em `memory_store.md` (append-only). Complementa `decision_registry` (índice travado) e `business_rules.md` (source of truth). Cobre o papel dos três gigantes com um ficheiro markdown simples.

---

## RESPONSABILIDADES

- ✅ Escrever em `.claude/.ai/memory/memory_store.md` (append-only)
- ✅ Armazenar decisões confirmadas, bugs resolvidos, padrões detectados
- ✅ Servir como fonte de contexto persistente entre sessões
- ✅ Ser lido no início de sessões complexas
- ✅ Referenciar BR §X quando a informação existe em `business_rules.md`

## NÃO PODE FAZER

- ❌ Deletar ou sobrescrever entradas existentes (append-only)
- ❌ Armazenar tentativas falhadas, output de debug ou dados temporários
- ❌ Armazenar dados que mudam frequentemente (usar Supabase)
- ❌ Duplicar conteúdo que já existe em BR v2 — preferir uma referência §X
- ❌ Interpretar ou tomar decisões baseadas no conteúdo (delegar a `learning_engine`)
- ❌ Escrever em qualquer outro ficheiro

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Persistir decisão confirmada / bug resolvido / padrão | **memory** (eu) |
| Análise de padrões históricos | `learning_engine` |
| Consultar decisões travadas na BR | `decision_registry` |
| Decisões de design de feature | `product_analyst` |
| Avaliar risco antes de persistir | `decision_engine` |

## RULES

- Nunca deletar conteúdo existente — apenas append
- Nunca sobrescrever decisão anterior sem instrução explícita
- Entradas concisas — uma decisão por bloco
- Memory é referência, não log — evitar duplicatas
- Sempre datar com `YYYY-MM-DD` absoluta (nunca "ontem"/"hoje")
- Source of truth de regras de negócio: `.claude/.ai/business_rules.md` v2
