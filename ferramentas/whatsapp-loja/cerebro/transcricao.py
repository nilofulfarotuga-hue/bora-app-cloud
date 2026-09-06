# -*- coding: utf-8 -*-
"""transcricao.py — ouvir audios e ver imagens, de graca. Cadeia provada nivel a nivel.

Audio:  1) Groq whisper-large-v3-turbo (chave GROQ_API_KEY no cerebro/.env desde 02/09 12:40; gratis, ~1 s)
        2) faster-whisper LOCAL (small se estiver no disco, senao base; int8, CPU; PT)
        3) gemini-3.6-flash com o audio inline (chave em backend/.env)
Imagem: gemini-3.6-flash (visao) com o contexto da ficha.
O texto transcrito entra na conversa como se fosse texto escrito; o bot responde em texto.
"""
import base64
import json
import os
import subprocess
import tempfile
import urllib.request

from . import supa

MODELOS_WHISPER = ("small", "base")
_whisper = {}


def _ffmpeg_para_wav(caminho):
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    for exe in ("ffmpeg", r"C:\BoraLocal\BoraStudio\_bin\ffmpeg.exe"):
        try:
            r = subprocess.run([exe, "-y", "-v", "error", "-i", caminho, "-ac", "1", "-ar", "16000", tmp],
                               capture_output=True, timeout=120)
            if r.returncode == 0 and os.path.getsize(tmp) > 1000:
                return tmp
        except Exception:
            continue
    return None


def _whisper_modelo():
    from faster_whisper import WhisperModel
    for nome in MODELOS_WHISPER:
        if nome in _whisper:
            return nome, _whisper[nome]
        try:
            _whisper[nome] = WhisperModel(nome, device="cpu", compute_type="int8", local_files_only=(nome == "small"))
            return nome, _whisper[nome]
        except Exception:
            continue
    _whisper["base"] = WhisperModel("base", device="cpu", compute_type="int8")
    return "base", _whisper["base"]


def _local(caminho, idioma="pt"):
    nome, m = _whisper_modelo()
    wav = _ffmpeg_para_wav(caminho) or caminho
    segs, info = m.transcribe(wav, language=idioma, beam_size=2, vad_filter=True)
    texto = " ".join(s.text.strip() for s in segs).strip()
    return texto, "faster-whisper:" + nome


def _gemini_audio(caminho):
    key = supa.ENV.get("GEMINI_API_KEY") or ""
    if not key:
        raise RuntimeError("sem GEMINI_API_KEY")
    wav = _ffmpeg_para_wav(caminho) or caminho
    mime = "audio/wav" if wav.endswith(".wav") else "audio/ogg"
    corpo = {"contents": [{"role": "user", "parts": [
        {"text": "Transcreve este audio em portugues, palavra por palavra, sem comentarios. Se nao houver fala, responde so: (sem fala)"},
        {"inline_data": {"mime_type": mime, "data": base64.b64encode(open(wav, "rb").read()).decode()}}]}],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 400}}
    req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=" + key,
                                 data=json.dumps(corpo).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
    parts = (d.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
    return "".join(p.get("text", "") for p in parts).strip(), "gemini-3.6-flash"


UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"


def _groq_audio(caminho, idioma="pt"):
    """Groq whisper-large-v3-turbo pela API compativel com a OpenAI (multipart). O Cloudflare do Groq
    devolve 403/1010 a pedidos sem User-Agent de browser (igual ao Zen)."""
    key = supa.ENV.get("GROQ_API_KEY") or os.environ.get("GROQ_API_KEY") or ""
    if not key:
        raise RuntimeError("sem GROQ_API_KEY")
    wav = _ffmpeg_para_wav(caminho) or caminho
    dados = open(wav, "rb").read()
    limite = "----BoraGroq" + os.urandom(8).hex()

    def campo(nome, valor):
        return ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (limite, nome, valor)).encode()

    corpo = campo("model", "whisper-large-v3-turbo") + campo("language", idioma) + campo("response_format", "json") + campo("temperature", "0")
    corpo += ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % limite).encode()
    corpo += dados + ("\r\n--%s--\r\n" % limite).encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/audio/transcriptions", data=corpo,
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "multipart/form-data; boundary=" + limite,
                                          "User-Agent": UA_BROWSER, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
    return (d.get("text") or "").strip(), "groq:whisper-large-v3-turbo"


def transcrever(caminho, idioma="pt"):
    """Devolve (texto, motor, erros). Nunca levanta: se tudo falhar, texto='' e erros diz porque."""
    erros = []
    for fn in (_groq_audio, _local, _gemini_audio):
        try:
            texto, motor = fn(caminho) if fn is _gemini_audio else fn(caminho, idioma)
            if texto:
                return texto, motor, erros
            erros.append(fn.__name__ + ": vazio")
        except Exception as e:  # noqa: BLE001
            erros.append("%s: %s: %s" % (fn.__name__, type(e).__name__, str(e)[:120]))
    return "", None, erros


def ver_imagem(caminho, contexto=""):
    """O que esta na foto, com o contexto da ficha. Devolve (descricao, erro)."""
    key = supa.ENV.get("GEMINI_API_KEY") or ""
    if not key:
        return "", "sem GEMINI_API_KEY"
    ext = os.path.splitext(caminho)[1].lower()
    mime = {"png": "image/png", "webp": "image/webp"}.get(ext.strip("."), "image/jpeg")
    corpo = {"contents": [{"role": "user", "parts": [
        {"text": "Es o atendimento do Bora (delivery na Guarda). Descreve esta imagem em 2-3 frases uteis para responder ao cliente: "
                 "e um talao/comprovativo? uma foto de produto ou de loja? um print de erro da app? uma reclamacao? Contexto: " + (contexto or "")[:400]},
        {"inline_data": {"mime_type": mime, "data": base64.b64encode(open(caminho, "rb").read()).decode()}}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 250}}
    try:
        req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=" + key,
                                     data=json.dumps(corpo).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            d = json.loads(r.read())
        parts = (d.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
        return "".join(p.get("text", "") for p in parts).strip(), None
    except Exception as e:  # noqa: BLE001
        return "", "%s: %s" % (type(e).__name__, str(e)[:120])


if __name__ == "__main__":
    import sys
    print(transcrever(sys.argv[1]) if len(sys.argv) > 1 else "uso: transcricao.py <audio>")
