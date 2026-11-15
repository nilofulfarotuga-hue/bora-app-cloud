# -*- coding: utf-8 -*-
"""Material de venda do caderno "O dinheiro da casa em ordem" da Vo Celeste (15/11/2026, ordem do Danilo das 16:57
passada pela Claude.ai; precos autorizados pelo Danilo as 16:59; planner pedido no adendo da Claude.ai das 17:05;
versao Portugal com a pagina da app Em Dia no adendo das 17:12 e no acerto das 17:06). Mesmas cores e letras do PDF
(azul #1F3A5F, vermelho #B23A3A, creme #FAF8F3, Georgia + Segoe UI). Modelo: gospel/produto/venda/montar_venda.py.

Faz, nesta pasta:
  _livro-com-planner.html/.pdf            o caderno de 14/11 + 5 paginas de planner antes do "Ate breve"
  _livro-com-planner-portugal.html/.pdf   o mesmo + a pagina da app Em Dia no fim (PT-PT, QR com ?de=celeste)
  capa-1200x1700.png                      capa vertical (proporcao da pagina do PDF) com a cara da Vo Celeste
  capa-quadrada-1080.png                  imagem quadrada do produto
  mockup-1-tablet-celular.png, mockup-2-paginas-abertas.png, mockup-3-planner.png
  caderno-...-vo-celeste-com-capa.pdf            a vender no Brasil (R$)
  caderno-...-vo-celeste-com-capa-portugal.pdf   a vender em Portugal (EUR)
Uso: python montar_venda.py [livro|imagens|final|revisao]   (sem argumento: tudo, um passo de cada vez)
As paginas novas (planner e Em Dia) estao em _planner-paginas.html e _pagina-em-dia-portugal.html: sao conteudo do
produto pago e nao vao para o GitHub."""
import os
import sys
import tempfile

sys.path.insert(0, r"C:\BoraLocal\ConteudoIA\_trabalho")
import venda_base as vb  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
PRODUTO = os.path.dirname(AQUI)
BASE = "caderno-30-dias-dinheiro-da-casa-em-ordem-vo-celeste"
HTML_ORIG = os.path.join(PRODUTO, BASE + ".html")
VIDEO = r"C:\BoraLocal\ConteudoIA\videos\vo-celeste\vo-celeste-r002.mp4"
T_FOTO = 14.95  # fim do video: sorriso de boca fechada, a olhar para a camara, o fotograma mais nitido dos vistos
URL_EM_DIA = "https://emdia.boraguarda.com/baixar?de=celeste"
PERFIL = os.path.join(tempfile.gettempdir(), "edge-perfil-produtos")

LIVRO_BR = os.path.join(AQUI, "_livro-com-planner")
LIVRO_PT = os.path.join(AQUI, "_livro-com-planner-portugal")
FINAL_BR = os.path.join(AQUI, BASE + "-com-capa.pdf")
FINAL_PT = os.path.join(AQUI, BASE + "-com-capa-portugal.pdf")

H = vb.hexrgb
C = dict(
    cor=H("#1F3A5F"), cor2=H("#B23A3A"), cor2_txt=H("#B23A3A"), fundo=H("#FAF8F3"), fundo2=H("#E9E3D7"),
    tinta=H("#2b2622"), tinta2=H("#4a423c"), cinza=H("#8a7f76"), mock1=H("#F3EFE7"), mock2=H("#DDD5C6"),
    capa_h=1700,  # 1200 x 594,96/420
    kicker="CADERNO  ·  30 DIAS  ·  PLANNER",
    titulo=[("O dinheiro da", 118), ("casa em ordem", 132)],
    subtitulo="um caderno de 30 dias com a Vó Celeste",
    arco=(840, 945, 7), recorte_capa=(120, 150, 600),
    linha_capa="lição  ·  exercício  ·  planner do orçamento",
    kicker_q="CADERNO · 30 DIAS", titulo_q=[("O dinheiro", 74), ("da casa", 74), ("em ordem", 92)],
    com_q="com a Vó Celeste", recorte_quadrada=(250, 150, 470),
    itens_q=["Uma lição por dia, 30 dias", "Exercícios no próprio caderno", "Planner do orçamento",
             "Contas fixas e metas", "PDF para ler e imprimir"],
    legenda1=["Leia no celular, no tablet ou imprima"],
    legenda2=["Uma lição por dia, com exercício", "e quadro para preencher"],
    legenda3=["+ planner do orçamento para imprimir"],
)
AUTOR = "Vó Celeste (personagem criada com IA) – Edições Bora"
LINHA_AUTOR = "Autor: Vó Celeste (personagem criada com IA) – Edições Bora\n© 2026 Bora"


def partes(fragmento):
    s = open(os.path.join(AQUI, fragmento), encoding="utf-8").read()
    i, j = s.index("<style>") + 7, s.index("</style>")
    return s[i:j], s[j + 8:].strip()


