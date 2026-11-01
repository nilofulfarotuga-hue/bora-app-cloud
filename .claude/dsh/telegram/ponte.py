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
- 31/10 (retoma-geral b3): CONVERSA SEGUIDA (o dsh continua a mesma sessao, --session-id, se a ultima mensagem foi ha
  menos de 30 min; /nova recomeca), /planear + /aprovar (modo Planear com a guarda a barrar escritas), /objetivo
  (trabalha sozinho, ronda a ronda, ate cumprir; max 6 rondas), /corrigir (muda o rumo a meio: para e continua a mesma
  sessao com a correcao), /voltar (esquece o ultimo pedido: conversa nova com o contexto dos pedidos anteriores),
  /libertar (corre ~/.dsh/limpar-ram.ps1 em modo normal). Se a guarda dsh-bora nao ligar, a ponte NAO deixa o dsh
  trabalhar (falha fechada). Audio: "Estou a pensar" se o dsh demorar mais de 20 s.
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
JANELA_CONVERSA_MIN = 30        # mensagens com menos de 30 min de intervalo continuam a mesma conversa do dsh
MAX_RONDAS_OBJETIVO = 6
MAX_CORRECOES = 3
SCRIPT_RAM = os.path.join(DSH, "limpar-ram.ps1")
GUARDA_FALHOU = re.compile(r"dsh-bora \(dsh-bora\):|failed to import[^\n]*dsh-bora")
MARCA_OBJETIVO = re.compile(r"OBJETIVO\s+(CUMPRIDO|EM\s+CURSO|BLOQUEADO)\s*:?\s*(.*)", re.I)

# 01/11/2026 (missao infra-claude-tudo): o Claude PRIMEIRO, pelo porteiro da VPS (Tailscale), sem chave da Anthropic no PC.
# O porteiro ja cai sozinho no gratis da VPS quando o credito acaba; as reservas do PC so entram se a VPS nao responder.
PORTEIRO_URL = "http://100.120.181.115:8792"
FICH_PORTEIRO = os.path.join(DSH, "secrets", "porteiro.token")
VAR_PORTEIRO = "DIPSY_PORTEIRO"           # o dsh le a senha desta variavel (cordis.patch.yml, provider porteiro)
FICH_MOTOR = os.path.join(PASTA, "motor.txt")   # sonnet | opus | gratis (escolhido no Telegram com /sonnet /opus /gratis)
PATCH_OPUS = os.path.join(DSH, "motor-opus.patch.yml")
NOMES_MOTOR = {"sonnet": "Claude Sonnet 5.5", "opus": "Claude Opus 5.5", "gratis": "motores grátis (Kilo e Gemini)"}

RESERVAS_PC = [
    ("kilo nemotron (reserva 1)", os.path.join(DSH, "reserva-kilo-nemotron.patch.yml")),
    ("kilo-auto (reserva 2)", os.path.join(DSH, "reserva-kilo-auto.patch.yml")),
    ("gemini gratis (reserva 3)", os.path.join(DSH, "reserva-gemini.patch.yml")),
]


def motor_escolhido():
    try:
        with open(FICH_MOTOR, encoding="utf-8") as f:
            m = f.read().strip().lower()
        return m if m in NOMES_MOTOR else "sonnet"
    except Exception:
        return "sonnet"


