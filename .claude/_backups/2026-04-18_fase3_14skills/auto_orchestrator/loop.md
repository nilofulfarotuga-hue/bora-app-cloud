---
name: auto_orchestrator_loop
description: Defines the bounded loop semantics for auto_orchestrator. Max 5 cycles, abort on repeated identical action.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill define limites de ciclo — nunca executa directamente, nunca modifica ficheiros. Delega escrita de log à skill `memory`.

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
5. REGISTAR     → memory

SE OK             → FINALIZAR
SE NÃO RESOLVIDO  → VOLTAR PARA PASSO 1 (com novo contexto)
```

---

## REGRAS

- **Máximo: 5 ciclos.** Acima disso → reportar erro e parar.
- **Anti-loop:** nunca repetir a MESMA acção sem mudança no input.
- **Gate bloqueia:** parar imediatamente, reportar, aguardar GO humano.
- **Validação falha 2x:** parar, escalar a `learning_engine` para detectar padrão.
- **Memória obrigatória:** registar cada ciclo (input, skills chamadas, resultado) via skill `memory`.
- **Zona protegida travada (BR §25.3):** **STOP imediato**, sem retry — exige aprovação explícita do Danilo.

---

## SAÍDA DO LOOP

Condições para FINALIZAR:
- ✅ `system_validator` retorna OK
- ✅ Objectivo do task atingido
- ✅ Gate bloqueante activado (escala para humano)

Condições para ABORTAR:
- 🛑 5 ciclos sem solução
- 🛑 Mesma acção repetida sem mudança
- 🛑 Erro irreversível detectado por `guardian`
- 🛑 Qualquer tentativa de tocar zona protegida BR §25.3 sem aprovação explícita

---

## REPORTE FINAL

Ao sair do loop, sempre produzir:

```
CICLOS EXECUTADOS: <n>
SKILLS USADAS:    <lista>
RESULTADO:        <ok | parcial | falha | bloqueado>
BR REFS:          <lista §X relevantes>
PRÓXIMA ACÇÃO:    <o que humano precisa fazer, se algo>
```

---

## EXEMPLOS WORKED

### Exemplo 1: Chain executada, `guardian` bloqueia no ciclo 1

**Input (contexto real):**
Task: "corrigir driver duplicado que aparece em ambos pedidos". Ciclo 1 corre `decision_engine → dispatch_bugfix → guardian`. Guardian detecta que proposta altera `current_driver_offer_id` de forma não-atómica — viola BR §6.5 (lock optimista).

**Processo:**
1. Guardian emite 🔴 RISK DETECTED.
2. Loop **NÃO** chama `executor`. Input é reescrito com guard atómico sugerido por `guardian`.
3. Ciclo 2 corre `decision_engine → dispatch_bugfix → guardian`. Guardian confirma ✅.
4. `executor` aplica. `system_validator` OK. `memory` regista.
5. Total: 2 ciclos, dentro do limite 5.

**Output esperado:**
```
CICLOS EXECUTADOS: 2
SKILLS USADAS: decision_engine, dispatch_bugfix, guardian, executor, system_validator, memory
RESULTADO: ok
BR REFS: §6.5 (guard anti-duplicação)
PRÓXIMA ACÇÃO: nenhuma (task concluída)
```

**Failure mode:**
Loop falha se insistir com o mesmo input após guardian bloquear — regra anti-loop exige mudança de input antes de repetir. Também falha se pular `system_validator` no ciclo final.

---

### Exemplo 2: Chain tenta tocar `pricing_service.dart` (BR §25.3)

**Input (contexto real):**
Task auto-classificado: "ajustar taxa de entrega para começar a €3". Proposta toca `lib/services/pricing_service.dart` (zona protegida em BR §25.3 e valor em BR §2.1).

**Processo:**
1. Ciclo 1. `decision_engine` abre a análise. Detecta que valor é travado em BR §2.1 e ficheiro é zona protegida BR §25.3.
2. Loop **STOP imediato** — zona protegida, sem retry automático.
3. Escalar a Danilo com resumo: (1) BR precisa ser actualizada primeiro, (2) só depois código. Nenhuma execução ocorre.

**Output esperado:**
```
CICLOS EXECUTADOS: 1 (abortado)
SKILLS USADAS: decision_engine
RESULTADO: bloqueado (zona protegida BR §25.3)
BR REFS: §2.1 (taxa entrega travada €2,50), §25.3 (pricing_service.dart protegido)
PRÓXIMA ACÇÃO (humana):
  1. Danilo confirma mudança do valor em BR §2.1
  2. Só depois reabrir task com aprovação explícita
  3. Chain só corre com destructive:true + approved_by contendo Danilo
```

**Failure mode:**
Loop falha catastroficamente se tentar retry após bloqueio de zona protegida. Também falha se propor "workaround" (ex: "criar wrapper que multiplica por 1.2") — isso é burlar BR, não aplicar decisão.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `auto_orchestrator/rules.md` | Regras gerais do orquestrador (max 5, timeout 10 min) |
| `auto_orchestrator/flow.md` | Playbook passo-a-passo por classe |
| `auto_orchestrator/decision.md` | Tabela problema → chain |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — bloqueio imediato, sem retry |
| `.claude/.ai/memory/memory_store.md` | Destino do log de cada ciclo (via skill `memory`) |
| skill `memory` | Delegação da escrita de log (loop nunca escreve directamente) |
| skill `learning_engine` | Escalação quando validação falha 2x — detecta padrão |

**NOTA:** skill lê e coordena. Escrita de log delega a `memory`. Nunca modifica ficheiros.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Max Retry Policy" em qualquer pipeline — retry máximo 3-5 dependendo da criticidade. Acima → alerta e fila humana.
>
> **Glovo** usa "Circuit Breaker" — se acção falha N vezes consecutivas, circuito abre e entrada é redireccionada para human-in-the-loop.
>
> **iFood** tem "Backoff & Abort" — retry com backoff exponencial, abort após limite, escalation obrigatório.
>
> **Bora App equivalente:** `auto_orchestrator/loop.md` combina max retries (5) + circuit breaker (zona protegida → STOP imediato) + escalation obrigatória (2x falha → `learning_engine`). Sem backoff exponencial (não é necessário num orquestrador síncrono).

---

## RESPONSABILIDADES

- ✅ Executar ciclos bounded (max 5) até objectivo atingido
- ✅ Prevenir loops (não repetir mesma acção sem mudança)
- ✅ Escalar a humano quando gate bloqueia, 5 ciclos sem solução, ou zona protegida (BR §25.3)
- ✅ Delegar escrita de log à skill `memory`
- ✅ Reportar BR §X relevantes no reporte final

## NÃO PODE FAZER

- ❌ Loop infinito (regra absoluta: max 5)
- ❌ Pular `system_validator`
- ❌ Pular registo em `memory`
- ❌ Chamar skill inexistente
- ❌ Repetir mesma acção sem mudança no input
- ❌ Retry automático após bloqueio de zona protegida (BR §25.3)
- ❌ Modificar ficheiros (é read-only; log vai via `memory`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Controlo de ciclos e anti-loop | **auto_orchestrator/loop.md** (eu) |
| Classificar problema e seleccionar chain | `auto_orchestrator/flow.md` |
| Mapeamento problema → skills | `auto_orchestrator/decision.md` |
| Regras gerais | `auto_orchestrator/rules.md` |

## RULES

- Max 5 ciclos — regra absoluta
- Zona protegida BR §25.3 → STOP sem retry
- Todo reporte final cita BR §X quando aplicável
- Source of truth: `.claude/.ai/business_rules.md` v2
