# -*- coding: utf-8 -*-
"""Monta os vídeos IPG do Bora (9:16, 1080x1920, 30 fps) — missão videos-ipg-30-09.

Cada vídeo é uma lista de SEGMENTOS; cada segmento gera fotogramas PIL que vão por
pipe para um único ffmpeg (pouca memória: o PC tem 4 GB). No fim junta-se a voz
(edge-tts, uma frase por segmento) e a música.

Tipos de segmento:
  clip   — plano de vídeo (Veo/banco), com empurrão de câmara lento
  still  — fotografia com Ken Burns
  phone  — telemóvel desenhado a flutuar sobre fundo desfocado, com ECRÃS REAIS da app
           (capturas do app.boraguarda.com) a trocar e toques animados
  fim    — cartão final: logo Bora + QR boraguarda.com/baixar?de=<origem> + BEMVINDO

Regra da marca: embalagens com marca só entram por planos/fotos que já a têm impressa
por script; este ficheiro nunca desenha logos de terceiros.
"""
import json, math, os, re, subprocess, sys, asyncio
from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
MAT = os.path.join(AQUI, "_material")
W, H, FPS = 1080, 1920, 30
VERDE, VERDE_ESC, LARANJA = (22, 163, 74), (12, 92, 44), (249, 115, 22)
FONTE = os.path.join(MAT, "fontes", "Inter-VariableFont.ttf")
LOGO = os.path.join(MAT, "imagens", "bora_logo.png")
sys.path.insert(0, MAT)
import bora_qr  # noqa: E402


def fonte(tam, peso=800):
    f = ImageFont.truetype(FONTE, tam)
    try:
        f.set_variation_by_axes([32, peso])
    except Exception:
        pass
    return f


