---
name: supabase_engine_queries
description: Query execution procedure for supabase_engine. Protocol for running controlled, efficient Supabase queries via MCP — SELECT, INSERT, UPDATE with proper filters and validation.
version: 2.1.0
protection_mode: read-only
---

# SUPABASE ENGINE — QUERY EXECUTION

## ROLE
Step-by-step protocol for executing database queries efficiently and safely via Supabase MCP.

---

## OBJECTIVE

Executar queries no banco de forma controlada, eficiente e sem impacto desnecessário.

---

## PASSOS

### 1. INVESTIGAR
- Identificar tabela correta
- Identificar colunas necessárias (nunca `SELECT *`)
- Ler estrutura mínima antes de modificar

### 2. VALIDAR
- Confirmar query antes de executar
- Estimar impacto (quantas rows afetadas?)
- Verificar se operação é realmente necessária

### 3. EXECUTAR
- Preferir SELECT primeiro
- INSERT/UPDATE só se necessário e confirmado
- Nunca operações em massa sem filtro WHERE

### 4. VERIFICAR
- Confirmar resultado da query
- Verificar integridade dos dados (FK, constraints)
- Logar resultado para rastreabilidade

---

## REGRAS

- ❌ Nunca `SELECT *` — especificar colunas
- ❌ Nunca sem filtro WHERE em tabelas grandes
- ❌ Nunca joins desnecessários
- ✅ Sempre limitar resultados com `.limit(n)`
- ✅ Sempre usar índices quando disponíveis
- ✅ Sempre respeitar BR §21 (RLS) e §25.2 (constantes)

---

## RESPONSABILIDADES

- ✅ Executar queries individuais controladas
- ✅ Garantir eficiência e integridade

## NÃO PODE FAZER

- ❌ Decidir política de acesso (delegar a `supabase_agent`)
- ❌ Executar migrations (usar procedure separada)
- ❌ Operações destrutivas sem confirmação

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Executar queries controladas | **supabase_engine/queries.md** (eu) |
| Investigar problema de backend | `supabase_engine/debug.md` |
| Política de acesso | `supabase_agent/rules.md` |

## RULES

- SELECT-first obrigatório antes de qualquer modificação
- Filtros WHERE obrigatórios em tabelas grandes
- Source of truth: `.claude/.ai/business_rules.md`

---

## EXEMPLOS WORKED

#### Exemplo 1: Buscar pedidos activos com dados de driver e cliente
**Input (contexto):** Painel admin precisa listar pedidos não-finalizados.
**Processo:**
1. Identifica colunas necessárias — não usa `SELECT *`.
2. Query:
   ```sql
   SELECT o.id, o.status, o.created_at, d.name AS driver_name, p.name AS client_name
   FROM orders o
   LEFT JOIN drivers d ON d.id = o.driver_id
   LEFT JOIN profiles p ON p.id = o.client_id
   WHERE o.status NOT IN ('delivered', 'cancelled')
   ORDER BY o.created_at DESC
   LIMIT 100;
   ```
3. Usa índices existentes em `orders.status` + `orders.created_at`.
**Output esperado:** Resultado limitado a 100 rows + tempo de execução.
**Failure mode:** Esquecer LIMIT → painel descarrega 50k pedidos e bloqueia browser.

#### Exemplo 2: Pedidos críticos do painel admin (>7 min sem driver — BR §9.1)
**Input (contexto):** Alerta SLA crítico — pedidos parados em `callingDriver` há mais de 7 min.
**Processo:**
1. Lê BR §9.1 — SLA crítico = 7 min (= 420 segundos).
2. Query:
   ```sql
   SELECT id, status, EXTRACT(EPOCH FROM (NOW() - created_at)) AS age_seconds
   FROM orders
   WHERE status = 'callingDriver'
     AND EXTRACT(EPOCH FROM (NOW() - created_at)) > 420
   ORDER BY created_at ASC
   LIMIT 50;
   ```
3. Threshold `420` referencia explícita a BR §9.1 (não é literal mágico).
**Output esperado:** Lista de pedidos críticos + idade em segundos.
**Failure mode:** Hardcoded `> 600` em vez de BR §9.1 → desalinhamento com regra de negócio.

---

## REFERÊNCIAS BORA APP

- Consulta: [supabase/migrations/](supabase/migrations/) — schema actual + índices.
- Consulta: [lib/models/order_model.dart](lib/models/order_model.dart) — colunas usadas pelo client.
- Consulta: [lib/models/order_service_type.dart](lib/models/order_service_type.dart) — enum status para filtros.
- Referências BR: §9.1 (SLA crítico 7 min = 420s), §21 (RLS), §1.3/§1.4 (status progression), §25.2 (constantes).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** tem "Query Approval Service" — qualquer query >100ms exige aprovação.
> **iFood** tem catálogo de queries pré-aprovadas para painéis admin (evita ad-hoc lento).
> **Glovo** força `EXPLAIN` antes de qualquer query nova ir para produção.
> **Bora equivalente:** `supabase_engine/queries` exige `LIMIT`, filtros explícitos e referências a BR §X em vez de literais — combinando catálogo do iFood com EXPLAIN-first do Glovo.
