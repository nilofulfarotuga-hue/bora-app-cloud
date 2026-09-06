#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BeUnique Beauty and Academy — construir e instalar as imagens da equipa.

O que faz (ponta-a-ponta, fora do app Flutter):
  1. LOGO + CAPA do salão: baixa do Cloudinary do Noona, re-processa e re-sobe
     ao nosso bucket público via Edge Function `upload-restaurant-asset`
     (deixamos de depender do hotlink do Noona).
  2. FOTOS DAS 9 PROFISSIONAIS:
       - 7 têm foto real no Noona  -> baixa + recorta quadrado 512x512.
       - 2 sem foto (Liliana Elias, Dra. Bianca Melo) -> avatar de iniciais
         elegante (gradiente do design system, iniciais brancas).
     Todas sobem via a mesma Edge Function (kind='staff-<sort_order>').
  3. Escreve `relatorio-beunique-fotos.sql` (raiz do repo) com os UPDATEs prontos
     e um manifest JSON (out/manifest.json) com todos os publicUrl devolvidos.

Segredos: a anon key lê-se de env SB_ANON (é a chave pública do app; nunca
hardcoded aqui). Uso:
  SB_ANON="<anon key>" python tools/beunique/build_photos.py

Requisitos: Python 3 + Pillow (já instalado no PC).
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ─── Config ────────────────────────────────────────────────────────────────
SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
PROVIDER_ID = "192c7d0b-b8ef-4d52-bac3-307895fbbf8e"
ANON = os.environ.get("SB_ANON", "").strip()
UPLOAD_FN = f"{SUPABASE_URL}/functions/v1/upload-restaurant-asset"
CLD = "https://res.cloudinary.com/timatal-ehf/image/upload/"

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)
REPO_ROOT = HERE.parent.parent
SQL_PATH = REPO_ROOT / "relatorio-beunique-fotos.sql"

UA = {"User-Agent": "Mozilla/5.0 (BoraApp tooling)"}

# ─── Logo + capa (URLs full-res confirmados via API Noona) ──────────────────
LOGO_URL = CLD + "v1736619530/profileImages/i1x2s2n4yiap4u1efuig.jpg"
COVER_URL = CLD + "v1726136466/companyCoverImages/llpgozrux2omg7dz1w9z.png"

# ─── Staff: id + nome exato + sort_order + fonte da foto ────────────────────
# `photo` = URL Cloudinary (foto real Noona) OU None -> gera avatar de iniciais.
STAFF = [
    {"id": "1465ee9b-200c-440d-b62d-60ce31af493d", "name": "Camila Pissarra",
     "sort": 1, "photo": CLD + "v1736765750/employeesProfileImages/ti5jftzllpioarkoprb0.jpg"},
    {"id": "88f92a80-a828-4578-b025-c9b4489ae1f4", "name": "Amalia Cavalcante",
     "sort": 2, "photo": CLD + "v1780069398/employeesProfileImages/yajtch7pedquworfrhmh.jpg"},
    {"id": "672b8da7-26da-4ae2-b4fc-ccec5b713d6b", "name": "Bruna Frias",
     "sort": 3, "photo": CLD + "v1729769615/employeesProfileImages/pd3iigoz2zqc5bubr2ql.png"},
    {"id": "975ff095-e0c2-461a-b5c5-14a470415f68", "name": "Priscila Santana",
     "sort": 4, "photo": CLD + "v1782576223/employeesProfileImages/iludvjpzesph9fx8moc4.jpg"},
    {"id": "b69066c9-546a-43ff-ab00-f03fd609401d", "name": "Diana",
     "sort": 5, "photo": CLD + "v1741106407/employeesProfileImages/wino5c3pufiqmonq0vdi.jpg"},
    {"id": "23727a56-2ec0-4889-9c89-61d292f5f595", "name": "Jenniffer",
     "sort": 6, "photo": CLD + "v1741108506/employeesProfileImages/famuu4omiqdqbzjgjtvd.jpg"},
    {"id": "79b35f92-cd96-4f52-b455-82c994476aa0", "name": "Viviane Torres",
     "sort": 7, "photo": CLD + "v1745427925/employeesProfileImages/stqjcr7pbjnsbtnzucfw.jpg"},
    {"id": "1f934392-dcbd-42ca-b3ca-9311dda0471b", "name": "Liliana Elias",
     "sort": 8, "photo": None},
    {"id": "a72a8b2c-6e54-4d9d-9cc1-4abb9eceb7a6", "name": "Dra. Bianca Melo",
     "sort": 9, "photo": None},
]

# Gradientes suaves (top-left -> bottom-right) inspirados no design system.
# Verde Bora primeiro; depois tons pastel/dourado/rosa-poeira/teal por índice.
GRADIENTS = [
    ((22, 163, 74), (74, 222, 128)),    # verde Bora
    ((13, 148, 136), (94, 234, 212)),   # teal
    ((180, 112, 138), (224, 169, 190)), # rosa-poeira
    ((199, 154, 58), (232, 200, 116)),  # dourado
    ((99, 102, 241), (165, 180, 252)),  # índigo suave
]


def http_get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def load_font(size):
    candidates = [
        REPO_ROOT / "assets" / "fonts" / "Inter-Bold.ttf",
        REPO_ROOT / "assets" / "fonts" / "Inter-SemiBold.ttf",
        Path("C:/Windows/Fonts/segoeuib.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf"),
        Path("C:/Windows/Fonts/seguisb.ttf"),
    ]
    for c in candidates:
        try:
            if Path(c).exists():
                return ImageFont.truetype(str(c), size)
        except Exception:
            pass
    return ImageFont.load_default()


