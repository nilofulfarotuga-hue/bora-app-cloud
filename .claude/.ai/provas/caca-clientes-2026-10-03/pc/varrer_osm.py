#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Varredura alargada pelo OpenStreetMap (missao caca-clientes-2026-10-03, continuacao).

PORQUE EXISTE: a lista de 24/09 so tinha 20 km a volta da Guarda e quase so cafes. Aqui
alarga-se ao concelho inteiro da Guarda e a Covilha, Seia e Gouveia, e entram os nichos
que pagam sites (alojamento, imobiliarias, dentistas, advogados, ginasios, oficinas) mais
os que servem a app Bora (restaurantes, cafes, mercearias, farmacias, saloes, floristas).

Custo zero: Overpass (OpenStreetMap). Nao usa a Places API.
Tambem preenche o concelho dos que ja estavam na base (pelo concelho onde o OSM os tem; os
que sobram, por geocodificacao inversa no Nominatim, 1 pedido por segundo).

Uso: python varrer_osm.py [--seco]
"""
import io
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
LOG = os.path.join(BASE, "varrer_osm.log")
GUARDA = (40.5373, -7.2676)
CONCELHOS = ["Guarda", "Covilhã", "Seia", "Gouveia"]
UA = "BoraApp-Guarda-prospeccao/1.0 (boraappbora@gmail.com)"

# (filtro overpass, categoria, e nicho de dinheiro?)
ALVOS = [
    ('["tourism"~"^(guest_house|hotel|chalet|hostel|apartment|motel)$"]', "alojamento", True),
    ('["office"="estate_agent"]', "imobiliaria", True),
    ('["amenity"="dentist"]', "clinica", True),
    ('["healthcare"="dentist"]', "clinica", True),
    ('["amenity"="clinic"]', "clinica", True),
    ('["office"="lawyer"]', "advogado", True),
    ('["leisure"="fitness_centre"]', "ginasio", True),
    ('["shop"~"^(car_repair|car)$"]', "oficina", True),
    ('["shop"~"^(beauty|hairdresser)$"]', "cabeleireiro", False),
    ('["amenity"="restaurant"]', "restaurante", False),
    ('["amenity"="fast_food"]', "restaurante", False),
    ('["amenity"="cafe"]', "cafe", False),
    ('["amenity"="pharmacy"]', "farmacia", False),
    ('["shop"~"^(bakery|pastry)$"]', "padaria", False),
    ('["shop"~"^(convenience|greengrocer|butcher|deli)$"]', "mercearia", False),
    ('["shop"="florist"]', "florista", False),
    ('["shop"~"^(laundry|dry_cleaning)$"]', "lavandaria", False),
]
DINHEIRO = set(c for _, c, d in ALVOS if d)
CADEIAS = ("springfield", "lanidor", "telepizza", "decenio", "inatel", "mcdonald", "burger king", "kfc", "pingo doce",
           "continente", "lidl", "intermarch", "auchan", "mercadona", "minipreço", "minipreco", "aldi", "wells", "pizza hut",
           "h3", "starbucks", "zara", "remax", "re/max", "era imobili", "century 21", "norauto", "midas", "fitness hut",
           "solinca", "ibis", "tryp", "pousada de juventude", "hi pousada", "telepizza", "domino", "padaria portuguesa")


def ambiente():
    e = {}
    for linha in io.open(ENV, encoding="utf-8"):
        linha = linha.strip()
        if linha and not linha.startswith("#") and "=" in linha:
            k, v = linha.split("=", 1)
            e[k.strip()] = v.strip()
    return e


E = ambiente()


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha.encode("ascii", "replace").decode("ascii"), flush=True)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + chr(10))


def rpc(nome, corpo):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/" + nome,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"], "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        t = r.read().decode("utf-8")
    return json.loads(t) if t.strip() else None


def km(a, b):
    r = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    d = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b[1] - a[1]) / 2) ** 2
    return round(2 * r * math.asin(math.sqrt(d)), 1)


def overpass(concelho):
    """Pede em fatias pequenas (o Overpass publico recusa pedidos grandes) e insiste 3 vezes por fatia."""
    todos = []
    for i in range(0, len(ALVOS), 4):
        partes = "".join('nwr%s["name"](area.a);' % f for f, _, _ in ALVOS[i:i + 4])
        q = '[out:json][timeout:90];area["boundary"="administrative"]["admin_level"="7"]["name"="%s"]->.a;(%s);out center tags;' % (concelho, partes)
        feito = False
        for tentativa in range(3):
            for servidor in ("https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"):
                try:
                    req = urllib.request.Request(servidor, data=urllib.parse.urlencode({"data": q}).encode(), headers={"User-Agent": UA})
                    with urllib.request.urlopen(req, timeout=120) as r:
                        todos += json.loads(r.read().decode("utf-8")).get("elements", [])
                    feito = True
                    break
                except Exception as ex:
                    log("  overpass %s fatia %d falhou em %s: %s" % (concelho, i, servidor.split("/")[2], type(ex).__name__))
                    time.sleep(8)
            if feito:
                break
        if not feito:
            return None
        time.sleep(4)
    return todos


def categoria_de(tags):
    for filtro, cat, _ in ALVOS:
        chave = filtro.split('"')[1]
        valores = filtro.split('"')[3].strip("^$()").split("|")
        if tags.get(chave) in valores:
            return cat
    return None


def primeiro(tags, *chaves):
    for c in chaves:
        if tags.get(c):
            return tags[c].strip()
    return None


def pontuar(tem_site, categoria, tem_instagram):
    """Regra da ordem: sem site 30, categoria com dinheiro 15, Instagram 10.
    (site fraco 20 e sem livro de reclamacoes 10 entram no cacador, que e quem abre o site;
    as avaliacoes do Google ficam de fora por ser a Places paga.)"""
    return (0 if tem_site else 30) + (15 if categoria in DINHEIRO else 0) + (10 if tem_instagram else 0)


def nominatim(lat, lon):
    u = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=pt&lat=%s&lon=%s" % (lat, lon)
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=30) as r:
            a = json.loads(r.read().decode("utf-8")).get("address", {})
        return a.get("municipality") or a.get("city") or a.get("town") or a.get("county")
    except Exception:
        return None


def main():
    seco = "--seco" in sys.argv
    antes = rpc("prospects_ler", {"p_chave": E["PROSPECTS_KEY"]})
    conhecidos = {p["fonte_id"]: p for p in antes}
    log("INICIO varredura OSM: %d ja na base%s" % (len(antes), " [SECO]" if seco else ""))
    concelho_de = {}
    novos = 0
    por_cat = {}
    lista = sys.argv[sys.argv.index("--so") + 1].split(",") if "--so" in sys.argv else CONCELHOS
    for concelho in lista:
        els = overpass(concelho)
        if els is None:
            log("  %s: SEM RESPOSTA do Overpass" % concelho)
            continue
        vistos = 0
        for el in els:
            tags = el.get("tags", {})
            nome = (tags.get("name") or "").strip()
            cat = categoria_de(tags)
            if not nome or not cat:
                continue
            fonte = "osm:%s/%s" % (el["type"], el["id"])
            concelho_de[fonte] = concelho
            if any(c in nome.lower() for c in CADEIAS) or tags.get("brand"):
                continue
            lat = el.get("lat") or el.get("center", {}).get("lat")
            lon = el.get("lon") or el.get("center", {}).get("lon")
            if lat is None:
                continue
            vistos += 1
            if fonte in conhecidos:
                continue
            web = primeiro(tags, "website", "contact:website", "url")
            ig = primeiro(tags, "contact:instagram", "instagram")
            fb = primeiro(tags, "contact:facebook", "facebook")
            if web and "facebook.com" in web and not fb:
                fb = web
            tem_site = bool(web) and not any(x in web.lower() for x in ("facebook.com", "instagram.com", "tripadvisor", "booking.com"))
            tel = primeiro(tags, "phone", "contact:phone", "contact:mobile")
            morada = " ".join(x for x in (tags.get("addr:street"), tags.get("addr:housenumber"), tags.get("addr:postcode"), tags.get("addr:city")) if x) or None
            linha = {"fonte_id": fonte, "nome": nome, "categoria": cat, "morada": morada, "concelho": concelho,
                     "lat": str(lat), "lon": str(lon), "km_da_guarda": str(km(GUARDA, (lat, lon))), "telefone": tel,
                     "email": primeiro(tags, "email", "contact:email"), "website": web, "instagram": ig, "facebook": fb,
                     "sem_site": not tem_site, "sem_telefone": not tel, "sem_horario": not tags.get("opening_hours"),
                     "ficha_google": "por_ver", "pontuacao": str(pontuar(tem_site, cat, bool(ig))),
                     "notas": "varredura OSM 03/10"}
            por_cat[cat] = por_cat.get(cat, 0) + 1
            novos += 1
            if not seco:
                try:
                    rpc("prospect_registar", {"p_chave": E["PROSPECTS_KEY"], "p_linha": linha})
                except Exception as ex:
                    log("  ERRO a gravar %s: %s" % (nome, ex))
        log("  %s: %d negocios com nome nas categorias, novos ate agora %d" % (concelho, vistos, novos))
        time.sleep(3)
    # concelho dos que ja estavam
    preenchidos = 0
    for p in antes:
        if (p.get("concelho") or "").strip():
            continue
        c = concelho_de.get(p["fonte_id"])
        if not c and p.get("lat") is not None:
            c = nominatim(p["lat"], p["lon"])
            time.sleep(1.1)
        if c:
            preenchidos += 1
            if not seco:
                rpc("prospect_contacto_registar", {"p_chave": E["PROSPECTS_KEY"], "p_id": p["id"], "p_linha": {"concelho": c}})
    log("FIM varredura: %d novos %s; concelho preenchido em %d dos antigos" % (novos, json.dumps(por_cat, ensure_ascii=False), preenchidos))


if __name__ == "__main__":
    main()
