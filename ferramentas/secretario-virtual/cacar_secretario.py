#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Cacador do Secretario Virtual (missao unica 03/10, bloco 5a).

PORQUE EXISTE: o assistente de WhatsApp da Mister Navalha funciona; vende-se a negocios de
TODO o Portugal que trabalham por WhatsApp (barbearias, cabeleireiros, estetica, clinicas,
explicacoes, takeaway, oficinas). Reaproveita o cacador do caca-clientes (mesmas funcoes de
email e MX) com o alvo novo `cliente_tipo = 'secretario-virtual'`.

Regras (Danilo 04/10):
  - so email PUBLICO e verificado (dominio recebe correio); nada de WhatsApp a frio;
  - so entra quem mostra no site que marca/encomenda por WhatsApp (wa.me, api.whatsapp.com,
    ou a palavra WhatsApp junto de marcar/reservar/encomendar);
  - guarda canal (email), email, fonte, e um gancho curto para o email.
Fonte: OpenStreetMap (Overpass, gratis). Custo zero.

Uso:
  python cacar_secretario.py --seco [--limite 30]   # so le e escreve CSV ao lado (nada vai a base)
  python cacar_secretario.py [--limite 30]          # regista por RPC secretario_prospect_registar
"""
import csv
import json
import os
import random
import re
import sys
import time
import urllib.parse
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
CACADOR = os.path.join(AQUI, "..", "..", ".claude", ".ai", "provas", "caca-clientes-2026-10-03", "pc")
sys.path.insert(0, os.path.abspath(CACADOR))
import cacar_contactos as C  # noqa: E402  (buscar, varrer_site, escolher, dominio_de, tem_mx, rpc, E)

OVERPASS = "https://overpass-api.de/api/interpreter"
# categoria Bora -> filtro OSM + gancho do email
ALVOS = {
    "barbearia":    ('nwr["shop"="hairdresser"]["hairdresser"="barber"]', "Respondem às marcações fora de horas, ou ficam por responder até ao dia seguinte?"),
    "cabeleireiro": ('nwr["shop"="hairdresser"]', "Quantas marcações chegam por WhatsApp quando estão com as mãos ocupadas?"),
    "estetica":     ('nwr["shop"="beauty"]', "Quantas marcações chegam por WhatsApp quando estão com uma cliente?"),
    "clinica":      ('nwr["amenity"~"^(dentist|clinic)$"]', "Os pedidos de consulta por WhatsApp têm resposta à noite e ao fim de semana?"),
    "takeaway":     ('nwr["amenity"="fast_food"]', "Os pedidos por WhatsApp na hora de ponta têm resposta a tempo?"),
    "oficina":      ('nwr["shop"="car_repair"]', "Os pedidos de orçamento por WhatsApp têm resposta enquanto estão debaixo de um carro?"),
    "explicacoes":  ('nwr["amenity"="prep_school"]', "As perguntas dos pais por WhatsApp têm resposta fora das aulas?"),
}
WA_RE = re.compile(r"wa\.me/|api\.whatsapp\.com|whatsapp", re.I)
ACAO_RE = re.compile(r"marca|reserv|agend|encomend|pedido|orçament|orcament|consult", re.I)
PUBLICO_DOM = re.compile(r"(min-saude|\.gov|\.edu|\.mun|cm-[a-z]|ulsam|ulsne|sns)\.?", re.I)
PUBLICO_NOME = re.compile(r"centro de sa[uú]de|hospital|\bUSF\b|\bULS\b|\bUCSP\b|agrupamento de escolas|c[aâ]mara municipal", re.I)
CSV_SAIDA =os.path.join(AQUI, "cacar_secretario_%s.csv" % time.strftime("%Y%m%d"))


def overpass(filtro, n):
    q = '[out:json][timeout:120];area["ISO3166-1"="PT"][admin_level=2]->.pt;(%s["website"](area.pt);%s["contact:website"](area.pt););out tags %d;' % (filtro, filtro, n)
    req = urllib.request.Request(OVERPASS, data=urllib.parse.urlencode({"data": q}).encode(),
                                 headers={"User-Agent": "BoraGuarda-secretario/1.0 (boraguarda.com)"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read().decode("utf-8")).get("elements", [])


def sinal_whatsapp(texto):
    """True se o site mostra que trabalham por WhatsApp (link direto ou a palavra junto de uma accao)."""
    if re.search(r"wa\.me/|api\.whatsapp\.com", texto, re.I):
        return True
    for m in WA_RE.finditer(texto):
        janela = texto[max(0, m.start() - 160): m.end() + 160]
        if ACAO_RE.search(janela):
            return True
    return False


def main():
    seco = "--seco" in sys.argv
    limite = int(sys.argv[sys.argv.index("--limite") + 1]) if "--limite" in sys.argv else 30
    candidatos = []
    for cat, (filtro, gancho) in ALVOS.items():
        try:
            els = overpass(filtro, 400)
        except Exception as ex:
            C.log("overpass %s falhou: %s" % (cat, ex))
            continue
        random.shuffle(els)
        for el in els:
            t = el.get("tags", {})
            site = t.get("website") or t.get("contact:website")
            if not site or any(x in site for x in C.NAO_E_SITE):
                continue
            candidatos.append((cat, gancho, t, site if site.startswith("http") else "http://" + site))
        time.sleep(2)
    random.shuffle(candidatos)
    C.log("secretario: %d candidatos com site; a ver %d" % (len(candidatos), limite))

    achados, vistos = [], set()
    for cat, gancho, t, site in candidatos:
        if len(achados) >= limite:
            break
        dom = C.dominio_de(site)
        if dom in vistos or any(c in dom for c in C.CADEIAS):
            continue
        vistos.add(dom)
        final, pag = C.buscar(site)
        if not final or pag.startswith("ERRO") or not sinal_whatsapp(pag):
            continue
        nome = t.get("name") or dom
        r = C.varrer_site(final, nome)
        email = C.escolher(r.get("emails") or [], C.dominio_de(final), nome)
        if not email or not C.tem_mx(email.split("@", 1)[1]):
            continue
        # Servicos publicos (SNS, escolas, camaras) nao sao clientes: fora.
        if PUBLICO_DOM.search(email.split("@", 1)[1]) or PUBLICO_NOME.search(nome):
            continue
        linha = {
            "nome": nome, "categoria": cat, "concelho": t.get("addr:city") or t.get("addr:municipality") or "",
            "morada": " ".join(x for x in (t.get("addr:street"), t.get("addr:housenumber"), t.get("addr:postcode")) if x),
            "website": final, "email": email, "email_fonte": (r.get("fontes") or {}).get(email, "site"),
            "instagram": r.get("instagram") or "", "facebook": r.get("facebook") or "",
            "telefone": t.get("phone") or t.get("contact:phone") or "", "gancho": gancho,
            "fonte_id": "osm:%s" % t.get("name", dom),
        }
        achados.append(linha)
        C.log("  + %s (%s, %s) %s" % (nome, cat, linha["concelho"], email))
        if not seco:
            try:
                v = C.rpc("secretario_prospect_registar", {"p_chave": C.E.get("PROSPECTS_KEY", ""), "p_linha": linha})
                C.log("    registado: %s" % v)
            except Exception as ex:
                C.log("    falhou registar: %s" % ex)
        time.sleep(1)

    with open(CSV_SAIDA, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(achados[0].keys()) if achados else ["nome"])
        w.writeheader()
        for a in achados:
            w.writerow(a)
    C.log("secretario: %d prospects com WhatsApp + email verificado -> %s" % (len(achados), CSV_SAIDA))


if __name__ == "__main__":
    main()
