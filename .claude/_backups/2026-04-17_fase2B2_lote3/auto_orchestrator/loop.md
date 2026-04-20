---
name: auto_orchestrator_loop
description: Defines the bounded loop semantics for auto_orchestrator. Max 5 cycles, abort on repeated identical action.
version: 2.0.0
---

# AUTO ORCHESTRATOR — LOOP

## ROLE
Bounded execution loop. Coordinates real Bora skills until objective is reached or limit is hit.

---

## LOOP

```
1. ANALISAR     → decision_engine (+ decision_registry se BR aplicável)
2. CONTROLAR    → guardian (+ flow_guard / refactor_guard se aplicável)
3. EXECUTAR     → executor
4. VALIDAR      → system_validator
5. REGISTRAR    → memory

SE OK             → FINALIZAR
SE NÃO RESOLVIDO  → VOLTAR PARA PASSO 1 (com novo contexto)
```

---

## REGRAS

- **Máximo: 5 ciclos.** Acima disso → reportar erro e parar.
- **Anti-loop:** nunca repetir a MESMA ação sem mudança no input.
- **Gate bloqueia:** parar imediatamente, reportar, aguardar GO humano.
- **Validação falha 2x:** parar, escalar para `learning_engine`.
- **Memória obrigatória:** registrar cada ciclo (input, skills chamadas, resultado).

---

## SAÍDA DO LOOP

Condições para FINALIZAR:
- ✅ `system_validator` retorna OK
- ✅ Objetivo do task atingido
- ✅ Gate bloqueante ativado (escala para humano)

Condições para ABORTAR:
- 🛑 5 ciclos sem solução
- 🛑 Mesma ação repetida sem mudança
- 🛑 Erro irreversível detectado por `guardian`

---

## REPORTE FINAL

Ao sair do loop, sempre produzir:

```
CICLOS EXECUTADOS: <n>
SKILLS USADAS:    <lista>
RESULTADO:        <ok | parcial | falha | bloqueado>
PRÓXIMA AÇÃO:     <o que humano precisa fazer, se algo>
```

---

## RESPONSABILIDADES

- ✅ Executar ciclos bounded (max 5) até objetivo atingido
- ✅ Prevenir loops (não repetir mesma ação sem mudança)
- ✅ Escalar para humano quando gate bloqueia ou 5 ciclos sem solução

## NÃO PODE FAZER

- ❌ Loop infinito (regra absoluta: max 5)
- ❌ Pular `system_validator`
- ❌ Pular registro em `memory`
- ❌ Chamar skill inexistente
- ❌ Repetir mesma ação sem mudança no input

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Controle de ciclos e anti-loop | **auto_orchestrator/loop.md** (eu) |
| Classificar problema e selecionar chain | `auto_orchestrator/flow.md` |
| Mapeamento problema → skills | `auto_orchestrator/decision.md` |
