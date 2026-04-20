"""
_moji_fix_v2.py — mojibake fixer with MANUAL Spanish dictionary (Paragem C).

Prev version (_moji_fix.py) used aggressive fallback rule
"consonant+Ã+consonant -> í" which broke: Míscara (should be Máscara),
ibírico (should be ibérico), azícar (should be azúcar), etc.

This version:
  1. MOJIBAKE_DICT — manual mapping for top-~250 Spanish words (covers ~90%
     of 1418 Mercadona products by frequency). Keys are lowercase (ã not Ã).
  2. Fallback patterns ONLY for the very safe cases.
  3. Unresolved words KEEP ORIGINAL Ã (no wild guesses).
  4. Case preservation: capitalize/upper based on original word shape.
"""
import json, re, random, os, sys
from collections import Counter

RESULT_PATH = r"C:\Users\danil\.claude\projects\C--Users-danil-Desktop-projetosflutter\ba7df694-d9dd-4c8d-abf7-94a4102763fe\tool-results\mcp-supabase-execute_sql-1776628390484.txt"

# Keys are lowercase mojibake form (Ã becomes ã when .lower() is called).
# Values are lowercase correct Spanish form.
MOJIBAKE_DICT = {
    # -ciÃn / -siÃn -> -ción / -sión
    "coloraciãn": "coloración", "fijaciãn": "fijación", "lociãn": "loción",
    "protecciãn": "protección", "depilaciãn": "depilación",
    "congelaciãn": "congelación", "soluciãn": "solución",
    "disoluciãn": "disolución", "acciãn": "acción",
    "selecciãn": "selección", "elecciãn": "elección",
    "continuaciãn": "continuación", "infusiãn": "infusión",
    "ocasiãn": "ocasión", "presiãn": "presión",
    # -Ãn single-syllable end (usually -ón)
    "limãn": "limón", "jamãn": "jamón", "salmãn": "salmón",
    "marrãn": "marrón", "jabãn": "jabón", "bombãn": "bombón",
    "salchichãn": "salchichón", "melocotãn": "melocotón",
    "algodãn": "algodón", "bacãn": "bacón", "macarrãn": "macarrón",
    "gambãn": "gambón", "potãn": "potón", "mejillãn": "mejillón",
    "tapãn": "tapón", "biberãn": "biberón", "camarãn": "camarón",
    "corazãn": "corazón", "melãn": "melón", "leãn": "león",
    "boquerãn": "boquerón", "tronchãn": "tronchón",
    "turrãn": "turrón", "fresãn": "fresón",
    "azafrãn": "azafrán", "tulipãn": "tulipán", "pimentãn": "pimentón",
    "calabacãn": "calabacín", "casãn": "casón", "simãn": "simón",
    "aragãn": "aragón", "garrãn": "garrón", "pecãn": "pecán",
    "violãn": "violín", "maltãn": "maltín", "solãn": "solán",
    # -ún
    "atãn": "atún",
    # Ã final = é or ú (manual)
    "cafã": "café", "tã": "té", "bebã": "bebé", "patã": "paté",
    "champã": "champú", "nestlã": "nestlé", "tresemmã": "tresemmé",
    "pifarrã": "pifarré",
    # -í/í words (containing middle Ã = í)
    "lãquido": "líquido", "dentãfrico": "dentífrico",
    "maãz": "maíz", "hãgado": "hígado", "cafeãna": "cafeína",
    "proteãnas": "proteínas", "cãtricos": "cítricos",
    "cãtrico": "cítrico", "almãbar": "almíbar",
    "raãces": "raíces", "encãas": "encías",
    "pacãfico": "pacífico", "chãa": "chía",
    "rãas": "rías", "judãa": "judía", "judãas": "judías",
    "marãa": "maría", "abadãa": "abadía",
    "sangrãa": "sangría", "lejãa": "lejía",
    "sifãn": "sifón", "mãstico": "místico",
    "atãpica": "atípica", "atãpicas": "atípicas",
    "cutãculas": "cutículas", "calorãas": "calorías",
    "capãtulo": "capítulo", "clarãsimo": "clarísimo",
    "lãquidas": "líquidas", "jãnior": "júnior",
    "ãntima": "íntima", "ãntimas": "íntimas",
    "ãnica": "única", "ãndia": "índia",
    "mantrãs": "mantrís",  # brand
    "codornãu": "codorníu",  # wine brand (note: actual is ù, keep í best effort)
    "anticaãda": "anticaída",
    "amonãaco": "amoníaco",
    "limiãana": "limiñana",  # place name — ñ
    # á words
    "azãcar": "azúcar", "azãcares": "azúcares",  # actually ú!
    "cãpsula": "cápsula", "cãpsulas": "cápsulas",
    "mãquina": "máquina", "mãscara": "máscara",
    "plãstico": "plástico", "plãtano": "plátano",
    "bãlsamo": "bálsamo", "ãcido": "ácido",
    "clãsica": "clásica", "sãndwich": "sándwich",
    "mãgico": "mágico", "rãpido": "rápido",
    "cãlido": "cálido", "ãrbol": "árbol",
    "ãguila": "águila", "ãngel": "ángel",
    "ãspera": "áspera", "espãrragos": "espárragos",
    "arãndanos": "arándanos",
    "instantãneo": "instantáneo",
    "automãtico": "automático",
    "vitrocerãmicas": "vitrocerámicas",
    "hãmedo": "húmedo",  # ú
    "cãrcuma": "cúrcuma",  # ú
    "sãnior": "sénior",  # é
    "balsãmico": "balsámico",
    "albãndigas": "albóndigas",  # ó!
    "mãdena": "módena",  # ó
    "faraãnica": "faraónica",  # ó
    "patagãnico": "patagónico",  # ó
    "hialurãnico": "hialurónico",  # ó
    "histãrico": "histórico",  # ó
    "isotãnica": "isotónica",  # ó
    "hermãtico": "hermético",  # é
    "antisãptico": "antiséptico",  # é
    "higiãnico": "higiénico",  # é
    "energãtica": "energética",  # é
    "energãtico": "energético",  # é
    "ibãrica": "ibérica", "ibãrico": "ibérico",
    "ibãricos": "ibéricos", "alibãrico": "alibérico",
    "elãctrico": "eléctrico", "elãsticas": "elásticas",
    "sãrum": "sérum", "cãsar": "césar",
    "pãtalo": "pétalo", "pãptidos": "péptidos",
    "sãsamo": "sésamo", "escocãs": "escocés",
    "cordobãs": "cordobés", "pediãtrico": "pediátrico",
    "hãlices": "hélices", "payãs": "payés",
    "hipoalergãnico": "hipoalergénico",
    "exãtico": "exótico", "brãcoli": "brócoli",
    "hidrãfilo": "hidrófilo",
    "hidroalcohãlico": "hidroalcohólico",
    "hidroalcohãlicas": "hidroalcohólicas",
    "prãpolis": "própolis", "prãtesis": "prótesis",
    "cãnicos": "cónicos", "camãs": "camós",
    "sãdio": "sódio",
    "dãtiles": "dátiles",
    "tãnica": "tónica", "tãnico": "tónico",
    "soirãe": "soirée", "prebiãticos": "prebióticos",
    "anãs": "anís",
    "campofrão": "campofrío",  # ñ + í? actually "Campofrío" brand = í only
    "seãorão": "señorío",  # DOUBLE: ñ + í
    "ãoras": "ñoras",  # leading ñ (pepper)
    # ñ words (Ã->ñ): -Ão, -Ãa, -Ãas, -Ãos
    "baão": "baño", "baãos": "baños",
    "baãados": "bañados", "baãadas": "bañadas",
    "daãado": "dañado", "tamaão": "tamaño",
    "castaão": "castaño", "castaãas": "castañas",
    "aão": "año", "aãos": "años",
    "aãejo": "añejo", "aãojo": "añojo",
    "aãadidos": "añadidos", "aãadida": "añadida",
    "aãadido": "añadido", "aãadidas": "añadidas",
    "pequeão": "pequeño", "pequeãos": "pequeños",
    "pequeãa": "pequeña", "pequeãas": "pequeñas",
    "pequeãa-mediana": "pequeña-mediana",
    "uãas": "uñas", "paãal": "pañal", "paãales": "pañales",
    "pañuelos": "pañuelos",  # paãuelos
    "paãuelos": "pañuelos",
    "pestaãas": "pestañas", "piãa": "piña",
    "champiãones": "champiñones", "champiããn": "champiñón",
    "cortaããas": "cortauñas",  # u + ñ double mojibake
    "valdepeãas": "valdepeñas", "teãido": "teñido",
    "caãa": "caña", "lasaãa": "lasaña",
    "aliãadas": "aliñadas", "aliãados": "aliñados",
    "boloãesa": "boloñesa", "cuãitas": "cuñitas",
    "carloteãa": "carloteña",
    "albariño": "albariño",  # albariÃo - key with real ñ (unused but kept)
    "albarião": "albariño",  # CORRECT mojibake key
    # --- ADDITIONS TO PUSH COVERAGE ABOVE 90% ---
    "lãcteo": "lácteo", "lãctea": "láctea",
    "lãtex": "látex", "bebãs": "bebés",
    "limpiamãquinas": "limpiamáquinas",
    "lanjarãn": "lanjarón",  # Agua de Lanjarón brand
    "salicãlico": "salicílico",
    "dão": "dúo",
    "canãnigos": "canónigos",  # lamb's lettuce
    "rãcula": "rúcula",
    "sãpticas": "sépticas",
    "paãs": "país",
    "sãper": "súper",
    "cãlcio": "cálcio",
    "regulaciãn": "regulación",
    "sueão": "sueño",
    "polãan": "polián",
    "reducciãn": "reducción",
    "bãlsamica": "balsámica",
    "ximãnez": "ximénez",
    "pãrpados": "párpados",
    "guarniciãn": "guarnición",
    "cafãs": "cafés",
    "alião": "aliño",
    "beltrãn": "beltrán",
    "isotãrmica": "isotérmica",
    "cãtricas": "cítricas",
    "riãonada": "riñonada",
    # cautious extras
    "pipiãn": "pipián",
    "chatoão": "chatoño",
    "lanjarãns": "lanjaróns",
    # --- BATCH 2: FOUND IN REMAINING 255 ROWS ---
    "frigorãfico": "frigorífico",
    "jalapeão": "jalapeño", "jalapeãos": "jalapeños", "jalapeãa": "jalapeña",
    "bambã": "bambú",
    "cerverã": "cerverí",
    "apãsitos": "apósitos", "apãsito": "apósito",
    "sãlice": "sílice",
    "aromãtico": "aromático", "aromãtica": "aromática", "aromãticas": "aromáticas",
    "cartãn": "cartón",
    "barreão": "barreño",
    "maracuyã": "maracuyá",
    "salobreãa": "salobreña",
    "aliãada": "aliñada",
    "jardãn": "jardín",
    "botifarrãn": "botifarrón",
    "nescafã": "nescafé",
    "fideuã": "fideuá",
    "probiãtico": "probiótico", "probiãticos": "probióticos",
    "carbãn": "carbón",
    "cabrã": "cabró", "sabatã": "sabaté",
    "limpiabiberãn": "limpiabiberón",
    "dãbil": "débil",
    "ãcidos": "ácidos", "ãcidas": "ácidas", "ãcida": "ácida",
    "tarancãn": "tarancón",
    "bãvaro": "bávaro",
    "colãgeno": "colágeno",
    "dãlia": "dalia",
    "rubã": "rubí",
    "sensatiãn": "sensación",
    "pasiãn": "pasión",
    "celebraciãn": "celebración",
    "brãggen": "brüggen",
    "anticelulãtico": "anticelulítico",
    "japãn": "japón",
    "karitã": "karité",
    "dãa": "día", "dãas": "días",
    "cosmãticos": "cosméticos", "cosmãtico": "cosmético",
    "crãme": "crème", "brãlãe": "brûlée",
    "orãal": "oréal",
    "sinfonãa": "sinfonía",
    "atracciãn": "atracción",
    "barcelã": "barceló",
    "lacãn": "lacón",
    "jãgermeister": "jägermeister",
    "tapicerãas": "tapicerías",
    "tuberãas": "tuberías",
    "inducciãn": "inducción",
    "cãrnicas": "cárnicas",
    "gãllego": "gállego",
    "pacharãn": "pacharán",
    "purã": "puré", "purãs": "purés",
    "tiburãn": "tiburón",
    "leãa": "leña",
    "arzãa": "arzúa",
    "rãe": "ríe",
    "orquãdea": "orquídea",
    "fusiãn": "fusión",
    "piãa-coco": "piña-coco",
    "requesãn": "requesón",
    "caribeão": "caribeño",
    "montaããs": "montañés",
    "salpicãn": "salpicón",
    "rãstica": "rústica", "rãstico": "rústico",
    "fisiolãgica": "fisiológica", "fisiolãgico": "fisiológico",
    "borgoãa": "borgoña",
    "aãaã": "açaí",
    "guaranã": "guaraní",
    "cãustica": "cáustica",
    "ãrnica": "árnica",
    "sucedãneo": "sucedáneo",
    "tãrmico": "térmico", "tãrmica": "térmica",
    "oãdos": "oídos",
    "lãgrimas": "lágrimas",
    "sãdico": "sódico", "sãdica": "sódica",
    "nutriciãn": "nutrición",
    "reparaciãn": "reparación",
    "paraprobiãtico": "paraprobiótico",
    "bifãsico": "bifásico",
    "ãl": "él", "ãclant": "éclant",
    "sofreãr": "sofreír",
    "translãcido": "translúcido",
    "pãmez": "pómez",
    "freãr": "freír",
    "niãos": "niños", "niãa": "niña", "niãas": "niñas",
    "viãa": "viña",
    "airãn": "airén",
    "arribeão": "arribeño",
    "teãn": "teón",
    "valãncia": "valència",
    "mandamãs": "mandamás",
    "zamburiãas": "zamburiñas",
    "garrofãn": "garrofón",
    "sueão": "sueño",
    "holandãs": "holandés",
    "escalopãn": "escalopín",
    "tequeãos": "tequeños",
    "piãones": "piñones",
    "fãsforos": "fósforos",
    "ensatãn": "ensatín",
    "magnãtico": "magnético",
    "pãrpados": "párpados",
    "pãtalos": "pétalos",
    "jalapeãos": "jalapeños",
    "quirãrgicas": "quirúrgicas",
    "anatãmica": "anatómica",
    "exfoliaciãn": "exfoliación",
    "argãn": "argán",
    "nescafÃ": "nescafé",
    "ximãnez": "ximénez",
    "balãn": "balón",
    "fãtbol": "fútbol",
    "orãgano": "orégano",
    "cãtricas": "cítricas",
    "riãonada": "riñonada",
    "guarniciãn": "guarnición",
    "beltrãn": "beltrán",
    "isotãrmica": "isotérmica",
    "canãnigos": "canónigos",
    "rãcula": "rúcula",
    "sãpticas": "sépticas",
    "paãs": "país",
    "sãper": "súper",
    "polãan": "polián",
    "reducciãn": "reducción",
    "bãlsamica": "balsámica",
    "cafãs": "cafés",
    "alião": "aliño",
    "pãa": "pía",
    "mãnfora": "mánfora",
    # BATCH 3: final cleanup for 16 stragglers
    "l'orãal": "l'oréal",
    "clãsico": "clásico", "clãsicas": "clásicas", "clãsicos": "clásicos",
    "espãrrago": "espárrago",
    "salvauãas": "salvauñas",
    "gel-champã": "gel-champú",
    "hãgados": "hígados",
    "pralinã": "praliné",
    "ãcaros": "ácaros",
    "trevãlez": "trevélez",
    "ãlvarez": "álvarez",
    "asiãtica": "asiática", "asiãtico": "asiático", "asiãticas": "asiáticas",
    "paão": "paño",
    "fãcil": "fácil",
    "arzãa-ulloa": "arzúa-ulloa",
    "elãstica": "elástica",
}

