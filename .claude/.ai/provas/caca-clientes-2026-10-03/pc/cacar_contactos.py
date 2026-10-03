#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Cacador de contactos (missao caca-clientes-2026-10-03, Bloco 1).

PORQUE EXISTE: a varredura de 24/09 deixou 126 negocios e so 5 com email. Sem email
verificado o carteiro nao tem a quem escrever. Este script procura o email onde a lei
obriga a po-lo (contactos, rodape, politica de privacidade, termos), confirma que o
dominio recebe correio (MX) e regista de onde veio.

Fontes, por ordem: 1) site do negocio; 2) pesquisa aberta (DuckDuckGo) para quem nao tem
site; 3) Facebook/Instagram ficam como canal quando nao ha email.
Custo zero: nao chama a Places API (essa e paga).

Uso:  python cacar_contactos.py [--so ID,ID] [--seco]
Escreve por RPC `prospect_contacto_registar` (chave em C:\\BoraLocal\\_segredos\\avenca\\prospects.env).
"""
import html
import io
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
LOG = os.path.join(BASE, "cacar_contactos.log")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

# Nao sao "o site do negocio": diretorios, redes e agregadores.
NAO_E_SITE = ("facebook.com", "instagram.com", "tripadvisor.", "booking.com", "ciberforma", "beira.pt",
              "vamosja.pt", "eatbu.com", "thefork", "zomato", "google.", "newtech-guarda", "linktr.ee")
# Cadeias: o email do site e o da sede, nao o do dono da loja da Guarda.
CADEIAS = ("springfield", "lanidor", "telepizza", "decenio", "inatel", "pousadasjuventude", "tavferhoteis")
EMAIL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._%+\-]{0,63}@[A-Za-z0-9][A-Za-z0-9.\-]{1,190}\.[A-Za-z]{2,10}")
LIXO = ("sentry", "wixpress", "example.", "exemplo", "godaddy", "domain.com", "email.com", "seudominio", "yourdomain",
        "@2x", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".css", ".js", "schema.org", "w3.org", "noreply", "no-reply",
        "livroreclamacoes", "cnpd.pt", "wordpress", "user@", "nome@", "name@", "u003e", "protected")
PAGINAS = ("contacto", "contactos", "contact", "contacts", "contato", "fale-connosco", "sobre", "about",
           "privacidade", "politica-de-privacidade", "privacy", "termos", "termos-e-condicoes", "legal", "rgpd")
SITE_TIPO = ("alojamento", "clinica", "ginasio", "cabeleireiro")


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
    print(linha.encode("ascii", "replace").decode("ascii"))
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


def buscar(url, limite=600000, timeout=20):
    """Devolve (url_final, texto) ou (None, '')."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            tipo = r.headers.get("Content-Type", "")
            if "html" not in tipo and "text" not in tipo and tipo:
                return None, ""
            bruto = r.read(limite)
            return r.geturl(), bruto.decode(r.headers.get_content_charset() or "utf-8", "replace")
    except Exception as ex:
        return None, "ERRO %s" % type(ex).__name__


def emails_de(texto):
    t = html.unescape(texto)
    t = urllib.parse.unquote(t)
    t = t.replace("[at]", "@").replace("(at)", "@").replace(" [arroba] ", "@")
    achados = []
    for m in EMAIL_RE.findall(t):
        e = m.strip(".").lower()
        if any(x in e for x in LIXO):
            continue
        if e not in achados:
            achados.append(e)
    return achados


_mx = {}


def tem_mx(dominio):
    """MX (ou A, que a norma aceita como recurso) por DNS-sobre-HTTPS."""
    if dominio in _mx:
        return _mx[dominio]
    ok = False
    for tipo in ("MX", "A"):
        try:
            u = "https://dns.google/resolve?name=%s&type=%s" % (urllib.parse.quote(dominio), tipo)
            with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=15) as r:
                d = json.loads(r.read().decode("utf-8"))
            if d.get("Status") == 0 and d.get("Answer"):
                if tipo == "MX" and all(a.get("data", "").strip().endswith(" .") for a in d["Answer"]):
                    break  # "null MX": o dominio declara que nao recebe correio
                ok = True
                break
        except Exception:
            pass
    _mx[dominio] = ok
    return ok


def tokens(nome):
    n = nome.lower()
    for a, b in (("á", "a"), ("à", "a"), ("ã", "a"), ("â", "a"), ("é", "e"), ("ê", "e"), ("í", "i"), ("ó", "o"),
                 ("ô", "o"), ("õ", "o"), ("ú", "u"), ("ç", "c")):
        n = n.replace(a, b)
    return [w for w in re.findall(r"[a-z0-9]+", n)
            if len(w) >= 4 and w not in ("cafe", "restaurante", "hotel", "pastelaria", "padaria", "snack", "guarda", "casa", "quinta")]


