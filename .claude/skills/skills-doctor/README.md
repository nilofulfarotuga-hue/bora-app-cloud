# skills-doctor

Valida todas as skills do Bora App. Read-only, stdlib-only.

```bash
python scripts/check.py            # relatório de todas
python scripts/check.py --skill <nome>
python scripts/check.py --strict   # avisos falham o exit code
```

Verifica frontmatter, `name == pasta`, `depends_on: bora-knowledge`, compilação
(`py_compile`) de cada script, presença de README/requirements e indício de dry-run.

Saída `[OK]/[!]/[X]` por skill + sumário. Exit code = nº de skills com erro.
Não altera nada. Ver `SKILL.md` para detalhe das regras.
