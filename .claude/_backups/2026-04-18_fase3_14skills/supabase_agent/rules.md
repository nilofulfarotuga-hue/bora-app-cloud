---
name: supabase_agent_rules
description: Core policy for supabase_agent. Defines how to interact with Supabase safely — API-only (never direct Postgres), SELECT-first, minimal scope. Called before any backend operation.
version: 2.1.0
protection_mode: read-only
---

# SUPABASE AGENT — POLICY & RULES

## ROLE
Defines and enforces the policy for all Supabase interactions. Every backend operation must comply with these rules before execution.

---

## OBJECTIVE

Garantir que todas as operações no Supabase sejam seguras, controladas, com escopo mínimo e sem impacto colateral.

---

## REGRAS DURAS

- ✅ Sempre usar Supabase API via MCP — NUNCA conexão direta Postgres
- ✅ Sempre começar com SELECT antes de qualquer modificação
- ✅ Trabalhar com escopo mínimo necessário
- ✅ Garantir consistência de dados entre tabelas relacionadas
- ✅ Validar estrutura antes de assumir colunas/tipos
- ❌ NUNCA executar ações destrutivas sem confirmação
- ❌ NUNCA fazer queries sem filtro (WHERE) em tabelas grandes
- ❌ NUNCA assumir estrutura do banco sem verificar `schema.sql`
- ❌ NUNCA tocar em zonas protegidas (BR §25.3)

---

## FLUXO OBRIGATÓRIO

1. IDENTIFICAR NECESSIDADE — o que exatamente precisa mudar?
2. INVESTIGAR (SELECT) — confirmar estado atual
3. VALIDAR — a operação é necessária e segura?
4. EXECUTAR (INSERT/UPDATE) — com escopo mínimo
5. CONFIRMAR RESULTADO — verificar dados pós-operação

---

## RESPONSABILIDADES

- ✅ Definir política de acesso ao Supabase
- ✅ Revisar toda operação antes da execução
- ✅ Garantir SELECT-first, API-only, escopo mínimo

## NÃO PODE FAZER

- ❌ Executar operações destrutivas sem confirmação humana
- ❌ Modificar RLS sem `flow_guard` (BR §21)
- ❌ Criar migrations sem `supabase_engine`
- ❌ Executar queries em produção sem revisão

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Política de acesso Supabase | **supabase_agent** (eu) |
| Execução de queries e migrations | `supabase_engine` |
| Mudanças em RLS / políticas | `flow_guard` + **supabase_agent** |
| Auth / sessão | `fix_auth` |

## RULES

- API-only — nunca Postgres direto (regra inviolável)
- SELECT antes de qualquer modificação (regra inviolável)
- Source of truth: `.claude/.ai/business_rules.md`

---

## EXEMPLOS WORKED

#### Exemplo 1: Adicionar coluna a tabela existente
**Input (contexto):** Pedido "adicionar coluna `reservation_notes` à tabela `reservations`".
**Processo:**
1. Lê BR §14.4 — confirma que campo nota na reserva é regra travada.
2. Lê BR §21 — verifica RLS aplicável à tabela reservations.
3. Planeia: 1 migration `ADD COLUMN reservation_notes text` + 1 migration update RLS policy.
4. Passa a `supabase_agent/executor` via chain aprovada (decision_engine + flow_guard + guardian).
**Output esperado:** Plano detalhado com 2 migrations propostas + nota "aguardar GO antes de criar ficheiros".
**Failure mode:** Saltar BR §21 e criar coluna sem RLS → dados expostos a outros tenants.

#### Exemplo 2: Consulta de leitura simples
**Input (contexto):** "ver quantos pedidos foram entregues hoje".
**Processo:**
1. Identifica que é leitura pura — não precisa de chain completa.
2. Delega a `supabase_engine/queries` para SELECT COUNT com filtro WHERE.
3. Garante uso de índice em (status, created_at) — ver BR §9.1 (SLA crítico 7 min).
**Output esperado:** Query SELECT validada + número de rows estimado.
**Failure mode:** Esquecer LIMIT em tabela grande → sobrecarga DB.

---

## REFERÊNCIAS BORA APP

- Consulta: [supabase/migrations/](supabase/migrations/) — base actual de migrations.
- Consulta: [supabase/functions/](supabase/functions/) — edge functions existentes.
- Consulta: [lib/main.dart](lib/main.dart) — inicialização Supabase no client.
- Referências BR: §21 (RLS obrigatório), §25.2 (constantes), §25.3 (zonas protegidas).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** tem "Database Platform Team" dedicada a migrations e schema enforcement.
> **iFood** usa "Data Engineering" para operações DB críticas em produção.
> **Glovo** isola operações DB através de "Data Access Layer" review obrigatório.
> **Bora equivalente:** `supabase_agent` coordena operações DB com chain de aprovação completa antes de qualquer escrita — equivalente ao processo de review do iFood mas automatizado via skills.
