# FASE 5 — AUTOMAÇÃO SEMANAL (RELATÓRIO 2026-04-18)

Executado: 2026-04-18
Orquestrador: `ceo-ai`
Status: ✅ **Fase 5 concluída — edge function + pg_cron activos**
Âmbito: Continente + Auchan (Pingo Doce, Lidl, Intermarché ficam para sessões dedicadas)

---

## 1. SUMÁRIO EXECUTIVO

| Item | Estado |
|---|---|
| Migração `product_update_runs` + `updated_at` | ✅ aplicada |
| Trigger `moddatetime` em `products` | ✅ activo |
| Edge function `update-products` (v2) | ✅ deployada |
| pg_cron job `update-products-continente` (seg 03:00 UTC) | ✅ activo |
| pg_cron job `update-products-auchan` (ter 03:00 UTC) | ✅ activo |
| Corrida manual Continente (3 páginas, teste) | ✅ 51 scraped / 2 inserted / 0 fail / 6.5s |
| Corrida manual Auchan (3 páginas, teste) | ✅ 144 scraped / 1 inserted / 0 fail / 3.5s |
| Zonas protegidas BR §25.3 | ✅ intactas |

---

## 2. SCHEMA CHANGES (migração `fase5_product_update_runs_and_updated_at`)

```sql
CREATE EXTENSION IF NOT EXISTS moddatetime;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TRIGGER trg_products_set_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE PROCEDURE moddatetime(updated_at);

CREATE TABLE public.product_update_runs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_at      timestamptz NOT NULL DEFAULT now(),
  market      text NOT NULL,
  source      text,
  scraped     integer NOT NULL DEFAULT 0,
  inserted    integer NOT NULL DEFAULT 0,
  updated     integer NOT NULL DEFAULT 0,
  failed      integer NOT NULL DEFAULT 0,
  duration_ms integer,
  status      text NOT NULL DEFAULT 'running',
  error       text
);

CREATE INDEX idx_product_update_runs_market_run_at
  ON public.product_update_runs (market, run_at DESC);

ALTER TABLE public.product_update_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY product_update_runs_service_all ON public.product_update_runs
  FOR ALL TO service_role USING (true) WITH CHECK (true);
```

---

## 3. EDGE FUNCTION `update-products` (v2)

**Path:** [bora_app/supabase/functions/update-products/index.ts](../../supabase/functions/update-products/index.ts)

**Modos suportados (`body.market`):**
| Valor | Pipeline | Notas |
|---|---|---|
| `mercadona` | API JSON `tienda.mercadona.es` (legado, preservado) | — |
| `continente` | **NOVO — SFCC best-sellers** | parser `data-product-tile-impression` |
| `auchan` | **NOVO — SFCC best-sellers** | parser `data-gtm` |
| `pingodoce` / `lidl` / `intermarche` | Cross-match com Mercadona (legado) | até chegar L1 dedicado |

**Parâmetros da corrida** (body JSON):
- `pages` (1-90, default 30) — páginas de 48 produtos a pescar
- `sleepMs` (≥1000, default 1000) — obedece BR §27.5 rate-limit
- `maxUpdates` (0-2000, default 500) — teto de UPDATEs por corrida (proteger timeout)

**Comportamento:**
1. Abre linha em `product_update_runs` (`status='running'`)
2. Scrape paginado com `sleepMs` entre páginas (BR §27.5)
3. Filtros: sem `/badges/`, só imagens do CDN do próprio mercado (`Sites-col-master-catalog` / `Sites-auchan-pt-master-catalog`), preço > 0
4. Separa novos (INSERT em chunks de 200) vs. existentes (UPDATE de `price/photo_url/name/category/brand_low`)
5. Fecha linha com `scraped/inserted/updated/failed/duration_ms/status`

**Deploy:** `mcp__supabase__deploy_edge_function` → id `fcc0e67b-…`, versão **2**, `verify_jwt=false` (chamado apenas por pg_cron interno).

---

## 4. AGENDAMENTO pg_cron (BR §27.1 — 1 mercado/dia, rotação)

```sql
-- Mon 03:00 UTC → Continente
SELECT cron.schedule('update-products-continente', '0 3 * * 1', $$
  SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"market":"continente","pages":60,"sleepMs":1000,"maxUpdates":500}'::jsonb,
    timeout_milliseconds := 150000
  );
$$);

-- Tue 03:00 UTC → Auchan
SELECT cron.schedule('update-products-auchan', '0 3 * * 2', $$
  SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"market":"auchan","pages":60,"sleepMs":1000,"maxUpdates":500}'::jsonb,
    timeout_milliseconds := 150000
  );
$$);
```

