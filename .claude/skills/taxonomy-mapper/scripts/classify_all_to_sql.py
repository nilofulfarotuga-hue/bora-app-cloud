"""Classify all 43K products locally (no LLM) and emit SQL UPDATE batches.

Reads: all_products.json
Writes: sql_batches/batch_NNNN.sql (2000 rows each)
Also writes: classify_all_stats.json with summary metrics.
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

# Import classify.py functions in-process (no subprocess)
sys.path.insert(0, str(Path(__file__).parent))
import classify as C  # type: ignore  # noqa: E402

HERE = Path(__file__).parent
INP = HERE / "all_products.json"
OUT_DIR = HERE / "sql_batches"
STATS = HERE / "classify_all_stats.json"
BATCH = 2000


def esc(s: str) -> str:
    return s.replace("'", "''")


def log(m: str) -> None:
    print(m, file=sys.stderr, flush=True)


def main() -> None:
    products = json.loads(INP.read_text(encoding="utf-8"))
    log(f"[load] {len(products)} products")

    # Force LLM off — classify_products calls LLM only on fallback; anthropic not in env
    # classify.py already handles missing ANTHROPIC_API_KEY gracefully → fallback_no_llm
    resolved = C.classify_products(products, force=True)
    log(f"[classify] {len(resolved)} results")

    # Stats
    sec_cnt = Counter(r.section for _, r in resolved)
    met_cnt = Counter(r.method for _, r in resolved)
    nr_cnt = sum(1 for _, r in resolved if r.needs_review)
    stats = {
        "total": len(resolved),
        "sections": dict(sec_cnt.most_common()),
        "methods": dict(met_cnt.most_common()),
        "needs_review": nr_cnt,
        "needs_review_pct": round(nr_cnt * 100 / len(resolved), 2),
        "outros_pct": round(sec_cnt.get("Outros", 0) * 100 / len(resolved), 2),
    }
    STATS.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    log(f"[stats] Outros={stats['outros_pct']}%, needs_review={stats['needs_review_pct']}%")

    # Emit SQL batches
    OUT_DIR.mkdir(exist_ok=True)
    # Clean old batches
    for f in OUT_DIR.glob("batch_*.sql"):
        f.unlink()

    batches = 0
    for i in range(0, len(resolved), BATCH):
        chunk = resolved[i:i + BATCH]
        lines = [
            "UPDATE public.products AS p SET",
            "  taxonomy_section = v.section,",
            "  taxonomy_confidence = v.conf,",
            "  needs_review = v.nr",
            "FROM (VALUES",
        ]
        tuples = []
        for p, r in chunk:
            tuples.append(
                f"  ('{esc(str(p['id']))}', '{esc(r.section)}', "
                f"{r.confidence:.2f}, {'true' if r.needs_review else 'false'})"
            )
        lines.append(",\n".join(tuples))
        lines.append(") AS v(id, section, conf, nr)")
        lines.append("WHERE p.id = v.id;")

        out_file = OUT_DIR / f"batch_{i // BATCH:04d}.sql"
        out_file.write_text("\n".join(lines), encoding="utf-8")
        batches += 1

    log(f"[done] wrote {batches} batches -> {OUT_DIR}")
    print(json.dumps({
        "batches": batches,
        "total": len(resolved),
        "outros_pct": stats["outros_pct"],
        "needs_review_pct": stats["needs_review_pct"],
    }))


if __name__ == "__main__":
    main()
