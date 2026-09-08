"""Corta o vídeo de 60–120 s para as notas ao revisor da Apple.

ENTRADA: o `demo.mp4` do artefacto do CI (gravação do simulador, 1320x2868).
SAÍDA:   `bora-ios-review-demo.mp4`, com legendas em inglês queimadas.

PORQUÊ ASSIM: o revisor da Apple lê inglês, e o vídeo serve de prova de uso —
não de anúncio. Sem música, sem cortes rápidos, uma frase curta por ecrã, a
dizer o que se está a ver.

COMO ENCONTRA OS SEGMENTOS: não se cravam tempos. O arnês segura cada ecrã ~10 s
(ver `integration_test/capturas_loja_test.dart`), por isso procura-se o verde
da marca (#16A34A) no topo do ecrã, amostrando 2x por segundo, e agrupam-se os
blocos contíguos. Se a gravação mudar, isto continua a funcionar.

USO:  python ios/tools/montar_video_revisor.py <caminho do demo.mp4> [saida.mp4]
"""
import os
import subprocess
import sys
import tempfile

FFMPEG = os.environ.get('FFMPEG', 'ffmpeg')
VERDE = (0x16, 0xA3, 0x4A)          # #16A34A
TOLERANCIA = 45
AMOSTRAS_POR_SEGUNDO = 2

# Uma frase por ecrã, na ordem em que o arnês os desenha.
LEGENDAS = [
    'Groceries from local shops in Guarda',
    'Restaurant food, delivered',
    'Barbershop and salon bookings',
    'Acai and desserts',
    'Home cleaning services',
    'Errands: we buy it for you',
    'Car wash at your door',
]


def blocos_com_app(video: str):
    """Devolve [(inicio_s, fim_s)] onde o cabeçalho verde da Bora está no ecrã."""
    tmp = tempfile.mkdtemp()
    cru = os.path.join(tmp, 'f.raw')
    subprocess.run(
        [FFMPEG, '-v', 'error', '-i', video,
         '-vf', f'fps={AMOSTRAS_POR_SEGUNDO},scale=8:16',
         '-f', 'rawvideo', '-pix_fmt', 'rgb24', cru],
        check=True)
    dados = open(cru, 'rb').read()
    tam = 8 * 16 * 3
    positivos = []
    for i in range(len(dados) // tam):
        q = dados[i * tam:(i + 1) * tam]
        topo = [tuple(q[(y * 8 + x) * 3:(y * 8 + x) * 3 + 3])
                for y in range(1, 4) for x in range(8)]
        verdes = sum(1 for p in topo
                     if all(abs(p[k] - VERDE[k]) <= TOLERANCIA for k in range(3)))
        if verdes >= 8:
            positivos.append(i / AMOSTRAS_POR_SEGUNDO)
    if not positivos:
        return []
    blocos, ini, ant = [], positivos[0], positivos[0]
    for s in positivos[1:]:
        if s - ant > 2.0:            # intervalo > 2 s = ecrã diferente
            blocos.append((ini, ant))
            ini = s
        ant = s
    blocos.append((ini, ant))
    # só blocos com substância (o arnês segura ~10 s)
    return [(a, b) for a, b in blocos if b - a >= 3.0]


def escapar(texto: str) -> str:
    return texto.replace("'", r"\'").replace(':', r'\:')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    entrada = sys.argv[1]
    saida = sys.argv[2] if len(sys.argv) > 2 else 'bora-ios-review-demo.mp4'

    blocos = blocos_com_app(entrada)
    print(f'blocos com a app: {len(blocos)}')
    for i, (a, b) in enumerate(blocos):
        print(f'  {i + 1}. {a:.1f}s -> {b:.1f}s  ({b - a:.1f}s)')
    if not blocos:
        sys.exit('ERRO: a app nao aparece na gravacao — nada para cortar. '
                 'Confirmar que o arnes segura cada ecra (SEGUNDOS_POR_ECRA).')

    tmp = tempfile.mkdtemp()
    pedacos = []
    for i, (a, b) in enumerate(blocos):
        legenda = LEGENDAS[i] if i < len(LEGENDAS) else ''
        fora = os.path.join(tmp, f'p{i:02d}.mp4')
        # Altura 1280 para o ficheiro não ficar gigante; a proporção mantém-se.
        vf = ('scale=-2:1280,'
              "drawbox=y=ih-190:w=iw:h=190:color=black@0.62:t=fill," +
              (f"drawtext=text='{escapar(legenda)}':fontcolor=white:fontsize=44:"
               "x=(w-text_w)/2:y=h-125" if legenda else 'null'))
        subprocess.run(
            [FFMPEG, '-v', 'error', '-y', '-ss', f'{a:.2f}', '-to', f'{b:.2f}',
             '-i', entrada, '-vf', vf, '-an',
             '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '24', fora],
            check=True)
        pedacos.append(fora)

    lista = os.path.join(tmp, 'lista.txt')
    with open(lista, 'w', encoding='utf-8') as f:
        for p in pedacos:
            f.write(f"file '{p}'\n")
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-f', 'concat', '-safe', '0',
                    '-i', lista, '-c', 'copy', saida], check=True)

    dur = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'default=nw=1:nk=1', saida],
        capture_output=True, text=True).stdout.strip()
    tamanho = os.path.getsize(saida) / 1024 / 1024
    print(f'\nfeito: {saida}  {tamanho:.1f} MB  {dur}s')
    if dur:
        d = float(dur)
        if d < 60 or d > 120:
            print(f'AVISO: {d:.0f}s esta fora do alvo 60-120 s — '
                  'ajustar SEGUNDOS_POR_ECRA no teste do arnes.')


if __name__ == '__main__':
    main()
