# BLOCO 4 — Cron cleanup (Sessão 7-CRON · 2026-05-08)

**Data**: 2026-05-08
**Sessão**: 7-CRON
**Modo**: MCP directo via Claude.ai (`cron.unschedule`)
**Migration**: nenhuma (operação `cron.unschedule` directa,
não-schema).

---

## Objectivo

Remover cron jobs broken (auth Bearer null → 401) que estavam a
poluir os logs de cron e a falhar silenciosamente.

---

## §4.1 Jobs unscheduled (7)

Todos estes jobs falhavam com **401 Unauthorized** porque o
header `Authorization: Bearer ${SECRET}` era resolvido para
`Bearer null` (variável de ambiente em falta no contexto de cron).

| Job | Razão |
|---|---|
| `update-mercadona` | scraper legado (substituído) |
| `update-continente` | scraper legado (substituído por `update-products-continente`) |
| `update-pingodoce` | scraper que nunca arrancou |
| `update-lidl` | scraper que nunca arrancou |
| `update-auchan` | scraper legado (substituído por `update-products-auchan`) |
| `update-intermarche` | scraper que nunca arrancou |
| `update-restaurants` | scraper legado |

### SQL aplicado (template)

```sql
SELECT cron.unschedule('update-mercadona');
SELECT cron.unschedule('update-continente');
SELECT cron.unschedule('update-pingodoce');
SELECT cron.unschedule('update-lidl');
SELECT cron.unschedule('update-auchan');
SELECT cron.unschedule('update-intermarche');
SELECT cron.unschedule('update-restaurants');
```

### Impacto

ZERO. Todos eram broken — `cron.job_run_details` mostrava 401
em 100% das execuções nas últimas semanas.

---

## §4.2 Jobs preservados (11)

Lista canónica dos jobs operacionais (não tocados):

| jobid | jobname | Schedule | Função |
|---|---|---|---|
| (varia) | `update-products-continente` | `0 3 * * *` | Scraper Continente |
| (varia) | `update-products-auchan` | `0 4 * * *` | Scraper Auchan |
| (varia) | `dispatch-engine-tick` | `* * * * *` | Dispatch loop minuto-a-minuto |
| (varia) | `dispatch-ttl-auto-reject` | `*/5 * * * *` | TTL auto-reject |
| (varia) | `wallet-charge-extra-drain` | `*/15 * * * *` | Drenagem `pending_charges` |
| (varia) | `tokens-expire-cleanup` | `0 1 * * *` | Expiry tokens 60d |
| (varia) | `analytics-aggregate` | `0 2 * * *` | Agregados diários |
| (varia) | `pg-net-vault-test` | `0 0 * * 0` | Health check pg_net |
| (varia) | (3 outros operacionais) | — | — |

Total preservados: **11/11 activos correctos**.

> **Nota**: jobids variam por execução (sequência interna do
> `pg_cron`). Para obter snapshot live:
> ```sql
> SELECT jobid, jobname, schedule, active
> FROM cron.job
> ORDER BY jobname;
> ```

---

## Validação MCP (CHECK 3)

```sql
SELECT count(*) AS active_jobs
FROM cron.job
WHERE active = true;
-- Resultado: 11 ✅
```

---

## Rollback info

Caso algum dos 7 jobs unscheduled fosse necessário (não é o caso
porque todos estavam broken), reagendar via:

```sql
SELECT cron.schedule(
  'update-mercadona',
  '0 5 * * *',
  $$ SELECT net.http_post(
       url := '<edge-fn-url>',
       headers := '{"Authorization": "Bearer ' ||
                  current_setting('vault.secret_token') || '"}'
     )
  $$
);
```

(usando vault para o token, não env var em falta).

---

## Resumo BLOCO 4

| Métrica | Valor |
|---|---|
| Jobs removidos | 7 |
| Jobs preservados | 11 |
| Migrations | 0 |
| Impacto | Zero (todos broken) |

**Estado final BLOCO 4**: cron limpo, logs deixam de mostrar 401
spam dos jobs broken. ✅
