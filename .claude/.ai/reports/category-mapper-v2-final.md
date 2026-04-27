# category-mapper-v2 — Relatório Final

**Campanha:** Reclassificação global em 22 categorias canónicas
**Data:** 2026-04-20
**Runtime:** JavaScript (sandbox ctx_execute) + Supabase RPC
**Backup:** `products.taxonomy_section_backup` (coluna original preservada)

---

## Resumo executivo

| Mercado | Total | Mudam | % | needs_review | em Outros |
|---|---:|---:|---:|---:|---:|
| **Pingo Doce** | 6 500 | 3 610 | 55.5% | 1 616 | 906 |
| **Continente** | 6 473 | 2 917 | 45.1% | 2 103 | 1 351 |
| **Auchan**     | 3 330 | 1 681 | 50.5% | 1 113 | 362 |
| **Mercadona**  | 3 009 | 1 556 | 51.7% | 1 252 | 697 |
| **Lidl+Interm.** |   697 |   395 | 56.7% |   335 |  67 |
| **TOTAL**      | **20 009** | **10 159** | **50.8%** | **6 419** | **3 383** |

- **Circuit breaker (60%):** nunca disparou ✅
- **Todas as 5 fases aplicadas** com sucesso, 100% dos batches concluídos
- **Backup intacto** — rollback possível via `UPDATE products SET taxonomy_section = taxonomy_section_backup WHERE …`

---

## Distribuição por categoria (todos os mercados)

| Categoria | Total | % |
|---|---:|---:|
| Outros | 3 383 | 16.9% |
| Charcutaria & Queijos ⭐ | 1 702 | 8.5% |
| Frutas & Legumes | 1 574 | 7.9% |
| Snacks ⭐ | 1 321 | 6.6% |
| Congelados | 1 296 | 6.5% |
| Higiene Pessoal | 1 218 | 6.1% |
| Bebidas | 1 213 | 6.1% |
| Animais | 1 198 | 6.0% |
| Mercearia | 1 045 | 5.2% |
| Talho | 843 | 4.2% |
| Peixaria | 778 | 3.9% |
| Vinhos & Espirituosas ⭐ | 767 | 3.8% |
| Bebé | 681 | 3.4% |
| Padaria & Pastelaria | 618 | 3.1% |
| Higiene do Lar | 618 | 3.1% |
| Pequenos-Almoços ⭐ | 533 | 2.7% |
| Laticínios & Ovos | 468 | 2.3% |
| Conservas ⭐ | 357 | 1.8% |
| Saúde & Bem-Estar | 163 | 0.8% |
| Fitness & Proteínas | 117 | 0.6% |
| Pronto a Comer | 59 | 0.3% |
| Festa & Ocasiões | 57 | 0.3% |

⭐ = categorias novas (antes dispersas noutras classes)

---

## Classificador (`classify_v2.py`)

- **951 keywords** em PT + ES + EN + FR
- **22 categorias canónicas** com **precedência explícita**
- **Word-boundary matching:**
  - Keywords ≤4 chars → `\bkw\b` (estrito, evita `maca` em `macarico`)
  - Keywords ≥5 chars → `\bkw\w*` (prefix/stem, apanha plurais e flexões)
- **Confiança:** 1.0 para kw ≥5 chars; 0.7 para kw <5 chars; 0.0 para Outros
- `needs_review = True` quando categoria = Outros

### Ordem de precedência final

