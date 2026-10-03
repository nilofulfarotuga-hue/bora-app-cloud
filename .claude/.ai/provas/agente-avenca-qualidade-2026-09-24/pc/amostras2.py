#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Amostras v2 da avença — com fotos reais e publicações já em imagem.

Missão agente-avenca-qualidade-2026-09-24. A v1 tinha dois defeitos que a revisão apanhou:
casamentos errados no Google (resolvido no `portao.py`) e publicações que eram TEXTO DE
MARCAÇÃO — «Foto do espaço ou do prato do dia» — em vez de imagens. Aqui as publicações são
ficheiros PNG 1080×1080, feitos com as fotos públicas do próprio negócio.

REGRA DE HONESTIDADE: na imagem e na legenda só entra o que se prova pela ficha do Google.
A estrela e o número de avaliações só aparecem se existirem mesmo; o horário só se a ficha o
tiver. Nada de «o melhor da cidade» nem de promessas que não são nossas para fazer.

Uso:  python amostras2.py [--quantos 10]
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import sys
import time
import unicodedata
import urllib.request

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
SITE = r"C:\BoraLocal\projetosflutter\bora-site"
FOTOS = os.path.join(BASE, "fotos")
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
FONTE = r"C:\BoraLocal\projetosflutter\bora_app\assets\fonts\Inter-VariableFont.ttf"
FONTE_ALT = r"C:\Windows\Fonts\segoeuib.ttf"
PRECO = 149
VERDE, LARANJA = (22, 163, 74), (249, 115, 22)

E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if "=" in _l and not _l.startswith("#"):
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()

# Os quatro que a revisão do Claude.ai aprovou à mão: entram sempre.
APROVADOS = ("Café o Redondo", "LuMiar", "Café Dorna", "Arcada")

# A categoria vive sem acentos na base (veio do mapa). Na imagem e na pagina escreve-se em
# portugues a serio: a 1.a versao pos "Cafe · Guarda" na arte, sem acento.
ROTULO = {"cafe": "Café", "restaurante": "Restaurante", "bar": "Bar", "padaria": "Padaria",
          "talho": "Talho", "cabeleireiro": "Cabeleireiro", "estetica": "Estética",
          "oficina": "Oficina", "pneus": "Pneus", "ginasio": "Ginásio", "clinica": "Clínica",
          "alojamento": "Alojamento", "loja": "Loja", "outro": "Negócio"}


def rotulo(cat):
    return ROTULO.get((cat or "").strip().lower(), (cat or "Negócio").capitalize())


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(os.path.join(BASE, "prospeccao.log"), "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def pedir(caminho, corpo, bruto=False):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + caminho,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"],
                 "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        dados = r.read()
    if bruto:
        return dados
    t = dados.decode("utf-8")
    return json.loads(t) if t.strip() else None


def token_de(fonte_id):
    return hashlib.sha256((fonte_id + "|avenca-bora-2026").encode()).hexdigest()[:14]