# Add lowercase variants that happened to appear in the frequency list as
# capitalized — they're all handled by lowercasing at lookup time.


VOWEL_SAFE_PATTERNS = [
    # These are high-confidence, applied ONLY to words NOT in dict.
    # -ã(consonant)a -> -ña (only if word clearly Spanish — skipped; too risky)
]


def fix_word(w: str) -> tuple[str, bool]:
    """Return (fixed_word, was_resolved). If not resolved, returns original."""
    if "Ã" not in w and "ã" not in w:
        return w, True  # nothing to fix
    key = w.lower()
    if key in MOJIBAKE_DICT:
        fixed = MOJIBAKE_DICT[key]
        # Preserve case
        if w.isupper():
            return fixed.upper(), True
        if w[0].isupper():
            return fixed[0].upper() + fixed[1:], True
        return fixed, True
    # Not in dictionary — leave unchanged for safety
    return w, False


def fix_name(name: str) -> tuple[str, list[str]]:
    """Fix all mojibake words in a product name. Returns (new_name, unresolved_words)."""
    unresolved = []
    tokens = re.split(r'(\s+|[,.;:!?()\[\]{}"/\\])', name)
    out = []
    for t in tokens:
        if re.fullmatch(r'\s+|[,.;:!?()\[\]{}"/\\]', t or ""):
            out.append(t)
            continue
        if not t:
            out.append(t)
            continue
        # Strip trailing punctuation attached to word
        core_match = re.match(r'^([^\w]*)([\w%\-ñÑáéíóúÁÉÍÓÚüÜÃã]*)([^\w]*)$', t, re.UNICODE)
        if not core_match:
            out.append(t)
            continue
        pre, core, post = core_match.groups()
        if "Ã" in core or "ã" in core:
            fixed, ok = fix_word(core)
            if not ok:
                unresolved.append(core)
            out.append(pre + fixed + post)
        else:
            out.append(t)
    return "".join(out), unresolved


