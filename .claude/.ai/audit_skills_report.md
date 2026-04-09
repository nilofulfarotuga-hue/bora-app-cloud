# BORA — AUDITORIA COMPLETA DO SISTEMA DE SKILLS

> Read-only. Nenhuma skill foi modificada.
> Fonte de verdade: `.claude/.ai/business_rules.md`
> Diretório auditado: `.claude/.ai/skills/`

---

## 1. INVENTÁRIO (21 unidades)

**Flat (14):** rules, decision_engine, dispatch_engine_fix, fix_auth, fix_realtime, flow_guard, guardian, learning_engine, map_master, memory, performance_watcher, product_analyst, refactor_guard, system_validator
**Folders (7):** auto_orchestrator/, prompt_engine/, realtime_engine/, state_validator/, supabase_agent/, supabase_engine/

---

## 2. CLASSIFICAÇÃO POR SKILL

| # | Skill | Propósito | Conflito BR | Sobreposições | Status |
|---|---|---|---|---|---|
| 1 | rules.md | Filosofia de execução, modo controlado | — | meta | ✅ OK |
| 2 | decision_engine | Avaliador pré-execução de risco/impacto | — | guardian, flow_guard | ✅ OK |
| 3 | dispatch_engine_fix | Bug-fixer do dispatch sequencial | — | realtime_engine, state_validator | ⚠️ AJUSTE — não cobre fila 200m/5s nem capacidade 1↔3 |
| 4 | fix_auth | Validação Auth Supabase | — | guardian | ⚠️ AJUSTE — apenas 18 linhas, falta investigação/checklist |
| 5 | fix_realtime | Debug de sync realtime | — | realtime_engine, state_validator | ✅ OK |
| 6 | flow_guard | Bloqueia mudanças arquiteturais perigosas | — | guardian, refactor_guard, decision_engine | ✅ OK |
| 7 | guardian | Gate pré-execução (null safety, streams, dispatch, GPS) | — | flow_guard, decision_engine | 🔥 CRÍTICA |
| 8 | learning_engine | Análise de padrões históricos / retrospectiva | — | — | ✅ OK |
| 9 | map_master | GPS/mapas, anti-patterns, background tracking | — | — | ✅ OK |
| 10 | memory | Persistência append-only de decisões/bugs | — | — | ✅ OK |
| 11 | performance_watcher | Análise de GPS waste, rebuilds, leaks (sem executar) | — | — | ✅ OK |
| 12 | product_analyst | UX/feature suggester por prioridade | — | — | ✅ OK |
| 13 | refactor_guard | Bloqueia refatores de risco, sugere alternativas | — | guardian, flow_guard | ✅ OK |
| 14 | system_validator | Health check geral (pedidos, dispatch, tokens, GPS, auth) | — | state_validator | ✅ OK |
| 15 | auto_orchestrator/ | Orquestração + loop até 5 ciclos | — | TODAS | 🔴 REDUNDANTE — referencia skills inexistentes (auto_debug, ux_optimizer, system_designer, tester, executor) |
| 16 | prompt_engine/ | Geração+otimização de prompts | — | meta | ⚠️ AJUSTE — `generator.md` é template vazio com placeholders |
| 17 | realtime_engine/ | Sync orchestration (rules+sync+debug) | — | state_validator, guardian | ✅ OK |
| 18 | state_validator/ | Valida sequência imutável de status | — | system_validator | ✅ OK |
| 19 | supabase_agent/ | Política de interação API-only com Supabase | — | supabase_engine (complementar) | ✅ OK |
| 20 | supabase_engine/ | Execução SELECT-first, MCP-required | — | supabase_agent (complementar) | ✅ OK |

**Resumo:** 16 OK · 3 PRECISA AJUSTE · 1 REDUNDANTE · 1 CRÍTICA

---

## 3. SKILLS ESPERADAS PELO USUÁRIO MAS AUSENTES

| Skill | Categoria do plano | Impacto |
|---|---|---|
| auto_runner | Camada Execução | Mencionada na lista do usuário |
| executor | Camada Execução | Referenciada por auto_orchestrator (quebra a orquestração) |
| tester | Camada Execução | Referenciada por auto_orchestrator |
| auto_executor | A criar (Camada 2) | Não existe |
| decision_registry | A criar (Camada 1) | Não existe |
| context_analyzer | A criar (Camada 4) | Não existe |
| flow_controller | A criar (Camada 4) | Não existe |
| error_handler | A criar (Camada 4) | Não existe |
| payment_manager | A criar (Camada 5 — crítica) | Não existe |

