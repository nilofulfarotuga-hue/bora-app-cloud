#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Portão de identidade da avença (missão agente-avenca-qualidade-2026-09-24).

PORQUE EXISTE: a primeira lista casou cada negócio do mapa com o PRIMEIRO resultado do
Google, sem confirmar que era o mesmo negócio. Saiu isto:
  · o café «JS» da Guarda casou com «PSD | JSD | TSD — Guarda», a sede de um partido;
  · o ginásio «Bemequer» casou com «Bemequer ortopedia», em Bragança;
  · o restaurante «Moreira» casou com a aldeia «Moreira de Rei»;
  · e três dos escolhidos estavam CLOSED_PERMANENTLY no Google.
Seis de dez amostras não podiam ir para lado nenhum. Mandar aquilo era queimar o nome da
Bora numa terra onde toda a gente se conhece.

Agora só passa quem cumpre as QUATRO condições, e quem não cumpre fica `descartado` com o
motivo escrito — não desaparece, fica a dizer porquê.

  1. ABERTO         estado_negocio = OPERATIONAL (quem fechou não compra nada)
  2. É ELE          o nome do Google parece-se mesmo com o nome do mapa
  3. É AQUI         o ponto do Google fica a menos de 2 km do ponto do mapa, e a 20 km da Guarda
  4. É DO RAMO      o tipo do Google bate certo com a categoria do mapa

