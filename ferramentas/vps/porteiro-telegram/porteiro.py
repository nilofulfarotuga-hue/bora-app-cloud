#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PORTEIRO — a UNICA porta de saida para o chat do Danilo no BoraHermesbot (missao retoma-geral-2026-10-31, bloco 6;
ordem do Danilo de 31/10 10:07). Vive ao lado de voz.py (fila + trabalhador da voz) e usa-o para falar.

PORQUE: chegavam-lhe (a) mensagens sem voz, de remetentes que falavam direto com a API do bot (curl de sessoes, crons das
redes, `hermes send`, Edge Function); (b) duplicados (o mesmo aviso por dois caminhos); (c) ruido que nao era para ele
("Facebook: ok", ids, estados de rotinas, propostas do radar). Ele quer SO resultados e urgencias, em portugues simples
e SEMPRE com voz; o resto resolve-se entre os robos.

ENTRADA:  telegram_danilo(texto, nivel, origem, ficheiros=None)
  nivel URGENTE   -> precisa dele agora (clique, dinheiro, decisao, cliente em apuros, alertas da base): texto + voz na
                     hora; comeca por "Precisas de ti:".
  nivel RESULTADO -> missao/rotina acabou: texto + voz, 3 linhas no maximo (o resto vai para os bastidores).
  nivel INFO      -> estados, ids, ok/erro de rotinas, propostas, radar: NAO vai ao chat dele. Vai para o e2e_log
                     (fluxo porteiro-telegram), para info-AAAA-MM-DD.jsonl e para o grupo "Bora Bastidores" (se existir).
                     O resumo das 06:45 e das 21:00 junta o INFO em 5 linhas com voz.
  Sem nivel: vale o nivel do remetente (ORIGENS) e o texto pode subir INFO -> URGENTE ("precisas de ti", "autoriza"...).
  Anti-duplicado: hash do texto sem horas/datas/ids, janela de 30 min; o 2.o igual e' descartado e registado.

REGRA DO DANILO 08/11/2026 (missao m6-crescimento-hermes): "so se for urgente mesmo". URGENTE so passa em 5 casos:
  1) pedido parado: sem estafeta/motorista/limpadora ha mais de 10 min (o vigia dos 10 min trata disto), ou ainda
     por encomendar a loja depois do 1.o aviso;
  2) pagamento falhado de cliente real (testes e contas demo nunca);
  3) app/site/funcao em baixo;
  4) candidato novo (candidatura completa);
  5) cliente a reclamar ou a pedir uma pessoa (inclui o cerebro do WhatsApp a escalar um cliente, origem "voz").
  Tudo o resto que chegasse como URGENTE (mesmo com nivel pedido explicitamente) desce a INFO e vai no resumo das 21:00
  (ou a RESULTADO, se o remetente for de resultados). Pedido novo, corrida nova e limpeza nova descem a INFO e ficam no
  VIGIA DOS 10 MIN: se ao fim de 10 min (ou 20 min antes da hora marcada) ainda nao tiverem estafeta, sai um URGENTE.
  radar-jai: URGENTE so quando um jornalista responde ("RESPOSTA de jornalista") ou o site do Jai esta em baixo.

PORTAS (systemd porteiro.service):
  127.0.0.1:8796 e 172.16.1.1:8796 (so maquina e redes docker):
     POST /telegram_danilo  {"texto","nivel","origem","ficheiros":[{"nome","b64"}]}
     *    /o/<origem>/bot<token>/<metodo>   espelho da API do bot: os scripts antigos so trocaram o endereco base;
                                            sendMessage/sendPhoto/... para o chat do Danilo passam pela triagem; o
                                            resto (outros chats, outros bots, getMe...) segue igual para a API.
     GET  /saude
  127.0.0.1:8797: SO POST /telegram_danilo com o cabecalho X-Porteiro-Segredo (PORTEIRO_SEGREDO em
     /opt/data/voz/porteiro.env). Ficou so local: publica-la pelo traefik foi recusado (31/10, TRANCAS.md).
  Fila da base public.porteiro_entrada (so service_role): a Edge notify-admin-urgent escreve, o porteiro le de 10 em 10 s.
  PC (sessoes do Claude Code): por ssh, `python3 /opt/data/voz/porteiro_cli.py danilo NIVEL --origem X -` (texto no stdin).

LINHA DE COMANDO:
  porteiro.py danilo URGENTE|RESULTADO|INFO [--origem X] [--foto CAMINHO]... (texto | -f FICHEIRO | -)
  porteiro.py --servir
  porteiro.py --resumo manha|noite [--seco]
  porteiro.py --bastidores          # mostra se o grupo "Bora Bastidores" ja foi encontrado
