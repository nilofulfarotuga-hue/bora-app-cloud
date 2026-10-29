"""Moradas escritas no WhatsApp -> coordenadas (missao-geral-2026-10-28, Bloco 4).

Usa o Google Geocoding com a MESMA chave do servidor que a Edge Function places-proxy usa
(env GOOGLE_MAPS_SERVER_KEY ou public.server_config 'google_maps_server_key', que so a chave de
servico le). A escolha do resultado e a porta da app (lib/services/place_autocomplete_service.dart:
escolherMelhorNaGuarda + partilhaPalavra, prova web de 15/10): caixa de ~30 km a volta da Guarda,
nunca o 1.o resultado cru, nada de "Rua, Portugal" a toa, nada de Lisboa para quem escreveu Guarda.
O cliente ve SEMPRE a morada encontrada e confirma antes do resumo.
"""
import json
import math
import os
import re
import unicodedata
import urllib.parse
import urllib.request

import db

GUARDA = (40.5373, -7.2657)  # lib/config/maps_config.dart (kGuardaBiasLat/Lng)
CAIXA = "40.27,-7.62|40.81,-6.91"  # ~30 km a volta do centro
RAIO_GUARDA_KM = 30

TIPOS_LARGOS = {"locality", "political", "country", "administrative_area_level_1", "administrative_area_level_2",
                "administrative_area_level_3", "administrative_area_level_4", "colloquial_area"}
GENERICAS = {"rua", "avenida", "av", "largo", "praca", "travessa", "estrada", "alameda", "bairro", "beco", "calcada",
             "quinta", "urbanizacao", "lugar", "sitio", "de", "da", "do", "das", "dos", "e", "a", "o", "n", "no", "num",
             "numero", "lote", "esq", "dto", "guarda", "portugal", "cidade", "dr", "doutor"}


def haversine_km(lat1, lng1, lat2, lng2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _sem_acentos(s):
    return unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode().lower()


def palavras(s):
    return {w for w in re.split(r"[^a-z0-9]+", _sem_acentos(s)) if len(w) >= 3 and w not in GENERICAS and not w[0].isdigit()}


def partilha_palavra(escrito, encontrado):
    """O resultado tem pelo menos uma palavra 'a serio' do que o cliente escreveu."""
    pedidas = palavras(escrito)
    return True if not pedidas else bool(pedidas & palavras(encontrado))


def escolher_melhor_na_guarda(candidatos, exigir_guarda=True, texto=None):
    """candidatos = [{lat, lng, morada, tipos}] -> o melhor na Guarda, ou None."""
    precisos = [c for c in candidatos
                if (not c.get("tipos") or any(t not in TIPOS_LARGOS for t in c["tipos"]))
                and (texto is None or partilha_palavra(texto, c.get("morada") or ""))]
    for c in precisos:
        if "guarda" in _sem_acentos(c.get("morada")) or haversine_km(GUARDA[0], GUARDA[1], c["lat"], c["lng"]) <= RAIO_GUARDA_KM:
            return c
    return None if exigir_guarda or not precisos else precisos[0]


def variantes(texto):
    """Texto todo (com a Guarda no fim, se nao a tiver) e depois sem numero de porta/andar."""
    t = re.sub(r"\s+", " ", (texto or "").strip(" ,."))
    if not t:
        return []
    com_cidade = t if "guarda" in _sem_acentos(t) else t + ", Guarda"
    partes = [p.strip() for p in com_cidade.split(",") if p.strip()]
    rua = re.sub(r"\s+(n\.?\s*[º°o]?\s*)?\d+\w*\b.*$", "", partes[0], flags=re.I).strip()
    resto = [p for p in partes[1:]
             if re.match(r"^\d{4}-\d{3}", p) or not re.fullmatch(r"(n\.?\s*[º°o]?\s*)?\d+\s*[º°]?\s*\w{0,5}\.?", p, flags=re.I)]
    sem_numero = ", ".join([rua] + resto) if rua else com_cidade
    out = []
    for v in (com_cidade, sem_numero):
        if v and v not in out:
            out.append(v)
    return out


def _chave():
    k = os.environ.get("GOOGLE_MAPS_SERVER_KEY", "").strip()
    if k:
        return k
    r = db.ler("server_config", "chave=eq.google_maps_server_key", "valor")
    if not r or not r[0].get("valor"):
        raise RuntimeError("sem chave google (env GOOGLE_MAPS_SERVER_KEY ou server_config)")
    return r[0]["valor"]


def _google(endereco):
    url = ("https://maps.googleapis.com/maps/api/geocode/json?address=" + urllib.parse.quote(endereco)
           + "&bounds=" + urllib.parse.quote(CAIXA) + "&components=country:PT&region=pt&language=pt-PT&key=" + _chave())
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=10) as r:
        j = json.load(r)
    if j.get("status") not in ("OK", "ZERO_RESULTS"):
        raise RuntimeError("google geocode " + str(j.get("status")))
    out = []
    for x in j.get("results") or []:
        loc = (x.get("geometry") or {}).get("location") or {}
        comp = {t: c.get("long_name") for c in x.get("address_components") or [] for t in c.get("types") or []}
        out.append({"lat": loc.get("lat"), "lng": loc.get("lng"), "morada": x.get("formatted_address") or "",
                    "tipos": x.get("types") or [], "rua": " ".join(filter(None, [comp.get("route"), comp.get("street_number")])) or None,
                    "codigo_postal": comp.get("postal_code"), "cidade": comp.get("locality") or comp.get("administrative_area_level_2")})
    return [c for c in out if c["lat"] is not None]


def geocodificar(texto, pedir=None):
    """-> {lat, lng, morada, rua, codigo_postal, cidade} ou None. `pedir` substitui o Google nos testes."""
    pedir = pedir or _google
    for v in variantes(texto):
        try:
            c = escolher_melhor_na_guarda(pedir(v), exigir_guarda=True, texto=texto)
        except Exception:
            c = None
        if c:
            return c
    return None
