#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VOZ v2 — o UNICO caminho de envio do Hermes para o Danilo: texto completo E audio do texto inteiro. Sem excepcoes.
(missao C5c-voz, 30/10/2026; substitui a v1 de 04/09/2026, que tinha uma regra de "um audio com resumo de 3 frases")

POR QUE O AUDIO SAIA PELA METADE (causa raiz, medida a 30/10/2026):
  1. voz.py v1: se o texto passava de 900 letras o audio levava so as 3 primeiras frases (resumir) ou t[:400]; e limpar(...)[:2500].
  2. edge-tts 7.2.8 estava desatualizado: a Microsoft recusava-o (WebSocket 403) e tudo caia no Piper, mais lento, sem aviso.
  3. O guarda da voz (--teste) so via se ALGUM nivel funcionava; o Piper tapava o edge-tts morto durante semanas.
  4. O agente do Hermes (gateway) usa o seu proprio TTS (edge, tambem a dar 403) e so fala quando o Danilo manda voz; texto
     por cima de 4000 letras e' cortado pelo gateway (text[:4000]).

O QUE FAZ AGORA
  - O texto vai INTEIRO logo (pedacos de ate 3800 letras cortados em quebras de linha ou espacos).
  - O audio e' o texto INTEIRO, em pedacos de ate 900 letras cortados SEMPRE em frases inteiras (e prova-se que nada se perdeu),
    um sendVoice por pedaco, por ordem. OGG/Opus mono 32k, feito por ffmpeg.
  - Antes de mandar cada pedaco confere-se a duracao: tem de ter mais de 2 s por cada 100 letras; senao gera-se outra vez
    (edge-tts 2x, Piper, gTTS). Cada pedaco fica registado em voz.log.jsonl.
  - Quem chama sem querer esperar (scripts de cron, o contentor) deixa o pedido na fila /opt/data/voz/fila/ e um unico
    trabalhador (cron de minuto a minuto + disparo imediato) trata dele. O texto desses scripts nunca depende da voz.
  - O agente do Hermes fala por aqui tambem: servidor local (/sintetizar) que o TTS por comando do gateway chama.

USO
  voz "texto"                      # texto + audio inteiro (espera acabar)
  echo "texto" | voz -             # o mesmo, por pipe
  voz --async "texto"              # texto ja, audio pela fila
  voz --so-audio "texto"           # so audio, pela fila (o texto ja foi mandado por outro caminho)
  voz --so-audio -f ficheiro.txt   # o mesmo, com o texto num ficheiro
  voz --chat 123 "texto"           # outro chat (por omissao: TELEGRAM_HOME_CHANNEL)
  voz --worker                     # trata da fila (cron de minuto a minuto)
  voz --servir 127.0.0.1 172.16.1.1   # servidor de voz para o agente do Hermes (systemd: voz-servidor)
  voz --teste                      # gera audio de prova (nao envia) e diz o nivel usado
  VOZ_SEM_EDGE=1 voz "..."         # mata o nivel 1 de proposito (prova da descida)
Importavel:  from voz import falar;  falar("texto")     # o parametro resumo= ja nao faz nada (aceita-se por compatibilidade)
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VOZ_DIR = "/opt/data/voz"
TMP = os.path.join(VOZ_DIR, "tmp")
FILA = os.path.join(VOZ_DIR, "fila")
FEITOS = os.path.join(VOZ_DIR, "fila-feitos")
LOG = os.path.join(VOZ_DIR, "voz.log.jsonl")
VOZ_PIPER = os.path.join(VOZ_DIR, "vozes", "pt_BR-faber-medium.onnx")
PY_VENV = os.path.join(VOZ_DIR, ".venv", "bin", "python")
EDGE_FALHOU = os.path.join(VOZ_DIR, ".edge-falhou")
ENV_FILES = ["/opt/data/.env", "/opt/data/social/.aviso.conf", "/opt/whatsapp-bora/.env"]
LIMITE_TEXTO_TELEGRAM = 3800
LIMITE_PEDACO = 900
SEG_POR_100 = 2.0
MAX_FILA = 15
VOZ_EDGE = "pt-BR-FranciscaNeural"
PORTA_SERVIDOR = 8794


def _env():
    e = {}
    for p in ENV_FILES:
        try:
            with open(p, encoding="utf-8") as fh:
                for ln in fh:
                    ln = ln.strip()
                    if ln and not ln.startswith("#") and "=" in ln:
                        k, v = ln.split("=", 1)
                        e.setdefault(k.strip(), v.strip().strip('"').strip("'"))
        except Exception:
            pass
    for k, v in os.environ.items():
        e.setdefault(k, v)
    return e


