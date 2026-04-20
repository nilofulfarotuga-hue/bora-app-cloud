"""Translate Mercadona product names ES -> PT.

Approach:
  1. Comprehensive manual ES->PT dictionary (~350 entries).
  2. Word-by-word substitution, longest-match first, preserving brand names.
  3. Apply via PostgREST PATCH concurrently.
  4. Capture original Spanish name in a new column `name_es` (NEW) so
     name_original still holds the mojibake legacy form.
"""
import os, sys, json, re, time
from dotenv import load_dotenv
import httpx
import concurrent.futures

load_dotenv(r"C:\Users\danil\Desktop\projetosflutter\bora_app\backend\.env")
URL = os.environ["SUPABASE_URL"]
SVC = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

# === ES -> PT DICTIONARY ===
# Keys are lowercase Spanish. Multi-word keys are matched before single-word.
# Values are lowercase Portuguese.
DICT_ES_PT = {
    # --- LÁCTEOS ---
    "leche entera": "leite gordo", "leche desnatada": "leite magro",
    "leche semidesnatada": "leite meio-gordo", "leche": "leite",
    "leches": "leites", "mantequilla": "manteiga",
    "queso fresco": "queijo fresco", "queso curado": "queijo curado",
    "queso fundido": "queijo fundido", "queso de cabra": "queijo de cabra",
    "queso en lonchas": "queijo em fatias", "queso rallado": "queijo ralado",
    "quesos": "queijos", "queso": "queijo",
    "yogur desnatado": "iogurte magro", "yogur": "iogurte",
    "yogures": "iogurtes", "nata": "natas",
    "nata para montar": "natas para bater",
    "requesón": "requeijão",
    "cuajada": "coalhada",
    "batido": "batido", "batidos": "batidos",
    # --- ÓLEOS ---
    "aceite de oliva virgen extra": "azeite virgem extra",
    "aceite de oliva virgen": "azeite virgem",
    "aceite de oliva": "azeite", "aceite de girasol": "óleo de girassol",
    "aceite de soja": "óleo de soja", "aceite de coco": "óleo de coco",
    "aceite": "azeite", "aceites": "azeites",
    "vinagre": "vinagre",
    # --- PROTEÍNAS ---
    "carne picada": "carne picada", "carne": "carne",
    "pescado": "peixe", "pescados": "peixes",
    "pollo entero": "frango inteiro", "pechuga de pollo": "peito de frango",
    "muslos de pollo": "coxas de frango", "alitas de pollo": "asas de frango",
    "pollo": "frango", "pavo": "peru",
    "huevo": "ovo", "huevos": "ovos",
    "atún claro": "atum claro", "atún": "atum",
    "bonito": "bonito", "salmón": "salmão", "sardina": "sardinha",
    "sardinas": "sardinhas", "merluza": "pescada",
    "bacalao": "bacalhau", "boquerón": "biqueirão", "boquerones": "biqueirões",
    "trucha": "truta", "lubina": "robalo", "dorada": "dourada",
    "gambas": "camarão", "langostinos": "lagostins",
    "mejillón": "mexilhão", "mejillones": "mexilhões",
    "almejas": "amêijoas", "pulpo": "polvo",
    "calamar": "lula", "calamares": "lulas",
    "cerdo": "porco", "ternera": "vitela", "vaca": "vaca",
    "cordero": "borrego", "conejo": "coelho",
    "jamón serrano": "presunto serrano", "jamón cocido": "fiambre",
    "jamón ibérico": "presunto ibérico", "jamón": "presunto",
    "chorizo": "chouriço", "salchichón": "salsichão",
    "salchicha": "salsicha", "salchichas": "salsichas",
    "tocino": "toucinho", "panceta": "panceta",
    "lomo": "lombo", "costilla": "costeleta", "costillas": "costeletas",
    "solomillo": "lombinho", "filete": "bife",
    "morcilla": "morcela", "butifarra": "botifarra",
    "embutido": "enchido", "embutidos": "enchidos",
    # --- MERCEARIA ---
    "agua mineral": "água mineral", "agua con gas": "água com gás",
    "agua sin gas": "água sem gás", "agua": "água",
    "pan de molde": "pão de forma", "pan rallado": "pão ralado",
    "pan tostado": "pão torrado", "pan": "pão", "panes": "pães",
    "tostada": "torrada", "tostadas": "torradas",
    "arroz": "arroz", "pasta": "massa",
    "pastas": "massas", "fideos": "fideus",
    "espaguetis": "esparguete", "macarrones": "macarrão",
    "azúcar": "açúcar", "sal": "sal",
    "harina": "farinha", "harinas": "farinhas",
    "galleta": "bolacha", "galletas": "bolachas",
    "bizcocho": "bolo", "bollería": "padaria",
    "magdalena": "madalena", "magdalenas": "madalenas",
    "zumo de naranja": "sumo de laranja",
    "zumo de manzana": "sumo de maçã",
    "zumo": "sumo", "zumos": "sumos",
    "refresco": "refrigerante", "refrescos": "refrigerantes",
    "café soluble": "café solúvel", "café molido": "café moído",
    "café en grano": "café em grão", "café descafeinado": "café descafeinado",
    "café": "café",
    "té verde": "chá verde", "té negro": "chá preto", "té": "chá",
    "infusión": "infusão", "infusiones": "infusões",
    "mermelada": "doce", "confitura": "compota",
    "miel": "mel", "chocolate": "chocolate", "cacao": "cacau",
    "caramelo": "caramelo", "caramelos": "rebuçados",
    "golosinas": "guloseimas", "chicle": "pastilha elástica",
    "chicles": "pastilhas elásticas",
    "helado": "gelado", "helados": "gelados",
    "turrón": "turrão", "mazapán": "maçapão",
    # --- FRUTAS / HORTALIÇAS ---
    "manzana": "maçã", "manzanas": "maçãs",
    "naranja": "laranja", "naranjas": "laranjas",
    "plátano": "banana", "plátanos": "bananas",
    "fresa": "morango", "fresas": "morangos",
    "pera": "pera", "peras": "peras",
    "uva": "uva", "uvas": "uvas",
    "melocotón": "pêssego", "melocotones": "pêssegos",
    "albaricoque": "damasco", "cereza": "cereja", "cerezas": "cerejas",
    "ciruela": "ameixa", "ciruelas": "ameixas",
    "sandía": "melancia", "melón": "melão",
    "piña": "ananás", "limón": "limão", "limones": "limões",
    "mandarina": "tangerina", "kiwi": "kiwi",
    "aguacate": "abacate", "mango": "manga", "papaya": "papaia",
    "granada": "romã", "higo": "figo", "higos": "figos",
    "tomate": "tomate", "tomates": "tomates",
    "patata": "batata", "patatas": "batatas",
    "cebolla": "cebola", "cebollas": "cebolas",
    "ajo": "alho", "ajos": "alhos",
    "zanahoria": "cenoura", "zanahorias": "cenouras",
    "lechuga": "alface", "espinaca": "espinafre", "espinacas": "espinafres",
    "pimiento": "pimento", "pimientos": "pimentos",
    "calabacín": "courgette", "calabaza": "abóbora",
    "berenjena": "beringela", "pepino": "pepino",
    "coliflor": "couve-flor", "brócoli": "brócolos",
    "col": "couve", "repollo": "repolho",
    "seta": "cogumelo", "setas": "cogumelos",
    "champiñón": "cogumelo", "champiñones": "cogumelos",
    "aceituna": "azeitona", "aceitunas": "azeitonas",
    "espárrago": "espargo", "espárragos": "espargos",
    "alcachofa": "alcachofra", "alcachofas": "alcachofras",
    "puerro": "alho-francês", "apio": "aipo",
    "nabo": "nabo", "rábano": "rabanete",
    "maíz": "milho", "guisante": "ervilha", "guisantes": "ervilhas",
    "judía": "feijão", "judías": "feijões",
    "judía verde": "feijão verde", "judías verdes": "feijão verde",
    "garbanzo": "grão", "garbanzos": "grão",
    "lenteja": "lentilha", "lentejas": "lentilhas",
    "soja": "soja",
    # --- ADJETIVOS / ESTADOS ---
    "entero": "inteiro", "entera": "inteira",
    "enteros": "inteiros", "enteras": "inteiras",
    "fresco": "fresco", "fresca": "fresca",
    "frescos": "frescos", "frescas": "frescas",
    "congelado": "congelado", "congelada": "congelada",
    "congelados": "congelados", "congeladas": "congeladas",
    "ultracongelado": "ultracongelado",
    "ultracongelada": "ultracongelada",
    "caliente": "quente", "frío": "frio", "fría": "fria",
    "cocido": "cozido", "cocida": "cozida",
    "asado": "assado", "asada": "assada",
    "frito": "frito", "frita": "frita",
    "crudo": "cru", "cruda": "crua",
    "cortado": "cortado", "cortada": "cortada",
    "picado": "picado", "picada": "picada",
    "rallado": "ralado", "rallada": "ralada",
    "loncheado": "fatiado", "lonchas": "fatias",
    "natural": "natural", "ecológico": "biológico",
    "ecológica": "biológica", "bio": "bio",
    "integral": "integral", "integrales": "integrais",
    "sin gluten": "sem glúten", "sin lactosa": "sem lactose",
    "sin azúcar": "sem açúcar", "sin azúcares": "sem açúcares",
    "sin azúcares añadidos": "sem açúcares adicionados",
    "con azúcar": "com açúcar",
    "desnatado": "magro", "desnatada": "magra",
    "semidesnatado": "meio-gordo", "semidesnatada": "meia-gorda",
    "ligero": "leve", "ligera": "leve",
    "light": "light",
    "suave": "suave", "fuerte": "forte",
    "amargo": "amargo", "dulce": "doce",
    "salado": "salgado", "salada": "salgada",
    "picante": "picante",
    "clásico": "clássico", "clásica": "clássica",
    "tradicional": "tradicional",
    "especial": "especial", "premium": "premium",
    "selección": "seleção", "surtido": "sortido",
    # --- UNIDADES / EMBALAGEM ---
    "bolsa": "saco", "bolsas": "sacos",
    "botella": "garrafa", "botellas": "garrafas",
    "paquete": "pacote", "paquetes": "pacotes",
    "caja": "caixa", "cajas": "caixas",
    "lata": "lata", "latas": "latas",
    "tarro": "frasco", "tarros": "frascos",
    "frasco": "frasco", "bote": "frasco",
    "rollo": "rolo", "rollos": "rolos",
    "tableta": "tablete", "tabletas": "tabletes",
    "barra": "barra", "barras": "barras",
    "unidad": "unidade", "unidades": "unidades",
    "pack": "pack", "docena": "dúzia",
    # --- BEBIDAS ---
    "cerveza": "cerveja", "cervezas": "cervejas",
    "vino tinto": "vinho tinto", "vino blanco": "vinho branco",
    "vino rosado": "vinho rosé", "vino": "vinho",
    "cava": "espumante", "champán": "champanhe",
    "sidra": "sidra", "ron": "rum", "ginebra": "gin",
    "whisky": "whisky", "vodka": "vodka",
    "licor": "licor", "licores": "licores",
    "bebida": "bebida", "bebidas": "bebidas",
    "bebida isotónica": "bebida isotónica",
    "bebida energética": "bebida energética",
    "leche vegetal": "bebida vegetal",
    "bebida de avena": "bebida de aveia",
    "bebida de almendras": "bebida de amêndoa",
    "bebida de soja": "bebida de soja",
    # --- LIMPEZA ---
    "detergente": "detergente", "suavizante": "amaciador",
    "lejía": "lixívia", "lavavajillas": "detergente loiça",
    "fregasuelos": "detergente para o chão",
    "limpiador": "limpador", "limpiador multiusos": "limpador multiusos",
    "desinfectante": "desinfetante", "antical": "anti-calcário",
    "bayeta": "esfregão", "bayetas": "esfregões",
    "estropajo": "esfregão", "papel higiénico": "papel higiénico",
    "servilleta": "guardanapo", "servilletas": "guardanapos",
    "bolsa de basura": "saco do lixo",
    "bolsas de basura": "sacos do lixo",
    "ambientador": "ambientador",
    # --- CUIDADO PESSOAL ---
    "champú": "champô", "acondicionador": "amaciador de cabelo",
    "gel de baño": "gel de banho", "jabón": "sabonete",
    "jabón de manos": "sabonete líquido",
    "pasta de dientes": "pasta de dentes",
    "dentífrico": "pasta de dentes",
    "cepillo de dientes": "escova de dentes",
    "desodorante": "desodorizante",
    "crema": "creme", "cremas": "cremes",
    "crema facial": "creme facial", "crema corporal": "creme corporal",
    "crema de manos": "creme de mãos",
    "loción": "loção",
    "perfume": "perfume", "colonia": "colónia",
    "máscara": "máscara", "maquillaje": "maquilhagem",
    "pañal": "fralda", "pañales": "fraldas",
    "pañuelo": "lenço", "pañuelos": "lenços",
    "toallita": "toalhita", "toallitas": "toalhitas",
    "compresa": "penso higiénico", "compresas": "pensos higiénicos",
    "tampón": "tampão", "tampones": "tampões",
    "maquinilla": "lâmina", "cuchilla": "lâmina",
    "cuchillas": "lâminas",
    "espuma de afeitar": "espuma de barbear",
    "gel de afeitar": "gel de barbear",
    "preservativo": "preservativo",
    "algodón": "algodão", "bastoncillos": "cotonetes",
    "esmalte de uñas": "verniz das unhas",
    "laca de uñas": "verniz das unhas",
    "quitaesmalte": "acetona",
    # --- BEBÉS / CUIDADOS ---
    "bebé": "bebé", "bebés": "bebés",
    "biberón": "biberão", "biberones": "biberões",
    "chupete": "chucha", "papilla": "papa",
    "leche para lactantes": "leite para lactentes",
    # --- CARNES preparados ---
    "hamburguesa": "hambúrguer", "hamburguesas": "hambúrgueres",
    "pincho": "espetada", "pinchos": "espetadas",
    "brocheta": "espetada", "brochetas": "espetadas",
    "albóndiga": "almôndega", "albóndigas": "almôndegas",
    "empanada": "empada", "empanadas": "empadas",
    "empanadilla": "rissol", "empanadillas": "rissóis",
    "croqueta": "croquete", "croquetas": "croquetes",
    "nugget": "nugget", "nuggets": "nuggets",
    # --- FRASES/PALAVRAS COMUNS ---
    "con": "com", "sin": "sem",
    "y": "e", "o": "ou", "u": "ou",
    "al": "ao", "del": "do", "de la": "da",
    "para": "para", "por": "por",
    "en": "em", "la": "a", "el": "o",
    "las": "as", "los": "os",
    "un": "um", "una": "uma",
    "uno": "um", "unos": "uns", "unas": "umas",
    "nueva": "nova", "nuevo": "novo",
    "grande": "grande", "pequeño": "pequeno", "pequeña": "pequena",
    "mediano": "médio", "mediana": "média",
    "extra": "extra", "máximo": "máximo", "mínimo": "mínimo",
    "más": "mais", "menos": "menos",
    "listo": "pronto", "lista": "pronta",
    # --- SABORES / INGREDIENTES ---
    "sabor": "sabor", "sabores": "sabores",
    "relleno": "recheado", "rellena": "recheada",
    "rellenos": "recheados", "rellenas": "recheadas",
    "relleno de": "recheado de",
    "hierbas": "ervas", "finas hierbas": "ervas finas",
    "especias": "especiarias",
    "vainilla": "baunilha", "canela": "canela",
    "pimienta": "pimenta", "mostaza": "mostarda",
    "comino": "cominhos", "orégano": "orégão",
    "perejil": "salsa", "albahaca": "manjericão",
    "romero": "alecrim", "tomillo": "tomilho",
    "mayonesa": "maionese", "ketchup": "ketchup",
    "mostaza": "mostarda", "ali oli": "alho e azeite",
    # --- PESCADO/MARISCO ---
    "ahumado": "fumado", "ahumada": "fumada",
    "salazón": "salmoura", "marinado": "marinado",
    "en escabeche": "em escabeche",
    "en aceite de oliva": "em azeite",
    "al natural": "ao natural",
    # --- AUSÊNCIA / REDUÇÃO ---
    "reducido en": "reduzido em",
    "bajo en": "baixo em",
    "rico en": "rico em",
    "alto en": "alto em",
    "fuente de": "fonte de",
    # --- DEPARTAMENTOS ---
    "limpieza": "limpeza", "hogar": "lar",
    "cocina": "cozinha", "baño": "casa de banho",
    "lavandería": "lavandaria",
    "cuidado personal": "cuidado pessoal",
    "cuidado facial": "cuidado facial",
    "cuidado corporal": "cuidado corporal",
    "cuidado capilar": "cuidado capilar",
    "higiene": "higiene", "higiene íntima": "higiene íntima",
    # --- EXTRA COMUNS ---
    "nuevas": "novas", "varios": "vários",
    "muchos": "muitos", "muchas": "muitas",
    "mucho": "muito", "mucha": "muita",
    "poco": "pouco", "pocos": "poucos",
    "todo": "tudo", "toda": "toda", "todos": "todos", "todas": "todas",
    "cada": "cada", "algún": "algum", "alguna": "alguma",
    "otro": "outro", "otra": "outra",
    # tipos adicionais
    "caldo": "caldo", "caldos": "caldos",
    "sopa": "sopa", "sopas": "sopas",
    "puré": "puré", "purés": "purés",
    "salsa": "molho", "salsas": "molhos",
    "crema de": "creme de",  # crema de setas = creme de cogumelos
    "ensalada": "salada", "ensaladas": "saladas",
    "verdura": "legume", "verduras": "legumes",
    "hortalizas": "legumes", "hortaliza": "legume",
    "fruta": "fruta", "frutas": "frutas",
    "frutos secos": "frutos secos",
    "nueces": "nozes", "nuez": "noz",
    "almendra": "amêndoa", "almendras": "amêndoas",
    "avellana": "avelã", "avellanas": "avelãs",
    "pistacho": "pistácio", "pistachos": "pistácios",
    "cacahuete": "amendoim", "cacahuetes": "amendoins",
    "anacardo": "caju", "anacardos": "caju",
    "pasas": "passas", "dátil": "tâmara", "dátiles": "tâmaras",
    "ciruela pasa": "ameixa seca", "orejón": "alperce seco",
    # pequenas correções
    "nuevo": "novo", "fácil": "fácil",
    "familiar": "familiar", "infantil": "infantil",
    "adulto": "adulto", "adulta": "adulta",
    "recambio": "recarga", "recambios": "recargas",
    "prelavado": "pré-lavagem",
    "limpio": "limpo", "limpia": "limpa",
    # bebidas vegetais / soja
    "avena": "aveia", "almendras": "amêndoas",
    # comuns palavras compridas
    "lactosa": "lactose", "gluten": "glúten",
    "vegano": "vegan", "vegana": "vegan",
    "vegetariano": "vegetariano", "vegetariana": "vegetariana",
    # --- BATCH 2: MISSING WORDS FROM FIRST RUN ---
    "castaña": "castanha", "castañas": "castanhas",
    "cocida": "cozida", "cocidas": "cozidas",
    "cocido": "cozido", "cocidos": "cozidos",
    "pelada": "sem casca", "peladas": "sem casca",
    "hueso": "caroço", "huesos": "caroços",
    "sin hueso": "sem caroço",
    "piel": "pele", "pieles": "peles",
    "ropa": "roupa",
    "aliñado": "temperado", "aliñada": "temperada",
    "aliñados": "temperados", "aliñadas": "temperadas",
    "quitamanchas": "tira-nódoas",
    "recetas": "receitas", "receta": "receita",
    "azúcares": "açúcares",
    "azúcares añadidos": "açúcares adicionados",
    "añadido": "adicionado", "añadida": "adicionada",
    "añadidos": "adicionados", "añadidas": "adicionadas",
    "sin azúcares añadidos": "sem açúcares adicionados",
    "manteca": "banha", "manteca de cerdo": "banha de porco",
    "lavadora": "máquina de lavar", "lavadoras": "máquinas de lavar",
    "lavavajillas": "máquina de loiça",
    "activador": "ativador",
    "tendencia": "tendência",
    "verduritas": "legumes pequenos",
    "polvo": "pó", "en polvo": "em pó",
    "líquido": "líquido", "líquida": "líquida",
    "solido": "sólido", "sólido": "sólido",
    "lavado": "lavado", "lavada": "lavada",
    "limpio": "limpo", "limpia": "limpa",
    "troceado": "aos pedaços", "troceada": "aos pedaços",
    "mezcla": "mistura", "mezclas": "misturas",
    "variado": "variado", "variada": "variada",
    "variados": "variados", "variadas": "variadas",
    "gruesos": "grossos", "gruesa": "grossa",
    "grueso": "grosso", "gruesas": "grossas",
    "pequeño": "pequeno", "pequeña": "pequena",
    "pequeños": "pequenos", "pequeñas": "pequenas",
    "niño": "criança", "niños": "crianças",
    "niña": "criança", "niñas": "crianças",
    "paño": "pano", "paños": "panos",
    "baño": "banho", "baños": "banhos",
    "cepillo": "escova", "cepillos": "escovas",
    "esponja": "esponja", "esponjas": "esponjas",
    "caja": "caixa", "cajas": "caixas",
    "cartón": "cartão", "cartones": "cartões",
    "bandeja": "bandeja", "bandejas": "bandejas",
    "sobre": "saqueta", "sobres": "saquetas",
    "blanco": "branco", "blanca": "branca",
    "negro": "preto", "negra": "preta",
    "rojo": "vermelho", "roja": "vermelha",
    "amarillo": "amarelo", "amarilla": "amarela",
    "verde": "verde", "verdes": "verdes",
    "azul": "azul", "azules": "azuis",
    "rosa": "rosa",
    "marrón": "castanho", "marrones": "castanhos",
    "gris": "cinzento", "grises": "cinzentos",
    "dorado": "dourado", "dorada": "dourada",
    "plateado": "prateado", "plateada": "prateada",
    "caballero": "homem", "señor": "homem",
    "señora": "senhora", "mujer": "mulher",
    "hombre": "homem", "hombres": "homens",
    "mujeres": "mulheres",
    "hidratante": "hidratante", "nutritiva": "nutritiva",
    "nutritivo": "nutritivo", "reparadora": "reparadora",
    "reparador": "reparador", "protector": "protetor",
    "protectora": "protetora",
    "calcio": "cálcio",
    "hierro": "ferro", "zinc": "zinco",
    "vitamina": "vitamina", "vitaminas": "vitaminas",
    "aloe vera": "aloé vera",
    "aceite esencial": "óleo essencial",
    "aceites esenciales": "óleos essenciais",
    "cabello": "cabelo", "cabellos": "cabelos",
    "pelo": "cabelo",
    "piel normal": "pele normal",
    "piel seca": "pele seca",
    "piel grasa": "pele oleosa",
    "piel mixta": "pele mista",
    "piel sensible": "pele sensível",
    "anti-edad": "anti-idade", "antiedad": "anti-idade",
    "antimanchas": "anti-manchas",
    "antiarrugas": "anti-rugas",
    "arrugas": "rugas",
    "rubio": "loiro", "rubia": "loira",
    "castaño": "castanho", "castaña": "castanha",
    "moreno": "moreno", "morena": "morena",
    "tinte": "tinta", "tintes": "tintas",
    "coloración": "coloração",
    "coloración permanente": "coloração permanente",
    "rizado": "encaracolado", "rizada": "encaracolada",
    "liso": "liso", "lisa": "lisa",
    "ondulado": "ondulado", "ondulada": "ondulada",
    "seco": "seco", "seca": "seca",
    "graso": "oleoso", "grasa": "oleosa",
    "sensible": "sensível", "sensibles": "sensíveis",
    "suave": "suave", "suaves": "suaves",
    "dañado": "danificado", "dañada": "danificada",
    "dañados": "danificados", "dañadas": "danificadas",
    "sano": "saudável", "sana": "saudável",
    "sanos": "saudáveis", "sanas": "saudáveis",
    "fuerza": "força",
    "brillo": "brilho",
    "volumen": "volume",
}


