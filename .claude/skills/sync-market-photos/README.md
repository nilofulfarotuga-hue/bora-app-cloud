# README — sync-market-photos

Dá foto a produtos de mercado sem imagem, reutilizando fotos de uma loja donor
(Mercadona). **DB-interno, sem scraping, nunca preço.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/list_missing_photos.py
python scripts/match_photos.py --store continente-guarda          # → _preview/photo_matches.csv
python scripts/apply_photos.py  --store continente-guarda          # dry-run
python scripts/apply_photos.py  --store continente-guarda --commit # grava + audita
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `MARKET_STORES` + `audit_log` + `head_ok` + rate-limit |
| `list_missing_photos.py` | contagem `needs_photo=true` por loja |
| `match_photos.py` | constrói índice donor (search_normalized→photo_url) e propõe candidatos → CSV |
| `apply_photos.py` | valida HEAD 200, dry-run/`--commit` UPDATE photo_url+image_source+needs_photo=false |

## Notas
- Donor default `mercadona-guarda` (100% fotos). Override `--donor`.
- CSV externo (`product_id,photo_url`) aceite via `apply_photos --csv <file>` (imagens de
  Glovo/Uber via market-data-sync — só imagem).
- Foto reutilizada entre lojas → caveat de qualidade (relatório lista para revisão).
- Soft-delete em products é `is_available` (sem is_deleted/deleted_at) — não relevante aqui.
