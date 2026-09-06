# update-bora-knowledge

Deteta drift entre a `bora-knowledge` e o repo. **Read-only sobre a knowledge** —
gera uma proposta em `_preview/`, nunca edita os docs (Knowledge Protocol).

```bash
python scripts/detect_drift.py            # drift read-only → _preview/
python scripts/apply_updates.py           # MODO A: preview de 00-auto-facts.md
python scripts/apply_updates.py --apply   # escreve knowledge/00-auto-facts.md
```

Verifica: Edge Functions (`supabase/functions/` vs `08-edge-functions.md`) e skills
(pastas vs `INDEX.md` + contagem). `apply_updates` só escreve o ficheiro auto-gerido
`00-auto-facts.md` (docs curados 01–12 intactos). Stdlib-only. Ver `SKILL.md`.
