# Regras Globais — Market Data Sync

Regras de execução, qualidade e taxonomia. Aplicam-se a TODAS as lojas.

---

## 1. Rate Limiting

| Operação | Delay |
|----------|-------|
| Pedido HTTP a Glovo / Uber Eats | 4,5s ± 1s jitter |
| Pedido HTTP a site oficial (preço) | 4,5s ± 1s jitter |
| Lookup BD (SELECT) | sem delay |
| UPDATE / INSERT BD | em batches de 50, com transacção |

**Jitter** = `Math.random() * 1000` ms adicionais (evita padrão detectável).

**Backoff exponencial** em caso de HTTP 429 / 503:
- Retry 1: aguardar 30s
- Retry 2: aguardar 60s
- Retry 3: aguardar 120s
- Após 3 falhas: parar e gerar relatório.

---

## 2. Name Guard (anti-duplicados agressivos)

Quando se procura match na BD por nome normalizado:

```
norm(name) = lowercase(strip_accents(trim(name)))
```

Se houver **múltiplos candidatos** ou nenhum exacto, usar **Levenshtein normalizado**:

```
score = levenshtein(a, b) / max(len(a), len(b))
```

Regras:
- `score == 0` → match exacto, fazer UPDATE.
- `0 < score ≤ 0.3` → match aceitável, log mas pedir aprovação.
- `score > 0.3` → tratar como **produto novo** (INSERT).

**Exemplo**:
- "Leite Mimosa Magro 1L" vs "leite mimosa magro 1l" → score 0 → UPDATE.
- "Leite Mimosa Magro 1L" vs "Leite Mimosa Meio Gordo 1L" → score ≈ 0.18 → pedir aprovação.
- "Leite Mimosa 1L" vs "Iogurte Mimosa 4x125g" → score > 0.3 → INSERT.

---

## 3. Checkpoint

A cada **200 produtos** processados (extracção ou pricing), gravar:

```
tmp/checkpoint_<store>_<YYYYMMDD>.json
{
  "phase": "extract" | "price" | "apply",
  "last_index": 200,
  "last_product_name": "Leite Mimosa 1L",
  "timestamp": "2026-04-21T10:30:00Z"
}
```

Em caso de queda do script, retomar do `last_index + 1` na próxima execução.

---

## 4. Categorias Canónicas (22 secções)

Toda categoria de origem (Glovo, Uber, site oficial) DEVE ser mapeada para uma destas 22 secções canónicas Bora. Mesma taxonomia usada por `category-mapper-v2`.

| # | Secção Canónica | Inclui |
|---|------------------|--------|
| 1 | Congelados | Gelados, comida congelada, vegetais congelados |
| 2 | Bebé | Fraldas, leite infantil, papas, brinquedos bebé |
| 3 | Animais | Comida cão/gato, areia, brinquedos animais |
| 4 | Vinhos | Vinho tinto, branco, rosé, espumantes, sangrias |
| 5 | Charcutaria | Fiambre, presunto, chouriço, salsicha, queijos curados |
| 6 | Fitness | Proteína, barras, suplementos, bebidas isotónicas |
| 7 | Conservas | Atum, sardinha, vegetais em lata, azeitonas |
| 8 | Snacks | Batatas fritas, frutos secos, chocolates, bolachas |
| 9 | Pequenos-Almoços | Cereais, granola, tostas, marmelada, mel |
| 10 | Padaria | Pão, croissants, bolos, broa, baguete |
| 11 | Peixaria | Peixe fresco, marisco fresco (não congelado) |
| 12 | Talho | Carne fresca de vaca, porco, frango, peru |
| 13 | Laticínios | Leite, iogurtes, manteiga, queijo fresco, ovos |
| 14 | Frutas & Legumes | Frutas e vegetais frescos, ervas aromáticas |
| 15 | Pronto a Comer | Refeições prontas, sandes, sushi, pizzas frescas |
| 16 | Mercearia | Massa, arroz, farinha, açúcar, óleos, molhos |
| 17 | Bebidas | Refrigerantes, sumos, águas, cervejas (não vinho) |
| 18 | Saúde | Medicamentos OTC, vitaminas, primeiros socorros |
| 19 | Higiene Pessoal | Champô, gel duche, escovas dentes, desodorizante |
| 20 | Higiene do Lar | Detergentes, lixívia, papel higiénico, esfregões |
| 21 | Festa | Velas, balões, decoração, descartáveis festa |
| 22 | Bio | Produtos certificados orgânicos / bio |

### Regras de Precedência

Quando um produto pode encaixar em mais que uma secção, usar esta ordem (mais específico → mais genérico):

```
Congelados > Bebé > Animais > Vinhos > Charcutaria > Fitness >
Conservas > Snacks > Pequenos-Almoços > Padaria > Peixaria >
Talho > Laticínios > Frutas & Legumes > Pronto a Comer >
Mercearia > Bebidas > Saúde > Higiene Pessoal >
Higiene do Lar > Festa > Bio
```

**Exemplos**:
- "Gelado Bio" → Congelados (Congelados > Bio)
- "Iogurte Bio Bebé" → Bebé (Bebé > Bio)
- "Vinho Tinto Bio" → Vinhos (Vinhos > Bio)
- "Pão Bio" → Padaria (Padaria > Bio)

---

## 5. Qualidade Mínima de Dados

Antes de fazer INSERT, garantir:

- [x] `name` não vazio, ≥ 3 caracteres.
- [x] `name` não contém só números/símbolos.
- [x] `image_url` é HTTPS válido (ou `NULL` se não disponível).
- [x] `taxonomy_section` é uma das 22 secções canónicas.
- [x] `restaurant_id` existe na BD.
- [x] `price_cents` é integer ≥ 0 (ou `NULL` se `is_available=false`).
- [x] `price_cents` ≤ 50000 (€500 máximo — alertar se acima).

Produtos que falham qualquer destes critérios → log para `tmp/rejected_<store>_<YYYYMMDD>.json` e não fazer INSERT.

---

## 6. Logging

Cada execução gera 4 ficheiros em `tmp/`:
- `extracted_<store>_<date>.json` — todos os produtos extraídos da fonte
- `priced_<store>_<date>.json` — produtos com preço resolvido
- `rejected_<store>_<date>.json` — produtos rejeitados (não passam qualidade)
- `checkpoint_<store>_<date>.json` — estado para retoma

E 1 relatório final em `.claude/.ai/reports/`:
- `market-data-sync-<store>-<date>.md` — sumário, diff, decisões pendentes

---

## 7. Aprovação Manual (MODO PROTECÇÃO TOTAL)

Pontos onde a skill **DEVE PARAR** e aguardar aprovação explícita do Danilo:

1. Antes da Fase 1 (extracção) — confirmar loja + restaurant_id.
2. Antes da Fase 5 (apply BD) — após relatório com diff.
3. Sempre que > 10% dos produtos tenham `score` Levenshtein entre 0 e 0.3 (matches duvidosos).
4. Sempre que diff médio de preços > 20% (possível erro de extracção).
5. Sempre que > 50 produtos novos forem detectados (possível desalinhamento de loja).
