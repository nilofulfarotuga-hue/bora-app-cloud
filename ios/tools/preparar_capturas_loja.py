"""Prepara as capturas PUBLICAS da App Store a partir do artefacto do CI.

O QUE FAZ
  1. Apanha so os ficheiros `NN-loja-*.png` -- as que sao publicidade publica.
     Os `NN-video-*` (percurso do video do revisor) e os `zz-*` (diagnostico)
     ficam de fora de proposito. A separacao esta explicada em
     `integration_test/demo_real_test.dart`.
  2. Tira o CANAL ALFA e desce para 8 bits por canal.
  3. Confere tamanho e formato, e recusa o que nao servir.

PORQUE O ALFA IMPORTA
  A pagina de especificacoes da Apple diz, textualmente:

    "Note: Images can't include alpha channels or transparencies."
    https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

  E as capturas do `IntegrationTestWidgetsFlutterBinding.takeScreenshot` saem
  RGBA -- medido a 2026-09-08 no artefacto ios-simulador-14, onde
  `00-video-perfis.png` veio em `rgba64be`, ou seja RGBA com 16 bits por canal.
  Enviadas assim, a App Store Connect recusa-as. Isto nao se ve a olho: o PNG
  abre bem em qualquer visualizador.

TAMANHO
  A mesma pagina aceita, para o ecra de 6,9 polegadas (iPhone Air, 17 Pro Max,
  16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max), 1260x2736, 1290x2796
  ou 1320x2868 em retrato. O simulador que o CI escolhe da 1320x2868, que e a
  maior das tres. E a ajuda da App Store Connect diz que basta o maior tamanho
  quando a interface e igual nos varios aparelhos:

    "If your app's user interface is the same across multiple device sizes and
     localizations, provide only the highest resolution screenshots required."
    https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/

  A mesma pagina limita a "a minimum of one and a maximum of ten screenshots".

USO:  python ios/tools/preparar_capturas_loja.py <pasta do artefacto> [saida]
"""
import glob
import os
import shutil
import subprocess
import sys

FFMPEG = os.environ.get('FFMPEG', 'ffmpeg')
FFPROBE = os.environ.get('FFPROBE', 'ffprobe')

# Retrato, para o ecra de 6,9 polegadas. Ver a citacao no cabecalho.
TAMANHOS_ACEITES = {(1260, 2736), (1290, 2796), (1320, 2868)}
MAXIMO_APPLE = 10


def _sonda(caminho):
    saida = subprocess.run(
        [FFPROBE, '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=width,height,pix_fmt',
         '-of', 'csv=p=0', caminho],
        capture_output=True, text=True).stdout.strip()
    largura, altura, formato = saida.split(',')
    with open(caminho, 'rb') as f:
        cabecalho = f.read(26)
    # byte 25 do PNG e o color type: 2 = RGB, 6 = RGBA.
    return int(largura), int(altura), formato, cabecalho[25]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pasta = os.path.abspath(sys.argv[1])
    saida = os.path.abspath(sys.argv[2] if len(sys.argv) > 2
                            else os.path.join(pasta, 'capturas-loja'))

    fontes = sorted(glob.glob(os.path.join(pasta, '*-loja-*.png')))
    if not fontes:
        sys.exit('ERRO: nenhuma captura `NN-loja-*.png` em %s.\n'
                 'Confirmar que a corrida do CI chegou ao fim e que o arnes '
                 'fotografou os ecras publicos.' % pasta)

    if os.path.isdir(saida):
        shutil.rmtree(saida)
    os.makedirs(saida)

    problemas = []
    for origem in fontes:
        nome = os.path.basename(origem)
        largura, altura, _formato, tipo = _sonda(origem)
        if (largura, altura) not in TAMANHOS_ACEITES:
            problemas.append('%s tem %dx%d, que nao e tamanho aceite para 6,9"'
                             % (nome, largura, altura))
            continue
        destino = os.path.join(saida, nome)
        # `-pix_fmt rgb24`: 8 bits por canal e SEM alfa. E o unico ponto que
        # interessa aqui -- nao se redimensiona nem se recomprime a imagem.
        p = subprocess.run(
            [FFMPEG, '-v', 'error', '-y', '-i', origem,
             '-pix_fmt', 'rgb24', destino],
            capture_output=True, text=True)
        if p.returncode != 0:
            problemas.append('%s: ffmpeg falhou -- %s'
                             % (nome, p.stderr[:160]))
            continue
        # ler de volta: nao se da por boa uma conversao sem a conferir
        l2, a2, f2, t2 = _sonda(destino)
        if t2 == 6 or 'a' in f2:
            problemas.append('%s AINDA tem alfa depois de converter (%s)'
                             % (nome, f2))
            continue
        print('  ok  %-26s %dx%d  %s  antes: tipo %d'
              % (nome, l2, a2, f2, tipo))

    feitas = sorted(os.listdir(saida))
    print('\ncapturas prontas: %d  em %s' % (len(feitas), saida))
    if len(feitas) > MAXIMO_APPLE:
        problemas.append('sao %d capturas e a Apple aceita no maximo %d'
                         % (len(feitas), MAXIMO_APPLE))
    if len(feitas) < 1:
        problemas.append('a Apple exige pelo menos uma captura')

    if problemas:
        print('\nPROBLEMAS:')
        for x in problemas:
            print('  -', x)
        sys.exit(1)
    print('Nenhuma leva alfa e todas tem tamanho aceite.')


if __name__ == '__main__':
    main()
