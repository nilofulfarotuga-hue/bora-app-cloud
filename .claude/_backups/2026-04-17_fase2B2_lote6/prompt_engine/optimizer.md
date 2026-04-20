---
name: prompt_engine_optimizer
description: Optimizer for prompt_engine. Reviews an existing prompt and removes redundancy, simplifies phrases, reduces token use, and improves clarity — without changing meaning or scope.
version: 2.0.0
---

# PROMPT ENGINE — OPTIMIZER

## ROLE
Cleans and simplifies existing prompts. Read-only analysis of input prompt → produce leaner version preserving full meaning.

---

## OBJECTIVE

Reduzir tokens, remover redundância e tornar instruções mais diretas — sem alterar significado, escopo ou skills referenciadas.

---

## PASSOS

1. Ler o prompt original na íntegra
2. Identificar: redundâncias, frases longas, seções duplicadas, skills inexistentes
3. Simplificar frase por frase
4. Verificar que MODO/OBJETIVO/SKILLS/REGRAS ainda estão presentes
5. Retornar versão otimizada

---

## FUNÇÕES DE OTIMIZAÇÃO

- Remover redundância (frases que repetem a mesma ideia)
- Simplificar frases longas (cortar palavras desnecessárias)
- Reduzir tokens (preferir bullet a parágrafo)
- Tornar instruções diretas (ativo > passivo)
- Manter estrutura padrão (MODO/OBJETIVO/SKILLS/REGRAS/PASSOS)

---

## RESPONSABILIDADES

- ✅ Otimizar prompt existente para clareza e economia de tokens
- ✅ Garantir que estrutura padrão seja preservada

## NÃO PODE FAZER

- ❌ Mudar significado ou escopo do prompt
- ❌ Adicionar skills não presentes no original
- ❌ Remover seções obrigatórias (MODO/OBJETIVO/SKILLS/REGRAS)
- ❌ Substituir skills por skills inexistentes

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Simplificar prompt existente | **prompt_engine/optimizer.md** (eu) |
| Templates prontos para novos prompts | `prompt_engine/generator.md` |
| Regras de estrutura obrigatória | `prompt_engine/rules.md` |

## RULES

- Nunca mudar significado — apenas clareza
- Nunca adicionar escopo ao otimizar
- Após otimizar → verificar contra `prompt_engine/rules.md`
- Source of truth: `.claude/.ai/business_rules.md`
