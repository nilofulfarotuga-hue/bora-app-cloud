# update-bora-knowledge

Deteta drift entre a `bora-knowledge` e o repo. **Read-only sobre a knowledge** —
gera uma proposta em `_preview/`, nunca edita os docs (Knowledge Protocol).

```bash
python scripts/detect_drift.py            # relatório + _preview/knowledge-drift-<data>.md
python scripts/detect_drift.py --no-file  # só terminal
```

Verifica: Edge Functions (`supabase/functions/` vs `08-edge-functions.md`) e skills
(pastas vs `INDEX.md` + contagem). Stdlib-only. Ver `SKILL.md`.