ENV = _env()
CRED = ENV.get("TELEGRAM_BOT_" + "TOKEN", "")
CHAT = ENV.get("TELEGRAM_HOME_CHANNEL", "")


def registar(**o):
    o["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        os.makedirs(VOZ_DIR, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(o, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass


# ───────────────────────────── texto ─────────────────────────────

def limpar(t):
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
    """Pedacos de ate `limite` letras, em frases inteiras. Prova que juntos dao o texto todo (senao levanta)."""
    texto = (texto or "").strip()
    if not texto:
        return []
    frases = [f.strip() for f in re.split(r"(?<=[.!?…])\s+", texto) if f.strip()]
    pequenas = []
    for f in frases:
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
    if re.sub(r"\s+", "", "".join(pedacos)) != re.sub(r"\s+", "", texto):
        raise RuntimeError("partir() perdeu texto: recusado")
    return pedacos


def partir_texto_telegram(texto, limite=LIMITE_TEXTO_TELEGRAM):
    texto = (texto or "").strip()
    pedacos = []
    while texto:
        if len(texto) <= limite:
            pedacos.append(texto)
            break
        corte = max(texto.rfind("\n", 0, limite), texto.rfind(". ", 0, limite) + 1, texto.rfind(" ", 0, limite))
        if corte < limite // 2:
            corte = limite
        pedacos.append(texto[:corte].rstrip())
        texto = texto[corte:].lstrip()
    return pedacos


# ───────────────────────── niveis de voz ─────────────────────────

def _edge_em_pausa():
    try:
        return time.time() - os.path.getmtime(EDGE_FALHOU) < 20 * 60
    except Exception:
        return False


def _n1_edge(texto, base):
    if os.environ.get("VOZ_SEM_EDGE") == "1":
        raise RuntimeError("edge-tts desligado de proposito (VOZ_SEM_EDGE=1)")
    if _edge_em_pausa():
        raise RuntimeError("edge-tts em pausa (falhou ha menos de 20 min)")
    ft = base + ".txt"
    mp3 = base + "-edge.mp3"
    with open(ft, "w", encoding="utf-8") as f:
        f.write(texto)
    exe = os.path.join(VOZ_DIR, ".venv", "bin", "edge-tts")
    r = subprocess.run([exe, "--voice", VOZ_EDGE, "--file", ft, "--write-media", mp3], capture_output=True, timeout=120)
    if r.returncode != 0 or not os.path.exists(mp3) or not os.path.getsize(mp3):
        open(EDGE_FALHOU, "w").write(time.strftime("%FT%T"))
        raise RuntimeError("edge-tts: " + ((r.stderr or b"")[-160:].decode("utf-8", "replace") or "sem audio"))
    return mp3


def _n2_piper(texto, base):
    if not os.path.exists(VOZ_PIPER):
        raise RuntimeError("modelo do Piper nao esta em %s" % VOZ_PIPER)
    wav = base + "-piper.wav"
    r = subprocess.run([os.path.join(VOZ_DIR, ".venv", "bin", "piper"), "-m", VOZ_PIPER, "-f", wav],
                       input=texto.encode("utf-8"), capture_output=True, timeout=300)
    if r.returncode != 0 or not os.path.exists(wav) or not os.path.getsize(wav):
        raise RuntimeError("piper: " + ((r.stderr or b"")[-160:].decode("utf-8", "replace") or "sem audio"))
    return wav


def _n3_gtts(texto, base):
    mp3 = base + "-gtts.mp3"
    codigo = ("from gtts import gTTS\nimport sys\n"
              "gTTS(text=sys.stdin.read(), lang='pt', tld='com.br').save(sys.argv[1])\n")
    r = subprocess.run([PY_VENV, "-c", codigo, mp3], input=texto.encode("utf-8"), capture_output=True, timeout=180)
    if r.returncode != 0 or not os.path.exists(mp3) or not os.path.getsize(mp3):
        raise RuntimeError("gtts: " + ((r.stderr or b"")[-160:].decode("utf-8", "replace") or "sem audio"))
    return mp3


NIVEIS = (("edge-tts", _n1_edge, 2), ("piper", _n2_piper, 1), ("gtts", _n3_gtts, 1))


def duracao(f):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f],
                       capture_output=True, timeout=30)
    try:
        return float((r.stdout or b"0").decode().strip() or 0)
    except Exception:
        return 0.0


