# Campanha 4/5 — Paragem B (Projecção de Limpeza)

**Data:** 2026-04-19
**Backup:** `products_cleanup_backup_20260419` criado — 43 121 rows (= products total)
**Coluna adicionada:** `products.name_original TEXT NULL` (para preservar ES antes da tradução)
**Writes aplicados à coluna is_available/needs_review/name: 0** (só DDL de setup)

---

## Heurística "tem marca"

Dada a descoberta de que Mercadona tem 100% `brand_low/mid/premium = NULL` apesar de
marcas visíveis no nome ("Hacendado", "Bosque Verde", "Deliplus"), adoptei heurística
com dois sinais (OR):

1. `brand_low IS NOT NULL OR brand_mid IS NOT NULL OR brand_premium IS NOT NULL`
2. `name ~ '[A-ZÀ-Þ][a-zà-ÿ]{2,}'` (palavra capitalizada ≥3 letras — proxy para marca/nome próprio)

**Validação Mercadona:** 5 005 / 5 011 têm palavra capitalizada; apenas 6 sem sinal
de marca algum. Heurística sobrevive ao caso mais problemático.

---

## 📊 Projecção de soft-delete por mercado

| Mercado | Total | Hide | Keep | % Hide | Sem img | Sem marca | Preço inválido | Preço €0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Auchan** | 6 333 | **3 019** | 3 314 | 47.67% | 2 998 | 4 | 20 | 0 |
| **Continente** | 6 334 | **2 031** | 4 303 | 32.07% | 2 028 | 0 | 3 | 0 |
| **Pingo Doce** | 9 542 | **3 037** | 6 505 | 31.83% | 3 037 | 3 | 0 | 0 |
| **Intermarché** | 6 504 | **152** | 6 352 | 2.34% | 2 999 | 3 | 0 | 3 500 |
| **Lidl** | 9 085 | **119** | 8 966 | 1.31% | 3 002 | 0 | 0 | 6 083 |
| **Mercadona** | 5 011 | **41** | 4 970 | 0.82% | 0 | 6 | 33 | 2 |
| **TOTAL** | 42 809 | **8 399** | 34 410 | 19.6% | 14 064 | 16 | 56 | 9 585 |

**Lógica aplicada por mercado:**
- **Auchan/Continente/Pingo Doce/Mercadona:** hide se (sem imagem) OR (sem marca) OR (preço inválido) OR (preço €0)
- **Lidl/Intermarché:** hide SÓ se (sem imagem) AND (sem marca OR <3 palavras) — conforme regra do Danilo para preservar catálogo visível

**Tradução Mercadona:** ~1 650 produtos com keywords ES (dicionário expandido para cobrir "fresco/congelado/bolsa/lata" etc — inclui preserativas de tamanho/estado)

---

## ✅ Circuit breakers — todos dentro dos limites

| Limite | Pior caso | Estado |
|---|---|---|
| >50% afectado por mercado | Auchan 47.67% | ✅ OK (perto do limite) |
| <100 produtos activos após limpeza | Mercadona 4 970 (menor) | ✅ OK |
| Produtos totais activos (6 mercados) | **34 410** | ✅ catálogo viável |

Auchan está a 2.33 pontos percentuais do circuit breaker — peço atenção especial nesse batch.

---

## 🔴 Tarefa URGENTE registada

**RE-SCRAPING obrigatório `Lidl.pt` e `Intermarche.pt` antes do lançamento.**

O scraping actual trouxe `Lidl.de` (alemão, "Saskia", "Milbona", "Bratwurst") e
`Intermarche.fr` (francês, "Crème Caramel", "Reblochon"). Preços €0 em 9 583 produtos
são consequência desse bug — não dados corruptos para limpar.

**Impacto pós-limpeza:**
- Lidl: 8 966 produtos "keep" mas com **67% sem preço** → clientes veem catálogo visível mas compram quase nada
- Intermarché: 6 352 "keep" com **54% sem preço** → mesmo problema

**Mitigação temporária até reingestão:** manter visíveis conforme decisão Danilo (melhor que zero produtos). Post-lançamento tem de haver re-scrape PT.

---

## 📋 Ordem de execução proposta (Paragens C-G)

| Paragem | Mercado | Operações | Volume | Tempo estimado |
|---|---|---|---:|---|
| **C** | Mercadona | Preservar `name_original` + traduzir 1 650 via dicionário + soft-delete 41 | ~1 691 writes | ~3-5 min |
| **D** | Continente | Soft-delete 2 031 (batches de 1000) | 2 031 writes | ~1 min |
| **E** | Auchan | Soft-delete 3 019 (batches de 1000, **atenção 47%**) | 3 019 writes | ~2 min |
| **F** | Pingo Doce | Soft-delete 3 037 + remover 2 electrónicos (aspirador, desumidificador) | 3 039 writes | ~2 min |
| **G** | Lidl + Intermarché | Soft-delete 119 + 152 (piores apenas) | 271 writes | ~30s |
| Final | Relatório | Com tarefa URGENTE re-scraping PT | 0 writes | — |

**Total writes previstos: 10 051** (soft-delete) + **1 650** (tradução) + **5 011** (preservação name_original Mercadona) = **~16 712 UPDATEs em batches de 1 000.**

---

## ⚠️ 2 Cautelas finais antes de aprovar

1. **Heurística de marca é proxy.** Para um catálogo definitivo, uma 2ª passagem com
   allowlist real de marcas (extraída de `brand_low/mid/premium` + expandida manualmente)
   dará menos falsos positivos. Esta campanha faz o 80/20 — relatório final vai listar
   amostras do `hide` para revisão.

2. **Auchan a 47.67%** — se ao correr o batch real subir acima dos 50% (por causa de
   algum arredondamento ou race), o script deve abortar. Mantém circuit breaker activo.

---

## 🛑 PARAGEM B — Aguardar aprovação Danilo

**Pergunto explicitamente:**
- Números acima estão aceitáveis?
- Arrancamos por **Paragem C (Mercadona)** com esta estratégia?
- Alguma alteração à heurística de "sem marca"?

**Não vou tocar em nenhuma row de `products` sem tua confirmação.**
