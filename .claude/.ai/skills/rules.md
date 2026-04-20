---
name: rules
description: This skill defines the top-level philosophy and operating principles for the entire Bora skill system. Read this first when starting any task. Overrides no other skill — just establishes shared behavioral ground rules.
version: 2.2.0
protection_mode: read-only
---

# RULES — SYSTEM OPERATING PRINCIPLES

## ROLE
Defines the baseline behavioral philosophy for all skills. Camada 0 — META. Not a gate, not an executor. Just the shared rulebook every skill inherits.

---

## OBJECTIVE

Ensure every skill in the system operates consistently: minimal changes, root-cause first, validation always, business rules respected.

---

## SOURCE OF TRUTH

- **Regras de negócio**: `.claude/.ai/business_rules.md` v2 (BR) — fonte absoluta para qualquer decisão de produto, pricing, dispatch, fluxos.
- **Filosofia de execução**: este ficheiro (`rules.md`) — fonte para comportamento das skills.
- Em conflito → **business_rules.md vence** (é mais específico).

---

## PRINCÍPIOS CENTRAIS

- Ser direto e técnico — sem explicações desnecessárias
- Nunca quebrar funcionalidades existentes
- Sempre aplicar a MENOR mudança possível
- Sempre respeitar Model → Store → Screen
- Nunca executar sem entender a causa raiz
- Sempre validar após qualquer mudança
- Nunca tocar em zonas protegidas (BR §25.3) sem chain completa

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
- Mudanças que impactam regras de negócio (BR)
- Qualquer alteração em zonas protegidas (BR §25.3)
- Tarefas estimadas em >1h
- Qualquer alteração em pagamentos / DB / segurança / RLS

---

## PROTECTION MODE — 3 NÍVEIS

Toda skill tem um `protection_mode` no frontmatter:

| Valor | Significado |
|---|---|
| **read-only** | Apenas analisa e recomenda. Nunca escreve em ficheiros do projecto. (ex: `decision_engine`, `guardian`, `business_rules`, `rules`, todas as skills de regras) |
| **read-write-append-only** | Pode acrescentar (logs, memory, relatórios) mas nunca apagar nem reescrever. (ex: `memory`, `learning_engine`) |
| **execute-after-chain** | Pode escrever/modificar ficheiros de produto/DB, mas APENAS após chain completa aprovada. (ex: `executor`, `supabase_agent/executor`) |

---

## ORDEM CANÓNICA DO SISTEMA

Toda alteração no sistema segue esta cadeia:

```
decision_engine → flow_guard / refactor_guard → guardian → executor → system_validator → memory
```

- `decision_engine`: decide se a mudança deve acontecer
- `flow_guard` / `refactor_guard`: valida arquitetura e fluxo
- `guardian`: valida segurança técnica pré-execução
- `executor`: aplica a mudança (único com `execute-after-chain` no fluxo geral)
- `system_validator`: valida pós-execução
- `memory`: regista contexto da operação para futuras sessões

---

## SKILLS DISPONÍVEIS NO SISTEMA (FASE 3 COMPLETA — 50 SKILLS)

**Camada 0 — META (1):**
- `rules` — este ficheiro

**Camada 1 — DECISÃO (3):**
- `decision_engine`
- `decision_registry`
- `ceo-ai` (skill global)

**Camada 2 — VALIDAÇÃO ARQUITECTURAL (4):**
- `flow_guard`
- `refactor_guard`
- `guardian`
- `state_validator/rules` + `state_validator/validation`

**Camada 3 — EXECUÇÃO (3):**
- `executor`
- `manager`
- `tester`

**Camada 4 — VALIDAÇÃO PÓS + QA (5):**
- `system_validator`
- `learning_engine`
- `performance_watcher`
- `testing-engineer` ⭐ NOVO (Fase 3)
- `qa-engineer` ⭐ NOVO (Fase 3)

**Camada 5 — DOMÍNIO (15):**
- `dispatch_manager` + `dispatch_bugfix`
- `fix_auth`
- `fix_realtime`
- `product_analyst`
- `auto_orchestrator/decision` + `auto_orchestrator/flow` + `auto_orchestrator/loop` + `auto_orchestrator/rules`
- `cancellation-engineer` ⭐ NOVO (Fase 3) — BR §8.3 · §12
- `gdpr-compliance` ⭐ NOVO (Fase 3) — BR §20
- `partner-dashboard-engineer` ⭐ NOVO (Fase 3) — BR §14 · §14.10 · §15
- `admin-panel-engineer` ⭐ NOVO (Fase 3) — BR §16
- `partner-onboarding` ⭐ NOVO (Fase 3) — BR §15
- `notifications-engineer` ⭐ NOVO (Fase 3) — BR §22 · §14.6
- `ui-designer` ⭐ NOVO (Fase 3) — identidade visual

