#!/usr/bin/env python3
"""Regra de roteiro: 2,5 palavras por segundo (20 s ~ 50 palavras).

Uso: python conta_palavras.py <duracao_s> "fala 1" ["fala 2" ...]
     python conta_palavras.py <duracao_s> --ficheiro roteiro.txt   (uma fala por linha)
Exit 0 = cabe; exit 1 = excede o limite.
"""
import sys

PPS = 2.5


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    dur = float(sys.argv[1].replace(",", "."))
    if sys.argv[2] == "--ficheiro":
        falas = [l.strip() for l in open(sys.argv[3], encoding="utf-8") if l.strip()]
    else:
        falas = sys.argv[2:]
    total = 0
    for f in falas:
        n = len(f.split())
        total += n
        print(f"{n:3d} palavras ~{n / PPS:4.1f}s | {f[:60]}")
    limite = int(dur * PPS)
    print(f"TOTAL {total} palavras ~{total / PPS:.1f}s | limite {limite} para {dur:g}s")
    if total > limite:
        print(f"EXCEDE em {total - limite} palavras: corta texto ou sobe a duracao")
        sys.exit(1)
    print("OK: cabe no tempo")


if __name__ == "__main__":
    main()