def initials_of(name):
    stop = {"dra.", "dra", "dr.", "dr", "de", "da", "do", "e"}
    toks = [t for t in name.replace(".", ". ").split() if t.lower().strip(".") not in stop]
    toks = [t for t in toks if t.strip()]
    if not toks:
        toks = name.split()
    if len(toks) == 1:
        return toks[0][:2].upper()
    return (toks[0][0] + toks[-1][0]).upper()


def make_gradient(size, c1, c2):
    """Gradiente linear diagonal simples e suave."""
    w = h = size
    base = Image.new("RGB", (w, h), c1)
    top = Image.new("RGB", (w, h), c2)
    mask = Image.new("L", (w, h))
    md = mask.load()
    for y in range(h):
        for x in range(w):
            md[x, y] = int(255 * (x + y) / (w + h - 2))
    base.paste(top, (0, 0), mask)
    return base


def initials_avatar(name, idx, size=512):
    c1, c2 = GRADIENTS[idx % len(GRADIENTS)]
    img = make_gradient(size, c1, c2).convert("RGB")
    draw = ImageDraw.Draw(img)
    text = initials_of(name)
    font = load_font(int(size * 0.40))
    # centra o texto
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - tw) / 2 - bbox[0]
    y = (size - th) / 2 - bbox[1]
    # sombra suave para dar profundidade
    draw.text((x + 3, y + 3), text, font=font, fill=(0, 0, 0, 60))
    draw.text((x, y), text, font=font, fill=(255, 255, 255))
    return img


def square_512(raw):
    """Recorta ao quadrado centrado + redimensiona 512x512, achata alpha."""
    im = Image.open(BytesIO(raw))
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im).convert("RGB")
    else:
        im = im.convert("RGB")
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    im = im.crop((left, top, left + side, top + side)).resize((512, 512), Image.LANCZOS)
    return im


def fit_max(raw, max_w, max_h):
    """Redimensiona preservando aspecto (logo/capa), achata alpha em branco."""
    im = Image.open(BytesIO(raw))
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im).convert("RGB")
    else:
        im = im.convert("RGB")
    im.thumbnail((max_w, max_h), Image.LANCZOS)
    return im


def to_jpeg_bytes(im, quality=82):
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=quality, optimize=True)
    return buf.getvalue()


def upload(kind, jpeg_bytes):
    body = json.dumps({
        "restaurantId": PROVIDER_ID,
        "kind": kind,
        "fileBase64": base64.b64encode(jpeg_bytes).decode("ascii"),
        "contentType": "image/jpeg",
    }).encode("utf-8")
    req = urllib.request.Request(
        UPLOAD_FN, data=body, method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {ANON}",
            "apikey": ANON,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"upload {kind} HTTP {e.code}: {e.read().decode('utf-8','replace')[:300]}")
    if not data.get("success") or not data.get("public_url"):
        raise RuntimeError(f"upload {kind} sem public_url: {data}")
    return data["public_url"]


def sql_str(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    if not ANON:
        print("ERRO: define SB_ANON com a anon key.", file=sys.stderr)
        sys.exit(1)

    manifest = {"provider_id": PROVIDER_ID, "logo": None, "hero": None, "staff": []}

    # 1) LOGO
    print("[1/3] Logo...")
    logo_im = fit_max(http_get(LOGO_URL), 800, 800)
    logo_im.save(OUT / "logo.jpg", "JPEG", quality=88)
    manifest["logo"] = upload("logo", to_jpeg_bytes(logo_im, 88))
    print("   ->", manifest["logo"])

    # 1b) CAPA / HERO
    print("[2/3] Capa...")
    hero_im = fit_max(http_get(COVER_URL), 1280, 720)
    hero_im.save(OUT / "hero.jpg", "JPEG", quality=84)
    manifest["hero"] = upload("hero", to_jpeg_bytes(hero_im, 84))
    print("   ->", manifest["hero"])

    # 2) STAFF
    print("[3/3] Equipa (9)...")
    for i, s in enumerate(STAFF):
        if s["photo"]:
            im = square_512(http_get(s["photo"]))
            src = "noona"
        else:
            im = initials_avatar(s["name"], i)
            src = "avatar_iniciais"
        fname = f"staff-{s['sort']}.jpg"
        im.save(OUT / fname, "JPEG", quality=80)
        url = upload(f"staff-{s['sort']}", to_jpeg_bytes(im, 80))
        manifest["staff"].append({
            "id": s["id"], "name": s["name"], "sort": s["sort"],
            "source": src, "public_url": url,
        })
        print(f"   [{s['sort']}] {s['name']:<20} {src:<16} -> {url}")

    # 3) manifest + SQL
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "-- BeUnique Beauty and Academy — instalar imagens (gerado por tools/beunique/build_photos.py)",
        f"-- provider_id = {PROVIDER_ID}",
        "",
        "UPDATE service_providers SET",
        f"  photo_url = {sql_str(manifest['logo'])},",
        f"  hero_image_url = {sql_str(manifest['hero'])}",
        f"WHERE id = {sql_str(PROVIDER_ID)};",
        "",
    ]
    for st in manifest["staff"]:
        lines.append(
            f"UPDATE staff_members SET photo_url = {sql_str(st['public_url'])} "
            f"WHERE id = {sql_str(st['id'])};  -- {st['name']} ({st['source']})"
        )
    SQL_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\nOK. Manifest:", OUT / "manifest.json")
    print("SQL:", SQL_PATH)


if __name__ == "__main__":
    main()