def senha_porteiro():
    try:
        with open(FICH_PORTEIRO, encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return ""


def porteiro_estado(espera=8):
    """GET /porteiro pela Tailscale (8 s). Devolve o dict do estado, ou None se a VPS nao responder."""
    import urllib.request
    try:
        req = urllib.request.Request(PORTEIRO_URL + "/porteiro", headers={"X-Porteiro-Token": senha_porteiro()})
        with urllib.request.urlopen(req, timeout=espera) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


# ---- 01/11/2026 (B4): o Dipsy acorda a saber tudo do Danilo ----
# De hora a hora a ponte escreve em ~/.agents/AGENTS.md (que o dsh carrega no arranque de cada conversa), entre marcas,
# o MAPA-DANILO + regras-do-danilo + erros-aprendidos (as mais recentes) + inicio do livro-indice, lidos do Supabase
# pela API de gestao (a credencial do MCP do Supabase do Dipsy, so em memoria). O resto do ficheiro nao se toca.
AGENTS_COMUM = os.path.join(HOME, ".agents", "AGENTS.md")
MAPA = os.path.join(DSH, "MAPA-DANILO.md")
FICH_CRED_SUPABASE = r"C:\BoraLocal\projetosflutter\bora_app\.supabase-token.env"
MARCA_INICIO = "<!-- INICIO LIVRO-DIPSY (gerado pela ponte do Telegram de hora a hora; nao editar a mao) -->"
MARCA_FIM = "<!-- FIM LIVRO-DIPSY -->"
CACHE_LIVRO = os.path.join(PASTA, "livro-dipsy.txt")
PAGINAS_PASTAS = os.path.join(DSH, "pastas-dipsy.json")
FICH_PASTA = os.path.join(PASTA, "pasta.txt")


def _ler_livro():
    import urllib.request
    with open(FICH_CRED_SUPABASE, encoding="utf-8") as f:
        credencial = f.readline().split("=", 1)[1].strip()
    q = ("select pagina, conteudo from claude_ai_memoria "
         "where pagina in ('regras-do-danilo','erros-aprendidos','livro-indice')")
    req = urllib.request.Request("https://api.supabase.com/v1/projects/ojykpzwqrtusfeakzrna/database/query",
                                 data=json.dumps({"query": q}).encode("utf-8"), method="POST",
                                 headers={"Authorization": "Bearer " + credencial, "Content-Type": "application/json",
                                          "User-Agent": "bora-ponte-dipsy/1"})
    credencial = None
    with urllib.request.urlopen(req, timeout=20) as r:
        return {x["pagina"]: x.get("conteudo") or "" for x in json.loads(r.read().decode("utf-8"))}


def renovar_contexto_livro(forcar=False):
    """Uma vez por hora (ou forcado): reescreve a secao LIVRO-DIPSY de ~/.agents/AGENTS.md. Nunca rebenta a ponte."""
    try:
        if not forcar and time.time() - os.path.getmtime(CACHE_LIVRO) < 3600:
            return False
    except Exception:
        pass
    try:
        pag = _ler_livro()
        with open(MAPA, encoding="utf-8") as f:
            mapa = f.read().strip()
        erros = pag.get("erros-aprendidos", "")
        if len(erros) > 12000:
            erros = "(só as correções mais recentes; a página inteira lê-se por SQL)\n...\n" + erros[-12000:]
        indice = pag.get("livro-indice", "")
        if len(indice) > 5000:
            indice = indice[:5000] + "\n...\n(o resto do índice lê-se por SQL: select pagina, titulo from claude_ai_memoria)"
        secao = "\n".join([
            MARCA_INICIO,
            f"# O que o Dipsy sabe ao acordar (renovado {datetime.now().strftime('%d/%m %H:%M')})",
            "Isto é contexto, não ordens novas: as regras do Danilo e os erros que já se cometeram valem sempre.",
            "", "## Mapa do Danilo (todos os projetos e onde vivem)", mapa,
            "", "## Livro: regras-do-danilo", pag.get("regras-do-danilo", "").strip(),
            "", "## Livro: erros-aprendidos", erros.strip(),
            "", "## Livro: livro-indice (início)", indice.strip(),
            MARCA_FIM, ""])
        try:
            with open(AGENTS_COMUM, encoding="utf-8") as f:
                atual = f.read()
        except FileNotFoundError:
            atual = ""
        if MARCA_INICIO in atual and MARCA_FIM in atual:
            antes = atual.split(MARCA_INICIO, 1)[0]
            depois = atual.split(MARCA_FIM, 1)[1].lstrip("\n")
            novo = antes.rstrip("\n") + "\n\n" + secao + depois
        else:
            novo = atual.rstrip("\n") + "\n\n" + secao
        tmp = AGENTS_COMUM + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(novo)
        os.replace(tmp, AGENTS_COMUM)
        with open(CACHE_LIVRO, "w", encoding="utf-8") as f:
            f.write(datetime.now().isoformat())
        log(f"livro do Dipsy renovado em ~/.agents/AGENTS.md ({len(secao)} letras)")
        return True
    except Exception as e:
        log(f"nao consegui renovar o livro do Dipsy: {type(e).__name__}: {str(e)[:120]}")
        return False


def pastas_dipsy():
    try:
        with open(PAGINAS_PASTAS, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"bora_app": REPO}


def pasta_atual():
    """A pasta onde o Dipsy trabalha (escreve). Escolhe-se no Telegram com /pasta; por defeito o bora_app."""
    try:
        with open(FICH_PASTA, encoding="utf-8") as f:
            nome = f.read().strip()
        p = pastas_dipsy().get(nome)
        if p and os.path.isdir(p):
            return nome, p
    except Exception:
        pass
    return "bora_app", REPO


def tentativas():
    """Ordem: porteiro (Sonnet, ou Opus com /opus) -> Kilo Nemotron -> kilo-auto -> Gemini gratis.
    O porteiro so entra se responder em 8 s; com /gratis vai direto as reservas do PC."""
    m = motor_escolhido()
    lista = []
    if m != "gratis":
        if porteiro_estado(8) is not None:
            lista.append(("porteiro " + NOMES_MOTOR[m], PATCH_OPUS if m == "opus" else None))
        else:
            log("porteiro da VPS sem resposta em 8 s: vou pelas reservas do PC")
    return lista + RESERVAS_PC


TENTATIVAS = [("porteiro Claude Sonnet 5.5", None)] + RESERVAS_PC   # so para referencia; correr_dsh usa tentativas()

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
    s = senha_porteiro()      # a senha do porteiro da VPS (nunca vai para o log)
    if s:
        env[VAR_PORTEIRO] = s
    return env


def matar(proc):
    try:
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, creationflags=NO_WINDOW, timeout=20)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def correr_dsh(pedido, estado, sid=None, modo=None):
    """Corre UM pedido no dsh headless (com reservas). Devolve (texto, motor) ou (None, motivo).
    sid: continua essa sessao do dsh (--session-id). modo: 'planear' liga o modo Planear da guarda (DIPSY_MODO).
    Guarda o id da sessao usada em estado['sid']. Se a guarda dsh-bora nao ligar, para o dsh logo (falha fechada)."""
    curar_agents_md()
    renovar_contexto_livro()          # de hora a hora: mapa + regras + erros + indice do livro
    _, cwd_dsh = pasta_atual()
    dsh = shutil.which("dsh") or os.path.join(os.environ.get("APPDATA", ""), "npm", "dsh.cmd")
    ultimo_erro = "nenhum motor respondeu"
    env = ambiente()
    if modo:
        env["DIPSY_MODO"] = modo
    else:
        env.pop("DIPSY_MODO", None)
    for nome, patch in tentativas():
        if estado.get("cancelado") or estado.get("correcao"):
            return None, "cancelado"
        args = [dsh, "--profile", "headless"]
        if patch:
            args += ["--patch", patch]
        if sid:
            args += ["--session-id", sid]
        args += ["--json", "-"]
        try:
            proc = subprocess.Popen(
                args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                cwd=cwd_dsh, env=env, creationflags=NO_WINDOW,
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
        erros = []
        limite = time.time() + LIMITE_MINUTOS * 60

        def vigia():
            while proc.poll() is None:
                if time.time() > limite:
                    estado["excedeu"] = True
                    matar(proc)
                    return
                time.sleep(2)

        def ler_erros():   # le o stderr (diagnosticos do dsh): se a guarda nao ligou, para tudo antes de o dsh agir
            try:
                for b in proc.stderr:
                    l = b.decode("utf-8", "replace")
                    if GUARDA_FALHOU.search(l):
                        estado["guarda_falhou"] = l.strip()[:200]
                        log(f"GUARDA dsh-bora NAO LIGOU: {l.strip()[:160]}; dsh parado")
                        matar(proc)
                        return
            except Exception:
                pass

        threading.Thread(target=vigia, daemon=True).start()
        threading.Thread(target=ler_erros, daemon=True).start()
        for linha in proc.stdout:
            try:
                ev = json.loads(linha.decode("utf-8", "replace"))
            except Exception:
                continue
            t = ev.get("type")
            if t == "session" and ev.get("sessionId"):
                estado["sid"] = ev["sessionId"]
            elif t == "final":
                final = ev.get("text")
            elif t == "text" and ev.get("text"):
                textos.append(ev["text"])
            elif t == "error":
                erros.append(str(ev.get("message", ""))[:200])
        proc.wait()
        estado["proc"] = None
        if estado.get("guarda_falhou"):
            return None, "a guarda do Dipsy não ligou, por isso não trabalhei (pede ao Claude Code para ver o plugin dsh-bora)"
        if estado.get("excedeu"):
            return None, f"passou o limite de {LIMITE_MINUTOS} minutos"
        if estado.get("cancelado") or estado.get("correcao"):
            return None, "cancelado"
        resposta = final or ("\n".join(textos) if textos else None)
        if proc.returncode == 0 and resposta:
            return resposta, nome
        if sid and any(re.search(r"does not exist|cannot be adopted|was recorded in|is live in this process|cannot be driven", e) for e in erros):
            log(f"sessao {sid} ja nao se pode continuar ({erros[0][:120]}); passo a conversa nova")
            estado["sid_perdida"] = True
            sid = None
            continue
        ultimo_erro = f"{nome} falhou (codigo {proc.returncode})"
        log(ultimo_erro + (f": {erros[0]}" if erros else ""))
    return None, ultimo_erro


def git_mudados():
    """Ficheiros com alteracoes na arvore do repo (para dizer o que um pedido mudou). Conjunto vazio se falhar."""
    try:
        r = subprocess.run(["git", "-C", REPO, "status", "--porcelain"], capture_output=True, timeout=25, creationflags=NO_WINDOW)
        return {l[3:].strip() for l in r.stdout.decode("utf-8", "replace").splitlines() if len(l) > 3}
    except Exception:
        return set()


def libertar_ram():
    """Corre ~/.dsh/limpar-ram.ps1 em modo normal (sem -Forcar, sem -Sessoes). Devolve o texto para o Danilo."""
    if not os.path.exists(SCRIPT_RAM):
        return "Não encontrei o script de limpeza da memória. Pede ao Claude Code."
    reg = os.path.join(DSH, "limpar-ram.log")
    try:
        antes_b = os.path.getsize(reg)
    except Exception:
        antes_b = 0
    antes = vz._ram_livre_mb()
    try:
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPT_RAM],
                       capture_output=True, timeout=120, creationflags=NO_WINDOW)
    except Exception as e:
        return f"A limpeza da memória não correu ({type(e).__name__})."
    depois = vz._ram_livre_mb()
    novas = ""
    try:
        with open(reg, "rb") as f:
            f.seek(antes_b)
            novas = " | ".join(l.strip() for l in f.read().decode("utf-8", "replace").splitlines() if l.strip())[-400:]
    except Exception:
        pass
    log(f"libertar memoria: {antes} -> {depois} MB")
    return f"Memória livre antes: {antes} MB. Depois: {depois} MB." + (f" O que a limpeza fez: {novas}" if novas else "")


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
PREFIXO_CORRECAO = ("CORREÇÃO DO DANILO A MEIO DO TRABALHO (ele mandou /corrigir enquanto trabalhavas; o que estavas a fazer "
                    "foi interrompido): ")
