# -*- coding: utf-8 -*-
"""Devocional da Irma Lucia em ESPANHOL: "21 días para volver a empezar" (15/11/2026).
Ordem do Danilo das 16:57 e precos autorizados as 16:59, passada pela Claude.ai as 17:00 (e2e_log 9374);
titulo e capa adaptados a lingua por ordem da Claude.ai das 17:05.

MESMO METODO do PDF portugues (C:\\BoraLocal\\ConteudoIA\\_trabalho\\build_pdf.py, importado aqui):
le o conteudo no formato REGRAS-PDF.md, monta o HTML A5 com o MESMO CSS, imprime em PDF pelo Edge headless e tira
um PNG por pagina (PyMuPDF) + folhas de contacto para o juiz. So mudam os rotulos fixos (lingua) e o lang do HTML.
A mais: (1) mede cada pagina no Edge (--dump-dom) para provar que nenhum texto fica cortado e quantas linhas de
anotacoes sobram; (2) le o texto do PDF de volta e confirma que cada campo do conteudo esta la.
Uso: python build_pdf_es.py
"""
import html
import io
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, r"C:\BoraLocal\ConteudoIA\_trabalho")
import build_pdf as B  # noqa: E402  ler(), CSS, linhas(), pagina(), EDGE: os mesmos do PDF portugues
import pymupdf  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(AQUI, "conteudo-es.md")
OUT = os.path.join(AQUI, "21-dias-para-volver-a-empezar")
TEMA = B.TEMAS["gospel"]  # bordo #7A2E3A, dourado #C9A46A, fundo #FBF7F1
L = dict(
    lang="es",
    personagem="Hermana Lucía",
    ia="La Hermana Lucía es un personaje creado con inteligencia artificial.",
    antes="Antes de empezar",
    ola="Hola, qué alegría que estés aquí",
    como="Cómo usarlo",
    pouco="Un poco cada día",
    importante="Importante",
    dia="Día",
    de="de",
    parafrase="paráfrasis",
    oracao="Oración.",
    passo="El paso de hoy",
    anot="Notas",
    caminho="Tu camino",
    marque="Marca cada día que completes",
    mudou="Lo que cambió en mí",
    breve="Hasta pronto",
    agora="¿Y ahora?",
    uso="Material de uso personal.",
)


def tipo(s):
    """Apostrofo tipografico (o espanhol nao tem; fica igual ao ingles)."""
    return (s or "").replace("'", "\u2019")


def e(s):
    return html.escape(tipo(s), quote=False)


def montar(doc):
    t, total = L, TEMA["total"]
    P = [B.pagina(f'''
      <div class="capa-faixa"></div>
      <div class="capa">
        <div class="selo">{e(t["personagem"])}</div>
        <h1>{e(doc["titulo"])}</h1>
        <p class="sub">{e(doc["subtitulo"])}</p>
        <div class="capa-orn"><span></span><span></span><span></span></div>
        <p class="capa-ia">{e(t["ia"])}</p>
      </div>''', "capa-pg")]
    intro = "".join(f"<p>{e(x)}</p>" for x in doc["sec"].get("INTRO", []))
    como = "".join(f"<p>{e(x)}</p>" for x in doc["sec"].get("COMO USAR", []))
    aviso = "".join(f"<p>{e(x)}</p>" for x in doc["sec"].get("AVISO", []))
    P.append(B.pagina(f'<p class="kicker">{e(t["antes"])}</p><h2>{e(t["ola"])}</h2>{intro}', "texto"))
    P.append(B.pagina(f'<p class="kicker">{e(t["como"])}</p><h2>{e(t["pouco"])}</h2>{como}'
                      f'<div class="aviso"><b>{e(t["importante"])}</b>{aviso}</div>', "texto"))
    for d in sorted(doc["dias"], key=lambda x: x["n"]):
        cab = (f'<div class="dia-cab"><span class="dia-n">{e(t["dia"])} {d["n"]}</span>'
               f'<span class="dia-de">{e(t["de"])} {total}</span></div><h3>{e(d["titulo"])}</h3>')
        corpo = (f'<div class="verso">“{e(d.get("VERSO"))}”<span>{e(d.get("REF"))} · {e(t["parafrase"])}</span></div>'
                 f'<p>{e(d.get("TEXTO"))}</p><p class="oracao"><b>{e(t["oracao"])}</b> {e(d.get("ORACAO"))}</p>'
                 f'<div class="passo"><b>{e(t["passo"])}</b>{e(d.get("PASSO"))}</div>'
                 f'<p class="lbl">{e(t["anot"])}</p>{B.linhas()}')
        P.append(B.pagina(cab + corpo, "dia"))
    caixas = "".join(f'<div class="cx"><span>{i}</span></div>' for i in range(1, total + 1))
    P.append(B.pagina(f'<p class="kicker">{e(t["caminho"])}</p><h2>{e(t["marque"])}</h2>'
                      f'<div class="grelha g{total}">{caixas}</div><p class="lbl">{e(t["mudou"])}</p>{B.linhas()}', "texto"))
    fecho = "".join(f"<p>{e(x)}</p>" for x in doc["sec"].get("FECHO", []))
    P.append(B.pagina(f'<p class="kicker">{e(t["breve"])}</p><h2>{e(t["agora"])}</h2>{fecho}'
                      f'<p class="assina">— {e(t["personagem"])}</p>'
                      f'<p class="fim-ia">{e(t["ia"])} {e(t["uso"])}</p>', "texto"))
    css = B.CSS.replace("$COR2", TEMA["cor2"]).replace("$COR", TEMA["cor"]).replace("$FUNDO", TEMA["fundo"])
    return (f'<!doctype html><html lang="{t["lang"]}"><head><meta charset="utf-8"><title>{e(doc["titulo"])}</title>'
            f'<style>{css}</style></head><body>{"".join(P)}</body></html>')


