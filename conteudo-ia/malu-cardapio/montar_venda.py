# -*- coding: utf-8 -*-
"""Material de venda do planner "Lista e cardapio da semana" da Malu (produto n.o 4, adendo da Claude.ai das 17:05
de 15/11/2026; mesmo preco dos outros, autorizado pelo Danilo as 16:59). Mesmas cores e letras do PDF (terracota
#B5543A, amarelo #E3A93B, creme #FDF8F2, Georgia + Segoe UI). Modelo: gospel/produto/venda/montar_venda.py.
O PDF base sai de _trabalho/pdf-malu-cardapio/montar_pdf_malu.py (conteudo pago: nao vai para o GitHub).

Faz, nesta pasta:
  capa-1200x1700.png              capa vertical (proporcao da pagina do PDF) com a cara da Malu
  capa-quadrada-1080.png          imagem quadrada do produto
  mockup-1-tablet-celular.png, mockup-2-paginas-abertas.png, mockup-3-o-que-tem-dentro.png
  lista-e-cardapio-da-semana-malu-com-capa.pdf   o PDF a vender
Uso: python montar_venda.py [imagens|final|revisao]   (sem argumento: tudo, um passo de cada vez)"""
import os
import sys

sys.path.insert(0, r"C:\BoraLocal\ConteudoIA\_trabalho")
import venda_base as vb  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
PRODUTO = os.path.dirname(AQUI)
BASE = "lista-e-cardapio-da-semana-malu"
PDF = os.path.join(PRODUTO, BASE + ".pdf")
VIDEO = r"C:\BoraLocal\ConteudoIA\videos\malu\malu-r002.mp4"
T_FOTO = 2.12  # pausa da fala: sorriso de boca fechada, a olhar para a camara, nitido
FINAL = os.path.join(AQUI, BASE + "-com-capa.pdf")

H = vb.hexrgb
C = dict(
    cor=H("#B5543A"), cor2=H("#E3A93B"), cor2_txt=H("#A8741A"), fundo=H("#FDF8F2"), fundo2=H("#F3E4D1"),
    tinta=H("#2b2622"), tinta2=H("#4a423c"), cinza=H("#8a7f76"), mock1=H("#FAF1E6"), mock2=H("#EBD9C2"),
    capa_h=1700,
    kicker="PLANNER  ·  PARA IMPRIMIR",
    titulo=[("Lista e cardápio", 122), ("da semana", 140)],
    subtitulo="refeições da semana e lista de compras, com a Malu",
    arco=(840, 945, 7), recorte_capa=(120, 90, 600),
    linha_capa="cardápio  ·  lista por seção  ·  preços  ·  dicas",
    kicker_q="PLANNER · PARA IMPRIMIR", titulo_q=[("Lista e", 80), ("cardápio", 92), ("da semana", 80)],
    com_q="com a Malu", recorte_quadrada=(235, 100, 470),
    itens_q=["Cardápio dos 7 dias", "Lista por seção do mercado", "Preços para comparar", "O que já tenho em casa",
             "Dicas para o dinheiro render"],
    legenda1=["Imprima toda semana ou use no celular"],
    legenda2=["Cardápio da semana e lista", "por seção do mercado"],
    legenda3=["14 páginas para usar toda semana"],
)
AUTOR = "Malu (personagem criada com IA) – Edições Bora"
LINHA_AUTOR = "Autora: Malu (personagem criada com IA) – Edições Bora\n© 2026 Bora"


def foto():
    return vb.fotograma(VIDEO, T_FOTO, os.path.join(AQUI, f"_malu-r002-{T_FOTO:.2f}s.png"))


def imagens():
    ft = foto()
    c = vb.capa(C, ft)
    c.save(os.path.join(AQUI, "capa-1200x1700.png"))
    vb.quadrada(C, ft).save(os.path.join(AQUI, "capa-quadrada-1080.png"))
    vb.mockup1(C, c, PDF, 5).save(os.path.join(AQUI, "mockup-1-tablet-celular.png"))
    vb.mockup2(C, PDF, 5, 6).save(os.path.join(AQUI, "mockup-2-paginas-abertas.png"))
    vb.mockup3(C, PDF, [(4, -9, 190, "O que já tenho"), (9, 0, 400, "Preços"),
                        (13, 9, 610, "Dicas da Malu")]).save(os.path.join(AQUI, "mockup-3-o-que-tem-dentro.png"))
    for n in sorted(os.listdir(AQUI)):
        if n.endswith(".png") and not n.startswith("_"):
            print(n, os.path.getsize(os.path.join(AQUI, n)) // 1024, "KB")


def final():
    import pymupdf
    from PIL import Image
    c = Image.open(os.path.join(AQUI, "capa-1200x1700.png")).convert("RGB")
    d = pymupdf.open(PDF)
    n_pag = d.page_count
    d.close()
    n, rect = vb.pdf_final(PDF, c, FINAL, "Lista e cardápio da semana", AUTOR, LINHA_AUTOR, n_pag, C["cinza"], AQUI)
    print(os.path.basename(FINAL), n, "paginas,", os.path.getsize(FINAL) // 1024, "KB; autora na pagina", n_pag, rect)
    d = pymupdf.open(FINAL)
    assert all("Em Dia" not in p.get_text() for p in d), "este produto nao leva nada do Em Dia"
    d.close()


def revisao():
    pags = [vb.pagina(PDF, n, zoom=1.2) for n in range(2, 15)]
    vb.folha(pags, os.path.join(AQUI, "revisao-paginas.jpg"), alt=560, cols=5,
             legenda="Paginas 2 a 14 do planner da Malu (a 1 e a capa)")


if __name__ == "__main__":
    passos = sys.argv[1:] or ["imagens", "final", "revisao"]
    for passo in passos:
        globals()[passo]()
