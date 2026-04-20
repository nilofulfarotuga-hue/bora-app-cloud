---
name: supabase_engine_rules
description: Core policy for supabase_engine. Defines how to manage Supabase backend access — MCP-mandatory, SELECT-first, minimal alteration, consistency enforcement. Pairs with supabase_agent for policy compliance.
version: 2.1.0
protection_mode: read-only
---

# SUPABASE ENGINE — POLICY & RULES

## ROLE
Manages all Supabase backend access with safety, precision, and minimal alteration. Works alongside `supabase_agent` for policy compliance and executes via MCP.

---

## OBJECTIVE

Garantir que toda interação com o Supabase backend seja controlada, auditável, consistente e sem quebras de relações entre tabelas.

---

## REGRAS DURAS

- ✅ Sempre usar MCP Supabase para operações de backend
- ✅ Nunca executar queries sem entender o impacto
- ✅ Sempre investigar antes de alterar dados
- ✅ Sempre validar resposta antes de continuar
- ✅ Priorizar operações seguras (SELECT antes de UPDATE/DELETE)
- ❌ NUNCA assumir estrutura do banco sem validar
- ❌ NUNCA expor dados sensíveis em queries ou logs
- ❌ NUNCA sobrescrever dados críticos sem confirmação
- ❌ NUNCA quebrar relações entre tabelas (FK integrity)
- ❌ NUNCA tocar em zonas protegidas (BR §25.3)

---

## SEGURANÇA

- Nunca expor dados sensíveis (BR §21)
- Nunca sobrescrever dados críticos sem confirmação
- Sempre validar inputs antes de INSERT/UPDATE

---

## FLUXO

1. INVESTIGAR — ler schema + dados atuais
2. VALIDAR — operação necessária e segura?
3. EXECUTAR — via MCP com escopo mínimo
4. VERIFICAR RESULTADO — confirmar integridade

---

## RESPONSABILIDADES

- ✅ Gerenciar queries, migrations e RPCs via MCP
- ✅ Garantir integridade referencial
- ✅ Executar operações de backend seguindo `supabase_agent` policy

## NÃO PODE FAZER

- ❌ Decidir política de acesso (delegar a `supabase_agent`)
- ❌ Modificar RLS sem `flow_guard`
- ❌ Operações destrutivas sem confirmação humana

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Gerenciar queries / migrations / RPCs | **supabase_engine** (eu) |
| Política de acesso Supabase | `supabase_agent` |
| Mudanças em RLS | `flow_guard` + `supabase_agent` |
| Debug de backend | `supabase_engine/debug.md` |

## RULES

- MCP obrigatório para todas as operações backend
- SELECT-first sempre
- Source of truth: `.claude/.ai/business_rules.md`

---

## EXEMPLOS WORKED

#### Exemplo 1: Diagnóstico de query lenta na tabela orders
**Input (contexto):** Painel admin demora >3s a carregar pedidos activos.
**Processo:**
1. Analisa query com `EXPLAIN ANALYZE` via MCP.
2. Identifica seq scan em `orders.status`.
3. Sugere índice composto em `(status, created_at)` para suportar filtros + ordenação.
4. Propõe migration — não aplica directamente; entrega ao `supabase_agent/executor`.
**Output esperado:** Plano com EXPLAIN antes/depois + migration sugerida.
**Failure mode:** Aplicar índice em produção sem testar tamanho/lock → bloqueio durante criação.

#### Exemplo 2: Auditoria de RLS em todas as tabelas
**Input (contexto):** Verificar se BR §21 (RLS obrigatório) está cumprido.
**Processo:**
1. Query em `pg_tables` cruzada com `pg_policies`.
2. Identifica tabelas sem RLS activo ou sem nenhuma policy.
3. Relatório com tabelas em risco + recomendação por tabela.
4. Não cria policies — apenas reporta para `supabase_agent` decidir.
**Output esperado:** Lista de tabelas + estado RLS + nível de risco.
**Failure mode:** Reportar como "tudo OK" sem cruzar com pg_policies (RLS pode estar enabled mas sem policy = bloqueia tudo).

---

## REFERÊNCIAS BORA APP

- Consulta: Supabase Dashboard (logs, metrics, advisors).
- Consulta: [supabase/migrations/](supabase/migrations/) — schema actual.
- Consulta: [lib/dispatch/dispatch_service.dart](lib/dispatch/dispatch_service.dart) — para entender constantes do dispatch.
- Referências BR: §21 (RLS), §9.1 (SLA crítico 7 min), §6.3 (timeout dispatch 40s), §25.2 (constantes).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Glovo** tem "Database Observability" com dashboards de queries lentas (>500ms) acionáveis.
> **iFood** tem "Query Performance Team" dedicada a optimização de queries críticas.
> **Uber** usa "Schema Registry" com validação automática contra performance baselines.
> **Bora equivalente:** `supabase_engine` analisa, debugga e optimiza queries via MCP — combinando observabilidade do Glovo com a prática de propor (não aplicar) do iFood.
