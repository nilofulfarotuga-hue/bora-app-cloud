#!/usr/bin/env python3
"""
Market Data Cleaner — translate.py
Translate Mercadona product names ES→PT using a hardcoded dictionary.

No network dependencies by default. `deep-translator` only if --online is
explicitly passed AND the user approves.

Usage:
    python translate.py --print-dict              # show dictionary
    python translate.py --emit-sql                # emit UPDATE statements
    python translate.py --sample "Leche entera 1L"  # test translation
"""

import argparse
import re
import sys


PT_ES_DICT = {
    # laticínios / lácteos
    "leche": "leite",
    "leche entera": "leite gordo",
    "leche desnatada": "leite magro",
    "leche semidesnatada": "leite meio-gordo",
    "mantequilla": "manteiga",
    "queso": "queijo",
    "queso fresco": "queijo fresco",
    "queso curado": "queijo curado",
    "yogur": "iogurte",
    "nata": "natas",

    # óleos / gorduras
    "aceite": "azeite",
    "aceite de oliva": "azeite",
    "aceite de girasol": "óleo de girassol",

    # proteínas
    "carne": "carne",
    "carne picada": "carne picada",
    "pescado": "peixe",
    "pollo": "frango",
    "pollo entero": "frango inteiro",
    "pechuga de pollo": "peito de frango",
    "huevo": "ovo",
    "huevos": "ovos",
    "atun": "atum",
    "atún": "atum",
    "cerdo": "porco",
    "ternera": "vitela",

    # mercearia
    "agua": "água",
    "agua mineral": "água mineral",
    "pan": "pão",
    "pan de molde": "pão de forma",
    "arroz": "arroz",
    "azucar": "açúcar",
    "azúcar": "açúcar",
    "sal": "sal",
    "harina": "farinha",
    "galleta": "bolacha",
    "galletas": "bolachas",
    "zumo": "sumo",
    "zumo de naranja": "sumo de laranja",
    "cafe": "café",
    "café": "café",
    "mermelada": "doce",

    # frutas / vegetais
    "verdura": "vegetais",
    "verduras": "vegetais",
    "fruta": "fruta",
    "manzana": "maçã",
    "naranja": "laranja",
    "platano": "banana",
    "plátano": "banana",
    "uva": "uva",
    "tomate": "tomate",
    "patata": "batata",
    "patatas": "batatas",
    "cebolla": "cebola",
    "ajo": "alho",
    "zanahoria": "cenoura",
    "lechuga": "alface",

    # preposições / comuns
    "con": "com",
    "sin": "sem",
    "de": "de",
    "para": "para",
    "entero": "inteiro",
    "entera": "inteira",
    "fresco": "fresco",
    "fresca": "fresca",
    "congelado": "congelado",
    "congelada": "congelada",
    "caliente": "quente",
    "frio": "frio",
    "frío": "frio",

    # tamanhos/unidades (comuns em nomes)
    "bolsa": "saco",
    "botella": "garrafa",
    "paquete": "pacote",
    "caja": "caixa",
    "lata": "lata",
}


def translate_name(name: str) -> str:
    """Naive word-by-word replace, preserving case on the first letter."""
    if not name:
        return name
    lowered = name.lower()
    # sort by length desc so multi-word keys match first
    for es in sorted(PT_ES_DICT, key=len, reverse=True):
        pt = PT_ES_DICT[es]
        lowered = re.sub(rf"\b{re.escape(es)}\b", pt, lowered)
    if name and name[0].isupper():
        lowered = lowered[:1].upper() + lowered[1:]
    return lowered


def emit_sql_update_per_entry() -> None:
    """Emit SQL that runs translate_name on every Mercadona product name.

    Strategy: do it in Python (pull names, translate, push back in batches)
    because Postgres regex_replace per-word would be verbose. Emit a stub
    that the operator will wire up to MCP Supabase in a follow-up step.
    """
    print("-- To apply translation, run this script's translate_name() in Python")
    print("-- against a SELECT of Mercadona products, then emit UPDATEs in batches.")
    print()
    print("-- Step 1: export original names to a CSV for review")
    print("""
SELECT p.id, p.name
FROM public.products p
JOIN public.markets m ON m.id = p.market_id
WHERE m.name ILIKE '%mercadona%'
  AND p.name ~* '\\y(con|de|para|sin|leche|aceite|carne|pescado|queso|huevo|pollo|agua|verdura|pan|mantequilla|galleta|zumo|arroz|az[úu]car)\\y';
""".strip())
    print()
    print("-- Step 2: preserve original in products.original_name_es")
    print("""
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS original_name_es text;

UPDATE public.products p SET original_name_es = p.name
FROM public.markets m
WHERE m.id = p.market_id
  AND m.name ILIKE '%mercadona%'
  AND p.original_name_es IS NULL;
""".strip())
    print()
    print("-- Step 3: apply translations in batches via Python+MCP (see SKILL.md).")


def main() -> int:
    parser = argparse.ArgumentParser(description="ES→PT translation for Mercadona product names.")
    parser.add_argument("--print-dict", action="store_true", help="Print the translation dictionary.")
    parser.add_argument("--emit-sql", action="store_true", help="Emit setup SQL (ES preservation).")
    parser.add_argument("--sample", help="Translate a single name and exit.")
    args = parser.parse_args()

    if args.sample:
        print(translate_name(args.sample))
        return 0

    if args.print_dict:
        for es, pt in sorted(PT_ES_DICT.items()):
            print(f"{es:30s} → {pt}")
        return 0

    if args.emit_sql:
        emit_sql_update_per_entry()
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
