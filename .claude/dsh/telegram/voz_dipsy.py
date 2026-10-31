#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Voz do Dipsy (PC). Codigo nosso, missao C-liga / C5c-voz (30/10/2026). So biblioteca padrao + edge-tts + faster-whisper
(ja instalados no PC).

SAIDA (texto -> voz): o texto INTEIRO vira audio, nunca cortado.
  1. limpa o texto para se ouvir bem (sem markdown, sem enderecos, sem codigo);
  2. parte em pedacos de ate 900 letras, SEMPRE em frases inteiras (e prova que nada se perdeu);
  3. cada pedaco: edge-tts (pt-BR-FranciscaNeural, a mesma voz do Hermes) -> reserva Gemini TTS; ffmpeg -> OGG/Opus mono 32k;
  4. ANTES de mandar, confere a duracao: tem de ter mais de 2 s por cada 100 letras; senao gera outra vez
     (2 tentativas por motor, depois o motor seguinte); se tudo falhar, diz-se (nunca silencio calado);
  5. regista cada pedaco em ~/.dsh/telegram/voz-dipsy.log.jsonl.

ENTRADA (voz -> texto): faster-whisper local em CPU (modelo small, reserva base), portugues; se falhar, Gemini.
  python voz_dipsy.py --transcrever ficheiro.ogg   -> JSON {"texto": ..., "motor": ...}