"""
import base64
import datetime
import email.parser
import email.policy
import fcntl
import hashlib
import hmac
import json
import mimetypes
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

sys.path.insert(0, "/opt/data/voz")
import voz  # noqa: E402  (o porteiro so usa voz.enviar_texto / voz.pedir_audio, nunca voz.falar: sem voltas)

DIR = "/opt/data/voz/porteiro"
CONF = "/opt/data/voz/porteiro.env"
LOG = os.path.join(DIR, "porteiro.log.jsonl")
VISTOS = os.path.join(DIR, "vistos.json")
TRINCO = os.path.join(DIR, ".trinco")
RESUMO_OK = os.path.join(DIR, "resumo.json")
CANAIS = "/opt/data/channel_directory.json"
PORTA_LOCAL, PORTA_PUBLICA = 8796, 8797
HOSTS_LOCAIS = ("127.0.0.1", "172.16.1.1")
JANELA_DUP = 30 * 60
NIVEIS = ("URGENTE", "RESULTADO", "INFO")
TZ = ZoneInfo("Europe/Lisbon")
API = "https://api.telegram.org"

# Nivel por omissao de cada remetente conhecido (nome do script sem extensao). O texto ainda pode subir INFO -> URGENTE.
ORIGENS = {
    # precisam dele
    "notify-admin-urgent": "URGENTE", "hermes-meta-token-vigia": "URGENTE", "cobrador": "URGENTE",
    "ig_auto_dm": "URGENTE",
    # /usr/local/bin/voz: quem o chama e' sobretudo o cerebro do WhatsApp a escalar um cliente (cerebro/telegram.py)
    "voz": "URGENTE",
    # vigias: so chegam ao chat quando o texto diz que precisam dele ("precisa de ti", "faz login"...)
    "hermes-gateway-watchdog": "INFO", "hermes-watchdog": "INFO", "claude-token-watchdog": "INFO",
    # resultados (rotina/missao acabou)
    "prova_do_dia": "RESULTADO", "resumo_do_dia": "RESULTADO", "social-medir": "RESULTADO", "manha": "RESULTADO",
    "hermes-relatorio-semanal": "RESULTADO", "bom-dia": "RESULTADO", "enviar-video-telegram": "RESULTADO",
    "ipg-enviar-video": "RESULTADO",
    # bastidores
    "social-story": "INFO", "social-reel": "INFO", "social-carrossel": "INFO", "social-loja-do-dia": "INFO",
    "social-bora": "INFO", "social-grupos-resumo": "INFO", "social-grupos-plano": "INFO", "social-reavaliacao": "INFO",
    "social-formato-extra": "INFO", "social-semana": "INFO", "publicar_cartaz": "INFO", "publicar-ipg": "INFO",
    "radar-ia": "INFO", "radar-dinheiro": "INFO", "radar_freelas": "INFO", "radar-jai": "INFO", "correr": "INFO",
    "radar-crescimento": "INFO",
    "hermes-voz-guarda": "INFO", "hermes-heartbeat": "INFO", "hermes-notificar-rotina": "INFO", "hermes-sonda-auth": "INFO",
    "hermes-carteiro-vigia": "INFO", "hermes-hook-conclusao": "INFO", "carteiro": "INFO", "guarda_noturno": "INFO",
    "carteiro_caca": "INFO", "caca_respostas": "INFO", "vigia_porta": "INFO", "gritar": "INFO", "em-dia-telegram": "INFO",
    "bora-env-guarda": "INFO", "emerson": "INFO", "despachante": "INFO", "aviso2": "INFO", "rotinas": "INFO",
}
RE_URGENTE = re.compile(
    r"(?i)precisas? de ti|precisamos de ti|preciso de ti|\burgente\b|\bautoriz|carrega(r)? em|clica(r)? |"
    r"\baprova(r|s)?\b|aceitar o contrato|faz(er)? login|iniciar sess|ler o (c[oó]digo )?qr|escanear|"
    r"pedido novo|novo pedido|nova encomenda|nova reserva|nova marca[cç][aã]o|marca[cç][aã]o nova|novo cadastro|"
    r"nova candidatura|cliente (?:[àa] espera|em apuros)|reclama[cç]")
RE_RESULTADO = re.compile(r"(?i)^\W*(feito|conclu[ií]d|acabou|terminad|pronto)|miss[aã]o .{0,40}(acabou|conclu)")

# ── Regra 08/11: os 5 casos que podem ser URGENTE (ver o topo). O resto desce. ──
RE_URGENTE_OK = re.compile(
    r"(?i)"
    # 1) pedido parado
    r"sem (estafeta|motorista|limpadora|profissional)|ningu[eé]m aceitou|sem estafetas? dispon|ainda por encomendar|"
    r"pedido parado|corrida parada|"
    # 2) pagamento falhado de cliente real
    r"pagamento (falh|recusad|n[aã]o passou)|falhou o pagamento|cart[aã]o recusado|payment_failed|"
    r"pag(ou|amento) e n[aã]o tem pedido|cobran[cç]a (ao cliente )?falh|"
    # 3) app em baixo
    r"fun[cç][aã]o n[aã]o responde|\b(app|site|servidor|painel|base)\b.{0,40}(em baixo|fora do ar|caiu|n[aã]o (abre|responde|carrega))|"
    # 4) candidato novo
    r"nova candidatura|candidatura (nova|completa)|novo candidato|candidato novo|"
    # 5) cliente a reclamar ou a pedir uma pessoa
    r"reclam|pedido de ajuda|atendimento humano|assistente real|falar com (um |uma )?(humano|pessoa)|"
    r"cliente (?:[àa] espera|em apuros|zangad|chatead|irritad)|escreveu ao suporte")
# Nunca urgente: testes, contas demo e "0 reclamacoes" de relatorios.
RE_NUNCA_URGENTE = re.compile(
    r"(?i)test user|teste vigia|\[teste\]|\bensaio\b|loja demo|conta demo|@bora\.app\b|"
    r"\b0 reclama|sem reclama|nenhuma reclama")
# radar-jai: so jornalista a responder ou o site do Jai em baixo.
RE_JAI_URGENTE = re.compile(
    r"(?i)RESPOSTA de jornalista|(jaiagarwala\.com|site do jai).{0,80}(em baixo|fora do ar|caiu|n[aã]o (abre|responde)|"
    r"offline|HTTP 5\d\d|erro 5\d\d)")
# Remetentes que por construcao ja sao "cliente a pedir uma pessoa" (cerebro do WhatsApp a escalar).
ORIGENS_SEMPRE_URGENTES = {"voz", "vigia-10min"}
# Pedido/corrida/limpeza novos: descem a INFO e entram no vigia dos 10 min. (tabela, coluna de quem faz, hora marcada,
# estados terminados, antecedencia em min antes da hora marcada)
NOVOS = [
    (re.compile(r"(?i)pedido novo|ligar [àa] loja"), "orders", "assigned_driver_id", "scheduled_for",
     ("delivered", "cancelled", "canceled", "refunded"), 20),
    (re.compile(r"(?i)corrida tvde"), "tvde_rides", "driver_id", "scheduled_at",
     ("finalizada", "cancelada_cliente", "cancelada", "cancelada_motorista", "cancelada_admin", "no_show"), 20),
    (re.compile(r"(?i)limpeza nova"), "cleaning_bookings", "cleaner_id", "scheduled_at",
     ("completed", "accepted", "cancelled", "cancelled_client", "cancelled_no_cleaner", "cancelled_admin"), 24 * 60),
]
RE_ID_CURTO = re.compile(r"#([0-9a-f]{8})\b")
VIGIA = os.path.join(DIR, "vigia-10min.json")
VIGIA_MIN = 10
METODOS_TEXTO = ("sendMessage",)
METODOS_MEDIA = ("sendPhoto", "sendVideo", "sendDocument", "sendAnimation", "sendMediaGroup", "sendAudio", "sendVoice")

_trinco_mem = threading.Lock()


# ───────────────────────────── utilitarios ─────────────────────────────

def conf():
    c = {}
    try:
        with open(CONF, encoding="utf-8") as fh:
            for ln in fh:
                ln = ln.strip()
                if ln and not ln.startswith("#") and "=" in ln:
                    k, v = ln.split("=", 1)
                    c[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return c


def agora():
    return datetime.datetime.now(datetime.timezone.utc)


def registar(**o):
    o["ts"] = agora().isoformat(timespec="seconds")
    try:
        os.makedirs(DIR, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(o, ensure_ascii=False, default=str) + "\n")
    except Exception:  # noqa: BLE001
        pass


class _Trinco:
    """Trinco entre processos (servidor, voz.falar das rotinas, linha de comando) para o ficheiro dos vistos."""

    def __enter__(self):
        os.makedirs(DIR, exist_ok=True)
        _trinco_mem.acquire()
        self.fh = open(TRINCO, "w")
        fcntl.flock(self.fh, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        try:
            fcntl.flock(self.fh, fcntl.LOCK_UN)
            self.fh.close()
        finally:
            _trinco_mem.release()


def chave_dup(texto):
    t = (texto or "").lower()
    t = re.sub(r"https?://\S+", " ", t)
    t = re.sub(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", " ", t)
    t = re.sub(r"\b\d{1,2}[:h]\d{2}(:\d{2})?\b", " ", t)            # horas
    t = re.sub(r"\b\d{1,4}[-/.]\d{1,2}([-/.]\d{1,4})?\b", " ", t)   # datas
    t = re.sub(r"\b(?=\w*\d)(?=\w*[a-z])\w{8,}\b", " ", t)             # ids com letras e numeros
    t = re.sub(r"\b\d{5,}\b", " ", t)                               # ids numericos
    t = re.sub(r"[^\w€]+", " ", t)
    return hashlib.sha1(" ".join(t.split()).encode("utf-8")).hexdigest()


def ja_visto(texto, origem, nivel):
    """True se o mesmo texto (sem horas/ids) ja passou nos ultimos 30 min. Regista-o se for novo."""
    k = texto if texto.startswith("anexo:") else chave_dup(texto)
    with _Trinco():
        try:
            with open(VISTOS, encoding="utf-8") as fh:
                v = json.load(fh)
        except Exception:  # noqa: BLE001
            v = {}
        t = time.time()
        v = {a: b for a, b in v.items() if t - b.get("t", 0) < 2 * JANELA_DUP}
        antes = v.get(k)
        if antes and t - antes.get("t", 0) < JANELA_DUP:
            return antes
        v[k] = {"t": t, "origem": origem, "nivel": nivel}
        tmp = VISTOS + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(v, fh)
        os.replace(tmp, VISTOS)
    return None


def _decidir_nivel_antigo(texto, nivel, origem):
    n = (nivel or "").strip().upper()
    if n in NIVEIS:
        return n, "pedido"
    base = ORIGENS.get(origem)
    if base == "URGENTE":
        return "URGENTE", "remetente"
    if RE_URGENTE.search(texto or ""):
        return "URGENTE", "texto"
    if base:
        return base, "remetente"
    if RE_RESULTADO.search(texto or ""):
        return "RESULTADO", "texto"
    return "INFO", "omissao"


def urgente_permitido(texto, origem):
    """Regra do Danilo 08/11: True so nos 5 casos (ver o topo do ficheiro)."""
    t = texto or ""
    if RE_NUNCA_URGENTE.search(t):
        return False
    base = (origem or "").split(":")[0]
    if base == "radar-jai":
        return bool(RE_JAI_URGENTE.search(t))
    if base in ORIGENS_SEMPRE_URGENTES:
        return True
    return bool(RE_URGENTE_OK.search(t))


def decidir_nivel(texto, nivel, origem):
    n, porque = _decidir_nivel_antigo(texto, nivel, origem)
    base = (origem or "").split(":")[0]
    # radar-jai: o jornalista a responder sobe a URGENTE mesmo sem as palavras antigas.
    if base == "radar-jai" and n != "URGENTE" and urgente_permitido(texto, origem):
        return "URGENTE", "regra-08-11:jai"
    if n != "URGENTE" or urgente_permitido(texto, origem):
        return n, porque
    desce = "RESULTADO" if (ORIGENS.get(base) == "RESULTADO" or RE_RESULTADO.search(texto or "")) else "INFO"
    return desce, "regra-08-11:" + porque


def novo_para_vigiar(texto):
    """Pedido/corrida/limpeza novo com o #id curto -> (tabela, id8, ...) para o vigia dos 10 min; senao None."""
    m = RE_ID_CURTO.search(texto or "")
    if not m:
        return None
    for rx, tabela, quem, hora, fim, antes in NOVOS:
        if rx.search(texto or ""):
            return {"tabela": tabela, "id8": m.group(1), "quem": quem, "hora": hora, "fim": list(fim), "antes_min": antes,
                    "titulo": (texto or "").splitlines()[0][:120]}
    return None


