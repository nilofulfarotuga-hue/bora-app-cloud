---
name: category-mapper-v2
description: >
  Reclassifica produtos da tabela `products` em 22 categorias canónicas usando
  regras de palavras-chave em Python puro. Sem API externa, sem LLM. Usa
  precedência (Congelados > Bebé > Animais > Vinhos > Charcutaria > Fitness >
  Conservas > Snacks > Pequenos-Almoços > Padaria > Peixaria > Talho >
  Laticínios > Frutas & Legumes > Pronto a Comer > Mercearia > Bebidas >
  Saúde > Higiene Pessoal > Higiene do Lar > Festa > Bio). Suporta PT+ES+EN+FR
  (≥500 palavras-chave). Execução por fases com dry-run, aprovação manual do
  Danilo e modo interactivo para produtos sem categoria clara.
  Triggers: "reclassificar produtos", "mapear 22 categorias", "category-mapper-v2",
  "dry-run Continente/Pingo Doce/Auchan/Mercadona/Lidl/Intermarché".
metadata:
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# category-mapper-v2

## Objectivo

Reclassificar `products.taxonomy_section` em 22 categorias canónicas via regras
deterministas em Python. Dry-run obrigatório antes de qualquer write. Backup em
`taxonomy_section_backup` (já existente).

## Circuit Breakers

- NUNCA tocar em: `is_available`, `price`, `photo_url`, `name`, `brand_*`.
- SÓ alterar: `taxonomy_section` e `needs_review`.
- Se >60% de um mercado mudar de categoria → PARAR e avisar o Danilo.
- Em erro de batch → rollback SÓ desse batch, continuar.
- Backup já feito em `taxonomy_section_backup` — não refazer.

## 22 Categorias Canónicas

Ver `references/categorias.md`.

## Fluxo

1. **FASE 0** — backup + contagem actual (JÁ FEITO).
2. **FASE 1 Continente** → dry-run 30 exemplos → **STOP** → aplicar batches 500.
3. **FASE 2 Pingo Doce** → mesmo.
4. **FASE 3 Auchan** → mesmo.
5. **FASE 4 Mercadona** → mesmo (espera tradução ES→PT).
6. **FASE 5 Lidl + Intermarché** → mesmo.
7. **FASE 6** — relatório final em `.claude/.ai/reports/category-mapper-v2-final.md`.

## Modo Interactivo

Quando `confidence < 0.7` e `taxonomy_section ∈ (NULL, 'Outros')`:

1. Agrupar em lotes de 10.
2. Apresentar ao Danilo com sugestão + opção livre.
3. Guardar decisão em `references/decisoes_danilo.json` (chave = nome
   normalizado, valor = categoria escolhida).
4. Nunca perguntar o mesmo produto duas vezes.

## Ficheiros

- `scripts/classify_v2.py` — classe `Classifier` com ≥500 keywords.
- `scripts/run_all.py` — orchestrator com paragens por fase.
- `references/categorias.md` — docs das 22 categorias + regras.
- `references/decisoes_danilo.json` — decisões manuais.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
