# Missão farmacias-2026-11-11 — constrói o catálogo final a partir dos dados recolhidos da Glovo.
# Lê: dados/raw_<loja>.json, dados/detalhes_<loja>.json, dados/fotos_<loja>.json, dados/info_<loja>.json
# Escreve: <loja>.json, insert_<loja>.sql, resumo.md, lojas_glovo.json
# Não toca na base de dados.
import json, os, re, random, unicodedata
from decimal import Decimal, ROUND_HALF_UP

AQUI = os.path.dirname(os.path.abspath(__file__))
DADOS = os.path.join(AQUI, "dados")
LOJAS = {
    "farmacia-se-guarda": {"nome": "Farmácia da Sé", "slug": "farmacia-da-se-grd", "storeId": "461279", "addressId": "732949", "prefix": "fse"},
    "farmacia-teixeira-guarda": {"nome": "Farmácia Teixeira", "slug": "farmacia-teixeira-grd", "storeId": "461596", "addressId": "733650", "prefix": "fte"},
}
SOURCE = "glovo-provisorio-2026-11-11"
HOJE = "2026-11-11"

# ---------------- arrumação das categorias (para o cliente) ----------------
ORDEM = [
    "Medicamentos sem receita",
    "Dor e febre",
    "Constipação, gripe e alergias",
    "Primeiros socorros",
    "Suplementos e vitaminas",
    "Nutrição e controlo de peso",
    "Bebé e mamã",
    "Saúde oral",
    "Saúde sexual e íntima",
    "Dermocosmética",
    "Higiene e cuidado pessoal",
    "Cabelo",
    "Homem",
    "Solares",
    "Maquilhagem e perfumes",
    "Ortopedia e bem-estar",
]
# categorias pequenas que se juntam a outra (definido depois de ver as contagens)
JUNTAR_SE_MENOS_DE = 8
JUNTAR_EM = {
    "Homem": "Higiene e cuidado pessoal",
    "Maquilhagem e perfumes": "Dermocosmética",
    "Nutrição e controlo de peso": "Suplementos e vitaminas",
    "Primeiros socorros": "Ortopedia e bem-estar",
    "Ortopedia e bem-estar": "Primeiros socorros",
    "Cabelo": "Higiene e cuidado pessoal",
}

def categoria_de(sc, c):
    if sc.startswith("Medicamentos"):
        if c in ("Dor e Febre", "Dores Musculares e Articulações"):
            return "Dor e febre"
        if c in ("Gripes e Constipações", "Tosse", "Dor de Garganta e Roquidão", "Alergias e Congestão Nasal"):
            return "Constipação, gripe e alergias"
        return "Medicamentos sem receita"
    if sc == "Bebé e Mamã":
        return "Bebé e mamã"
    if sc == "Saúde e Bem-Estar":
        if c == "Primeiros-Socorros":
            return "Primeiros socorros"
        if c == "Saúde e Respiração":
            return "Constipação, gripe e alergias"
        return "Ortopedia e bem-estar"
    if sc == "Nutrição e Suplementos":
        if c == "Suplementos Alimentares":
            return "Suplementos e vitaminas"
        return "Nutrição e controlo de peso"
    if sc == "Higiene Oral":
        return "Saúde oral"
    if sc == "Saúde Sexual e Íntima":
        return "Saúde sexual e íntima"
    if sc == "Cosmética Rosto":
        return "Solares" if c.startswith("Solares") else "Dermocosmética"
    if sc == "Cuidado Corpo":
        return "Solares" if c.startswith("Solares") else "Higiene e cuidado pessoal"
    if sc == "Cuidado Cabelo":
        return "Cabelo"
    if sc == "Cosmética Masculina":
        return "Homem"
    if sc in ("Perfumes", "Maquilhagem"):
        return "Maquilhagem e perfumes"
    if sc == "Solares":
        return "Solares"
    if sc == "Ortopedia":
        return "Ortopedia e bem-estar"
    return None  # desconhecida -> reportada

# ---------------- medicamento (MNSRM) ou parafarmácia ----------------