SUFIXO_CORRECAO = ("\nContinua o trabalho a partir de onde ficaste, já com esta correção. Não repitas o que já estava bem. "
                   "Responde em português simples, curto, em texto corrido.")
PEDIDO_PLANEAR = ("Pedido do Danilo pelo Telegram, em MODO PLANEAR (/planear): ainda NÃO mudes nada; investiga só o "
                  "necessário e devolve o plano numerado, curto, em português simples, para ele aprovar. Pedido: ")
PEDIDO_APROVAR = ("O Danilo APROVOU o plano que fizeste (mandou /aprovar). Faz agora o plano, passo a passo, com as regras de "
                  "sempre, e no fim diz em texto corrido e curto o que ficou feito e como o provaste.")
OBJETIVO_INICIO = ("OBJETIVO DO DANILO (/objetivo): {meta}\nTrabalha sozinho para o cumprir; tens até {max} rondas e esta é a 1.ª. "
                   "Em cada ronda faz uma parte real do trabalho e prova-a. A ÚLTIMA linha da tua resposta tem de ser exatamente "
                   "uma destas: OBJETIVO CUMPRIDO: <prova> | OBJETIVO EM CURSO: <o que falta> | OBJETIVO BLOQUEADO: <porquê>. "
                   "Se precisares de uma decisão do Danilo, de dinheiro ou de algo que a guarda barrou, é BLOQUEADO.")
