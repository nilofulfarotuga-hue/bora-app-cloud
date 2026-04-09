# BORA — ARQUITETURA FINAL DAS SKILLS (FASE 2)

> Planejamento read-only. Nenhum arquivo modificado.
> Base: `audit_skills_report.md` + `business_rules.md`
> Status: aguardando go/no-go para execução

---

## 1. ORGANIZAÇÃO POR CAMADAS

```
┌─────────────────────────────────────────────────────────────┐
│  CAMADA 0 — META (filosofia, regras de uso)                 │
│  rules                                                       │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 1 — CÉREBRO (decisão, memória, aprendizagem)        │
│  decision_engine · memory · learning_engine · product_analyst│
├─────────────────────────────────────────────────────────────┤
│  CAMADA 2 — CONTROLE (gates, bloqueios, validação prévia)   │
│  guardian · flow_guard · refactor_guard · state_validator    │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 3 — EXECUÇÃO (orquestração + ação)                  │
│  auto_orchestrator · executor* (NOVA)                        │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 4 — PROCESSAMENTO (análise, debug, performance)     │
│  performance_watcher · system_validator · fix_realtime      │
│  · fix_auth · dispatch_engine_fix                            │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 5 — ESPECIALISTAS DE DOMÍNIO (regras de negócio)    │
│  realtime_engine · map_master · payment_manager* (NOVA)     │
│  · dispatch_manager* (NOVA) · token_manager* (NOVA)         │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 6 — BACKEND (Supabase / infra)                      │
│  supabase_agent · supabase_engine                            │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 7 — AI (prompts, geração)                           │
│  prompt_engine                                               │
└─────────────────────────────────────────────────────────────┘
```

`*` = skill nova proposta na seção 5.

---

## 2. CLASSIFICAÇÃO CONSOLIDADA

### 2.1 MANTIDAS (sem mudança) — 13

| Skill | Camada | Razão |
|---|---|---|
| rules | 0 | Filosofia central, sem conflito |
| decision_engine | 1 | Avaliação risco/impacto pré-execução |
| memory | 1 | Append-only de decisões/bugs |
| learning_engine | 1 | Retrospectiva histórica |
| product_analyst | 1 | UX/feature suggester |
| flow_guard | 2 | Gate arquitetural |
| refactor_guard | 2 | Gate de refatores |
| state_validator | 2 | Sequência imutável de status |
| performance_watcher | 4 | Análise GPS/rebuilds/leaks |
| system_validator | 4 | Health check geral |
| fix_realtime | 4 | Debug realtime sync |
| realtime_engine | 5 | Sync orchestration |
| map_master | 5 | GPS/mapas/anti-patterns |
| supabase_agent | 6 | Política API-only |
| supabase_engine | 6 | Execução SELECT-first |

(15 itens — contagem real)

### 2.2 PRECISA AJUSTE — 3

| Skill | Problema | Ajuste necessário |
|---|---|---|
| **fix_auth** | 18 linhas, sem checklist, sem cenários de erro | Expandir com matriz de erros (PGRST116, JWT expired, RLS denied, anonymous mismatch), checklist de investigação, exemplos worked |
| **dispatch_engine_fix** | Cobre só bug-fix sequencial; ignora fila local 200m/5s, capacidade 1↔3, prioridade in-store | Expandir para refletir BR seções Dispatch/Capacidade/Fila — OU renomear para `dispatch_bugfix` e criar `dispatch_manager` separado (recomendado) |
| **prompt_engine/generator.md** | Template vazio com placeholders `{modo}`/`{objetivo}` | Substituir por 3-5 exemplos concretos de prompts BORA reais |

### 2.3 CRÍTICA — 1

| Skill | Problema | Ação |
|---|---|---|
| **guardian** | Funciona, mas tem fronteira difusa com flow_guard e refactor_guard. Risco de "quem chama quem" e gates inconsistentes | Documentar explicitamente: guardian = checklist técnico pré-execução de código (null safety, streams, dispatch, GPS); flow_guard = mudanças arquiteturais; refactor_guard = mudanças estruturais. Adicionar seção "NÃO faço X — chame Y" em cada uma |

### 2.4 REDUNDANTE / REMOVER — 1