def formatar(texto, nivel, sem_corte=False):
    """Devolve (texto_para_o_chat, resto_para_os_bastidores)."""
    t = (texto or "").strip()
    if nivel == "URGENTE" and not re.match(r"(?i)^\W*precisas? de ti", t):
        t = "Precisas de ti: " + t
    if nivel == "RESULTADO" and not sem_corte:
        linhas = [ln for ln in t.splitlines() if ln.strip()]
        if len(linhas) > 3:
            return "\n".join(linhas[:3]) + "\n(o resto ficou nos bastidores)", t
    return t, None


def bastidores_chat():
    c = conf().get("PORTEIRO_BASTIDORES_CHAT", "").strip()
    if c:
        return c
    try:   # o grupo aparece aqui quando o Danilo junta o bot ao grupo "Bora Bastidores"
        with open(CANAIS, encoding="utf-8") as fh:
            d = json.load(fh)
        for ch in (d.get("platforms") or {}).get("telegram") or []:
            if re.search(r"(?i)bastidores", str(ch.get("name") or "")) and str(ch.get("id", "")).startswith("-"):
                return str(ch["id"])
    except Exception:  # noqa: BLE001
        pass
    return ""


def _e2e(passo, estado, detalhe):
    try:
        sys.path.insert(0, "/opt/data/rotinas")
        from comum import SUPA_URL, SUPA_KEY, CTX  # noqa: E402
        corpo = json.dumps({"fluxo": "porteiro-telegram", "passo": passo[:80], "estado": estado,
                            "detalhe": detalhe[:1800], "device": "vps", "run_id": "porteiro"}).encode("utf-8")
        req = urllib.request.Request(SUPA_URL + "/rest/v1/e2e_log", data=corpo, method="POST", headers={
            "apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY, "Content-Type": "application/json",
            "Prefer": "return=minimal"})
        urllib.request.urlopen(req, timeout=15, context=CTX).read()
        return True
    except Exception as e:  # noqa: BLE001
        registar(evento="e2e-falhou", erro=str(e)[:200])
        return False