def escolher(emails, dominio_site, nome):
    """O melhor email: mesmo dominio do site > com o nome do negocio > generico de contacto."""
    if not emails:
        return None
    tk = tokens(nome)

    def nota(e):
        loc, dom = e.split("@", 1)
        n = 0
        if dominio_site and (dom == dominio_site or dom.endswith("." + dominio_site) or dominio_site.endswith("." + dom)):
            n += 50
        if any(t in e for t in tk):
            n += 30
        if loc in ("geral", "info", "contacto", "contactos", "reservas", "comercial", "email", "mail"):
            n += 10
        if any(x in loc for x in ("webmaster", "dpo", "privacidade", "rgpd", "suporte", "support", "admin")):
            n -= 20
        return n
    return sorted(emails, key=nota, reverse=True)[0]


def dominio_de(url):
    h = urllib.parse.urlparse(url).netloc.lower()
    return h[4:] if h.startswith("www.") else h


def varrer_site(url, nome):
    """Devolve dict com email, fonte, livro, instagram, facebook, fraco."""
    r = {"emails": [], "fonte": None, "livro": None, "instagram": None, "facebook": None, "https": url.startswith("https"),
         "vivo": False, "mobile": None}
    final, pag = buscar(url)
    if not final:
        if url.startswith("http://"):
            final, pag = buscar("https://" + url[7:])
        if not final:
            return r
    r["vivo"] = True
    r["https"] = final.startswith("https")
    r["mobile"] = "viewport" in pag.lower()
    base = final
    dom = dominio_de(final)
    paginas = [(final, pag, "site:inicio")]
    # ligacoes interiores que interessam
    vistos = set()
    for href in re.findall(r'href=["\']([^"\'#]+)["\']', pag, flags=re.I):
        alvo = urllib.parse.urljoin(base, href)
        if dominio_de(alvo) != dom or alvo in vistos:
            continue
        baixo = alvo.lower()
        if any(p in baixo for p in PAGINAS):
            vistos.add(alvo)
    for alvo in list(vistos)[:6]:
        f2, p2 = buscar(alvo)
        if f2:
            paginas.append((f2, p2, "site:" + urllib.parse.urlparse(f2).path.strip("/")[:40]))
        time.sleep(0.5)
    if len(paginas) == 1:
        for cam in ("contactos", "contacto", "contact"):
            f2, p2 = buscar(urllib.parse.urljoin(base, "/" + cam))
            if f2 and p2 and not p2.startswith("ERRO"):
                paginas.append((f2, p2, "site:" + cam))
                break
    todo = ""
    for _, p, fonte in paginas:
        todo += p
        for e in emails_de(p):
            if e not in r["emails"]:
                r["emails"].append(e)
                r.setdefault("fontes", {})[e] = fonte
    baixo = todo.lower()
    r["livro"] = "livroreclamacoes.pt" in baixo
    m = re.search(r"https?://(?:www\.)?instagram\.com/([A-Za-z0-9_.]{2,40})", todo)
    if m and m.group(1) not in ("p", "explore", "accounts"):
        r["instagram"] = "https://www.instagram.com/" + m.group(1)
    m = re.search(r"https?://(?:www\.|pt-pt\.)?facebook\.com/([A-Za-z0-9_.\-]{2,80})", todo)
    if m and m.group(1) not in ("sharer", "sharer.php", "tr", "plugins", "dialog", "share"):
        r["facebook"] = "https://www.facebook.com/" + m.group(1)
    return r


def pesquisa_aberta(nome, concelho):
    """Para quem nao tem site: o que a pesquisa aberta mostra (emails nos resumos, redes)."""
    q = '"%s" %s email' % (nome, concelho or "Guarda")
    _, pag = buscar("https://html.duckduckgo.com/html/?q=" + urllib.parse.quote(q), timeout=25)
    r = {"emails": [], "instagram": None, "facebook": None}
    if not pag or pag.startswith("ERRO"):
        return r
    texto = re.sub(r"<[^>]+>", " ", pag)
    tk = tokens(nome)
    for e in emails_de(texto):
        if tk and any(t in e for t in tk):
            r["emails"].append(e)
    pag_u = urllib.parse.unquote(pag)
    m = re.search(r"instagram\.com/([A-Za-z0-9_.]{3,40})", pag_u)
    if m and m.group(1) not in ("p", "explore", "accounts", "reel") and tk and any(t in m.group(1).lower() for t in tk):
        r["instagram"] = "https://www.instagram.com/" + m.group(1)
    m = re.search(r"facebook\.com/([A-Za-z0-9_.\-]{3,80})", pag_u)
    if m and tk and any(t in m.group(1).lower() for t in tk):
        r["facebook"] = "https://www.facebook.com/" + m.group(1)
    return r