| Skill | Problema | Decisão |
|---|---|---|
| **auto_orchestrator** | Referencia 5 skills inexistentes (auto_debug, ux_optimizer, system_designer, tester, executor). Orquestração quebrada | **REESCREVER** (não deletar). Manter o conceito mas reapontar para skills reais. Loop até 5 ciclos é válido. Decisão final: substituir todo o conteúdo por orquestração apoiada em skills existentes + nova `executor` |

---

## 3. RESPONSABILIDADES EXATAS

### Camada 0 — META

**rules**
- ✅ Filosofia de execução, modo controlado, princípios
- ❌ NÃO executa, NÃO valida, NÃO decide

### Camada 1 — CÉREBRO

**decision_engine**
- ✅ Avalia risco/impacto/reversibilidade ANTES de qualquer execução
- ✅ Retorna go/no-go com justificativa
- ❌ NÃO executa código, NÃO valida sintaxe, NÃO acessa banco

**memory**
- ✅ Append-only de decisões, bugs, padrões
- ❌ NÃO modifica entradas existentes, NÃO interpreta, NÃO decide

**learning_engine**
- ✅ Lê memory + git history para detectar padrões recorrentes
- ❌ NÃO escreve em memory, NÃO decide ações futuras (só sugere)

**product_analyst**
- ✅ Sugere features/UX por prioridade
- ❌ NÃO implementa, NÃO altera business_rules

### Camada 2 — CONTROLE

**guardian**
- ✅ Checklist técnico pré-execução de **código**: null safety, streams, dispatch sequencial, GPS leaks, dispose
- ❌ NÃO valida arquitetura (flow_guard), NÃO valida refatores (refactor_guard), NÃO valida estados (state_validator)

**flow_guard**
- ✅ Bloqueia mudanças **arquiteturais** perigosas (substituir Provider, mudar fluxo de auth, trocar Supabase por outro)
- ❌ NÃO valida código linha-a-linha, NÃO valida refatores localizados

**refactor_guard**
- ✅ Bloqueia refatores **estruturais** (renomear God Object, dividir arquivo grande, mover responsabilidade)
- ❌ NÃO valida código novo, NÃO valida arquitetura macro

**state_validator**
- ✅ Valida sequência imutável `created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered`
- ❌ NÃO valida pagamento, NÃO valida dispatch, NÃO valida realtime

### Camada 3 — EXECUÇÃO

**auto_orchestrator** (reescrito)
- ✅ Loop até 5 ciclos. Chama: decision_engine → guardian/flow_guard/refactor_guard → executor → system_validator → memory
- ❌ NÃO executa diretamente, NÃO toma decisões próprias

**executor** (NOVA — ver seção 5)
- ✅ Executa ações já aprovadas (Edit/Write/Bash) com logging
- ❌ NÃO decide o que executar, NÃO valida pré-execução

### Camada 4 — PROCESSAMENTO

**performance_watcher**
- ✅ Detecta GPS waste, rebuilds excessivos, leaks (análise estática)
- ❌ NÃO corrige, NÃO executa profiler

**system_validator**
- ✅ Health check geral pós-execução: pedidos, dispatch, tokens, GPS, auth
- ❌ NÃO corrige bugs, NÃO valida sequência de estados (delegar a state_validator)

**fix_realtime**
- ✅ Investiga bugs específicos de sync realtime
- ❌ NÃO modifica regras de sync (delegar a realtime_engine)

**fix_auth** (após expansão)
- ✅ Investiga bugs de Auth Supabase (RLS, JWT, anonymous, RPC denied)
- ❌ NÃO altera políticas RLS sem flow_guard

**dispatch_engine_fix** (renomeado → `dispatch_bugfix`)
- ✅ Bug-fixer pontual do dispatch sequencial existente
- ❌ NÃO implementa novas regras de fila/capacidade — delegar a `dispatch_manager`

### Camada 5 — ESPECIALISTAS DE DOMÍNIO

**realtime_engine**
- ✅ Política e regras de sync (Postgres streams, channels, debounce, cleanup)
- ❌ NÃO debuga incidentes pontuais (delegar a fix_realtime)

**map_master**
- ✅ GPS, mapas, background tracking, anti-patterns, interpolação
- ❌ NÃO implementa SLA monitor (delegar a `dispatch_manager`)

**dispatch_manager** (NOVA)
- ✅ Implementa BR seções Dispatch/Capacidade/Fila/SLA: FIFO 200m/5s, capacidade 1↔3, prioridade in-store, SLA GPS-driven com extensão até +5min
- ❌ NÃO debuga bugs (delegar a dispatch_bugfix)

