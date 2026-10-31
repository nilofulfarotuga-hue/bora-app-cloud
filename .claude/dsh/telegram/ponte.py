#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ponte Telegram <-> Dipsy (dsh). Codigo nosso, missao C-liga / C5c-voz (30/10/2026). So biblioteca padrao do Python.

- Fala com a API oficial (api.telegram.org) por long polling. Nenhum servidor aberto, nenhuma porta de entrada.
- So o Danilo manda: chat id lido de ~/.bora/aviso.conf (TELEGRAM_CHAT_ID), so conversa privada. O resto e ignorado em silencio.
- Cada mensagem dele (texto, FOTO ou VOZ) vira UM pedido ao dsh headless (perfil headless, com a guarda do Dipsy).
- VOZ A ENTRAR: o audio e' transcrito em portugues (faster-whisper local; reserva Gemini) e a ponte responde "Ouvi: ..."
  antes de tratar o pedido, como se fosse texto escrito.
- REGRA DO DANILO: TUDO o que a ponte lhe manda chega SEMPRE em duas formas, texto completo E audio do texto inteiro.
  Um unico caminho de envio (Ponte.dizer): texto logo, e o audio por pedacos de ate 900 letras em frases inteiras, por
  ordem, com a duracao conferida antes de mandar (ver voz_dipsy.py). Nada sai por outro caminho.
- Comandos: /ajuda  /estado  /parar (cancela o pedido atual)  /desligar (fecha esta ponte).
- Tudo o que sai passa por um redator que tapa chaves e segredos conhecidos.
- A credencial do bot vive em ~/.dsh/secrets/telegram-dipsy.token (so o utilizador le). Nunca e escrita em log nem em mensagem.

Uso:  python ponte.py                      (corre a ponte)
      python ponte.py --teste "texto"      (corre um pedido ao dsh e mostra a resposta, sem Telegram)
      python ponte.py --provar-envio       (manda ao Danilo 3 mensagens, curta, media e de ~1200 letras, e resume o que chegou)