```
1. Congelados           (override absoluto — "congelad*")
2. Bebé                 (> Laticínios: fralda, biberão, aptamil)
3. Animais              (> Talho/Peixaria: ração, "para cão", …)
4. Vinhos & Espirituosas (> Bebidas)
5. Fitness & Proteínas  (> Saúde: whey, creatina)
6. Charcutaria & Queijos (> Talho: fiambre, queijo, chouriço)
7. Conservas            (> Mercearia/Peixaria: atum em lata, azeitonas)
8. Bebidas              (> Frutas — fix chá fermentado/kombucha/smoothie)
9. Snacks               (> Mercearia: bolachas, chips, pipocas)
10. Pequenos-Almoços    (> Mercearia: cereais, granola, mel)
11. Padaria & Pastelaria
12. Peixaria
13. Talho
14. Laticínios & Ovos
15. Frutas & Legumes
16. Pronto a Comer
17. Mercearia           (fallback alimentar)
18. Saúde & Bem-Estar
19. Higiene Pessoal
20. Higiene do Lar
21. Festa & Ocasiões
22. Bio & Saudável      (último — só se nada mais mapear)
```

---

## Fixes aplicados durante a campanha

| # | Correção | Motivo |
|---|---|---|
| 1 | Remoção de `"pan"` (ES) | Apanhava "Panos Microfibra" → Padaria |
| 2 | `"cao "` → frases compostas (`"para cao"`, `"cao adulto"`, etc.) | Evitar false positives, cobrir contexto animal |
| 3 | Keywords `elixir bucal`, `gel bucal`, `enxaguante`, `colutorio` | Faltavam em Higiene Pessoal |
| 4 | Keywords `xarope`, `xarope tosse` | Saúde & Bem-Estar |
| 5 | Keywords `pano microfibra`, `pano limpeza`, `esfregao` | Higiene do Lar |
| 6 | `"azeitona"`/`"azeitonas"` → Conservas | Fix "Azeitona com Alho" |
| 7 | Word-boundary estrito para ≤4 chars | Evitar "maca" em "macarico" |
| 8 | Remoção de `"creme"` solo de Laticínios | Ambíguo; adicionado `creme de rosto/leite/etc.` explícitos |
| 9 | Bebidas → precedência superior a Frutas | Fix "Chá Fermentado Framboesa" |
| 10 | `cha fermentado`, `kombucha`, `smoothie` → Bebidas | |

---

## Infra-estrutura

### Helper RPC criado
```sql
CREATE OR REPLACE FUNCTION public.apply_category_updates(updates jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER …
```
Só altera `taxonomy_section` e `needs_review`. Acessível apenas via `service_role`. Pode ser removido com `DROP FUNCTION apply_category_updates(jsonb)` no final da campanha.

### Ficheiros gerados
```
.claude/skills/category-mapper-v2/
├── SKILL.md
├── references/
│   ├── categorias.md
│   └── decisoes_danilo.json
└── scripts/
    ├── classify_v2.py
    └── run_all.py

.claude/.ai/tmp/
├── classification_{market}.json       (5 ficheiros, ~20K linhas totais)
├── stats_{market}.json                (5 ficheiros)
├── apply_log_{market}.json            (5 ficheiros)
└── batches_continente/batch_01..08.sql

.claude/.ai/reports/
└── category-mapper-v2-final.md        (este ficheiro)
```

---

## Próximos passos

1. **Modo interactivo — Outros (3 383 produtos)**
   Apresentar ao Danilo em grupos de 10 para decisão manual.
   Guardar em `.claude/skills/category-mapper-v2/references/decisoes_danilo.json`.

2. **Limpeza de `needs_review` residuais**
   6 419 com flag — alguns são legados pré-campanha. Opcional: reset `needs_review=false` em categorias que não sejam Outros e tenham confiança ≥ 1.0.

3. **Drop da RPC helper** após revisão final:
   ```sql
   DROP FUNCTION apply_category_updates(jsonb);
   ```

4. **Monitorização pós-lançamento**
   Adicionar check periódico: produtos novos com `taxonomy_section` NULL ou em Outros.

---

## Rollback completo (se necessário)

```sql
UPDATE products
SET taxonomy_section = taxonomy_section_backup
WHERE source ILIKE '%continente%'
   OR source ILIKE '%pingodoce%'
   OR source ILIKE '%auchan%'
   OR source ILIKE '%mercadona%'
   OR source ILIKE '%lidl%'
   OR source ILIKE '%intermarche%';
```
