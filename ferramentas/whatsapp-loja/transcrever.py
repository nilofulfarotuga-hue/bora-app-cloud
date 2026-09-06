#!/usr/bin/env python3
"""Transcreve um audio (ogg/opus do WhatsApp, mp3, wav...) para texto, LOCAL e GRATIS.
Por defeito em portugues. Nada sai deste PC. Usa faster-whisper (modelo 'base' por
defeito; 'small' com --modelo small para mais qualidade).

Uso:  python transcrever.py <ficheiro-audio> [--idioma pt] [--modelo base]
Saida: o texto transcrito no stdout (so o texto, para encadear).
"""
import argparse, sys
from faster_whisper import WhisperModel

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--idioma", default="pt")     # WhatsApp da loja fala portugues
    ap.add_argument("--modelo", default="base")   # base=rapido; small=melhor
    a = ap.parse_args()
    m = WhisperModel(a.modelo, device="cpu", compute_type="int8")
    idioma = None if a.idioma == "auto" else a.idioma
    segs, _ = m.transcribe(a.audio, language=idioma)
    sys.stdout.write(" ".join(s.text.strip() for s in segs).strip() + "\n")

if __name__ == "__main__":
    main()
