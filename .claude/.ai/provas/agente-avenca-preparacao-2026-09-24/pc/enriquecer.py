#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Confere no Google o que o OpenStreetMap diz — e volta a pontuar (avença, 24/09/2026).

PORQUE EXISTE: a primeira pontuação saiu do OpenStreetMap e mentiu. O «melhor candidato»
era o Restaurante Belo Horizonte, marcado como sem site e sem telefone; no Google tem site,
telefone, horário, 10 fotos e 1112 avaliações. Mandar-lhe uma proposta a dizer «vocês não
têm presença online» era o caminho mais curto para levar com a porta na cara.

Por isso: para os candidatos de topo pergunta-se ao Google (pela Edge Function
`ficha-google-diagnostico`, que guarda a chave do lado do servidor) o que a ficha tem mesmo,
e a pontuação passa a sair DAÍ. Só depois se escolhem os 10 para amostra.

Custo: uma chamada à Places API por negócio. É dinheiro do Danilo, por isso o `--quantos`
tem tecto e o valor pedido fica escrito no log.
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
LOG = os.path.join(BASE, "prospeccao.log")
E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if "=" in _l and not _l.startswith("#"):
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()

PESO_CATEGORIA = ("restaurante", "cafe", "cabeleireiro", "barbearia", "estetica",
                  "ginasio", "alojamento", "oficina", "pneus", "bar")


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def pedir(caminho, corpo):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + caminho,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"],
                 "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        texto = r.read().decode("utf-8")
    return json.loads(texto) if texto.strip() else None


def pontuar(p, g):
    """Agora com a ficha Google na mão. Metade oportunidade, metade conseguirmos falar."""
    n = 0
    if not g or g.get("estado") == "sem_ficha":
        n += 30                                  # não existir no Google é o buraco maior
    else:
        falta = g.get("falta") or []
        n += min(45, 9 * len(falta))             # cada buraco real vale, com tecto
        if not g.get("site"):
            n += 10                              # o site é o que a avença entrega primeiro
    tel = (g or {}).get("telefone") or p.get("telefone")
    if tel:
        n += 25                                  # sem forma de falar, não há negócio
    if p.get("email"):
        n += 5
    if p.get("categoria") in PESO_CATEGORIA:
        n += 10
    if (p.get("km_da_guarda") or 99) <= 8:
        n += 5
    return max(0, min(100, n))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quantos", type=int, default=40, help="quantos negocios conferir no Google")
    a = ap.parse_args()
    a.quantos = max(1, min(a.quantos, 120))

    linhas = json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))
    linhas.sort(key=lambda x: -(x.get("pontuacao") or 0))
    alvo = linhas[:a.quantos]
    log("ENRIQUECER: %d negocios ao Google (1 chamada cada, ~%.2f EUR de Places)"
        % (len(alvo), len(alvo) * 0.032))

    diagnosticos, mudou, sem_ficha, completas = {}, 0, 0, 0
    for i, p in enumerate(alvo, 1):
        try:
            g = pedir("/functions/v1/ficha-google-diagnostico",
                      {"nome": p["nome"], "morada": p.get("morada") or ""})
        except Exception as ex:  # noqa: BLE001
            log("  %s: falhou (%s)" % (p["nome"][:30], str(ex)[:80]))
            continue
        if not g or not g.get("ok"):
            log("  %s: sem resposta util (%s)" % (p["nome"][:30], str(g)[:80]))
            continue
        diagnosticos[p["fonte_id"]] = g
        antes = p.get("pontuacao")
        p["pontuacao"] = pontuar(p, g)
        p["ficha_google"] = g.get("estado", "por_ver")
        if g.get("telefone") and not p.get("telefone"):
            p["telefone"] = g["telefone"]
            p["sem_telefone"] = False
        if g.get("site"):
            p["website"] = g["site"]
            p["sem_site"] = False
        p["notas"] = ("OpenStreetMap + ficha Google conferida. %s"
                      % ("; ".join(g.get("falta") or []) or "ficha completa"))[:900]
        if g.get("estado") == "sem_ficha":
            sem_ficha += 1
        if g.get("estado") == "completa":
            completas += 1
        if antes != p["pontuacao"]:
            mudou += 1
        try:
            pedir("/rest/v1/rpc/prospect_registar", {"p_chave": E["PROSPECTS_KEY"], "p_linha": p})
        except Exception as ex:  # noqa: BLE001
            log("  %s: nao gravou (%s)" % (p["nome"][:30], str(ex)[:80]))
        if i % 10 == 0:
            log("  ... %d/%d" % (i, len(alvo)))
        time.sleep(0.4)

    io.open(os.path.join(BASE, "diagnosticos.json"), "w", encoding="utf-8").write(
        json.dumps(diagnosticos, ensure_ascii=False, indent=1))
    io.open(os.path.join(BASE, "prospects.json"), "w", encoding="utf-8").write(
        json.dumps(linhas, ensure_ascii=False, indent=1))

    alvo.sort(key=lambda x: -(x.get("pontuacao") or 0))
    log("FIM: %d conferidos, %d mudaram de pontuacao, %d sem ficha no Google, %d com ficha completa"
        % (len(diagnosticos), mudou, sem_ficha, completas))
    log("TOP 10 depois da conferencia:")
    for x in alvo[:10]:
        g = diagnosticos.get(x["fonte_id"]) or {}
        log("  %3d  %-30s %-11s %s | falta: %s"
            % (x["pontuacao"], x["nome"][:30], x["categoria"], g.get("estado", "?"),
               "; ".join((g.get("falta") or []))[:90] or "nada"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
