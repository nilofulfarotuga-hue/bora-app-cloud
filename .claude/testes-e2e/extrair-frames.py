# -*- coding: utf-8 -*-
"""
Extrai frames de um vídeo do cinegrafista à volta do momento da falha.

Fluxo falhado no passo N → o runner sabe o timestamp do passo (log) e o
inicio_epoch do vídeo (sidecar .json) → segundo do vídeo = ts_passo - inicio_epoch.
Extrai [t-3s, t+3s] a 1 fps para frames/<nome-do-video>/ (Claude analisa os frames;
o MP4 completo fica como prova para o Danilo).

Uso:
    python extrair-frames.py --video gravacoes/2026-07-10/SERIAL/login-123456.mp4 --segundo 42
    python extrair-frames.py --video ... --ts-epoch 1783640000.5   (usa o sidecar para converter)
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
FRAMES = BASE / "frames"


def extrair(video: Path, segundo: float, janela: float = 3.0, fps: int = 1) -> Path:
    if not video.exists():
        raise FileNotFoundError(video)
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg não encontrado no PATH")
    inicio = max(0.0, segundo - janela)
    dur = janela * 2
    destino = FRAMES / video.stem
    destino.mkdir(parents=True, exist_ok=True)
    cmd = [ffmpeg, "-y", "-ss", f"{inicio:.2f}", "-i", str(video), "-t", f"{dur:.2f}",
           "-vf", f"fps={fps}", str(destino / "frame-%02d.png")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg falhou: {r.stderr[-400:]}")
    return destino


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--segundo", type=float, help="segundo do vídeo onde falhou")
    g.add_argument("--ts-epoch", type=float, help="timestamp epoch do passo falhado (converte via sidecar)")
    ap.add_argument("--janela", type=float, default=3.0)
    args = ap.parse_args()

    video = Path(args.video)
    if not video.is_absolute():
        video = BASE / video
    segundo = args.segundo
    if segundo is None:
        sidecar = video.with_suffix(".json")
        if not sidecar.exists():
            print(f"sidecar não existe: {sidecar}", file=sys.stderr); sys.exit(2)
        inicio_epoch = json.loads(sidecar.read_text(encoding="utf-8"))["inicio_epoch"]
        segundo = args.ts_epoch - inicio_epoch
        if segundo < 0:
            print(f"timestamp anterior ao início do vídeo ({segundo:.1f}s)", file=sys.stderr); sys.exit(2)
    destino = extrair(video, segundo, args.janela)
    print(destino)


if __name__ == "__main__":
    main()