def gerar_pedaco(texto, i=1, n=1):
    """Gera UM audio inteiro e confere a duracao. Devolve dict; levanta se nenhum nivel serviu."""
    os.makedirs(TMP, exist_ok=True)
    minimo = SEG_POR_100 * len(texto) / 100.0
    erros, tentativas = [], 0
    for nome, fn, voltas in NIVEIS:
        for _ in range(voltas):
            tentativas += 1
            base = os.path.join(TMP, "v-" + uuid.uuid4().hex[:10])
            t0 = time.time()
            try:
                bruto = fn(texto, base)
                ogg = base + ".ogg"
                c = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", bruto, "-ac", "1",
                                    "-c:a", "libopus", "-b:a", "32k", ogg], capture_output=True, timeout=180)
                if c.returncode != 0 or not os.path.exists(ogg) or not os.path.getsize(ogg):
                    raise RuntimeError("ffmpeg falhou: " + (c.stderr or b"")[:160].decode("utf-8", "replace"))
                dur = duracao(ogg)
                if dur <= minimo:
                    raise RuntimeError("audio curto demais: %.1f s para %d letras (minimo %.1f s)" % (dur, len(texto), minimo))
                registar(evento="parte-gerada", parte=i, de=n, letras=len(texto), duracao=round(dur, 1), minimo=round(minimo, 1),
                         nivel=nome, tentativa=tentativas, ms=int((time.time() - t0) * 1000))
                return {"ogg": ogg, "duracao": dur, "nivel": nome, "tentativas": tentativas}
            except Exception as e:
                erros.append("%s: %s" % (nome, str(e)[:110]))
                registar(evento="parte-falhou", parte=i, de=n, nivel=nome, tentativa=tentativas, erro=str(e)[:200])
    raise RuntimeError("nenhum nivel de voz serviu: " + " | ".join(erros)[-300:])


# ───────────────────────────── Telegram ────────────────────────────

def _pedir(metodo, campos, ficheiro=None):
    url = "https://api.telegram.org/bot%s/%s" % (CRED, metodo)
    lim = "----voz%s" % uuid.uuid4().hex
    corpo = b""
    for k, v in campos.items():
        corpo += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (lim, k, v)).encode("utf-8")
    if ficheiro:
        nome, dados = ficheiro
        corpo += ("--%s\r\nContent-Disposition: form-data; name=\"voice\"; filename=\"%s\"\r\n"
                  "Content-Type: audio/ogg\r\n\r\n" % (lim, nome)).encode("utf-8")
        corpo += dados + b"\r\n"
    corpo += ("--%s--\r\n" % lim).encode("utf-8")
    req = urllib.request.Request(url, data=corpo, headers={"Content-Type": "multipart/form-data; boundary=%s" % lim})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def enviar_texto(texto, chat=None):
    chat = chat or CHAT
    ids = []
    for p in partir_texto_telegram(texto):
        try:
            r = _pedir("sendMessage", {"chat_id": str(chat), "text": p, "disable_web_page_preview": "true"})
            ids.append(r["result"]["message_id"])
        except Exception as e:
            registar(evento="texto-falhou", erro=str(e)[:200])
    return ids


def enviar_voz(ogg, dur, chat=None):
    chat = chat or CHAT
    with open(ogg, "rb") as fh:
        dados = fh.read()
    return _pedir("sendVoice", {"chat_id": str(chat), "duration": str(int(round(dur)))}, ("voz.ogg", dados))["result"]["message_id"]


def _limpar_tmp():
    try:
        for f in os.listdir(TMP):
            p = os.path.join(TMP, f)
            if time.time() - os.path.getmtime(p) > 3 * 3600:
                os.remove(p)
    except Exception:
        pass


def audio_inteiro(texto, chat=None, origem="direto"):
    """O texto TODO em audio, por pedacos, por ordem, cada um conferido antes de ir. Devolve dict."""
    chat = chat or CHAT
    limpo = limpar(texto)
    if not limpo:
        registar(evento="sem-nada-para-ler", origem=origem)
        return {"ok": True, "partes": []}
    partes = partir(limpo)
    feitas, falhas = [], []
    for i, p in enumerate(partes, 1):
        try:
            r = gerar_pedaco(p, i, len(partes))
            mid = enviar_voz(r["ogg"], r["duracao"], chat)
            feitas.append({"parte": i, "letras": len(p), "duracao": round(r["duracao"], 1), "nivel": r["nivel"], "msg_id": mid})
            registar(evento="voz-enviada", origem=origem, parte=i, de=len(partes), letras=len(p), duracao=round(r["duracao"], 1),
                     nivel=r["nivel"], chat=str(chat), msg_id=mid)
        except Exception as e:
            falhas.append(i)
            registar(evento="voz-parte-falhou", origem=origem, parte=i, de=len(partes), erro=str(e)[:250])
            enviar_texto("(Não consegui gravar a parte %d de %d do áudio. O texto está completo acima. Motivo: %s)"
                         % (i, len(partes), str(e)[:160]), chat)
    _limpar_tmp()
    return {"ok": not falhas, "partes": feitas, "falhas": falhas}


