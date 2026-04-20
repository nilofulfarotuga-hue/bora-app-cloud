# Passo 2 — Índice das análises por skill

> Sub-fase 2.A · Read-only · 2026-04-17
> Total: **42 skills** distribuídas por 8 camadas + extras/legacy

## Estrutura dos ficheiros

| Ficheiro | Camada | Skills |
|---|---|---|
| [passo2_0_meta.md](passo2_0_meta.md) | Camada 0 — META | rules |
| [passo2_1_cerebro.md](passo2_1_cerebro.md) | Camada 1 — CÉREBRO | decision_engine, memory, learning_engine, product_analyst, decision_registry |
| [passo2_2_controle.md](passo2_2_controle.md) | Camada 2 — CONTROLE | guardian, flow_guard, refactor_guard, state_validator/rules, state_validator/validation |
| [passo2_3_execucao.md](passo2_3_execucao.md) | Camada 3 — EXECUÇÃO | auto_orchestrator/rules, flow, decision, loop, executor |
| [passo2_4_processamento.md](passo2_4_processamento.md) | Camada 4 — PROCESSAMENTO | performance_watcher, system_validator, fix_realtime, fix_auth, dispatch_bugfix |
| [passo2_5_dominio.md](passo2_5_dominio.md) | Camada 5 — ESPECIALISTAS | realtime_engine (rules/sync/debug), map_master, dispatch_manager, payment_manager, token_manager |
| [passo2_6_backend.md](passo2_6_backend.md) | Camada 6 — BACKEND | supabase_agent (rules/executor), supabase_engine (rules/debug/queries) |
| [passo2_7_ai.md](passo2_7_ai.md) | Camada 7 — AI | prompt_engine (rules/generator/optimizer) |
| [passo2_extras_legacy.md](passo2_extras_legacy.md) | Extras/Legacy | (root) manager, tester, auto_debug, auto_runner, memory_store · (plugin) ceo-ai |

## Ficheiros de trabalho (não são fichas)

- `_skill_profiles.json` — métricas estruturais cruas das 42 skills
- `_skill_profiles_table.md` — tabela markdown com scores
- `_skill_sections.json` — todo o conteúdo por secção H2 (148 KB)

## Formato da ficha

Cada skill tem:
1. Caminho + versão + tamanho
2. Estado atual (ROLE/OBJECTIVE resumo)
3. Sete scores de qualidade (0-10)
4. Gaps identificados
5. Melhorias propostas (ADICIONAR / REMOVER / REESCREVER)
6. Refs Bora App que deveriam estar na skill
7. Benchmarks Uber/iFood/Glovo relevantes
8. Risco + Esforço estimados
