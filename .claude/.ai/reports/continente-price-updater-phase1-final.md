# Continente Price Updater — Fase 1 FINAL (2.844 produtos)

**Data:** 2026-04-22
**Fonte:** `products WHERE source='glovo-continente-guarda-2026-04-21' AND price IS NULL`
**Universo:** 2.844 produtos (100 % processado)
**Método:** M3 — `continente.pt/.../Product-Show?pid=<PID>` (PID extraído de `id` `glv-<N>`)
**Rate:** 4,5 s ± 1,0 s jitter · sleep 30 s extra em net_error
**Tempo total wall-clock:** ~3 h 30 min (em 4 batches: 1.000 + 1.272 + 222 + 350)
**ZERO writes na BD em qualquer fase.**

---

## 1. Resultado global

| Status | Qtd | % | Significado | Acção sugerida (Fase 2) |
|---|---:|---:|---|---|
| ✅ **ok** | **2.569** | **90,3 %** | Preço extraído com sucesso | `UPDATE price = <X>` |
| 404 | 154 | 5,4 % | PID não existe em continente.pt | `is_available=false, needs_review=true` |
| redirect_home | 113 | 4,0 % | Redirecciona para homepage (sem stock / sazonal) | `is_available=false`, retry mensal |
| net_error | 6 | 0,2 % | Falha de rede transitória | retry isolado (Fase 1.5) |
| no_price_in_html | 2 | 0,1 % | HTML carregou mas sem padrão de preço | inspecção manual |
| **BLOCKED (429/403)** | **0** | **0 %** | **Sem rate-limit, sem CAPTCHA** | — |

**Coverage de preço efectivo: 90,3 % (2.569 produtos prontos para UPDATE).**

---

## 2. Estatísticas de preço (sobre 2.569 OK)

| Métrica | Valor |
|---|---|
| Mínimo | **0,29 €** (Sal Fino Continente) |
| Mediana | **2,99 €** |
| Média | 4,99 € |
| p90 | 10,99 € |
| p99 | 31,00 € |
| Máximo | **110,00 €** (Glenfiddich 18 anos) |

### Distribuição por bucket

| Faixa preço (€) | Produtos | % |
|---|---:|---:|
| 0 – 1 | 204 | 7,9 % |
| 1 – 2 | 642 | 25,0 % |
| 2 – 5 | 1.061 | 41,3 % |
| 5 – 10 | 388 | 15,1 % |
| 10 – 20 | 197 | 7,7 % |
| 20 – 50 | 71 | 2,8 % |
| 50 – 100 | 5 | 0,2 % |
| 100 – 999 | 1 | 0,0 % |

**Insight:** 74 % do catálogo está entre 1 € e 10 €, distribuição típica de supermercado em Portugal.

---

## 3. Top 10 mais caros

| Preço € | PID | Produto |
|---:|---|---|
| **110,00** | 7646487 | Glenfiddich Whisky 18 anos Single Malt |
| 65,00 | 5425886 | Esporão Private Selection BIO Alentejo Tinto |
| 60,99 | 2426358 | Old Parr Whisky Scotch 12 anos |
| 59,99 | 8598933 | Coffret Revitalift Laser L'Oréal Paris |
| 59,99 | 8599277 | Coffret Duo Rotina Rejuvenescedora L'Oréal Paris |
| 57,99 | 5365794 | Monkey 47 Gin |
| 49,04 | 8575345 | Recarga Lâminas Gillette Fusion |
| 46,99 | 2051281 | Glenfiddich Whisky 12 anos Single Malt |
| 45,00 | 6928112 | Herdade do Sobroso Grande Reserva Tinto |
| 44,99 | 7647313 | Recarga Lâminas Gillette Labs |

## 4. Top 10 mais baratos

| Preço € | PID | Produto |
|---:|---|---|
| **0,29** | 5621157 | Sal Fino Continente |
| 0,32 | 5679836 | Infusão Hortelã Saquetas Continente |
| 0,35 | 2373254 | Água sem Gás Vitalis |
| 0,35 | 7742735 | Conjunto Garfo+Faca madeira |
| 0,39 | 2119809 | Água sem Gás Luso |
| 0,39 | 5679840 | Chá Preto Saquetas Continente |
| 0,40 | 7610967 | Conjunto Talheres madeira Kasa |
| 0,45 | 5723928 | Sal Marinho Iodado Continente |
| 0,49 | 7450723 | Refrigerante Cola Zero Continente |
| 0,49 | 7805597 | Bebida Energética Guapa |

