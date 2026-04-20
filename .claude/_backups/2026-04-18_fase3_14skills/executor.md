---
name: executor
description: This skill should be used when the user says "SKILL: executor", or when an action has been approved by decision_engine + guardian and needs to be physically executed (Edit/Write/Bash). Never decides what to do — only executes pre-approved actions.
version: 1.1.0
protection_mode: execute-after-chain
---

> **MODO PROTECÇÃO:** execute-after-chain. Esta skill é a **única** do Lote 3 que escreve em disco. Só age após receber `approved_by` contendo a cadeia canónica completa (decision_engine + guardian + flow_guard/refactor_guard se aplicável). Em ausência de aprovação → recusa. Zona protegida BR §25.3 exige `destructive: true` + aprovação explícita do Danilo.

# EXECUTOR — APPROVED ACTION RUNNER

## ROLE
Executes actions that have already been validated by the decision/control layers. Pure execution, zero decision-making.

Runs AFTER: `decision_engine` → `flow_guard`/`refactor_guard` (se aplicável) → `guardian` → **executor** → `system_validator`.

---

## OBJECTIVE

Carry out approved file edits, file creations, and shell commands with full traceability, then hand control back to validation skills.

---

## INPUT CONTRACT

Executor only acts when receiving:

```
{
  action: "edit" | "write" | "bash",
  target: <file path or command>,
  payload: <diff | content | command string>,
  approved_by: ["decision_engine", "guardian", ...],
  reason: <one-line why>,
  destructive: <true | false>
}
```

Se `approved_by` estiver vazio ou não contiver `guardian` → **REFUSE** e reporta ao orquestrador.

Se `target` tocar zona protegida (BR §25.3) sem `destructive: true` + aprovação explícita → **REFUSE**.

---

## EXECUTION RULES

1. **Never improvise.** Se o payload é ambíguo, aborta e pede clarificação ao orquestrador.
2. **Atomic.** Uma acção por chamada. Sem batching de mudanças não relacionadas.
3. **Logged.** Toda execução escreve em `memory` (action, target, result, timestamp, aprovadores).
4. **Reversible-aware.** Acções destrutivas (delete, overwrite, force push) exigem `destructive: true` + aprovação.
5. **Post-execution handoff.** Após completar, devolve controlo ao `system_validator`.
6. **Zonas protegidas (BR §25.3) travadas por defeito:**
   - `lib/services/pricing_service.dart`
   - `lib/dispatch/driver_capacity_service.dart`
   - `lib/stores/order_store.dart` método `finalizePurchase`
   - Triggers `bora_tokens` · `trg_award_tokens_on_delivery`
   - Qualquer código Stripe
   - `supabase/functions/dispatch-engine/index.ts`

---

## EXEMPLOS WORKED

### Exemplo 1: Correcção de bug em `order_store.dart` (fora do método protegido)

**Input (contexto real):**
Pipeline completa aprovou patch para `lib/stores/order_store.dart` que adiciona `mounted` check antes de `notifyListeners()` num callback async. Payload é um diff de 3 linhas. `approved_by: ["decision_engine", "guardian"]` (não precisa de flow_guard — é bug fix isolado; não precisa de refactor_guard — 1 ficheiro).

**Processo:**
1. Validar contrato: `action: "edit"`, `approved_by` contém `guardian` → OK.
2. Validar zona protegida: ficheiro está em BR §25.3 **mas** o método tocado não é `finalizePurchase`. Tolerância aceita (zona é sobre `finalizePurchase` específico, não o ficheiro inteiro). Confirmar com `guardian` via `approved_by` → já confirmado.
3. Aplicar Edit cirúrgico (exact old_string → new_string).
4. Log em `memory` com timestamp e aprovadores.
5. Handoff a `system_validator` para confirmar `dart analyze` zero erros e regression smoke test.

**Output esperado:**
```
✅ executor: edit on lib/stores/order_store.dart
   approved_by: [decision_engine, guardian]
   result: success (3 linhas alteradas)
   reason: "guard mounted antes de notifyListeners em async callback"
   handoff: system_validator
```

**Failure mode:**
Executor falha se o diff tentar alterar `finalizePurchase` sem `destructive: true`, ou se `approved_by` não contiver `guardian`. Também falha se `old_string` não for exact match — abort, não "best effort".

---

### Exemplo 2: Nova coluna em `orders` via migration

**Input (contexto real):**
Pipeline aprovou `action: "write"`, `target: "supabase/migrations/20260417120000_add_orders_delivery_code_index.sql"`, `payload: <SQL CREATE INDEX IF NOT EXISTS ...>`, `approved_by: ["decision_engine", "flow_guard", "refactor_guard", "guardian"]`. Migration é aditiva (apenas índice) — não altera schema nem adiciona coluna NOT NULL.

**Processo:**
1. Validar contrato: `write` para path que não existe ainda → OK.
2. Confirmar que cadeia inclui `flow_guard` (BR §21 — migrations tocam RLS).
3. Confirmar que é aditivo: `CREATE INDEX IF NOT EXISTS`. Nenhum `DROP` nem `ALTER TABLE ... NOT NULL`. `destructive` pode ficar `false`.
4. Escrever ficheiro SQL exactamente como no payload. Atomic.
5. Log em `memory` com path e hash do conteúdo.
6. Handoff a `system_validator`.

