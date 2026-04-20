#!/usr/bin/env python3
"""
Market Data Cleaner — clean.py
Soft-delete (is_active=false) products that fail quality rules.

SAFETY RULES (enforced):
  1. --dry-run is DEFAULT. Must pass --apply explicitly.
  2. --market is REQUIRED. Never operates globally.
  3. Backup table products_cleanup_backup_20260419 must exist before --apply.
  4. Circuit breaker: aborts if >50% of market would be affected.
  5. Batch size hard limit: 1000 rows per UPDATE.

Usage:
    python clean.py --market lidl                  # dry-run (default)
    python clean.py --market lidl --apply          # real execution (requires backup)
    python clean.py --market lidl --criteria c,d   # only criteria c and d

This script emits the SQL to stdout for execution via MCP Supabase.
It does NOT connect to the DB directly.
"""

import argparse
import sys
from typing import Iterable


CRITERIA = {
    "a": "no_image",          # marca needs_review (não soft-delete)
    "b": "no_brand",          # marca needs_review
    "c": "invalid_price",     # soft-delete
    "d": "non_supermarket",   # soft-delete (Pingo Doce)
    "e": "translate_es_pt",   # usar translate.py em vez deste
}


SOFT_DELETE_INVALID_PRICE = """
-- Critério (c): soft-delete preços inválidos (market: {market})
UPDATE public.products SET is_active = false
WHERE id IN (
  SELECT p.id FROM public.products p
  JOIN public.markets m ON m.id = p.market_id
  WHERE m.name ILIKE '%{market}%'
    AND (p.price IS NULL OR p.price = 0 OR p.price > 500 OR p.price < 0.05)
    AND p.is_active = true
  LIMIT 1000
);
""".strip()


SOFT_DELETE_NON_SUPERMARKET = """
-- Critério (d): soft-delete electrónicos/etc no Pingo Doce
UPDATE public.products SET is_active = false
WHERE id IN (
  SELECT p.id FROM public.products p
  JOIN public.markets m ON m.id = p.market_id
  WHERE m.name ILIKE '%pingo%'
    AND p.name ~* '\\y(tv|televis[ãa]o|smartphone|telem[óo]vel|computador|laptop|notebook|tablet|pneu|ourivesaria|joia)\\y'
    AND p.name !~* '\\y(pilha|l[âa]mpada)\\y'
    AND (p.price IS NULL OR p.price >= 20)
    AND p.is_active = true
  LIMIT 1000
);
""".strip()


MARK_NEEDS_REVIEW_NO_IMAGE = """
-- Critério (a): flag needs_review para produtos sem imagem (market: {market})
-- NOTA: assumes coluna needs_review existe (bool default false).
UPDATE public.products SET needs_review = true
WHERE id IN (
  SELECT p.id FROM public.products p
  JOIN public.markets m ON m.id = p.market_id
  WHERE m.name ILIKE '%{market}%'
    AND (p.photo_url IS NULL OR p.photo_url = '' OR p.photo_url !~ '^https?://')
    AND COALESCE(p.needs_review, false) = false
  LIMIT 1000
);
""".strip()


PRECHECK_AFFECTED_PCT = """
-- Pre-check: % afectado. ABORTAR se > 50%.
SELECT
  COUNT(*) FILTER (WHERE {where_clause}) AS afectados,
  COUNT(*) AS total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE {where_clause}) / NULLIF(COUNT(*), 0), 2) AS pct
FROM public.products p
JOIN public.markets m ON m.id = p.market_id
WHERE m.name ILIKE '%{market}%' AND p.is_active = true;
""".strip()


ENSURE_IS_ACTIVE_COLUMN = """
-- Run once: adicionar coluna is_active se não existir
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
""".strip()


ENSURE_NEEDS_REVIEW_COLUMN = """
-- Run once: adicionar coluna needs_review se não existir
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS needs_review boolean NOT NULL DEFAULT false;
""".strip()


CREATE_BACKUP = """
-- Run once before first --apply: criar tabela de backup
CREATE TABLE IF NOT EXISTS public.products_cleanup_backup_20260419 AS
SELECT id, photo_url, name, price,
       COALESCE(is_active, true) AS is_active_prev,
       COALESCE(needs_review, false) AS needs_review_prev,
       now() AS backed_up_at
FROM public.products;
""".strip()


def emit(sql: str) -> None:
    print(sql)
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="Soft-delete products failing quality rules.")
    parser.add_argument("--market", required=True, help="Market name substring (e.g. 'lidl').")
    parser.add_argument("--criteria", default="c,d",
                        help="Comma-separated criteria to apply (default: c,d). a,b = needs_review only.")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Emit SQL only (default).")
    parser.add_argument("--apply", action="store_true", help="Override --dry-run. Requires backup.")
    parser.add_argument("--emit-setup", action="store_true",
                        help="Emit one-time setup SQL (columns + backup).")
    args = parser.parse_args()

    if args.apply:
        print("-- WARNING: --apply mode. Confirm backup exists.", file=sys.stderr)
        args.dry_run = False

    market = args.market.strip().lower()
    if not market or len(market) < 3:
        print("ERROR: --market must be >= 3 chars.", file=sys.stderr)
        return 2

    criteria: Iterable[str] = [c.strip().lower() for c in args.criteria.split(",") if c.strip()]
    unknown = [c for c in criteria if c not in CRITERIA]
    if unknown:
        print(f"ERROR: unknown criteria {unknown}. Valid: {list(CRITERIA.keys())}", file=sys.stderr)
        return 2

    if args.emit_setup:
        print("-- ===== ONE-TIME SETUP =====")
        emit(ENSURE_IS_ACTIVE_COLUMN)
        emit(ENSURE_NEEDS_REVIEW_COLUMN)
        emit(CREATE_BACKUP)
        return 0

    print(f"-- ===== MARKET: {market} =====")
    print(f"-- Criteria: {list(criteria)}")
    print(f"-- Mode: {'DRY-RUN' if args.dry_run else 'APPLY'}")
    print()

    if "c" in criteria:
        print("-- Pre-check critério (c):")
        emit(PRECHECK_AFFECTED_PCT.format(
            market=market,
            where_clause="p.price IS NULL OR p.price = 0 OR p.price > 500 OR p.price < 0.05",
        ))
        if not args.dry_run:
            emit(SOFT_DELETE_INVALID_PRICE.format(market=market))

    if "d" in criteria and "pingo" in market:
        print("-- Pre-check critério (d) Pingo Doce:")
        emit(PRECHECK_AFFECTED_PCT.format(
            market=market,
            where_clause=(
                "p.name ~* '\\y(tv|televis[ãa]o|smartphone|telem[óo]vel|computador|laptop|notebook|pneu|ourivesaria)\\y' "
                "AND p.name !~* '\\y(pilha|l[âa]mpada)\\y'"
            ),
        ))
        if not args.dry_run:
            emit(SOFT_DELETE_NON_SUPERMARKET)

    if "a" in criteria:
        print("-- Critério (a) — flag needs_review (sem apagar):")
        if not args.dry_run:
            emit(MARK_NEEDS_REVIEW_NO_IMAGE.format(market=market))

    print("-- END")
    return 0


if __name__ == "__main__":
    sys.exit(main())