# ─────────────────────────── fila e trabalhador ───────────────────────────

def _pendentes():
    try:
        return sorted(f for f in os.listdir(FILA) if f.endswith(".job"))
    except Exception:
        return []


def _acordar_trabalhador():
    try:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "--worker"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception as e:
        registar(evento="trabalhador-nao-arrancou", erro=str(e)[:120])


def pedir_audio(texto, chat=None, origem="fila"):
    chat = chat or CHAT
    os.makedirs(FILA, exist_ok=True)
    try:
        os.chmod(FILA, 0o777)
    except Exception:
        pass
    if len(_pendentes()) >= MAX_FILA:
        registar(evento="fila-cheia-audio-omitido", origem=origem, letras=len(texto))
        return False
    nome = "%013d-%s.job" % (int(time.time() * 1000), uuid.uuid4().hex[:6])
    with open(os.path.join(FILA, nome), "w", encoding="utf-8") as f:
        json.dump({"chat": str(chat), "texto": texto, "origem": origem}, f, ensure_ascii=False)
    registar(evento="audio-pedido", origem=origem, letras=len(texto), chat=str(chat))
    _acordar_trabalhador()
    return True


def trabalhador():
    os.makedirs(FILA, exist_ok=True)
    os.makedirs(FEITOS, exist_ok=True)
    trinco = open(os.path.join(FILA, ".trinco"), "w")
    try:
        fcntl.flock(trinco, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0                       # ja ha um trabalhador a tratar da fila
    feitos = 0
    while True:
        jobs = _pendentes()
        if not jobs:
            break
        for nome in jobs:
            p = os.path.join(FILA, nome)
            try:
                with open(p, encoding="utf-8") as f:
                    j = json.load(f)
                audio_inteiro(j.get("texto", ""), j.get("chat"), j.get("origem", "fila"))
            except Exception as e:
                registar(evento="job-falhou", job=nome, erro=str(e)[:200])
            finally:
                try:
                    os.replace(p, os.path.join(FEITOS, nome))
                except Exception:
                    pass
            feitos += 1
    try:
        for f in os.listdir(FEITOS):
            if time.time() - os.path.getmtime(os.path.join(FEITOS, f)) > 7 * 86400:
                os.remove(os.path.join(FEITOS, f))
    except Exception:
        pass
    return feitos


# ───────────────────────────── a porta ────────────────────────────

def falar(texto, chat=None, resumo=None, sincrono=True, so_audio=False):
    """TEXTO COMPLETO + AUDIO DO TEXTO INTEIRO. `resumo` e' ignorado (compatibilidade). Nunca levanta."""
    texto = (texto or "").strip()
    if not texto:
        return {"ok": False, "porque": "texto vazio"}
    chat = chat or CHAT
    if not CRED or not chat:
        registar(evento="sem-credenciais", tem_cred=bool(CRED), tem_chat=bool(chat))
        return {"ok": False, "porque": "falta o bot ou o canal do Telegram"}
    ids = [] if so_audio else enviar_texto(texto, chat)
    if not so_audio and not ids:
        return {"ok": False, "porque": "o texto nao chegou ao Telegram", "texto_enviado": False}
    if sincrono:
        r = audio_inteiro(texto, chat)
        registar(evento="enviado", chat=str(chat), chars=len(texto), ids_texto=ids, partes=len(r["partes"]), falhas=r["falhas"] if "falhas" in r else [])
        return {"ok": r["ok"], "ids_texto": ids, "partes": r["partes"], "texto_enviado": True}
    pedido = pedir_audio(texto, chat, origem="falar-async" if not so_audio else "so-audio")
    return {"ok": True, "ids_texto": ids, "audio_na_fila": pedido, "texto_enviado": not so_audio}


# ─────────────────── servidor de voz (para o agente do Hermes) ───────────────────
_TRINCO_SERVIDOR = threading.Lock()


def sintetizar_inteiro(texto):
    """Devolve (bytes_ogg, duracao) com o texto TODO num so audio (pedacos juntos por ordem)."""
    partes = partir(limpar(texto))
    if not partes:
        raise RuntimeError("nada para ler em voz alta")
    ficheiros, total = [], 0.0
    for i, p in enumerate(partes, 1):
        r = gerar_pedaco(p, i, len(partes))
        ficheiros.append(r["ogg"])
        total += r["duracao"]
    if len(ficheiros) == 1:
        saida = ficheiros[0]
    else:
        base = os.path.join(TMP, "j-" + uuid.uuid4().hex[:10])
        lista = base + ".lst"
        with open(lista, "w") as f:
            for x in ficheiros:
                f.write("file '%s'\n" % x)
        saida = base + ".ogg"
        c = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lista,
                            "-c", "copy", saida], capture_output=True, timeout=180)
        if c.returncode != 0 or not os.path.getsize(saida):
            raise RuntimeError("ffmpeg concat falhou: " + (c.stderr or b"")[:160].decode("utf-8", "replace"))
    registar(evento="sintetizado-para-o-agente", partes=len(partes), letras=len(texto), duracao=round(total, 1))
    with open(saida, "rb") as fh:
        return fh.read(), total


