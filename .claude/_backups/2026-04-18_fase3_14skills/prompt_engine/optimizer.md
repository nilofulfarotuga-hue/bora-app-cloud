---
name: prompt_engine_optimizer
description: Optimizer for prompt_engine. Reviews an existing prompt and removes redundancy, simplifies phrases, reduces token use, and improves clarity — without changing meaning or scope.
version: 2.1.0
protection_mode: read-only
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
5. Verificar que zonas protegidas (BR §25.3) continuam citadas se aplicável
6. Retornar versão otimizada

---

## FUNÇÕES DE OTIMIZAÇÃO

- Remover redundância (frases que repetem a mesma ideia)
- Simplificar frases longas (cortar palavras desnecessárias)
- Reduzir tokens (preferir bullet a parágrafo)
- Tornar instruções diretas (ativo > passivo)
- Manter estrutura padrão (MODO/OBJETIVO/SKILLS/REGRAS/PASSOS)
- Preservar referências a BR §X (não substituir por valores hardcoded)

---

## RESPONSABILIDADES

- ✅ Otimizar prompt existente para clareza e economia de tokens
- ✅ Garantir que estrutura padrão seja preservada

## NÃO PODE FAZER

- ❌ Mudar significado ou escopo do prompt
- ❌ Adicionar skills não presentes no original
- ❌ Remover seções obrigatórias (MODO/OBJETIVO/SKILLS/REGRAS)
- ❌ Substituir skills por skills inexistentes
- ❌ Remover referências a zonas protegidas (BR §25.3)

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

---

## EXEMPLOS WORKED

#### Exemplo 1: Prompt longo a desperdiçar tokens
**Input (contexto):** Prompt com 800 tokens, 3 parágrafos a explicar o mesmo MODO de execução, lista REGRAS duplicada em 2 sítios.
**Processo:**
1. Identifica os 2 blocos REGRAS — consolida em 1.
2. Substitui parágrafos de explicação por bullets.
3. Confirma que MODO/OBJETIVO/SKILLS/REGRAS/BR §25.3 continuam presentes.
**Output esperado:** Prompt reduzido a ~350 tokens preservando 100% do significado.
**Failure mode:** Remover BR §25.3 por parecer "redundante" → Claude pode tocar em zona protegida.

#### Exemplo 2: Prompt que fez Claude tocar em código proibido
**Input (contexto):** Prompt anterior fez Claude refactor de `dispatch_service.dart` (zona protegida BR §25.3) sem chain.
**Processo:**
1. Lê o prompt original — guard estava genérico ("não tocar em código crítico").
2. Diagnóstico: faltava restrição EXPLÍCITA por ficheiro/zona.
3. Adiciona linha exacta: "PROIBIDO modificar `lib/dispatch/dispatch_service.dart`, `lib/services/pricing_service.dart`, `supabase/migrations/*` — BR §25.3".
4. Não muda o resto do prompt.
**Output esperado:** Prompt com guard reforçado em zonas específicas.
**Failure mode:** Reescrever todo o prompt em vez de apenas reforçar guard → muda escopo (proibido pela skill).

---

## REFERÊNCIAS BORA APP

- Lê: `.claude/.ai/business_rules.md` — para confirmar referências BR §X usadas no prompt.
- Lê: [.claude/.ai/skills/](.claude/.ai/skills/) — verifica que skills mencionadas existem.
- Referências BR: §25.3 (zonas protegidas — nunca remover de prompts), §25.2 (constantes — nunca substituir por literais).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** "Prompt Compression" — equipa dedicada a optimizar prompts internos para reduzir custo de tokens.
> **iFood** revê prompts trimestralmente para eliminar drift e redundância.
> **Glovo** usa "Prompt Linting" automático antes de publicar templates novos.
> **Bora equivalente:** `prompt_engine/optimizer` reduz tokens preservando significado e referências BR — combinando compression do Uber com lint do Glovo.