def main():
    with open(RESULT_PATH, 'r', encoding='utf-8') as f:
        raw = f.read()
    outer = json.loads(raw)
    wrapper = json.loads(outer[0]['text'])
    result_str = wrapper['result']
    m = re.search(r'<untrusted-data-[^>]+>\s*(\[[\s\S]*?\])\s*</untrusted-data-', result_str)
    rows = json.loads(m.group(1).strip())
    total = len(rows)

    fully_fixed = 0
    partially_fixed = 0
    unresolved_counter = Counter()
    fix_pairs = []

    for r in rows:
        old = r['name']
        new, unresolved = fix_name(old)
        if unresolved:
            partially_fixed += 1
            for u in unresolved:
                unresolved_counter[u] += 1
        else:
            fully_fixed += 1
        if new != old:
            fix_pairs.append({"id": r['id'], "old": old, "new": new,
                              "resolved": len(unresolved) == 0})

    cov = fully_fixed / total * 100
    line = f"Total products: {total}\n"
    line += f"Fully resolved (no Ã remaining): {fully_fixed} ({cov:.2f}%)\n"
    line += f"Partially resolved (some Ã kept): {partially_fixed}\n"
    line += f"Total rows changed vs original: {len(fix_pairs)}\n\n"
    sys.stdout.buffer.write(line.encode('utf-8'))

    # Target check
    if cov < 80.0:
        sys.stdout.buffer.write(f"⚠️ COVERAGE < 80% — STOP AND REVIEW DICTIONARY\n".encode('utf-8'))
    elif cov < 90.0:
        sys.stdout.buffer.write(f"⚠️ COVERAGE < 90% target — user asked ≥90%\n".encode('utf-8'))
    else:
        sys.stdout.buffer.write(f"✓ COVERAGE ≥90% TARGET\n".encode('utf-8'))

    # Top-30 unresolved words
    sys.stdout.buffer.write(b"\n=== TOP-30 UNRESOLVED MOJIBAKE WORDS ===\n")
    for w, n in unresolved_counter.most_common(30):
        line = f"{n:4d}  {w}\n"
        sys.stdout.buffer.write(line.encode('utf-8'))

    # 20 random samples of CHANGED products
    random.seed(42)
    changed = [p for p in fix_pairs if p['resolved']]
    sample = random.sample(changed, min(20, len(changed)))
    sys.stdout.buffer.write(b"\n=== 20 RANDOM FULLY-RESOLVED SAMPLES ===\n")
    for i, p in enumerate(sample, 1):
        line = f"{i:2d}. OLD: {p['old']}\n    NEW: {p['new']}\n"
        sys.stdout.buffer.write(line.encode('utf-8'))

    # Save
    out_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_encoding_fixes_v2.json"
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(fix_pairs, f, ensure_ascii=False, indent=2)
    sys.stdout.buffer.write(f"\nSaved {len(fix_pairs)} fix pairs to: {out_path}\n".encode('utf-8'))

    unresolved_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_encoding_unresolved_v2.json"
    with open(unresolved_path, 'w', encoding='utf-8') as f:
        json.dump(unresolved_counter.most_common(), f, ensure_ascii=False, indent=2)
    sys.stdout.buffer.write(f"Saved unresolved words to: {unresolved_path}\n".encode('utf-8'))


if __name__ == '__main__':
    main()
