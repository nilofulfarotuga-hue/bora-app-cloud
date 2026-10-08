"""Gera uma imagem de TESTE com um "SMS de receita" inventado (08/10/2026).

Serve para provar que, no ecrã do estafeta, a foto da receita abre em ecrã
inteiro e os números se leem depois de ampliar. Os números são falsos e a
imagem diz em letra grande que é de teste. Pequena de propósito (texto miúdo),
como uma captura de SMS num telemóvel.

Uso: python gerar_receita_teste.py <saida.png>
"""
import sys

from PIL import Image, ImageDraw, ImageFont

saida = sys.argv[1] if len(sys.argv) > 1 else 'receita_teste.png'
W, H = 720, 1280
img = Image.new('RGB', (W, H), (245, 245, 245))
d = ImageDraw.Draw(img)
f_titulo = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 30)
f = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 22)
f_num = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 24)
f_aviso = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 26)

d.rectangle([0, 0, W, 110], fill=(30, 30, 30))
d.text((30, 38), 'SNS  |  Mensagens', font=f_titulo, fill=(255, 255, 255))

y = 150
bolha = [24, y, W - 24, y + 560]
d.rounded_rectangle(bolha, radius=28, fill=(229, 229, 234))
linhas = [
    ('Receita Eletrónica SNS', f_aviso),
    ('Utente: TESTE BORA', f),
    ('', f),
    ('N.º da receita:', f),
    ('1012 3456 7890 1234 567', f_num),
    ('', f),
    ('Código de acesso e dispensa:', f),
    ('482915', f_num),
    ('', f),
    ('Código de direito de opção:', f),
    ('7731', f_num),
    ('', f),
    ('Castilium 10 mg  x1 embalagem', f),
]
yy = y + 30
for txt, fonte in linhas:
    d.text((56, yy), txt, font=fonte, fill=(20, 20, 20))
    yy += 40

d.rectangle([24, 780, W - 24, 860], fill=(255, 235, 59))
d.text((48, 802), 'IMAGEM DE TESTE — RECEITA INVENTADA', font=f_aviso, fill=(0, 0, 0))
d.text((48, 900), 'Não é uma receita verdadeira. Prova da app Bora, 08/10/2026.', font=f, fill=(90, 90, 90))
img.save(saida, optimize=True)
print(saida, img.size)