**Camada 6 — BACKEND + EXTRAS (10):**
- `supabase_agent/rules` + `supabase_agent/executor`
- `supabase_engine/rules` + `supabase_engine/debug` + `supabase_engine/queries`
- `prompt_engine/rules` + `prompt_engine/generator` + `prompt_engine/optimizer`
- `products-updater` ⭐ NOVO (Fase 3) — BR §24 · §27
- `market-scraper` ⭐ NOVO (Fase 3) — BR §27.4

**Camada 7 — RELEASE + OPS (3):** ⭐ NOVA CAMADA (Fase 3)
- `deployment-engineer` ⭐ NOVO (Fase 3) — BR §26
- `security-engineer` ⭐ NOVO (Fase 3) — BR §21 · §25.3 · §3.2
- `monitoring-engineer` ⭐ NOVO (Fase 3) — BR §9 · §22

**Memória persistente (1):**
- `memory`

> Lista actualizada após Fase 3 (14 skills novas). Total: 36 → 50 skills.
> Para detalhe de cada skill, abrir o respectivo `.md` em `.claude/.ai/skills/`.
> Todas as skills novas têm `protection_mode: read-only`.

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

- Nunca usar broadcast — apenas 1 driver recebe por vez (BR §6.1)
- Usar `current_driver_offer_id` como fonte de verdade
- Dispatch deve ser sequencial
- Timeout (BR §25.2 — 40s) gera redispatch imediato
- Constantes em BR §25.2 — nunca hardcoded em código

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
- RLS obrigatório em todas as tabelas user-facing (BR §21)

---

## RESPONSABILIDADES

- ✅ Definir filosofia e princípios compartilhados
- ✅ Ser consultado no início de qualquer tarefa
- ✅ Alinhar comportamento de todas as skills
- ✅ Indexar todas as skills disponíveis no sistema

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

---

## EXEMPLOS WORKED

#### Exemplo 1: Nova skill adicionada ao sistema
**Input (contexto):** Nova skill `notification_manager` é criada em `.claude/.ai/skills/`.
**Processo:**
1. `rules.md` é a primeira referência consultada por qualquer fluxo.
2. Deve ser actualizado com a nova skill na lista de "SKILLS DISPONÍVEIS NO SISTEMA".
3. Categorizar na camada apropriada (provavelmente Camada 5 — Domínio).
4. Adicionar `protection_mode` correcto na frontmatter da nova skill.
**Output esperado:** Lista actualizada + categorização clara.
**Failure mode:** Esquecer de actualizar a lista → outras skills não sabem que `notification_manager` existe.

#### Exemplo 2: Regra nova de negócio aprovada (ex: gorjetas)
**Input (contexto):** BR §4.5 introduz feature de gorjetas (80%/20%, valores 1/2/3/5€).
**Processo:**
1. `rules.md` NÃO duplica a regra — apenas referencia BR §4.5 como source of truth.
2. Skills de domínio (`payment_manager`, `executor`) consultam BR §4.5 directamente.
3. Em conflito entre interpretações → BR §4.5 vence sempre.
**Output esperado:** Pointer a BR §4.5, sem duplicação de conteúdo.
**Failure mode:** Copiar a regra para `rules.md` → drift entre os dois ficheiros ao longo do tempo.

---

## REFERÊNCIAS BORA APP

- É o ponto de entrada — referencia todas as outras skills.
- Referencia: `.claude/.ai/business_rules.md` v2 como source of truth absoluto.
- Lê (apenas para indexar): [.claude/.ai/skills/](.claude/.ai/skills/) — todas as skills do sistema.

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** mantém "Engineering Handbook" — documento vivo com todas as regras técnicas e operacionais.
> **iFood** tem "Tech Guidelines" centralizadas que toda skill/agente consulta.
> **Glovo** usa "Engineering Charter" como referência única para princípios de qualidade.
> **Bora equivalente:** `rules.md` é o handbook do sistema multi-agente Bora — combinando Engineering Handbook do Uber com Tech Guidelines do iFood, com a particularidade de delegar regras de negócio a `business_rules.md` (separação clara de responsabilidades).
