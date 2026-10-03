#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Pecas simples do caca-clientes (missao caca-clientes-2026-10-03, Bloco 2).

Regra: maquete ANTES do contacto, um link so por negocio. Quem tem maquete premium sai com
ela; os outros levam uma pagina privada em boraguarda.com/avenca/<token>/ (noindex):
  - cliente_tipo 'parceiro-bora' -> "a tua loja no Bora": como a loja apareceria na app;
  - os restantes                -> "o que a Bora preparou": o que vimos e o que fariamos.
So entra o que e publico e do proprio negocio, mais o que o cacador MEDIU no site dele.
Nao ha fotos de terceiros, avaliacoes inventadas nem precos.

Escreve em bora-site/avenca/<token>/index.html e regista em prospect_amostras.
A publicacao e depois, com o deploy-cloudflare.sh do bora-site.
Uso: python pecas.py [--seco]
"""
import hashlib
import html
import io
import json
import os
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
SITE = r"C:\BoraLocal\projetosflutter\bora-site"
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
LOG = os.path.join(BASE, "pecas.log")
E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if _l and not _l.startswith("#") and "=" in _l:
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()

NOMES = {"restaurante": "Restaurante", "cafe": "Café", "padaria": "Padaria e pastelaria", "mercearia": "Mercearia",
         "farmacia": "Farmácia", "talho": "Talho", "bar": "Bar", "loja": "Loja", "florista": "Florista",
         "lavandaria": "Lavandaria", "cabeleireiro": "Cabeleireiro e estética", "alojamento": "Alojamento",
         "clinica": "Clínica", "imobiliaria": "Imobiliária", "advogado": "Advocacia", "ginasio": "Ginásio", "oficina": "Oficina"}

CSS = """:root{--verde:#16A34A;--laranja:#F97316;--tinta:#0f172a;--cinza:#475569;--fundo:#f8fafc}
*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:var(--tinta);background:var(--fundo);line-height:1.55}
main{max-width:720px;margin:0 auto;padding:28px 18px 60px}
.marca{font-weight:800;color:var(--verde);font-size:15px;letter-spacing:.02em}
h1{font-size:30px;line-height:1.15;margin:10px 0 8px}h2{font-size:19px;margin:30px 0 10px}
p{margin:0 0 12px;color:var(--cinza)}ul{margin:0 0 12px;padding-left:20px;color:var(--cinza)}li{margin-bottom:6px}
.cartao{background:#fff;border:1px solid #e2e8f0;border-radius:16px;padding:18px;margin:14px 0;box-shadow:0 1px 2px rgba(15,23,42,.04)}
.loja{display:flex;gap:14px;align-items:center}.selo{width:64px;height:64px;border-radius:14px;background:var(--verde);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:26px;flex:none}
.loja b{font-size:18px;display:block}.loja span{color:var(--cinza);font-size:14px}
.etiqueta{display:inline-block;background:#dcfce7;color:#166534;border-radius:999px;padding:3px 10px;font-size:12px;font-weight:700;margin-top:6px}
.botao{display:inline-block;background:var(--laranja);color:#fff;text-decoration:none;font-weight:800;padding:14px 22px;border-radius:12px;margin-top:6px}
.nota{font-size:13px;color:#64748b;margin-top:26px}"""


FRASES = [
    ("nao tem site proprio", "ainda não têm um site próprio"),
    ("nao tem ligacao segura", "o vosso site não tem ligação segura (falta o https)"),
    ("nao esta preparado para telemovel", "o vosso site não está preparado para telemóvel"),
    ("livro de reclamacoes", "falta no vosso site a ligação ao livro de reclamações eletrónico, que a lei exige"),
]


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


def token_de(fonte_id):
    return hashlib.sha256((fonte_id + "|avenca-bora-2026").encode()).hexdigest()[:14]


def esc(s):
    return html.escape(str(s or ""))


def moldura(titulo, corpo):
    return ("<!doctype html><html lang=\"pt-PT\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            "<meta name=\"robots\" content=\"noindex,nofollow\"><title>%s</title><style>%s</style></head>"
            "<body><main><div class=\"marca\">BORA APP — GUARDA</div>%s"
            "<p class=\"nota\">Página privada, feita só para este negócio. Não aparece no Google. "
            "Usámos apenas informação pública do próprio negócio. Se preferirem que a apaguemos, basta dizer.</p>"
            "</main></body></html>") % (esc(titulo), CSS, corpo)


def contacto():
    return ("<h2>Faz sentido conversar?</h2><p>Basta responder ao email que vos enviámos. Passamos aí, sem compromisso.</p>"
            "<a class=\"botao\" href=\"mailto:boraappbora@gmail.com\">Responder à Bora</a>")


def pagina_parceiro(p):
    nome = esc(p["nome"])
    cat = NOMES.get(p.get("categoria"), "Loja")
    onde = esc(p.get("morada") or p.get("concelho") or "Guarda")
    corpo = ("<h1>%s na Bora</h1>"
             "<p>A Bora é a aplicação de entregas e serviços da Guarda. Está em fase de arranque: a app está construída "
             "e a ser testada com alguns comerciantes da cidade. Preparámos esta página para verem como a vossa casa apareceria lá dentro.</p>"
             "<div class=\"cartao\"><div class=\"loja\"><div class=\"selo\">%s</div><div><b>%s</b><span>%s · %s</span><br>"
             "<span class=\"etiqueta\">Entrega por estafetas da Guarda</span></div></div></div>"
             "<h2>Como funciona para a loja</h2><ul>"
             "<li>O primeiro mês é grátis.</li>"
             "<li>Não há mensalidade: a Bora só ganha quando a loja vende pela app.</li>"
             "<li>Os pedidos chegam ao telemóvel ou ao computador da loja; a loja aceita e prepara.</li>"
             "<li>A entrega é feita por estafetas da Guarda.</li>"
             "<li>O cliente paga por MB Way ou cartão.</li>"
             "<li>O menu e os preços são os vossos; mudam quando quiserem.</li></ul>"
             "<h2>O que precisamos de vocês</h2><p>O menu (uma fotografia serve), o horário e dez minutos de conversa. "
             "Montamos a loja na app e mostramos antes de ficar visível para os clientes.</p>%s") % (
        nome, esc(p["nome"][:1].upper()), nome, esc(cat), onde, contacto())
    return moldura("%s na Bora" % p["nome"], corpo)


def pagina_site(p):
    nome = esc(p["nome"])
    gancho = p.get("gancho") or ""
    if any(c in gancho for c in "áéíóúãõç"):  # escrito a mao
        vimos = [g.strip() for g in gancho.split(";") if g.strip()]
    else:  # o que o cacador mediu, em portugues como deve ser ("nao abre" fica de fora: nao esta confirmado)
        vimos = [frase for chave, frase in FRASES if chave in gancho]
    itens = "".join("<li>%s.</li>" % esc(g[:1].upper() + g[1:]) for g in vimos) or "<li>Uma presença online que não mostra tudo o que a casa vale.</li>"
    corpo = ("<h1>%s — o que a Bora preparou</h1>"
             "<p>Somos a Bora, da Guarda. Fazemos sites e tratamos da presença digital de negócios da região. "
             "Antes de pedir uma conversa, olhámos com atenção para a vossa presença online.</p>"
             "<h2>O que vimos</h2><ul>%s</ul>"
             "<h2>O que fazíamos por vocês</h2><ul>"
             "<li>Um site próprio, rápido e feito para telemóvel, com as vossas fotografias e os vossos textos.</li>"
             "<li>Contacto e pedido directo (telefone, WhatsApp ou reserva), sem depender de intermediários.</li>"
             "<li>O que a lei pede: ligação ao livro de reclamações electrónico e política de privacidade.</li>"
             "<li>Ficha do Google arrumada: horário, morada, fotografias e ligação ao site.</li></ul>"
             "<div class=\"cartao\"><b>Como trabalhamos</b><p style=\"margin-top:8px\">Primeiro mostramos, depois falamos. "
             "Se quiserem, fazemos uma primeira versão do vosso site com o vosso material, para verem antes de decidir.</p></div>%s") % (
        nome, itens, contacto())
    return moldura("%s — o que a Bora preparou" % p["nome"], corpo)


def main():
    seco = "--seco" in sys.argv
    todos = rpc("prospects_ler", {"p_chave": E["PROSPECTS_KEY"]})
    alvos = [p for p in todos if p.get("email_verificado") and p.get("estado") in ("novo", "proposta_rascunho", "amostra_pronta", "pronta")
             and not p["fonte_id"].startswith("manual:")]
    log("INICIO pecas: %d com email verificado%s" % (len(alvos), " [SECO]" if seco else ""))
    n = {"parceiro": 0, "site": 0, "ja_tinha": 0}
    for p in alvos:
        tok = token_de(p["fonte_id"])
        pasta = os.path.join(SITE, "avenca", tok)
        fich = os.path.join(pasta, "index.html")
        if os.path.exists(fich) and not ("--refazer" in sys.argv and "O que fazíamos por vocês" in io.open(fich, encoding="utf-8").read()):
            n["ja_tinha"] += 1
            continue
        parceiro = p.get("cliente_tipo") == "parceiro-bora"
        pag = pagina_parceiro(p) if parceiro else pagina_site(p)
        n["parceiro" if parceiro else "site"] += 1
        if seco:
            continue
        os.makedirs(pasta, exist_ok=True)
        io.open(os.path.join(pasta, "index.html"), "w", encoding="utf-8", newline=chr(10)).write(pag)
        rpc("prospect_amostra_registar", {"p_chave": E["PROSPECTS_KEY"], "p_prospect": p["id"],
            "p_linha": {"link_unico": "https://boraguarda.com/avenca/%s/" % tok, "mini_site": "avenca/%s/index.html" % tok,
                        "publicacoes": [], "diagnostico_google": {"peca": "parceiro-bora" if parceiro else "site"}}})
        log("  %s %-34s /avenca/%s/" % ("loja" if parceiro else "site", p["nome"][:34], tok))
    log("FIM pecas: %s" % json.dumps(n))


if __name__ == "__main__":
    main()