"""
import json
import os
import queue
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voz_dipsy as vz  # noqa: E402

HOME = os.path.expanduser("~")
DSH = os.path.join(HOME, ".dsh")
PASTA = os.path.join(DSH, "telegram")
FICH_CRED_BOT = os.path.join(DSH, "secrets", "telegram-dipsy.token")
LOG = os.path.join(PASTA, "ponte.log")
OFFSET = os.path.join(PASTA, "offset.txt")
AVISADO = os.path.join(PASTA, "ultimo-arranque.txt")
CAPTURAS = os.path.join(DSH, "capturas")
REPO = r"C:\BoraLocal\projetosflutter\bora_app"
CLAUDE_MD = os.path.join(HOME, ".claude", "CLAUDE.md")
DSH_AGENTS = os.path.join(DSH, "AGENTS.md")
NOME_VAR_KILO = "KILO_" + "ANON_" + "KEY"   # a credencial anonima publica da Kilo, lida de ~/.dsh/kilo-anonima.txt
PORTA_TRAVA = 47831
LIMITE_MINUTOS = 25
MAX_MENSAGENS_HORA = 40
MAX_AUDIO_SEGUNDOS = 300
NO_WINDOW = 0x08000000

TENTATIVAS = [
    ("kilo nemotron (padrao)", None),
    ("kilo-auto (reserva 1)", os.path.join(DSH, "reserva-kilo-auto.patch.yml")),
    ("gemini gratis (reserva 2)", os.path.join(DSH, "reserva-gemini.patch.yml")),
]

SEGREDOS = [
    re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{30,}"),             # credencial de bot do Telegram
    re.compile(r"\bsbp_[A-Za-z0-9_-]{16,}"),                    # credencial do Supabase
    re.compile(r"\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}"),  # JWT
    re.compile(r"\bAIza[0-9A-Za-z_-]{30,}"),                    # chave Google
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),                     # chaves tipo OpenAI
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}"),                # GitHub
    re.compile(r"\b[A-Fa-f0-9]{48,}\b"),                        # hex muito longo
    re.compile(r"(?i)(refresh_token|client_secret|api[_-]?key|password|palavra-passe)\s*[:=]\s*\S{12,}"),
]


def log(msg):
    try:
        os.makedirs(PASTA, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat(timespec='seconds')}] {msg}\n")
    except Exception:
        pass


def redigir(texto):
    for rx in SEGREDOS:
        texto = rx.sub("[segredo tapado]", texto)
    return texto


def ler_credencial():
    with open(FICH_CRED_BOT, encoding="utf-8") as f:
        return f.read().strip()


def chat_autorizado():
    try:
        with open(os.path.join(HOME, ".bora", "aviso.conf"), encoding="utf-8") as f:
            for linha in f:
                m = re.match(r"\s*TELEGRAM_CHAT_ID\s*=\s*\"?(\d+)\"?", linha)
                if m:
                    return int(m.group(1))
    except Exception:
        pass
    return 6731890157


# --------------------------------------------------------------------------- API do Telegram
class Telegram:
    def __init__(self, cred):
        self._cred = cred

    def _url(self, metodo):
        return f"https://api.telegram.org/bot{self._cred}/{metodo}"

    def chamar(self, metodo, espera=30, **params):
        dados = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
        req = urllib.request.Request(self._url(metodo), data=dados)
        try:
            with urllib.request.urlopen(req, timeout=espera) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{metodo}: HTTP {e.code}") from None
        except Exception as e:
            raise RuntimeError(f"{metodo}: {type(e).__name__}") from None

    def enviar(self, chat_id, texto):
        """Texto INTEIRO, em pedacos de ate 3800 letras cortados em quebras de linha ou espacos. Devolve os ids enviados."""
        texto = redigir(texto).strip() or "(sem resposta)"
        pedacos = []
        while texto:
            if len(texto) <= 3800:
                pedacos.append(texto)
                break
            corte = max(texto.rfind("\n", 0, 3800), texto.rfind(". ", 0, 3800) + 1, texto.rfind(" ", 0, 3800))
            if corte < 1500:
                corte = 3800
            pedacos.append(texto[:corte].rstrip())
            texto = texto[corte:].lstrip()
        ids = []
        for p in pedacos:
            try:
                r = self.chamar("sendMessage", chat_id=chat_id, text=p, disable_web_page_preview="true")
                ids.append(r["result"]["message_id"])
            except Exception as e:
                log(f"falhou o envio de texto: {e}")
            time.sleep(0.3)
        return ids

    def enviar_voz(self, chat_id, ogg, duracao):
        lim = "----dipsy" + uuid.uuid4().hex
        corpo = b""
        for k, v in (("chat_id", str(chat_id)), ("duration", str(int(round(duracao))))):
            corpo += f'--{lim}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode("utf-8")
        with open(ogg, "rb") as f:
            dados = f.read()
        corpo += (f'--{lim}\r\nContent-Disposition: form-data; name="voice"; filename="voz.ogg"\r\n'
                  f"Content-Type: audio/ogg\r\n\r\n").encode("utf-8") + dados + b"\r\n"
        corpo += f"--{lim}--\r\n".encode("utf-8")
        req = urllib.request.Request(self._url("sendVoice"), data=corpo,
                                     headers={"Content-Type": f"multipart/form-data; boundary={lim}"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                resp = json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"sendVoice: HTTP {e.code}") from None
        except Exception as e:
            raise RuntimeError(f"sendVoice: {type(e).__name__}") from None
        return resp["result"]

    def a_escrever(self, chat_id, acao="typing"):
        try:
            self.chamar("sendChatAction", espera=10, chat_id=chat_id, action=acao)
        except Exception:
            pass

    def descarregar(self, file_id, destino, max_bytes=20 * 1024 * 1024):
        info = self.chamar("getFile", file_id=file_id)
        caminho = info["result"]["file_path"]
        url = f"https://api.telegram.org/file/bot{self._cred}/{caminho}"
        with urllib.request.urlopen(url, timeout=90) as r, open(destino, "wb") as f:
            f.write(r.read(max_bytes))


# --------------------------------------------------------------------------- pedidos ao dsh
def curar_agents_md():
    """O AGENTS.md do dsh tem de ser o MESMO ficheiro que o CLAUDE.md global (hardlink); alguns editores partem-no."""
    try:
        if os.stat(CLAUDE_MD).st_nlink < 2:
            if os.path.exists(DSH_AGENTS):
                os.remove(DSH_AGENTS)
            os.link(CLAUDE_MD, DSH_AGENTS)
            log("AGENTS.md do dsh voltou a ser hardlink do CLAUDE.md")
    except Exception as e:
        log(f"nao consegui curar o AGENTS.md: {type(e).__name__}")


def ambiente():
    env = dict(os.environ)
    try:
        with open(os.path.join(DSH, "kilo-anonima.txt"), encoding="utf-8") as f:
            env[NOME_VAR_KILO] = f.read().strip()
    except Exception:
        pass
    return env


def matar(proc):
    try:
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, creationflags=NO_WINDOW, timeout=20)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def correr_dsh(pedido, estado):
    """Corre UM pedido no dsh headless (com reservas). Devolve (texto, motor) ou (None, motivo)."""
    curar_agents_md()
    dsh = shutil.which("dsh") or os.path.join(os.environ.get("APPDATA", ""), "npm", "dsh.cmd")
    ultimo_erro = "nenhum motor respondeu"
    for nome, patch in TENTATIVAS:
        if estado.get("cancelado"):
            return None, "cancelado"
        args = [dsh, "--profile", "headless"]
        if patch:
            args += ["--patch", patch]
        args += ["--json", "-"]
        try:
            proc = subprocess.Popen(
                args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                cwd=REPO, env=ambiente(), creationflags=NO_WINDOW,
            )
        except Exception as e:
            ultimo_erro = f"nao consegui arrancar o dsh ({type(e).__name__})"
            continue
        estado["proc"] = proc
        try:
            proc.stdin.write(pedido.encode("utf-8"))
            proc.stdin.close()
        except Exception:
            pass
        final = None
        textos = []
        limite = time.time() + LIMITE_MINUTOS * 60

        def vigia():
            while proc.poll() is None:
                if time.time() > limite:
                    estado["excedeu"] = True
                    matar(proc)
                    return
                time.sleep(2)

        threading.Thread(target=vigia, daemon=True).start()
        for linha in proc.stdout:
            try:
                ev = json.loads(linha.decode("utf-8", "replace"))
            except Exception:
                continue
            if ev.get("type") == "final":
                final = ev.get("text")
            elif ev.get("type") == "text" and ev.get("text"):
                textos.append(ev["text"])
        proc.wait()
        estado["proc"] = None
        if estado.get("excedeu"):
            return None, f"passou o limite de {LIMITE_MINUTOS} minutos"
        if estado.get("cancelado"):
            return None, "cancelado"
        resposta = final or ("\n".join(textos) if textos else None)
        if proc.returncode == 0 and resposta:
            return resposta, nome
        ultimo_erro = f"{nome} falhou (codigo {proc.returncode})"
        log(ultimo_erro)
    return None, ultimo_erro


AGENDA = os.path.join(DSH, "agenda", "agenda.json")


def ler_agenda():
    try:
        with open(AGENDA, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"tarefas": []}


def gravar_agenda(d):
    os.makedirs(os.path.dirname(AGENDA), exist_ok=True)
    tmp = AGENDA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(tmp, AGENDA)


PREFIXO = (
    "Pedido do Danilo pelo Telegram. Ele ouve a resposta em voz alta: responde em português simples, curto, "
    "em texto corrido, sem tabelas nem jargão. Se uma guarda barrar algo, diz-lho numa frase e segue com o resto. "
    "Pasta de trabalho: C:\\BoraLocal\\projetosflutter\\bora_app.\n\nPedido: "
)


# --------------------------------------------------------------------------- a ponte
class Ponte:
    def __init__(self):
        self.tg = Telegram(ler_credencial())
        self.autorizado = chat_autorizado()
        self.trabalho = None            # {"inicio": t, "resumo": str, "estado": dict}
        self.trinco = threading.Lock()
        self.recentes = []              # instantes das mensagens aceites (limite por hora)
        self.ignoradas = 0
        self.inicio = time.time()
        self.fila_audio = queue.Queue()
        self.resultados_envio = []      # so para --provar-envio: (letras, ids de texto, partes de voz)
        threading.Thread(target=self._trabalhador_audio, daemon=True).start()

    # ---- O UNICO CAMINHO DE ENVIO: texto completo logo + audio do texto inteiro, por pedacos, por ordem ----
    def dizer(self, chat_id, texto, falado=None):
        """TODA a mensagem para o Danilo passa por aqui. `falado` so serve para tirar do audio o que nao se le (rodapes)."""
        texto = (texto or "").strip()
        if not texto:
            return
        ids = self.tg.enviar(chat_id, texto)
        item = {"chat": chat_id, "falado": redigir(falado if falado is not None else texto), "ids_texto": ids, "partes": [],
                "feito": threading.Event()}
        self.fila_audio.put(item)
        self.resultados_envio.append(item)
        return item

    def _trabalhador_audio(self):
        while True:
            item = self.fila_audio.get()
            try:
                limpo = vz.limpar_para_voz(item["falado"])
                if not limpo:
                    log("sem nada para ler em voz alta nesta mensagem")
                    continue
                partes = vz.partir(limpo)
                for i, p in enumerate(partes, 1):
                    self.tg.a_escrever(item["chat"], "record_voice")
                    try:
                        r = vz.gerar_pedaco(p, i, len(partes))
                        mid = self.tg.enviar_voz(item["chat"], r["ogg"], r["duracao"])["message_id"]
                        item["partes"].append({"parte": i, "de": len(partes), "letras": len(p), "duracao": round(r["duracao"], 1),
                                               "motor": r["motor"], "tentativas": r["tentativas"], "msg_id": mid})
                        vz.registar(evento="voz-enviada", parte=i, de=len(partes), letras=len(p), duracao=round(r["duracao"], 1),
                                    motor=r["motor"], msg_id=mid)
                        log(f"voz enviada: parte {i}/{len(partes)}, {len(p)} letras, {r['duracao']:.1f} s ({r['motor']})")
                    except Exception as e:
                        vz.registar(evento="voz-parte-falhou", parte=i, de=len(partes), erro=str(e)[:200])
                        log(f"voz: parte {i}/{len(partes)} falhou: {str(e)[:120]}")
                        self.tg.enviar(item["chat"], f"(Não consegui gravar a parte {i} de {len(partes)} do áudio. O texto está completo acima.)")
                vz.limpar_tmp()
            except Exception as e:
                log(f"trabalhador de audio: {type(e).__name__}: {str(e)[:120]}")
            finally:
                item["feito"].set()
                self.fila_audio.task_done()

    # ---- comandos ----
    def ajuda(self):
        return ("Sou o Dipsy. Escreve-me o que queres, ou manda um áudio, como falas com uma pessoa, e eu faço no PC. "
                "Podes mandar também uma foto, e eu vejo-a. Respondo sempre em texto e em áudio, com tudo por inteiro.\n"
                "/estado diz o que estou a fazer. /parar cancela o que estou a fazer. "
                "/desligar fecha esta ligação ao Telegram (volta a ligar com o DIPSY no ambiente de trabalho).")

    def estado(self):
        with self.trinco:
            t = self.trabalho
        if t:
            mins = int((time.time() - t["inicio"]) / 60)
            return f"Estou a trabalhar há {mins} min em: {t['resumo']}"
        return f"Livre, à espera do teu pedido. Ligado há {int((time.time() - self.inicio) / 60)} min."

    def parar(self):
        with self.trinco:
            t = self.trabalho
        if not t:
            return "Não estou a fazer nada neste momento."
        t["estado"]["cancelado"] = True
        p = t["estado"].get("proc")
        if p:
            matar(p)
        return "Parei o pedido."

    # ---- tarefas em horario marcado (o dsh escreve em ~/.dsh/agenda/agenda.json; a ponte executa) ----
    def texto_agenda(self):
        ts = ler_agenda().get("tarefas", [])
        if not ts:
            return "Não há tarefas agendadas."
        linhas = []
        for t in ts:
            quando = (f"{t.get('data')} às {t['hora']}" if t["repetir"] == "uma_vez"
                      else f"{'dias úteis' if t['repetir'] == 'dias_uteis' else 'todos os dias'} às {t['hora']}")
            linhas.append(f"{t['id']}: {quando}: {t['pedido'][:110]}")
        return "Tarefas agendadas:\n" + "\n".join(linhas) + "\nPara cancelar uma, pede-me por escrito ou em áudio."

    def _agenda_loop(self):
        while True:
            time.sleep(20)
            try:
                self._agenda_tick()
            except Exception as e:
                log(f"agenda: {type(e).__name__}: {str(e)[:100]}")

    def _agenda_tick(self):
        d = ler_agenda()
        if not d.get("tarefas"):
            return
        agora = datetime.now()
        hoje, hm = agora.strftime("%Y-%m-%d"), agora.strftime("%H:%M")
        for t in list(d["tarefas"]):
            devido = perdida = False
            if t["repetir"] == "uma_vez":
                if (t.get("data") or hoje) < hoje:
                    perdida = True
                elif (t.get("data") or hoje) == hoje and t["hora"] <= hm:
                    devido = True
            else:
                if t["repetir"] == "dias_uteis" and agora.weekday() >= 5:
                    continue
                if (t.get("ultima_execucao") or "")[:10] == hoje:
                    continue
                devido = t["hora"] <= hm
            if perdida:
                d["tarefas"].remove(t)
                gravar_agenda(d)
                self.dizer(self.autorizado, f"A tarefa agendada {t['id']} para {t.get('data')} às {t['hora']} não correu, porque o PC estava desligado. Era: {t['pedido'][:150]}")
                continue
            if not devido:
                continue
            atraso = (agora.hour * 60 + agora.minute) - (int(t["hora"][:2]) * 60 + int(t["hora"][3:5]))
            if atraso > 180 and t["repetir"] != "uma_vez":       # PC ligado tarde demais: salta-se hoje
                t["ultima_execucao"] = f"{hoje} {hm}"
                gravar_agenda(d)
                log(f"agenda: {t['id']} saltada hoje (atraso de {atraso} min)")
                continue
            with self.trinco:
                ocupado = self.trabalho is not None
            if ocupado:
                return                                           # tenta no ciclo seguinte
            t["ultima_execucao"] = f"{hoje} {hm}"
            if t["repetir"] == "uma_vez":
                d["tarefas"].remove(t)
            gravar_agenda(d)
            titulo = f"Tarefa agendada das {t['hora']}" + (" (atrasada)" if atraso > 5 else "")
            log(f"agenda: a correr {t['id']} ({titulo})")
            pedido = ("Tarefa agendada pelo Danilo, a correr sozinha à hora marcada (ele não está a escrever agora). "
                      "Responde em português simples e curto, texto corrido, sem tabelas.\n\nPedido: " + t["pedido"])
            threading.Thread(target=self.trabalhar, args=(self.autorizado, pedido, t["pedido"][:70], titulo), daemon=True).start()
            return

    def trabalhar(self, chat_id, pedido, resumo, titulo=None):
        estado = {"cancelado": False, "proc": None}
        with self.trinco:
            self.trabalho = {"inicio": time.time(), "resumo": resumo, "estado": estado}
        parar_aviso = threading.Event()

        def avisos():
            n = 0
            while not parar_aviso.wait(4.5):
                self.tg.a_escrever(chat_id)
                n += 1
                if n in (40, 40 + 66, 40 + 132, 40 + 198):          # ~3 min e depois de 5 em 5
                    self.dizer(chat_id, "Ainda estou a trabalhar nisto. Escreve /parar se quiseres cancelar.")

        threading.Thread(target=avisos, daemon=True).start()
        try:
            texto, motor = correr_dsh(pedido, estado)
        finally:
            parar_aviso.set()
            with self.trinco:
                self.trabalho = None
        if estado["cancelado"]:
            return
        if texto is None:
            self.dizer(chat_id, f"Não consegui fazer isto: {motor}. Tenta outra vez daqui a pouco.")
            return
        rodape = "" if motor.startswith("kilo nemotron") else f"\n\n(motor de reserva: {motor})"
        cabeca = f"{titulo}.\n\n" if titulo else ""
        self.dizer(chat_id, cabeca + texto + rodape, falado=cabeca + texto)

    def _ouvir(self, m):
        """Descarrega e transcreve uma mensagem de voz. Devolve o texto ou levanta."""
        v = m.get("voice") or m.get("audio")
        if (v.get("duration") or 0) > MAX_AUDIO_SEGUNDOS:
            raise RuntimeError(f"áudio com mais de {MAX_AUDIO_SEGUNDOS // 60} minutos")
        os.makedirs(CAPTURAS, exist_ok=True)
        destino = os.path.join(CAPTURAS, f"tg-voz-{m['message_id']}.ogg")
        self.tg.descarregar(v["file_id"], destino)
        saida = subprocess.run([sys.executable if not sys.executable.lower().endswith("pythonw.exe") else "python",
                                os.path.join(PASTA, "voz_dipsy.py"), "--transcrever", destino],
                               capture_output=True, timeout=300, creationflags=NO_WINDOW)
        try:
            j = json.loads((saida.stdout or b"").decode("utf-8", "replace").strip().splitlines()[-1])
        except Exception:
            raise RuntimeError("não percebi o áudio (a transcrição falhou)") from None
        log(f"transcrito ({j.get('motor')}): {len(j.get('texto', ''))} letras de um áudio de {v.get('duration')} s")
        return j["texto"], j.get("motor", "")

    def _tratar_voz(self, m):
        chat = self.autorizado
        try:
            self.tg.a_escrever(chat, "record_voice")
            texto, motor = self._ouvir(m)
        except Exception as e:
            self.dizer(chat, f"Não consegui perceber o teu áudio: {e}. Tenta outra vez, ou escreve.")
            return
        if not texto.strip():
            self.dizer(chat, "Não ouvi nada no áudio. Tenta outra vez.")
            return
        self.dizer(chat, f"Ouvi: {texto}")
        self.trabalhar(chat, PREFIXO + texto, texto[:70])

    def tratar(self, u):
        m = u.get("message")
        if not m:
            return
        chat = m.get("chat", {})
        de = m.get("from", {})
        if chat.get("id") != self.autorizado or de.get("id") != self.autorizado or chat.get("type") != "private":
            self.ignoradas += 1
            log(f"mensagem de alguem nao autorizado (ignorada; total {self.ignoradas})")
            return
        agora = time.time()
        self.recentes = [t for t in self.recentes if agora - t < 3600]
        if len(self.recentes) >= MAX_MENSAGENS_HORA:
            self.dizer(self.autorizado, "Muitos pedidos numa hora; espera um bocado.")
            return
        self.recentes.append(agora)
        atraso = agora - m.get("date", agora)
        texto = (m.get("text") or m.get("caption") or "").strip()
        eh_voz = bool(m.get("voice") or m.get("audio"))
        log(f"mensagem do Danilo ({len(texto)} letras, foto={bool(m.get('photo'))}, voz={eh_voz}, atraso {int(atraso)} s)")
        if atraso > 30 * 60:
            self.dizer(self.autorizado, f"Recebi isto com {int(atraso / 60)} min de atraso (estava desligado). Se ainda interessa, repete.")
            return
        cmd = texto.split()[0].lower().split("@")[0] if texto.startswith("/") else ""
        if cmd in ("/start", "/ajuda", "/help"):
            self.dizer(self.autorizado, self.ajuda())
            return
        if cmd == "/estado":
            self.dizer(self.autorizado, self.estado())
            return
        if cmd == "/agenda":
            self.dizer(self.autorizado, self.texto_agenda())
            return
        if cmd == "/parar":
            self.dizer(self.autorizado, self.parar())
            return
        if cmd == "/desligar":
            item = self.dizer(self.autorizado, "Desligado. Para me voltares a ligar, abre o DIPSY no ambiente de trabalho do PC.")
            if item:
                item["feito"].wait(timeout=90)
            log("desligado a pedido do Danilo")
            os._exit(0)
        with self.trinco:
            ocupado = self.trabalho is not None
        if ocupado:
            self.dizer(self.autorizado, "Ainda estou a trabalhar no pedido anterior. Escreve /parar para o cancelar.")
            return
        if eh_voz:      # a transcricao demora: trata-se noutra linha para o polling continuar
            threading.Thread(target=self._tratar_voz, args=(m,), daemon=True).start()
            return
        pedido = texto
        if m.get("photo"):
            try:
                os.makedirs(CAPTURAS, exist_ok=True)
                destino = os.path.join(CAPTURAS, f"tg-{m['message_id']}.jpg")
                self.tg.descarregar(m["photo"][-1]["file_id"], destino)
                pedido = f"O Danilo enviou uma imagem, guardada em {destino}. Usa a ferramenta ver_imagem com esse caminho. " + (texto or "Descreve-a e diz o que é importante.")
            except Exception as e:
                self.dizer(self.autorizado, f"Não consegui receber a foto ({e}).")
                return
        elif not texto:
            self.dizer(self.autorizado, "Por enquanto percebo texto, fotos e áudios de voz.")
            return
        self.dizer(self.autorizado, "Recebi. Estou a tratar disto.")
        resumo = (texto or "(foto)")[:70]
        threading.Thread(target=self.trabalhar, args=(self.autorizado, PREFIXO + pedido, resumo), daemon=True).start()

    def correr(self):
        offset = 0
        try:
            with open(OFFSET, encoding="utf-8") as f:
                offset = int(f.read().strip() or 0)
        except Exception:
            pass
        try:
            ultimo = os.path.getmtime(AVISADO)
        except Exception:
            ultimo = 0
        if time.time() - ultimo > 600:
            self.dizer(self.autorizado, "Dipsy ligado. Já ouço os teus áudios e respondo sempre em texto e em áudio. Escreve-me ou manda um áudio.")
            with open(AVISADO, "w", encoding="utf-8") as f:
                f.write(datetime.now().isoformat())
        try:   # menu de botoes no Telegram: o Danilo toca, nao escreve
            self.tg.chamar("setMyCommands", commands=json.dumps([
                {"command": "estado", "description": "O que estou a fazer"},
                {"command": "agenda", "description": "As tarefas marcadas para uma hora"},
                {"command": "parar", "description": "Cancelar o pedido atual"},
                {"command": "ajuda", "description": "O que sei fazer"},
                {"command": "desligar", "description": "Desligar o Dipsy"},
            ]))
        except Exception as e:
            log(f"nao consegui pôr o menu de comandos: {e}")
        threading.Thread(target=self._agenda_loop, daemon=True).start()
        log("ponte a correr (com agenda)")
        falhas = 0
        while True:
            try:
                r = self.tg.chamar("getUpdates", espera=65, offset=offset, timeout=50, allowed_updates=json.dumps(["message"]))
            except Exception as e:
                falhas += 1
                log(f"getUpdates falhou ({e}); falha {falhas}")
                time.sleep(min(60, 3 * falhas))
                continue
            falhas = 0
            for u in r.get("result", []):
                offset = u["update_id"] + 1
                try:
                    with open(OFFSET, "w", encoding="utf-8") as f:
                        f.write(str(offset))
                    self.tratar(u)
                except Exception as e:
                    log(f"erro a tratar uma mensagem: {type(e).__name__}")


def uma_so_instancia():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", PORTA_TRAVA))
        s.listen(1)
    except OSError:
        print("A ponte do Telegram já está a correr.")
        sys.exit(0)
    return s


TEXTO_CURTO = "Teste de voz do Dipsy: mensagem curta. Se estás a ouvir isto por inteiro, está tudo bem."
TEXTO_MEDIO = ("Teste de voz do Dipsy, mensagem de tamanho médio. O Dipsy responde sempre em texto e em áudio, com o texto "
               "inteiro, sem cortar nada. Quando a resposta é comprida, o áudio vem em várias partes, por ordem, cada uma "
               "com frases inteiras. Antes de enviar cada parte, o Dipsy confere se a duração do áudio bate com o tamanho do texto.")
TEXTO_LONGO = ("Teste de voz do Dipsy, mensagem comprida. O Bora é o aplicativo de entregas da Guarda. O cliente escolhe o "
               "restaurante, paga pelo telemóvel e acompanha o estafeta no mapa. Cada pedido passa por vários passos antes "
               "de chegar a casa: o restaurante aceita, prepara, o sistema chama um estafeta, o estafeta recolhe e entrega "
               "com um código de confirmação. Se alguma coisa falhar, o suporte responde em poucos minutos. Os parceiros têm "
               "um painel próprio para ver os pedidos, mudar os preços dos produtos e acompanhar os ganhos da semana. Os "
               "estafetas veem as ofertas no telemóvel, aceitam com um toque e recebem ao fim de cada semana. O painel de "
               "administração mostra tudo em tempo real: pedidos, estafetas online, pagamentos e reclamações. Tudo isto "
               "funciona sem papel e sem telefonemas, para que a equipa pequena consiga atender muita gente ao mesmo tempo, "
               "mesmo nas horas de maior movimento ao almoço e ao jantar. Quando o dia acaba, o sistema fecha as contas, "
               "confere cada pagamento e prepara o relatório da manhã seguinte, para que o Danilo possa ouvir o resumo antes "
               "de sair de casa. Fim da mensagem comprida: se ouviste esta frase, o áudio chegou inteiro.")


def provar_envio():
    p = Ponte()
    itens = []
    for nome, t in (("curta", TEXTO_CURTO), ("média", TEXTO_MEDIO), ("1.200 letras", TEXTO_LONGO)):
        itens.append((nome, len(t), p.dizer(p.autorizado, t)))
    for _, _, it in itens:
        it["feito"].wait(timeout=600)
    for nome, n, it in itens:
        letras_audio = sum(x["letras"] for x in it["partes"])
        dur = sum(x["duracao"] for x in it["partes"])
        print(f"{nome}: texto {n} letras (mensagens de texto: {it['ids_texto']}); áudio em {len(it['partes'])} parte(s), "
              f"{letras_audio} letras lidas, {dur:.1f} s no total, minimo exigido {2.0 * letras_audio / 100:.1f} s; "
              f"partes: {[(x['letras'], x['duracao'], x['motor'], x['msg_id']) for x in it['partes']]}")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--teste":
        texto, motor = correr_dsh(PREFIXO + sys.argv[2], {"cancelado": False, "proc": None})
        print(redigir(texto or f"(sem resposta: {motor})"))
        print(f"[motor: {motor}]")
        return
    if len(sys.argv) >= 2 and sys.argv[1] == "--provar-envio":
        provar_envio()
        return
    trava = uma_so_instancia()  # noqa: F841  (mantem a porta ocupada enquanto a ponte vive)
    if not os.path.exists(FICH_CRED_BOT):
        log("sem credencial do bot; a ponte nao arranca")
        print("Falta criar o bot (ainda nao existe).")
        sys.exit(2)
    Ponte().correr()


if __name__ == "__main__":
    main()