# ───────────────────────────── API do bot ─────────────────────────────

def api(metodo, campos, ficheiros=None, token=None):
    """Chama a API do bot com multipart. ficheiros = [(campo, nome, bytes)]. Devolve o JSON (ou levanta)."""
    lim = "----porteiro%s" % uuid.uuid4().hex
    corpo = b""
    for k, v in campos.items():
        corpo += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (lim, k, v)).encode("utf-8")
    for campo, nome, dados in ficheiros or []:
        mime = mimetypes.guess_type(nome)[0] or "application/octet-stream"
        corpo += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                  % (lim, campo, nome, mime)).encode("utf-8") + dados + b"\r\n"
    corpo += ("--%s--\r\n" % lim).encode("utf-8")
    req = urllib.request.Request("%s/bot%s/%s" % (API, token or voz.CRED, metodo), data=corpo,
                                 headers={"Content-Type": "multipart/form-data; boundary=%s" % lim})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def _tipo_media(nome):
    ext = os.path.splitext(nome.lower())[1]
    if ext in (".jpg", ".jpeg", ".png", ".webp"):
        return "photo"
    if ext in (".mp4", ".mov", ".m4v", ".webm"):
        return "video"
    return "document"


def enviar_media(chat, ficheiros, legenda):
    """1 ficheiro -> sendPhoto/sendVideo/sendDocument; varios -> sendMediaGroup (legenda no 1.o). Devolve ids."""
    leg = legenda if len(legenda) <= 1000 else ""
    if len(ficheiros) == 1:
        nome, dados = ficheiros[0]
        tipo = _tipo_media(nome)
        metodo = {"photo": "sendPhoto", "video": "sendVideo"}.get(tipo, "sendDocument")
        r = api(metodo, {"chat_id": chat, "caption": leg}, [(tipo, nome, dados)])
        return [r["result"]["message_id"]]
    media, anexos = [], []
    for i, (nome, dados) in enumerate(ficheiros[:10]):
        tipo = _tipo_media(nome)
        tipo = tipo if tipo in ("photo", "video") else "document"
        campo = "f%d" % i
        item = {"type": tipo, "media": "attach://" + campo}
        if i == 0 and leg:
            item["caption"] = leg
        media.append(item)
        anexos.append((campo, nome, dados))
    r = api("sendMediaGroup", {"chat_id": chat, "media": json.dumps(media)}, anexos)
    return [m["message_id"] for m in r.get("result") or []]


# ───────────────────────────── a porta ─────────────────────────────