**Output esperado:**
```
✅ executor: write on supabase/migrations/20260417120000_add_orders_delivery_code_index.sql
   approved_by: [decision_engine, flow_guard, refactor_guard, guardian]
   result: success (file created, 1847 bytes)
   reason: "índice para lookup de orders.delivery_code em onTheWay → delivered (BR §7.3)"
   handoff: system_validator (rodar migration em staging primeiro)
```

**Failure mode:**
Executor falha e aborta se:
- Payload contém `DROP TABLE` ou `ALTER TABLE ... NOT NULL` sem `destructive: true`
- `approved_by` não contiver `flow_guard` (migration = arquitetura → exige gate arquitetural)
- Ficheiro já existe (não sobrescreve sem `destructive: true`)

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/**/*.dart` | Alvo de Edit/Write pós-aprovação |
| `supabase/migrations/*.sql` | Alvo de Write (novas migrations). Nunca editar existentes sem `destructive: true` |
| `supabase/functions/dispatch-engine/index.ts` | Zona protegida (BR §25.2 + §25.3) — exige aprovação explícita |
| `.claude/.ai/business_rules.md` §25.3 | Lista de zonas protegidas — executor consulta antes de cada acção |
| `.claude/.ai/business_rules.md` §6 · §3 · §1.3 | Contexto das áreas sensíveis (dispatch, pagamentos, FSM) |
| `.claude/.ai/memory/memory_store.md` | Destino do log de cada execução (via skill `memory`) |
| skill `guardian` | Gate imediatamente antes — executor recusa sem aprovação `guardian` |
| skill `system_validator` | Handoff imediatamente depois |
| skill `decision_engine` | Gate inicial — executor recusa sem aprovação `decision_engine` |
| skill `memory` | Delegação do log (executor nunca escreve directamente em `memory_store.md`) |

**NOTA:** executor só age sobre o target recebido. Nunca explora, nunca decide escopo, nunca edita ficheiros adjacentes.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Controlled Deployment Service" — CD pipeline aplica mudanças só depois de todos os checks passarem (static analysis, tests, canary). Uma falha em qualquer etapa → auto-rollback.
>
> **iFood** usa "Safe Rollout" com gates formais — cada deploy exige aprovação de Tech Review + passagem em staging + health-check em produção pós-deploy.
>
> **Glovo** tem "Deploy Controller" — ferramenta que só inicia deploy se todos os guards (lint, test, security scan) reportaram PASS dentro das últimas 2h.
>
> **Bora App equivalente:** `executor` é o último passo da cadeia. Só corre após `decision_engine` + `guardian` (+ `flow_guard`/`refactor_guard` se aplicável) aprovarem. Sem aprovação = recusa. Cobre o papel dos três num único gate, com trace obrigatório em `memory`.

---

## RESPONSABILIDADES

- ✅ Executar `Edit` num ficheiro existente com diff pré-aprovado
- ✅ Executar `Write` de ficheiro novo com conteúdo pré-aprovado
- ✅ Executar `Bash` de comando pré-aprovado (build, test, migration runner)
- ✅ Log de cada acção delegando à skill `memory`
- ✅ Recusar acção sem `approved_by` completo
- ✅ Recusar acção em zona protegida (BR §25.3) sem `destructive: true` explícito

## NÃO PODE FAZER

- ❌ Decidir se uma acção é segura (delegar a `guardian`)
- ❌ Escolher quais ficheiros tocar (delegar a `decision_engine`)
- ❌ Validar o resultado (delegar a `system_validator`)
- ❌ Modificar `business_rules.md`
- ❌ Operações destrutivas sem `destructive: true` explícito
- ❌ Múltiplas acções não relacionadas numa chamada
- ❌ Tocar zona protegida (BR §25.3) sem aprovação explícita do Danilo

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Executar acção aprovada | **executor** (eu) |
| Decidir o que executar | `decision_engine` |
| Validar arquitetura pré-exec | `flow_guard` |
| Validar refactor pré-exec | `refactor_guard` |
| Validar segurança técnica pré-exec | `guardian` |
| Validar resultado pós-exec | `system_validator` |
| Registar decisão / acção | `memory` |

---

## OUTPUT FORMAT

```
✅ executor: <action> on <target>
   approved_by: [<list>]
   result: <success | partial | failed>
   reason: <one-line why>
   handoff: system_validator
```

Ou em falha:

```
🔴 executor: <action> on <target> FAILED
   reason: <error>
   handoff: orchestrator
```

Ou em recusa por falta de aprovação:

```
🛑 executor: REFUSED
   target: <target>
   missing approvals: [<list>]
   handoff: auto_orchestrator
```

---

## RULES

- Última camada antes do disco. Confiar na cadeia acima.
- Nunca a primeira nem única skill chamada.
- Nunca decide E executa — são preocupações separadas.
- Sempre handoff. Nunca silencioso.
- Qualquer valor numérico citado deve vir com ref BR §X.
- Source of truth: `.claude/.ai/business_rules.md` v2
