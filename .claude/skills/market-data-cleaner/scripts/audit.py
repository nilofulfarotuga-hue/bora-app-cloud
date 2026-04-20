#!/usr/bin/env python3
"""
Market Data Cleaner — audit.py
Read-only audit of product catalog quality per market.

Usage:
    SUPABASE_URL=... SUPABASE_ANON_KEY=... python audit.py
    python audit.py --market lidl
    python audit.py --json

Never writes to the database. Safe to run at any time.
"""

import argparse
import json
import os
import sys
from typing import Any

try:
    from supabase import create_client, Client
except ImportError:
    print("ERROR: supabase-py not installed. Run: pip install supabase", file=sys.stderr)
    sys.exit(1)


QUERIES = {
    "A_no_image": """
        SELECT m.name AS market, COUNT(p.*) AS total,
               COUNT(p.*) FILTER (WHERE p.photo_url IS NULL OR p.photo_url = '') AS sem_imagem,
               ROUND(100.0 * COUNT(p.*) FILTER (WHERE p.photo_url IS NULL OR p.photo_url = '')
                     / NULLIF(COUNT(p.*), 0), 2) AS pct_sem_img
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        GROUP BY m.name
        ORDER BY pct_sem_img DESC NULLS LAST;
    """,
    "B_invalid_price": """
        SELECT m.name AS market,
               COUNT(p.*) FILTER (WHERE p.price IS NULL) AS sem_preco,
               COUNT(p.*) FILTER (WHERE p.price = 0) AS preco_zero,
               COUNT(p.*) FILTER (WHERE p.price > 500) AS preco_muito_alto,
               MIN(p.price) FILTER (WHERE p.price > 0) AS min_price,
               MAX(p.price) AS max_price
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        GROUP BY m.name;
    """,
    "C_short_names": """
        SELECT m.name AS market,
               COUNT(p.*) FILTER (WHERE LENGTH(p.name) < 10) AS nomes_curtos,
               (array_agg(p.name ORDER BY random()) FILTER (WHERE LENGTH(p.name) < 10))[1:5] AS amostras
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        GROUP BY m.name;
    """,
    "D_non_supermarket_pingodoce": """
        SELECT m.name AS market, p.name, p.category_root, p.price
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        WHERE m.name ILIKE '%pingo%'
          AND p.name ~* '\\y(tv|televis[ãa]o|smartphone|telem[óo]vel|computador|laptop|notebook|pneu|ourivesaria)\\y'
        LIMIT 50;
    """,
    "E_spanish_mercadona": """
        SELECT m.name AS market, p.name
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        WHERE m.name ILIKE '%mercadona%'
          AND p.name ~* '\\y(con|de|para|sin|leche|aceite|carne|pescado|queso|huevo|pollo|agua|verdura|pan)\\y'
        LIMIT 30;
    """,
    "F_taxonomy_outros": """
        SELECT m.name AS market,
               COUNT(p.*) FILTER (WHERE p.taxonomy_section = 'Outros') AS outros,
               COUNT(p.*) AS total,
               ROUND(100.0 * COUNT(p.*) FILTER (WHERE p.taxonomy_section = 'Outros')
                     / NULLIF(COUNT(p.*), 0), 2) AS pct_outros
        FROM public.products p
        JOIN public.markets m ON m.id = p.market_id
        GROUP BY m.name
        ORDER BY pct_outros DESC NULLS LAST;
    """,
}


def run_query(client: Client, sql: str) -> list[dict[str, Any]]:
    # supabase-py v2 doesn't support raw SQL directly.
    # For raw SQL, use a Postgres RPC or the postgrest REST API.
    # Recommended: run via MCP Supabase execute_sql or psql.
    raise NotImplementedError(
        "supabase-py doesn't run raw SQL. Use MCP Supabase execute_sql or psql. "
        "This script serves as the authoritative source of the 6 queries."
    )


def print_queries() -> None:
    """Print all queries to stdout for manual execution."""
    for label, sql in QUERIES.items():
        print(f"-- ===== {label} =====")
        print(sql.strip())
        print()


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit product catalog quality (read-only).")
    parser.add_argument("--print", action="store_true", help="Print SQL queries to stdout and exit.")
    parser.add_argument("--json", action="store_true", help="Output results as JSON.")
    args = parser.parse_args()

    if args.print or True:
        # Default behavior: emit queries for MCP Supabase or psql execution.
        print_queries()
        return 0

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_ANON_KEY")
    if not url or not key:
        print("ERROR: set SUPABASE_URL and SUPABASE_ANON_KEY env vars.", file=sys.stderr)
        return 2

    _ = create_client(url, key)
    print("TIP: run the queries via MCP Supabase (execute_sql) or psql.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
