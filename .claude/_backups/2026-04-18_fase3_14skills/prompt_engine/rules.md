---
name: prompt_engine_rules
description: Core rules for the prompt_engine skill. Defines how prompts must be structured for Bora workflows — mandatory MODO, clear OBJETIVO, explicit SKILLS, step-by-step with stop points.
version: 2.1.0
protection_mode: read-only
---

# PROMPT ENGINE — RULES

## ROLE
Defines structural rules for all Bora prompts. Every prompt generated for this system must follow these conventions.

---

## OBJECTIVE

Garantir que todo prompt do sistema Bora seja estruturado, rastreável, com skills explícitas e objetivos claros — eliminando ambiguidade e execução acidental.

---

## REGRAS DURAS

- ✅ Todo prompt começa com `MODO:` (tipo de operação)
- ✅ Todo prompt define `OBJETIVO:` claro e específico
- ✅ Todo prompt lista `SKILLS:` explicitamente
- ✅ Todo prompt lista `REGRAS:` que limitam escopo
- ✅ Prompts de execução incluem `PARAR após cada passo`
- ✅ 1 prompt = 1 objetivo (nunca multi-objetivo)
- ✅ Prompts críticos referenciam BR §25.3 (zonas protegidas)
- ❌ NUNCA incluir skills que não existem em `.claude/.ai/skills/`
- ❌ NUNCA prompt sem objetivo específico
- ❌ NUNCA execução cega sem stop points entre passos

---

## INVESTIGAÇÃO

- Sempre investigar antes de executar
- Nunca assumir estado — ler arquivos relevantes primeiro
- Nunca alterar sem validar

---

## ESCOPO

- Sempre limitar escopo no prompt
- Evitar mudanças amplas em um único prompt

---

## RESPONSABILIDADES

- ✅ Definir regras de estrutura de prompts
- ✅ Garantir compatibilidade entre prompts e skills reais

## NÃO PODE FAZER

- ❌ Gerar prompts com skills inexistentes
- ❌ Criar prompts sem MODO/OBJETIVO/SKILLS
- ❌ Otimizar regras de negócio (delegar a `business_rules.md`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Regras de estrutura de prompt | **prompt_engine/rules.md** (eu) |
| Templates concretos prontos para uso | `prompt_engine/generator.md` |
| Simplificação de prompt existente | `prompt_engine/optimizer.md` |

## RULES

- MODO + OBJETIVO + SKILLS + REGRAS = estrutura mínima obrigatória
- Skills listadas devem existir em `.claude/.ai/skills/`
- Source of truth: `.claude/.ai/business_rules.md`

---

## EXEMPLOS WORKED

#### Exemplo 1: Gerar prompt para investigar bug de dispatch
**Input (contexto):** Pedido "investigar bug de dispatch — drivers não recebem ofertas".
**Processo:**
1. Inclui contexto: versão do dispatch (v31, BR §25.2), constantes (timeout 40s — BR §25.2).
2. Inclui guards: MODO PROTECÇÃO TOTAL + zonas protegidas (BR §25.3 — não tocar em dispatch_engine sem aprovação).
3. Lista skills: `decision_engine`, `fix_realtime`, `guardian`, `supabase_engine/debug`.
4. Define `PARAR após cada passo`.
**Output esperado:** Prompt completo, copy-paste ready para colar no Claude Code.
**Failure mode:** Esquecer BR §25.3 → Claude Code tenta refactor do dispatch sem chain.

#### Exemplo 2: Gerar prompt para implementar feature da BR
**Input (contexto):** Pedido "implementar gorjetas (BR §4.5)".
**Processo:**
1. Lê BR §4.5 — extrai regra exacta (80% driver, 20% Bora, valores 1/2/3/5€).
2. Gera prompt com: contexto, regras BR §4.5 incluídas inline, lista de zonas a NÃO tocar, formato output esperado.
3. Lista skills: `decision_registry`, `payment_manager`, `guardian`, `executor`.
**Output esperado:** Prompt com toda a especificação embutida — não precisa de leitura externa.
**Failure mode:** Apenas referenciar "implementar BR §4.5" sem extrair regras → Claude pode interpretar errado.

---

## REFERÊNCIAS BORA APP

- Lê: `.claude/.ai/business_rules.md` — todas as secções para incluir contexto.
- Lê: [.claude/.ai/skills/](.claude/.ai/skills/) — lista actualizada de skills disponíveis.
- Referências BR: §25.3 (zonas protegidas — devem estar em TODOS os prompts), §25.2 (constantes).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** tem "Prompt Library" interna para operações de IA repetidas (debug, refactor, audit).
> **iFood** mantém templates de prompts versionados para cada tipo de tarefa de engenharia.
> **Glovo** usa "AI Style Guide" interno para garantir output consistente.
> **Bora equivalente:** `prompt_engine/rules` define a estrutura obrigatória (MODO/OBJETIVO/SKILLS/REGRAS) — equivalente ao AI Style Guide do Glovo combinado com biblioteca versionada do iFood.
