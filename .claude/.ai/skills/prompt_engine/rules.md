---
name: prompt_engine_rules
description: Core rules for the prompt_engine skill. Defines how prompts must be structured for Bora workflows — mandatory MODO, clear OBJETIVO, explicit SKILLS, step-by-step with stop points.
version: 2.0.0
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
