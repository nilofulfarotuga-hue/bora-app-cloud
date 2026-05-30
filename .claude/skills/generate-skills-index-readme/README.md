# generate-skills-index-readme

Gera um README tabular das skills a partir do frontmatter de cada `SKILL.md`.
Não toca no `INDEX.md` (curado à mão). Stdlib-only.

```bash
python scripts/generate.py          # dry-run → _preview/SKILLS_README.generated.md
python scripts/generate.py --write  # grava SKILLS_README.md na raiz das skills
```

Tabela `| Skill | Tipo | Descrição |` ordenada por nome + contagem. Ver `SKILL.md`.