Jobs actuais (verificado):
| jobid | jobname | schedule | active |
|---|---|---|:---:|
| 20 | update-products-continente | `0 3 * * 1` | ✅ |
| 21 | update-products-auchan | `0 3 * * 2` | ✅ |

Próximas execuções automáticas:
- **Seg 2026-04-20 03:00 UTC** — Continente
- **Ter 2026-04-21 03:00 UTC** — Auchan

Estimativa por corrida real (60 páginas × 1s sleep + fetch): ≈ 90–120s, dentro do timeout de 150s.

---

## 5. TESTES MANUAIS (3 páginas cada)

| Mercado | scraped | inserted | updated | failed | duration_ms | status |
|---|---:|---:|---:|---:|---:|:---:|
| Continente | 51 | 2 | 0 | 0 | 6.521 | ✅ ok |
| Auchan | 144 | 1 | 0 | 0 | 3.550 | ✅ ok |

- Os 2 produtos novos do Continente e 1 do Auchan são PIDs que o Fase 4 não tinha capturado (rotação de best-sellers no site).
- `updated=0` porque o teste foi com `maxUpdates=0` (apenas validar INSERT path sem tocar existentes).

---

## 6. ESTADO FINAL `public.products`

| Mercado | Total | L1 | Com foto | Meta BR §27.2 ≥5.000 |
|---|---:|---:|---:|:---:|
| mercadona-guarda | 5.011 | 5.011 | 5.011 | ✅ |
| continente-guarda | **6.334** | 4.305 | 4.306 | ✅ |
| auchan-guarda | **6.333** | 3.330 | 3.335 | ✅ |
| pingodoce-guarda | 3.101 | — | — | ❌ (deferido) |
| lidl-guarda | 3.002 | — | — | ❌ (deferido) |
| intermarche-guarda | 3.004 | — | — | ❌ (deferido) |

3 / 6 mercados passam a meta. Os 3 deferidos serão tratados em sessões dedicadas (ver Fase 4 report, Opção A).

---

## 7. ZONAS PROTEGIDAS BR §25.3 — INTACTAS

- `lib/services/pricing_service.dart` — não tocado
- `lib/dispatch/driver_capacity_service.dart` — não tocado
- `lib/stores/order_store.dart::finalizePurchase` — não tocado
- Triggers `bora_tokens`, `trg_award_tokens_on_delivery` — não tocados
- Stripe, `dispatch-engine` Edge Function — não tocados
- Backup `products_backup_2026_04_18` — preservado

**Apenas tocado nesta Fase 5:**
- Schema: `products` ganhou coluna `updated_at` + trigger (não-destrutivo)
- Nova tabela: `product_update_runs` (observabilidade)
- Edge function `update-products` — versão **2** (legado Mercadona/cross-match preservado, adicionado SFCC path)
- 2 novas entradas no `cron.job`

---

## 8. ROLLBACK

### Desactivar agendamento (mantém edge function)
```sql
SELECT cron.unschedule('update-products-continente');
SELECT cron.unschedule('update-products-auchan');
```

### Rollback total Fase 5
```sql
SELECT cron.unschedule('update-products-continente');
SELECT cron.unschedule('update-products-auchan');
DROP TABLE IF EXISTS public.product_update_runs;
DROP TRIGGER IF EXISTS trg_products_set_updated_at ON public.products;
ALTER TABLE public.products DROP COLUMN IF EXISTS updated_at;
```

Edge function `update-products` pode ser revertida para versão 1 no dashboard Supabase → Edge Functions.

---

## 9. OBSERVABILIDADE

Monitorizar corridas:
```sql
SELECT run_at, market, scraped, inserted, updated, failed, duration_ms, status, error
FROM public.product_update_runs
ORDER BY run_at DESC
LIMIT 20;
```

Alerta sugerido (fora do âmbito desta fase): criar view `v_failed_runs` + notify Discord se `failed > 50` ou `status='error'` durante 2 dias consecutivos.

---

## 10. PRÓXIMAS SESSÕES (FORA DO ÂMBITO)

- **Sessão L1 Playwright** — Pingo Doce + Lidl + Intermarché via navegador real (anti-bot + SPA)
- **Fase 4b** — cascata L1→L4 aos 14.064 produtos `needs_photo=true` via skill `market-harvester`
- **Orçamento L4** — tabela `product_image_budget` + cap €50/mês (BR §27.2)

---

*Gerado automaticamente pelo `ceo-ai`. Autonomia multi-fase respeitada: pilot → Fase 4 → Fase 5 sem paragens intermédias. Zonas protegidas BR §25.3 intactas.*
