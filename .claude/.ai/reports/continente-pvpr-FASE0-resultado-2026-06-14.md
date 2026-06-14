# Fase 0 — RESULTADO (Crawler PVPR Continente)

> **Data:** 2026-06-14 · **Veredicto: ✅ PASSOU** (critério ≥90% atingido) · **ZERO writes na BD**
> Read-only sobre continente.pt. Aguarda OK do Danilo para a corrida completa.

---

## 1. Veredicto

| Critério (Danilo) | Resultado | Decisão |
|---|---|---|
| `cont-<N>` = PID Continente? | **SIM — 92,0%** resolvem direto | **PID universal → name-matching DISPENSADO** |
| Gate 5 produtos bate PVPR? | **3/3 PASS** nos que existem online (4º = 404 real) | Regra de preço validada |
| continente.pt bloqueia? | **0 bloqueios** em 177 requests (150+27) | Método seguro a 4,5s/req |

---

## 2. Amostra aleatória (n=150, seed fixa)

```
OK (PID resolve c/ preço): 138/150 = 92,0%   [promo=57 · sem promo=81]
404=6 (4%) · redirect_home=6 (4%) · no_price=0 · ambíguo=0 · weird=0 · BLOCKED=0
```

- **41% (57/138) estavam EM PROMOÇÃO** → sem a regra PVPR, capturaríamos preços promocionais temporários.
- **0 ambíguos / 0 weird** → a regra "1 `PVP Recomendado` na página = produto principal" é robusta (o risco "tile vs principal" não se materializou).

### Divergência preço-correto vs BD atual (Glovo ÷ 1,15)
```
<=5%: 78 | 5-15%: 7 | 15-25%: 10 | 25-50%: 19 | >50%: 24
base MAIOR que BD: 73 (Bora a vender BARATO demais → perde margem)
base MENOR que BD: 65 (Bora a vender CARO demais)
```
**31% (43/138) divergem >25%.** Erros nos dois sentidos — confirma a observação do Danilo.

---

## 3. Gate de validação (PVPR, ignorando promoção)

| Produto | BD atual | Site venda | PVPR | Base obtida | Esperado | ✓ |
|---|---|---|---|---|---|---|
| Sanex Cuidado Experto Protector 600ml | 3,05 | 2,99 (promo) | 5,99 | **5,99** | 5,99 | ✅ |
| Sanex Zero% Pele Seca 600ml | 3,05 | 5,99 | — | **5,99** | 5,99 | ✅ |
| Vaseline Manteiga Karité 700ml | 5,09 | 2,99 (promo) | 4,99 | **4,99** | 4,99 | ✅ |
| Gresso UHT Magro s/Lactose 1L | 1,19 | — | — | 404 | 1,06 | ⚠️ 404 (descontinuado online) |

> O "Leite Magro Gresso 1L simples" (esperado 0,87) **não existe na BD** do Continente — só "6×1 lt" e "sem lactose".

---

## 4. Prova de impacto (top divergências reais da amostra)

| Δ% | BD (errado) | Real (PVPR/venda) | Produto |
|---:|---:|---:|---|
| +929% | 0,65 | **6,69** | Alho Seco Continente |
| +227% | 4,28 | 13,99 | Vinho Rovisco Pais Premium |
| +145% | 4,07 | 9,99 | Toalhitas Woolite 20un |
| +145% | 10,19 | 24,99 | Detergente Máquina Flores Silvestre |
| +144% | 7,81 | 19,09 | Azeite V.E. Oliveira da Serra |
| +96% | 29,16 | 57,19 | Box Fraldas Dodot T6+ |
| +102% | 1,06 | 2,14 | Gelatina Royal Frutos Bosque |

→ Dezenas de produtos a vender a **⅓–½ do preço real**. Correção urgente para a margem.

---

## 5. Tratamento dos 8% que falham (extrapolado: ~950 produtos)

404 (~475) + redirect_home (~475) = produtos ausentes/sem-stock no continente.pt online.
- **Decisão #5 (Danilo):** deixar `price` como está + `needs_review=true` + log. **NÃO** marcar `is_available=false`.
- Name-matching **não** ajuda aqui (produto sem página) e arrisca casar produto errado → **não usar**.

---

## 6. Projeção da corrida completa (11.884 produtos)

| Métrica | Estimativa |
|---|---|
| Atualizáveis (status ok) | **~10.933** (92%) |
| Em promoção → usa PVPR | ~4.480 (41%) |
| Divergência >25% (sinalizar no painel) | ~3.380 (31%) |
| Sem preço (404/redirect) → needs_review | ~950 (8%) |
| **Tempo (1 worker, 4,5s+jitter)** | **~19 h** (medido: 5,88 s/produto) |
| Bloqueios esperados | 0 |

---

## 7. Decisões do Danilo (confirmadas)

1. Re-crawl dos 934 SFCC → **SIM** (incluídos nos 11.884).
2. Auto-apply → **NÃO**, tudo pelo painel admin nesta 1ª corrida.
3. Limiar de flag de divergência → **25%**.
4. **1 worker** (~19h, sem risco de bloqueio).
5. Sem preço/404/ambíguo → `price` inalterado + `needs_review`.
6. Cron de Terça → só **depois** da 1ª corrida validada.

---

## 8. Próximos passos (pós-OK)

1. **Infra** ([continente_price_staging.sql](../sql/continente_price_staging.sql)): backup + `continente_price_staging` + kill switch → via `apply_migration`.
2. **Corrida completa** `continente_pvpr_crawl.py --all` (background ~19h, resume-safe) → JSON.
3. **Carregar** JSON → `continente_price_staging` (com `divergence_pct`, `needs_review`).
4. **Painel admin PT-BR** (revisão/filtros/aprovar/aplicar/auditoria/kill switch).
5. **Aplicar** staging→`products` (só linhas aprovadas) via RPC `continente_apply_price_staging`.
6. Depois: integrar cron de Terça (`weekly-market-prices`).

---

## 9. Artefactos (Fase 0)

- [continente_pvpr_crawl.py](../scripts/continente_pvpr_crawl.py) — crawler produção (amostra + corrida, resume)
- [continente_phase0_crawl.py](../scripts/continente_phase0_crawl.py) — gate + 23 amostra
- [continente_phase0_analyze.py](../scripts/continente_phase0_analyze.py) — decifrou estrutura de preço
- [continente_price_staging.sql](../sql/continente_price_staging.sql) — DDL (não aplicado)
- `tmp/phase0_sample150.json` — resultados detalhados da amostra
