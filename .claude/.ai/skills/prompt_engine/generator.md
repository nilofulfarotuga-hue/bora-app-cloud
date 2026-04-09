---
name: prompt_engine_generator
description: Concrete prompt templates for common Bora workflows. Use these as starting points instead of writing prompts from scratch. Each template is real, tested, and aligned with business_rules.md.
version: 2.0.0
---

# PROMPT GENERATOR — REAL TEMPLATES

## ROLE
Library of concrete, ready-to-use prompts for common Bora development scenarios. Replaces ad-hoc prompt writing with battle-tested templates.

---

## TEMPLATE 1 — BUG INVESTIGATION (CONTROLLED)

```
MODO: INVESTIGAÇÃO + CORREÇÃO CONTROLADA
SKILLS: decision_engine, guardian, fix_realtime, executor, system_validator
OBJETIVO: Investigar e corrigir [DESCREVER BUG ESPECÍFICO]

REGRAS:
- não modificar nada antes de identificar causa raiz
- mudança mínima e cirúrgica
- prova obrigatória (file:line + log)
- compatibilidade total com business_rules.md

PASSOS:
1. Reproduzir o bug com logs
2. Identificar causa raiz com prova
3. Propor fix mínimo
4. Aguardar GO antes de executar
5. Validar pós-fix com system_validator

PARAR após cada passo e reportar.
```

---

## TEMPLATE 2 — IMPLEMENTAR REGRA DE NEGÓCIO

```
MODO: IMPLEMENTAÇÃO DE REGRA TRAVADA
SKILLS: decision_registry, dispatch_manager (ou payment_manager / token_manager), guardian, executor
OBJETIVO: Implementar [REGRA EXATA DA BR, ex: "fila local FIFO 200m/5s"]

REGRAS:
- regra é INVIOLÁVEL — ler business_rules.md antes
- usar constantes da tabela 📐 (nunca literais mágicos)
- não otimizar a regra
- não adicionar comportamento extra

PASSOS:
1. decision_registry confirma que regra está travada
2. [domain skill] propõe implementação
3. guardian valida segurança técnica
4. executor aplica
5. system_validator confirma

PARAR após cada passo.
```

---

## TEMPLATE 3 — AUDITORIA READ-ONLY

```
MODO: AUDITORIA — READ-ONLY
SKILLS: system_validator, learning_engine, performance_watcher
OBJETIVO: Auditar [ÁREA, ex: "fluxo de pagamento E2E"]

REGRAS:
- ZERO modificação
- ZERO execução
- relatório completo no final
- comparar com business_rules.md

ENTREGÁVEL:
- arquivo .md em .claude/.ai/[nome_audit].md
- classificar achados: OK / AJUSTE / CRÍTICO
- listar gaps e overlaps
- sugerir próximas ações (NÃO executar)
```

---

## TEMPLATE 4 — REFATOR CONTROLADO

```
MODO: REFATOR CONTROLADO
SKILLS: decision_engine, refactor_guard, flow_guard, guardian, executor
OBJETIVO: Refatorar [ALVO, ex: "extrair PaymentStore de OrderStore"]

REGRAS:
- comportamento existente NÃO muda
- testes (se houver) continuam passando
- mudança em 1 PR lógico
- nenhuma feature nova junto

PASSOS:
1. refactor_guard confirma viabilidade
2. flow_guard confirma não-quebra arquitetural
3. propor diff
4. aguardar GO
5. executor aplica
6. system_validator valida

PARAR após cada passo.
```

---

## TEMPLATE 5 — CORREÇÃO DE AUTH

```
MODO: FIX AUTH
SKILLS: fix_auth, guardian, executor
OBJETIVO: Corrigir [SINTOMA: ex "PGRST116 ao buscar driver após login"]

REGRAS:
- não tocar em RLS sem flow_guard
- não substituir Supabase Auth
- prova obrigatória (error.code + file:line)

PASSOS:
1. Reproduzir e capturar error.code exato
2. Cruzar com matriz de erros do fix_auth
3. Propor fix mínimo
4. Aguardar GO
5. Validar login → logout → login limpo
```

---

## REGRAS DE USO

- Sempre nomear as skills explicitamente em `SKILLS:`
- Sempre incluir `OBJETIVO:` específico (não vago)
- Sempre incluir `REGRAS:` que limitam o escopo
- Sempre terminar com `PARAR após cada passo` em modo controlado
- Sempre referenciar `business_rules.md` quando aplicável

---

## RESPONSABILIDADES

- ✅ Fornecer templates prontos para os 5 fluxos mais comuns do Bora
- ✅ Garantir que templates usam apenas skills reais e seguem estrutura padrão

## NÃO PODE FAZER

- ❌ Modificar `business_rules.md` (apenas product owner via processo formal)
- ❌ Criar templates com skills inexistentes
- ❌ Templates sem MODO/OBJETIVO/SKILLS/REGRAS
- ❌ Múltiplos objetivos em um só template (1 = 1)
- ❌ Execução cega sem GO entre passos

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Templates concretos prontos para uso | **prompt_engine/generator.md** (eu) |
| Regras de estrutura de prompt | `prompt_engine/rules.md` |
| Simplificar prompt existente | `prompt_engine/optimizer.md` |
