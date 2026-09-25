# generate-skills-readme

Gera o **README.md mestre** das skills, agrupado por categoria, a partir do
frontmatter + corpo de cada `SKILL.md`. Não toca no `INDEX.md` (curado à mão).
Stdlib-only.

```bash
python scripts/gen_readme.py          # dry-run → _preview/README.generated.md
python scripts/gen_readme.py --write  # grava README.md na raiz das skills
```

Para cada skill: nome · o que faz · comando exemplo · dry-run sim/não. Ver `SKILL.md`.
