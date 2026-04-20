"""
Mercadona mojibake fix — dictionary + ES pattern rules.
Destructive mojibake recovery by contextual inference in Spanish vocabulary.
"""
import json, re, sys, os, random
from collections import Counter

# ==== DICIONARIO ES: mojibake -> corrigido ====
# Construido por inferência em vocabulário ES de supermercado.
# Preserva capitalização original via lookup case-insensitive + re-aplicação.
MOJIBAKE_DICT = {
    # -ción / -sión
    "coloracion": "coloración", "fijacion": "fijación", "locion": "loción",
    "proteccion": "protección", "depilacion": "depilación", "infusion": "infusión",
    "hidratacion": "hidratación", "nutricion": "nutrición", "racion": "ración",
    "seleccion": "selección", "emulsion": "emulsión", "solucion": "solución",
    "precision": "precisión", "coleccion": "colección", "cocina": "cocina",
    "limpieza": "limpieza", "condicion": "condición", "preparacion": "preparación",
    "presentacion": "presentación", "cancion": "canción", "duracion": "duración",
    "iluminacion": "iluminación", "combinacion": "combinación", "aplicacion": "aplicación",
    "reduccion": "reducción", "reparacion": "reparación", "conservacion": "conservación",
    "relajacion": "relajación", "exfoliacion": "exfoliación", "maceracion": "maceración",
    "extraccion": "extracción", "absorcion": "absorción", "digestion": "digestión",

    # -ón finals (masculine)
    "limon": "limón", "jamon": "jamón", "salmon": "salmón", "atun": "atún",
    "maiz": "maíz", "pati": "paté", "bombon": "bombón", "salchichon": "salchichón",
    "melocoton": "melocotón", "marron": "marrón", "champan": "champán",
    "aragon": "aragón", "rincon": "rincón", "algodon": "algodón", "canelon": "canelón",
    "cartagenon": "cartagenón", "razon": "razón", "corazon": "corazón",
    "chorizon": "chorizón", "turron": "turrón", "melon": "melón",
    "camarón": "camarón", "carbon": "carbón", "nylon": "nylón",
    "balcon": "balcón", "huron": "hurón", "racimon": "racimón",

    # -í / -ú endings
    "cafe": "café", "ti": "té", "bebi": "bebé", "pati": "paté", "champu": "champú",
    "rapi": "rápi", "sofa": "sofá",  # common shorts

    # ñ between letters (-Ão -Ãa -Ãe -Ãi -Ãu)
    "bano": "baño", "ano": "año", "pequeño": "pequeño",  # already
    "pequena": "pequeña", "pequeno": "pequeño", "danado": "dañado",
    "castano": "castaño", "uñas": "uñas", "uñas": "uñas",  # placeholder
    "pestañas": "pestañas", "tamano": "tamaño", "pañal": "pañal", "panal": "pañal",
    "pañales": "pañales", "panales": "pañales", "espanol": "español",
    "espanola": "española", "albanil": "albañil", "banar": "bañar",
    "acompanar": "acompañar", "manana": "mañana", "engano": "engaño",
    "nino": "niño", "nina": "niña", "senor": "señor", "senora": "señora",
    "punado": "puñado", "sueño": "sueño", "otoño": "otoño",
    "añadido": "añadido", "añadida": "añadida", "añadidos": "añadidos",
    "añadidas": "añadidas",

    # -í -é -ó -ú -á accented mid-word
    "liquido": "líquido", "liquida": "líquida", "liquidos": "líquidos",
    "ibérico": "ibérico", "ibérica": "ibérica", "iberico": "ibérico", "iberica": "ibérica",
    "electrico": "eléctrico", "electrica": "eléctrica", "electricos": "eléctricos",
    "plastico": "plástico", "plastica": "plástica",
    "dentifrico": "dentífrico", "dentifricos": "dentífricos",
    "energetica": "energética", "energetico": "energético",
    "isotonica": "isotónica", "isotonico": "isotónico",
    "lacteo": "lácteo", "lactea": "láctea", "lacteos": "lácteos", "lacteas": "lácteas",
    "tonica": "tónica", "tonico": "tónico",
    "instantaneo": "instantáneo", "instantanea": "instantánea",
    "acido": "ácido", "acida": "ácida", "acidos": "ácidos",
    "balsamo": "bálsamo", "higado": "hígado",
    "maquina": "máquina", "maquinas": "máquinas",
    "capsula": "cápsula", "capsulas": "cápsulas",
    "serum": "sérum", "cúrcuma": "cúrcuma", "curcuma": "cúrcuma",
    "azucar": "azúcar", "azúcares": "azúcares", "azucares": "azúcares",
    "oleico": "oleico", "sartén": "sartén", "sarten": "sartén",
    "mostramos": "mostramos",  # no-op placeholder

    # amoníaco y similares
    "amoniaco": "amoníaco", "organico": "orgánico", "organica": "orgánica",
    "basico": "básico", "basica": "básica", "magico": "mágico", "magica": "mágica",
    "exotico": "exótico", "exotica": "exótica",
    "clasico": "clásico", "clasica": "clásica",
    "publico": "público", "publica": "pública",
    "clinico": "clínico", "clinica": "clínica",
    "medico": "médico", "medica": "médica",
    "automatico": "automático", "automatica": "automática",
    "aromatico": "aromático", "aromatica": "aromática",
    "ecologico": "ecológico", "ecologica": "ecológica",
    "hipoalergenico": "hipoalergénico",
    "cosmetico": "cosmético", "cosmetica": "cosmética",
    "tropical": "tropical",  # no-op
    "alcoholico": "alcohólico", "alcoholica": "alcohólica",
    "unico": "único", "unica": "única",
    "rapida": "rápida", "rapido": "rápido",
    "aspero": "áspero", "nuclear": "nuclear",
    "pimenton": "pimentón", "aleman": "alemán", "alemana": "alemana",
    "japones": "japonés", "frances": "francés",
    "sifon": "sifón", "jabon": "jabón",
    "coliflor": "coliflor",  # no-op
    "caja": "caja",  # no-op
}