CAPITALIZED_WORDS = {
    # known brand names (preserve case exactly)
    "Hacendado", "Deliplus", "Bosque Verde", "Milbona", "Compal", "Mimosa",
    "Delta", "Nestlé", "Nescafé", "Gallo", "Knorr", "Maggi",
    "Coca-Cola", "Pepsi", "Fanta", "Sprite", "Schweppes", "Nivea",
    "L'Oréal", "Pantene", "Elvive", "H&S", "Head & Shoulders",
    "Colgate", "Sensodyne", "Listerine",
}


def translate_word(w: str) -> str:
    """Apply dict to a single token, preserving case."""
    key = w.lower()
    if key in DICT_ES_PT:
        pt = DICT_ES_PT[key]
        if w.isupper():
            return pt.upper()
        if w[0].isupper():
            return pt[0].upper() + pt[1:]
        return pt
    return w


def translate_name(name: str) -> str:
    """Translate full name. First try multi-word phrases (longest first),
    then word-by-word."""
    # Keep original for fallback
    result = name
    # Apply multi-word phrases first (sorted by length desc), case-insensitive
    multi_word = [k for k in DICT_ES_PT if " " in k]
    multi_word.sort(key=len, reverse=True)
    for es in multi_word:
        pt = DICT_ES_PT[es]
        pattern = re.compile(r"\b" + re.escape(es) + r"\b", re.IGNORECASE)
        def replace(m):
            matched = m.group(0)
            if matched[0].isupper():
                return pt[0].upper() + pt[1:]
            return pt
        result = pattern.sub(replace, result)
    # Now word-by-word for single words
    def replace_word(m):
        return translate_word(m.group(0))
    result = re.sub(r"\b\w+\b", replace_word, result)
    return result