MEDIR = """<script>(function(){var mm=96/25.4,ps=document.querySelectorAll('.page'),r=[];
for(var i=0;i<ps.length;i++){var p=ps[i],l=p.querySelector('.linhas');
r.push([i+1,p.scrollHeight-p.clientHeight,l?Math.round(l.getBoundingClientRect().height/mm*10)/10:null]);}
var x=document.createElement('pre');x.id='medidas';x.textContent=JSON.stringify(r);document.body.appendChild(x);})();</script>"""


def medir(h):
    """Abre uma copia do HTML no Edge headless e devolve [pagina, px a mais (corte), mm da zona de anotacoes]."""
    chk = OUT + "-_medir.html"
    io.open(chk, "w", encoding="utf-8").write(h.replace("</body>", MEDIR + "</body>"))
    url = "file:///" + os.path.abspath(chk).replace("\\", "/")
    r = subprocess.run([B.EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--disable-extensions",
                        "--dump-dom", url], capture_output=True, text=True, encoding="utf-8", timeout=180)
    os.remove(chk)
    m = re.search(r'<pre id="medidas">(.*?)</pre>', r.stdout, re.S)
    if not m:
        print("ERRO: medicao falhou", r.returncode, r.stderr[-300:])
        sys.exit(2)
    return json.loads(m.group(1))


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def main():
    doc = B.ler(SRC)
    ns = [d["n"] for d in doc["dias"]]
    print("dias:", len(ns), "faltam:", sorted(set(range(1, TEMA["total"] + 1)) - set(ns)))
    for d in doc["dias"]:
        for k in ("VERSO", "REF", "TEXTO", "ORACAO", "PASSO"):
            if not d.get(k):
                print("ERRO: dia", d["n"], "sem", k)
                sys.exit(2)
        nv = len(d["VERSO"].split())
        if nv > 25 or len(d["PASSO"].split()) > 20 or len(d["titulo"].split()) > 6:
            print("AVISO limites dia", d["n"], "verso", nv, "passo", len(d["PASSO"].split()), "titulo", d["titulo"])
    h = montar(doc)
    io.open(OUT + ".html", "w", encoding="utf-8").write(h)

    med = medir(h)
    cortes = [m for m in med if m[1] > 1]
    dias = [m for m in med if 4 <= m[0] <= 24]
    print("paginas no HTML:", len(med), "| paginas cortadas:", cortes or "nenhuma")
    print("anotacoes nos dias (mm): min", min(m[2] for m in dias), "max", max(m[2] for m in dias),
          "| dias com menos de 3 linhas:", [m[0] - 3 for m in dias if m[2] < 24] or "nenhum")

    pdf = os.path.abspath(OUT + ".pdf")
    if os.path.exists(pdf):
        os.remove(pdf)
    url = "file:///" + os.path.abspath(OUT + ".html").replace("\\", "/")
    r = subprocess.run([B.EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--no-first-run",
                        "--disable-extensions", f"--print-to-pdf={pdf}", url], capture_output=True, text=True, timeout=180)
    if not os.path.exists(pdf):
        print("ERRO: PDF nao criado", r.returncode, r.stderr[-400:])
        sys.exit(2)
    d = pymupdf.open(pdf)
    pngdir = OUT + "-paginas"
    os.makedirs(pngdir, exist_ok=True)
    for i, pg in enumerate(d):
        pg.get_pixmap(dpi=60).save(os.path.join(pngdir, f"p{i+1:02d}.png"))
    print("PDF:", pdf, "paginas:", d.page_count, "tamanho:", round(pg.rect.width / 72 * 25.4), "x",
          round(pg.rect.height / 72 * 25.4), "mm", "|", os.path.getsize(pdf) // 1024, "KB")
    from PIL import Image
    pngs = sorted(f for f in os.listdir(pngdir) if f.startswith("p"))
    for k in range(0, len(pngs), 12):
        ims = [Image.open(os.path.join(pngdir, f)) for f in pngs[k:k + 12]]
        w, hh = ims[0].size
        sheet = Image.new("RGB", (w * 4 + 50, hh * 3 + 40), "#777777")
        for i, im in enumerate(ims):
            sheet.paste(im, (10 + (i % 4) * (w + 10), 10 + (i // 4) * (hh + 10)))
        sheet.save(os.path.join(pngdir, f"folha-{k // 12 + 1}.png"))
    print("folhas de contacto:", (len(pngs) + 11) // 12)

    # o texto do PDF lido de volta: cada campo do conteudo tem de estar la, letra a letra
    texto = re.sub(r"(\w)- (\w)", r"\1-\2", norm(" ".join(pg.get_text() for pg in d)))  # "tick-" + fim de linha
    campos = [doc["titulo"], doc["subtitulo"]] + [x for k in ("INTRO", "COMO USAR", "AVISO", "FECHO") for x in doc["sec"][k]]
    for dd in doc["dias"]:
        campos += [dd["titulo"], dd["VERSO"], dd["REF"], dd["TEXTO"], dd["ORACAO"], dd["PASSO"]]
    falta = [c[:60] for c in campos if norm(tipo(c)) not in texto]
    print("texto lido de volta:", len(texto.split()), "palavras;", len(campos), "campos;",
          "em falta:", falta or "nenhum", "| caracteres estragados (U+FFFD):", texto.count("\ufffd"))
    io.open(os.path.join(pngdir, "texto-lido-do-pdf.txt"), "w", encoding="utf-8").write(
        "\n\n".join(f"--- pagina {i + 1} ---\n" + pg.get_text() for i, pg in enumerate(d)))


if __name__ == "__main__":
    main()