OBJETIVO_CONTINUA = ("Continua o objetivo (ronda {ronda} de {max}): {meta}\nFaz a parte seguinte do que faltava, prova-a, e acaba "
                     "outra vez com UMA destas linhas: OBJETIVO CUMPRIDO: <prova> | OBJETIVO EM CURSO: <o que falta> | "
                     "OBJETIVO BLOQUEADO: <porquê>.")


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
        self.conversa = {"sid": None, "ultimo": 0.0, "turnos": []}   # a conversa seguida com o dsh
        self.semente = None             # contexto a dar a uma conversa nova depois de /voltar
        self.plano = None               # plano a espera de /aprovar: {"sid", "pedido"}
        self.objetivo = None            # {"meta", "ronda", "parar", "estado"}
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
                "Podes mandar também uma foto, e eu vejo-a. Respondo sempre em texto e em áudio, com tudo por inteiro. "
                "Lembro-me da conversa enquanto falamos (até 30 minutos de pausa).\n"
                "/planear e o pedido: faço primeiro o plano, sem mexer em nada; se gostares, mandas /aprovar e eu faço.\n"
                "/objetivo e a meta: trabalho sozinho, ronda a ronda, até a meta estar cumprida (no máximo 6 rondas).\n"
                "/corrigir e a correção: mudo o rumo a meio do trabalho, sem começar do zero.\n"
                "/voltar: esqueço o último pedido, como se não o tivesses feito (os ficheiros que mudei não voltam atrás; eu digo quais).\n"
                "/nova: começo uma conversa nova. /libertar: liberto memória do PC.\n"
                "/motor: digo que motor estou a usar e quanto crédito do Claude resta. /sonnet: uso o Claude Sonnet (o normal). "
                "/opus: uso o Claude Opus, o melhor, para coisas difíceis. /gratis: uso só os motores grátis.\n"
                "/pasta: digo em que projeto trabalho; /pasta e o nome (em_dia, BoraStudio, jai-site...) muda de projeto.\n"
                "/estado diz o que estou a fazer. /parar cancela o que estou a fazer. "
                "/desligar fecha esta ligação ao Telegram (volta a ligar com o DIPSY no ambiente de trabalho).")

    def texto_motor(self):
        """/motor: o motor escolhido e o credito do Claude que resta (lido de GET /porteiro, pela Tailscale)."""
        m = motor_escolhido()
        linhas = [f"Estou a usar: {NOMES_MOTOR[m]}."]
        e = porteiro_estado(8)
        if e is None:
            linhas.append("O porteiro da VPS não responde agora: se precisar, vou pelos motores grátis do PC (Kilo e Gemini).")
            return " ".join(linhas)
        c = e.get("contas") or {}
        pode = ((e.get("decisoes") or {}).get("claude-dipsy") or [False, ""])
        if e.get("dormido_ate"):
            linhas.append(f"O crédito do Claude acabou: até ele voltar ({str(e['dormido_ate'])[:10]}) vou pelos motores grátis, sozinho.")
        elif e.get("pausa_ate"):
            linhas.append(f"O Claude está em pausa curta ({e.get('pausa_motivo') or 'erro'}); entretanto vou pelos grátis.")
        elif pode[0]:
            linhas.append("O Claude está disponível.")
        try:
            linhas.append(f"Crédito do Claude: restam cerca de {float(c.get('resta_usd') or 0):.2f} dólares "
                          f"(hoje gastos {float(c.get('gasto_hoje_usd') or 0):.2f}); o crédito novo chega a {c.get('proximo_credito')}.")
        except Exception:
            pass
        linhas.append("Sem limite por dia: só paro o Claude se o crédito acabar.")
        return " ".join(linhas)

    def texto_objetivo(self):
        o = self.objetivo
        if not o:
            return "Não há nenhum objetivo. Para dar um, escreve /objetivo e a meta."
        return f"Objetivo: {o['meta'][:200]}. Ronda {o['ronda']} de {MAX_RONDAS_OBJETIVO}. Estado: {o['estado']}."

    def voltar_atras(self):
        with self.trinco:
            ocupado = self.trabalho is not None
        if ocupado:
            return "Estou a meio de um trabalho. Manda /parar primeiro, e depois /voltar."
        turnos = self.conversa["turnos"]
        if not turnos:
            return "Não há nenhum pedido nesta conversa para esquecer."
        ultimo = turnos.pop()
        self.plano = None
        self.conversa["sid"] = None              # a proxima mensagem abre uma conversa nova do dsh...
        if turnos:                                # ...com o contexto dos pedidos de antes deste
            linhas = [f"{i}) Pedido: {t['pedido'][:300]} | Resposta: {t['resposta'][:400]}" for i, t in enumerate(turnos[-4:], 1)]
            self.semente = ("Contexto da conversa: o Danilo voltou atrás e pediu para esquecer o último pedido que fez. "
                            "Antes disso, nesta conversa, tinha sido isto:\n" + "\n".join(linhas) + "\n\n")
        else:
            self.semente = None
        ficheiros = ultimo.get("ficheiros") or []
        aviso = (f" Os ficheiros que esse pedido mudou não voltaram atrás: {', '.join(ficheiros[:8])}"
                 + (f" e mais {len(ficheiros) - 8}" if len(ficheiros) > 8 else "") + ". Se quiseres, pede ao Claude Code para os repor."
                 ) if ficheiros else " Esse pedido não mudou ficheiros no projeto."
        log(f"voltar atras: esquecido o pedido '{ultimo['pedido'][:60]}' ({len(ficheiros)} ficheiros mudados)")
        return f"Voltei atrás: esqueci o pedido \"{ultimo['pedido'][:120]}\".{aviso}"

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
            threading.Thread(target=self.trabalhar, args=(self.autorizado, pedido, t["pedido"][:70], titulo),
                             kwargs={"continuar": False}, daemon=True).start()
            return

    def trabalhar(self, chat_id, pedido, resumo, titulo=None, modo=None, continuar=True, pensar=False,
                  enviar=True, sid_forcado=None, pedido_danilo=None):
        """Corre um pedido no dsh e (por omissao) manda a resposta ao Danilo. Devolve (texto, motor).
        continuar: segue a conversa do dsh (se a ultima mensagem foi ha menos de 30 min) e regista o turno para /voltar.
        modo='planear': a guarda barra escritas. pensar: diz "Estou a pensar" se passar de ~20 s. A meio, /corrigir
        para o dsh e continua a MESMA sessao com a correcao (ate 3 vezes)."""
        estado = {"cancelado": False, "proc": None}
        with self.trinco:
            self.trabalho = {"inicio": time.time(), "resumo": resumo, "estado": estado}
        parar_aviso = threading.Event()

        def avisos():
            n = 0
            while not parar_aviso.wait(4.5):
                self.tg.a_escrever(chat_id)
                n += 1
                if pensar and n == 5:                                # ~22 s sem resposta
                    self.dizer(chat_id, "Estou a pensar, já te respondo.")
                if n in (40, 40 + 66, 40 + 132, 40 + 198):          # ~3 min e depois de 5 em 5
                    self.dizer(chat_id, "Ainda estou a trabalhar nisto. Escreve /parar para cancelar, ou /corrigir e o que queres diferente.")

        threading.Thread(target=avisos, daemon=True).start()
        sid = sid_forcado
        if sid is None and continuar and self.conversa["sid"] and time.time() - self.conversa["ultimo"] < JANELA_CONVERSA_MIN * 60:
            sid = self.conversa["sid"]
        texto_pedido = pedido
        if sid is None and continuar and self.semente:
            texto_pedido = self.semente + pedido
            self.semente = None
        antes = git_mudados() if continuar else set()
        texto, motor = None, "cancelado"
        try:
            for _ in range(MAX_CORRECOES + 1):
                texto, motor = correr_dsh(texto_pedido, estado, sid=sid, modo=modo)
                correcao = estado.pop("correcao", None)
                if not correcao or estado.get("cancelado"):
                    break
                sid = estado.get("sid") or sid
                log(f"correcao a meio: continuo a sessao {sid or '(nova)'}")
                texto_pedido = (PREFIXO_CORRECAO + correcao + SUFIXO_CORRECAO) if sid else (pedido + "\n\nCORREÇÃO DO DANILO: " + correcao)
        finally:
            parar_aviso.set()
            with self.trinco:
                self.trabalho = None
        if continuar and estado.get("sid"):
            self.conversa["sid"] = estado["sid"]
            self.conversa["ultimo"] = time.time()
        if estado["cancelado"]:
            return None, "cancelado"
        if texto is None:
            if enviar:
                self.dizer(chat_id, f"Não consegui fazer isto: {motor}. Tenta outra vez daqui a pouco.")
            return None, motor
        if continuar:
            mudados = sorted(git_mudados() - antes)
            self.conversa["turnos"].append({"pedido": (pedido_danilo or resumo), "resposta": texto[:1500], "ficheiros": mudados})
            self.conversa["turnos"] = self.conversa["turnos"][-12:]
        if enviar:
            rodape = "" if motor.startswith("porteiro") or motor_escolhido() == "gratis" else f"\n\n(motor de reserva: {motor})"
            cabeca = f"{titulo}.\n\n" if titulo else ""
            self.dizer(chat_id, cabeca + texto + rodape, falado=cabeca + texto)
        return texto, motor

    def _objetivo(self, meta):
        """/objetivo: o Dipsy trabalha sozinho, ronda a ronda (mesma sessao do dsh), ate a meta estar cumprida."""
        chat = self.autorizado
        self.objetivo = {"meta": meta, "ronda": 0, "parar": False, "estado": "a começar"}
        sid = None
        texto = ""
        for ronda in range(1, MAX_RONDAS_OBJETIVO + 1):
            o = self.objetivo
            if not o or o["parar"]:
                break
            o["ronda"] = ronda
            o["estado"] = "a trabalhar"
            pedido = PREFIXO + (OBJETIVO_INICIO.format(meta=meta, max=MAX_RONDAS_OBJETIVO) if ronda == 1
                                else OBJETIVO_CONTINUA.format(ronda=ronda, max=MAX_RONDAS_OBJETIVO, meta=meta))
            texto, motor = self.trabalhar(chat, pedido, f"objetivo, ronda {ronda}: {meta[:50]}", enviar=False,
                                          sid_forcado=sid, pedido_danilo=f"/objetivo {meta}" if ronda == 1 else f"(objetivo, ronda {ronda})")
            if texto is None:
                o["estado"] = "parado" if motor == "cancelado" else f"falhou: {motor}"
                if motor != "cancelado":
                    self.dizer(chat, f"O objetivo parou na ronda {ronda}: {motor}.")
                break
            sid = self.conversa["sid"]
            marca = None
            for linha in reversed(texto.strip().splitlines()[-6:]):
                marca = MARCA_OBJETIVO.search(linha)
                if marca:
                    break
            tipo = re.sub(r"\s+", " ", marca.group(1).upper()) if marca else "EM CURSO"
            resto = (marca.group(2).strip() if marca else "")[:300]
            log(f"objetivo ronda {ronda}: {tipo} {resto[:80]}")
            if tipo == "CUMPRIDO":
                o["estado"] = "cumprido"
                self.dizer(chat, f"Objetivo cumprido (ronda {ronda} de {MAX_RONDAS_OBJETIVO}).\n\n{texto}")
                break
            if tipo == "BLOQUEADO":
                o["estado"] = f"bloqueado: {resto}"
                self.dizer(chat, f"Objetivo bloqueado na ronda {ronda}.\n\n{texto}")
                break
            o["estado"] = f"em curso, falta: {resto}" if resto else "em curso"
            if ronda == MAX_RONDAS_OBJETIVO:
                self.dizer(chat, f"Fiz as {MAX_RONDAS_OBJETIVO} rondas e o objetivo ainda não está cumprido. Onde fiquei:\n\n{texto}")
            elif not o["parar"]:
                self.dizer(chat, f"Ronda {ronda} feita. Falta: {resto or 'continuar'}. Sigo para a ronda {ronda + 1} (para parar: /objetivo parar).")
        if self.objetivo and self.objetivo.get("parar"):
            self.dizer(chat, f"Parei o objetivo na ronda {self.objetivo['ronda']}, como pediste.")
        if self.objetivo:
            self.objetivo["fim"] = True

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
        self.trabalhar(chat, PREFIXO + texto, texto[:70], pensar=True, pedido_danilo=texto)

    def tratar(self, u):
        m = u.get("message")
        if not m:
            return
        chat = m.get("chat", {})
        de = m.get("from", {})
        if chat.get("id") != self.autorizado or de.get("id") != self.autorizado or chat.get("type") != "private":
            self.ignoradas += 1
            log(f"mensagem de alguem nao autorizado (ignorada; total {self.ignoradas})")
            # 01/11/2026 (B6): o grupo "Bora Bastidores" (do Danilo, com os 2 bots) fica registado para o porteiro da VPS
            if chat.get("type") in ("group", "supergroup") and de.get("id") == self.autorizado:
                try:
                    with open(os.path.join(PASTA, "grupos.json"), "w", encoding="utf-8") as f:
                        json.dump({"id": chat.get("id"), "titulo": chat.get("title"), "visto": datetime.now().isoformat()}, f, ensure_ascii=False)
                    log(f"grupo do Danilo visto: {chat.get('title')} id={chat.get('id')}")
                except Exception:
                    pass
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
        partes = texto.split(None, 1)
        resto = partes[1].strip() if cmd and len(partes) > 1 else ""
        quem = self.autorizado
        with self.trinco:
            ocupado = self.trabalho is not None or bool(self.objetivo and not self.objetivo.get("fim"))
        ocupado_msg = "Ainda estou a trabalhar no pedido anterior. Escreve /parar para o cancelar, ou /corrigir e o que queres diferente."
        if cmd in ("/start", "/ajuda", "/help"):
            self.dizer(quem, self.ajuda())
            return
        if cmd == "/estado":
            extra = ("\n" + self.texto_objetivo()) if self.objetivo and not self.objetivo.get("fim") else ""
            extra += "\nHá um plano à espera do teu /aprovar." if self.plano else ""
            self.dizer(quem, self.estado() + extra)
            return
        if cmd == "/agenda":
            self.dizer(quem, self.texto_agenda())
            return
        if cmd in ("/sonnet", "/opus", "/gratis", "/grátis"):
            m = "gratis" if cmd.startswith("/gr") else cmd[1:]
            with open(FICH_MOTOR, "w", encoding="utf-8") as f:
                f.write(m)
            log(f"motor escolhido pelo Danilo: {m}")
            extra = {"opus": " É o melhor e o mais caro: uso-o até mandares /sonnet.",
                     "sonnet": "", "gratis": " Para voltar ao Claude, manda /sonnet."}[m]
            self.dizer(quem, f"Combinado: a partir de agora uso {NOMES_MOTOR[m]}.{extra}")
            return
        if cmd == "/motor":
            self.dizer(quem, self.texto_motor())
            return
        if cmd == "/pasta":
            ps = pastas_dipsy()
            atual, _ = pasta_atual()
            if not resto:
                self.dizer(quem, f"Estou a trabalhar na pasta {atual}. Leio todas as pastas; para escrever noutra, manda "
                                 f"/pasta e o nome. Pastas: {', '.join(sorted(ps))}.")
                return
            if ocupado:
                self.dizer(quem, ocupado_msg)
                return
            escolha = next((k for k in ps if k.lower() == resto.strip().lower()), None)
            if not escolha or not os.path.isdir(ps[escolha]):
                self.dizer(quem, f"Não conheço a pasta {resto.strip()}. Pastas: {', '.join(sorted(ps))}.")
                return
            with open(FICH_PASTA, "w", encoding="utf-8") as f:
                f.write(escolha)
            self.conversa = {"sid": None, "ultimo": 0.0, "turnos": []}
            log(f"pasta de trabalho escolhida pelo Danilo: {escolha}")
            self.dizer(quem, f"Combinado: a partir de agora trabalho na pasta {escolha}. Comecei uma conversa nova.")
            return
        if cmd == "/parar":
            if self.objetivo and not self.objetivo.get("fim"):
                self.objetivo["parar"] = True
            self.dizer(quem, self.parar())
            return
        if cmd == "/libertar":
            self.dizer(quem, "Vou libertar memória do PC (só fecho o que é seguro). Um momento.")
            threading.Thread(target=lambda: self.dizer(quem, libertar_ram()), daemon=True).start()
            return
        if cmd == "/voltar":
            self.dizer(quem, self.voltar_atras())
            return
        if cmd == "/corrigir":
            if not resto:
                self.dizer(quem, "Escreve /corrigir e, a seguir, o que queres diferente.")
                return
            with self.trinco:
                t = self.trabalho
            if t:
                t["estado"]["correcao"] = resto
                p = t["estado"].get("proc")
                if p:
                    matar(p)
                log("correcao a meio pedida pelo Danilo")
                self.dizer(quem, "Recebi a correção. Paro o que estava a fazer e continuo já com ela, sem começar do zero.")
                return
            if self.plano:
                self.dizer(quem, "Recebi. Vou mudar o plano, ainda sem mexer em nada.")
                threading.Thread(target=self._planear, args=(PEDIDO_PLANEAR + "muda o plano que fizeste assim: " + resto, "/corrigir " + resto[:60]),
                                 kwargs={"sid": self.plano.get("sid")}, daemon=True).start()
            else:
                self.dizer(quem, "Recebi a correção. Vou refazer o último trabalho com ela.")
                threading.Thread(target=self.trabalhar, args=(quem, PREFIXO + "Correção ao teu último trabalho: " + resto, resto[:70]),
                                 kwargs={"pedido_danilo": "/corrigir " + resto}, daemon=True).start()
            return
        if cmd == "/objetivo":
            if not resto:
                self.dizer(quem, self.texto_objetivo())
                return
            if resto.lower() in ("parar", "pausa", "pausar", "cancelar", "limpar", "acabar"):
                if self.objetivo and not self.objetivo.get("fim"):
                    self.objetivo["parar"] = True
                    self.dizer(quem, "Paro o objetivo no fim desta ronda. Para parar já, manda /parar.")
                else:
                    self.dizer(quem, "Não há nenhum objetivo a correr.")
                return
            if ocupado:
                self.dizer(quem, ocupado_msg)
                return
            self.dizer(quem, f"Objetivo recebido: {resto[:160]}. Vou trabalhar sozinho, ronda a ronda (no máximo {MAX_RONDAS_OBJETIVO}), e digo-te como vai.")
            threading.Thread(target=self._objetivo, args=(resto,), daemon=True).start()
            return
        if cmd == "/planear":
            if not resto:
                self.dizer(quem, "Escreve /planear e, a seguir, o que queres. Eu faço só o plano; depois mandas /aprovar.")
                return
            if ocupado:
                self.dizer(quem, ocupado_msg)
                return
            self.dizer(quem, "Vou planear, sem mexer em nada. Já te mando o plano.")
            threading.Thread(target=self._planear, args=(PEDIDO_PLANEAR + resto, "/planear " + resto[:60]), daemon=True).start()
            return
        if cmd == "/aprovar":
            if not self.plano:
                self.dizer(quem, "Não há nenhum plano à espera. Para fazer um, escreve /planear e o pedido.")
                return
            if ocupado:
                self.dizer(quem, ocupado_msg)
                return
            plano, self.plano = self.plano, None
            self.dizer(quem, "Aprovado. Vou fazer o plano agora.")
            threading.Thread(target=self.trabalhar, args=(quem, PEDIDO_APROVAR, "plano aprovado: " + plano["pedido"][:50]),
                             kwargs={"sid_forcado": plano.get("sid"), "pedido_danilo": "/aprovar (" + plano["pedido"][:60] + ")"},
                             daemon=True).start()
            return
        if cmd == "/nova":
            if ocupado:
                self.dizer(quem, ocupado_msg)
                return
            self.conversa = {"sid": None, "ultimo": 0.0, "turnos": []}
            self.semente = None
            self.plano = None
            self.dizer(quem, "Começámos uma conversa nova: esqueci o contexto anterior.")
            return
        if cmd == "/desligar":
            item = self.dizer(self.autorizado, "Desligado. Para me voltares a ligar, abre o DIPSY no ambiente de trabalho do PC.")
            if item:
                item["feito"].wait(timeout=90)
            log("desligado a pedido do Danilo")
            os._exit(0)
        if ocupado:
            self.dizer(self.autorizado, ocupado_msg)
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
        threading.Thread(target=self.trabalhar, args=(self.autorizado, PREFIXO + pedido, resumo),
                         kwargs={"pedido_danilo": texto or "(foto)"}, daemon=True).start()

    def _planear(self, pedido, resumo, sid=None):
        """/planear: corre o dsh com a guarda em modo Planear e guarda o plano a espera de /aprovar."""
        texto, _ = self.trabalhar(self.autorizado, pedido, resumo, modo="planear", sid_forcado=sid, pedido_danilo=resumo)
        if texto is not None:
            self.plano = {"sid": self.conversa["sid"], "pedido": resumo, "quando": time.time()}
            log(f"plano pronto, a espera de /aprovar (sessao {self.conversa['sid']})")

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
                {"command": "planear", "description": "Planear: faço o plano e só mexo depois de aprovares"},
                {"command": "aprovar", "description": "Aprovar o plano e fazer"},
                {"command": "objetivo", "description": "Objetivo: trabalho sozinho até cumprir"},
                {"command": "corrigir", "description": "Corrigir: mudo o rumo a meio do trabalho"},
                {"command": "voltar", "description": "Voltar atrás: esqueço o último pedido"},
                {"command": "nova", "description": "Conversa nova"},
                {"command": "libertar", "description": "Libertar memória do PC"},
                {"command": "agenda", "description": "As tarefas marcadas para uma hora"},
                {"command": "motor", "description": "Que motor estou a usar e quanto crédito resta"},
                {"command": "pasta", "description": "Em que projeto trabalho (Bora, Em Dia, BoraStudio, sites...)"},
                {"command": "sonnet", "description": "Usar o Claude Sonnet (o normal)"},
                {"command": "opus", "description": "Usar o Claude Opus (o melhor)"},
                {"command": "gratis", "description": "Usar só os motores grátis"},
                {"command": "parar", "description": "Cancelar o pedido atual"},
                {"command": "ajuda", "description": "O que sei fazer"},
                {"command": "desligar", "description": "Desligar o Dipsy"},
            ]))
        except Exception as e:
            log(f"nao consegui pôr o menu de comandos: {e}")
        threading.Thread(target=self._agenda_loop, daemon=True).start()
        threading.Thread(target=renovar_contexto_livro, kwargs={"forcar": True}, daemon=True).start()
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
