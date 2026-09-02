#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""servidor_cerebro.py v2 — o servidor local do cerebro do WhatsApp da loja (missao 02/09/2026).

A porta (extensao do Chrome no PC, ou o Baileys na VPS) entrega EVENTOS crus -- uma mensagem de
cada vez, com o id do WhatsApp, o tipo (texto/audio/imagem) e o nome guardado se houver -- e
vem buscar as respostas a fila de saida. O cerebro (cerebro/agente.py) decide com ferramentas.

O que mudou face ao v1 (ver provas/whatsapp-2026-09-02/diagnostico.md):
  - BUFFER de 9 s por pessoa: mensagens seguidas viram uma so; dedup por id de mensagem
    (local + tranca partilhada no Supabase, para as duas portas nunca responderem a mesma).
  - NUNCA SILENCIO: dinheiro/reclamacao/falta acusam recepcao e escalam; se o modelo cair,
    sai uma frase e uma tarefa; a VIGIA cumpre os prazos (promessa = tarefa).
  - Quem envia continua a ser a porta; aqui so se decide e se guarda TUDO (jsonl + Supabase).

ENVIO DESLIGADO (regra de arranque, Danilo 02/09): enquanto existir o ficheiro ENVIO_DESLIGADO
ao lado deste, nada sai por esta porta e nada se calcula para mensagens reais (so se regista).
Liga-se apagando o ficheiro E pondo whatsapp_settings.envio_ligado=true. Duas trancas, uma conta:
a porta so envia quando as duas dizem sim.

Endpoints (127.0.0.1:8790):
  GET  /saude        estado, cadeia de modelos, se ha censo pedido
  POST /evento       {numero,msg_id,tipo,texto,nome_guardado,grupo,audio_b64,imagem_b64,mime,ts,dir}
  GET  /pendentes    fila de saida -> [{id,numero,texto,motivo}]
  POST /enviado      {id,ok,erro}
  POST /prova        {numero,msg,audio_path?} -> decisao completa SEM enviar (provas da missao)
  POST /responder    compat v1 (sincrono) -> {acao,texto,aviso_danilo}
  POST /censo        {numero,nome_guardado,grupo,mensagens:[...]} -> ficha a partir do historico
  POST /correcao     {texto}   POST /pausar {numero,minutos,assumir}   POST /retomar {numero}
  GET  /lembretes    compat -> []