def tipo_cliente(p, tem_site_proprio):
    if p.get("categoria") in SITE_TIPO:
        return "site"
    return "parceiro-bora" if tem_site_proprio else "os-dois"


def main():
    seco = "--seco" in sys.argv
    so = None
    if "--so" in sys.argv:
        so = set(int(x) for x in sys.argv[sys.argv.index("--so") + 1].split(","))
    todos = rpc("prospects_ler", {"p_chave": E["PROSPECTS_KEY"]})
    alvos = [p for p in todos if p.get("estado") in ("novo", "proposta_rascunho", "amostra_pronta", "email_invalido")]
    if so:
        alvos = [p for p in alvos if p["id"] in so]
    log("INICIO cacador: %d alvos ativos (de %d)%s" % (len(alvos), len(todos), " [SECO]" if seco else ""))
    n_email = n_canal = 0
    for p in alvos:
        nome = p.get("nome") or ""
        web = (p.get("website") or "").strip()
        proprio = bool(web) and not any(x in web.lower() for x in NAO_E_SITE)
        cadeia = any(c in (web + " " + nome).lower().replace(" ", "") for c in CADEIAS)
        linha = {"cliente_tipo": tipo_cliente(p, proprio)}
        email = None
        fonte = None
        gancho = []
        if web and "facebook.com" in web.lower():
            linha["facebook"] = web
        if proprio and not cadeia:
            s = varrer_site(web, nome)
            if not s["vivo"]:
                gancho.append("o site %s nao abre" % dominio_de(web))
            else:
                if not s["https"]:
                    gancho.append("o site nao tem ligacao segura (https)")
                if s["mobile"] is False:
                    gancho.append("o site nao esta preparado para telemovel")
                linha["livro_reclamacoes_ok"] = bool(s["livro"])
                if not s["livro"]:
                    gancho.append("o site nao tem a ligacao ao livro de reclamacoes eletronico, que a lei exige")
                if s["instagram"]:
                    linha["instagram"] = s["instagram"]
                if s["facebook"]:
                    linha["facebook"] = s["facebook"]
                email = escolher(s["emails"], dominio_de(web), nome)
                if email:
                    fonte = s.get("fontes", {}).get(email, "site")
        elif cadeia:
            linha["canal_preferido"] = "presencial"
            linha["notas"] = "cadeia nacional: o email do site e o da sede, nao o do dono da loja"
        if not email and not cadeia and p.get("email"):
            email, fonte = p["email"].strip().lower(), "openstreetmap"
        if not email and not cadeia:
            a = pesquisa_aberta(nome, p.get("concelho"))
            time.sleep(2.5)
            if a["emails"]:
                email, fonte = a["emails"][0], "pesquisa-aberta"
            if a["instagram"] and "instagram" not in linha:
                linha["instagram"] = a["instagram"]
            if a["facebook"] and "facebook" not in linha:
                linha["facebook"] = a["facebook"]
        if not proprio and not cadeia:
            gancho.insert(0, "nao tem site proprio")
        if email:
            ok = bool(EMAIL_RE.fullmatch(email)) and tem_mx(email.split("@", 1)[1])
            linha.update({"email": email, "email_verificado": ok, "email_fonte": fonte})
            if ok:
                linha["canal_preferido"] = "email"
                n_email += 1
        if "canal_preferido" not in linha:
            if linha.get("instagram") or p.get("instagram"):
                linha["canal_preferido"] = "instagram"
            elif linha.get("facebook") or p.get("facebook"):
                linha["canal_preferido"] = "facebook"
            if "canal_preferido" in linha:
                n_canal += 1
        if gancho:
            linha["gancho"] = "; ".join(gancho)
        log("  %-4s %-34s email=%s (%s) canal=%s gancho=%s" % (
            p["id"], nome[:34], linha.get("email", "-"), linha.get("email_fonte", "-"),
            linha.get("canal_preferido", "-"), (linha.get("gancho") or "-")[:70]))
        if not seco:
            try:
                rpc("prospect_contacto_registar", {"p_chave": E["PROSPECTS_KEY"], "p_id": p["id"], "p_linha": linha})
            except Exception as ex:
                log("  ERRO a gravar %s: %s" % (p["id"], ex))
    log("FIM cacador: %d alvos, %d com email verificado, %d so com rede social" % (len(alvos), n_email, n_canal))


if __name__ == "__main__":
    main()