Uso:  python portao.py [--quantos 130]
"""
import argparse
import difflib
import io
import json
import math
import os
import re
import sys
import time
import unicodedata
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
GUARDA = (40.5373, -7.2674)
E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if "=" in _l and not _l.startswith("#"):
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()

# Tipos do Google aceites por categoria nossa. O que não estiver aqui é casamento errado —
# foi assim que entraram uma sede de partido e uma aldeia.
RAMOS = {
    "restaurante": {"restaurant", "meal_takeaway", "meal_delivery", "food", "bar_and_grill",
                    "pizza_restaurant", "hamburger_restaurant", "fast_food_restaurant",
                    "portuguese_restaurant", "cafe", "bar", "steak_house", "seafood_restaurant"},
    "cafe": {"cafe", "coffee_shop", "bakery", "bar", "restaurant", "meal_takeaway",
             "breakfast_restaurant", "snack_bar", "pub"},
    "bar": {"bar", "pub", "cafe", "night_club", "restaurant"},
    "padaria": {"bakery", "cafe", "store", "food_store"},
    "talho": {"butcher_shop", "store", "food_store", "grocery_store"},
    "cabeleireiro": {"hair_salon", "hair_care", "beauty_salon", "barber_shop"},
    "estetica": {"beauty_salon", "spa", "nail_salon", "hair_salon", "wellness_center"},
    "oficina": {"car_repair", "car_dealer", "auto_parts_store", "car_wash", "tire_shop"},
    "pneus": {"tire_shop", "car_repair", "auto_parts_store"},
    "ginasio": {"gym", "fitness_center", "sports_club", "sports_complex", "wellness_center"},
    "clinica": {"doctor", "dentist", "hospital", "medical_lab", "veterinary_care",
                "physiotherapist", "health", "clinic"},
    "alojamento": {"lodging", "hotel", "guest_house", "bed_and_breakfast", "motel",
                   "resort_hotel", "cottage", "farmstay", "inn", "apartment_complex"},
    "loja": {"store", "clothing_store", "florist", "gift_shop", "shoe_store", "jewelry_store"},
}
# Tipos que NUNCA podem ser um negócio destes (foi por aqui que a lista se estragou).
PROIBIDOS = {"association_or_organization", "local_government_office", "locality",
             "political", "city_hall", "school", "university", "church", "place_of_worship",
             "administrative_area_level_1", "administrative_area_level_2", "sublocality",
             "post_office", "police", "fire_station", "hospital_department"}


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(os.path.join(BASE, "prospeccao.log"), "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def km(a, b):
    r = 6371.0
    dlat, dlon = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    x = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlon / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(x))


def simples(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode()
    s = s.lower()
    s = re.sub(r"\b(cafe|restaurante|cervejaria|snack[- ]?bar|bar|taberna|tasca|tasquinha|"
               r"pastelaria|padaria|churrasqueira|residencial|hotel|pensao|casa|quinta|"
               r"ginasio|clinica|oficina|stand|auto|lda|unipessoal|sa)\b", " ", s)
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return " ".join(s.split())


def parecido(nome_osm, nome_google):
    """Quão parecidos são os dois nomes, 0 a 1, já sem as palavras de género de negócio."""
    a, b = simples(nome_osm), simples(nome_google)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    ta, tb = set(a.split()), set(b.split())
    # um nome curto dentro do outro, com palavra inteira, conta como o mesmo negócio
    if len(a) >= 4 and (a in b or b in a):
        return 0.95
    if ta and ta.issubset(tb):
        return 0.92
    if tb and tb.issubset(ta):
        return 0.9
    comuns = ta & tb
    if comuns and max(len(w) for w in comuns) >= 5:
        return max(0.85, difflib.SequenceMatcher(None, a, b).ratio())
    return difflib.SequenceMatcher(None, a, b).ratio()


def julgar(p, c):
    """Devolve (passa, motivo). O motivo fica escrito mesmo quando passa."""
    nome_g = c.get("nome_no_google") or ""
    if (c.get("estado_negocio") or "") != "OPERATIONAL":
        return False, "no Google está %s, não OPERATIONAL" % (c.get("estado_negocio") or "sem estado")
    tipos = set(c.get("tipos") or []) | ({c["tipo"]} if c.get("tipo") else set())
    if tipos & PROIBIDOS:
        return False, "o Google diz que é %s, não um negócio deste ramo" % ", ".join(sorted(tipos & PROIBIDOS))
    s = parecido(p["nome"], nome_g)
    if s < 0.72:
        return False, "o nome no Google é «%s» e no mapa é «%s» (parecença %.2f)" % (nome_g[:40], p["nome"][:30], s)
    if c.get("lat") is None or c.get("lon") is None:
        return False, "a ficha do Google não tem coordenadas"
    d_osm = km((p["lat"], p["lon"]), (c["lat"], c["lon"]))
    if d_osm > 2.0:
        return False, "a ficha do Google fica a %.1f km do ponto do mapa (não é o mesmo sítio)" % d_osm
    d_guarda = km(GUARDA, (c["lat"], c["lon"]))
    if d_guarda > 20.0:
        return False, "fica a %.1f km da Guarda, fora dos 20 km" % d_guarda
    aceites = RAMOS.get(p.get("categoria") or "", set())
    if aceites and not (tipos & aceites):
        return False, "o ramo não bate: no mapa é %s, no Google é %s" % (p.get("categoria"), c.get("tipo") or "?")
    return True, "confere: %s, a %.1f km do ponto do mapa, parecença %.2f, %s" % (
        nome_g[:40], d_osm, s, c.get("tipo") or "sem tipo")


def pedir(caminho, corpo):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + caminho,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"],
                 "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        t = r.read().decode("utf-8")
    return json.loads(t) if t.strip() else None


def pontuar(p, c):
    n = 0
    n += min(45, 9 * len(c.get("falta") or []))
    if not c.get("site"):
        n += 10
    if c.get("telefone") or p.get("telefone"):
        n += 25
    if p.get("email"):
        n += 5
    if (c.get("n_fotos") or 0) >= 2:
        n += 5
    if (p.get("km_da_guarda") or 99) <= 8:
        n += 5
    return max(0, min(100, n))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quantos", type=int, default=130)
    a = ap.parse_args()

    linhas = json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))
    linhas.sort(key=lambda x: -(x.get("pontuacao") or 0))
    alvo = linhas[:a.quantos]
    log("PORTAO: conferir %d negocios (1 chamada ao Google cada, ~%.2f EUR)"
        % (len(alvo), len(alvo) * 0.032))

    bons, maus, fichas = [], [], {}
    for i, p in enumerate(alvo, 1):
        try:
            g = pedir("/functions/v1/ficha-google-diagnostico",
                      {"nome": p["nome"], "morada": p.get("morada") or ""})
        except Exception as ex:  # noqa: BLE001
            log("  %-28s ERRO %s" % (p["nome"][:28], str(ex)[:60]))
            continue
        candidatos = (g or {}).get("candidatos") or []
        escolhido, motivo_bom, motivos_maus = None, None, []
        for c in candidatos:
            passa, motivo = julgar(p, c)
            if passa:
                if escolhido is None or parecido(p["nome"], c.get("nome_no_google") or "") > \
                        parecido(p["nome"], escolhido.get("nome_no_google") or ""):
                    escolhido, motivo_bom = c, motivo
            else:
                motivos_maus.append(motivo)
        if escolhido:
            p["pontuacao"] = pontuar(p, escolhido)
            p["ficha_google"] = escolhido.get("estado", "por_ver")
            p["estado"] = "novo"
            if escolhido.get("telefone"):
                p["telefone"], p["sem_telefone"] = escolhido["telefone"], False
            if escolhido.get("site"):
                p["website"], p["sem_site"] = escolhido["site"], False
            p["notas"] = ("Portao de identidade OK — %s. Falta na ficha: %s"
                          % (motivo_bom, "; ".join(escolhido.get("falta") or []) or "nada"))[:900]
            fichas[p["fonte_id"]] = escolhido
            bons.append(p)
        else:
            p["estado"] = "descartado"
            p["ficha_google"] = "por_ver"
            p["notas"] = ("Descartado pelo portao de identidade: %s"
                          % ("; ".join(motivos_maus[:2]) or "o Google nao devolveu nenhuma ficha"))[:900]
            maus.append(p)
        try:
            pedir("/rest/v1/rpc/prospect_registar", {"p_chave": E["PROSPECTS_KEY"], "p_linha": p})
        except Exception as ex:  # noqa: BLE001
            log("  %-28s nao gravou: %s" % (p["nome"][:28], str(ex)[:60]))
        if i % 20 == 0:
            log("  ... %d/%d (%d passam, %d descartados)" % (i, len(alvo), len(bons), len(maus)))
        time.sleep(0.3)

    io.open(os.path.join(BASE, "fichas_boas.json"), "w", encoding="utf-8").write(
        json.dumps(fichas, ensure_ascii=False, indent=1))
    io.open(os.path.join(BASE, "prospects.json"), "w", encoding="utf-8").write(
        json.dumps(linhas, ensure_ascii=False, indent=1))

    com_fotos = [p for p in bons if (fichas[p["fonte_id"]].get("n_fotos") or 0) >= 2]
    com_fotos.sort(key=lambda x: -x["pontuacao"])
    log("FIM PORTAO: %d passam, %d descartados. Com 2+ fotos proprias: %d" % (len(bons), len(maus), len(com_fotos)))
    log("OS 14 MELHORES QUE PASSAM E TEM FOTOS:")
    for p in com_fotos[:14]:
        c = fichas[p["fonte_id"]]
        log("  %3d %-26s %-11s %-30s fotos=%-2s tel=%s"
            % (p["pontuacao"], p["nome"][:26], p["categoria"], (c["nome_no_google"] or "")[:30],
               c["n_fotos"], c.get("telefone") or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
