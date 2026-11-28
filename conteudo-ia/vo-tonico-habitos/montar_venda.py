# -*- coding: utf-8 -*-
"""Material de venda do caderno "30 dias de habitos simples" do Vo Tonico (15/11/2026, ordem do Danilo das 16:57
passada pela Claude.ai; precos autorizados pelo Danilo as 16:59; quadro de habitos em letra grande pedido no adendo
da Claude.ai das 17:05). Mesmas cores e letras do PDF (verde #2F6B3E, mostarda #D9A441, creme #F7F5EC,
Georgia + Segoe UI). Modelo: gospel/produto/venda/montar_venda.py. Nada do Em Dia neste produto.

Faz, nesta pasta:
  _livro-com-quadro.html/.pdf     o caderno de 14/11 + 4 paginas do quadro de habitos antes do "Ate breve"
  capa-1200x1700.png              capa vertical (proporcao da pagina do PDF) com a cara do Vo Tonico
  capa-quadrada-1080.png          imagem quadrada do produto
  mockup-1-tablet-celular.png, mockup-2-paginas-abertas.png, mockup-3-quadro-de-habitos.png
  workbook-30-dias-habitos-simples-vo-tonico-com-capa.pdf   o PDF a vender
Uso: python montar_venda.py [livro|imagens|final|revisao]   (sem argumento: tudo, um passo de cada vez)
As paginas novas estao em _quadro-habitos-paginas.html: sao conteudo do produto pago e nao vao para o GitHub."""
import os
import sys
import tempfile

sys.path.insert(0, r"C:\BoraLocal\ConteudoIA\_trabalho")
import venda_base as vb  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
PRODUTO = os.path.dirname(AQUI)
BASE = "workbook-30-dias-habitos-simples-vo-tonico"
HTML_ORIG = os.path.join(PRODUTO, BASE + ".html")
VIDEO = r"C:\BoraLocal\ConteudoIA\videos\vo-tonico\vo-tonico-03.mp4"
T_FOTO = 2.33  # pausa da fala: sorriso de boca fechada, olhos abertos para a camara, nitido
PERFIL = os.path.join(tempfile.gettempdir(), "edge-perfil-produtos")

LIVRO = os.path.join(AQUI, "_livro-com-quadro")
FINAL = os.path.join(AQUI, BASE + "-com-capa.pdf")

H = vb.hexrgb
C = dict(
    cor=H("#2F6B3E"), cor2=H("#D9A441"), cor2_txt=H("#A8771F"), fundo=H("#F7F5EC"), fundo2=H("#E8E2CB"),
    tinta=H("#2b2622"), tinta2=H("#4a423c"), cinza=H("#8a7f76"), mock1=H("#F3F0E2"), mock2=H("#DDD6BC"),
    capa_h=1700,
    kicker="CADERNO  ·  30 DIAS  ·  QUADRO DE HÁBITOS",
    titulo=[("30 dias de", 118), ("hábitos simples", 132)],
    subtitulo="um caderno com o Vô Tonico",
    arco=(840, 945, 7), recorte_capa=(80, 0, 640),
    linha_capa="um hábito por dia  ·  quadro para marcar",
    kicker_q="CADERNO · 30 DIAS", titulo_q=[("30 dias de", 74), ("hábitos", 92), ("simples", 92)],
    com_q="com o Vô Tonico", recorte_quadrada=(210, 40, 520),
    itens_q=["Um hábito simples por dia", "O passo de hoje, sem pressa", "Quadro de hábitos",
             "Letra grande para imprimir", "PDF para ler no celular"],
    legenda1=["Leia no celular, no tablet ou imprima"],
    legenda2=["Um hábito simples por dia,", "com o passo de hoje"],
    legenda3=["+ quadro de hábitos em letra grande"],
)
AUTOR = "Vô Tonico (personagem criado com IA) – Edições Bora"
LINHA_AUTOR = "Autor: Vô Tonico (personagem criado com IA) – Edições Bora\n© 2026 Bora"


def partes(fragmento):
    s = open(os.path.join(AQUI, fragmento), encoding="utf-8").read()
    i, j = s.index("<style>") + 7, s.index("</style>")
    return s[i:j], s[j + 8:].strip()


def livro():
    base = open(HTML_ORIG, encoding="utf-8").read()
    css, novas = partes("_quadro-habitos-paginas.html")
    open(LIVRO + ".html", "w", encoding="utf-8").write(vb.inserir_antes_da_ultima(base, novas, css))
    r = vb.paginas_cortadas(LIVRO + ".html", PERFIL)
    print(os.path.basename(LIVRO), "paginas:", r["total"], "cortadas:", r["cortadas"])
    assert not r["cortadas"], "ha paginas com conteudo cortado"
    vb.imprimir(LIVRO + ".html", LIVRO + ".pdf", PERFIL)
    print("  PDF", LIVRO + ".pdf", os.path.getsize(LIVRO + ".pdf") // 1024, "KB")


def foto():
    return vb.fotograma(VIDEO, T_FOTO, os.path.join(AQUI, f"_vo-tonico-03-{T_FOTO:.2f}s.png"))


def imagens():
    ft = foto()
    c = vb.capa(C, ft)
    c.save(os.path.join(AQUI, "capa-1200x1700.png"))
    vb.quadrada(C, ft).save(os.path.join(AQUI, "capa-quadrada-1080.png"))
    pdf = LIVRO + ".pdf"
    vb.mockup1(C, c, pdf, 4).save(os.path.join(AQUI, "mockup-1-tablet-celular.png"))
    vb.mockup2(C, pdf, 4, 11).save(os.path.join(AQUI, "mockup-2-paginas-abertas.png"))
    vb.mockup3(C, pdf, [(35, -9, 190, "Escolha os hábitos"), (36, 0, 400, "Marque com um X"),
                        (37, 9, 610, "Letra grande")]).save(os.path.join(AQUI, "mockup-3-quadro-de-habitos.png"))
    for n in sorted(os.listdir(AQUI)):
        if n.endswith(".png") and not n.startswith("_"):
            print(n, os.path.getsize(os.path.join(AQUI, n)) // 1024, "KB")


def final():
    import pymupdf
    from PIL import Image
    c = Image.open(os.path.join(AQUI, "capa-1200x1700.png")).convert("RGB")
    d = pymupdf.open(LIVRO + ".pdf")
    ate = [i + 1 for i, p in enumerate(d) if "AT\u00c9 BREVE" in p.get_text().upper() and "E agora?" in p.get_text()]
    d.close()
    assert len(ate) == 1, f"pagina do autor: {ate}"
    n, rect = vb.pdf_final(LIVRO + ".pdf", c, FINAL, "30 dias de hábitos simples", AUTOR, LINHA_AUTOR, ate[0],
                           C["cinza"], AQUI)
    print(os.path.basename(FINAL), n, "paginas,", os.path.getsize(FINAL) // 1024, "KB; autor na pagina", ate[0], rect)
    d = pymupdf.open(FINAL)
    assert all("Em Dia" not in p.get_text() for p in d), "este produto nao leva nada do Em Dia"
    d.close()


def revisao():
    pdf = LIVRO + ".pdf"
    novas = [vb.pagina(pdf, n, zoom=1.6) for n in (35, 36, 37, 38)]
    vb.folha(novas, os.path.join(AQUI, "revisao-paginas-novas.jpg"), alt=640, cols=4,
             legenda="Paginas novas: quadro de habitos em letra grande (35 a 38)")


if __name__ == "__main__":
    passos = sys.argv[1:] or ["livro", "imagens", "final", "revisao"]
    for passo in passos:
        globals()[passo]()