---

## 5. Falhas (275 total)

### 5a. 404 — descontinuados em continente.pt (154)

PIDs que o Glovo manteve em catálogo mas o Continente já removeu. Padrão: clusters sequenciais (ex: `2050121`, `2050124`, `2050284`, `2050288`, …). Marcar `is_available=false, needs_review=true`.

### 5b. redirect_home — sem stock / sazonal (113)

URL `Product-Show?pid=X` redirecciona para `continente.pt/`. Causas possíveis: produto sazonal (ex: Carvão Vegetal — verão), sem stock momentâneo, ou PID em transição. Marcar `is_available=false`, agendar retry mensal.

### 5c. no_price_in_html (2)

| PID | Final URL | Diagnóstico |
|---|---|---|
| 2005798 | `/mercearia/acucar-e-sobremesas/acucar-e-adocante/` | Redirect para categoria, não produto |
| 2203334 | `/bebidas-e-garrafeira/agua/agua-sem-gas/luso/` | Redirect para listagem da marca |

Tratar como `is_available=false`.

### 5d. net_error — retry necessário (6)

PIDs onde o socket falhou. Lista guardada em `.claude/.ai/tmp/phase1_failed_pids.txt`. Sugestão: Fase 1.5 só com estes 6 + sleep 60 s entre cada para garantir.

---

## 6. Performance & rate-limit

| Métrica | Valor |
|---|---|
| Fetch médio | 1,52 s |
| Fetch p99 | 5,09 s |
| Fetches > 5 s | 30 |
| Sleep médio entre requests | 4,5 s ± 1 s |
| **Bloqueios (429/403)** | **0** |

**continente.pt aceita 4,5 s ± jitter sem reagir.** Método M3 reutilizável para outros mercados.

---

## 7. Fase 2 — Plano de UPDATE (a aguardar OK)

### 7.1 Backup obrigatório

```sql
CREATE TABLE products_backup_glovo_continente_guarda_20260422
AS SELECT * FROM products
WHERE source='glovo-continente-guarda-2026-04-21';
```

### 7.2 SQL UPDATE (estratégia)

**Opção A — `unnest` único statement:**
```sql
UPDATE products SET
  price = v.new_price,
  updated_at = now(),
  source = 'continente_guarda_pid_lookup_2026-04-22'
FROM unnest(
  ARRAY['glv-2003965', 'glv-2004442', ...],
  ARRAY[1.23, 0.99, ...]::numeric[]
) AS v(id, new_price)
WHERE products.id = v.id;
```

**Opção B — chunks de 500** (mais legível, fácil de debug)

### 7.3 Validações antes de aplicar

- Diff de preço para PIDs em ambos `glovo-continente-guarda-2026-04-21` e `continente_guarda` (18 overlap, conforme Fase 0)
- Sanity > 200 € → flag (só Glenfiddich 18 anos = 110 €, OK)
- Sanity < 0,20 € → flag (mín actual 0,29 €, OK)

---

## 8. Ficheiros gerados

| Ficheiro | Conteúdo |
|---|---|
| `.claude/.ai/scripts/phase1_full.py` | Scraper paginated com resume + checkpoint |
| `.claude/.ai/scripts/phase1_summarize.py` | Aggregator stats sem flooding context |
| `.claude/.ai/tmp/phase1_pids_2026-04-21.txt` | 2.844 PIDs em ordem |
| `.claude/.ai/tmp/phase1_prices_2026-04-21.json` | 2.844 resultados (resume-safe) |
| `.claude/.ai/tmp/phase1_failed_pids.txt` | 275 PIDs sem preço |
| `.claude/.ai/reports/continente-price-updater-phase1-final.md` | Este relatório |

---

## 🛑 STOP — aguardar aprovação Danilo para Fase 2

**Decisões a tomar:**

1. **Backup BD** — confirmar criação de `products_backup_glovo_continente_guarda_20260422`?
2. **Estratégia UPDATE** — opção A (unnest) ou B (chunks)?
3. **269 sem preço** — `is_available=false` agora ou manter NULL?
4. **Fase 1.5 (6 net_errors)** — antes ou em paralelo da Fase 2?
5. **18 overlaps com `continente_guarda`** — qual fica como source-of-truth?

Responde para arrancar Fase 2.