def ease(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


# ------------------------------------------------------------------ texto
def caixa_texto(linhas, tam=84, destaque=None, fundo=(0, 0, 0, 170), cor=(255, 255, 255)):
    """Bloco de texto grande centrado, com fundo arredondado. `destaque` = palavra a laranja."""
    f = fonte(tam, 850)
    d0 = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    alt_l = int(tam * 1.18)
    larg = max(d0.textlength(l, font=f) for l in linhas)
    pad_x, pad_y = int(tam * 0.55), int(tam * 0.38)
    im = Image.new("RGBA", (int(larg + 2 * pad_x), alt_l * len(linhas) + 2 * pad_y), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=int(tam * 0.45), fill=fundo)
    for i, l in enumerate(linhas):
        x = (im.width - d.textlength(l, font=f)) / 2
        y = pad_y + i * alt_l
        if destaque and destaque in l:
            a, b = l.split(destaque, 1)
            d.text((x, y), a, font=f, fill=cor)
            x2 = x + d.textlength(a, font=f)
            d.text((x2, y), destaque, font=f, fill=LARANJA)
            d.text((x2 + d.textlength(destaque, font=f), y), b, font=f, fill=cor)
        else:
            d.text((x, y), l, font=f, fill=cor)
    return im


def rodape(txt, tam=30):
    f = fonte(tam, 500)
    d0 = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    w = int(d0.textlength(txt, font=f)) + 40
    im = Image.new("RGBA", (w, int(tam * 1.7)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, im.height - 1], radius=14, fill=(0, 0, 0, 140))
    d.text((20, int(tam * 0.3)), txt, font=f, fill=(255, 255, 255, 235))
    return im


def pos_texto(im, onde):
    x = (W - im.width) // 2
    y = {"cima": 260, "meio": (H - im.height) // 2 - 120, "baixo": 1330}.get(onde, onde)
    return x, y


def aplicar_textos(fr, seg, t):
    """Textos do segmento: entram com um pequeno salto de escala nos primeiros 0,25 s."""
    for tx in seg.get("textos", []):
        a, b = tx.get("de", 0), tx.get("ate", seg["dur"])
        if not (a <= t < b):
            continue
        im = tx["_im"]
        k = ease((t - a) / 0.25)
        esc = 0.85 + 0.15 * k
        im2 = im.resize((max(1, int(im.width * esc)), max(1, int(im.height * esc))), Image.LANCZOS) if esc < 0.999 else im
        if k < 1:
            al = im2.getchannel("A").point(lambda v: int(v * k))
            im2 = im2.copy(); im2.putalpha(al)
        x, y = pos_texto(im, tx.get("onde", "cima"))
        x += (im.width - im2.width) // 2; y += (im.height - im2.height) // 2
        fr.alpha_composite(im2, (x, y))
    if seg.get("rodape") and seg["tipo"] != "fim":
        r = seg["_rodape"]
        fr.alpha_composite(r, ((W - r.width) // 2, H - 330))
    return fr


# ------------------------------------------------------------------ fontes de imagem
def ler_clip(src, ss, dur, alvo=(1188, 2112)):
    """Fotogramas de um vídeo, já cobertos para 1188x2112 (10% de folga para o empurrão)."""
    aw, ah = alvo
    cmd = ["ffmpeg", "-v", "error", "-ss", str(ss), "-t", str(dur), "-i", src, "-an",
           "-vf", f"fps={FPS},scale={aw}:{ah}:force_original_aspect_ratio=increase:flags=lanczos,crop={aw}:{ah}",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-threads", "2", "-"]
    cmd[1:3] = ["-v", "quiet"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = aw * ah * 3
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield Image.frombytes("RGB", (aw, ah), b)
    p.kill(); p.wait()


def empurrar(im, k, z0=1.0, z1=1.08, dx=0.0, dy=0.0, ay=0.5):
    """Recorta 1080x1920 de `im` com zoom z0->z1 e deslize (fracção) ao longo de k∈[0,1]."""
    z = z0 + (z1 - z0) * k
    cw = im.width / 1.1 / z          # a fonte tem 10% de folga sobre 1080x1920
    ch = cw * H / W
    cx = im.width / 2 + dx * im.width * (k - 0.5)
    cy = im.height * ay + dy * im.height * (k - 0.5)
    cx = min(max(cx, cw / 2), im.width - cw / 2)
    cy = min(max(cy, ch / 2), im.height - ch / 2)
    box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
    return im.resize((W, H), Image.BILINEAR, box=box)


def seg_clip(seg):
    n = int(round(seg["dur"] * FPS))
    zz = seg.get("zoom", (1.0, 1.07))
    for i, im in enumerate(ler_clip(seg["src"], seg.get("ss", 0), seg["dur"] + 0.2)):
        if i >= n:
            break
        yield empurrar(im, i / max(1, n - 1), zz[0], zz[1], seg.get("dx", 0), seg.get("dy", 0), seg.get("ay", 0.5)).convert("RGBA"), i / FPS


def cobrir(im, alvo=(1188, 2112)):
    im = im.convert("RGB")
    aw, ah = alvo
    s = max(aw / im.width, ah / im.height)
    im = im.resize((int(im.width * s + 1), int(im.height * s + 1)), Image.LANCZOS)
    x, y = (im.width - aw) // 2, (im.height - ah) // 2
    return im.crop((x, y, x + aw, y + ah))


def _cartao(src, larg=900):
    """Foto pequena/quadrada: inteira, num cartão arredondado, sobre ela própria desfocada."""
    im = Image.open(src).convert("RGB")
    fundo = cobrir(im).filter(ImageFilter.GaussianBlur(30))
    fundo = Image.blend(fundo, Image.new("RGB", fundo.size, (0, 0, 0)), 0.35)
    c = im.resize((larg, int(im.height * larg / im.width)), Image.LANCZOS)
    m = _mascara_arred(c.width, c.height, 48)
    sombra = Image.new("RGBA", (c.width + 120, c.height + 120), (0, 0, 0, 0))
    ImageDraw.Draw(sombra).rounded_rectangle([60, 80, c.width + 60, c.height + 80], radius=52, fill=(0, 0, 0, 160))
    sombra = sombra.filter(ImageFilter.GaussianBlur(30))
    base = fundo.convert("RGBA")
    x, y = (base.width - c.width) // 2, (base.height - c.height) // 2 + 60
    base.alpha_composite(sombra, (x - 60, y - 60))
    base.paste(c, (x, y), m)
    return base.convert("RGB")


def seg_still(seg):
    base = _cartao(seg["src"]) if seg.get("cartao") else cobrir(Image.open(seg["src"]))
    n = int(round(seg["dur"] * FPS))
    zz = seg.get("zoom", (1.0, 1.1))
    for i in range(n):
        yield empurrar(base, i / max(1, n - 1), zz[0], zz[1], seg.get("dx", 0), seg.get("dy", 0), seg.get("ay", 0.5)).convert("RGBA"), i / FPS


# ------------------------------------------------------------------ telemóvel
SCR_W = 700
SCR_H = int(SCR_W * 2532 / 1170)          # 1515
BEZ = 18
PH_W, PH_H = SCR_W + 2 * BEZ, SCR_H + 2 * BEZ


def _mascara_arred(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m


MASC_ECRA = None
CORPO = None
SOMBRA = None


def _preparar_telemovel():
    global MASC_ECRA, CORPO, SOMBRA
    if CORPO is not None:
        return
    MASC_ECRA = _mascara_arred(SCR_W, SCR_H, 88)
    CORPO = Image.new("RGBA", (PH_W, PH_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(CORPO)
    d.rounded_rectangle([0, 0, PH_W - 1, PH_H - 1], radius=106, fill=(18, 18, 20, 255))
    d.rounded_rectangle([3, 3, PH_W - 4, PH_H - 4], radius=103, outline=(70, 70, 76, 255), width=3)
    SOMBRA = Image.new("RGBA", (PH_W + 160, PH_H + 160), (0, 0, 0, 0))
    ImageDraw.Draw(SOMBRA).rounded_rectangle([80, 110, PH_W + 80, PH_H + 110], radius=110, fill=(0, 0, 0, 150))
    SOMBRA = SOMBRA.filter(ImageFilter.GaussianBlur(40))


def _ecra(path):
    im = Image.open(path).convert("RGB")
    return im.resize((SCR_W, SCR_H), Image.LANCZOS)


def _ilha(scr):
    d = ImageDraw.Draw(scr)
    d.rounded_rectangle([SCR_W // 2 - 95, 22, SCR_W // 2 + 95, 74], radius=26, fill=(0, 0, 0))
    return scr


def seg_phone(seg):
    """ecras: [[ficheiro, t_inicio], ...]; toques: [[t, x_css, y_css], ...] (ecrã 390x844)."""
    _preparar_telemovel()
    fundo = seg["_fundo"]
    ecras = [(_ilha(_ecra(p)), t0) for p, t0 in seg["ecras"]]
    esc_css = SCR_W / 390
    n = int(round(seg["dur"] * FPS))
    y_base = seg.get("y", 330)
    x0 = (W - PH_W) // 2
    entrada = seg.get("entrada", True)
    for i in range(n):
        t = i / FPS
        fr = fundo.copy()
        # ecrã actual + transição a deslizar (0,32 s)
        idx = max(j for j, (_, t0) in enumerate(ecras) if t0 <= t) if any(t0 <= t for _, t0 in ecras) else 0
        scr = ecras[idx][0].copy()
        if idx > 0 and t - ecras[idx][1] < 0.32:
            k = ease((t - ecras[idx][1]) / 0.32)
            ant = ecras[idx - 1][0]
            tela = Image.new("RGB", (SCR_W, SCR_H))
            off = int(SCR_W * k)
            tela.paste(ant, (-off, 0)); tela.paste(ecras[idx][0], (SCR_W - off, 0))
            scr = tela
        scr = scr.convert("RGBA")
        # toques
        d = ImageDraw.Draw(scr)
        for tt, xc, yc in seg.get("toques", []):
            if tt <= t < tt + 0.5:
                k = (t - tt) / 0.5
                r = 18 + 62 * ease(k)
                a = int(200 * (1 - k))
                cx, cy = xc * esc_css, yc * esc_css
                d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, a), width=6)
                if k < 0.6:
                    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(255, 255, 255, int(150 * (1 - k / 0.6))))
        # telemóvel: entra a subir nos primeiros 0,4 s e flutua devagar
        flut = 10 * math.sin(2 * math.pi * 0.45 * t)
        sub = (1 - ease(t / 0.4)) * 500 if entrada else 0
        y = int(y_base + flut + sub)
        fr.alpha_composite(SOMBRA, (x0 - 80, y - 80))
        fr.alpha_composite(CORPO, (x0, y))
        ecr = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 0))
        ecr.paste(scr, (0, 0), MASC_ECRA)
        fr.alpha_composite(ecr, (x0 + BEZ, y + BEZ))
        yield fr, t


def fundo_desfocado(src, ss=0.0, escurecer=0.45):
    if src.lower().endswith((".mp4", ".mov", ".webm")):
        im = next(ler_clip(src, ss, 0.5))
    else:
        im = cobrir(Image.open(src))
    im = im.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(28))
    escuro = Image.new("RGB", (W, H), (0, 0, 0))
    im = Image.blend(im, escuro, escurecer)
    # brilho verde da marca por trás do telemóvel
    brilho = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(brilho).ellipse([90, 420, W - 90, H - 260], fill=VERDE + (120,))
    brilho = brilho.filter(ImageFilter.GaussianBlur(120))
    im = im.convert("RGBA"); im.alpha_composite(brilho)
    return im


# ------------------------------------------------------------------ cartão final
def seg_fim(seg):
    origem = seg["origem"]
    url = "https://boraguarda.com/baixar?de=" + origem
    assert re.match(r"^[a-z0-9-]{1,48}$", origem), origem
    fundo = Image.new("RGB", (W, H), VERDE)
    g = Image.new("L", (1, H))
    for yy in range(H):
        g.putpixel((0, yy), int(255 * (yy / H) ** 1.4))
    esc = Image.new("RGB", (W, H), VERDE_ESC)
    fundo = Image.composite(esc, fundo, g.resize((W, H))).convert("RGBA")
    # logo sobre cartão branco (o logo tem verde, precisa de fundo claro)
    lg = Image.open(LOGO).convert("RGBA")
    lw = 640
    lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
    cart_logo = Image.new("RGBA", (lw + 90, lg.height + 70), (0, 0, 0, 0))
    ImageDraw.Draw(cart_logo).rounded_rectangle([0, 0, cart_logo.width - 1, cart_logo.height - 1], radius=48, fill=(255, 255, 255, 255))
    cart_logo.alpha_composite(lg, (45, 35))
    tit = caixa_texto(seg.get("titulo", ["Descarrega a Bora"]), tam=96, fundo=(0, 0, 0, 0))
    qr = bora_qr.qr_em_cartao(url, 460, logo=LOGO)
    cod = caixa_texto(["Código BEMVINDO"], tam=80, destaque="BEMVINDO", fundo=(255, 255, 255, 255), cor=(15, 23, 42))
    sub = caixa_texto(["€5 de oferta no 1.º pedido"], tam=58, fundo=(0, 0, 0, 0))
    end = caixa_texto([bora_qr.endereco_curto()], tam=36, fundo=(0, 0, 0, 0), cor=(220, 252, 231))
    pecas = [(cart_logo, 150), (tit, 150 + cart_logo.height + 30)]
    yq = pecas[-1][1] + tit.height + 20
    pecas += [(qr, yq), (end, yq + qr.height + 6), (cod, yq + qr.height + 80), (sub, yq + qr.height + 80 + cod.height + 6)]
    n = int(round(seg["dur"] * FPS))
    for i in range(n):
        t = i / FPS
        fr = fundo.copy()
        for j, (im, y) in enumerate(pecas):
            k = ease((t - 0.07 * j) / 0.3)
            if k <= 0:
                continue
            e = 0.8 + 0.2 * k
            im2 = im.resize((max(1, int(im.width * e)), max(1, int(im.height * e))), Image.LANCZOS) if e < 0.999 else im
            if k < 1:
                im2 = im2.copy(); im2.putalpha(im2.getchannel("A").point(lambda v: int(v * k)))
            fr.alpha_composite(im2, ((W - im2.width) // 2, y + (im.height - im2.height) // 2))
        if seg.get("rodape"):
            r = seg["_rodape"]
            fr.alpha_composite(r, ((W - r.width) // 2, H - 150))
        yield fr, t


GER = {"clip": seg_clip, "still": seg_still, "phone": seg_phone, "fim": seg_fim}


# ------------------------------------------------------------------ voz e música
async def _tts(txt, voz, saida, rate="+8%", pitch="+0Hz"):
    import edge_tts
    await edge_tts.Communicate(txt, voz, rate=rate, pitch=pitch).save(saida)


def duracao(f):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", f]).decode().strip())


def montar(plano, saida):
    tmp = saida + ".tmp"
    os.makedirs(tmp, exist_ok=True)
    segs = plano["segmentos"]
    # prepara textos e fundos
    for s in segs:
        for tx in s.get("textos", []):
            tx["_im"] = caixa_texto(tx["linhas"], tam=tx.get("tam", 84), destaque=tx.get("destaque"))
        if s.get("rodape"):
            s["_rodape"] = rodape(s["rodape"])
        if s["tipo"] == "phone":
            s["_fundo"] = fundo_desfocado(s["fundo"], s.get("fundo_ss", 0))
    video = os.path.join(tmp, "video.mp4")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast",
                            "-crf", "19", "-pix_fmt", "yuv420p", "-threads", "2", video], stdin=subprocess.PIPE)
    t_ini = []
    t_acum = 0.0
    for s in segs:
        t_ini.append(t_acum)
        nfr = 0
        for fr, t in GER[s["tipo"]](s):
            fr = aplicar_textos(fr, s, t)
            enc.stdin.write(fr.convert("RGB").tobytes())
            nfr += 1
        t_acum += nfr / FPS
        print(f"  segmento {s['tipo']:6s} {nfr / FPS:5.2f}s", flush=True)
    enc.stdin.close(); enc.wait()
    total = t_acum
    # voz: uma frase por segmento (campo "voz"), começa 0,15 s depois do corte
    entradas, filtros = [], []
    for i, s in enumerate(segs):
        if not s.get("voz"):
            continue
        f = os.path.join(tmp, f"voz{i}.mp3")
        asyncio.run(_tts(s["voz"], plano.get("voz", "pt-PT-RaquelNeural"), f, rate=plano.get("rate", "+8%")))
        entradas.append(f)
        filtros.append((len(entradas), int((t_ini[i] + s.get("voz_atraso", 0.15)) * 1000)))
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", video, "-i", plano["musica"]]
    for f in entradas:
        cmd += ["-i", f]
    fc = [f"[1:a]atrim=start={plano.get('musica_ss', 0)}:duration={total},asetpts=PTS-STARTPTS,"
          f"volume={plano.get('musica_vol', 0.22)},afade=t=out:st={total - 1.2}:d=1.2[m]"]
    rot = ["[m]"]
    for k, (j, ms) in enumerate(filtros):
        fc.append(f"[{j + 1}:a]adelay={ms}|{ms},volume=1.6[v{k}]")
        rot.append(f"[v{k}]")
    fc.append("".join(rot) + f"amix=inputs={len(rot)}:normalize=0:duration=first,alimiter=limit=0.95[a]")
    cmd += ["-filter_complex", ";".join(fc), "-map", "0:v", "-map", "[a]", "-c:v", "copy",
            "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", saida]
    subprocess.run(cmd, check=True)
    print("ok", saida, round(total, 2), "s")


if __name__ == "__main__":
    plano = json.load(open(sys.argv[1], encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(sys.argv[1]))
    for s in plano["segmentos"]:
        for k in ("src", "fundo"):
            if k in s and not os.path.isabs(s[k]):
                s[k] = os.path.join(base, s[k])
        if "ecras" in s:
            s["ecras"] = [[p if os.path.isabs(p) else os.path.join(base, p), t] for p, t in s["ecras"]]
    if not os.path.isabs(plano["musica"]):
        plano["musica"] = os.path.join(base, plano["musica"])
    montar(plano, sys.argv[2])
