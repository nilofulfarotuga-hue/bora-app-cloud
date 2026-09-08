"""Corta o video de 60-120 s para as notas ao revisor da Apple.

ENTRADA: o `demo.mp4` do artefacto do CI (gravacao do simulador, 1320x2868)
         e os 7 PNGs de captura que vieram no MESMO artefacto.
SAIDA:   `bora-ios-review-demo.mp4`, com legendas em ingles queimadas.

PORQUE ASSIM: o revisor da Apple le ingles, e o video serve de prova de uso --
nao de anuncio. Sem musica, sem cortes rapidos, uma frase curta por ecra, a
dizer o que se esta a ver.

COMO ENCONTRA OS SEGMENTOS: nao se cravam tempos. Cada um dos 7 PNGs de captura
e reduzido a uma assinatura de 8x16 pixeis, e cada fotograma da gravacao passa
pelo MESMO caminho de reducao e e emparelhado com o PNG mais parecido. Os
fotogramas seguidos com o mesmo vencedor formam um bloco. Se a gravacao mudar
de duracao, de ordem ou de simulador, isto continua a funcionar.

  CICATRIZ (2026-09-08): a primeira versao procurava o verde da marca (#16A34A)
  na faixa do topo. Deu 0 blocos, e concluiu-se "a app so aparece 5 segundos".
  Estava errado: cada um dos 7 ecras tem um cabecalho de cor DIFERENTE (mercado
  verde, comida laranja, barbearia indigo, acai roxo, limpeza azul, favores
  turquesa, lavagem petroleo) e a 8x16 o cabecalho mistura-se com o conteudo.
  Os 7 PNGs conhecidos pontuaram 0/24 contra o proprio detector. Comparar o
  FOTOGRAMA INTEIRO contra os PNGs achou os 7 blocos, ~25 s cada, na ordem.

  CICATRIZ (2026-09-08): `drawtext=fontfile=C:/Windows/...` rebenta o parser de
  filtros (o ':' da unidade separa opcoes) e, sem fontfile, o ffmpeg de Windows
  morre em fontconfig com 0xC0000005. Por isso a fonte e COPIADA para o
  directorio de trabalho e referida por nome relativo, sem ':'.

USO:  python ios/tools/montar_video_revisor.py <pasta com demo.mp4 + PNGs> [saida.mp4]
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile

FFMPEG = os.environ.get('FFMPEG', 'ffmpeg')
FFPROBE = os.environ.get('FFPROBE', 'ffprobe')
LARGURA, ALTURA = 8, 16              # assinatura: 8x16 pixeis RGB
TAM = LARGURA * ALTURA * 3
LIMIAR = 18.0                        # distancia media por canal, 0-255
SEGUNDOS_POR_ECRA = 10.0
RECUO = 7.0                          # so entra depois do ecra assentar
ALTURA_SAIDA = 1280

# Uma frase por ecra, na ordem dos ficheiros 01..07. Curtas de proposito: a
# 590 px de largura, mais de ~28 caracteres a 32 pt sai fora do enquadramento
# (medido: "Groceries from local shops in Guarda" ficou cortado nas duas pontas).
LEGENDAS = {
    '01': 'Groceries from local shops',
    '02': 'Restaurant food, delivered',
    '03': 'Barber and salon bookings',
    '04': 'Acai and desserts',
    '05': 'Home cleaning services',
    '06': 'Errands - we buy for you',
    '07': 'Car wash at your door',
}
TITULO = 'Bora - Guarda, Portugal'
SUBTITULO = 'Demo recorded on iPhone simulator'


def _assinatura(caminho, tmp):
    cru = os.path.join(tmp, 'a.raw')
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-i', caminho,
                    '-vf', 'scale=%d:%d' % (LARGURA, ALTURA),
                    '-f', 'rawvideo', '-pix_fmt', 'rgb24', cru], check=True)
    return list(open(cru, 'rb').read()[:TAM])


def _distancia(a, b):
    return sum(abs(a[k] - b[k]) for k in range(TAM)) / TAM


def blocos_por_ecra(video, pngs, tmp):
    """[(inicio_s, fim_s, prefixo)] por ordem cronologica, um por ecra."""
    refs = [(os.path.basename(p)[:2], _assinatura(p, tmp)) for p in pngs]

    saida = subprocess.run(
        [FFPROBE, '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'frame=pts_time', '-of', 'csv=p=0', video],
        capture_output=True, text=True, check=True).stdout
    tempos = [float(x.strip().rstrip(',')) for x in saida.split()
              if x.strip().rstrip(',')]

    cru = os.path.join(tmp, 'v.raw')
    # passthrough: o simctl grava com taxa variavel (673 fotogramas em 920 s),
    # e so assim cada fotograma casa com o seu pts_time.
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-i', video,
                    '-fps_mode', 'passthrough',
                    '-vf', 'scale=%d:%d' % (LARGURA, ALTURA),
                    '-f', 'rawvideo', '-pix_fmt', 'rgb24', cru], check=True)
    dados = open(cru, 'rb').read()

    corridas = []
    for i in range(min(len(dados) // TAM, len(tempos))):
        q = list(dados[i * TAM:(i + 1) * TAM])
        nome, ref = min(refs, key=lambda r: _distancia(q, r[1]))
        alvo = nome if _distancia(q, ref) <= LIMIAR else None
        if corridas and corridas[-1][0] == alvo:
            corridas[-1][2] = tempos[i]
        else:
            corridas.append([alvo, tempos[i], tempos[i]])

    vistos, blocos = set(), []
    for nome, a, b in corridas:
        # `ecra-final.png` (o ecra inicial do iOS no fim da corrida) tambem e
        # uma referencia: serve para o rejeitar, nao para o filmar.
        if nome in LEGENDAS and nome not in vistos and b - a >= SEGUNDOS_POR_ECRA:
            blocos.append((a, b, nome))
            vistos.add(nome)
    return blocos


def _codificar(ff_args, tmp, ficheiro):
    p = subprocess.run([FFMPEG, '-v', 'error', '-y'] + ff_args +
                       ['-an', '-r', '15', '-c:v', 'libx264',
                        '-pix_fmt', 'yuv420p', '-crf', '26',
                        '-profile:v', 'high', '-level', '4.0', ficheiro],
                       cwd=tmp, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit('ffmpeg falhou (%s):\n%s' % (p.returncode, p.stderr[:800]))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pasta = os.path.abspath(sys.argv[1])
    saida = os.path.abspath(
        sys.argv[2] if len(sys.argv) > 2
        else os.path.join(pasta, 'bora-ios-review-demo.mp4'))
    video = os.path.join(pasta, 'demo.mp4')
    pngs = sorted(glob.glob(os.path.join(pasta, '*.png')))
    if not os.path.exists(video) or len(pngs) < 7:
        sys.exit('ERRO: falta demo.mp4 ou os PNGs de captura em %s' % pasta)

    tmp = tempfile.mkdtemp()
    shutil.copy(os.path.join(os.environ.get('WINDIR', 'C:/Windows'),
                             'Fonts', 'arialbd.ttf'),
                os.path.join(tmp, 'f.ttf'))

    blocos = blocos_por_ecra(video, pngs, tmp)
    print('ecras encontrados: %d/%d' % (len(blocos), len(LEGENDAS)))
    for a, b, nome in blocos:
        print('  %s  %7.1f -> %7.1f (%5.1fs)  %s'
              % (nome, a, b, b - a, LEGENDAS[nome]))
    if len(blocos) < len(LEGENDAS):
        sys.exit('ERRO: nem todos os ecras aparecem na gravacao. Confirmar '
                 'SEGUNDOS_POR_ECRA em integration_test/capturas_loja_test.dart.')

    pedacos = []
    cartao = 'p_titulo.mp4'
    _codificar(['-f', 'lavfi',
                '-i', 'color=c=0x16A34A:s=590x%d:d=4' % ALTURA_SAIDA,
                '-vf', ("drawtext=fontfile=f.ttf:text='%s':fontcolor=white:"
                        'fontsize=44:x=(w-text_w)/2:y=h/2-60,'
                        "drawtext=fontfile=f.ttf:text='%s':fontcolor=white@0.85:"
                        'fontsize=26:x=(w-text_w)/2:y=h/2+10')
                % (TITULO, SUBTITULO)],
               tmp, cartao)
    pedacos.append(cartao)

    for i, (a, _b, nome) in enumerate(blocos):
        ficheiro = 'p%02d.mp4' % i
        vf = ('scale=-2:%d,' % ALTURA_SAIDA +
              'drawbox=y=ih-200:w=iw:h=200:color=black@0.66:t=fill,' +
              "drawtext=fontfile=f.ttf:text='%s':fontcolor=white:"
              'fontsize=32:x=(w-text_w)/2:y=h-125' % LEGENDAS[nome])
        _codificar(['-ss', '%.2f' % (a + RECUO),
                    '-t', '%.2f' % SEGUNDOS_POR_ECRA,
                    '-i', video, '-vf', vf], tmp, ficheiro)
        pedacos.append(ficheiro)

    with open(os.path.join(tmp, 'lista.txt'), 'w', encoding='utf-8') as f:
        f.write(''.join("file '%s'\n" % p for p in pedacos))
    # RECODIFICA, nao copia. Com `-c copy` o cartao de titulo (fonte lavfi, base
    # de tempo 1/25) e os cortes (base de tempo do simulador) misturam bases e o
    # ficheiro sai com tempos nao monotonos: medido a 2026-09-08, o cartao de 4 s
    # durava um unico fotograma na reproducao. Recodificar a 15 fps constantes
    # custa segundos num ficheiro de 0,3 MB e resolve.
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-f', 'concat', '-safe', '0',
                    '-i', 'lista.txt', '-fps_mode', 'cfr', '-r', '15',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '26',
                    '-profile:v', 'high', '-level', '4.0',
                    '-movflags', '+faststart', saida], cwd=tmp, check=True)

    dur = subprocess.run(
        [FFPROBE, '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'default=nw=1:nk=1', saida],
        capture_output=True, text=True).stdout.strip()
    print('\nfeito: %s  %.1f MB  %ss'
          % (saida, os.path.getsize(saida) / 1024 / 1024, dur))
    if dur and not 60 <= float(dur) <= 120:
        print('AVISO: %.0fs esta fora do alvo 60-120 s — '
              'ajustar SEGUNDOS_POR_ECRA aqui.' % float(dur))


if __name__ == '__main__':
    main()