def telegram_danilo(texto, nivel=None, origem="desconhecido", ficheiros=None, cru=None, sem_corte=False, ensaio=False):
    """O unico caminho para o chat do Danilo. ficheiros=[(nome, bytes)]. cru=(metodo, ctype, corpo) reencaminha um
    pedido original da API tal e qual (espelho). ensaio=True decide tudo e NAO envia nem grava (prova sem incomodar).
    Nunca levanta; devolve dict com o que aconteceu."""
    texto = (texto or "").strip()
    origem = re.sub(r"[^\w.\-:]", "", str(origem or "desconhecido"))[:60] or "desconhecido"
    ficheiros = ficheiros or []
    if not texto and not ficheiros and not cru:
        return {"ok": False, "porque": "texto vazio"}
    n, porque = decidir_nivel(texto, nivel, origem)
    vigiar = novo_para_vigiar(texto) if n != "URGENTE" else None
    if ensaio:
        para_chat, resto = formatar(texto, n, sem_corte)
        r = {"ok": True, "ensaio": True, "nivel": n, "porque": porque, "origem": origem,
             "destino": "bastidores" if n == "INFO" else "chat", "texto_final": texto if n == "INFO" else para_chat,
             "voz": n != "INFO", "resto_para_bastidores": bool(resto), "anexos": len(ficheiros) + (1 if cru else 0),
             "vigia_10min": (vigiar or {}).get("tabela")}
        registar(evento="ensaio", **{k: v for k, v in r.items() if k not in ("ok", "ensaio", "texto_final")})
        return r
    if vigiar:
        vigia_registar(vigiar)
    marca = texto
    if not marca:   # sem legenda: o anexo e' que diz se e' repetido
        h = hashlib.sha1()
        for _, dados in ficheiros:
            h.update(dados)
        if cru:
            h.update(cru[2])
        marca = "anexo:" + h.hexdigest()
    dup = ja_visto(marca, origem, n)
    if dup:
        registar(evento="duplicado-descartado", nivel=n, origem=origem, primeiro=dup.get("origem"), letras=len(texto))
        return {"ok": True, "nivel": n, "destino": "descartado", "duplicado": True, "primeiro": dup.get("origem")}
    if n == "INFO":
        return _info(texto, origem, ficheiros, cru)
    para_chat, resto = formatar(texto, n, sem_corte)
    if resto:
        _info(resto, origem + ":resto", [], None, sem_chat=True)
    chat = voz.CHAT
    ids_texto, ids_media, erro = [], [], None
    try:
        if cru:
            metodo, ctype, corpo = cru
            req = urllib.request.Request("%s/bot%s/%s" % (API, voz.CRED, metodo), data=corpo, headers={"Content-Type": ctype})
            with urllib.request.urlopen(req, timeout=120) as r:
                resp = json.loads(r.read().decode("utf-8"))
            res = resp.get("result")
            ids_media = [m.get("message_id") for m in res] if isinstance(res, list) else ([res.get("message_id")] if isinstance(res, dict) else [])
        elif ficheiros:
            if len(para_chat) > 1000:
                ids_texto = voz.enviar_texto(para_chat, chat)
            ids_media = enviar_media(chat, ficheiros, para_chat)
        else:
            ids_texto = voz.enviar_texto(para_chat, chat)
    except Exception as e:  # noqa: BLE001
        erro = str(e)[:200]
    voz_pedida = False
    if para_chat and not (cru and cru[0] in ("sendVoice", "sendAudio")) and (ids_texto or ids_media):
        voz_pedida = voz.pedir_audio(para_chat, chat, origem="porteiro:" + origem)
    ok = bool(ids_texto or ids_media) and not erro
    registar(evento="enviado" if ok else "falhou", nivel=n, porque=porque, origem=origem, letras=len(para_chat),
             ids_texto=ids_texto, ids_media=ids_media, voz_na_fila=voz_pedida, erro=erro)
    return {"ok": ok, "nivel": n, "destino": "chat", "ids_texto": ids_texto, "ids_media": ids_media,
            "voz_na_fila": voz_pedida, "erro": erro}


def _info(texto, origem, ficheiros, cru, sem_chat=False):
    dia = datetime.datetime.now(TZ).strftime("%Y-%m-%d")
    nomes = [f[0] for f in ficheiros] + ([cru[0]] if cru else [])
    linha = {"ts": agora().isoformat(timespec="seconds"), "origem": origem, "texto": texto, "anexos": nomes}
    try:
        os.makedirs(DIR, exist_ok=True)
        with open(os.path.join(DIR, "info-%s.jsonl" % dia), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(linha, ensure_ascii=False) + "\n")
    except Exception:  # noqa: BLE001
        pass
    e2e = _e2e("info:" + origem, "info", texto + (" [anexos: %s]" % ", ".join(nomes) if nomes else ""))
    b = bastidores_chat()
    ids = []
    if b:
        try:
            ids = voz.enviar_texto("[%s] %s" % (origem, texto[:3500]), b)
        except Exception as e:  # noqa: BLE001
            registar(evento="bastidores-falhou", erro=str(e)[:200])
    registar(evento="info", origem=origem, letras=len(texto), e2e=e2e, bastidores=bool(ids), ids_bastidores=ids)
    return {"ok": True, "nivel": "INFO", "destino": "bastidores" if ids else "registo", "e2e": e2e, "ids_bastidores": ids}


# ───────────────────────────── resumo 06:45 / 21:00 ─────────────────────────────

