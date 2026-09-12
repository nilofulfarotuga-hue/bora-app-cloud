# -*- coding: utf-8 -*-
"""Ladrilho da Lavagem Auto, a partir da ilustracao gerada pelo Danilo.

A imagem original veio com o XADREZ da transparencia pintado dentro do JPG na
metade de cima. Aqui deteta-se a fronteira do xadrez, recorta-se so a parte
boa (o carro com espuma, sobre azul cheio) e reconstroi-se o fundo azul ate as
bordas, no formato dos outros ladrilhos.
"""
from PIL import Image, ImageFilter
import os

SRC = r'C:/Users/danil/Downloads/Gemini_Generated_Image_xqhq27xqhq27xqhq.jpg'
DST = 'assets/categories/cat_lavagem_auto.png'
LADO = 512

im = Image.open(SRC).convert('RGB')
w, h = im.size

# 1. Onde acaba o xadrez.
#    Medido no perfil de cores distintas por linha da imagem original:
#      y=0 a 192  -> 85 a 95 cores  (xadrez: dois azuis a alternar)
#      y=224 em diante -> 114 e a subir (ja e o carro, que tem muita cor)
#      y=800 em diante -> 20 a 35 (fundo azul liso)
#    A automatica nao serve aqui: o carro tem MAIS cores que o xadrez, por
#    isso qualquer limiar simples corta no sitio errado. A fronteira e a
#    subida das ~95 para as ~114, entre as linhas 192 e 224.
LIMITE_XADREZ = 210
limite = LIMITE_XADREZ
print('xadrez cortado ate a linha y =', limite, 'de', h)

# 2. Cor do fundo bom: mediana de uma faixa limpa, em baixo.
amostra = [im.getpixel((x, h - 60)) for x in range(0, w, 6)]
amostra.sort(key=lambda p: p[0] + p[1] + p[2])
FUNDO = amostra[len(amostra)//2]
print('azul do fundo:', '#%02X%02X%02X' % FUNDO)

# 3. Apaga o xadrez pintando-o com o azul do fundo, em vez de o recortar —
#    assim nao se perde o carro nem as bolhas de cima.
#    Medido na propria imagem: o xadrez alterna #1546AF (praticamente o fundo)
#    com #366BD1 (visivelmente mais claro). So o claro precisa de ser tapado.
CLARO = (0x36, 0x6B, 0xD1)
px = im.load()
trocados = 0
for y in range(h):
    for x in range(w):
        r, g, bl = px[x, y]
        if abs(r-CLARO[0]) < 26 and abs(g-CLARO[1]) < 26 and abs(bl-CLARO[2]) < 26:
            px[x, y] = FUNDO
            trocados += 1
print('pixeis de xadrez tapados:', trocados)

boa = im
bw, bh = boa.size
lado = max(bw, bh)
tela = Image.new('RGB', (lado, lado), FUNDO)
tela.paste(boa, ((lado - bw) // 2, (lado - bh) // 2))

# 4. Suaviza a emenda entre o recorte e o fundo novo.
tela = tela.filter(ImageFilter.SMOOTH)
tela = tela.resize((LADO, LADO), Image.LANCZOS)

# Mesmo tratamento dos irmaos: paleta, sem dither (a ilustracao e lisa).
q = tela.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE)
q.save(DST, 'PNG', optimize=True)
print('gravado', DST, q.size, '%.0f KB' % (os.path.getsize(DST)/1024))
