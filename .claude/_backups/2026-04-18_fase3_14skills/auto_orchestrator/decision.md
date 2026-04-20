---
name: auto_orchestrator_decision
description: Mapping table of problem types to the correct sequence of real Bora skills. Use this to pick which skills to invoke for a given task.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill é tabela de lookup — nunca executa, nunca modifica ficheiros. Cada chain aponta as secções BR §X relevantes.

# AUTO ORCHESTRATOR — DECISION TABLE

## ROLE
Maps problem types to the canonical skill chain. Only references skills that exist on disk.

---

## REGRAS

- Basear decisão no tipo de problema
- Evitar skills desnecessárias
- Sempre passar por `decision_engine` primeiro (excepto UX que começa em `product_analyst`)
- Sempre terminar com `system_validator` + `memory`
- Cada chain cita BR §X para as áreas travadas

---

## MAPEAMENTO

### BUG (geral, não-realtime)
```
decision_engine → guardian → executor → system_validator → memory
```

### BUG REALTIME / SYNC
```
decision_engine → fix_realtime → guardian → executor → system_validator → memory
```
BR REF: §22 (notificações / realtime)

### BUG DISPATCH (incidente pontual)
```
decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory
```
BR REF: §6 (dispatch), §6.5 (guard anti-duplicação)

### BUG AUTH
```
decision_engine → fix_auth → guardian → executor → system_validator → memory
```

### IMPLEMENTAR REGRA DE DISPATCH (fila, capacidade, SLA, batching)
```
decision_engine → decision_registry → dispatch_manager → guardian → executor → system_validator → memory
```
BR REF: §6 completa, §9.1 (SLA), §25.2 (constantes)
**NOTA:** toca zona protegida (BR §25.3 → `driver_capacity_service.dart`, `dispatch-engine`) — exige aprovação explícita

### IMPLEMENTAR REGRA DE PAGAMENTO (cobrança, refund, fees, markup)
```
decision_engine → decision_registry → payment_manager → flow_guard → guardian → executor → system_validator → memory
```
BR REF: §2 (pricing), §3 (pagamentos), §8.3 (cancel), §25.3 (pricing_service.dart zona protegida)

### IMPLEMENTAR REGRA DE TOKENS (FIFO, expiração, cashback)
```
decision_engine → decision_registry → token_manager → guardian → executor → system_validator → memory
```
BR REF: §4 completa, §25.3 (triggers bora_tokens e trg_award_tokens_on_delivery — zona protegida)

### REALTIME (mudança em sync, channels, streams)
```
decision_engine → realtime_engine → flow_guard → guardian → executor → system_validator → memory
```
BR REF: §22 (notificações)

### BACKEND (queries, migrations, RPCs)
```
decision_engine → supabase_agent → supabase_engine → flow_guard → guardian → executor → system_validator → memory
```
BR REF: §21 (RLS)
**NOTA:** `flow_guard` obrigatório em migrations (podem alterar RLS)

### REFATOR (3+ ficheiros, rename, restructure)
```
decision_engine → refactor_guard → flow_guard → guardian → executor → system_validator → memory
```
BR REF: §25.3 (zonas protegidas) — consultar antes de planear

### MUDANÇA ARQUITETURAL (Provider, layers, fluxo central)
```
decision_engine → flow_guard → refactor_guard → guardian → executor → system_validator → memory
```

### PERFORMANCE (rebuilds, GPS waste, leaks)
```
decision_engine → performance_watcher → guardian → executor → system_validator → memory
```

### MUDANÇA DE STATUS / ESTADO DO PEDIDO
```
decision_engine → state_validator → guardian → executor → system_validator → memory
```
BR REF: §1.3 (delivery), §1.4 (reserva), §7.3 (código 4 dígitos), §7.4 (isPurchaseFinalized)

### GPS / MAPAS / TRACKING
```
decision_engine → map_master → guardian → executor → system_validator → memory
```
BR REF: §7.2 (mapa do estafeta)

### UX / FEATURE
```
product_analyst → decision_engine → guardian → executor → system_validator → memory
```
BR REF: §8 (fluxo cliente), §16 (painel admin), §26 (checklist lançamento)

---

## EXEMPLOS WORKED

### Exemplo 1: "Driver não recebe oferta"

**Input (contexto real):**
Classificação: bug operacional em dispatch. Driver reporta sintoma, não código quebrado.

**Processo:**
1. Não é refactor, não é arquitetura, não é UX. É **BUG DISPATCH**.
2. Chain: `decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory`.
3. Consultar BR §6 → verificar se comportamento cumpre regra (sequencial, 40s timeout, 200m FIFO).
4. Estimar: 1 ciclo se for bug isolado. Escalar a Danilo se precisar de mudança em constante travada (BR §25.2).

**Output esperado:**
```
DECISION: bug-dispatch
CHAIN: decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory
BR REFS: §6 (dispatch), §6.3 (40s), §6.5 (guard), §25.2 (constantes)
EST. CYCLES: 1-2
ESCALATE IF: fix requer mudança em OFFER_TIMEOUT_SECONDS, FIFO_RADIUS_KM, ou MAX_ORDERS_PER_DRIVER (BR §25.2 travadas)
```