def resumo(slot, seco=False):
    try:
        with open(RESUMO_OK, encoding="utf-8") as fh:
            ok = json.load(fh)
    except Exception:  # noqa: BLE001
        ok = {}
    hoje = datetime.datetime.now(TZ).strftime("%Y-%m-%d")
    if ok.get(slot) == hoje and not seco:
        print("SALTA: resumo %s de %s ja saiu" % (slot, hoje))
        return 0
    desde = agora() - datetime.timedelta(hours=10 if slot == "manha" else 15)
    linhas = []
    for d in (desde.astimezone(TZ).strftime("%Y-%m-%d"), hoje):
        try:
            with open(os.path.join(DIR, "info-%s.jsonl" % d), encoding="utf-8") as fh:
                for ln in fh:
                    try:
                        x = json.loads(ln)
                        if datetime.datetime.fromisoformat(x["ts"]) >= desde:
                            linhas.append(x)
                    except Exception:  # noqa: BLE001
                        pass
        except OSError:
            pass
    vistos = set()
    unicas = []
    for x in linhas:
        k = (x["ts"], x["origem"])
        if k not in vistos:
            vistos.add(k)
            unicas.append(x)
    dups = 0
    try:
        with open(LOG, encoding="utf-8") as fh:
            for ln in fh:
                if '"duplicado-descartado"' in ln:
                    try:
                        if datetime.datetime.fromisoformat(json.loads(ln)["ts"]) >= desde:
                            dups += 1
                    except Exception:  # noqa: BLE001
                        pass
    except OSError:
        pass
    por = {}
    erros = []
    for x in unicas:
        o = x["origem"].split(":")[0]
        por[o] = por.get(o, 0) + 1
        if re.search(r"(?i)\b(erro|falhou|falha|nao saiu|não saiu|caiu)\b", x.get("texto") or ""):
            erros.append(o)
    hora = desde.astimezone(TZ).strftime("%Hh%M")
    if not unicas:
        corpo = ["Bastidores desde as %s: nada de novo, os robôs não precisaram de ti." % hora]
    else:
        top = sorted(por.items(), key=lambda a: -a[1])[:4]
        corpo = ["Bastidores desde as %s: %d avisos de %d rotinas, tratados entre os robôs." % (hora, len(unicas), len(por)),
                 "Mais ativos: " + ", ".join("%s (%d)" % (o.replace("_", " ").replace("-", " "), c) for o, c in top) + "."]
        if erros:
            eo = sorted(set(erros))
            corpo.append("Com erro, a tratar sozinhos: %d (%s)." % (len(erros), ", ".join(e.replace("_", " ").replace("-", " ") for e in eo[:4])))
        else:
            corpo.append("Sem erros.")
    if dups:
        corpo.append("Avisos repetidos que não te mandei: %d." % dups)
    corpo.append("O detalhe está no grupo Bora Bastidores." if bastidores_chat() else "O detalhe fica guardado no registo do sistema.")
    texto = "\n".join(corpo[:5])
    if seco:
        print("--- ENSAIO ---\n" + texto)
        return 0
    r = telegram_danilo(texto, "RESULTADO", "porteiro-resumo-" + slot, sem_corte=True)
    print(json.dumps(r, ensure_ascii=False))
    if r.get("ok") or r.get("duplicado"):
        ok[slot] = hoje
        with open(RESUMO_OK, "w", encoding="utf-8") as fh:
            json.dump(ok, fh)
    return 0 if r.get("ok") else 1


# ───────────────────────────── espelho da API ─────────────────────────────

def _campos(ctype, corpo, query):
    """Le os campos de um pedido da API (form, json ou multipart). Devolve (campos:str->str, ficheiros:[(campo,nome,bytes)])."""
    campos = {k: v[0] for k, v in urllib.parse.parse_qs(query or "", keep_blank_values=True).items()}
    ficheiros = []
    ct = (ctype or "").lower()
    try:
        if "application/json" in ct:
            for k, v in (json.loads(corpo.decode("utf-8") or "{}") or {}).items():
                campos[k] = v if isinstance(v, str) else json.dumps(v)
        elif "multipart/form-data" in ct:
            msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                b"Content-Type: " + ctype.encode("latin-1") + b"\r\n\r\n" + corpo)
            for parte in msg.iter_parts():
                nome = parte.get_param("name", header="content-disposition")
                fn = parte.get_param("filename", header="content-disposition")
                dados = parte.get_payload(decode=True) or b""
                if fn:
                    ficheiros.append((nome, fn, dados))
                elif nome:
                    campos[nome] = dados.decode("utf-8", "replace")
        elif corpo:
            for k, v in urllib.parse.parse_qs(corpo.decode("utf-8", "replace"), keep_blank_values=True).items():
                campos[k] = v[0]
    except Exception as e:  # noqa: BLE001
        registar(evento="espelho-nao-leu", erro=str(e)[:200])
    return campos, ficheiros