def norm_nome(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()

def cents(x):
    return int((Decimal(str(x)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))

def euros(c):
    return (Decimal(c) / 100).quantize(Decimal("0.01"))

def sql_str(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def ler(nome, defeito=None):
    f = os.path.join(DADOS, nome)
    if not os.path.exists(f):
        return defeito
    with open(f, encoding="utf8") as fh:
        return json.load(fh)


def precos(p):
    """Devolve (preço normal em cêntimos, preço promocional em cêntimos ou None, nota)."""
    base = cents(p["price"]) if p.get("price") is not None else None
    promo = None
    nota = None
    for pr in p.get("promotions") or []:
        # formatos vistos na Glovo: {"price": x, "priceInfo": {...}} ou {"discountedPrice": ...}
        cand = pr.get("price") if isinstance(pr, dict) else None
        if cand is None and isinstance(pr, dict):
            cand = (pr.get("priceInfo") or {}).get("amount") or pr.get("discountedPrice") or pr.get("promoPrice")
        if cand is not None:
            c = cents(cand)
            if base is not None and c != base:
                lo, hi = min(c, base), max(c, base)
                base, promo = hi, lo
                nota = "promo"
    return base, promo, nota


def limpar_nome(s):
    """Tira o código CNP (7 dígitos) que a Glovo cola no fim de alguns nomes ("...orodisp-2438489") e hífens soltos."""
    s = (s or "").strip()
    s = re.sub(r"\s*-\s*\d{7}$", "", s)
    s = re.sub(r"\s+-$", "", s)
    return re.sub(r"\s{2,}", " ", s).strip()


# Nota: a ficha da Glovo traz o aviso "MNSRM" em TODOS os produtos destas farmácias (872/872 na Sé),
# por isso não serve para distinguir. Sinais usados:
DOSE_MG = re.compile(r"\d+([.,]\d+)?\s?(mg|mcg|µg)\b|\bmg/(ml|g|dose)\b|\d+\s?ui\b", re.I)
FORMA_FARM = re.compile(r"\b(comprimidos?|c[aá]psulas?|xarope|suspens[aã]o|solu[cç][aã]o|gotas|granulado|gr[aâ]nulos|pastilhas?|gomas?|emplastro|gel|creme|pomada|emuls[aã]o|enema|col[ií]rio|efervescente|transd[eé]rmico)\b", re.I)  # palavras inteiras (o estilo POS "Comp X30" é de suplementos)
INFARMED = re.compile(r"^[^,]+,\s.*(\bx\s?\d+\b|Blister|Frasco|Bisnaga|Recipiente|Saqueta).*-\d{7}$")  # "Nome, dose x qtd forma-CNP"
NAO_MED = re.compile(r"\b(repel|repelente|ohropax|tamp[oõ]es|thermacare|faixa term|breathe right|penso nasal|fisiocrem|rhinomer|arko\w*|advancis|supracare|grintuss|uriage|ducray|isdin\w*|lrposay|la roche|bepanthene eczema|paranix|previpiq|stop repel|preservativ\w*|teste de gravidez|lubrificante|corega)\b", re.I)


# Imagens da Glovo que NÃO são o produto (vistas à mão a 11/11 numa folha de contactos, ver analisar_fotos.py)
MARCADORES_MD5 = {
    "20d45f8205433b1bfa777c9df3d3b962": "quadro 'PRODUTO SEM IMAGEM DISPONÍVEL' (Nossa Farmácia)",
    "a4a692fa886f6d8f7e9f5875913dccc0": "quadro 'SKIN — IMAGEM INDISPONÍVEL' (a mesma em produtos diferentes)",
    "fff7a8430da14474c04fe230f7db6d88": "logótipo Caudalie (cacho de uvas) em vez do produto",
}


def maiusculas(s):
    letras = [c for c in s if c.isalpha()]
    return bool(letras) and sum(c.isupper() for c in letras) / len(letras) >= 0.7


def medicamento(p):
    """Lista de razões para ser medicamento não sujeito a receita (vazia = parafarmácia)."""
    nome = p.get("name") or ""
    razoes = []
    if p.get("restricted"):
        razoes.append("Glovo marca 'restricted'")
    if INFARMED.search(nome):
        razoes.append("nome no formato INFARMED com CNP")
    if DOSE_MG.search(nome) and FORMA_FARM.search(nome):
        razoes.append("dose + forma farmacêutica no nome")
    na_seccao = any(o["sc"].startswith("Medicamentos") for o in p["occ"])
    if na_seccao and not maiusculas(nome) and not NAO_MED.search(nome):
        razoes.append("secção Medicamentos da Glovo")
    if razoes and NAO_MED.search(nome):
        return []
    return razoes


def construir(loja, cfg, amostras):
    raw = ler(f"raw_{loja}.json")
    det = ler(f"detalhes_{loja}.json", {})
    fotos = ler(f"fotos_{loja}.json", {})
    prods = raw["products"]
    for p in prods:
        p["occ"].sort(key=lambda o: o["ord"])
    prods.sort(key=lambda p: p["occ"][0]["ord"])

    # duplicados por nome normalizado dentro da loja (fica o primeiro na ordem do menu)
    vistos, unicos, dup = {}, [], []
    for p in prods:
        k = norm_nome(limpar_nome(p["name"]))
        if k in vistos:
            dup.append({"glovo_id": p["glovo_id"], "name": p["name"], "fica": vistos[k]["glovo_id"]})
            continue
        vistos[k] = p
        unicos.append(p)

    desconhecidas = set()
    itens = []
    for p in unicos:
        o = p["occ"][0]
        cat = categoria_de(o["sc"], o["c"])
        if cat is None:
            desconhecidas.add((o["sc"], o["c"]))
            cat = "Medicamentos sem receita"
        d = det.get(p["glovo_id"]) or {}
        base, promo, _ = precos(p)
        razoes = medicamento(p)
        f = dict(fotos.get(p["glovo_id"]) or {})
        if f.get("status") == "ok" and f.get("md5") in MARCADORES_MD5:
            # a Glovo tem um quadro "sem imagem" no lugar da foto: conta como produto SEM foto (fica fora do SQL)
            f["status"] = "marcador_sem_imagem_na_glovo: " + MARCADORES_MD5[f["md5"]]
        itens.append({
            "id": f'{cfg["prefix"]}-{p["glovo_id"]}',
            "glovo_id": p["glovo_id"],
            "external_id": p.get("external_id"),
            "name": limpar_nome(p["name"]),
            "name_glovo": p["name"],
            "description": d.get("description"),
            "glovo_category": f'{o["sc"]} > {o["c"]} > {o["s"]}',
            "category": cat,
            "category_order": None,
            "sort_order": None,
            "price_cents_glovo": base,
            "promo_price_cents": promo,
            "is_medicine": None,
            "_razoes_medicamento": razoes,
            "photo_url": f.get("photo_url") if f.get("status") == "ok" else None,
            "photo_bytes": f.get("photo_bytes") if f.get("status") == "ok" else None,
            "photo_type": f.get("photo_type") if f.get("status") == "ok" else None,
            "_foto_estado": f.get("status", "por_fazer"),
            "_out_of_stock": p.get("outOfStock"),
            "_detalhes_erro": d.get("error"),
        })

    # juntar categorias pequenas
    conta = {}
    for it in itens:
        conta[it["category"]] = conta.get(it["category"], 0) + 1
    juntas = {}
    mudou = True
    while mudou:
        mudou = False
        for cat, n in sorted(conta.items(), key=lambda x: x[1]):
            if n < JUNTAR_SE_MENOS_DE and cat in JUNTAR_EM and conta.get(JUNTAR_EM[cat], 0) > 0:
                destino = JUNTAR_EM[cat]
                juntas[cat] = destino
                for it in itens:
                    if it["category"] == cat:
                        it["category"] = destino
                conta[destino] += n
                del conta[cat]
                mudou = True
                break
    ordem = {c: i + 1 for i, c in enumerate([c for c in ORDEM if c in conta])}
    itens.sort(key=lambda it: (ordem[it["category"]], unicos.index(next(p for p in unicos if p["glovo_id"] == it["glovo_id"]))))
    seq = {}
    for it in itens:
        it["category_order"] = ordem[it["category"]]
        seq[it["category"]] = seq.get(it["category"], 0) + 1
        it["sort_order"] = seq[it["category"]]
        # Na dúvida, true: só é parafarmácia se nenhum sinal de medicamento
        it["is_medicine"] = len(it["_razoes_medicamento"]) > 0
    return {"itens": itens, "dup": dup, "desconhecidas": sorted(desconhecidas), "juntas": juntas, "raw": raw, "conta": conta, "ordem": ordem}


def escrever_sql(loja, itens):
    linhas = []
    cab = ("insert into public.products (id, restaurant_id, name, description, category, price, partner_shelf_price, "
           "photo_url, is_available, source, image_source, needs_photo, requires_prescription, sort_order, last_updated) values\n")
    validos = [it for it in itens if it["price_cents_glovo"] is not None and it["photo_url"]]
    blocos = [validos[i:i + 200] for i in range(0, len(validos), 200)]
    out = [f"-- Missão farmacias-2026-11-11 — {loja}: {len(validos)} produtos da Glovo (preço provisório).",
           "-- price = preço que a Glovo mostra ao cliente; partner_shelf_price = round(price * 0.90 / 1.05, 2) (balcão PROVISÓRIO).",
           "-- NÃO APLICADO: entregue para revisão. on conflict (id) do nothing.", ""]
    for b in blocos:
        vals = []
        for it in b:
            preco = euros(it["price_cents_glovo"])
            balcao = (preco * Decimal("0.90") / Decimal("1.05")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            vals.append("(" + ", ".join([
                sql_str(it["id"]), sql_str(loja), sql_str(it["name"]), sql_str(it["description"]), sql_str(it["category"]),
                str(preco), str(balcao), sql_str(it["photo_url"]), "true", sql_str(SOURCE), "'glovo'", "false", "false",
                str(it["sort_order"]), sql_str(HOJE)]) + ")")
        out.append(cab + ",\n".join(vals) + "\non conflict (id) do nothing;\n")
    with open(os.path.join(AQUI, f"insert_{loja}.sql"), "w", encoding="utf8", newline="\n") as fh:
        fh.write("\n".join(out))
    return len(validos), len(blocos)


def info_loja(loja, cfg):
    info = ler(f"info_{loja}.json")
    store = ler(f"store_{loja}.json")
    textos = []
    def walk(n):
        if isinstance(n, dict):
            for k in ("text", "title", "label", "description"):
                v = n.get(k)
                if isinstance(v, str) and v.strip():
                    textos.append(v.strip())
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for x in n:
                walk(x)
    walk(info)
    dias = [t for t in textos if re.match(r"^(Segunda|Terça|Quarta|Quinta|Sexta|Sábado|Domingo)", t)]
    morada = next((t for t in textos if re.search(r"\d{4}-\d{3}", t)), None)
    tel = next((t for t in textos if re.match(r"^\+?\d[\d ]{8,}$", t)), None)
    # Ficha legal que a Glovo mostra: "<valor>" seguido do rótulo ("Nome legal", "Morada da sede", "Número de identificação fiscal")
    legal = {}
    for i, t in enumerate(textos[1:], 1):
        if t in ("Nome legal", "Morada da sede", "Número de identificação fiscal"):
            legal[t] = textos[i - 1]
    out = {"loja": loja, "nome_glovo": None, "glovo_slug": cfg["slug"], "glovo_store_id": cfg["storeId"],
           "glovo_address_id": cfg["addressId"], "url_glovo": f'https://glovoapp.com/pt/pt/guarda/stores/{cfg["slug"]}',
           "morada": morada, "telefone": tel, "horario": dias,
           "latitude": None, "longitude": None,
           "nota_coordenadas": "a Glovo não devolve coordenadas da loja (location=null em /v3/stores e na ficha); não inventadas",
           "imagem_loja_url": None, "logo_url": None,
           "nome_legal": legal.get("Nome legal"), "morada_sede": legal.get("Morada da sede"),
           "nif": legal.get("Número de identificação fiscal")}
    if isinstance(store, dict):
        out["nome_glovo"] = store.get("name")
        out["morada"] = store.get("address") or out["morada"]
        out["telefone"] = store.get("phoneNumber") or out["telefone"]
        loc = store.get("location") or {}
        if isinstance(loc, dict):
            out["latitude"], out["longitude"] = loc.get("latitude"), loc.get("longitude")
        if store.get("imageId"):
            out["imagem_loja_url"] = "https://glovo.dhmedia.io/image/" + str(store["imageId"]).replace("dh:", "")
        if store.get("logoImageId"):
            out["logo_url"] = "https://glovo.dhmedia.io/image/" + str(store["logoImageId"]).replace("dh:", "")
    return out


def main():
    res = {}
    lojas_info = []
    for loja, cfg in LOJAS.items():
        if not os.path.exists(os.path.join(DADOS, f"raw_{loja}.json")):
            print("sem dados para", loja)
            continue
        r = construir(loja, cfg, None)
        itens = r["itens"]
        publico = []
        for it in itens:
            publico.append({k: v for k, v in it.items() if not k.startswith("_")})
        with open(os.path.join(AQUI, f"{loja}.json"), "w", encoding="utf8") as fh:
            json.dump(publico, fh, ensure_ascii=False, indent=1)
        n_sql, n_blocos = escrever_sql(loja, itens)
        r["n_sql"], r["n_blocos"] = n_sql, n_blocos
        res[loja] = r
        lojas_info.append(info_loja(loja, cfg))
        print(loja, "itens", len(itens), "sql", n_sql, "blocos", n_blocos, "dup", len(r["dup"]), "desconhecidas", r["desconhecidas"], "juntas", r["juntas"])
    with open(os.path.join(AQUI, "lojas_glovo.json"), "w", encoding="utf8") as fh:
        json.dump(lojas_info, fh, ensure_ascii=False, indent=1)
    escrever_resumo(res)


def escrever_resumo(res):
    L = ["# Catálogo das farmácias da Guarda (Glovo) — missão farmacias-2026-11-11", "",
         "Recolhido da API pública da Glovo (menu da loja + páginas de categoria + ficha de cada produto) a 11/11/2026.",
         "Nada foi inserido na base. As fotos estão no bucket público `product-images`, pasta `farmacias/<loja>/`.", ""]
    rnd = random.Random(20261111)
    for loja, r in res.items():
        cfg = LOJAS[loja]
        itens = r["itens"]
        raw = r["raw"]
        ok = sum(1 for it in itens if it["_foto_estado"] == "ok")
        falh = [it for it in itens if it["_foto_estado"] != "ok"]
        sem_desc = sum(1 for it in itens if not it["description"])
        promo = sum(1 for it in itens if it["promo_price_cents"] is not None)
        med = sum(1 for it in itens if it["is_medicine"])
        esgot = sum(1 for it in itens if it["_out_of_stock"])
        L += [f"## {cfg['nome']} (`{loja}`) — Glovo store {cfg['storeId']} / address {cfg['addressId']}", "",
              f"- Menu da Glovo: {raw['menu_sections']} secções, {raw['menu_categories']} categorias, {raw['menu_subsections']} subsecções; subsecções lidas: {raw['sections_seen']}; em falta: {len(raw['missing_sections'])}.",
              f"- Subsecções do menu sem produtos na Glovo (vazias, não é falha de leitura): " + (", ".join(f"{m['c']} / {m['s']}" for m in raw['missing_sections']) or "nenhuma") + ".",
              f"- Produtos distintos na Glovo (por id): {raw['total_unique']}.",
              f"- Duplicados por nome normalizado retirados: {len(r['dup'])}. Secções de promoções/mais vendidos: não existem no menu desta loja (só `elementsWithoutMenu` = {json.dumps(raw.get('elements_without_menu'))}, ignorados).",
              f"- Produtos finais: **{len(itens)}**; com preço promocional: {promo}; marcados como medicamento: {med}; parafarmácia: {len(itens) - med}; esgotados na Glovo no momento: {esgot} (vão como is_available true, como pedido).",
              f"- Sem descrição na ficha da Glovo: {sem_desc}.",
              f"- Fotos: com foto real, subida e provada (200 no URL público, mesmo tamanho, mesmos primeiros bytes e mesmo md5) {ok}; sem foto real {len(falh)}. Tipos: "
              + ", ".join(f"{t} {n}" for t, n in sorted(__import__('collections').Counter(it['photo_type'] for it in itens if it['photo_type']).items())) + " (nenhuma AVIF).",
              f"- SQL: {r['n_sql']} linhas em {r['n_blocos']} INSERT (`insert_{loja}.sql`).", ""]
        if falh:
            L.append("Produtos SEM foto real (ficam fora do SQL; as cópias do quadro ficaram no Storage mas o JSON tem photo_url null):")
            for it in falh:
                L.append(f"- {it['id']} — {it['name']} — estado: {it['_foto_estado']}")
            L.append("")
        if r["juntas"]:
            L.append("Categorias pequenas juntadas: " + "; ".join(f"{a} → {b}" for a, b in r["juntas"].items()))
            L.append("")
        L += ["Categorias (ordem, nome, produtos):", ""]
        for cat, o in sorted(r["ordem"].items(), key=lambda x: x[1]):
            L.append(f"{o}. {cat} — {r['conta'][cat]}")
        L += ["", "Amostra ao acaso de 20 produtos para conferir à mão:", "",
              "| # | Nome | Preço Glovo | Categoria | Medicamento | Foto |", "|---|---|---|---|---|---|"]
        for i, it in enumerate(rnd.sample(itens, min(20, len(itens))), 1):
            preco = f"{euros(it['price_cents_glovo'])} €".replace(".", ",") if it["price_cents_glovo"] is not None else "—"
            if it["promo_price_cents"] is not None:
                preco += f" (promo {euros(it['promo_price_cents'])} €)".replace(".", ",")
            L.append(f"| {i} | {it['name'].replace('|', '/')} | {preco} | {it['category']} | {'sim' if it['is_medicine'] else 'não'} | {it['photo_url'] or '—'} |")
        L.append("")
    with open(os.path.join(AQUI, "resumo.md"), "w", encoding="utf8", newline="\n") as fh:
        fh.write("\n".join(L))


if __name__ == "__main__":
    main()
