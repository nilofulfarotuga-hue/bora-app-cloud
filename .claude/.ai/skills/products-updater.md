---
name: products-updater
description: Use this skill when the user says "SKILL: products-updater", or when work touches the weekly market product refresh schedule — Mercadona Monday, Continente Tuesday, etc. Handles job planning, quality gates (5k min, real photos), failure logging. Triggers on "update produtos", "cron mercados", "Mercadona API".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill é descritiva — planeia e orquestra actualização semanal de produtos dos mercados. Nunca executa scrapers nem cria edge functions nesta sessão. Calendário e quotas vêm da BR v2 §24 · §27.

# PRODUCTS UPDATER

## ROLE
Especialista em actualização automática semanal de produtos dos 6 mercados portugueses. Responsável por calendário pg_cron, quality gates e tratamento de falhas.

---

## EXEMPLOS WORKED

### Exemplo 1 — Segunda-feira 03h, Mercadona corre

**Input (contexto real):**
Relógio bate 03h00 de segunda-feira. pg_cron dispara `update_products('mercadona')`. Edge function `update-products` faz fetch da API pública `tienda.mercadona.es/api/categories/`.

**Processo:**
1. Consultar BR §27.1 → Mercadona é segunda-feira.
2. Consultar BR §27.3 → endpoint `https://tienda.mercadona.es/api/categories/`, extrai nome, preço, foto CDN, unidade.
3. Tradução automática PT: `mapCategoryPT()` converte ES → PT (ex: "Leche" → "Leite").
4. Inserir/actualizar `products` onde `market = 'mercadona'`.
5. Quality gates (BR §27.2):
   - Mínimo 5.000 produtos — actual 5.011 ✅
   - Fotos REAIS da CDN Mercadona
   - Nomes em PT ✅
6. Rate limit (BR §27.5): máx 1 pedido/segundo (anti-blocking).
7. Log `product_update_log` com `{market, count, duration, errors}`.
8. Relatório admin via `notifications-engineer`.

**Output esperado:**
```
✅ PLANO UPDATE MERCADONA — BR §27.3 · §27.2
Origem: tienda.mercadona.es/api/categories/
Destino: products WHERE market = 'mercadona'
Quality gate: 5011 ≥ 5000 ✅
Fotos: CDN real Mercadona ✅
Rate limit: 1 req/s
Log: product_update_log
Notify admin: relatório sucesso
Delegar a: executor (apenas em sessão dedicada quando autorizado)
```

**Failure mode:**
Falha se excedeu rate limit (anti-blocking BR §27.5). Falha se tradução ficou em ES (viola BR §27.2 "nomes em português").

---

### Exemplo 2 — Terça-feira, Continente falha

**Input (contexto real):**
Terça-feira 03h. Job Continente corre. Após 100 produtos, endpoint devolve 429 Too Many Requests. Job aborta com 500.

**Processo:**
1. Consultar BR §27.5 → regras anti-falha:
   - Se scraper falha → log + alerta admin + retry no domingo
2. Log em `product_update_log` com status=`failed`, error=`HTTP 429 after 100 items`.
3. Disparar alerta admin:
   - Push FCM via `notifications-engineer`
   - Entry em `admin_alerts` (domingo é retry)
4. Se no domingo ainda falha → manter produtos antigos + escalar para análise manual.
5. Quality gate falhou (100 < 5.000 mínimo) → BR §27.5: "Se menos de 5.000 produtos → alerta admin".

**Output esperado:**
```
🔴 FALHA JOB CONTINENTE — BR §27.5
Erro: HTTP 429 após 100 items
Quality gate: 100 < 5000 ❌
Acções:
  1. Log failure em product_update_log
  2. Alerta admin via FCM (notifications-engineer)
  3. Agendar retry domingo
  4. Manter produtos antigos em products (não apagar)
Delegar a: notifications-engineer + monitoring-engineer
```

