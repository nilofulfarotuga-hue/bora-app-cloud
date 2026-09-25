"""Processa imagens cruas → WebP em 3 tamanhos, sem alterar os originais.

- logo + capa + cada foto de prato.
- rembg (remoção de fundo) aplicado a logo e fotos de prato (não à capa/hero).
- Saída em <dir>/_preview/images/: <base>_thumb.webp (200), _card.webp (600), _hero.webp (1200).

Nunca toca nos ficheiros originais (lê, escreve cópias processadas).

Uso:
    python process_images.py --dir ".claude/.ai/onboard/belmonte-grill"
"""
from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

from _shared import log, write_pipeline_json, read_pipeline_json

SIZES = {"thumb": 200, "card": 600, "hero": 1200}


def _load_pil():
    from PIL import Image  # import tardio (dependência pesada)
    return Image


def _maybe_rembg(data: bytes) -> bytes:
    try:
        from rembg import remove
        return remove(data)
    except Exception as e:  # noqa: BLE001
        log(f"rembg indisponível/erro ({e}); a usar imagem original.", "WARN")
        return data


def process_one(src: Path, out_dir: Path, do_rembg: bool) -> dict:
    Image = _load_pil()
    raw = src.read_bytes()
    if do_rembg:
        raw = _maybe_rembg(raw)
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    out = {}
    for label, size in SIZES.items():
        copy = img.copy()
        copy.thumbnail((size, size), Image.LANCZOS)
        dest = out_dir / f"{src.stem}_{label}.webp"
        copy.save(dest, "WEBP", quality=82, method=6)
        out[label] = str(dest)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    args = ap.parse_args()
    onboard_dir = Path(args.dir)
    out_dir = onboard_dir / "_preview" / "images"
    out_dir.mkdir(parents=True, exist_ok=True)

    state = read_pipeline_json(onboard_dir)
    images: dict = {}

    for asset, do_rembg in (("logo", True), ("capa", False)):
        for ext in (".png", ".jpg", ".jpeg"):
            p = onboard_dir / f"{asset}{ext}"
            if p.exists():
                images[asset] = process_one(p, out_dir, do_rembg)
                log(f"{asset} processado ({'rembg' if do_rembg else 'sem rembg'}).")
                break

    fotos_dir = onboard_dir / "fotos"
    images["produtos"] = {}
    if fotos_dir.exists():
        for foto in sorted(fotos_dir.iterdir()):
            if foto.suffix.lower() in (".png", ".jpg", ".jpeg"):
                images["produtos"][foto.name] = process_one(foto, out_dir, do_rembg=True)
        log(f"{len(images['produtos'])} foto(s) de prato processada(s).")

    state["images"] = images
    write_pipeline_json(onboard_dir, state)
    log(f"Imagens em {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