def livro():
    import qrcode
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=12, border=4)
    q.add_data(URL_EM_DIA)
    q.make(fit=True)
    q.make_image(fill_color="black", back_color="white").save(os.path.join(AQUI, "_qr-em-dia-celeste.png"))
    base = open(HTML_ORIG, encoding="utf-8").read()
    css, novas = partes("_planner-paginas.html")
    br = vb.inserir_antes_da_ultima(base, novas, css)
    open(LIVRO_BR + ".html", "w", encoding="utf-8").write(br)
    css_e, emdia = partes("_pagina-em-dia-portugal.html")
    pt = br.replace("</style>", css_e + "\n</style>", 1).replace("</body>", emdia + "</body>")
    open(LIVRO_PT + ".html", "w", encoding="utf-8").write(pt)
    for h in (LIVRO_BR, LIVRO_PT):
        r = vb.paginas_cortadas(h + ".html", PERFIL)
        print(os.path.basename(h), "paginas:", r["total"], "cortadas:", r["cortadas"])
        assert not r["cortadas"], "ha paginas com conteudo cortado"
        vb.imprimir(h + ".html", h + ".pdf", PERFIL)
        print("  PDF", h + ".pdf", os.path.getsize(h + ".pdf") // 1024, "KB")


def foto():
    return vb.fotograma(VIDEO, T_FOTO, os.path.join(AQUI, f"_vo-celeste-r002-{T_FOTO:.2f}s.png"))


def imagens():
    ft = foto()
    c = vb.capa(C, ft)
    c.save(os.path.join(AQUI, "capa-1200x1700.png"))
    vb.quadrada(C, ft).save(os.path.join(AQUI, "capa-quadrada-1080.png"))
    pdf = LIVRO_BR + ".pdf"
    vb.mockup1(C, c, pdf, 4).save(os.path.join(AQUI, "mockup-1-tablet-celular.png"))
    vb.mockup2(C, pdf, 11, 18).save(os.path.join(AQUI, "mockup-2-paginas-abertas.png"))
    vb.mockup3(C, pdf, [(36, -9, 190, "Entradas e saídas"), (38, 0, 400, "Contas fixas"),
                        (39, 9, 610, "Metas")]).save(os.path.join(AQUI, "mockup-3-planner.png"))
    for n in sorted(os.listdir(AQUI)):
        if n.endswith(".png") and not n.startswith("_"):
            print(n, os.path.getsize(os.path.join(AQUI, n)) // 1024, "KB")


def final():
    import pymupdf
    from PIL import Image
    c = Image.open(os.path.join(AQUI, "capa-1200x1700.png")).convert("RGB")
    for base, dst in ((LIVRO_BR + ".pdf", FINAL_BR), (LIVRO_PT + ".pdf", FINAL_PT)):
        d = pymupdf.open(base)
        ate = [i + 1 for i, p in enumerate(d) if "AT\u00c9 BREVE" in p.get_text().upper() and "E agora?" in p.get_text()]
        d.close()
        assert len(ate) == 1, f"pagina do autor: {ate}"
        n, rect = vb.pdf_final(base, c, dst, "O dinheiro da casa em ordem", AUTOR, LINHA_AUTOR, ate[0], C["cinza"], AQUI)
        print(os.path.basename(dst), n, "paginas,", os.path.getsize(dst) // 1024, "KB; autor na pagina", ate[0], rect)
    # versao Portugal: a ultima pagina e a da Em Dia; o QR e o link levam ?de=celeste
    import cv2
    import numpy as np
    d = pymupdf.open(FINAL_PT)
    p = d[d.page_count - 1]
    assert "Organiza isto no telemóvel" in p.get_text(), "a ultima pagina da versao Portugal nao e a da Em Dia"
    links = [l.get("uri") for l in p.get_links()]
    pix = p.get_pixmap(matrix=pymupdf.Matrix(4, 4), alpha=False)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 3)[:, :, ::-1].copy()
    lido, _, _ = cv2.QRCodeDetector().detectAndDecode(arr)
    print("QR lido de volta do PDF:", lido, "| links na pagina:", links)
    assert lido == URL_EM_DIA and URL_EM_DIA in links
    d.close()
    d = pymupdf.open(FINAL_BR)
    assert all("Em Dia" not in p.get_text() for p in d), "a versao Brasil nao pode ter nada do Em Dia"
    d.close()


def revisao():
    pdf = LIVRO_PT + ".pdf"
    novas = [vb.pagina(pdf, n, zoom=1.6) for n in (35, 36, 37, 38, 39, 41)]
    vb.folha(novas, os.path.join(AQUI, "revisao-paginas-novas.jpg"), alt=640, cols=3,
             legenda="Paginas novas: planner (35 a 39) e Em Dia (41, so na versao Portugal)")


if __name__ == "__main__":
    passos = sys.argv[1:] or ["livro", "imagens", "final", "revisao"]
    for passo in passos:
        globals()[passo]()
