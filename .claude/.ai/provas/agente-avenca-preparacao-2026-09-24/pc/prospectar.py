#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prospeção da avença «Presença Digital Bora» (missão agente-avenca-preparacao-2026-09-24).

O que faz: procura negócios num raio de 20 km da Guarda e mede, com o que é PÚBLICO, o
tamanho do buraco digital de cada um — não tem site? não tem telefone na ficha? não tem
horário? só tem Facebook e mais nada? Guarda tudo em `prospects_presenca` no Supabase do
Bora (RLS: só o admin lê), pela RPC `prospect_registar` com chave do Vault.

FONTE: OpenStreetMap, pela Overpass API. É a base de dados pública de mapas que o mundo
inteiro usa; cada ficha é do próprio negócio (nome, morada, telefone, site, horário) e está
aberta a qualquer pessoa. Não há raspagem de redes sociais, não há dados de pessoas, não há
contactos comprados. Só o que o negócio já publicou sobre si.

NADA É ENVIADO A NINGUÉM AQUI. Isto só constrói a lista.

Uso:  python prospectar.py [--raio-km 20] [--so-ver]
"""
import argparse
import io
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
GUARDA = (40.5373, -7.2674)
OVERPASS = "https://overpass-api.de/api/interpreter"

# O que procuramos, e como se chama em português simples no painel.
ALVOS = [
    ('node["amenity"="restaurant"]', "restaurante"),
    ('way["amenity"="restaurant"]', "restaurante"),
    ('node["amenity"="cafe"]', "cafe"),
    ('way["amenity"="cafe"]', "cafe"),
    ('node["amenity"="fast_food"]', "restaurante"),
    ('node["amenity"="bar"]', "bar"),
    ('node["amenity"="pub"]', "bar"),
    ('node["shop"="hairdresser"]', "cabeleireiro"),
    ('node["shop"="beauty"]', "estetica"),
    ('node["shop"="car_repair"]', "oficina"),
    ('way["shop"="car_repair"]', "oficina"),
    ('node["shop"="tyres"]', "pneus"),
    ('way["shop"="tyres"]', "pneus"),
    ('node["shop"="bakery"]', "padaria"),
    ('node["shop"="butcher"]', "talho"),
    ('node["shop"="clothes"]', "loja"),
    ('node["shop"="florist"]', "loja"),
    ('node["leisure"="fitness_centre"]', "ginasio"),
    ('way["leisure"="fitness_centre"]', "ginasio"),
    ('node["amenity"="clinic"]', "clinica"),
    ('node["amenity"="doctors"]', "clinica"),
    ('node["amenity"="dentist"]', "clinica"),
    ('node["amenity"="veterinary"]', "clinica"),
    ('node["tourism"="hotel"]', "alojamento"),
    ('way["tourism"="hotel"]', "alojamento"),
    ('node["tourism"="guest_house"]', "alojamento"),
    ('node["tourism"="apartment"]', "alojamento"),
    ('node["tourism"="hostel"]', "alojamento"),
]


def ambiente():
    e = {}
    for linha in io.open(ENV, encoding="utf-8"):
        linha = linha.strip()
        if linha and not linha.startswith("#") and "=" in linha:
            k, v = linha.split("=", 1)
            e[k.strip()] = v.strip()
    return e


E = ambiente()
LOG = os.path.join(BASE, "prospeccao.log")


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def km(a, b):
    """Distância em linha reta, em km."""
    r = 6371.0
    dlat = math.radians(b[0] - a[0])
    dlon = math.radians(b[1] - a[1])
    x = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlon / 2) ** 2)
    return round(2 * r * math.asin(math.sqrt(x)), 1)


def overpass(raio_m):
    partes = "".join("%s(around:%d,%f,%f);" % (a, raio_m, GUARDA[0], GUARDA[1]) for a, _ in ALVOS)
    q = "[out:json][timeout:180];(%s);out center tags;" % partes
    dados = urllib.parse.urlencode({"data": q}).encode("utf-8")
    req = urllib.request.Request(OVERPASS, data=dados,
                                 headers={"User-Agent": "BoraApp-prospeccao/1.0 (Guarda, PT)"})
    for tentativa in range(3):
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as ex:  # noqa: BLE001
            log("overpass falhou (%d/3): %s" % (tentativa + 1, str(ex)[:120]))
            time.sleep(20)
    return {"elements": []}


def categoria_de(tags):
    for consulta, nome in ALVOS:
        chave = consulta.split('["')[1].split('"]')[0].split('"')[0]
        valor = consulta.split('="')[1].split('"]')[0]
        if tags.get(chave) == valor:
            return nome
    return "outro"


def rede(tags, qual):
    """O link da rede social, venha ele de onde vier na ficha."""
    for k in ("contact:" + qual, qual, "contact:" + qual + ":url"):
        v = tags.get(k)
        if v:
            return v if v.startswith("http") else "https://%s.com/%s" % (qual, v.lstrip("@/"))
    return None


def pontuar(p):
    """0 a 100: quanto maior, melhor candidato.

    Metade é o BURACO (o que lhes falta e nós fazemos), metade é conseguirmos falar com eles.
    Um negócio sem site e sem forma de contacto não é uma boa oportunidade — é uma parede.
    """
    n = 0
    if p["sem_site"]:
        n += 35
    if p["sem_horario"]:
        n += 10
    if p["sem_site"] and (p["facebook"] or p["instagram"]):
        n += 10          # já perceberam que precisam de estar online, mas ficaram a meio
    if p["categoria"] in ("restaurante", "cafe", "cabeleireiro", "barbearia", "estetica",
                          "ginasio", "alojamento", "oficina", "pneus"):
        n += 10          # negócios onde a foto e a ficha Google valem dinheiro directo
    if p["telefone"]:
        n += 20          # dá para falar
    if p["email"]:
        n += 10
    if p["km_da_guarda"] is not None and p["km_da_guarda"] <= 8:
        n += 5           # perto: dá para ir lá à mão
    return max(0, min(100, n))


def rpc(nome, corpo):
    url = E["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/" + nome
    req = urllib.request.Request(url, data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                                 headers={"apikey": E["SUPABASE_ANON_KEY"],
                                          "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        corpo = r.read().decode("utf-8")
    return json.loads(corpo) if corpo.strip() else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raio-km", type=float, default=20.0)
    ap.add_argument("--so-ver", action="store_true", help="nao grava no Supabase")
    a = ap.parse_args()

    log("START prospeccao raio=%.0f km, %d tipos de negocio" % (a.raio_km, len(ALVOS)))
    dados = overpass(int(a.raio_km * 1000))
    elementos = dados.get("elements", [])
    log("o OpenStreetMap devolveu %d fichas" % len(elementos))

    vistos, linhas = set(), []
    for el in elementos:
        tags = el.get("tags") or {}
        nome = (tags.get("name") or "").strip()
        if not nome:
            continue                       # sem nome nao serve para nada
        lat = el.get("lat") or (el.get("center") or {}).get("lat")
        lon = el.get("lon") or (el.get("center") or {}).get("lon")
        if lat is None or lon is None:
            continue
        d = km(GUARDA, (lat, lon))
        if d > a.raio_km:
            continue
        fonte = "osm:%s/%s" % (el.get("type"), el.get("id"))
        if fonte in vistos:
            continue
        vistos.add(fonte)
        site = tags.get("website") or tags.get("contact:website") or tags.get("url")
        tel = tags.get("phone") or tags.get("contact:phone") or tags.get("contact:mobile")
        morada = " ".join(x for x in [tags.get("addr:street"), tags.get("addr:housenumber")] if x) or None
        p = {
            "fonte_id": fonte,
            "nome": nome,
            "categoria": categoria_de(tags),
            "morada": morada,
            "concelho": tags.get("addr:city") or tags.get("addr:municipality"),
            "lat": lat, "lon": lon, "km_da_guarda": d,
            "telefone": tel,
            "email": tags.get("email") or tags.get("contact:email"),
            "website": site,
            "instagram": rede(tags, "instagram"),
            "facebook": rede(tags, "facebook"),
            "sem_site": not bool(site),
            "sem_telefone": not bool(tel),
            "sem_horario": not bool(tags.get("opening_hours")),
            "ficha_google": "por_ver",
            "notas": "OpenStreetMap, dados publicos do proprio negocio",
        }
        p["pontuacao"] = pontuar(p)
        linhas.append(p)

    linhas.sort(key=lambda x: -x["pontuacao"])
    io.open(os.path.join(BASE, "prospects.json"), "w", encoding="utf-8").write(
        json.dumps(linhas, ensure_ascii=False, indent=1))
    log("ficaram %d negocios com nome dentro do raio (%d sem site, %d com telefone)"
        % (len(linhas), sum(1 for x in linhas if x["sem_site"]), sum(1 for x in linhas if x["telefone"])))

    if a.so_ver:
        for x in linhas[:15]:
            log("  %3d  %-34s %-12s %s" % (x["pontuacao"], x["nome"][:34], x["categoria"],
                                           "sem site" if x["sem_site"] else x["website"][:40]))
        return 0

    gravados = 0
    for x in linhas:
        try:
            rpc("prospect_registar", {"p_chave": E["PROSPECTS_KEY"], "p_linha": x})
            gravados += 1
        except Exception as ex:  # noqa: BLE001
            log("falhou a gravar %s: %s" % (x["nome"][:30], str(ex)[:120]))
    log("FIM: %d de %d gravados no Supabase" % (gravados, len(linhas)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
