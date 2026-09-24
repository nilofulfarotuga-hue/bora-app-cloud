#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Amostras e rascunhos de proposta da avença «Presença Digital Bora» (24/09/2026).

Para cada um dos melhores candidatos faz TRÊS coisas, todas guardadas, nenhuma enviada:

  1. uma página privada com link único (`/avenca/<token>/`) onde o dono vê, numa só folha:
     o que o Google mostra hoje sobre ele, o mini-site que a Bora lhe faria, e duas
     publicações prontas a sair;
  2. o registo dessa amostra em `prospect_amostras`;
  3. o RASCUNHO da proposta em `prospect_propostas` — estado 'rascunho', sempre. Quem envia
     é o Danilo, nunca este script.

Tudo o que aparece na página é público e do próprio negócio (nome, morada, telefone,
horário, avaliação), vindo da ficha Google. Não há fotos de terceiros nem texto inventado
sobre eles: o que se diz que falta é o que a API respondeu que falta.
"""
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
SITE = r"C:\BoraLocal\projetosflutter\bora-site"
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
PRECO = 149
E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if "=" in _l and not _l.startswith("#"):
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(os.path.join(BASE, "prospeccao.log"), "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def pedir(caminho, corpo):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + caminho,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"],
                 "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        t = r.read().decode("utf-8")
    return json.loads(t) if t.strip() else None


def token_de(fonte_id):
    return hashlib.sha256((fonte_id + "|avenca-bora-2026").encode()).hexdigest()[:14]


def esc(s):
    return (str(s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def publicacoes(p, g):
    """Duas peças prontas, escritas com o que é verdade sobre o negócio."""
    nome = p["nome"]
    cat = p.get("categoria")
    aval = g.get("avaliacao")
    n_aval = g.get("n_avaliacoes") or 0
    peca1 = {
        "tipo": "publicação de apresentação",
        "visual": "Foto do espaço ou do prato do dia, em grande plano, luz natural, sem texto por cima.",
        "legenda": (
            "%s, na Guarda.\n\n"
            "Estamos abertos e é mais fácil chegar cá do que parece. Guarda esta publicação "
            "para não te esqueceres de nós.\n\n"
            "📍 %s\n"
            "%s"
            "#Guarda #GuardaPortugal #Beiras" % (
                nome,
                p.get("morada") or "Guarda",
                ("📞 %s\n\n" % g["telefone"]) if g.get("telefone") else "\n",
            )
        ),
    }
    if aval and n_aval >= 5:
        gancho = ("Somos %s estrelas no Google, com %d avaliações de quem já cá veio." % (aval, n_aval))
    else:
        gancho = "Quem cá vem volta. Ainda não nos conheces?"
    peca2 = {
        "tipo": "publicação de prova social",
        "visual": "Três fotos em carrossel: a entrada, o balcão e o que fazem melhor.",
        "legenda": (
            "%s\n\n"
            "%s — na Guarda, para quem trabalha aqui e para quem está de passagem.\n\n"
            "Marca nos comentários quem tens de trazer cá.\n\n"
            "#Guarda #%s #Beiras" % (gancho, nome, (cat or "local").capitalize())
        ),
    }
    return [peca1, peca2]


def pagina(p, g, pecas):
    falta = g.get("falta") or []
    linhas_falta = "".join("<li>%s</li>" % esc(x) for x in falta) or "<li>Nada de grave — a ficha está bem.</li>"
    tel = g.get("telefone") or p.get("telefone")
    horario = "sim" if g.get("tem_horario") else "não"
    aval = ("%s ★ com %d avaliações" % (g["avaliacao"], g.get("n_avaliacoes") or 0)) if g.get("avaliacao") else "ainda sem avaliações"
    cartoes = ""
    for i, pc in enumerate(pecas, 1):
        cartoes += """
      <article class="peca">
        <h4>Publicação %d — %s</h4>
        <p class="visual"><b>Imagem:</b> %s</p>
        <pre>%s</pre>
      </article>""" % (i, esc(pc["tipo"]), esc(pc["visual"]), esc(pc["legenda"]))

    return """<!doctype html>