class _Servidor(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self.send_response(200 if self.path == "/saude" else 404)
        self.end_headers()
        self.wfile.write(b"ok" if self.path == "/saude" else b"")

    def do_POST(self):
        if self.path != "/sintetizar":
            self.send_response(404)
            self.end_headers()
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            texto = json.loads(self.rfile.read(n).decode("utf-8")).get("texto", "")
            with _TRINCO_SERVIDOR:
                dados, dur = sintetizar_inteiro(texto)
            self.send_response(200)
            self.send_header("Content-Type", "audio/ogg")
            self.send_header("X-Duracao", "%.1f" % dur)
            self.send_header("Content-Length", str(len(dados)))
            self.end_headers()
            self.wfile.write(dados)
        except Exception as e:
            registar(evento="servidor-falhou", erro=str(e)[:250])
            corpo = str(e)[:300].encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Length", str(len(corpo)))
            self.end_headers()
            self.wfile.write(corpo)


def servir(hosts):
    servidores = []
    for h in hosts:
        try:
            s = ThreadingHTTPServer((h, PORTA_SERVIDOR), _Servidor)
            servidores.append(s)
            threading.Thread(target=s.serve_forever, daemon=True).start()
            registar(evento="servidor-a-ouvir", host=h, porta=PORTA_SERVIDOR)
        except Exception as e:
            registar(evento="servidor-nao-abriu", host=h, erro=str(e)[:120])
    if not servidores:
        return 1
    while True:
        time.sleep(3600)


# ───────────────────────────────── main ─────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1
    if args[0] == "--teste":
        try:
            r = gerar_pedaco("Teste da voz do Bora. Se ouves isto, está tudo bem.")
            dg = "" if r["nivel"] == "edge-tts" else " DEGRADADO(o edge-tts nao serviu; ver voz.log.jsonl)"
            print("NIVEL=%s bytes=%d duracao=%.1f%s" % (r["nivel"], os.path.getsize(r["ogg"]), r["duracao"], dg))
            os.remove(r["ogg"])
            return 0
        except Exception as e:
            print("FALHOU: %s" % e)
            return 1
    if args[0] == "--worker":
        trabalhador()
        return 0
    if args[0] == "--servir":
        return servir(args[1:] or ["127.0.0.1"])
    chat, assinc, so_audio, ficheiro, resto = None, False, False, None, []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--chat" and i + 1 < len(args):
            chat = args[i + 1]; i += 2; continue
        if a == "--async":
            assinc = True; i += 1; continue
        if a == "--so-audio":
            so_audio = True; assinc = True; i += 1; continue
        if a == "-f" and i + 1 < len(args):
            ficheiro = args[i + 1]; i += 2; continue
        resto.append(a); i += 1
    if ficheiro:
        with open(ficheiro, encoding="utf-8") as fh:
            texto = fh.read()
    elif resto and resto[0] == "-":
        texto = sys.stdin.read()
    else:
        texto = " ".join(resto)
    r = falar(texto, chat=chat, sincrono=not assinc, so_audio=so_audio)
    print(json.dumps({k: v for k, v in r.items() if k != "ogg"}, ensure_ascii=False))
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
