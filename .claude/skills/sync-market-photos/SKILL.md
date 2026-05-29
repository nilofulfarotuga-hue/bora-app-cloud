---
name: sync-market-photos
description: Preenche photo_url de produtos de mercado com needs_photo=true reutilizando fotos de uma loja "donor" (Mercadona, 100% fotos) por search_normalized — só DB, zero scraping, ZERO preço. Dry-run default; --commit grava photo_url+image_source+needs_photo=false.
metadata:
  type: data
  category: market
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Sync Market Photos

Dá foto a produtos de mercado sem imagem (`needs_photo=true`) **reutilizando** a foto de
um produto com o mesmo nome normalizado numa loja donor que já tem fotos (default
`mercadona-guarda`, 8115 produtos, 100% com foto). **Não faz scraping** e **nunca toca preço**.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/07-database-key-tables.md` (schema `products`)
2. `bora-knowledge/knowledge/10-protected-zones.md` (fotos/preço intocáveis)

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fonte de fotos (permitida)
- **Primária (built-in)**: reuse donor por `search_normalized` (DB interna, verificável).
- **Externa opcional**: CSV `product_id,photo_url` (ex.: imagens obtidas via `market-data-sync`
  a partir de Glovo/Uber — **só imagem, nunca preço**). Validada por HEAD 200 antes de gravar.

## Uso
```bash
python scripts/list_missing_photos.py                              # needs_photo por loja
python scripts/match_photos.py --store continente-guarda [--donor mercadona-guarda]
                                                                   # → _preview/photo_matches.csv
python scripts/apply_photos.py --store continente-guarda           # dry-run (HEAD valida)
python scripts/apply_photos.py --store continente-guarda --commit  # UPDATE + auditoria
```

## Modos
- **DEFAULT (dry-run)**: gera/valida candidatos, relatório `_preview/`. NÃO escreve.
- **`--commit`** (apply_photos): `UPDATE products SET photo_url=:url, image_source='reuse:<donor>',
  needs_photo=false WHERE id=:id` + `admin_audit_log`. Rate limit `--rate` (default 3.5s) ao validar.

## Salvaguardas
- **NUNCA** toca `price`/`price_*`/`discount_price`. Só `photo_url`, `image_source`, `needs_photo`.
- Só lojas de **mercado** (allowlist em `_shared.MARKET_STORES`). Recusa partner/uuid/fast-food.
- Valida `HEAD 200` antes de gravar. Caveat de qualidade: foto reutilizada de outra loja →
  o relatório lista para revisão.