---

## 4. CONFLITOS COM `business_rules.md`

✅ **Nenhum conflito direto detectado.** Nenhuma skill contradiz uma regra travada.

---

## 5. GAPS DE COBERTURA (regras sem skill responsável)

Regras de `business_rules.md` que **nenhuma skill cobre explicitamente**:

| Regra (BR) | Skill responsável atual | Gap |
|---|---|---|
| Fila local FIFO 200m + dwell 5s | nenhuma | dispatch_engine_fix não trata fila local |
| Capacidade 1↔3 (normal vs escassez) | nenhuma | falta lógica de capacity-aware dispatch |
| Prioridade dentro do estabelecimento não-parceiro | nenhuma | não modelado |
| Batching: critério `combined < indiv × 1.20` | nenhuma | nenhuma skill de batching |
| SLA GPS-driven (≤500m OR ≤2min ETA, extensão até +5min) | map_master parcial | sem skill de SLA monitor |
| Pagamento antes do dispatch + reconciliação não-parceiro | nenhuma | precisa payment_manager |
| Cancelamento 1,50€ / 50% / 100% | nenhuma | sem skill de fees |
| Tokens FIFO 60d / cap 50% do total | nenhuma | sem skill de token economy |
| Driver Help (4€ interno, 1 ajudante MVP) | nenhuma | feature inteira sem skill |
| Markup +15% invisível embutido no cadastro | nenhuma | sem skill de pricing |

---

## 6. SOBREPOSIÇÕES (top 5)

| # | Skills | Severidade | Diagnóstico |
|---|---|---|---|
| 1 | guardian × flow_guard × refactor_guard | Média | Três gates de segurança com fronteiras difusas. Guardian = código pré-exec; flow_guard = arquitetura; refactor_guard = mudanças estruturais. Funcional, mas precisa explicitar limites. |
| 2 | system_validator × state_validator | Baixa | Complementares (full-system vs status-only). OK. |
| 3 | supabase_agent × supabase_engine | Baixa | Complementares (política vs execução). OK. |
| 4 | realtime_engine × state_validator × fix_realtime | Média | 3 skills tocam consistência realtime. Risco de "quem chama quem". |
| 5 | decision_engine × guardian | Baixa | decision_engine = risco/impacto antes; guardian = checklist técnico. Ordem: decisão → guardian. |

---

## 7. PROBLEMAS DE QUALIDADE (top 5)

| # | Skill | Problema | Severidade |
|---|---|---|---|
| 1 | auto_orchestrator/ | Referencia 5+ skills inexistentes — orquestração quebrada | 🔴 Crítica |
| 2 | prompt_engine/generator.md | Template com placeholders `{modo}`/`{objetivo}` em vez de exemplos concretos | 🟠 Alta |
| 3 | fix_auth.md | Apenas 18 linhas; sem investigação, sem checklist, sem cenários de erro | 🟡 Média |
| 4 | dispatch_engine_fix | Cobre fix de bugs sequencial mas não cobre fila local 200m, capacidade elástica, prioridade dentro de estabelecimento | 🟡 Média |
| 5 | maioria | Faltam exemplos concretos (apenas 4/21 têm exemplos worked) | 🟡 Média |

---

## 8. CLASSIFICAÇÃO FINAL CONSOLIDADA

```
✅ OK              16  ████████████████  76%
⚠️ PRECISA AJUSTE   3  ███               14%
🔴 REDUNDANTE       1  █                  5%
🔥 CRÍTICA          1  █                  5%
```

---

## 9. PRÓXIMAS AÇÕES (NÃO EXECUTADAS — apenas sugestão)

Antes de qualquer modificação, aguardar autorização explícita do product owner para:

1. **Reescrever auto_orchestrator** — remover referências a skills inexistentes
2. **Expandir fix_auth** — adicionar checklist e cenários
3. **Expandir dispatch_engine_fix** — incluir fila 200m/5s, capacidade 1↔3, prioridade in-store
4. **Substituir prompt_engine/generator.md** por exemplos concretos
5. **Criar skills faltantes** (decision_registry, auto_executor, payment_manager, context_analyzer, flow_controller, error_handler) **somente após confirmação**
6. **Documentar fronteiras** entre guardian / flow_guard / refactor_guard

**Nenhuma ação foi tomada. Aguardando go/no-go.**