"""
import base64
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HOME = os.path.expanduser("~")
DSH = os.path.join(HOME, ".dsh")
TMP = os.path.join(DSH, "voz-tmp")
LOG_VOZ = os.path.join(DSH, "telegram", "voz-dipsy.log.jsonl")
LIMITE_PEDACO = 900          # letras por audio (frases inteiras)
SEG_POR_100 = 2.0            # minimo de segundos de audio por cada 100 letras
VOZ_EDGE = "pt-BR-FranciscaNeural"
NO_WINDOW = 0x08000000
MODELOS_GEMINI_TTS = ["gemini-3.8-flash-tts", "gemini-2.5-flash-preview-tts"]
MODELOS_GEMINI_STT = ["gemini-3.1-flash-lite", "gemini-3.6-flash"]
# 31/10 (retoma-geral b3): medido neste PC com 1553 MB livres, o whisper small levou 76 s e errou o texto
# ("Vou incitar no vinho." em vez de "Oi, voce esta me ouvindo?"). Regra nova: abaixo de 1,5 GB vai direto ao Gemini;
# com mais RAM o PC ainda tenta, mas so 10 s, para o "Ouvi:" chegar em menos de 15 s.
RAM_MINIMA_WHISPER_MB = 1500 # abaixo disto o audio vai direto ao Gemini (antes 700)
ORCAMENTO_LOCAL_S = 10       # tempo maximo do whisper local antes de passar ao Gemini (antes 45)
ESPERA_FINAL_LOCAL_S = 200   # se o Gemini tambem falhar, espera-se mais pelo local (a ponte corta aos 300 s)


def registar(**o):
    o["ts"] = datetime.now().isoformat(timespec="seconds")
    try:
        os.makedirs(os.path.dirname(LOG_VOZ), exist_ok=True)
        with open(LOG_VOZ, "a", encoding="utf-8") as f:
            f.write(json.dumps(o, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass


def _exe(nome):
    achado = shutil.which(nome)
    if achado:
        return achado
    base = os.path.join(HOME, "AppData", "Local", "Microsoft", "WinGet", "Packages")
    for c in glob.glob(os.path.join(base, "Gyan.FFmpeg*", "*", "bin", nome + ".exe")):
        return c
    return nome


# --------------------------------------------------------------------------- texto
def limpar_para_voz(t):
    """O que se ouve nao pode ter markdown, codigo nem enderecos. Nada do resto se perde."""
    t = t or ""
    t = re.sub(r"```.*?```", " Há um bloco de código no texto. ", t, flags=re.S)
    t = re.sub(r"`([^`]*)`", r"\1", t)
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"https?://\S+", " o endereço que está no texto ", t)
    t = re.sub(r"(?m)^\s*[-*•]\s+", "", t)
    t = re.sub(r"[*_#>|~]+", " ", t)
    t = "".join(c for c in t if c.isprintable() or c in "\n\t")
    t = re.sub(r"[^\w\s.,;:!?()%€ºª'\"\-\n/@]", " ", t)
    linhas = []
    for ln in t.split("\n"):
        ln = re.sub(r"[ \t]+", " ", ln).strip()
        if not ln:
            continue
        if not re.search(r"[.!?:;…]$", ln):
            ln += "."
        linhas.append(ln)
    return " ".join(linhas).strip()


def partir(texto, limite=LIMITE_PEDACO):
    """Parte em pedacos de ate `limite` letras, em frases inteiras. Prova que juntos dao o texto todo."""
    texto = (texto or "").strip()
    if not texto:
        return []
    frases = [f.strip() for f in re.split(r"(?<=[.!?…])\s+", texto) if f.strip()]
    pequenas = []
    for f in frases:                       # uma frase maior que o limite parte-se na virgula ou no espaco
        while len(f) > limite:
            corte = max(f.rfind(", ", 0, limite), f.rfind("; ", 0, limite), f.rfind(": ", 0, limite))
            if corte < limite // 3:
                corte = f.rfind(" ", 0, limite)
            if corte <= 0:
                corte = limite
            pequenas.append(f[:corte + 1].strip())
            f = f[corte + 1:].strip()
        if f:
            pequenas.append(f)
    pedacos, atual = [], ""
    for f in pequenas:
        if atual and len(atual) + 1 + len(f) > limite:
            pedacos.append(atual)
            atual = f
        else:
            atual = (atual + " " + f).strip()
    if atual:
        pedacos.append(atual)
    junto = re.sub(r"\s+", "", "".join(pedacos))
    original = re.sub(r"\s+", "", texto)
    if junto != original:
        raise RuntimeError("partir() perdeu texto: recusado")
    return pedacos


# --------------------------------------------------------------------------- audio
def duracao_ogg(ficheiro):
    """Duração de um OGG/Opus lida no próprio ficheiro (granule da última página), sem ffprobe: com o PC aflito de memória
    o ffprobe chegou a passar do tempo e a voz caía para o motor de reserva (visto a 30/10/2026)."""
    with open(ficheiro, "rb") as fh:
        b = fh.read()
    i = b.rfind(b"OggS")
    if i < 0 or i + 14 > len(b):
        raise RuntimeError("não é um OGG")
    granule = int.from_bytes(b[i + 6:i + 14], "little", signed=False)
    h = b.find(b"OpusHead")
    pre = int.from_bytes(b[h + 10:h + 12], "little") if h >= 0 else 0
    return max(0.0, (granule - pre) / 48000.0)


def duracao(ficheiro):
    if ficheiro.lower().endswith(".ogg"):
        try:
            return duracao_ogg(ficheiro)
        except Exception:
            pass
    r = subprocess.run([_exe("ffprobe"), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", ficheiro],
                       capture_output=True, timeout=120, creationflags=NO_WINDOW)
    try:
        return float((r.stdout or b"0").decode().strip() or 0)
    except Exception:
        return 0.0


def para_ogg(entrada, saida, extra=None):
    args = [_exe("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y"] + (extra or []) + ["-i", entrada,
            "-ac", "1", "-c:a", "libopus", "-b:a", "32k", saida]
    r = subprocess.run(args, capture_output=True, timeout=300, creationflags=NO_WINDOW)
    if r.returncode != 0 or not os.path.exists(saida) or not os.path.getsize(saida):
        raise RuntimeError("ffmpeg falhou: " + (r.stderr or b"")[:160].decode("utf-8", "replace"))
    return saida


def _tts_edge(texto, base):
    ficheiro_texto = base + ".txt"
    mp3 = base + "-edge.mp3"
    with open(ficheiro_texto, "w", encoding="utf-8") as f:
        f.write(texto)
    r = subprocess.run([sys.executable if not sys.executable.lower().endswith("pythonw.exe") else "python",
                        "-m", "edge_tts", "--voice", VOZ_EDGE, "--file", ficheiro_texto, "--write-media", mp3],
                       capture_output=True, timeout=120, creationflags=NO_WINDOW)
    if r.returncode != 0 or not os.path.exists(mp3) or not os.path.getsize(mp3):
        raise RuntimeError("edge-tts: " + ((r.stderr or b"")[-160:].decode("utf-8", "replace") or "sem audio"))
    return mp3, None


def _tts_gemini(texto, base):
    chave = os.environ.get("GOOGLE_AI_API_KEY", "")
    if not chave:
        raise RuntimeError("sem GOOGLE_AI_API_KEY")
    corpo = json.dumps({
        "contents": [{"parts": [{"text": texto}]}],
        "generationConfig": {"responseModalities": ["AUDIO"],
                             "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Kore"}}}},
    }).encode("utf-8")
    ultimo = "sem resposta"
    for modelo in MODELOS_GEMINI_TTS:
        req = urllib.request.Request(
            f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent",
            data=corpo, headers={"content-type": "application/json", "x-goog-api-key": chave})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                j = json.loads(r.read().decode("utf-8"))
            partes = j["candidates"][0]["content"]["parts"]
            dados = next(p["inlineData"]["data"] for p in partes if "inlineData" in p)
            pcm = base + "-gemini.pcm"
            with open(pcm, "wb") as f:
                f.write(base64.b64decode(dados))
            return pcm, ["-f", "s16le", "-ar", "24000", "-ac", "1"]
        except Exception as e:
            ultimo = f"{modelo}: {type(e).__name__}"
    raise RuntimeError("gemini-tts: " + ultimo)


NIVEIS = (("edge-tts", _tts_edge), ("gemini-tts", _tts_gemini))


def gerar_pedaco(texto, indice=1, total=1):
    """Gera UM audio inteiro e verifica a duracao. Devolve dict com o ogg; levanta se nenhum motor serviu."""
    os.makedirs(TMP, exist_ok=True)
    minimo = SEG_POR_100 * len(texto) / 100.0
    erros = []
    tentativas = 0
    for nome, fn in NIVEIS:
        for volta in (1, 2):
            tentativas += 1
            base = os.path.join(TMP, "v-" + uuid.uuid4().hex[:10])
            t0 = time.time()
            try:
                bruto, extra = fn(texto, base)
                ogg = base + ".ogg"
                para_ogg(bruto, ogg, extra)
                dur = duracao(ogg)
                if dur <= minimo:
                    raise RuntimeError(f"audio curto demais: {dur:.1f} s para {len(texto)} letras (minimo {minimo:.1f} s)")
                registar(evento="parte-gerada", parte=indice, de=total, letras=len(texto), duracao=round(dur, 1),
                         minimo=round(minimo, 1), motor=nome, tentativa=tentativas, ms=int((time.time() - t0) * 1000))
                return {"ogg": ogg, "duracao": dur, "motor": nome, "tentativas": tentativas}
            except Exception as e:
                erros.append(f"{nome}: {str(e)[:120]}")
                registar(evento="parte-falhou", parte=indice, de=total, motor=nome, tentativa=tentativas, erro=str(e)[:160])
                if "sem GOOGLE_AI_API_KEY" in str(e) or nome == "gemini-tts":
                    break
    raise RuntimeError("nenhum motor de voz serviu: " + " | ".join(erros)[-300:])


def limpar_tmp(horas=3):
    try:
        limite = time.time() - horas * 3600
        for f in os.listdir(TMP):
            p = os.path.join(TMP, f)
            if os.path.isfile(p) and os.path.getmtime(p) < limite:
                os.remove(p)
    except Exception:
        pass


# --------------------------------------------------------------------------- voz -> texto
def _transcrever_local(ficheiro):
    from faster_whisper import WhisperModel
    ultimo = None
    for modelo in ("small", "base"):
        try:
            m = WhisperModel(modelo, device="cpu", compute_type="int8", cpu_threads=4)
            segmentos, info = m.transcribe(ficheiro, language="pt", beam_size=5, vad_filter=True,
                                           initial_prompt="Conversa em português com o Dipsy sobre o Bora, o Hermes, o Claude Code, estafetas, parceiros, Supabase e Telegram.")
            texto = " ".join(s.text.strip() for s in segmentos).strip()
            if texto:
                return texto, f"faster-whisper {modelo}"
            ultimo = RuntimeError(f"{modelo}: sem texto")
        except Exception as e:
            ultimo = e
    raise RuntimeError(f"whisper local falhou: {type(ultimo).__name__}")


def _transcrever_gemini(ficheiro):
    chave = os.environ.get("GOOGLE_AI_API_KEY", "")
    if not chave:
        raise RuntimeError("sem GOOGLE_AI_API_KEY")
    with open(ficheiro, "rb") as f:
        dados = base64.b64encode(f.read()).decode()
    corpo = json.dumps({"contents": [{"parts": [
        {"text": "Transcreve fielmente, em português, o que a pessoa diz neste áudio. Devolve só a transcrição."},
        {"inline_data": {"mime_type": "audio/ogg", "data": dados}}]}]}).encode("utf-8")
    ultimo = "sem resposta"
    for ronda in range(2):   # uma segunda volta: o 1.o pedido ja falhou uma vez por limite passageiro (31/10)
        for modelo in MODELOS_GEMINI_STT:
            req = urllib.request.Request(
                f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent",
                data=corpo, headers={"content-type": "application/json", "x-goog-api-key": chave})
            try:
                with urllib.request.urlopen(req, timeout=45) as r:
                    j = json.loads(r.read().decode("utf-8"))
                texto = "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"]).strip()
                if texto:
                    return texto, f"gemini {modelo}"
                ultimo = f"{modelo}: resposta vazia"
            except urllib.error.HTTPError as e:
                ultimo = f"{modelo}: HTTP {e.code}"
            except Exception as e:
                ultimo = f"{modelo}: {type(e).__name__}"
        if ronda == 0:
            time.sleep(3)
    raise RuntimeError(f"gemini: sem transcricao ({ultimo})")


def _ram_livre_mb():
    """RAM fisica livre em MB (Windows). -1 se nao der para medir."""
    try:
        import ctypes

        class MS(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
        s = MS()
        s.dwLength = ctypes.sizeof(MS)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(s))
        return int(s.ullAvailPhys // (1024 * 1024))
    except Exception:
        return -1


def transcrever(ficheiro):
    """Local primeiro (a voz fica no PC). Se a RAM esta curta ou o whisper nao acaba no orcamento, passa ao Gemini
    em vez de deixar a ponte esperar 300 s e dar erro (31/10: o 1.o audio real do Danilo morreu assim)."""
    import threading
    res = {}

    def local():
        try:
            res["ok"] = _transcrever_local(ficheiro)
        except Exception as e:
            res["erro"] = e

    ram = _ram_livre_mb()
    fio = threading.Thread(target=local, daemon=True)
    if 0 <= ram < RAM_MINIMA_WHISPER_MB:
        registar(evento="whisper-saltado", motivo="pouca-ram", ram_livre_mb=ram)
    else:
        fio.start()
        fio.join(ORCAMENTO_LOCAL_S)
        if "ok" in res:
            return res["ok"]
        registar(evento="whisper-falhou" if "erro" in res else "whisper-lento",
                 erro=str(res.get("erro", ""))[:160], orcamento_s=ORCAMENTO_LOCAL_S, ram_livre_mb=ram)
    try:
        t, motor = _transcrever_gemini(ficheiro)
        registar(evento="transcrito-gemini", letras=len(t), ram_livre_mb=ram)
        return t, motor
    except Exception as e2:
        registar(evento="gemini-stt-falhou", erro=str(e2)[:160])
        if not fio.is_alive() and "ok" not in res and "erro" not in res:
            fio.start()
        fio.join(ESPERA_FINAL_LOCAL_S)
        if "ok" in res:
            return res["ok"]
        raise RuntimeError("nem o whisper local nem o Gemini transcreveram") from e2


def main():
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "--transcrever":
        t, motor = transcrever(a[1])
        print(json.dumps({"texto": t, "motor": motor}, ensure_ascii=False))
        sys.stdout.flush()
        os._exit(0)  # o fio do whisper pode ainda estar a carregar; nao esperar por ele
    if len(a) >= 2 and a[0] == "--partir":
        for i, p in enumerate(partir(limpar_para_voz(a[1])), 1):
            print(f"[{i}] ({len(p)}) {p}")
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