def _passar(token, metodo, query, ctype, corpo, metodo_http):
    url = "%s/bot%s/%s%s" % (API, token, metodo, ("?" + query) if query else "")
    req = urllib.request.Request(url, data=corpo if metodo_http != "GET" else None, method=metodo_http,
                                 headers={"Content-Type": ctype} if ctype else {})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def espelho(origem, token, metodo, query, ctype, corpo, metodo_http):
    """Pedidos antigos 'https://api.telegram.org/bot...' que agora vem por aqui. Devolve (status, bytes)."""
    proprio = (not token) or token == voz.CRED or not re.match(r"^\d{6,}:", token)
    if not proprio:                                   # outro bot: nao e' a porta do BoraHermesbot
        return _passar(token, metodo, query, ctype, corpo, metodo_http)
    campos, fich = _campos(ctype, corpo, query)
    chat = str(campos.get("chat_id", "")).strip()
    if chat != str(voz.CHAT) or metodo not in METODOS_TEXTO + METODOS_MEDIA:
        return _passar(voz.CRED, metodo, query, ctype, corpo, metodo_http)
    ens = str(campos.get("ensaio", "")).lower() in ("1", "true", "sim")
    if metodo in METODOS_TEXTO:
        r = telegram_danilo(campos.get("text", ""), campos.get("nivel"), origem, ensaio=ens)
    else:
        legenda = campos.get("caption", "")
        if metodo == "sendMediaGroup" and not legenda:
            try:
                legenda = next((m.get("caption") for m in json.loads(campos.get("media", "[]")) if m.get("caption")), "") or ""
            except Exception:  # noqa: BLE001
                legenda = ""
        r = telegram_danilo(legenda, campos.get("nivel"), origem, ficheiros=[(f[1], f[2]) for f in fich],
                            cru=(metodo, ctype, corpo), ensaio=ens)
    mid = (r.get("ids_texto") or r.get("ids_media") or [0])[0]
    res = {"message_id": mid, "chat": {"id": int(chat) if chat.lstrip("-").isdigit() else chat, "type": "private"},
           "date": int(time.time()), "text": campos.get("text", "")}
    corpo_r = {"ok": bool(r.get("ok")), "result": [res] if metodo == "sendMediaGroup" else res, "porteiro": r}
    if not r.get("ok"):
        corpo_r["description"] = "porteiro: " + str(r.get("erro") or r.get("porque") or "falhou")
    return (200 if r.get("ok") else 502), json.dumps(corpo_r, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


# ───────────────────────────── servidor ─────────────────────────────

def _ficheiros_json(lista):
    out = []
    for f in lista or []:
        try:
            if f.get("b64"):
                out.append((os.path.basename(f.get("nome") or "anexo.bin"), base64.b64decode(f["b64"])))
            elif f.get("caminho") and str(f["caminho"]).startswith("/opt/data/"):
                with open(f["caminho"], "rb") as fh:
                    out.append((os.path.basename(f["caminho"]), fh.read()))
        except Exception as e:  # noqa: BLE001
            registar(evento="anexo-nao-lido", erro=str(e)[:150])
    return out


class _Base(BaseHTTPRequestHandler):
    publico = False
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _resp(self, status, corpo, ctype="application/json"):
        if isinstance(corpo, (dict, list)):
            corpo = json.dumps(corpo, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def _corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _tratar(self, metodo_http):
        caminho, _, query = self.path.partition("?")
        if caminho == "/saude":
            return self._resp(200, b"ok", "text/plain")
        corpo = self._corpo() if metodo_http != "GET" else b""
        if caminho == "/telegram_danilo" and metodo_http == "POST":
            if self.publico:
                seg = conf().get("PORTEIRO_SEGREDO", "")
                if not seg or not hmac.compare_digest(seg, self.headers.get("X-Porteiro-Segredo", "")):
                    registar(evento="recusado-sem-segredo", ip=self.headers.get("X-Forwarded-For") or self.client_address[0])
                    return self._resp(401, {"ok": False, "porque": "sem segredo"})
            try:
                j = json.loads(corpo.decode("utf-8") or "{}")
            except Exception:  # noqa: BLE001
                return self._resp(400, {"ok": False, "porque": "json invalido"})
            origem = j.get("origem") or ("publico" if self.publico else "local")
            r = telegram_danilo(j.get("texto", ""), j.get("nivel"), origem, _ficheiros_json(j.get("ficheiros")),
                                ensaio=bool(j.get("ensaio")))
            return self._resp(200 if r.get("ok") else 502, r)
        m = re.match(r"^/o/([\w.\-]+)/bot([^/]*)/(\w+)$", caminho)
        if m and not self.publico:
            st, b = espelho(m.group(1), m.group(2), m.group(3), query, self.headers.get("Content-Type", ""), corpo, metodo_http)
            return self._resp(st, b)
        return self._resp(404, {"ok": False, "porque": "nao existe"})

    def do_GET(self):
        self._tratar("GET")

    def do_POST(self):
        self._tratar("POST")


class _Publico(_Base):
    publico = True


def _supa(metodo, caminho, corpo=None):
    sys.path.insert(0, "/opt/data/rotinas")
    from comum import SUPA_URL, SUPA_KEY, CTX  # noqa: E402
    h = {"apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY, "Content-Type": "application/json",
         "Prefer": "return=minimal"}
    req = urllib.request.Request(SUPA_URL + "/rest/v1/" + caminho, method=metodo, headers=h,
                                 data=json.dumps(corpo).encode("utf-8") if corpo is not None else None)
    with urllib.request.urlopen(req, timeout=20, context=CTX) as r:
        t = r.read().decode("utf-8")
        return json.loads(t) if t else None


def vigiar_entrada():
    """Fila da base para o porteiro: a Edge notify-admin-urgent (alertas da base) escreve em public.porteiro_entrada
    (so service_role) e o porteiro trata de 10 em 10 s. Sem porta aberta a internet. Se a tabela ainda nao existir
    (migracao por publicar), espera 5 min e tenta outra vez, calado."""
    falhas = 0
    while True:
        espera = 10
        try:
            linhas = _supa("GET", "porteiro_entrada?select=id,origem,nivel,texto&tratado_em=is.null&order=id.asc&limit=10") or []
            falhas = 0
            for x in linhas:
                r = telegram_danilo(x.get("texto"), x.get("nivel"), x.get("origem") or "notify-admin-urgent")
                _supa("PATCH", "porteiro_entrada?id=eq.%d&tratado_em=is.null" % int(x["id"]),
                      {"tratado_em": agora().isoformat(), "resultado": {k: r.get(k) for k in ("ok", "nivel", "destino", "ids_texto", "duplicado", "erro")}})
        except urllib.error.HTTPError as e:
            falhas += 1
            if falhas == 1:
                registar(evento="entrada-indisponivel", http=e.code)
            espera = 300
        except Exception as e:  # noqa: BLE001
            falhas += 1
            if falhas in (1, 10):
                registar(evento="entrada-falhou", erro=str(e)[:200])
            espera = 60
        time.sleep(espera)


# ───────────────────────────── vigia dos 10 min (regra 08/11) ─────────────────────────────

_trinco_vigia = threading.Lock()


def _vigia_ler():
    try:
        with open(VIGIA, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001
        return []


def _vigia_gravar(itens):
    os.makedirs(DIR, exist_ok=True)
    tmp = VIGIA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(itens[-300:], fh, ensure_ascii=False)
    os.replace(tmp, VIGIA)


def vigia_registar(item):
    """Guarda um pedido/corrida/limpeza novo para rever daqui a VIGIA_MIN minutos. Repetidos nao entram."""
    with _trinco_vigia:
        itens = _vigia_ler()
        if any(i.get("tabela") == item["tabela"] and i.get("id8") == item["id8"] for i in itens):
            return False
        t = agora()
        itens.append(dict(item, desde=t.isoformat(timespec="seconds"),
                          rever_em=(t + datetime.timedelta(minutes=VIGIA_MIN)).isoformat(timespec="seconds")))
        _vigia_gravar(itens)
    registar(evento="vigia-registado", tabela=item["tabela"], id8=item["id8"])
    return True


def _filtro_id(id8):
    # ids sao uuid (ou texto com forma de uuid): o intervalo serve aos dois e nao precisa de LIKE.
    return "id=gte.%s-0000-0000-0000-000000000000&id=lte.%s-ffff-ffff-ffff-ffffffffffff" % (id8, id8)


def vigia_verificar(item, linha, agora_):
    """Pura (prova sem base): ('fim'|'esperar'|'alertar', motivo, rever_em|None) para um item do vigia."""
    if not linha:
        return "fim", "nao encontrado na base", None
    if str(linha.get("status") or "") in item["fim"]:
        return "fim", "estado " + str(linha.get("status")), None
    if linha.get(item["quem"]):
        return "fim", "ja tem quem faca", None
    hora = linha.get(item["hora"])
    if hora:
        try:
            h = datetime.datetime.fromisoformat(str(hora).replace("Z", "+00:00"))
            if h.tzinfo is None:
                h = h.replace(tzinfo=datetime.timezone.utc)
            limite = h - datetime.timedelta(minutes=item.get("antes_min", 20))
            if limite > agora_:
                return "esperar", "marcado para " + h.astimezone(TZ).strftime("%d/%m %H:%M"), limite
        except ValueError:
            pass
    return "alertar", "sem ninguem", None


def texto_alerta_vigia(item, agora_):
    quem = {"orders": "estafeta", "tvde_rides": "motorista", "cleaning_bookings": "limpadora"}.get(item["tabela"], "ninguem")
    try:
        minutos = int((agora_ - datetime.datetime.fromisoformat(item["desde"])).total_seconds() // 60)
    except Exception:  # noqa: BLE001
        minutos = VIGIA_MIN
    return "%s\nSem %s ha %d min. #%s" % (item.get("titulo") or "Pedido", quem, minutos, item["id8"])


def vigiar_pedidos():
    """De minuto a minuto: pedido/corrida/limpeza que desceu a INFO e ao fim de 10 min (ou perto da hora marcada) ainda
    nao tem quem o faca -> URGENTE (caso 1 da regra 08/11). So le a base (GET)."""
    while True:
        try:
            agora_ = agora()
            with _trinco_vigia:
                itens = _vigia_ler()
            ficam, alertas = [], []
            for it in itens:
                try:
                    rever = datetime.datetime.fromisoformat(it["rever_em"])
                except Exception:  # noqa: BLE001
                    continue
                if rever > agora_:
                    ficam.append(it)
                    continue
                try:
                    linhas = _supa("GET", "%s?select=id,status,%s,%s&%s&limit=1" % (
                        it["tabela"], it["quem"], it["hora"], _filtro_id(it["id8"]))) or []
                except Exception as e:  # noqa: BLE001
                    registar(evento="vigia-leitura-falhou", tabela=it["tabela"], id8=it["id8"], erro=str(e)[:150])
                    ficam.append(it)
                    continue
                acao, motivo, novo = vigia_verificar(it, linhas[0] if linhas else None, agora_)
                registar(evento="vigia-" + acao, tabela=it["tabela"], id8=it["id8"], motivo=motivo)
                if acao == "esperar":
                    ficam.append(dict(it, rever_em=novo.isoformat(timespec="seconds")))
                elif acao == "alertar":
                    alertas.append(it)
            with _trinco_vigia:
                vistos = {(i.get("tabela"), i.get("id8")) for i in itens}
                _vigia_gravar(ficam + [i for i in _vigia_ler() if (i.get("tabela"), i.get("id8")) not in vistos])
            for it in alertas:
                telegram_danilo(texto_alerta_vigia(it, agora_), "URGENTE", "vigia-10min")
        except Exception as e:  # noqa: BLE001
            registar(evento="vigia-falhou", erro=str(e)[:200])
        time.sleep(60)


def servir():
    threading.Thread(target=vigiar_entrada, daemon=True).start()
    threading.Thread(target=vigiar_pedidos, daemon=True).start()
    servidores = []
    for host, porta, cls in [(h, PORTA_LOCAL, _Base) for h in HOSTS_LOCAIS] + [("127.0.0.1", PORTA_PUBLICA, _Publico)]:
        try:
            s = ThreadingHTTPServer((host, porta), cls)
            s.daemon_threads = True
            servidores.append(s)
            threading.Thread(target=s.serve_forever, daemon=True).start()
            registar(evento="a-ouvir", host=host, porta=porta)
        except Exception as e:  # noqa: BLE001
            registar(evento="nao-abriu", host=host, porta=porta, erro=str(e)[:150])
    if not servidores:
        return 1
    while True:
        time.sleep(3600)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1
    if a[0] == "--servir":
        return servir()
    if a[0] == "--resumo":
        return resumo(a[1] if len(a) > 1 else "manha", "--seco" in a)
    if a[0] == "--bastidores":
        print(json.dumps({"bastidores_chat": bastidores_chat() or None}))
        return 0
    if a[0] == "danilo" and len(a) >= 2:
        nivel, origem, fotos, fich, resto, ens = a[1], "linha-de-comando", [], None, [], False
        i = 2
        while i < len(a):
            if a[i] == "--ensaio":
                ens = True; i += 1; continue
            if a[i] == "--origem" and i + 1 < len(a):
                origem = a[i + 1]; i += 2; continue
            if a[i] == "--foto" and i + 1 < len(a):
                fotos.append(a[i + 1]); i += 2; continue
            if a[i] == "-f" and i + 1 < len(a):
                fich = a[i + 1]; i += 2; continue
            resto.append(a[i]); i += 1
        if fich:
            texto = open(fich, encoding="utf-8").read()
        elif resto == ["-"]:
            texto = sys.stdin.buffer.read().decode("utf-8", "replace")
        else:
            texto = " ".join(resto)
        anexos = []
        for p in fotos:
            with open(p, "rb") as fh:
                anexos.append((os.path.basename(p), fh.read()))
        r = telegram_danilo(texto, nivel, origem, anexos, ensaio=ens)
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r.get("ok") else 1
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
