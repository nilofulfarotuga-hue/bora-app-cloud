#!/usr/bin/env python3
"""
run_all.py — Orchestrator (documentação executável) das 7 fases da campanha
category-mapper-v2.

Este ficheiro NÃO corre SQL directamente. É a referência da sequência que o
Claude Code deve executar via MCP Supabase com aprovação do Danilo a cada
paragem (modo protecção total).

Fases:
    0. Backup + contagem actual     (JÁ FEITO)
    1. Continente                   → dry-run → STOP → apply
    2. Pingo Doce                   → dry-run → STOP → apply
    3. Auchan                       → dry-run → STOP → apply
    4. Mercadona                    → dry-run → STOP → apply
    5. Lidl + Intermarché           → dry-run → STOP → apply
    6. Relatório final

Critérios de paragem automática:
    - >60% de produtos de um mercado mudam de categoria.
    - Erro em qualquer batch → rollback só desse batch.

Circuit breakers:
    - Só actualiza taxonomy_section e needs_review.
    - NUNCA toca em is_active, price, photo_url, name, brand_*.
"""
from __future__ import annotations

from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL_ROOT = HERE.parent
REF = SKILL_ROOT / "references"
REPORT_DIR = Path(".claude/.ai/reports")

MARKETS: dict[str, list[str]] = {
    "continente": ["continente_guarda", "continente.pt",
                   "continente_sfcc_bestsellers_2026-04-18",
                   "continente_sfcc_bestsellers_2026-04-20"],
    "pingodoce": ["pingodoce_guarda"],
    "auchan": ["auchan_guarda"],
    "mercadona": ["mercadona_guarda"],
    "lidl": ["lidl_guarda"],
    "intermarche": ["intermarche_guarda"],
}

BATCH_SIZE = 500
CHANGE_THRESHOLD_PCT = 60


def dry_run_sql(source_like: str) -> str:
    """SQL para apanhar amostra representativa (usar com LIMIT)."""
    return (
        "SELECT id, name, category_root, taxonomy_section "
        f"FROM products WHERE source ILIKE '%{source_like}%' "
        "ORDER BY md5(id) LIMIT 2000;"
    )


def apply_batch_sql(source_like: str, offset: int) -> str:
    """SQL de apply por batch (o Classifier corre em memória; o UPDATE é por id)."""
    return (
        "-- Cada UPDATE envia pares (id, nova_categoria) em transacção:\n"
        "BEGIN;\n"
        f"-- batch source={source_like} offset={offset} size={BATCH_SIZE}\n"
        "UPDATE products SET taxonomy_section = :new, needs_review = :nr\n"
        "  WHERE id = :id;\n"
        "COMMIT;"
    )


def main() -> None:
    print("category-mapper-v2 — orchestrator ready.")
    print(f"Skill root:  {SKILL_ROOT}")
    print(f"References:  {REF}")
    print(f"Report dir:  {REPORT_DIR}")
    print(f"Markets:     {', '.join(MARKETS.keys())}")
    print(f"Batch size:  {BATCH_SIZE}")
    print(f"Change breaker: {CHANGE_THRESHOLD_PCT}%")


if __name__ == "__main__":
    main()