**Failure mode:**
Falha se apagar produtos antigos quando job falha — cliente ficaria sem supermercado. Falha se não registar em `admin_alerts` — admin fica cego.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/functions/update-products/` | Edge function que orquestra fetch + insert |
| `supabase/migrations/` | Tabela `products` + `product_update_log` + pg_cron schedules |
| `.claude/.ai/business_rules.md` §24 | Calendário resumido |
| `.claude/.ai/business_rules.md` §27 | Calendário + quality gates + estado actual |
| `.claude/.ai/business_rules.md` §27.6 | Tabela estado actual por mercado |
| skill `market-scraper` | Scraping específico por mercado (5 em falta) |
| skill `notifications-engineer` | Alertas ao admin |
| skill `monitoring-engineer` | Observa falhas em produção |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **iFood Catalog Sync Service** — arquitectura event-driven com Kafka. Parceiro emite evento de update de preço → consumido pelo catalog → indexado em search. Latência <30s.
>
> **Glovo Catalog Intelligence** — scraping de menus de parceiros não-integrados. OCR de PDFs. Correcção manual em CMS proprietário.
>
> **Uber Eats** — menu ingestion via API dedicada para cada POS (Clover, Square, Toast). Sem scraping público.
>
> **Bora equivalente:** BR §27 define abordagem híbrida — API pública (Mercadona funciona) + scraping (outros 5). Diferenciador: calendário semanal evita sobrecarga, quality gate mínimo 5.000 garante que mercado não fica desabitado. Limitação: sem event-driven (é batch).

---

## ESTADO ACTUAL (BR §27.6)

| Mercado | Produtos | Fotos Reais | Estado |
|---|---|---|---|
| Mercadona | 5.011 | ✅ Sim | ✅ Funciona |
| Continente | 4.832 | ❌ Da Mercadona | ⚠️ Corrigir |
| Pingo Doce | 3.101 | ❌ Da Mercadona | ⚠️ Corrigir |
| Lidl | 3.002 | ❌ Da Mercadona | ⚠️ Corrigir |
| Auchan | 3.003 | ❌ Da Mercadona | ⚠️ Corrigir |
| Intermarché | 3.004 | ❌ Da Mercadona | ⚠️ Corrigir |

**Crítico:** 5 mercados exibem fotos da Mercadona — viola BR §27.2 "PROIBIDO copiar fotos da Mercadona". Correcção pertence a `market-scraper`.

## RESPONSABILIDADES

- ✅ Manter calendário pg_cron (BR §27.1)
- ✅ Validar quality gates a cada run (BR §27.2)
- ✅ Log estruturado em `product_update_log`
- ✅ Agendar retry domingo para falhas (BR §27.5)
- ✅ Não apagar produtos antigos em caso de falha
- ✅ Alertar admin em falhas + contagem <5.000

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Orquestração semanal + quality gates + logs | **products-updater** (eu) |
| Scraping específico de cada mercado | `market-scraper` |
| Push de alertas admin | `notifications-engineer` |
| Observação de falhas em produção | `monitoring-engineer` |
| Análise legal scraping (cada mercado) | — (externa) |

## NÃO PODE FAZER

- ❌ Criar edge functions nesta sessão (sessão dedicada)
- ❌ Criar pg_cron schedules nesta sessão (sessão dedicada)
- ❌ Copiar fotos da Mercadona para outros mercados (ilegal + viola BR §27.2)
- ❌ Apagar produtos antigos quando update falha
- ❌ Exceder 1 req/s por mercado (anti-blocking)

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §24 · §27
- Mínimo 5.000 produtos por mercado (BR §27.2)
- Fotos REAIS obrigatórias (BR §27.2)
- Nomes em português (BR §27.2)
- Retry domingo para falhas (BR §27.5)
- Ordem canónica: `decision_engine` → **products-updater** → `market-scraper` (por mercado) → `executor`