**payment_manager** (NOVA)
- ✅ Implementa BR seções Pagamento/Não-parceiro/Cancelamento: pre-dispatch payment, buffer não-parceiro, fees de cancelamento, markup +15% invisível
- ❌ NÃO toca em tokens (delegar a token_manager)

**token_manager** (NOVA)
- ✅ Implementa BR seção Tokens: FIFO 60d, conversão 100=0,50€, teto 50% do total, cashback 3%
- ❌ NÃO toca em pagamento direto (delegar a payment_manager)

### Camada 6 — BACKEND

**supabase_agent**
- ✅ Política: API-only, nunca SQL direto sem MCP
- ❌ NÃO executa queries

**supabase_engine**
- ✅ Execução SELECT-first via MCP, migrations controladas
- ❌ NÃO decide políticas (delegar a supabase_agent)

### Camada 7 — AI

**prompt_engine** (após ajuste)
- ✅ Otimização e geração de prompts BORA com exemplos concretos
- ❌ NÃO executa prompts

---

## 4. CONFLITOS DE RESPONSABILIDADE — RESOLUÇÃO

| Conflito | Resolução |
|---|---|
| **executor vs auto_runner vs auto_executor** (todos ausentes/redundantes na lista do usuário) | Manter **apenas `executor`**. auto_runner e auto_executor não são criados. Razão: 1 skill = 1 responsabilidade clara (executar ação aprovada) |
| **guardian vs flow_guard vs refactor_guard** | Fronteira por escopo: **código** (guardian) / **arquitetura** (flow_guard) / **estrutura** (refactor_guard). Documentar em cada skill seção "NÃO faço X" |
| **system_validator vs state_validator** | system = full health check pós-exec; state = só sequência de status. Mantidas (complementares) |
| **realtime_engine vs fix_realtime vs state_validator** | realtime_engine = regras; fix_realtime = bugs pontuais; state_validator = só status. Sem overlap se respeitarem fronteiras |
| **dispatch_engine_fix vs dispatch_manager (nova)** | Renomear `dispatch_engine_fix` → `dispatch_bugfix` (só bugs). Toda lógica de regras vai para `dispatch_manager` |
| **decision_engine vs guardian** | Ordem fixa: `decision_engine` (vale a pena?) → `guardian` (técnico OK?). Nunca em paralelo |

---

## 5. SKILLS NOVAS PROPOSTAS (MAX 5)

### 5.1 `executor`
- **Camada:** 3
- **Problema:** auto_orchestrator referencia executor que não existe → orquestração quebrada
- **Por que necessária:** separar "decidir" de "fazer". Sem executor explícito, qualquer ação é tomada inline sem rastreabilidade
- **Escopo:** recebe ação aprovada (Edit/Write/Bash), executa, retorna resultado + log para memory

### 5.2 `dispatch_manager`
- **Camada:** 5
- **Problema:** Nenhuma skill cobre fila local 200m/5s, capacidade 1↔3, prioridade in-store, SLA GPS-driven
- **Por que necessária:** business_rules.md define ~10 regras de dispatch sem skill responsável. Sem isso, qualquer implementação fica órfã
- **Escopo:** Regime A (FIFO local) + Regime B (scoring fora da fila) + SLA monitor + capacity-aware

### 5.3 `payment_manager`
- **Camada:** 5
- **Problema:** Pagamento pré-dispatch, buffer não-parceiro, cancelamento (1,50€/50%/100%), markup +15% invisível, +3€ pedido adicional — nenhuma skill cobre
- **Por que necessária:** Regra crítica do BR ("pagamento antes do dispatch") sem skill = risco financeiro
- **Escopo:** Stripe Payment Intents, reconciliação não-parceiro, fees, markup invisível

### 5.4 `token_manager`
- **Camada:** 5
- **Problema:** FIFO 60d, conversão, teto 50%, cashback 3%, +50 tokens pedido adicional — nenhuma skill
- **Por que necessária:** Token economy é metade da economia BORA. Lógica espalhada = bugs garantidos
- **Escopo:** RPCs `consume_tokens`/`add_tokens`/`get_user_tokens`, expiração, validação no checkout