# ==== ACCENT PATTERN RULES (fallback) ====
# Applied lowercase; capitalization restored after.
# Order matters: more specific first.
PATTERN_RULES = [
    # ciÃn$ -> ción
    (re.compile(r'ciÃn\b'), 'ción'),
    (re.compile(r'ciÃ(?=n)'), 'cióN'),   # rare
    # sÃn$ -> són
    (re.compile(r'sÃn\b'), 'són'),
    # -Ão -Ãa -Ãe -Ãi -Ãu (ñ + vowel)
    (re.compile(r'Ãa'), 'ña'),
    (re.compile(r'Ão'), 'ño'),
    (re.compile(r'Ãe'), 'ñe'),
    (re.compile(r'Ãu'), 'ñu'),
    (re.compile(r'Ã([íe])'), r'ñ\1'),
    # Ãn at word end (no following vowel) -> ón
    (re.compile(r'Ãn\b'), 'ón'),
    # consonant + Ã + consonant (mid-word) -> common heuristic: usually í
    (re.compile(r'([bcdfghjklmnpqrstvwxyz])Ã([bcdfghjklmnpqrstvwxyz])', re.IGNORECASE), r'\1í\2'),
    # Ã$ (end of word) -> é (Café, Paté, Té)
    (re.compile(r'Ã\b'), 'é'),
    # Remaining Ã -> ó (most common Spanish accent)
    (re.compile(r'Ã'), 'ó'),
]


def preserve_case(original: str, fixed: str) -> str:
    """If original starts uppercase, ensure fixed does too."""
    if not original or not fixed:
        return fixed
    if original[0].isupper() and fixed[0].islower():
        return fixed[0].upper() + fixed[1:]
    if original[0].islower() and fixed[0].isupper():
        return fixed[0].lower() + fixed[1:]
    return fixed


def fix_word(w: str) -> tuple[str, bool]:
    """Return (fixed_word, covered_by_dict)."""
    if 'Ã' not in w:
        return w, True
    key = w.lower()
    # try dict lookup (with Ã removed for key? No — key IS the mojibake form)
    if key in MOJIBAKE_DICT:
        return preserve_case(w, MOJIBAKE_DICT[key]), True
    # Apply pattern rules
    fixed = w
    for pat, repl in PATTERN_RULES:
        fixed = pat.sub(repl, fixed)
    # Check if still has mojibake
    return fixed, 'Ã' not in fixed


