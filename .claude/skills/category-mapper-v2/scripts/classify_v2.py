#!/usr/bin/env python3
"""
classify_v2.py — Classificador determinista de produtos em 22 categorias canónicas.

Uso programático:
    from classify_v2 import Classifier
    c = Classifier()
    cat, kw, conf = c.classify("Frango do campo 1kg")
    # → ("Talho", "frango", 1.0)

Uso CLI (stdin JSON array):
    echo '[{"id":"x","name":"Vinho tinto","taxonomy_section":"Outros"}]' | python classify_v2.py
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from typing import Iterable, Optional, Tuple


CANONICAL_22 = [
    "Frutas & Legumes", "Talho", "Peixaria", "Charcutaria & Queijos",
    "Padaria & Pastelaria", "Laticínios & Ovos", "Mercearia", "Congelados",
    "Pronto a Comer", "Bebidas", "Higiene Pessoal", "Higiene do Lar",
    "Animais", "Bebé", "Bio & Saudável", "Fitness & Proteínas",
    "Saúde & Bem-Estar", "Festa & Ocasiões", "Snacks", "Pequenos-Almoços",
    "Conservas", "Vinhos & Espirituosas",
]

PRECEDENCE = [
    "Congelados",
    "Bebé",
    "Animais",
    "Vinhos & Espirituosas",
    "Fitness & Proteínas",
    "Charcutaria & Queijos",
    "Conservas",
    "Bebidas",
    "Snacks",
    "Pequenos-Almoços",
    "Padaria & Pastelaria",
    "Peixaria",
    "Talho",
    "Laticínios & Ovos",
    "Frutas & Legumes",
    "Pronto a Comer",
    "Mercearia",
    "Saúde & Bem-Estar",
    "Higiene Pessoal",
    "Higiene do Lar",
    "Festa & Ocasiões",
    "Bio & Saudável",
]

# Keywords PT + ES + EN + FR. Total > 500. Case-insensitive + accent-insensitive.
KEYWORDS: dict[str, list[str]] = {
    "Congelados": [
        "congelad", "congelado", "congelada", "congelados", "congeladas",
        "frozen", "helado", "helados", "ice cream", "gelado", "gelados",
        "surgele", "surgeles", "surgelati", "pizza congelada",
        "nuggets congelados", "batata congelada", "peixe congelado",
        "vegetais congelados", "espinafre congelado", "legumes congelados",
    ],
    "Bebé": [
        "fralda", "fraldas", "panal", "panales", "diaper", "diapers",
        "biberao", "biberon", "biberone", "tetina", "tetinas",
        "chupeta", "chupetas", "chupete",
        "papinha", "papinhas", "papilla", "papillas",
        "bebe", "baby", "infantil", "infant",
        "pampers", "dodot", "huggies",
        "nan", "aptamil", "nidina", "hero baby", "bledine",
        "mustela", "johnson baby", "nestum", "nestle baby", "nutriben",
        "toalhitas bebe", "toalhetes bebe", "leite infantil",
    ],
    "Animais": [
        "racao", "racoes", "friskies", "whiskas", "felix", "purina",
        "pedigree", "chappi", "frolic", "sheba", "affinity",
        "cat food", "dog food", "pet food", "petfood",
        "alimento para gato", "alimento para cao",
        "comida gato", "comida cao", "comida humida para",
        "para cao", "para gato", "para caes", "para gatos",
        "snack cao", "snacks cao", "snack gato", "snacks gato",
        "saquetas gato", "saquetas cao",
        "bife cao", "bife gato",
        "cao adulto", "cao filhote", "cao mini", "cao maxi",
        "cao medio", "cao mediano", "gato adulto", "gato castrado",
        "perro", "canino", "felino",
        "aquario", "terrario", "passaro", "passaros",
        "roedor", "hamster", "coelho de estima", "pet shop",
        "areia gato", "arena gato", "cama gato", "cama cao",
        "coleira", "trela", "brinquedo gato", "brinquedo cao",
        "veterinario", "veterinaria",
    ],
    "Vinhos & Espirituosas": [
        "vinho", "vinhos", "vino", "vinos", "wine", "wines",
        "vin ", "vins", "vino tinto",
        "tinto", "branco seco", "rose ", "vinho verde",
        "espumante", "espumantes", "champagne", "cava",
        "prosecco", "cerveja", "cervejas", "cerveza", "cervezas",
        "beer", "beers", "biere", "bieres", "ale", "lager",
        "vodka", "whisky", "whiskey", "scotch", "bourbon",
        "gin", "rum", "ron", "licor", "licores", "liqueur",
        "porto", "vinho do porto", "moscatel",
        "aguardente", "brandy", "tequila", "vermute",
        "absinto", "pisco", "sake", "sangria", "cidra", "sidra",
        "hidromel", "calvados",
    ],
    "Fitness & Proteínas": [
        "proteina", "proteinas", "protein", "whey", "caseina",
        "creatina", "creatine", "bcaa", "eaa",
        "pre-workout", "pre workout", "pre treino",
        "gainer", "mass gainer",
        "barra proteica", "barra proteina", "barras proteicas",
        "protein bar", "protein bars",
        "prozis", "myprotein", "scitec", "optimum nutrition",
        "grenade", "quest bar", "fitness",
    ],
    "Charcutaria & Queijos": [
        "fiambre", "chourico", "chorizo", "salpicao", "paio",
        "presunto", "jamon", "jamón",
        "mortadela", "bacon", "salame", "salami",
        "pepperoni", "morcela", "alheira",
        "farinheira", "linguica",
        "queijo", "queijos", "queso", "quesos",
        "cheese", "cheeses", "fromage", "fromages", "formaggio",
        "feta", "mozzarella", "ricotta", "camembert", "brie",
        "parmigiano", "parmesao", "cheddar", "requeijao",
        "gorgonzola", "emmental", "gruyere", "gouda", "edam",
        "manchego", "mascarpone", "philadelphia", "rouladen",
    ],
    "Conservas": [
        "conserva", "conservas", "enlatado", "enlatados", "canned",
        "lata de ", "em lata", "na lata",
        "atum em ", "atum lata", "sardinhas em conserva",
        "cavala em ", "tomate pelado", "polpa de tomate",
        "milho enlatado", "milho doce lata",
        "grao em conserva", "feijao em conserva",
        "cogumelos em conserva", "ervilhas em conserva",
        "azeitona", "azeitonas", "pate", "pates",
        "anchova", "anchovas", "mexilhao em conserva",
    ],
    "Snacks": [
        "snack", "snacks", "batata frita", "batatas fritas",
        "chips", "crisps", "pipoca", "pipocas", "popcorn",
        "bolacha", "bolachas", "biscoito", "biscoitos",
        "biscuit", "biscuits", "cookie", "cookies",
        "galleta", "galletas",
        "belvita", "oreo", "pringles", "lays", "doritos", "cheetos",
        "tostitos", "tuc", "digestive", "bolacha maria",
        "mikado", "kitkat", "kit kat", "m&m", "twix", "snickers",
        "bounty", "milky way", "amendoim", "cajus", "frutos secos",
    ],
    "Pequenos-Almoços": [
        "cereal", "cereais", "cereales", "granola", "muesli",
        "aveia", "oats", "flocos de aveia",
        "cornflakes", "corn flakes", "kellogg", "nesquik",
        "choco krispies", "cheerios", "chocapic", "estrelitas",
        "crispy", "crosti", "trigo tufado",
        "torrada", "torradas", "tostas", "pao de forma",
        "mel ", "honey", "miel", "manuka",
        "compota", "compotas", "doce de fruta",
        "jam", "jams", "confiture", "marmelada", "geleia",
    ],
    "Padaria & Pastelaria": [
        "pao", "paes", "bread", "pain", "baguette", "baguete",
        "bolo", "bolos", "cake", "cakes", "gateau", "gateaux",
        "pastel", "pasteis", "pastries",
        "tarte", "tartes", "tarta", "pie", "pies",
        "croissant", "croissants", "brioche",
        "massa folhada", "massa quebrada", "massa tenra",
        "pao ralado", "broa", "regueifa",
        "folar", "bolo-rei", "bolo rei", "rabanada", "rabanadas",
        "tortas", "queque", "queques", "donut", "donuts",
    ],
    "Peixaria": [
        "peixe", "peixes", "pescado", "pescados", "fish", "poisson",
        "bacalhau", "bacalao", "cod",
        "salmao", "salmon", "saumon",
        "atum fresco", "atum posta",
        "camarao", "camaroes", "gambas", "gamba", "langostinos",
        "lula", "lulas", "squid", "polvo", "pulpo", "octopus",
        "pescada", "pescadinha", "dourada", "robalo",
        "sardinha fresca", "sardinhas frescas", "sardina",
        "linguado", "sargo", "carapau", "cavala fresca",
        "marisco", "ameijoa", "amejoa", "mexilhao", "berbigao",
        "ostra", "lagostim", "choco", "maruca",
    ],
    "Talho": [
        "frango", "pollo", "chicken", "poulet", "volaille",
        "carne ", "meat", "viande",
        "bife", "bifes", "steak", "steaks",
        "peru", "pavo", "turkey", "dinde",
        "borrego", "cordero", "lamb",
        "vitela", "ternera", "veau",
        "porco", "cerdo", "pork", "porc",
        "hamburger", "hamburguer", "hamburguesa",
        "almondega", "almondegas", "meatball",
        "salsicha fresca", "salsichas frescas",
        "figado", "higado", "liver",
        "costeleta", "costeletas", "costela", "entrecosto",
        "lombo", "file ", "filete", "picanha",
        "coelho", "rabbit", "lapin",
    ],
    "Laticínios & Ovos": [
        "leite", "leches", "leche", "milk", "lait", "latte",
        "iogurte", "iogurtes", "yogur", "yoghurt", "yogurt", "yaourt",
        "natas", "nata ", "cream", "creme de leite", "creme para cozinhar",
        "creme de natas", "creme fresco", "nata liquida",
        "manteiga", "mantequilla", "butter", "beurre",
        "ovo", "ovos", "huevo", "huevos", "egg", "eggs",
        "oeuf", "oeufs",
        "requeijao", "skyr", "kefir",
        "petit suisse", "petit-suisse",
        "sobremesa lactea", "danone", "actimel", "yoplait",
        "activia", "oikos", "danete",
        "margarina", "margarine",
    ],
    "Frutas & Legumes": [
        "fruta", "frutas", "fruit", "fruits",
        "maca ", "macas ", "pera", "peras", "banana", "bananas",
        "laranja", "laranjas", "limao", "limoes", "limon",
        "manga", "mangas", "kiwi", "kiwis",
        "uva", "uvas", "morango", "morangos",
        "melao", "melancia", "ananas", "pina", "pineapple",
        "pessego", "pessegos", "nectarina", "alperce",
        "cereja", "cerejas", "ameixa", "ameixas",
        "framboesa", "mirtilo",
        "tomate", "tomates", "alface", "alfaces",
        "cenoura", "cenouras", "batata", "batatas", "potato",
        "cebola", "cebolas", "onion", "alho", "alhos", "garlic",
        "pepino", "cucumber", "courgette", "abobrinha", "abobora",
        "pimento", "pimentos", "pepper", "couve", "couves",
        "brocolos", "brocolo", "espinafre", "espinafres",
        "legume", "legumes", "verdura", "verduras", "horticola",
        "salsa", "coentros", "hortela", "manjericao",
        "cogumelo", "cogumelos", "mushroom", "champignon",
        "aipo", "funcho", "beterraba", "rabano", "nabo",
        "bolsa de fruta", "bolsas de fruta", "pure de fruta",
        "fruta fresca", "fruta variada",
    ],
    "Pronto a Comer": [
        "pronto a comer", "pronto consumo", "ready meal", "ready to eat",
        "lasanha pronta", "lasagne",
        "sushi", "take away", "takeaway",
        "sandwich", "sanduiche", "sandes", "wrap", "wraps",
        "quiche", "empanada", "pizza fresca", "salada pronta",
        "tortilha pronta",
    ],
    "Mercearia": [
        "arroz", "rice", "riz",
        "massa ", "massas", "pasta", "pastas",
        "esparguete", "spaghetti", "macarrao", "noodles",
        "penne", "fusilli", "lasagna", "gnocchi",
        "feijao", "feijoes", "frijol", "beans",
        "grao ", "graos ", "chickpea", "lentilha", "lentilhas",
        "lentil", "lentils",
        "farinha", "farinhas", "flour", "harina", "harinas",
        "acucar", "azucar", "sugar", "sucre",
        "sal ", "salt", "sel ",
        "azeite", "aceite", "oil", "olio", "oleo ",
        "vinagre", "vinegar", "vinaigre",
        "molho", "molhos", "sauce", "sauces",
        "ketchup", "maionese", "mayonnaise", "mostarda", "mustard",
        "caldo", "tempero", "temperos", "especiaria", "especiarias",
        "spice", "spices", "pimenta", "piri piri",
        "oregao", "oregano", "manjericao", "canela",
        "fermento", "levedura",
    ],
    "Bebidas": [
        "agua", "water", "eau",
        "sumo", "sumos", "zumo", "zumos", "juice", "juices", "jus",
        "nectar",
        "refrigerante", "refrigerantes", "refresco", "refrescos",
        "soda",
        "coca cola", "coca-cola", "pepsi", "fanta", "sprite",
        "schweppes", "7up",
        "ice tea", "iced tea", "cha ", "tea", "the ",
        "cafe", "coffee", "cafes", "nescafe", "instant coffee",
        "gatorade", "powerade", "red bull", "energy drink",
        "bebida energetica",
        "kombucha", "bebida vegetal", "leite de aveia",
        "leite de soja", "bebida de amendoa", "almond milk",
        "oat milk", "soy milk", "cha fermentado", "cha frio",
        "smoothie", "smoothies", "iogurte liquido",
    ],
    "Saúde & Bem-Estar": [
        "vitamina", "vitaminas", "vitamin", "vitamins",
        "suplemento", "suplementos", "supplement",
        "multivitaminico", "multivitamin",
        "omega", "magnesio", "magnesium", "zinco", "zinc",
        "iron", "ferro", "colageno", "collagen",
        "probiotico", "probiotics", "calcium", "calcio",
        "aspirina", "aspirin", "paracetamol", "ibuprofeno",
        "antiacido", "antacid",
        "pensos", "penso rapido", "band aid", "bandaid",
        "desinfetante ferida", "betadine",
        "xarope", "xarope tosse", "pastilhas tosse",
        "termometro", "termómetro",
    ],
    "Higiene Pessoal": [
        "champo", "champos", "shampoo", "shampoos", "champu",
        "shampooing",
        "gel duche", "gel de duche", "shower gel", "gel douche",
        "sabonete", "sabonetes", "soap", "jabon", "jabones", "savon",
        "desodorizante", "desodorante", "deodorant", "deodorant",
        "pasta de dentes", "pasta dentes", "toothpaste",
        "dentifrico", "dentifrice",
        "escova de dentes", "escova dentes", "toothbrush",
        "fio dental",
        "creme hidratante", "creme de rosto", "creme rosto", "creme facial",
        "creme corpo", "creme maos", "creme anti-rugas", "creme antirugas",
        "creme olhos", "creme solar", "body lotion", "body milk",
        "perfume", "perfumes", "eau de toilette", "eau de parfum",
        "colonia", "colonias",
        "maquilhagem", "maquillaje", "makeup", "make up",
        "base maquilhagem", "batom", "rimmel", "mascara",
        "esmalte", "esmaltes", "unhas",
        "penso higienico", "pensos higienicos", "tampao",
        "tampoes", "compressa",
        "papel higienico", "toilet paper",
        "creme barbear", "aftershave", "after shave",
        "laminas", "laminas barbear", "shaving",
        "dove", "nivea", "rexona", "axe", "old spice",
        "elixir bucal", "elixir", "enxaguante", "enxaguante bucal",
        "colutorio", "gel bucal", "cuidado bucal",
    ],
    "Higiene do Lar": [
        "detergente", "detergentes", "detergent", "detergente loica",
        "detergente roupa",
        "lava-louca", "lava louca", "dishwasher", "lavavajillas",
        "amaciador", "softener", "suavizante",
        "limpa-vidros", "limpa vidros", "limpa chao",
        "limpa-chao", "limpa tudo",
        "desinfetante", "disinfectant",
        "lixivia", "bleach", "lejia",
        "esponja", "esponjas", "sponge",
        "rolo cozinha", "papel cozinha", "kitchen towel",
        "sacos lixo", "sacos do lixo", "trash bags",
        "vassoura", "esfregona", "esfregao", "esfregoes", "mop",
        "pano microfibra", "panos microfibra", "pano limpeza",
        "panos limpeza", "pano de cozinha", "panos de cozinha",
        "ambientador", "ambientadores", "air freshener",
        "fairy", "skip", "ariel", "calgon", "surf", "persil",
        "cif", "ajax", "pato ", "mr musculo", "vim",
    ],
    "Festa & Ocasiões": [
        "festa", "festas", "party",
        "aniversario", "aniversarios", "birthday",
        "decoracao", "decoracoes", "decoration",
        "natal", "christmas", "natalicio",
        "pascoa", "easter", "halloween",
        "velas", "candle", "candles",
        "baloes", "ballons", "balloons",
        "pifanias", "rei ", "coroa", "presepio",
        "arvore de natal", "bolo-rei", "ovos de pascoa",
        "amendoas de pascoa",
    ],
    "Bio & Saudável": [
        "bio ", " bio", "organico", "organicos", "organic",
        "ecologico", "eco-",
        "sem gluten", "gluten free", "gluten-free",
        "vegan", "vegano", "vegana", "plant based", "plant-based",
        "celiaco", "celiaca", "integral", "wholefood",
        "natural ", "superfood", "superalimento",
        "sem lactose", "lactose free", "sem acucar adicionado",
        "no added sugar",
    ],
}


def _normalize(text: Optional[str]) -> str:
    """Lower + strip accents + collapse whitespace. Safe for None."""
    if not text:
        return ""
    text = text.lower()
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"\s+", " ", text).strip()
    return text


class Classifier:
    """
    Matching = word-boundary + prefix (`\\bkw\\w*`). Evita falsos positivos como:
        - "uvas" dentro de "luvas"
        - "alho" dentro de "trabalho"
        - "cao" dentro de "caos"
    E permite matches com flexão:
        - keyword "congelad" → apanha congelado/congelada/congelados
    """
    def __init__(self) -> None:
        self._compiled: dict[str, list[Tuple[str, re.Pattern[str]]]] = {}
        for cat, words in KEYWORDS.items():
            seen = set()
            entries = []
            for w in words:
                n = _normalize(w)
                if not n or n in seen:
                    continue
                seen.add(n)
                # length-based matching:
                #   ≤4 chars  → strict word-boundary on both sides (evita "maca" em "macarico")
                #   ≥5 chars  → prefix/stem-match (apanha plural/flexões)
                if len(n) <= 4:
                    pat = re.compile(r"\b" + re.escape(n) + r"\b", re.IGNORECASE)
                else:
                    pat = re.compile(r"\b" + re.escape(n) + r"\w*", re.IGNORECASE)
                entries.append((n, pat))
            # keywords mais longas primeiro (specificity)
            entries.sort(key=lambda e: len(e[0]), reverse=True)
            self._compiled[cat] = entries
        for cat in CANONICAL_22:
            self._compiled.setdefault(cat, [])

    def classify(
        self,
        name: Optional[str],
        category_root: Optional[str] = None,
    ) -> Tuple[str, str, float]:
        haystack = _normalize(f"{name or ''} {category_root or ''}")
        if not haystack:
            return ("Outros", "", 0.0)
        for cat in PRECEDENCE:
            for kw, pat in self._compiled.get(cat, []):
                if pat.search(haystack):
                    conf = 1.0 if len(kw) >= 5 else 0.7
                    return (cat, kw, conf)
        return ("Outros", "", 0.0)

    def classify_batch(self, products: Iterable[dict]) -> list[dict]:
        out = []
        for p in products:
            cat, kw, conf = self.classify(p.get("name"), p.get("category_root"))
            old = p.get("taxonomy_section") or ""
            out.append({
                "id": p.get("id"),
                "name": p.get("name"),
                "old": old or "(null)",
                "new": cat,
                "matched": kw,
                "confidence": conf,
                "needs_review": conf < 0.7,
                "changed": old != cat,
            })
        return out

    @staticmethod
    def keyword_count() -> int:
        return sum(len(v) for v in KEYWORDS.values())


def main() -> None:
    data = json.load(sys.stdin)
    c = Classifier()
    json.dump(c.classify_batch(data), sys.stdout, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
