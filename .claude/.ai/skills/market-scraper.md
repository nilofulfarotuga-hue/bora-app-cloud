---
name: market-scraper
description: Use this skill when the user says "SKILL: market-scraper", or when work touches specific scraper implementation for the 6 Portuguese markets — Continente, Pingo Doce, Lidl, Auchan, Intermarché (Mercadona uses public API). Requires legal analysis per market. Triggers on "scraper Continente", "fetch Lidl", "Pingo Doce produtos".
version: 1.0.0
protection_mode: read-only
---

> **AVISO LEGAL:** scraping pode ser proibido por Termos de Serviço. Verificar ToS de cada mercado ANTES de implementar. Esta skill é descritiva — nunca executa scrapers nem cria edge functions nesta sessão. Fotos reais obrigatórias (BR §27.2).

# MARKET SCRAPER

## ROLE
Especialista em scraping de dados dos 6 mercados portugueses. Escolhe estratégia por mercado (API semi-aberta vs scraping HTML) e respeita quotas anti-blocking.

---

## EXEMPLOS WORKED

### Exemplo 1 — Continente (Salesforce Commerce Cloud)

**Input (contexto real):**
Precisa actualizar produtos Continente. Site `continente.pt` usa Salesforce Commerce Cloud (SFCC). Endpoint `/api/ocapi/shop/v22_4/products/{id}` retorna JSON.

**Processo:**
1. Verificar ToS do Continente — se proibido explicitamente, abortar e escalar.
2. Estratégia:
   - Fetch sitemap XML para lista de IDs de produtos (200.000+).
   - Filtrar por categorias relevantes (supermercado, não eletrónica/moda).
   - Para cada ID: fetch `/api/ocapi/shop/v22_4/products/{id}` → JSON com nome, preço, imagem, unidade.
3. Imagens: URL CDN Continente (`cdnd.continente.pt/...`) — são as REAIS (BR §27.2 cumpre).
4. Rate limit: 1 req/s (BR §27.5).
5. Target: 5.000 produtos em <90 minutos.
6. Guardar em `products` WHERE `market='continente'`.

**Output esperado:**
```
✅ PLANO SCRAPER CONTINENTE — BR §27.4
ToS review: pendente análise legal
Estratégia: SFCC API /ocapi/shop/v22_4
Fonte imagens: cdnd.continente.pt (REAIS)
Target: 5000 produtos <90min @ 1 req/s
Destino: products WHERE market='continente'
Delegar a: executor apenas após aprovação legal
```

**Failure mode:**
Falha se usar imagens da Mercadona como fallback (BR §27.2 proíbe). Falha se ignorar ToS.

---

### Exemplo 2 — Lidl bloqueia IP (HTTP 429/403)

**Input (contexto real):**
Scraper Lidl começa bem. Após 300 produtos, `lidl.pt` devolve HTTP 429 (Too Many Requests) e depois 403 (Forbidden).

**Processo:**
1. Detectar 429/403 → pausar scraper imediato.
2. Estratégia de recuperação:
   - Esperar 30s (backoff inicial)
   - Rotar User-Agent (passar de Chrome/Windows → Firefox/Mac)
   - Retry com backoff exponencial: 30s, 60s, 120s
3. Se após 3 retries continua a falhar → abortar com erro e agendar retry domingo (BR §27.5).
4. Log detalhado: `{market: lidl, status: 429/403, attempt: N, next_retry: sunday}`.
5. Alertar admin via `notifications-engineer`.

**Output esperado:**
```
⚠️ LIDL RATE LIMITED — BR §27.5
Erros: HTTP 429 depois 403 aos 300 produtos
Backoff: 30s → 60s → 120s (máx 3 retries)
Fallback: agendar retry domingo + alerta admin
Log: product_update_log + admin_alerts
Delegar a: monitoring-engineer (observar padrão) + executor (dry-run safe)
```

**Failure mode:**
Falha se fizer bruteforce sem backoff (IP banido definitivamente). Falha se não rotar User-Agent — agrava bloqueio.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/functions/update-products/` | Edge function hospeda cada scraper |
| `.claude/.ai/business_rules.md` §27 | Calendário + quality gates + rate limits |
| `.claude/.ai/business_rules.md` §27.4 | Estratégia por mercado |
| skill `products-updater` | Orquestra o ciclo semanal |
| skill `monitoring-engineer` | Observa falhas em produção |
| skill `notifications-engineer` | Alerta admin em falha |

---

## ESTRATÉGIA POR MERCADO (BR §27.4)

| Mercado | Estratégia | Fonte imagens |
|---|---|---|
| Mercadona | API pública `tienda.mercadona.es` | CDN Mercadona ✅ |
| Continente | API semi-aberta (SFCC `/ocapi`) | `cdnd.continente.pt` |
| Pingo Doce | Scraping `pingodoce.pt` | CDN Pingo Doce |
| Lidl | Scraping `lidl.pt` | CDN Lidl |
| Auchan | Scraping `auchan.pt` | CDN Auchan |
| Intermarché | Scraping `intermarche.pt` | CDN Intermarché |

**Crítico:** 5 dos 6 mercados exibem actualmente fotos da Mercadona (BR §27.6). Essa cópia é ilegal e viola BR §27.2 — corrigir prioridade.

## BENCHMARK UBER / IFOOD / GLOVO

> **Glovo Catalog Intelligence** — scraping de menus de parceiros não-integrados. OCR para PDFs, ML para normalizar nomes.
>
> **iFood Menu Ingestion Service** — pipeline com Apache Airflow. DAGs por restaurante.
>
> **Uber Eats** — raramente faz scraping; prefere integração POS directa. Quando scraping, é pontual para criar menu inicial.
>
> **Bora equivalente:** BR §27 é mais leve — scraping batch semanal, sem ML nem OCR. Adequado para Guarda (6 mercados), não escalável a 100+ cidades sem investimento. Limite assumido.

---

## RESPONSABILIDADES

- ✅ Análise legal (ToS) antes de implementar scraper novo
- ✅ Estratégia por mercado (API vs scraping)
- ✅ Rate limit 1 req/s (BR §27.5)
- ✅ Backoff exponencial em 429/403
- ✅ Rotação de User-Agent quando necessário
- ✅ Imagens REAIS de cada mercado (BR §27.2)
- ✅ Log estruturado para retry domingo

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Scraper específico (estratégia, backoff, User-Agent) | **market-scraper** (eu) |
| Orquestração semanal cross-market | `products-updater` |
| Alertas de falha admin | `notifications-engineer` |
| Observação em produção | `monitoring-engineer` |
| Análise legal dos ToS | — (externa — advogado / Danilo) |

## NÃO PODE FAZER

- ❌ Criar edge functions nesta sessão
- ❌ Criar pg_cron nesta sessão
- ❌ Copiar imagens entre mercados (BR §27.2 proíbe)
- ❌ Bypass de ToS sem análise legal
- ❌ Ignorar 429/403 (IP ban permanente)
- ❌ Exceder 1 req/s por mercado
- ❌ Tocar em `pricing_service.dart` ou dispatch-engine

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §27
- ToS review obrigatório ANTES de qualquer scraper novo
- Fotos REAIS de cada mercado (BR §27.2)
- Rate limit 1 req/s (BR §27.5)
- Retry domingo em falhas (BR §27.5)
- Ordem canónica: `decision_engine` (review legal) → **market-scraper** → `products-updater` → `executor` (em sessão dedicada)