**Failure mode:**
Skill falha se classificar como `ux/feature` (envia a `product_analyst` que é errado para bug). Também falha se pular `dispatch_bugfix` — perde diagnóstico específico.

---

### Exemplo 2: "Quero adicionar marketplace (AliExpress)"

**Input (contexto real):**
Danilo: "Quero abrir marketplace para vender coisas tipo AliExpress, com entrega CTT."

**Processo:**
1. Classificar: **NÃO É UMA FEATURE SIMPLES**. BR §17 já documenta, mas marca como "futuro, não desenvolvido".
2. Escopo: novo tipo de serviço, nova integração de fornecedor, nova logística (CTT), novo fluxo de devoluções (§17.6). Toca §1.2 (novo service type), §17 completa, potencialmente §3 (pagamentos internacionais).
3. **NÃO é 1 task — é um plano multi-lote**. Chain única não resolve.
4. Resposta: devolver ao orquestrador com recomendação de abrir plano dedicado.

**Output esperado:**
```
DECISION: feature-major (NÃO cabe em chain única)
CLASS: múltiplas (ux/feature + backend + regra-pagamento + novo service type)
BR REFS: §17 completa (marketplace), §1.2 (service types)

RECOMENDAÇÃO: NÃO abrir chain agora.
  1. Abrir plano dedicado "Marketplace MVP" em .claude/_planos/
  2. product_analyst produz spec (fluxo cliente, categorias, markup escalonado §17.5)
  3. decision_engine avalia scope e faseia em 3-5 lotes
  4. Cada lote entra como task separada depois

EST. CYCLES: não aplicável — exige planeamento prévio, não execução imediata.
```

**Failure mode:**
Skill falha se tentar squeeze numa chain (ex: `product_analyst → decision_engine → executor`) — marketplace é feature enorme, não cabe em 5 ciclos. Também falha se prometer estimativa irrealista.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/skills/` (directório) | Única lista de skills válidas — nunca referenciar skill fora deste directório |
| `.claude/.ai/memory/memory_store.md` | Consultar chains usadas com sucesso em casos anteriores |
| `.claude/.ai/business_rules.md` | Source of truth para anotar BR §X em cada chain |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — marcar chains que tocam estas áreas |
| skill `auto_orchestrator/flow.md` | Playbook passo-a-passo |
| skill `auto_orchestrator/loop.md` | Limites de ciclo |
| skill `auto_orchestrator/rules.md` | Regras gerais |
| skill `learning_engine` | Consultar para padrões históricos |

**NOTA:** skill apenas lê e devolve chain recomendada. Nunca executa, nunca modifica.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** usa "Triage Algorithm" — para cada sinal (alerta, ticket, pedido interno), classifica severidade + domínio e roteia para o runbook correcto.
>
> **iFood** tem "Request Classification Service" — serviço dedicado que classifica toda entrada operacional antes de encaminhar.
>
> **Glovo** tem "Smart Router" — combina classificação automática com histórico de resolução para sugerir chain de intervenção.
>
> **Bora App equivalente:** `auto_orchestrator/decision.md` é tabela de triagem estática, indexada por tipo de problema. Sem ML; simples, auditável, versionável. Cobre o papel dos três com papel de tabela consultável.

---

## RESPONSABILIDADES

- ✅ Mapear tipo de problema → chain de skills correcta
- ✅ Garantir que chains usem apenas skills reais
- ✅ Ser tabela de lookup central para `auto_orchestrator/flow.md`
- ✅ Ancorar cada chain em BR §X quando aplicável
- ✅ Sinalizar quando o request não cabe numa chain (caso plano dedicado)

## NÃO PODE FAZER

- ❌ Incluir skills inexistentes em chains
- ❌ Montar chains sem `guardian` antes de `executor`
- ❌ Montar chains sem `system_validator` + `memory` no final
- ❌ Tomar decisões de risco (delegar a `decision_engine`)
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Tabela de mapeamento problema → chain | **auto_orchestrator/decision.md** (eu) |
| Fluxo de execução passo-a-passo | `auto_orchestrator/flow.md` |
| Limites de ciclo | `auto_orchestrator/loop.md` |
| Regras gerais | `auto_orchestrator/rules.md` |
| Decisão de risco/impacto | `decision_engine` |

## RULES

- ❌ NÃO incluir `auto_debug`, `ux_optimizer`, `system_designer`, `tester` (não existem)
- ❌ NÃO usar `dispatch_engine_fix` (renomeado para `dispatch_bugfix`)
- ✅ Toda chain começa com `decision_engine` (excepto UX que começa com `product_analyst`)
- ✅ Toda chain termina com `system_validator` + `memory`
- ✅ Toda chain inclui `guardian` antes de `executor`
- ✅ Chains que tocam BR §25.3 devem marcar "exige aprovação explícita"
- Source of truth: `.claude/.ai/business_rules.md` v2