"""
import base64
import datetime
import json
import os
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
from cerebro import agente, fichas, manual, modelos, supa, tarefas, telegram  # noqa: E402

LOG = os.path.join(BASE, "atendimento-log.jsonl")
AUDIOS = os.path.join(BASE, "audios")
IMAGENS = os.path.join(BASE, "imagens")
PORT = int(os.environ.get("CEREBRO_PORT", "8790"))
PORTA = os.environ.get("CEREBRO_PORTA", "pc-extensao")
FLAG_ENVIO_DESLIGADO = os.path.join(BASE, "ENVIO_DESLIGADO")
FLAG_CENSO = os.path.join(BASE, "PEDIR_CENSO")
JANELA_S = 9.0
ESPACO_MIN_ENVIO_S = 4.0


def envio_desligado():
    """Duas trancas: o ficheiro local (esta porta) e o interruptor partilhado (painel admin)."""
    if os.path.exists(FLAG_ENVIO_DESLIGADO):
        return True
    ligado = supa.definicao("envio_ligado", None)
    if ligado is None:          # Supabase em baixo: o ficheiro decide sozinho
        return False
    return not bool(ligado)


# --- auditoria ------------------------------------------------------------
_loglock = threading.Lock()


def registar(obj):
    obj = dict(obj)
    obj["ts"] = datetime.datetime.now().isoformat(timespec="seconds")
    try:
        with _loglock:
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except OSError:
        pass


# --- fila de saida ----------------------------------------------------------
_saida = []
_saida_lock = threading.Lock()
_ultimo_envio = 0.0


def emitir(numero, texto, motivo):
    if not texto:
        return None
    if envio_desligado():
        registar({"evento": "saida-suprimida", "numero": numero, "texto": texto[:300], "motivo": motivo, "envio_desligado": True})
        return None
    item = {"id": str(uuid.uuid4()), "numero": numero, "texto": texto, "motivo": motivo,
            "criada": datetime.datetime.now().isoformat(timespec="seconds")}
    with _saida_lock:
        _saida.append(item)
    registar({"evento": "saida-em-fila", "numero": numero, "texto": texto[:300], "motivo": motivo})
    return item["id"]


def avisar(texto):
    ok, det = telegram.enviar(texto, registar)
    return ok


# --- dedup e trancas --------------------------------------------------------
_vistos = set()
_vistos_lock = threading.Lock()


def tranca(msg_id):
    """True se esta porta ficou com a mensagem; False se ja foi vista (aqui ou pela outra porta)."""
    if not msg_id:
        return True
    with _vistos_lock:
        if msg_id in _vistos:
            return False
        _vistos.add(msg_id)
        if len(_vistos) > 5000:
            _vistos.clear()
    try:
        supa.insert("whatsapp_locks", {"msg_id": msg_id, "porta": PORTA}, devolve=False)
        return True
    except supa.SupaErro as e:
        if "23505" in str(e) or "409" in str(e) or "duplicate" in str(e).lower():
            registar({"evento": "tranca-outra-porta", "msg_id": msg_id})
            return False
        return True            # Supabase em baixo: nao se trava o atendimento
    except Exception:
        return True


# --- buffer de entrada (agrupa mensagens seguidas) --------------------------
_buffer = {}
_buffer_lock = threading.Lock()


def _guardar_media(b64, mime, pasta, prefixo):
    if not b64:
        return None
    os.makedirs(pasta, exist_ok=True)
    ext = {"audio/ogg": ".ogg", "audio/mpeg": ".mp3", "audio/mp4": ".m4a", "audio/webm": ".webm", "audio/wav": ".wav",
           "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}.get((mime or "").split(";")[0], ".bin")
    caminho = os.path.join(pasta, "%s-%s%s" % (prefixo, datetime.datetime.now().strftime("%Y%m%d-%H%M%S"), ext))
    try:
        open(caminho, "wb").write(base64.b64decode(b64))
        return caminho
    except Exception:
        return None


def receber(ev):
    numero = fichas.so_digitos(ev.get("numero"))
    msg_id = ev.get("msg_id")
    if ev.get("grupo") or "@g.us" in str(msg_id or ""):
        registar({"evento": "ignorar-grupo", "msg_id": msg_id})
        return {"ok": True, "acao": "ignorar-grupo"}
    if not tranca(msg_id):
        return {"ok": True, "acao": "ja-vista"}
    if (ev.get("dir") or "entrada") == "saida-danilo":
        return _danilo_respondeu(numero, ev.get("texto") or "")
    tipo = ev.get("tipo") or "texto"
    pedaco = {"msg_id": msg_id, "tipo": tipo, "texto": ev.get("texto") or "", "ts": ev.get("ts")}
    if tipo == "audio":
        pedaco["audio"] = _guardar_media(ev.get("audio_b64"), ev.get("mime") or "audio/ogg", AUDIOS, numero)
    if tipo == "imagem":
        pedaco["imagem"] = _guardar_media(ev.get("imagem_b64"), ev.get("mime") or "image/jpeg", IMAGENS, numero)
    registar({"evento": "entrada", "numero": numero, "msg_id": msg_id, "tipo": tipo, "texto": (ev.get("texto") or "")[:300],
              "nome_guardado": ev.get("nome_guardado")})
    if envio_desligado():
        # regra de arranque: nao se calcula nada para mensagens reais; fica registado
        try:
            supa.insert("whatsapp_messages", {"msg_id": msg_id, "numero": numero, "direcao": "entrada", "porta": PORTA, "tipo": tipo,
                                              "texto": (ev.get("texto") or "")[:2000], "decisao": "silencio-missao"}, devolve=False)
        except Exception:
            pass
        return {"ok": True, "acao": "silencio-missao"}
    with _buffer_lock:
        b = _buffer.get(numero)
        if not b:
            b = {"pedacos": [], "nome_guardado": ev.get("nome_guardado"), "timer": None}
            _buffer[numero] = b
        b["pedacos"].append(pedaco)
        if ev.get("nome_guardado"):
            b["nome_guardado"] = ev["nome_guardado"]
        if b["timer"]:
            b["timer"].cancel()
        b["timer"] = threading.Timer(JANELA_S, _processar, args=(numero,))
        b["timer"].daemon = True
        b["timer"].start()
    return {"ok": True, "acao": "em-buffer", "janela_s": JANELA_S}


def _evento_de(numero, b):
    return {"numero": numero, "porta": PORTA, "nome_guardado": b.get("nome_guardado"),
            "msg_ids": [p["msg_id"] for p in b["pedacos"]],
            "textos": [p["texto"] for p in b["pedacos"] if p["tipo"] == "texto"],
            "audios": [p["audio"] for p in b["pedacos"] if p.get("audio")],
            "imagens": [p["imagem"] for p in b["pedacos"] if p.get("imagem")],
            "ts": b["pedacos"][-1].get("ts")}


def _processar(numero):
    with _buffer_lock:
        b = _buffer.pop(numero, None)
    if not b:
        return
    evento = _evento_de(numero, b)
    try:
        dec = agente.atender(evento, registar, emitir=emitir)
    except Exception as e:  # noqa: BLE001
        registar({"evento": "agente-erro", "numero": numero, "erro": "%s: %s" % (type(e).__name__, str(e)[:300])})
        t = tarefas.criar(numero, "erro do agente: " + str(e)[:80], 3, "servidor")
        avisar("WhatsApp da loja — ERRO no cerebro com %s: %s" % (numero, str(e)[:200]))
        dec = {"acao": "responder", "textos": ["Recebi a sua mensagem. Estou a ver isso e dou-lhe resposta em 3 minutos, no máximo."],
               "motivo": "erro", "tarefas": [t["id"]]}
    registar({"evento": "decisao", "numero": numero, "acao": dec.get("acao"), "textos": dec.get("textos"), "modelo": dec.get("modelo"),
              "ferramentas": dec.get("ferramentas"), "tarefas": dec.get("tarefas"), "segundos": dec.get("segundos"), "erro": dec.get("erro")})
    ids = [emitir(numero, t, dec.get("acao")) for t in (dec.get("textos") or [])] if dec.get("acao") in ("responder", "escalar") else []
    agente.registar_mensagens(evento, dec, enviada=False, porta=PORTA)
    return dec


def _danilo_respondeu(numero, texto):
    """O Danilo respondeu a mao: guarda o tom como exemplo e cala o bot 2 h neste contacto."""
    f = fichas.carregar(numero)
    f.pop("_nova", None)
    ate = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=2)).isoformat(timespec="seconds")
    f["bot_pausado"], f["bot_pausado_ate"], f["bot_pausado_por"] = True, ate, "danilo respondeu à mão"
    fichas.guardar(f)
    if texto and len(texto) > 12:
        manual.registar_correcao("exemplo de tom do Danilo (para " + numero[-3:] + "): \"" + texto[:200] + "\"", "danilo-a-mao")
    tarefas.cumprir_todas(numero, "o Danilo respondeu à mão")
    registar({"evento": "danilo-respondeu", "numero": numero, "texto": texto[:200], "bot_pausado_ate": ate})
    return {"ok": True, "acao": "bot-pausado-2h"}


# --- censo (fichas a partir do historico, sem responder) ---------------------
def censo(d):
    numero = fichas.so_digitos(d.get("numero"))
    if d.get("grupo") or not numero or numero == agente.OWN:
        return {"ok": True, "acao": "ignorado"}
    msgs = d.get("mensagens") or []
    registar({"evento": "censo-inicio", "numero": numero, "mensagens": len(msgs)})
    f = fichas.carregar(numero)
    f.pop("_nova", None)
    if d.get("nome_guardado") and not f.get("nome"):
        f["nome"], f["nome_fonte"] = d["nome_guardado"][:80], "contacto_guardado"
    fichas.cruzar_supabase(f)
    entradas = [m for m in msgs if (m.get("dir") == "entrada") and (m.get("texto") or "").strip()]
    for m in entradas[-6:]:
        fichas.anotar_pedido(f, m["texto"][:120])
    if msgs:
        f["primeira_msg_em"] = f.get("primeira_msg_em") or msgs[0].get("ts")
        f["ultima_msg_em"] = msgs[-1].get("ts") or f.get("ultima_msg_em")
    from cerebro import identidade
    ult = " ".join(m.get("texto") or "" for m in entradas[-5:])
    if ult:
        fichas.aprender_estilo(f, ult, identidade.lingua(ult, f.get("lingua")), identidade.registo(ult, f.get("registo")))
        identidade.decidir_tratamento(f, ult)
    sem_resposta = bool(entradas) and (msgs[-1].get("dir") == "entrada") and not agente.RE_ACK.match(msgs[-1].get("texto") or "")
    f["notas"] = ((f.get("notas") or "") + ("\n- censo 02/09: última mensagem deles sem resposta" if sem_resposta else "")).strip() or None
    fichas.guardar(f)
    n = 0
    linhas = [{"msg_id": m.get("id"), "numero": numero, "direcao": "saida" if m.get("dir") == "saida" else "entrada",
               "porta": "censo", "tipo": m.get("tipo") or "texto", "texto": (m.get("texto") or "")[:2000],
               "ts_whatsapp": m.get("ts"), "decisao": "historico"} for m in msgs[-150:] if m.get("id")]
    try:
        supa.upsert_muitos("whatsapp_messages", linhas, "msg_id")     # uma chamada, nao 150
        n = len(linhas)
    except Exception as e:  # noqa: BLE001
        registar({"evento": "censo-mensagens-erro", "numero": numero, "erro": str(e)[:200]})
    registar({"evento": "censo", "numero": numero, "mensagens": len(msgs), "guardadas": n, "sem_resposta": sem_resposta, "papel": f.get("papel")})
    return {"ok": True, "papel": f.get("papel"), "nome": f.get("nome"), "sem_resposta": sem_resposta}


# --- crons ----------------------------------------------------------------------
def _cron():
    ultimo_atrasos = ultimo_seguimentos = ultimo_revisao = 0
    while True:
        try:
            agora = time.time()
            if agora - ultimo_atrasos > 120:
                ultimo_atrasos = agora
                if not envio_desligado():
                    from cerebro import ferramentas_bot as FB
                    media, n = FB._media_entrega_min()
                    for o in tarefas.pedidos_atrasados(media if n >= 3 else 45):
                        emitir(fichas.so_digitos(o["client_phone"]),
                               "Olá! O seu pedido está a demorar mais do que o normal — peço desculpa. Estamos a tratar dele e "
                               "aviso-o assim que sair. Se preferir, é só dizer.", "cron:atraso-pedido")
                        avisar("WhatsApp da loja — pedido %s (%s) ha %s min, acima da media (%s). Avisei o cliente." % (
                            o["id"][:8], o.get("vendor_name"), o.get("minutos"), round(media)))
            if agora - ultimo_seguimentos > 600:
                ultimo_seguimentos = agora
                if not envio_desligado():
                    for l in tarefas.seguimentos_24h():
                        emitir(l["numero"], "Olá! Continuo por aqui para montar a sua loja no Bora, sem pressa nenhuma. "
                                            "Quando quiser retomar, é só responder por aqui.", "cron:seguimento-24h")
                        tarefas.marcar_lembrete(l["id"])
            h = datetime.datetime.now()
            if h.hour == 6 and h.minute < 5 and agora - ultimo_revisao > 3600 * 20:
                ultimo_revisao = agora
                threading.Thread(target=auto_revisao, daemon=True).start()
        except Exception as e:  # noqa: BLE001
            registar({"evento": "cron-erro", "erro": str(e)[:200]})
        time.sleep(30)


def auto_revisao():
    """Rele as conversas do dia, classifica cada resposta do bot e escreve as licoes; digest ao Danilo."""
    ontem = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=24)).isoformat(timespec="seconds")
    try:
        rows = supa.select("whatsapp_messages", select="numero,direcao,texto,decisao,created_at", created_at="gt." + ontem,
                           order="created_at.asc", limit="400")
    except Exception as e:  # noqa: BLE001
        registar({"evento": "auto-revisao-erro", "erro": str(e)[:200]})
        return
    if not rows:
        avisar("WhatsApp da loja — revisão diária: nenhuma conversa nas últimas 24 h.")
        return
    conversas = {}
    for r in rows:
        conversas.setdefault(r["numero"], []).append(("BOT" if r["direcao"] == "saida" else "PESSOA") + ": " + (r.get("texto") or "")[:200])
    texto = "\n\n".join("### %s\n%s" % (n[-3:], "\n".join(ls[-14:])) for n, ls in list(conversas.items())[:12])
    r = modelos.chat([{"role": "system", "content": "Es o revisor do atendimento do Bora. Para cada resposta do BOT diz: boa / fraca / errada + uma linha porque. No fim, 3 licoes curtas e accionaveis. Portugues, sem markdown."},
                      {"role": "user", "content": texto[:9000]}], max_tokens=700)
    saida = r.get("texto") or ("(revisor sem resposta: %s)" % r.get("erro"))
    for ln in [l.strip("-• ").strip() for l in saida.split("\n") if l.strip()][-3:]:
        manual.registar_licao(ln[:220])
    rep = manual.perguntas_repetidas(2)
    digest = "Revisão diária do WhatsApp da loja: %d conversas, %d mensagens. %s%s" % (
        len(conversas), len(rows), saida[-600:], ("\n\nPerguntas que se repetem e precisam de ti: " + "; ".join(p for _n, p in rep[:5])) if rep else "")
    avisar(digest)
    registar({"evento": "auto-revisao", "conversas": len(conversas), "mensagens": len(rows)})


# --- HTTP -------------------------------------------------------------------------
class H(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/saude"):
            pedir = os.path.exists(FLAG_CENSO)
            return self._json(200, {"ok": True, "servico": "cerebro-whatsapp", "versao": "v2-agente-2026-09-02", "porta": PORTA,
                                    "envio_desligado": envio_desligado(), "envio_ligado_supabase": supa.definicao("envio_ligado"),
                                    "cadeia": modelos.estado(), "ollama": modelos.ollama_vivo(), "pedir_censo": pedir,
                                    "em_buffer": len(_buffer), "em_fila": len(_saida)})
        if self.path.startswith("/pendentes"):
            global _ultimo_envio
            if envio_desligado():
                with _saida_lock:
                    _saida.clear()
                return self._json(200, {"mensagens": []})
            with _saida_lock:
                if not _saida or time.time() - _ultimo_envio < ESPACO_MIN_ENVIO_S:
                    return self._json(200, {"mensagens": []})
                item = _saida.pop(0)
                _ultimo_envio = time.time()
            return self._json(200, {"mensagens": [item]})
        if self.path.startswith("/lembretes"):
            return self._json(200, {"lembretes": []})
        if self.path.startswith("/estado"):
            return self._json(200, {"tarefas_abertas": len(tarefas.abertas()), "em_fila": len(_saida), "cadeia": modelos.estado()})
        return self._json(404, {"erro": "nao encontrado"})

    def do_POST(self):
        d = self._corpo()
        try:
            if self.path.startswith("/evento"):
                return self._json(200, receber(d))
            if self.path.startswith("/enviado"):
                registar({"evento": "enviado" if d.get("ok") else "envio-falhou", "id": d.get("id"), "numero": d.get("numero"), "erro": d.get("erro")})
                if d.get("ok"):
                    try:
                        supa.update("whatsapp_messages", {"enviada": True, "enviada_em": datetime.datetime.now(datetime.timezone.utc).isoformat()},
                                    numero="eq." + fichas.so_digitos(d.get("numero")), texto="eq." + (d.get("texto") or ""), enviada="is.false")
                    except Exception:
                        pass
                return self._json(200, {"ok": True})
            if self.path.startswith("/prova"):
                numero = fichas.so_digitos(d.get("numero"))
                ev = {"numero": numero, "porta": "prova", "nome_guardado": d.get("nome_guardado"), "grupo": bool(d.get("grupo")),
                      "msg_ids": [d.get("msg_id") or "prova_" + str(uuid.uuid4())],
                      "textos": [d.get("msg")] if d.get("msg") else [],
                      "audios": [d["audio_path"]] if d.get("audio_path") else [], "imagens": [d["imagem_path"]] if d.get("imagem_path") else []}
                if d.get("audio_b64"):
                    ev["audios"].append(_guardar_media(d["audio_b64"], d.get("mime") or "audio/ogg", AUDIOS, "prova-" + numero))
                from cerebro import ferramentas_bot as FB
                FB.ATRASO_PROVA = float(d.get("atraso_ferramenta_s") or 0)
                try:
                    dec = agente.atender(ev, registar, modo_prova=True)
                finally:
                    FB.ATRASO_PROVA = 0.0
                    telegram.SILENCIO = False
                registar({"evento": "prova", "numero": numero, "msg": d.get("msg"), "acao": dec.get("acao"), "textos": dec.get("textos"),
                          "modelo": dec.get("modelo"), "ferramentas": dec.get("ferramentas"), "segundos": dec.get("segundos")})
                agente.registar_mensagens(ev, dec, enviada=False, porta="prova")
                return self._json(200, dec)
            if self.path.startswith("/responder"):
                # compat v1: sincrono, nunca envia daqui; se o envio esta desligado devolve silencio sem calcular
                if envio_desligado():
                    registar({"evento": "responder", "numero": d.get("numero"), "msg": (d.get("msg") or "")[:300], "acao": "silencio-missao", "envio_desligado": True})
                    return self._json(200, {"acao": "silencio-missao", "texto": "", "aviso_danilo": ""})
                numero = fichas.so_digitos(d.get("numero"))
                ev = {"numero": numero, "porta": PORTA, "msg_ids": [d.get("msg_id")] if d.get("msg_id") else [], "textos": [d.get("msg") or ""], "grupo": bool(d.get("grupo"))}
                dec = agente.atender(ev, registar)
                agente.registar_mensagens(ev, dec, enviada=False, porta=PORTA)
                acao = {"responder": "responder-sozinho", "escalar": "responder-sozinho"}.get(dec.get("acao"), dec.get("acao"))
                return self._json(200, {"acao": acao, "texto": "\n\n".join(dec.get("textos") or []), "aviso_danilo": ""})
            if self.path.startswith("/censo"):
                return self._json(200, censo(d))
            if self.path.startswith("/avisar"):
                # aviso ao Danilo a partir DESTE processo (o que a tarefa agendada arranca, sem o PATH do
                # utilizador): e a prova de que o Telegram sai do cerebro e nao so da minha shell.
                ok, det = telegram.enviar(str(d.get("texto") or "")[:500], registar)
                return self._json(200, {"ok": ok, "detalhe": det})
            if self.path.startswith("/log"):
                # a extensao manda para aqui o que escreve na consola: a consola do browser nao se ve
                # daqui, e um erro de arranque da vigia ficava invisivel (02/09).
                registar({"evento": "extensao", "versao": d.get("versao"), "linha": str(d.get("linha") or "")[:300]})
                return self._json(200, {"ok": True})
            if self.path.startswith("/correcao"):
                ok = manual.registar_correcao((d.get("texto") or "").strip())
                registar({"evento": "correcao", "texto": d.get("texto"), "ok": ok})
                return self._json(200, {"ok": bool(ok)})
            if self.path.startswith("/pausar") or self.path.startswith("/retomar"):
                numero = fichas.so_digitos(d.get("numero"))
                f = fichas.carregar(numero)
                f.pop("_nova", None)
                if self.path.startswith("/pausar"):
                    minutos = d.get("minutos")
                    f["bot_pausado"] = True
                    f["bot_pausado_ate"] = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=int(minutos))).isoformat(timespec="seconds") if minutos else None
                    f["bot_pausado_por"] = d.get("por") or "admin"
                    f["assumido_por_danilo"] = bool(d.get("assumir"))
                else:
                    f["bot_pausado"], f["bot_pausado_ate"], f["assumido_por_danilo"] = False, None, False
                fichas.guardar(f)
                registar({"evento": "pausa" if self.path.startswith("/pausar") else "retomar", "numero": numero})
                return self._json(200, {"ok": True})
            return self._json(404, {"erro": "nao encontrado"})
        except Exception as e:  # noqa: BLE001
            registar({"evento": "http-erro", "caminho": self.path, "erro": "%s: %s" % (type(e).__name__, str(e)[:300])})
            return self._json(500, {"erro": str(e)[:300]})

    def log_message(self, *a):
        pass


def aquecedor():
    """Mantem o qwen quente E com o prefixo do prompt real em cache.

    O prompt do agente (regras + indice do manual + ferramentas) anda nos 3 mil tokens; avalia-lo
    a frio num 7b em CPU leva mais de um minuto. O Ollama guarda o prefixo do ultimo prompt: se o
    aquecedor mandar o MESMO system prompt e as MESMAS ferramentas de 4 em 4 min, a chamada real
    so tem de avaliar a mensagem do cliente -- segundos, nao minutos."""
    from cerebro import ferramentas_bot as FB
    while True:
        try:
            if modelos.ollama_vivo():
                sis = agente._sistema(fichas.nova("351000000000"), "neutro", "pt-PT", "voce", PORTA)
                modelos._chamar_ollama([{"role": "system", "content": sis}, {"role": "user", "content": "ok"}],
                                       FB.DEFINICOES, 1, 0, 240)
        except Exception as e:  # noqa: BLE001
            registar({"evento": "aquecedor-erro", "erro": str(e)[:120]})
        time.sleep(240)


def main():
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    except OSError:
        print("PORTA_%d_OCUPADA — ja ha um cerebro a correr, saio." % PORT, flush=True)
        return
    registar({"evento": "arranque", "porta": PORT, "versao": "v2-agente-2026-09-02", "envio_desligado": envio_desligado()})
    threading.Thread(target=aquecedor, daemon=True).start()
    threading.Thread(target=_cron, daemon=True).start()
    tarefas.Vigia(emitir, avisar, registar).start()
    print("CEREBRO_ONLINE v2 http://127.0.0.1:%d" % PORT, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
