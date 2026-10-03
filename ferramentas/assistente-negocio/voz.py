"""Voz do Assistente de Negocio (adendo 2, 02/10/2026).

ouvir(b64, mime)  -> (texto, motor): Groq whisper-large-v3-turbo (gratis) -> faster-whisper local (reserva).
falar(texto)      -> caminho de um .ogg (opus, mono) pronto a ir como NOTA DE VOZ: edge-tts pt-PT (gratis).

Chamadas de voz NAO: o Baileys nao as atende. Passo futuro, com a API oficial do WhatsApp."""
import base64
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.request
import uuid

AQUI = os.path.dirname(os.path.abspath(__file__))
PASTA_VOZ = os.environ.get("ASSISTENTE_VOZ_DIR", os.path.join(AQUI, "voz"))
EDGE_TTS = os.environ.get("EDGE_TTS_BIN", "/opt/data/voz/.venv/bin/edge-tts")
WHISPER_PY = os.environ.get("WHISPER_PY", os.path.join(AQUI, ".venv-whisper", "bin", "python"))
VOZ_PT = os.environ.get("ASSISTENTE_VOZ", "pt-PT-DuarteNeural")  # masculina: e uma barbearia (Danilo, 02/10)


def _groq(caminho, mime):
    chave = os.environ.get("GROQ_API_KEY", "")
    if not chave:
        raise RuntimeError("sem GROQ_API_KEY")
    fr = "----assistente" + uuid.uuid4().hex
    corpo = (f"--{fr}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"
             f"--{fr}\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\npt\r\n"
             f"--{fr}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voz.ogg\"\r\n"
             f"Content-Type: {mime or 'audio/ogg'}\r\n\r\n").encode() + open(caminho, "rb").read() + f"\r\n--{fr}--\r\n".encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/audio/transcriptions", corpo,
                                 {"Authorization": "Bearer " + chave, "Content-Type": "multipart/form-data; boundary=" + fr,
                                  "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return (json.load(r).get("text") or "").strip()


# O ffmpeg descodifica para PCM 16 kHz mono e o modelo recebe o array: o `av` que vem com o
# faster-whisper rebentava com "TypeError: open()" a abrir o ogg (medido 02/10/2026).
_LOCAL = r'''
import subprocess, sys
import numpy as np
from faster_whisper import WhisperModel
pcm = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", sys.argv[1], "-f", "s16le", "-ac", "1", "-ar", "16000", "-"],
                     capture_output=True, check=True).stdout
audio = np.frombuffer(pcm, np.int16).astype(np.float32) / 32768.0
m = WhisperModel("base", device="cpu", compute_type="int8")
seg, _ = m.transcribe(audio, language="pt", beam_size=1)
print(" ".join(s.text.strip() for s in seg))
'''


def _local(caminho):
    if not os.path.exists(WHISPER_PY):
        raise RuntimeError("faster-whisper nao instalado")
    r = subprocess.run([WHISPER_PY, "-c", _LOCAL, caminho], capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[-200:])
    return r.stdout.strip()


def ouvir(b64, mime=None, so_local=False):
    """Devolve (texto, motor, erros). Texto vazio = nao se percebeu."""
    erros = []
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as f:
        f.write(base64.b64decode(b64))
        caminho = f.name
    try:
        motores = [("faster-whisper:base", lambda: _local(caminho))] if so_local else \
                  [("groq:whisper-large-v3-turbo", lambda: _groq(caminho, mime)), ("faster-whisper:base", lambda: _local(caminho))]
        for nome, f in motores:
            try:
                t = f()
                if t:
                    return t, nome, erros
                erros.append(f"{nome}: vazio")
            except Exception as e:
                erros.append(f"{nome}: {str(e)[:150]}")
        return "", None, erros
    finally:
        os.unlink(caminho)


def _endereco_falado(m):
    """https://misternavalha.boraguarda.com -> 'misternavalha ponto boraguarda ponto com'"""
    url = re.sub(r"^https?://(www\.)?", "", m.group(0)).rstrip("/.,")
    return url.replace(".", " ponto ").replace("/", " barra ")


def para_falar(texto):
    """Texto para a nota de voz. Conversa por audio = resposta SO em audio (adendo 3, 02/10): le-se TUDO,
    horas incluidas, e os enderecos dizem-se por palavras."""
    t = re.sub(r"https?://\S+", _endereco_falado, texto)
    t = re.sub(r"[*_#\[\]]", "", t).strip()
    t = re.sub(r"\b([01]?\d|2[0-3])[:h]([0-5]\d)\b", _hora_falada, t)
    return re.sub(r"\s*€", " euros", t)


def _hora_falada(m):
    """10:30 -> 'dez e meia' (o edge-tts lia '10:30' de forma estranha)."""
    nomes = ["zero", "uma", "duas", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "onze", "meio-dia",
             "uma", "duas", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "onze"]
    h, mi = int(m.group(1)), int(m.group(2))
    base = nomes[h] if h != 12 else "meio-dia"
    if mi == 0:
        return base if h in (12,) else base + (" hora" if base == "uma" else " horas")
    if mi == 30:
        return base + " e meia"
    return f"{base} e {mi}"


def falar(texto):
    """edge-tts pt-PT -> mp3 -> ogg/opus mono 48 kHz (formato das notas de voz do WhatsApp). Devolve o caminho."""
    os.makedirs(PASTA_VOZ, exist_ok=True)
    base = os.path.join(PASTA_VOZ, time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8])
    mp3, ogg = base + ".mp3", base + ".ogg"
    r = subprocess.run([EDGE_TTS, "--voice", VOZ_PT, "--text", para_falar(texto), "--write-media", mp3],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0 or not os.path.exists(mp3):
        raise RuntimeError("edge-tts falhou: " + (r.stderr or "")[-200:])
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-ac", "1", "-ar", "48000",
                        "-c:a", "libopus", "-b:a", "32k", "-application", "voip", ogg], capture_output=True, text=True, timeout=60)
    os.unlink(mp3)
    if r.returncode != 0 or not os.path.exists(ogg):
        raise RuntimeError("ffmpeg falhou: " + (r.stderr or "")[-200:])
    return ogg


def duracao(ogg):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name,channels,sample_rate",
                        "-of", "json", ogg], capture_output=True, text=True, timeout=20)
    return json.loads(r.stdout or "{}")
