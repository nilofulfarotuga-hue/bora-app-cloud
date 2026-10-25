#!/usr/bin/env python3
"""Corta pausas longas de um video bruto (ffmpeg silencedetect), mantendo margem.

Uso: python corta_pausas.py entrada.mp4 saida.mp4 [--ruido -35] [--min-pausa 0.5]
                           [--margem 0.15] [--dry-run]
So stdlib + ffmpeg/ffprobe. Nunca altera o ficheiro de entrada.
"""
import argparse, re, subprocess, sys, tempfile, os


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def duracao(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", path])
    return float(r.stdout.strip())


def pausas(path, ruido, min_pausa):
    r = run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af",
             f"silencedetect=noise={ruido}dB:d={min_pausa}", "-f", "null", "-"])
    ini = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", r.stderr)]
    fim = [float(x) for x in re.findall(r"silence_end: (-?[\d.]+)", r.stderr)]
    if len(ini) > len(fim):  # silencio ate ao fim do ficheiro
        fim.append(None)
    return list(zip(ini, fim))


def segmentos_a_manter(total, sil, margem):
    """Fala = complemento das pausas; cada pausa perde so o miolo (margem fica nas pontas)."""
    cortes = []
    for s, e in sil:
        e = total if e is None else e
        a, b = max(s, 0) + margem, e - margem
        if b - a > 0.05:
            cortes.append((a, b))
    manter, cur = [], 0.0
    for a, b in cortes:
        if a - cur > 0.05:
            manter.append((cur, a))
        cur = b
    if total - cur > 0.05:
        manter.append((cur, total))
    return manter


def main():
    p = argparse.ArgumentParser()
    p.add_argument("entrada"); p.add_argument("saida")
    p.add_argument("--ruido", type=float, default=-35)
    p.add_argument("--min-pausa", type=float, default=0.5)
    p.add_argument("--margem", type=float, default=0.15)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    total = duracao(a.entrada)
    manter = segmentos_a_manter(total, pausas(a.entrada, a.ruido, a.min_pausa), a.margem)
    if not manter:
        sys.exit("ERRO: nada para manter (ruido/min-pausa mal ajustados?)")
    novo = sum(b - a_ for a_, b in manter)
    print(f"duracao: {total:.2f}s -> {novo:.2f}s | segmentos: {len(manter)} | margem: {a.margem}s")
    if a.dry_run:
        for s, e in manter:
            print(f"  manter {s:.2f} - {e:.2f}")
        return

    # filter_complex em ficheiro: evita limite de linha de comandos do Windows
    partes, ins = [], ""
    for i, (s, e) in enumerate(manter):
        partes.append(f"[0:v]trim={s:.3f}:{e:.3f},setpts=PTS-STARTPTS[v{i}];"
                      f"[0:a]atrim={s:.3f}:{e:.3f},asetpts=PTS-STARTPTS[a{i}]")
        ins += f"[v{i}][a{i}]"
    partes.append(f"{ins}concat=n={len(manter)}:v=1:a=1[v][a]")
    fd, fg = tempfile.mkstemp(suffix=".txt"); os.close(fd)
    with open(fg, "w", encoding="utf-8") as f:
        f.write(";\n".join(partes))
    try:
        # ffmpeg novo (>=7): -/filter_complex ; antigo (VPS): -filter_complex_script
        for flag in ("-/filter_complex", "-filter_complex_script"):
            r = run(["ffmpeg", "-hide_banner", "-y", "-i", a.entrada, flag, fg,
                     "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "veryfast",
                     "-crf", "20", "-c:a", "aac", a.saida])
            if r.returncode == 0 or "Unrecognized option" not in r.stderr:
                break
    finally:
        os.remove(fg)
    if r.returncode != 0:
        sys.exit("ERRO ffmpeg:\n" + r.stderr[-800:])
    print(f"saida: {a.saida} ({duracao(a.saida):.2f}s)")


if __name__ == "__main__":
    main()
