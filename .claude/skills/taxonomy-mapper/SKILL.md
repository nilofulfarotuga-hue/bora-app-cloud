---
name: taxonomy-mapper
description: >
  Classifica produtos de supermercado em 18 secções canónicas Bora
  (Padaria, Frutas & Legumes, Talho, Peixaria, Laticínios & Ovos, Congelados,
  Mercearia, Bebidas, Bebé, Animais, Higiene Pessoal, Higiene do Lar,
  Saúde & Bem-Estar, Bio & Saudável, Fitness & Proteínas, Pronto a Comer,
  Festa & Ocasiões, Outros). Use esta skill sempre que for preciso normalizar
  categorias vindas de Continente, Lidl, Auchan, Pingo Doce, Intermarché,
  Mercadona ou outros retalhistas, mapear 784+ `category_root` históricas
  para secções unificadas, ou popular/actualizar `products.taxonomy_section`.
  Triggers: "mapear produtos para taxonomia", "classificar produtos de
  supermercado", "aplicar 18 secções canónicas", "normalizar categorias do
  Continente/Lidl/Auchan/Pingo Doce/Mercadona/Intermarché".
---

# Taxonomy Mapper — Bora App

## Propósito

Normalizar a árvore de categorias dos supermercados em **18 secções canónicas Bora**, guardadas em `public.products.taxonomy_section`. Os nomes originais (`products.name`, `products.category`, `products.category_root`, `products.search_normalized`) permanecem intocados — a taxonomia é uma camada aditiva.

## Quando usar

- População inicial de `taxonomy_section` sobre os ~43K produtos existentes.
- Classificação incremental de produtos novos após scraping.
- Reclassificação de produtos com `needs_review = true` depois de revisão manual.
- Audit: contar distribuição por secção para detectar enviesamentos.

## Quando NÃO usar

- Não alterar `products.name`, `products.category`, `products.category_root` ou `products.search_normalized` — são campos fonte, preservados.
- Não tocar em zonas protegidas (`pricing_service`, `dispatch-engine`, Stripe, triggers `bora_tokens`, `driver_capacity_service`, `finalizePurchase`, `auth_store`).
- Não renomear secções canónicas sem aprovação explícita do Danilo (são 18 fixas).

## Estrutura

```
taxonomy-mapper/
├── SKILL.md                        # este ficheiro
├── references/
│   └── bora_taxonomy.md           # 18 secções + regras de keyword matching
└── scripts/
    ├── classify.py                # lógica de classificação (regras + LLM fallback)
    └── apply_migration.sql        # template UPDATE em batch
```

## As 18 Secções Canónicas

Lista completa e regras detalhadas em `references/bora_taxonomy.md`. Resumo:

1. Padaria & Pastelaria
2. Frutas & Legumes
3. Talho
4. Peixaria
5. Laticínios & Ovos
6. Congelados
7. Mercearia
8. Bebidas
9. Bebé
10. Animais
11. Higiene Pessoal
12. Higiene do Lar
13. Saúde & Bem-Estar
14. Bio & Saudável
15. Fitness & Proteínas
16. Pronto a Comer
17. Festa & Ocasiões
18. Outros

## Algoritmo de Classificação

Por ordem de **precedência** (primeira a ganhar vence):

1. **Keyword matching em `products.name`** — mais específico, prioritário. Regras em `references/bora_taxonomy.md` (dicionário PT + variantes).
2. **Mapeamento por `category_root`** — 784 raízes existentes mapeadas para secções (ver tabela em `references/bora_taxonomy.md`).
3. **LLM fallback** — para produtos que falharam 1 e 2. Modelo: `claude-haiku-4-5` (velocidade + custo baixo). Batches de 100 produtos por prompt.

## Score de Confiança

Cada produto recebe `taxonomy_confidence` entre 0.00 e 1.00:

| Método         | Confidence base |
|----------------|-----------------|
| Keyword match forte (≥2 keywords) | 0.95 |
| Keyword match fraco (1 keyword)   | 0.80 |
| Mapeamento por `category_root`     | 0.75 |
| LLM com resposta confiante        | 0.70 |
| LLM com resposta ambígua          | 0.45 |
| Fallback para "Outros"            | 0.20 |

Regras de aplicação:
- `confidence > 0.85` → aplicar directamente, `needs_review = false`
- `0.50 ≤ confidence ≤ 0.85` → aplicar, `needs_review = true` (revisão manual sugerida)
- `confidence < 0.50` → `taxonomy_section = 'Outros'`, `needs_review = true`

## Idempotência

Correr a skill 2× não muda nada em produtos já classificados com `confidence > 0.85`. A skill só escreve quando:
- Produto não tem `taxonomy_section` ainda, OU
- Produto tem `needs_review = true` E confidence novo > confidence antigo, OU
- Flag `--force` foi passada.

## Schema esperado

A skill assume que `public.products` tem as colunas:

```sql
taxonomy_section      TEXT                    -- uma das 18 secções
taxonomy_confidence   NUMERIC(3,2) DEFAULT 0.00
needs_review          BOOLEAN       DEFAULT false
```

Mais o índice `idx_products_taxonomy_section`.

A migration `20260419200000_products_taxonomy_section.sql` cria estas colunas. Se não existirem, a skill aborta com erro claro.

## Circuit Breakers

- Se `COUNT(*) WHERE taxonomy_section = 'Outros'` > 15% do total → **PARAR** e reportar. Indica falha na classificação, não categoria dominante.
- Se batch demorar > 60s → **PARAR** e reportar (LLM rate limit ou timeout).
- Cada batch é transaccional (`BEGIN ... COMMIT`) → rollback fácil por ronda.

## Como Executar

### 1. Aplicar migration (uma vez)
```bash
supabase migration up  # ou via MCP apply_migration
```

### 2. Correr classificação em batches
```bash
python scripts/classify.py --batch-size 1000 --start 0 --end 1000
python scripts/classify.py --batch-size 1000 --start 1000 --end 5000
# ... até cobrir todos os produtos
```

### 3. Validação
```sql
SELECT taxonomy_section, COUNT(*)
FROM public.products
GROUP BY taxonomy_section
ORDER BY COUNT(*) DESC;
```

### 4. Revisão manual
```sql
SELECT id, name, category_root, taxonomy_section, taxonomy_confidence
FROM public.products
WHERE needs_review = true
ORDER BY taxonomy_confidence ASC
LIMIT 20;
```

## Saídas da Skill

- UPDATE em `public.products.taxonomy_section`, `.taxonomy_confidence`, `.needs_review`.
- Relatório em `.claude/.ai/reports/<date>_campaign_<n>of<m>_report.md` com distribuição e TOP-N produtos duvidosos.

## O que esta Skill NÃO faz

- NÃO apaga produtos.
- NÃO renomeia colunas existentes.
- NÃO classifica produtos de restaurante (apenas `is_partner = true` com `category IN ('supermarket', 'store', 'pharmacy')` ou produtos scraped).
- NÃO faz deploy de nada para além do UPDATE SQL.
