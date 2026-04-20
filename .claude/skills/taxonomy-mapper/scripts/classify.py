#!/usr/bin/env python3
"""
Taxonomy Mapper v2 — Classificador de produtos para 18 secções canónicas Bora.

Estratégia (por precedência):
  1. Pet-context detector (produtos para cão/gato ganham sobre Talho/Peixaria/Mercearia)
  2. Keyword matching em products.name (regras de bora_taxonomy.md)
     — keywords distintivas sobem confidence a 0.88 (no review)
     — multilingue: PT, PT-BR, francês, inglês, espanhol
  3. Root-first fallback: se root_map >= 0.85 e keyword apenas ambígua, root vence
  4. Mapeamento por products.category_root
     — roots "Frescos", "Gastronomia", "Regional", "Casa" → confidence 0 (força LLM)
  5. LLM fallback (claude-haiku-4-5) em batches de 100

Idempotente: corre 2x não muda produtos já com taxonomy_confidence > 0.85.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass, field
from typing import Iterable

try:
    from supabase import create_client  # type: ignore
except ImportError:
    create_client = None

try:
    import anthropic  # type: ignore
except ImportError:
    anthropic = None


# ============================================================================
# 18 SECÇÕES CANÓNICAS
# ============================================================================

SECTIONS = [
    "Padaria & Pastelaria",
    "Frutas & Legumes",
    "Talho",
    "Peixaria",
    "Laticínios & Ovos",
    "Congelados",
    "Mercearia",
    "Bebidas",
    "Bebé",
    "Animais",
    "Higiene Pessoal",
    "Higiene do Lar",
    "Saúde & Bem-Estar",
    "Bio & Saudável",
    "Fitness & Proteínas",
    "Pronto a Comer",
    "Festa & Ocasiões",
    "Outros",
]


# ============================================================================
# PET-CONTEXT DETECTOR (precedência #1 — ganha sobre Talho/Peixaria/Mercearia)
# ============================================================================

PET_CONTEXT = re.compile(
    r"\b(cão|cao|cães|caes|cachorr\w*|gato\w*|felino\w*|canino\w*|pet\b|"
    r"snack[- ]para[- ]c[aã]o|petisco[- ]para[- ]c[aã]o|petisco[- ]para[- ]gato|"
    r"ração|racao|ração[- ]cão|racao[- ]cao|ração[- ]gato|racao[- ]gato|"
    r"royal[- ]canin|whiskas|friskies|felix|purina|pro[- ]plan|hills|"
    r"vitakraft|advance[- ]pet|coleira|trela|areia[- ]gato|tapete[- ]higiénico|"
    r"tapete[- ]higienico|aquário|aquario|gaiola|roedor|hamster|peixe[- ]ornamental)\b",
    re.I,
)


# ============================================================================
# KEYWORDS MULTILINGUE (PT, PT-BR, FR, EN, ES)
# ============================================================================

KEYWORDS: dict[str, list[str]] = {
    "Padaria & Pastelaria": [
        # PT
        "pão", "paozinho", "baguete", "cacete", "papo-seco", "broa", "carcaça",
        "croissant", "pastel de nata", "pastel-de-nata", "pastel de belem",
        "bolo", "queque", "muffin", "donut", "folhado", "torta", "palmier",
        "suspiro", "bolo-rei", "bolo rainha", "mil-folhas", "eclair", "éclair",
        "profiterole", "tarte", "rosquinha",
        # FR
        "pain ", "pain-", "brioche", "gateau", "gâteau", "tartelette",
        # EN
        "bread", "cake", "pastry",
        # ES
        "pan ", "bollo",
    ],
    "Frutas & Legumes": [
        # PT
        "maçã", "pera", "banana", "laranja", "tangerina", "clementina",
        "limão", "limao", "morango", "uva", "kiwi", "manga", "ananás", "ananas",
        "pêssego", "pessego", "nectarina", "ameixa", "cereja", "melancia",
        "melão", "melao", "abacate", "figo", "romã", "framboesa", "mirtilo",
        "amora", "dióspiro", "diospiro", "maracujá", "maracuja",
        "alface", "tomate", "pepino", "cebola", "alho ", "cenoura", "batata ",
        "batata-doce", "abóbora", "abobora", "courgette", "beringela",
        "brócolos", "brocolos", "couve", "couve-flor", "espinafres", "rúcula",
        "rucula", "aipo", "alho-francês", "alho-frances", "beterraba", "nabo",
        "rabanete", "pimento", "pimentão", "pimentao", "ervilha",
        "feijão-verde", "feijao-verde", "cogumelo", "champignon",
        "salsa ", "coentros", "manjericão", "manjericao", "hortelã", "hortela",
        # FR
        "fruit ", "fruits ", "légume", "legume", "pomme ", "poire ", "banane",
        "fraise", "raisin", "pastèque", "pasteque", "carotte", "oignon",
        "courgette", "aubergine", "salade",
        # EN
        "apple", "banana ", "grape", "strawberry", "blueberry", "tomato",
        "lettuce", "broccoli", "onion", "carrot", "potato", "cucumber",
        # ES
        "manzana", "pera ", "plátano", "platano", "fresa", "uva ", "tomate",
        "lechuga", "cebolla", "zanahoria", "patata", "verdura", "fruta",
    ],
    "Talho": [
        # PT
        "carne", "vaca", "vitela", "porco", "leitão", "leitao", "frango",
        "galinha", "peru ", "pato ", "borrego", "cordeiro", "coelho", "cabrito",
        "javali", "veado", "perdiz", "chouriço", "chourico", "salsicha",
        "bacon", "fiambre", "paio", "linguiça", "linguica", "morcela",
        "farinheira", "alheira", "chispe", "presunto", "lombinho", "lombo",
        "costeleta", "bife", "entrecôte", "entrecote", "picanha", "acém",
        "acem", "vazia", "cachaço", "cachaco", "rojões", "rojoes", "febras",
        "secretos", "plumas", "entremeada", "carne-picada", "hambúrguer",
        "hamburguer", "almôndegas", "almondegas", "espetada",
        # FR
        "viande", "boeuf", "bœuf", "poulet", "porc ", "jambon", "saucisse",
        "saucisson", "agneau", "dinde", "lapin", "rillettes", "pâté",
        # EN
        "beef", "pork", "chicken", "turkey", "lamb", "sausage", "ham ",
        # ES
        "carne", "ternera", "cerdo", "pollo", "cordero", "chorizo",
        "salchicha", "jamón", "jamon",
    ],
    "Peixaria": [
        # PT
        "peixe", "peixaria", "bacalhau", "sardinha", "sardinhas", "atum",
        "salmão", "salmao", "dourada", "robalo", "pescada", "tamboril",
        "linguado", "maruca", "cherne", "garoupa", "corvina", "polvo",
        "choco", "lula", "camarão", "camarao", "gamba", "lagostim", "lagosta",
        "caranguejo", "sapateira", "ostra", "mexilhão", "mexilhao", "amêijoa",
        "ameijoa", "berbigão", "berbigao", "vieira", "lingueirão", "lingueirao",
        "percebe", "navalheira", "marisco",
        # FR
        "poisson", "morue", "saumon", "thon", "crevette", "moule ",
        # EN
        "fish ", "cod ", "salmon", "tuna", "shrimp", "prawn", "mussel",
        "seafood",
        # ES
        "pescado", "merluza", "atún", "atun", "salmón", "salmon", "gamba",
        "mariscos", "bacalao",
    ],
    "Laticínios & Ovos": [
        # PT
        "leite", "iogurte", "yogurt", "queijo", "queijinho", "manteiga",
        "margarina", "nata ", "natas", "creme-de-leite", "kefir", "requeijão",
        "requeijao", "mascarpone", "ricota", "mozzarella", "mozarela",
        "cheddar", "gouda", "emmental", "parmesão", "parmesao", "feta",
        "flamengo", "azeitão", "azeitao", "ovo ", "ovos", "clara-de-ovo",
        "quark", "skyr", "pudim",
        # FR
        "lait ", "yaourt", "fromage", "beurre", "crème", "creme-fraiche",
        "œuf", "oeuf", "paturages", "bifidus",
        # EN
        "milk", "yogurt", "cheese", "butter", "cream ", "egg ", "eggs ",
        # ES
        "leche", "yogur", "queso", "mantequilla", "huevo",
    ],
    "Congelados": [
        # Multilingue (precedência absoluta — keyword qualquer ganha)
        "congelad", "gelado", "gelados", "ice-cream", "ice cream", "sorbet",
        "ultracongelad", "frozen", "surgelé", "surgele", "helado",
    ],
    "Mercearia": [
        # PT
        "massa ", "esparguete", "macarrão", "macarrao", "penne", "fusilli",
        "farfalle", "tagliatelle", "arroz", "farinha", "sêmola", "semola",
        "açúcar", "acucar", "sal ", "especiaria", "pimenta", "canela",
        "noz-moscada", "oregãos", "oregaos", "tomilho", "alecrim", "louro",
        "caril", "açafrão", "acafrao", "colorau", "mostarda", "maionese",
        "ketchup", "molho", "azeite", "óleo", "oleo ", "vinagre", "café",
        "cafe", "chá ", "cha ", "cereal", "cereais", "flocos", "granola",
        "aveia", "muesli", "leite-condensado", "bolacha", "biscoito", "snack",
        "batata-frita", "tortilha", "chips ", "chocolate", "tablete", "bombom",
        "bombons", "rebuçado", "rebucado", "gomas", "chiclete", "pastilha",
        "goma ", "conserva", "enlatad", "lata ", "atum-em-lata",
        "sardinha-em-lata", "compota", "geleia", "mel ", "amêndoa", "amendoa",
        "noz ", "avelã", "avela", "caju", "pistáchio", "pistachio", "passas",
        "tâmara", "tamara", "coco ralado", "coco-ralado",
        # FR
        "pasta", "sauce", "riz ", "huile", "vinaigre", "miel", "farine",
        "biscuit", "café", "thé",
        # EN
        "rice", "flour", "sugar", "salt", "honey", "olive oil", "cookie",
        "biscuit",
        # ES
        "aceite", "vinagre", "miel", "arroz", "azúcar", "azucar", "harina",
        "galleta", "café ", "bala ",  # PT-BR "bala" = rebuçado
    ],
    "Bebidas": [
        # PT
        "água", "agua", "sumo", "sumos", "suco ", "néctar", "nectar",
        "refrigerante", "coca-cola", "pepsi", "sprite", "fanta", "7up",
        "ice-tea", "iced-tea", "chá-gelado", "cha-gelado", "red-bull",
        "monster", "bebida-energética", "bebida-energetica", "vinho",
        "tinto ", "branco ", "rosé", "rose ", "vinho-do-porto", "porto ",
        "champanhe", "espumante", "prosecco", "cava ", "cerveja", "cervejas",
        "sagres", "super-bock", "heineken", "budweiser", "corona", "sidra",
        "whisky", "whiskey", "vodka", "gin ", "rum ", "tequila", "bagaço",
        "bagaco", "aguardente", "ginja", "licor", "brandy", "conhaque",
        "cognac", "cápsula", "capsula", "nespresso", "dolce-gusto",
        # FR
        "eau ", "jus ", "vin ", "bière", "biere",
        # EN
        "water", "juice", "wine", "beer", "soda ",
        # ES
        "agua ", "zumo", "vino", "cerveza",
    ],
    "Bebé": [
        # PT
        "fralda-bebé", "fralda-bebe", "fraldas-bebé", "fraldas-bebe",
        "pampers", "dodot", "huggies", "toalhitas-bebé", "toalhitas-bebe",
        "papa ", "papinha", "boião-bebé", "boiao-bebe", "leite-bebé",
        "leite-bebe", "fórmula-infantil", "formula-infantil", "nan ",
        "aptamil", "nestum", "biberão", "biberao", "chupeta", "chucha",
        "babete", "bebé ", "bebe ", "para bebé", "para bebe", "infantil",
        # Soft fralda (sem qualificador adulto vai para Bebé)
        "fralda", "fraldas",
    ],
    "Animais": [
        # PT + marcas
        "ração", "racao", "royal-canin", "whiskas", "friskies", "felix",
        "purina", "pro-plan", "hills", "advance-pet", "vitakraft",
        "petisco-cão", "petisco-cao", "petisco-gato", "snack-cão", "snack-cao",
        "snack para cão", "snack para cao", "brinquedo-cão", "brinquedo-cao",
        "coleira", "trela", "caixa-areia", "areia-gato", "tapete-higiénico",
        "tapete-higienico", "aquário", "aquario", "gaiola",
        # Pet-context keywords
        "para cão", "para cao", "para gato", "para gatos", "para cães",
        "para caes", "para cachorro",
    ],
    "Higiene Pessoal": [
        # PT
        "champô", "champo", "shampoo", "amaciador", "condicionador",
        "gel-duche", "gel-banho", "sabonete", "pasta-dentes",
        "pasta-dentífrica", "pasta-dentifrica", "escova-dentes",
        "fio-dentário", "fio-dentario", "colutório", "colutorio",
        "desodorizante", "antitranspirante", "creme-hidratante", "loção",
        "locao", "máscara-facial", "mascara-facial", "sérum", "serum",
        "batom", "rímel", "rimel", "base-maquilhagem", "pó-compacto",
        "po-compacto", "blush", "corretor", "eyeliner", "esmalte",
        "verniz-unhas", "pinça", "pinca", "depilação", "depilacao",
        "cera-depilatória", "cera-depilatoria", "lâmina-barbear",
        "lamina-barbear", "gillette", "gel-barbear", "after-shave",
        "aftershave", "perfume", "eau-de-toilette", "eau-de-parfum",
        "protector-solar", "protetor-solar", "pensos-higiénicos",
        "pensos-higienicos", "tampão-higiénico", "tampao-higienico",
        "coloração-capilar", "coloracao-capilar",
    ],
    "Higiene do Lar": [
        # PT
        "detergente", "amaciador-roupa", "amaciador-tecidos", "lixívia",
        "lixivia", "desinfectante", "desinfetante", "lava-tudo", "multiusos",
        "multi-usos", "papel-higiénico", "papel-higienico", "papel-cozinha",
        "guardanapo", "rolo-cozinha", "saco-lixo", "saco-congelar",
        "alumínio", "aluminio", "película-aderente", "pelicula-aderente",
        "ambientador", "insecticida", "inseticida", "lustra-móveis",
        "lustra-moveis", "cera-chão", "cera-chao", "anti-calcário",
        "anti-calcario", "destapa-canos", "ajax", "cif", "fairy", "skip",
        "persil", "omo ", "finish", "cotonetes", "disco-algodão",
        "disco-algodao", "algodão-hidrófilo", "algodao-hidrofilo",
        "velas-aromáticas", "velas-aromaticas", "vela-aromática",
        "vela-aromatica",
    ],
    "Saúde & Bem-Estar": [
        "vitamina", "multivitamínico", "multivitaminico", "magnésio",
        "magnesio", "cálcio", "calcio", "ferro ", "zinco", "ómega-3",
        "omega-3", "coenzima-q10", "probiótico", "probiotico", "paracetamol",
        "ben-u-ron", "aspirina", "ibuprofeno", "brufen", "lasolvan",
        "xarope", "pastilha-garganta", "soro-fisiológico", "soro-fisiologico",
        "penso-rápido", "penso-rapido", "band-aid", "compressa", "ligadura",
        "álcool-etílico", "alcool-etilico", "termómetro", "termometro",
        "tensiómetro", "tensiometro", "teste-gravidez", "preservativo",
        "lubrificante-íntimo", "lubrificante-intimo", "spray-nasal",
        "gotas-ouvidos", "gotas-nasais", "pomada",
        # Fraldas adulto / incontinência
        "fralda-adulto", "fraldas-adulto", "fralda adulto", "incontinência",
        "incontinencia", "tena ",
    ],
    "Bio & Saudável": [
        "bio ", " bio", "-bio", "biológico", "biologico", "orgânico",
        "organico", "organic", "ecológico", "ecologico", "sustentável",
        "sustentavel", "fairtrade", "fair-trade", "sem-glúten", "sem-gluten",
        "gluten-free", "vegan", "vegano", "vegetariano", "sem-lactose",
        "lactose-free", "sem-açúcar", "sem-acucar", "sugar-free", "raw ",
        "superalimento", "superfood", "spirulina", "chlorella",
        "maca-peruana", "acai", "chia", "quinoa", "linhaça", "linhaca",
        "sementes-cânhamo", "sementes-canhamo",
    ],
    "Fitness & Proteínas": [
        "whey", "proteína", "proteina", "protein", "caseína", "caseina",
        "casein", "bcaa", "creatina", "creatine", "pré-treino", "pre-treino",
        "preworkout", "pre-workout", "barra-proteica", "protein-bar",
        "shaker", "shake-proteína", "shake-proteina", "queimador-gordura",
        "fat-burner", "l-carnitina", "carnitina", "glutamina", "beta-alanina",
        "isolate", "hidrolisada", "concentrado-proteico", "iso-100",
        "gold-standard", "optimum-nutrition", "myprotein", "scitec",
    ],
    "Pronto a Comer": [
        "sandes ", "sanduíche-pronta", "sanduiche-pronta", "wrap ",
        "salada-pronta", "refeição-pronta", "refeicao-pronta", "sushi",
        "take-away", "pronto-a-comer", "ready-to-eat", "frango-assado",
        "empadão", "empadao", "gratin", "dauphinois",
    ],
    "Festa & Ocasiões": [
        "vela-aniversário", "vela-aniversario", "velas-aniversário",
        "velas-aniversario", "balão", "balao", "balões", "baloes",
        "chapéu-festa", "chapeu-festa", "apito-festa", "corneta-festa",
        "pinhata", "piñata", "confete", "serpentina", "guardanapo-festa",
        "prato-descartável", "prato-descartavel", "copo-descartável",
        "copo-descartavel", "talher-descartável", "talher-descartavel",
        "papel-presente", "fita-presente", "laço-presente", "laco-presente",
    ],
    "Outros": [
        "lâmpada", "lampada", "pilha", "pilhas", "bateria", "carregador",
        "cabo-usb", "fósforo", "fosforo", "isqueiro", "guarda-chuva",
        "lanterna",
    ],
}


# ============================================================================
# KEYWORDS MUITO DISTINTIVAS (1 match basta para confidence 0.88, no review)
# ============================================================================

DISTINCTIVE_KEYWORDS: dict[str, set[str]] = {
    "Padaria & Pastelaria": {
        "pão", "croissant", "pastel-de-nata", "baguete", "pastel de nata",
    },
    "Frutas & Legumes": {
        "abacate", "banana", "maçã", "pera", "morango", "kiwi", "ananás",
        "ananas", "manga", "melão", "melao", "melancia", "alface", "brócolos",
        "brocolos", "cenoura",
    },
    "Talho": {
        "bacon", "fiambre", "chouriço", "chourico", "presunto", "costeleta",
        "picanha", "hamburger-fresco",
    },
    "Peixaria": {
        "bacalhau", "sardinha", "polvo", "camarão", "camarao", "gamba",
        "mexilhão", "mexilhao", "marisco",
    },
    "Laticínios & Ovos": {
        "iogurte", "yogurt", "queijo", "manteiga", "natas", "bifidus",
        "kefir", "requeijão", "requeijao", "mozzarella", "mascarpone",
    },
    "Congelados": {
        "congelad", "gelado", "gelados", "ultracongelad", "frozen",
    },
    "Mercearia": {
        "vinagre", "azeite", "arroz ", "massa ", "esparguete", "macarrão",
        "macarrao", "café ", "açúcar", "acucar", "farinha", "coco-ralado",
        "coco ralado", "geleia", "compota", "mel ", "ketchup", "maionese",
    },
    "Bebidas": {
        "coca-cola", "pepsi", "sagres", "super-bock", "heineken", "vinho",
        "cerveja", "sumo", "suco", "água-mineral", "agua-mineral",
        "champanhe", "nespresso", "whisky", "vodka",
    },
    "Bebé": {
        "pampers", "dodot", "huggies", "nestum", "aptamil", "chupeta",
        "biberão", "biberao", "fralda-bebé", "fralda-bebe",
        "bebé ", "bebe ", "para bebé", "para bebe", "papinha",
    },
    "Animais": {
        "royal-canin", "whiskas", "friskies", "ração", "racao", "vitakraft",
        "coleira", "trela",
    },
    "Higiene Pessoal": {
        "champô", "champo", "shampoo", "desodorizante", "pasta-dentes",
        "gel-duche", "gel-banho", "pensos-higiénicos", "pensos-higienicos",
    },
    "Higiene do Lar": {
        "detergente", "lixívia", "lixivia", "papel-higiénico",
        "papel-higienico", "papel-cozinha", "guardanapo",
    },
    "Saúde & Bem-Estar": {
        "paracetamol", "ibuprofeno", "ben-u-ron", "vitamina", "preservativo",
        "termómetro", "termometro", "fralda-adulto", "incontinência",
        "incontinencia", "tena",
    },
    "Bio & Saudável": {
        "biológico", "biologico", "orgânico", "organico", "sem-glúten",
        "sem-gluten", "vegan",
    },
    "Fitness & Proteínas": {
        "whey", "bcaa", "creatina", "isolate", "myprotein",
        "optimum-nutrition",
    },
    "Pronto a Comer": {
        "take-away", "pronto-a-comer", "frango-assado",
        "pizza", "chili com carne", "lasanha fresca",
        "cozinha continente", "cozinha auchan", "refeição pronta",
    },
    "Festa & Ocasiões": {
        "balão-festa", "balao-festa", "vela-aniversário", "vela-aniversario",
        "prato-descartável", "prato-descartavel",
    },
    "Outros": {"lâmpada", "lampada"},
}


# ============================================================================
# MAPEAMENTO POR category_root
#   Confidence 0 = root ambíguo → força fallback keyword/LLM
# ============================================================================

# Roots ambíguos — forçam LLM
AMBIGUOUS_ROOTS = re.compile(
    r"^(frescos|gastronomia|regional|casa|casa e lar|casa, bricolage e jardim)$",
    re.I,
)

ROOT_MAP: list[tuple[re.Pattern, str, float]] = [
    # PRECEDÊNCIA ALTA (antes do root genérico "mercearia")
    (re.compile(r"congelad|frozen|gelad|ultracongelad", re.I), "Congelados", 0.90),
    (re.compile(r"^beb[eé]$|baby|infantil|puericultura|chupetas?|biber[õo]es?", re.I), "Bebé", 0.90),
    (re.compile(r"^animais$|\banimal\b|\bpet(s)?\b|^cão$|^cao$|^gato$|\broedor\b|\baqu[aá]rio\b", re.I), "Animais", 0.90),
    (re.compile(r"comida seca|comida h[úu]mida", re.I), "Animais", 0.75),
    (re.compile(r"^padaria$|pastelaria|bakery", re.I), "Padaria & Pastelaria", 0.85),
    (re.compile(r"^fruta(s)?$|^legumes$|^hort[íi]colas?$|produce|fruits|vegetables", re.I), "Frutas & Legumes", 0.85),
    (re.compile(r"^talho$|^carne(s)?$|charcutaria|meat|butcher", re.I), "Talho", 0.85),
    (re.compile(r"^peixaria$|^peixe(s)?$|marisco|fish|seafood", re.I), "Peixaria", 0.85),
    (re.compile(r"^latic[íi]nios$|^l[aá]cteos$|dairy|queijaria|^queijo", re.I), "Laticínios & Ovos", 0.85),
    (re.compile(r"^bebidas?$|beverage|drinks|^[áa]guas?$|sumos|refrigerantes|garrafeira|espirituosas|[aá]lcool|champanhes|espumantes", re.I), "Bebidas", 0.85),
    (re.compile(r"higiene.*beleza|beleza.*higiene|^higiene$|desodorizantes?|champ[ôo]s?|colora[çc][õo]es|^beleza$|cosm[ée]tica|capilar|perfumaria|maquilhagem", re.I), "Higiene Pessoal", 0.85),
    (re.compile(r"^limpeza$|^detergentes?$|household|cleaning", re.I), "Higiene do Lar", 0.90),
    (re.compile(r"^sa[uú]de$|farm[aá]cia|pharmacy|parafarm[aá]cia|bem-estar", re.I), "Saúde & Bem-Estar", 0.80),
    (re.compile(r"^bio$|^org[aâ]nico$|sem gl[úu]ten|sem-gl[úu]ten|vegan", re.I), "Bio & Saudável", 0.85),
    (re.compile(r"^fitness$|sports-nutrition|prote[íi]nas|musculação|musculacao", re.I), "Fitness & Proteínas", 0.90),
    (re.compile(r"pronto[- ]a[- ]comer|ready[- ]to[- ]eat|take[- ]away|deli", re.I), "Pronto a Comer", 0.80),
    (re.compile(r"^festa|party|anivers[aá]rio|ocasi[õo]es", re.I), "Festa & Ocasiões", 0.85),
    # Outros (lixo)
    (re.compile(r"brinquedo|bricolage|papelaria|jardim", re.I), "Outros", 0.80),
    # MERCEARIA (genérico — último)
    (re.compile(r"^mercearia$|grocery|despensa|pantry|^secos?$|conservas|^cereais$|^massas$|^arroz$|especiarias|^[oó]leos$|bolachas|^snacks$|chocolates|^doces$|caf[eé]s|ch[aá]s|frutos secos|pepitas|fibra", re.I), "Mercearia", 0.80),
]


# ============================================================================
# CLASSIFICADOR
# ============================================================================

@dataclass
class ClassificationResult:
    section: str
    confidence: float
    needs_review: bool = False
    method: str = ""
    matched_keywords: list[str] = field(default_factory=list)


def _normalize(s: str | None) -> str:
    return (s or "").lower()


def detect_pet_context(name: str) -> bool:
    return bool(PET_CONTEXT.search(name or ""))


def classify_by_keywords(name: str, pet_context: bool) -> ClassificationResult | None:
    normalized = _normalize(name)
    if not normalized:
        return None

    scores: dict[str, list[str]] = {}
    for section, keywords in KEYWORDS.items():
        matched = [kw for kw in keywords if kw in normalized]
        if matched:
            scores[section] = matched

    if not scores:
        return None

    # --- PRECEDÊNCIAS ---

    # 1. Congelados ganha sempre
    if "Congelados" in scores:
        matched = scores["Congelados"]
        return ClassificationResult(
            section="Congelados",
            confidence=0.95 if len(matched) >= 2 else 0.90,
            method="keyword_strong" if len(matched) >= 2 else "keyword_weak",
            matched_keywords=matched,
        )

    # 2. Pet-context: Animais ganha sobre Talho/Peixaria/Mercearia/Laticínios
    if pet_context:
        if "Animais" in scores:
            return ClassificationResult(
                section="Animais",
                confidence=0.92,
                method="pet_context",
                matched_keywords=scores["Animais"],
            )
        # Se pet_context sem match em Animais, ainda assim exclui Talho etc.
        for exclude in ("Talho", "Peixaria", "Mercearia", "Laticínios & Ovos"):
            scores.pop(exclude, None)
        if "Animais" in scores or scores:
            # Precedência: força Animais mesmo sem keyword exacta
            return ClassificationResult(
                section="Animais",
                confidence=0.75,
                needs_review=True,
                method="pet_context_inferred",
            )

    # 3. Bebé > Laticínios (leite-bebé)
    if "Bebé" in scores and "Laticínios & Ovos" in scores:
        scores.pop("Laticínios & Ovos")
    # Bebé > Saúde (fralda sem qualificador adulto)
    if "Bebé" in scores and "Saúde & Bem-Estar" in scores:
        saude_kws = scores.get("Saúde & Bem-Estar", [])
        if any("adulto" in kw or "incontin" in kw or "tena" in kw for kw in saude_kws):
            scores.pop("Bebé", None)  # fralda-adulto ganha
        else:
            scores.pop("Saúde & Bem-Estar")

    # 4. Fitness > Saúde (whey > vitamina)
    if "Fitness & Proteínas" in scores and "Saúde & Bem-Estar" in scores:
        scores.pop("Saúde & Bem-Estar")

    # 5. Bio só ganha sobre Mercearia (não sobre Bebidas/Laticínios/etc.)
    if "Bio & Saudável" in scores:
        if "Mercearia" in scores and len(scores) == 2:
            scores.pop("Mercearia")
        else:
            # Se Bio cruzou com secção mais específica, Bio perde
            scores.pop("Bio & Saudável")

    # 6. Talho/Peixaria > Mercearia
    if ("Talho" in scores or "Peixaria" in scores) and "Mercearia" in scores:
        scores.pop("Mercearia")

    # 7. Pronto a Comer > Talho/Laticínios/Mercearia quando há sinais de refeição pronta
    #    (pizza fresca não-congelada, chili com carne, lasanha fresca, "cozinha <marca>",
    #     refeição pronta). Congelados já ganhou na regra 1 se aplicável.
    ready_signals = re.search(
        r"\bpizza\b(?!\s*(congelad|fresca\s+congelad))"
        r"|\bchili\s+com\s+carne\b"
        r"|\bcozinha\s+(continente|auchan|pingo\s+doce|lidl|mercadona|intermarch[eé])\b"
        r"|refei[çc][aã]o\s+pronta"
        r"|\blasanha\b(?!.*congelad)",
        name, re.I,
    )
    if ready_signals:
        for exclude in ("Talho", "Laticínios & Ovos", "Mercearia"):
            scores.pop(exclude, None)
        scores["Pronto a Comer"] = [ready_signals.group(0).lower().strip()]

    # --- SCORING ---

    # Precedência: secção com keyword distintiva ganha sempre sobre secção sem.
    distinctive_sections = {
        s for s, kws in scores.items()
        if any(kw in DISTINCTIVE_KEYWORDS.get(s, set()) for kw in kws)
    }
    if distinctive_sections:
        # Restringir ao subset distinctive
        scores = {s: scores[s] for s in distinctive_sections}

    # Se todas as precedências esvaziaram scores (ex: Bio-alone popped) → sem match
    if not scores:
        return None

    best = max(scores.keys(), key=lambda s: (len(scores[s]), -SECTIONS.index(s)))
    matched = scores[best]
    n_matched = len(matched)

    # Keyword distintiva? → confidence 0.88 (no review mesmo com 1 match)
    distinctive = any(kw in DISTINCTIVE_KEYWORDS.get(best, set()) for kw in matched)

    if n_matched >= 2:
        return ClassificationResult(best, 0.95, False, "keyword_strong", matched)
    if distinctive:
        return ClassificationResult(best, 0.88, False, "keyword_distinctive", matched)
    return ClassificationResult(best, 0.80, True, "keyword_weak", matched)


def classify_by_root(category_root: str | None) -> ClassificationResult | None:
    if not category_root:
        return None
    # Decode HTML entities comuns do scraping
    root = (category_root
            .replace("&ccedil;", "ç").replace("&otilde;", "õ")
            .replace("&atilde;", "ã").replace("&aacute;", "á")
            .replace("&eacute;", "é").replace("&oacute;", "ó")
            .replace("&uacute;", "ú").replace("&ocirc;", "ô"))
    # Ambíguo → None força LLM
    if AMBIGUOUS_ROOTS.match(root.strip()):
        return None
    for pattern, section, confidence in ROOT_MAP:
        if pattern.search(root):
            return ClassificationResult(
                section=section,
                confidence=confidence,
                needs_review=confidence < 0.85,
                method="root_map",
            )
    return None


def classify_one(name: str, category_root: str | None) -> ClassificationResult:
    """Pipeline v2: pet_context → keyword → root-first-wins → root_map → fallback."""
    name = name or ""
    pet_context = detect_pet_context(name)

    # 1. Keyword matching
    kw_result = classify_by_keywords(name, pet_context)

    # 2. Root matching
    root_result = classify_by_root(category_root)

    # 3. Root-first-wins: se root tem confidence >= 0.85 e keyword é fraca,
    #    root vence (resolve "laranja" em "Sumo de Laranja" com root Bebidas).
    #    Quando root vence + secções divergem → needs_review=true (apanha scraping manchado).
    if root_result and root_result.confidence >= 0.85:
        if kw_result and kw_result.method == "keyword_weak":
            if kw_result.section != root_result.section:
                return ClassificationResult(
                    section=root_result.section,
                    confidence=root_result.confidence,
                    needs_review=True,  # divergência kw/root → revisão
                    method="root_map_over_weak",
                )
        if not kw_result:
            return root_result

    # 4. Se keyword teve resultado, usar
    if kw_result:
        return kw_result

    # 5. Senão, root
    if root_result:
        return root_result

    # 6. Fallback → LLM
    return ClassificationResult(
        section="Outros",
        confidence=0.20,
        needs_review=True,
        method="fallback",
    )


# ============================================================================
# LLM FALLBACK (claude-haiku-4-5)
# ============================================================================

LLM_SYSTEM = """És um classificador de produtos de supermercado para a Bora App.
Classifica cada produto numa das 18 secções canónicas:
""" + "\n".join(f"- {s}" for s in SECTIONS) + """

