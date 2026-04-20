---
name: rules
description: This skill defines the top-level philosophy and operating principles for the entire Bora skill system. Read this first when starting any task. Overrides no other skill — just establishes shared behavioral ground rules.
version: 2.0.0
---

# RULES — SYSTEM OPERATING PRINCIPLES

## ROLE
Defines the baseline behavioral philosophy for all skills. Camada 0 — META. Not a gate, not an executor. Just the shared rulebook every skill inherits.

---

## OBJECTIVE

Ensure every skill in the system operates consistently: minimal changes, root-cause first, validation always, business rules respected.

---

## PRINCÍPIOS CENTRAIS

- Ser direto e técnico — sem explicações desnecessárias
- Nunca quebrar funcionalidades existentes
- Sempre aplicar a MENOR mudança possível
- Sempre respeitar Model → Store → Screen
- Nunca executar sem entender a causa raiz
- Sempre validar após qualquer mudança

---

## MODO DE EXECUÇÃO

### PERMITIDO EXECUTAR DIRETO
- Correções de bug claras e localizadas
- Problemas de lógica em 1 arquivo
- Issues de realtime / auth pontuais

### OBRIGATÓRIO PEDIR APROVAÇÃO
- Refatoração de 3+ arquivos
- Mudança de arquitetura
- Novas funcionalidades
- Mudanças que impactam regras de negócio

---

## REGRAS DE DEBUG (OBRIGATÓRIAS)

1. Analisar problema
2. Encontrar causa raiz
3. Só então corrigir

Proibido:
- Corrigir por tentativa
- Fazer mudanças sem entender causa

---

## DISPATCH (CRÍTICO — alinhado com business_rules.md)

- Nunca usar broadcast — apenas 1 driver recebe por vez
- Usar `current_driver_offer_id` como fonte de verdade
- Dispatch deve ser sequencial
- Timeout gera redispatch imediato

---

## REALTIME (CRÍTICO)

- Supabase é a única fonte de verdade
- Nunca iniciar stream com ID null
- Apenas 1 subscription ativa por propósito
- Sempre cancelar stream anterior antes de criar novo

---

## AUTH (CRÍTICO)

- Nunca usar sessão guest para drivers
- `driverId` = `auth.currentUser.id`
- Nunca usar IDs mockados

---

## RESPONSABILIDADES

- ✅ Definir filosofia e princípios compartilhados
- ✅ Ser consultado no início de qualquer tarefa
- ✅ Alinhar comportamento de todas as skills

## NÃO PODE FAZER

- ❌ Executar mudanças (delegar a `executor`)
- ❌ Validar código (delegar a `guardian`)
- ❌ Tomar decisões (delegar a `decision_engine`)
- ❌ Substituir `business_rules.md` (BR é a fonte de verdade de negócio)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Filosofia e princípios gerais | **rules** (eu) |
| Regras de negócio específicas | `business_rules.md` |
| Decisão de risco/impacto | `decision_engine` |
| Validação técnica pré-execução | `guardian` |
| Execução da ação aprovada | `executor` |

## RULES

- Esta skill não bloqueia nem aprova — apenas define o piso de comportamento
- Todas as outras skills herdam estes princípios implicitamente
- Em conflito entre rules.md e business_rules.md → `business_rules.md` vence (é mais específico)
- Máximo 5 tentativas por problema → se não resolver, parar e reportar
