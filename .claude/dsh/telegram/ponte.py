#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ponte Telegram <-> Dipsy (dsh). Codigo nosso, missao C-liga (30/10/2026). So biblioteca padrao do Python.

- Fala com a API oficial (api.telegram.org) por long polling. Nenhum servidor aberto, nenhuma porta de entrada.
- So o Danilo manda: chat id lido de ~/.bora/aviso.conf (TELEGRAM_CHAT_ID), so conversa privada. O resto e ignorado em silencio.
- Cada mensagem dele vira UM pedido ao dsh headless (perfil headless, com a guarda do Dipsy) e a resposta volta ao Telegram.
- Fotos dele: guardadas em ~/.dsh/capturas e entregues ao Dipsy para usar a ferramenta ver_imagem.
- Comandos: /ajuda  /estado  /parar (cancela o pedido atual)  /desligar (fecha esta ponte).
- Tudo o que sai para o Telegram passa por um redator que tapa chaves e segredos conhecidos.
- A credencial do bot vive em ~/.dsh/secrets/telegram-dipsy.token (so o utilizador le). Nunca e escrita em log nem em mensagem.

Uso:  python ponte.py            (corre a ponte)
      python ponte.py --teste "texto"   (corre um pedido ao dsh e mostra a resposta, sem Telegram)
"""
import json
import os
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
from datetime import datetime

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

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
        texto = redigir(texto).strip() or "(sem resposta)"
        pedacos = [texto[i:i + 3800] for i in range(0, len(texto), 3800)]
        for p in pedacos:
            try:
                self.chamar("sendMessage", chat_id=chat_id, text=p, disable_web_page_preview="true")
            except Exception as e:
                log(f"falhou o envio: {e}")
            time.sleep(0.4)

    def a_escrever(self, chat_id):
        try:
            self.chamar("sendChatAction", espera=10, chat_id=chat_id, action="typing")
        except Exception:
            pass

    def descarregar_foto(self, file_id, destino):
        info = self.chamar("getFile", file_id=file_id)
        caminho = info["result"]["file_path"]
        url = f"https://api.telegram.org/file/bot{self._cred}/{caminho}"
        with urllib.request.urlopen(url, timeout=60) as r, open(destino, "wb") as f:
            f.write(r.read(8 * 1024 * 1024))


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

    def ajuda(self):
        return ("Sou o Dipsy. Escreve-me o que queres, como falas com uma pessoa, e eu faço no PC. "
                "Podes mandar também uma foto (eu vejo-a).\n"
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

    def trabalhar(self, chat_id, pedido, resumo):
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
                    self.tg.enviar(chat_id, "Ainda estou a trabalhar nisto. Escreve /parar se quiseres cancelar.")

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
            self.tg.enviar(chat_id, f"Não consegui fazer isto: {motor}. Tenta outra vez daqui a pouco.")
            return
        rodape = "" if motor.startswith("kilo nemotron") else f"\n\n(motor de reserva: {motor})"
        self.tg.enviar(chat_id, texto + rodape)

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
            self.tg.enviar(self.autorizado, "Muitos pedidos numa hora; espera um bocado.")
            return
        self.recentes.append(agora)
        atraso = agora - m.get("date", agora)
        texto = (m.get("text") or m.get("caption") or "").strip()
        log(f"mensagem do Danilo ({len(texto)} letras, foto={bool(m.get('photo'))}, atraso {int(atraso)} s)")
        if atraso > 30 * 60:
            self.tg.enviar(self.autorizado, f"Recebi isto com {int(atraso / 60)} min de atraso (estava desligado). Se ainda interessa, repete.")
            return
        cmd = texto.split()[0].lower().split("@")[0] if texto.startswith("/") else ""
        if cmd in ("/start", "/ajuda", "/help"):
            self.tg.enviar(self.autorizado, self.ajuda())
            return
        if cmd == "/estado":
            self.tg.enviar(self.autorizado, self.estado())
            return
        if cmd == "/parar":
            self.tg.enviar(self.autorizado, self.parar())
            return
        if cmd == "/desligar":
            self.tg.enviar(self.autorizado, "Desligado. Para me voltares a ligar, abre o DIPSY no ambiente de trabalho do PC.")
            log("desligado a pedido do Danilo")
            os._exit(0)
        with self.trinco:
            ocupado = self.trabalho is not None
        if ocupado:
            self.tg.enviar(self.autorizado, "Ainda estou a trabalhar no pedido anterior. Escreve /parar para o cancelar.")
            return
        pedido = texto
        if m.get("photo"):
            try:
                os.makedirs(CAPTURAS, exist_ok=True)
                destino = os.path.join(CAPTURAS, f"tg-{m['message_id']}.jpg")
                self.tg.descarregar_foto(m["photo"][-1]["file_id"], destino)
                pedido = f"O Danilo enviou uma imagem, guardada em {destino}. Usa a ferramenta ver_imagem com esse caminho. " + (texto or "Descreve-a e diz o que é importante.")
            except Exception as e:
                self.tg.enviar(self.autorizado, f"Não consegui receber a foto ({e}).")
                return
        elif not texto:
            self.tg.enviar(self.autorizado, "Por enquanto só percebo texto e fotos.")
            return
        self.tg.enviar(self.autorizado, "Recebi. Estou a tratar disto.")
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
            self.tg.enviar(self.autorizado, "Dipsy ligado. Escreve-me o que queres (ou /ajuda).")
            with open(AVISADO, "w", encoding="utf-8") as f:
                f.write(datetime.now().isoformat())
        try:   # menu de botoes no Telegram: o Danilo toca, nao escreve
            self.tg.chamar("setMyCommands", commands=json.dumps([
                {"command": "estado", "description": "O que estou a fazer"},
                {"command": "parar", "description": "Cancelar o pedido atual"},
                {"command": "ajuda", "description": "O que sei fazer"},
                {"command": "desligar", "description": "Desligar o Dipsy"},
            ]))
        except Exception as e:
            log(f"nao consegui pôr o menu de comandos: {e}")
        log("ponte a correr")
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


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--teste":
        texto, motor = correr_dsh(PREFIXO + sys.argv[2], {"cancelado": False, "proc": None})
        print(redigir(texto or f"(sem resposta: {motor})"))
        print(f"[motor: {motor}]")
        return
    trava = uma_so_instancia()  # noqa: F841  (mantem a porta ocupada enquanto a ponte vive)
    if not os.path.exists(FICH_CRED_BOT):
        log("sem credencial do bot; a ponte nao arranca")
        print("Falta criar o bot (ainda nao existe).")
        sys.exit(2)
    Ponte().correr()


if __name__ == "__main__":
    main()