Responde APENAS em JSON:
[{"id": "<id>", "section": "<nome exacto>", "confidence": <0.0-1.0>}, ...]

Regras (por precedência):
1. Congelados ganha sempre (frozen/congelado/gelado).
2. Produto para animais (cão/gato/pet) → Animais, não Talho/Mercearia.
3. Bebé (fralda, papa, leite-bebé) > Laticínios/Saúde.
4. Fraldas adulto/incontinência → Saúde & Bem-Estar.
5. Whey/protein → Fitness, não Saúde.
6. Bio/organic só ganha sobre Mercearia (vinho-bio → Bebidas; ovos-bio → Laticínios).
7. Cápsulas café → Bebidas.
8. Leite achocolatado/leite-de-amêndoa/leite-de-soja → Laticínios & Ovos.
9. Velas aromáticas casa → Higiene do Lar; velas aniversário → Festa.
10. "Outros" só se genuinamente não encaixa (lâmpadas, pilhas, brinquedos, papelaria).
"""


def classify_batch_llm(batch: list[dict]) -> list[ClassificationResult]:
    if not anthropic or not os.getenv("ANTHROPIC_API_KEY"):
        return [ClassificationResult("Outros", 0.20, True, "fallback_no_llm") for _ in batch]

    client = anthropic.Anthropic()
    products_json = json.dumps(
        [{"id": str(p["id"]), "name": p["name"], "root": p.get("category_root")} for p in batch],
        ensure_ascii=False,
    )

    try:
        msg = client.messages.create(
            model="claude-haiku-4-5",
            max_tokens=4096,
            system=LLM_SYSTEM,
            messages=[{"role": "user", "content": f"Classifica {len(batch)} produtos:\n{products_json}"}],
        )
        text = msg.content[0].text
        match = re.search(r"\[.*\]", text, re.DOTALL)
        if not match:
            raise ValueError("No JSON array")
        parsed = json.loads(match.group(0))
    except Exception:
        return [ClassificationResult("Outros", 0.20, True, "fallback_llm_error") for _ in batch]

    results_by_id = {str(x["id"]): x for x in parsed if "id" in x}
    out: list[ClassificationResult] = []
    for p in batch:
        r = results_by_id.get(str(p["id"]))
        if not r or r["section"] not in SECTIONS:
            out.append(ClassificationResult("Outros", 0.20, True, "fallback_llm_bad"))
            continue
        conf = float(r.get("confidence", 0.5))
        out.append(ClassificationResult(
            section=r["section"],
            confidence=conf,
            needs_review=conf < 0.85,
            method="llm" if conf >= 0.50 else "fallback",
        ))
    return out


# ============================================================================
# PIPELINE
# ============================================================================

def classify_products(products: list[dict], force: bool = False) -> list[tuple[dict, ClassificationResult]]:
    needs_llm: list[dict] = []
    resolved: list[tuple[dict, ClassificationResult]] = []

    for p in products:
        if not force and (p.get("taxonomy_section")
                          and float(p.get("taxonomy_confidence") or 0) > 0.85):
            continue
        result = classify_one(p.get("name", ""), p.get("category_root"))
        if result.method == "fallback":
            needs_llm.append(p)
        else:
            resolved.append((p, result))

    for i in range(0, len(needs_llm), 100):
        chunk = needs_llm[i:i + 100]
        llm_results = classify_batch_llm(chunk)
        for p, r in zip(chunk, llm_results):
            resolved.append((p, r))
        time.sleep(0.5)

    return resolved


def apply_updates_sql(resolved: list[tuple[dict, ClassificationResult]]) -> str:
    lines = ["BEGIN;"]
    for p, r in resolved:
        sec = r.section.replace("'", "''")
        lines.append(
            f"UPDATE public.products SET "
            f"taxonomy_section = '{sec}', "
            f"taxonomy_confidence = {r.confidence:.2f}, "
            f"needs_review = {str(r.needs_review).lower()} "
            f"WHERE id = '{p['id']}';"
        )
    lines.append("COMMIT;")
    return "\n".join(lines)


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=1000)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--end", type=int, default=None)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--stats", action="store_true")
    parser.add_argument("--review", action="store_true")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--from-file", type=str, default=None,
                        help="JSON file com [{id,name,category_root}] — ignora query Supabase")
    parser.add_argument("--json", action="store_true",
                        help="Output JSON array no --dry-run (em vez de SQL)")
    args = parser.parse_args()

    if args.from_file:
        # --from-file: carrega produtos de JSON local, sem ligação Supabase
        with open(args.from_file, encoding="utf-8") as f:
            products = json.load(f)
        sb = None
    else:
        if not create_client:
            print("supabase-py não instalado")
            sys.exit(1)
        sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

        if args.stats:
            res = sb.rpc("get_taxonomy_distribution").execute()
            print(json.dumps(res.data, indent=2, ensure_ascii=False))
            return

        if args.review:
            res = (sb.table("products")
                   .select("id,name,category_root,taxonomy_section,taxonomy_confidence")
                   .eq("needs_review", True)
                   .order("taxonomy_confidence")
                   .limit(args.top)
                   .execute())
            print(json.dumps(res.data, indent=2, ensure_ascii=False))
            return

        query = sb.table("products").select("id,name,category_root,taxonomy_section,taxonomy_confidence")
        if args.start is not None and args.end is not None:
            query = query.range(args.start, args.end - 1)
        products = query.execute().data

    resolved = classify_products(products, force=args.force)
    if args.dry_run:
        if args.json:
            output = [
                {
                    "product_id": p["id"],
                    "name": p.get("name", ""),
                    "category_root": p.get("category_root", ""),
                    "predicted_section": r.section,
                    "method": r.method,
                    "confidence": round(r.confidence, 2),
                    "needs_review": r.needs_review,
                }
                for p, r in resolved
            ]
            print(json.dumps(output, ensure_ascii=False, indent=2))
        else:
            print(apply_updates_sql(resolved))
        return

    if sb is None:
        print("Modo --from-file sem --dry-run: usa --dry-run para não actualizar BD")
        return

    for p, r in resolved:
        sb.table("products").update({
            "taxonomy_section": r.section,
            "taxonomy_confidence": round(r.confidence, 2),
            "needs_review": r.needs_review,
        }).eq("id", p["id"]).execute()

    print(f"Classified: {len(resolved)} products")


if __name__ == "__main__":
    main()