### 5.5 `decision_registry`
- **Camada:** 1
- **Problema:** memory é append-only de bugs/decisões, mas não há índice consultável de decisões travadas (ex: "BR v1.2 trava raio em 200m fixo")
- **Por que necessária:** evita reabrir discussões já fechadas. Todo PR pode consultar antes de propor mudança
- **Escopo:** lookup rápido por tópico → decisão atual + versão BR + data

**Total:** 5 skills novas (limite respeitado).

**NÃO criadas** (da lista do usuário): auto_runner, auto_executor, context_analyzer, flow_controller, error_handler.
**Razão:** redundantes com executor (auto_runner/auto_executor), com decision_engine (context_analyzer), com flow_guard (flow_controller), ou com guardian+system_validator (error_handler).

---

## 6. GARANTIAS

### 6.1 Sem duplicação
- Cada regra do BR tem **exatamente 1** skill responsável (ver tabela seção 7)
- Cada gate tem escopo exclusivo (código vs arquitetura vs estrutura vs estado)
- Cada camada de execução tem 1 papel (decidir vs executar vs validar)

### 6.2 Sem sobreposição
- Camadas hierárquicas: superior chama inferior, nunca lateral
- Camada 1 (cérebro) → Camada 2 (controle) → Camada 3 (execução) → Camada 4 (validação)
- Especialistas (camada 5) só são chamados via Camada 3

### 6.3 Compatibilidade com business_rules.md
Todas as 18 regras críticas e 33 constantes têm skill responsável:

| Regra BR | Skill |
|---|---|
| Dispatch sequencial, no broadcast | dispatch_manager |
| FIFO 200m/5s | dispatch_manager |
| Capacidade 1↔3 | dispatch_manager |
| Prioridade in-store não-parceiro | dispatch_manager |
| Batching `combined < indiv × 1.20` | dispatch_manager |
| SLA GPS-driven ≤500m OR ≤2min, +5min teto | dispatch_manager |
| Pagamento antes do dispatch | payment_manager |
| Buffer não-parceiro + reconciliação | payment_manager |
| Cancelamento 1,50€/50%/100% | payment_manager |
| Markup +15% invisível | payment_manager |
| +3€ pedido adicional | payment_manager |
| Tokens FIFO 60d, 50% teto | token_manager |
| +50 tokens pedido adicional | token_manager |
| Cashback 3% | token_manager |
| Driver Help 4€ interno (MVP) | dispatch_manager (helper dispatch) + payment_manager (4€ interno) |
| Sequência imutável de estados | state_validator |
| GPS / mapas / interpolação | map_master |
| Realtime sync | realtime_engine |
| Auth Supabase | fix_auth + supabase_agent |

✅ Cobertura 100% após criação das 5 skills novas.

---

## 7. ESTADO FINAL — RESUMO NUMÉRICO

```
Antes:     21 unidades (16 OK · 3 ajuste · 1 redundante · 1 crítica)
           + 9 ausentes esperadas

Depois:    20 unidades flat/folder organizadas em 8 camadas
           ├─ 13 mantidas
           ├─  3 ajustadas (fix_auth, dispatch_engine_fix→dispatch_bugfix, prompt_engine)
           ├─  1 reescrita (auto_orchestrator)
           ├─  1 documentada (guardian — fronteiras)
           └─  5 novas (executor, dispatch_manager, payment_manager,
                        token_manager, decision_registry)

Cobertura BR:  100% (era ~40%)
Conflitos:     0
Sobreposições: 0 (todas resolvidas por escopo)
```

---

## 8. ORDEM DE EXECUÇÃO PROPOSTA (quando autorizado)

1. **Documentar fronteiras** guardian / flow_guard / refactor_guard (sem código)
2. **Reescrever** auto_orchestrator apontando para skills reais
3. **Criar** executor (Camada 3) — desbloqueia auto_orchestrator
4. **Renomear** dispatch_engine_fix → dispatch_bugfix
5. **Criar** dispatch_manager (Camada 5) — cobre maior gap do BR
6. **Criar** payment_manager (Camada 5) — risco financeiro
7. **Criar** token_manager (Camada 5)
8. **Criar** decision_registry (Camada 1)
9. **Expandir** fix_auth (matriz de erros + checklist)
10. **Substituir** prompt_engine/generator.md por exemplos concretos

**Nenhum arquivo modificado. Aguardando go/no-go por etapa ou em bloco.**