def fix_name(name: str) -> tuple[str, bool]:
    """Return (fixed_name, fully_fixed)."""
    if 'Ã' not in name:
        return name, True
    parts = re.split(r'(\s+)', name)  # preserve whitespace
    out = []
    all_covered = True
    for p in parts:
        if p.strip() == '':
            out.append(p)
        else:
            # strip leading/trailing punctuation for matching
            lead = re.match(r'^([^\wÃ]*)', p).group(1)
            trail = re.search(r'([^\wÃ%]*)$', p).group(1)
            core = p[len(lead):len(p)-len(trail)] if trail else p[len(lead):]
            fixed_core, covered = fix_word(core)
            if not covered:
                all_covered = False
            out.append(lead + fixed_core + trail)
    return ''.join(out), all_covered and 'Ã' not in ''.join(out)


def main():
    path = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"
    with open(path, 'r', encoding='utf-8') as f:
        raw = f.read()
    outer = json.loads(raw)
    wrapper = json.loads(outer[0]['text'])
    result_str = wrapper['result']
    m = re.search(r'<untrusted-data-[^>]+>\s*(\[[\s\S]*?\])\s*</untrusted-data-', result_str)
    rows = json.loads(m.group(1).strip())

    fully_fixed = []
    partially_fixed = []
    uncovered_words = Counter()

    for r in rows:
        old = r['name']
        new, ok = fix_name(old)
        if ok and new != old:
            fully_fixed.append((r['id'], old, new))
        elif new != old:
            partially_fixed.append((r['id'], old, new))
            # collect uncovered words
            for w in new.split():
                core = re.sub(r'^[^\w]+|[^\w%]+$', '', w, flags=re.UNICODE)
                if 'Ã' in core:
                    uncovered_words[core] += 1
        else:
            # fix_name didn't change anything — should be rare
            for w in old.split():
                core = re.sub(r'^[^\w]+|[^\w%]+$', '', w, flags=re.UNICODE)
                if 'Ã' in core:
                    uncovered_words[core] += 1

    total = len(rows)
    full = len(fully_fixed)
    partial = len(partially_fixed)
    pct = 100.0 * full / total

    print(f"Total mojibake products: {total}")
    print(f"Fully fixed:             {full} ({pct:.2f}%)")
    print(f"Partially fixed:         {partial} ({100.0*partial/total:.2f}%)")
    print(f"Unique words uncovered:  {len(uncovered_words)}")
    print()

    # Show 20 random fully_fixed samples
    random.seed(42)
    sample = random.sample(fully_fixed, min(20, len(fully_fixed))) if fully_fixed else []
    print("=== 20 AMOSTRAS ALEATORIAS (fully fixed) ===")
    for i, (pid, old, new) in enumerate(sample, 1):
        line = f"{i:2d}. OLD: {old}\n    NEW: {new}\n\n"
        sys.stdout.buffer.write(line.encode('utf-8'))

    # Show 5 partially fixed samples
    if partially_fixed:
        print("=== 5 AMOSTRAS PARCIAIS (ainda têm Ã residual) ===")
        for i, (pid, old, new) in enumerate(partially_fixed[:5], 1):
            line = f"{i}. OLD: {old}\n   NEW: {new}\n\n"
            sys.stdout.buffer.write(line.encode('utf-8'))

    # Top uncovered words
    print("=== TOP 40 PALAVRAS NÃO COBERTAS ===")
    for w, n in uncovered_words.most_common(40):
        line = f"{n:4d}  {w}\n"
        sys.stdout.buffer.write(line.encode('utf-8'))

    # Save the mapping for later use
    out_dir = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports"
    with open(os.path.join(out_dir, "mercadona_encoding_fixes.json"), 'w', encoding='utf-8') as f:
        json.dump(
            [{"id": p, "old": o, "new": n, "status": "full"} for p, o, n in fully_fixed]
            + [{"id": p, "old": o, "new": n, "status": "partial"} for p, o, n in partially_fixed],
            f, ensure_ascii=False, indent=2,
        )
    with open(os.path.join(out_dir, "mercadona_uncovered_words.json"), 'w', encoding='utf-8') as f:
        json.dump(uncovered_words.most_common(), f, ensure_ascii=False, indent=2)
    print(f"\nSaved fixes + uncovered lists to {out_dir}")


if __name__ == "__main__":
    main()
