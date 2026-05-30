---
name: generate-skills-index-readme
description: Gera um README tabular das skills a partir do frontmatter de cada SKILL.md (name, metadata.type, description). Dry-run escreve em _preview/; --write grava SKILLS_README.md na raiz. NÃO toca no INDEX.md (curado à mão). Stdlib-only.
metadata:
  type: meta
  category: consolidation
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Generate Skills Index README

Produz uma vista tabular automática de todas as skills, derivada do **frontmatter**
(`name`, `metadata.type`, `description`). Útil para ter um índice sempre fiel ao que
existe, sem manutenção manual.

## Relação com o INDEX.md
- `INDEX.md` é **curado à mão** (notas ricas por lote S1–S4) — esta skill **não lhe toca**.
- O output vai para `SKILLS_README.md` (gerado) — complementar, não substituto.

## Uso
```bash
python scripts/generate.py            # dry-run → _preview/SKILLS_README.generated.md
python scripts/generate.py --write    # grava SKILLS_README.md na raiz das skills
```

## Saída
Tabela `| Skill | Tipo | Descrição |` ordenada por nome, com a 1ª frase da
`description` de cada skill + contagem total.

## Salvaguardas
- Read-only sobre as skills; só **gera** um ficheiro de índice (preview por default).
- Nunca edita `INDEX.md`, `SKILL.md`, DB, Stripe ou `lib/`.
- Stdlib-only; reusa o parser de frontmatter de `skills-doctor` (DRY).