<html lang="pt-PT">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>%(nome)s — o que a Bora preparou</title>
<style>
 :root{--verde:#16A34A;--laranja:#F97316;--tinta:#111827;--cinza:#6B7280;--fundo:#F9FAFB}
 *{box-sizing:border-box}
 body{margin:0;font-family:Inter,system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--tinta);background:var(--fundo);line-height:1.6}
 .faixa{background:var(--verde);color:#fff;padding:28px 20px}
 .faixa b{font-size:1.05rem;letter-spacing:.04em;text-transform:uppercase;opacity:.9}
 .faixa h1{margin:.2em 0 0;font-size:1.9rem}
 main{max-width:760px;margin:0 auto;padding:24px 20px 64px}
 section{background:#fff;border:1px solid #E5E7EB;border-radius:14px;padding:20px 22px;margin:18px 0}
 h2{font-size:1.25rem;margin:.2em 0 .6em}
 h3{font-size:1rem;color:var(--cinza);text-transform:uppercase;letter-spacing:.05em;margin:1.4em 0 .4em}
 ul{margin:.4em 0 .4em 1.1em;padding:0}
 li{margin:.35em 0}
 .mini{border:1px dashed #CBD5E1;border-radius:12px;padding:18px;background:#fff}
 .mini .capa{background:linear-gradient(135deg,var(--verde),#0F7A37);color:#fff;border-radius:10px;padding:26px 20px;text-align:center}
 .mini .capa h3{color:#fff;opacity:.9;margin:0 0 .2em}
 .mini .capa .n{font-size:1.6rem;font-weight:800}
 .mini .botoes{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
 .mini .botoes span{border:1px solid var(--verde);color:var(--verde);border-radius:999px;padding:8px 14px;font-weight:600;font-size:.92rem}
 .peca{border-left:4px solid var(--laranja);padding-left:14px;margin:16px 0}
 .peca h4{margin:.2em 0}
 .peca .visual{color:var(--cinza);font-size:.92rem;margin:.2em 0 .5em}
 pre{white-space:pre-wrap;background:var(--fundo);border-radius:10px;padding:14px;font-family:inherit;font-size:.96rem;margin:0}
 .preco{font-size:1.5rem;font-weight:800;color:var(--verde)}
 .rodape{color:var(--cinza);font-size:.88rem;text-align:center;margin-top:26px}
</style>
</head>
<body>
<div class="faixa">
  <b>Bora · Presença Digital</b>
  <h1>%(nome)s</h1>
</div>
<main>

<section>
  <h2>Porque é que isto vos chegou</h2>
  <p>Somos a <b>Bora</b>, a aplicação de entregas e serviços da Guarda. Fazemos todos os dias
  para nós aquilo que a seguir está feito para vocês: publicações, mini-site e ficha no Google.
  <b>Não pedimos nada.</b> Fizemos primeiro, para verem com os vossos olhos.</p>
</section>

<section>
  <h2>O que o Google mostra hoje sobre %(nome)s</h2>
  <p>Isto não é opinião nossa: é o que está na vossa ficha, agora, à vista de toda a gente.</p>
  <ul>
    <li><b>Morada:</b> %(morada)s</li>
    <li><b>Telefone na ficha:</b> %(tel)s</li>
    <li><b>Horário na ficha:</b> %(horario)s</li>
    <li><b>Fotografias:</b> %(fotos)s</li>
    <li><b>Avaliações:</b> %(aval)s</li>
  </ul>
  <h3>O que falta</h3>
  <ul>%(falta)s</ul>
</section>

<section>
  <h2>O mini-site que vos fazíamos</h2>
  <div class="mini">
    <div class="capa">
      <h3>%(categoria)s · Guarda</h3>
      <div class="n">%(nome)s</div>
      <div>%(morada)s</div>
    </div>
    <div class="botoes">
      <span>Ligar%(tel_botao)s</span><span>Como chegar</span><span>Horário</span><span>Ver fotos</span>
    </div>
    <p style="color:#6B7280;margin-top:14px;font-size:.92rem">Uma página só, que abre depressa no
    telemóvel, com o vosso nome, as vossas fotos e o botão de ligar. É esta a página que passa
    a estar no Google quando alguém vos procura.</p>
  </div>
</section>

<section>
  <h2>Duas publicações já escritas</h2>
  <p>Prontas a sair no Instagram e no Facebook. Se aceitarem, saem 3 a 4 por semana, sempre assim.</p>
  %(pecas)s
</section>

<section>
  <h2>Quanto custa</h2>
  <p class="preco">%(preco)d € por mês</p>
  <p><b>Sem fidelização.</b> Cancelam quando quiserem, com um mês de aviso. Inclui as publicações,
  o mini-site, a ficha do Google tratada e o atendimento por WhatsApp.</p>
  <p>Se não quiserem, fiquem com o que está aqui: é vosso à mesma.</p>
</section>

<p class="rodape">Bora · Guarda · esta página é só vossa e não está no Google (noindex).</p>
</main>
</body>
</html>
""" % {
        "nome": esc(p["nome"]),
        "categoria": esc((p.get("categoria") or "negócio").capitalize()),
        "morada": esc(g.get("morada") or p.get("morada") or "Guarda"),
        "tel": esc(tel or "não tem"),
        "tel_botao": (" " + esc(tel)) if tel else "",
        "horario": horario,
        "fotos": g.get("n_fotos", 0),
        "aval": esc(aval),
        "falta": linhas_falta,
        "pecas": cartoes,
        "preco": PRECO,
    }


def proposta(p, g):
    falta = g.get("falta") or []
    primeiro = falta[0] if falta else "a vossa ficha está bem, mas não tem quem a alimente todas as semanas"
    primeiro = primeiro[0].lower() + primeiro[1:] if primeiro else primeiro
    return (
        "Boa tarde,\n\n"
        "Somos a Bora, a aplicação de entregas e serviços da Guarda.\n\n"
        "Reparámos numa coisa na vossa ficha do Google: %s\n\n"
        "Em vez de vos pedirmos uma reunião, fizemos primeiro. Está tudo nesta página, só vossa:\n"
        "%s\n\n"
        "Lá dentro estão o mini-site que vos fazíamos, duas publicações já escritas e o que falta "
        "na ficha do Google, ponto por ponto.\n\n"
        "Se gostarem, tratamos disto por %d € por mês, sem fidelização. Se não gostarem, fiquem "
        "com o que lá está — é vosso à mesma.\n\n"
        "Bora\n"
        "Guarda"
    ) % (primeiro, "%(link)s", PRECO)


def main():
    quantos = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    linhas = json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))
    diag = json.load(io.open(os.path.join(BASE, "diagnosticos.json"), encoding="utf-8"))
    top = sorted([l for l in linhas if l["fonte_id"] in diag], key=lambda x: -x["pontuacao"])[:quantos]
    log("AMOSTRAS: %d negocios" % len(top))

    # ids no Supabase, para ligar amostra e proposta ao prospect certo
    ids = {}
    for linha in pedir("/rest/v1/rpc/prospects_ler", {"p_chave": E["PROSPECTS_KEY"]}) or []:
        ids[linha["fonte_id"]] = linha["id"]

    feitos = []
    for p in top:
        g = diag[p["fonte_id"]]
        tok = token_de(p["fonte_id"])
        pasta = os.path.join(SITE, "avenca", tok)
        os.makedirs(pasta, exist_ok=True)
        pecas = publicacoes(p, g)
        io.open(os.path.join(pasta, "index.html"), "w", encoding="utf-8", newline="\n").write(pagina(p, g, pecas))
        link = "https://boraguarda.com/avenca/%s/" % tok
        pid = ids.get(p["fonte_id"])
        if not pid:
            log("  %s: sem id no Supabase, saltei" % p["nome"][:30])
            continue
        pedir("/rest/v1/rpc/prospect_amostra_registar", {
            "p_chave": E["PROSPECTS_KEY"], "p_prospect": pid,
            "p_linha": {"link_unico": link, "mini_site": "avenca/%s/index.html" % tok,
                        "publicacoes": pecas, "diagnostico_google": g}})
        pedir("/rest/v1/rpc/prospect_proposta_registar", {
            "p_chave": E["PROSPECTS_KEY"], "p_prospect": pid,
            "p_linha": {"canal": "whatsapp" if (g.get("telefone") or p.get("telefone")) else "presencial",
                        "assunto": "Fizemos isto para %s — vejam" % p["nome"],
                        "texto": proposta(p, g) % {"link": link},
                        "preco_mes_eur": PRECO}})
        feitos.append((p["nome"], link))
        log("  ok %-28s %s" % (p["nome"][:28], link))

    log("FIM amostras: %d paginas + %d rascunhos de proposta (nada enviado)" % (len(feitos), len(feitos)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