def esc(s):
    return str(s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def sem_acentos(s):
    return unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()


def letra(tam, negrito=True):
    try:
        f = ImageFont.truetype(FONTE, tam)
        try:
            f.set_variation_by_axes([700 if negrito else 400])
        except Exception:  # noqa: BLE001
            pass
        return f
    except Exception:  # noqa: BLE001
        return ImageFont.truetype(FONTE_ALT, tam)


def baixar_fotos(ficha, token, quantas=3):
    """Traz as fotos públicas do negócio, pela função (a chave Google nunca sai do servidor)."""
    destino = os.path.join(FOTOS, token)
    os.makedirs(destino, exist_ok=True)
    caminhos = []
    for i, nome in enumerate((ficha.get("fotos") or [])[:quantas], 1):
        alvo = os.path.join(destino, "foto%d.jpg" % i)
        if not os.path.exists(alvo):
            try:
                dados = pedir("/functions/v1/ficha-google-diagnostico",
                              {"foto": nome, "largura": 1400}, bruto=True)
            except Exception as ex:  # noqa: BLE001
                log("    foto %d falhou: %s" % (i, str(ex)[:70]))
                continue
            if len(dados) < 5000 or dados[:1] == b"{":
                log("    foto %d nao veio imagem" % i)
                continue
            io.open(alvo, "wb").write(dados)
        caminhos.append(alvo)
    return caminhos


def quadrado(caminho, lado=1080):
    im = Image.open(caminho).convert("RGB")
    l, a = im.size
    m = min(l, a)
    im = im.crop(((l - m) // 2, (a - m) // 2, (l - m) // 2 + m, (a - m) // 2 + m))
    return im.resize((lado, lado), Image.LANCZOS)


def texto_centrado(d, y, txt, fonte, cor=(255, 255, 255), largura=1080, contorno=6):
    """Branco com contorno preto: nao se pode contar com a foto ser escura naquele sitio.

    Medido a 24/09: numa esplanada ao sol, o veu deixava o fundo a 87 de brilho e o titulo
    branco quase nao se lia. O contorno resolve em qualquer foto, clara ou escura.
    """
    caixa = d.textbbox((0, 0), txt, font=fonte, stroke_width=contorno)
    d.text(((largura - (caixa[2] - caixa[0])) / 2, y), txt, font=fonte, fill=cor,
           stroke_width=contorno, stroke_fill=(0, 0, 0))
    return y + (caixa[3] - caixa[1])


def peca_imagem(foto, titulo, linha, rodape, destino):
    """1080×1080: a foto do negócio, escurecida em baixo, com texto curto por cima.

    O texto é curto de propósito: as regras destiladas do radar de vídeos dizem que texto
    comprido em cima da imagem afasta o dedo. A marca da Bora só aparece no canto, pequena.
    """
    im = quadrado(foto)
    # Véu escuro em baixo, para o texto se ler sem tapar a comida. Curva suave e FORTE no
    # fundo (a 1.a tentativa usou um desfoque que fazia uma mancha e o texto quase nao se lia).
    veu = Image.new("L", (1080, 1080), 0)
    dv = ImageDraw.Draw(veu)
    inicio = 430
    for y in range(inicio, 1080):
        t = (y - inicio) / float(1080 - inicio)
        dv.line([(0, y), (1080, y)], fill=int(250 * (t ** 1.1)))
    preto = Image.new("RGB", (1080, 1080), (0, 0, 0))
    im = Image.composite(preto, im, veu)
    d = ImageDraw.Draw(im)

    f_tit, f_lin, f_rod = letra(78), letra(44, False), letra(30, False)
    # título pode partir em duas linhas
    palavras, linhas, atual = titulo.split(), [], ""
    for p in palavras:
        teste = (atual + " " + p).strip()
        if d.textlength(teste, font=f_tit) > 980 and atual:
            linhas.append(atual); atual = p
        else:
            atual = teste
    linhas.append(atual)
    y = 1080 - 120 - (len(linhas) * 92) - (52 if linha else 0)
    for ln in linhas:
        y = texto_centrado(d, y, ln, f_tit) + 30
    if linha:
        y = texto_centrado(d, y + 6, linha, f_lin, (240, 240, 240), contorno=4) + 26
    d.rounded_rectangle([390, 1080 - 86, 690, 1080 - 30], 28, fill=VERDE)
    texto_centrado(d, 1080 - 74, rodape, f_rod, contorno=0)
    im.save(destino, "PNG", optimize=True)
    return destino


def pecas_do_negocio(p, g, fotos, pasta, token):
    """Duas publicações, em imagem, só com o que se prova."""
    nome = p["nome"] if len(p["nome"]) <= 26 else (g.get("nome_no_google") or p["nome"])[:26]
    cidade = "Guarda"
    pecas = []

    # 1 — apresentação: a casa e onde fica
    destino1 = os.path.join(pasta, "publicacao-1.png")
    peca_imagem(fotos[0], nome, "%s · %s" % (rotulo(p.get("categoria")), cidade), "Bora", destino1)
    legenda1 = ("%s, na Guarda.\n\n"
                "Estamos aqui. Guarda esta publicação para não te esqueceres de nós.\n\n"
                "📍 %s\n%s\n"
                "#Guarda #GuardaPortugal #Beiras"
                % (nome, g.get("morada") or "Guarda",
                   ("📞 " + g["telefone"]) if g.get("telefone") else ""))
    pecas.append({"ficheiro": "publicacao-1.png", "tipo": "apresentação",
                  "legenda": legenda1, "fonte_da_foto": "ficha Google do próprio negócio"})

    # 2 — so o que e verdade sempre. A 1.a versao pos "Estamos abertos" com a linha
    # "domingo: Encerrado" por baixo, porque ia buscar a primeira linha do horario sem
    # olhar. Regra agora: gabar a nota so com 20+ avaliacoes (o nosso proprio diagnostico
    # diz que abaixo de 10 e problema — gabar 9 contradizia a pagina ao lado); senao, diz-se
    # o que nao pode estar errado: quem somos e onde estamos.
    destino2 = os.path.join(pasta, "publicacao-2.png")
    foto2 = fotos[2] if len(fotos) > 2 else (fotos[1] if len(fotos) > 1 else fotos[0])
    if g.get("avaliacao") and (g.get("n_avaliacoes") or 0) >= 20:
        titulo2 = "%s ★ no Google" % g["avaliacao"]
        linha2 = "%d pessoas avaliaram" % g["n_avaliacoes"]
        legenda2 = ("%s estrelas no Google, com %d avaliações de quem já cá veio.\n\n"
                    "Obrigado a quem escreveu. Quem ainda não veio, já sabe onde somos.\n\n"
                    "📍 %s\n#Guarda #Beiras"
                    % (g["avaliacao"], g["n_avaliacoes"], g.get("morada") or "Guarda"))
    else:
        titulo2 = "%s na Guarda" % rotulo(p.get("categoria"))
        linha2 = (g.get("morada") or "Guarda").split(",")[0][:38]
        legenda2 = ("%s. Estamos na %s.\n\n"
                    "Se passas por aqui, entra. Se não passas, agora já sabes onde somos.\n\n"
                    "%s📍 %s\n#Guarda #GuardaPortugal #Beiras"
                    % (nome, (g.get("morada") or "Guarda").split(",")[0],
                       ("📞 " + g["telefone"] + "\n") if g.get("telefone") else "",
                       g.get("morada") or "Guarda"))
    peca_imagem(foto2, titulo2, linha2, "Bora", destino2)
    pecas.append({"ficheiro": "publicacao-2.png",
                  "tipo": "prova" if (g.get("n_avaliacoes") or 0) >= 20 else "onde somos",
                  "legenda": legenda2, "fonte_da_foto": "ficha Google do próprio negócio"})
    return pecas


def pagina(p, g, pecas, n_fotos_pagina):
    falta = g.get("falta") or []
    itens_falta = "".join("<li>%s</li>" % esc(x) for x in falta) or "<li>A ficha está bem — falta é quem a alimente todas as semanas.</li>"
    galeria = "".join('<img src="foto%d.jpg" alt="Foto de %s">' % (i, esc(p["nome"]))
                      for i in range(1, n_fotos_pagina + 1))
    cartoes = "".join(
        '<figure><img src="%s" alt="Publicação %d"><figcaption><pre>%s</pre></figcaption></figure>'
        % (esc(pc["ficheiro"]), i, esc(pc["legenda"])) for i, pc in enumerate(pecas, 1))
    horario = ("<ul>" + "".join("<li>%s</li>" % esc(h) for h in (g.get("horario") or [])[:7]) + "</ul>") if g.get("horario") else "<p>A ficha não tem horário.</p>"
    aval = ("%s ★ · %d avaliações" % (g["avaliacao"], g.get("n_avaliacoes") or 0)) if g.get("avaliacao") else "ainda sem avaliações"

    return """<!doctype html>
<html lang="pt-PT"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>%(nome)s — o que a Bora preparou</title>
<style>
 :root{--verde:#16A34A;--laranja:#F97316;--tinta:#111827;--cinza:#6B7280;--fundo:#F8FAFC}
 *{box-sizing:border-box}
 body{margin:0;font-family:Inter,system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--tinta);background:var(--fundo);line-height:1.6}
 header.capa{position:relative;min-height:320px;display:flex;align-items:flex-end;background:#111}
 header.capa img{position:absolute;inset:0;width:100%%;height:100%%;object-fit:cover;opacity:.62}
 header.capa .txt{position:relative;padding:28px 22px;color:#fff}
 header.capa b{text-transform:uppercase;letter-spacing:.06em;font-size:.82rem;opacity:.85}
 header.capa h1{margin:.15em 0 0;font-size:2rem;line-height:1.15}
 main{max-width:780px;margin:0 auto;padding:22px 18px 64px}
 section{background:#fff;border:1px solid #E5E7EB;border-radius:14px;padding:20px 22px;margin:18px 0}
 h2{font-size:1.22rem;margin:.1em 0 .5em}
 h3{font-size:.86rem;color:var(--cinza);text-transform:uppercase;letter-spacing:.06em;margin:1.3em 0 .3em}
 ul{margin:.3em 0 .3em 1.1em;padding:0} li{margin:.3em 0}
 .galeria{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px;margin-top:10px}
 .galeria img{width:100%%;aspect-ratio:1;object-fit:cover;border-radius:10px}
 .mini{border:1px solid #E5E7EB;border-radius:12px;overflow:hidden}
 .mini .topo{position:relative;height:190px;background:#111}
 .mini .topo img{width:100%%;height:100%%;object-fit:cover;opacity:.8}
 .mini .topo .nome{position:absolute;left:16px;bottom:12px;color:#fff;font-size:1.3rem;font-weight:800;text-shadow:0 2px 8px rgba(0,0,0,.6)}
 .mini .corpo{padding:14px 16px}
 .botoes{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
 .botoes span{border:1px solid var(--verde);color:var(--verde);border-radius:999px;padding:7px 13px;font-weight:600;font-size:.9rem}
 figure{margin:0 0 20px}
 figure img{width:100%%;max-width:420px;border-radius:12px;display:block}
 figcaption pre{white-space:pre-wrap;font-family:inherit;background:var(--fundo);border-radius:10px;padding:12px;margin:8px 0 0;font-size:.94rem}
 .preco{font-size:1.5rem;font-weight:800;color:var(--verde);margin:.2em 0}
 .rodape{color:var(--cinza);font-size:.86rem;text-align:center;margin-top:24px}
</style></head><body>
<header class="capa">
  <img src="foto1.jpg" alt="Foto de %(nome)s">
  <div class="txt"><b>Bora · Presença Digital</b><h1>%(nome)s</h1></div>
</header>
<main>

<section>
  <h2>Porque é que isto vos chegou</h2>
  <p>Somos a <b>Bora</b>, a aplicação de entregas e serviços da Guarda. Todos os dias fazemos
  para nós o que está aqui feito para vocês. <b>Não pedimos nada</b> — fizemos primeiro, com as
  <b>vossas fotos</b>, as que já estão na vossa ficha do Google.</p>
  <div class="galeria">%(galeria)s</div>
</section>

<section>
  <h2>O que o Google mostra hoje</h2>
  <ul>
    <li><b>Morada:</b> %(morada)s</li>
    <li><b>Telefone:</b> %(tel)s</li>
    <li><b>Avaliações:</b> %(aval)s</li>
    <li><b>Fotografias na ficha:</b> %(n_fotos)s</li>
  </ul>
  <h3>Horário que o Google mostra</h3>
  %(horario)s
  <h3>O que falta</h3>
  <ul>%(falta)s</ul>
</section>

<section>
  <h2>O mini-site que vos fazíamos</h2>
  <div class="mini">
    <div class="topo"><img src="foto1.jpg" alt=""><div class="nome">%(nome)s</div></div>
    <div class="corpo">
      <div>%(categoria)s · %(morada)s</div>
      <div class="botoes"><span>Ligar%(tel_bt)s</span><span>Como chegar</span><span>Horário</span><span>Fotos</span></div>
      <p style="color:#6B7280;font-size:.92rem;margin-top:12px">Uma página só, que abre depressa
      no telemóvel, com o vosso nome, as vossas fotos e o botão de ligar — e é esta que passa a
      estar no Google quando alguém vos procura.</p>
    </div>
  </div>
</section>

<section>
  <h2>Duas publicações já feitas</h2>
  <p>Não são ideias: são as imagens, prontas a sair. Com as vossas fotos.</p>
  %(cartoes)s
</section>

<section>
  <h2>Quanto custa</h2>
  <p class="preco">%(preco)d € por mês</p>
  <p><b>Sem fidelização.</b> Inclui as publicações, o mini-site, a ficha do Google tratada e o
  atendimento por WhatsApp. Se não quiserem, fiquem com o que está aqui: é vosso à mesma.</p>
</section>

<p class="rodape">Bora · Guarda · página só vossa, fora do Google (noindex).<br>
As fotografias são as da vossa ficha pública do Google.</p>
</main></body></html>
""" % {
        "nome": esc(p["nome"]), "galeria": galeria,
        "morada": esc(g.get("morada") or "Guarda"),
        "tel": esc(g.get("telefone") or "não tem"),
        "tel_bt": (" " + esc(g["telefone"])) if g.get("telefone") else "",
        "aval": esc(aval), "n_fotos": g.get("n_fotos", 0),
        "horario": horario, "falta": itens_falta,
        "categoria": esc(rotulo(p.get("categoria"))),
        "cartoes": cartoes, "preco": PRECO,
    }


def proposta(p, g, link):
    falta = g.get("falta") or []
    inicio = (falta[0][0].lower() + falta[0][1:]) if falta else "a ficha está bem, mas não tem quem a alimente todas as semanas"
    return ("Boa tarde,\n\n"
            "Somos a Bora, a aplicação de entregas e serviços da Guarda.\n\n"
            "Reparámos numa coisa na vossa ficha do Google: %s\n\n"
            "Em vez de pedirmos uma reunião, fizemos primeiro — com as vossas próprias fotos. "
            "Está tudo nesta página, só vossa:\n%s\n\n"
            "Lá dentro estão o mini-site, duas publicações já feitas (imagens, não ideias) e o "
            "que falta na ficha, ponto por ponto.\n\n"
            "Se gostarem, tratamos disto por %d € por mês, sem fidelização. Se não gostarem, "
            "fiquem com o que lá está — é vosso à mesma.\n\nBora\nGuarda" % (inicio, link, PRECO))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quantos", type=int, default=10)
    a = ap.parse_args()

    linhas = json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))
    fichas = json.load(io.open(os.path.join(BASE, "fichas_boas.json"), encoding="utf-8"))
    bons = [l for l in linhas if l["fonte_id"] in fichas
            and (fichas[l["fonte_id"]].get("n_fotos") or 0) >= 1
            and fichas[l["fonte_id"]].get("telefone")]
    bons.sort(key=lambda x: -x["pontuacao"])
    escolhidos = [b for b in bons if b["nome"] in APROVADOS]
    for b in bons:
        if len(escolhidos) >= a.quantos:
            break
        if b not in escolhidos:
            escolhidos.append(b)
    log("AMOSTRAS v2: %d negocios (%d vinham aprovados da revisao)"
        % (len(escolhidos), sum(1 for e in escolhidos if e["nome"] in APROVADOS)))

    ids = {l["fonte_id"]: l["id"] for l in (pedir("/rest/v1/rpc/prospects_ler", {"p_chave": E["PROSPECTS_KEY"]}) or [])}
    feitas = []
    for p in escolhidos:
        g = fichas[p["fonte_id"]]
        tok = token_de(p["fonte_id"])
        pasta = os.path.join(SITE, "avenca", tok)
        os.makedirs(pasta, exist_ok=True)
        fotos = baixar_fotos(g, tok, quantas=3)
        if not fotos:
            log("  %-26s SEM FOTOS — nao faco amostra" % p["nome"][:26])
            continue
        for i, f in enumerate(fotos, 1):
            quadrado(f, 900).save(os.path.join(pasta, "foto%d.jpg" % i), "JPEG", quality=86)
        pecas = pecas_do_negocio(p, g, fotos, pasta, tok)
        io.open(os.path.join(pasta, "index.html"), "w", encoding="utf-8", newline="\n").write(
            pagina(p, g, pecas, len(fotos)))
        link = "https://boraguarda.com/avenca/%s/" % tok
        pid = ids.get(p["fonte_id"])
        if pid:
            pedir("/rest/v1/rpc/prospect_amostra_registar", {
                "p_chave": E["PROSPECTS_KEY"], "p_prospect": pid,
                "p_linha": {"link_unico": link, "mini_site": "avenca/%s/index.html" % tok,
                            "publicacoes": pecas, "diagnostico_google": g}})
            pedir("/rest/v1/rpc/prospect_proposta_registar", {
                "p_chave": E["PROSPECTS_KEY"], "p_prospect": pid,
                "p_linha": {"canal": "whatsapp" if g.get("telefone") else "presencial",
                            "assunto": "Fizemos isto para %s — vejam" % p["nome"],
                            "texto": proposta(p, g, link), "preco_mes_eur": PRECO}})
        feitas.append({"nome": p["nome"], "token": tok, "link": link, "pasta": pasta,
                       "fotos": len(fotos), "prospect_id": pid})
        log("  ok %-26s %d fotos  %s" % (p["nome"][:26], len(fotos), link))

    io.open(os.path.join(BASE, "amostras_feitas.json"), "w", encoding="utf-8").write(
        json.dumps(feitas, ensure_ascii=False, indent=1))
    log("FIM amostras v2: %d feitas, com fotos reais e publicacoes em imagem" % len(feitas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