def main():
    headers = {"apikey": SVC, "Authorization": f"Bearer {SVC}",
               "Content-Type": "application/json"}
    client = httpx.Client(headers=headers, timeout=30.0, base_url=URL)

    # Fetch Mercadona id
    r = client.get("/rest/v1/restaurants", params={"select": "id,name", "name": "ilike.*mercadona*"})
    rest = r.json()[0]
    print(f"Mercadona id: {rest['id']}")

    # Fetch all active products
    rows = []
    offset = 0
    page = 1000
    while True:
        r = client.get("/rest/v1/products",
                       params={"select": "id,name,name_es",
                               "restaurant_id": f"eq.{rest['id']}",
                               "limit": str(page), "offset": str(offset)})
        chunk = r.json()
        if not chunk:
            break
        rows.extend(chunk)
        offset += page
        if len(chunk) < page:
            break
    print(f"Total Mercadona products: {len(rows)}")

    # Translate
    updates = []
    changed = 0
    for row in rows:
        old = row['name']
        new = translate_name(old)
        if new != old:
            changed += 1
            updates.append({"id": row['id'], "old": old, "new": new,
                            "has_es_already": row.get('name_es') is not None})
    print(f"Translated (different from ES): {changed}")

    # Save diff for review
    out_diff = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\mercadona_translation_diff.json"
    with open(out_diff, 'w', encoding='utf-8') as f:
        json.dump(updates, f, ensure_ascii=False, indent=2)
    print(f"Saved diff to {out_diff}")

    # Show 20 random samples
    import random
    random.seed(7)
    sample = random.sample(updates, min(20, len(updates)))
    print("\n=== 20 RANDOM TRANSLATION SAMPLES ===")
    for i, u in enumerate(sample, 1):
        line = f"{i:2d}. ES: {u['old']}\n    PT: {u['new']}\n"
        sys.stdout.buffer.write(line.encode('utf-8'))

    # Apply via PATCH — set name=PT, name_es=original-ES (first time only)
    def apply_one(u):
        body = {"name": u['new']}
        if not u['has_es_already']:
            body["name_es"] = u['old']
        r = client.patch(
            f"/rest/v1/products?id=eq.{u['id']}",
            headers={**headers, "Prefer": "return=minimal"},
            json=body,
        )
        return r.status_code in (200, 204)

    apply_flag = '--apply' in sys.argv
    if not apply_flag:
        print("\n(dry-run. Add --apply to update DB.)")
        client.close()
        return

    t0 = time.time()
    ok = 0
    err = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
        for i, good in enumerate(ex.map(apply_one, updates), 1):
            if good:
                ok += 1
            else:
                err += 1
            if i % 500 == 0:
                sys.stdout.write(f"  {i}/{len(updates)}\n")
                sys.stdout.flush()
    print(f"\nDone {time.time()-t0:.1f}s: OK={ok} ERR={err}")
    client.close()


if __name__ == '__main__':
    main()
