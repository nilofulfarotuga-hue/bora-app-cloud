"""WhatsApp da Bora (937 501 673) atendido pela MESMA assistente do telefone (27/11/2026, pedido do Danilo às 21:55:
"quero que o WhatsApp da Bora responda o cliente automaticamente, por voz e por texto, que saiba tudo o que o atendente
por telefone sabe, que aprenda com os erros, e que pare quando eu assumir").

Vive no assistente de negócio da VPS (/opt/assistente-negocio). A porta vps-baileys pergunta "é teu?" (servidor.py
/quem); o tenant "Bora" (assistant_tenants, tipo 'bora') diz que sim e assistente.atender() manda para aqui.

  - O cérebro é a Edge Function voz-cerebro (Opus, mesmas regras, ferramentas e lições do telefone) com canal=whatsapp.
  - Texto -> resposta em texto. Áudio -> resposta SÓ em nota de voz, com a mesma voz de mulher do telefone (Google
    Kore; reserva: Microsoft Raquel). Se a voz falhar, vai em texto: o cliente nunca fica sem resposta.
  - Mensagens seguidas juntam-se: espera JUNTAR_SEG sem mensagem nova e responde a todas de uma vez.
  - Conversa pessoal (amigos e família de quem gere o número) -> silêncio, fica só registada.
  - O Danilo escreveu à mão nesta conversa (dono-falou) ou carregou "Assumir" no painel -> calada (12 h ou até ele
    carregar "Devolver ao robô" em Conversas ao vivo).
  - REVER_MIN minutos depois da última mensagem, o treinador (voz-cerebro op aprender, canal whatsapp) revê a conversa,
    dá nota e escreve lições (voz_licoes, canal todos|whatsapp). Revisão em assistant_contacts.revisao_ia.

Instalar/atualizar: python3 /opt/voz/voz/whatsapp/instalar_bora_wa.py (copia este ficheiro, liga o gancho no
assistente.py e o laço de revisão no servidor.py, copia as chaves de .env para .env e reinicia o serviço).
"""
import base64
import datetime as dt
import json
import os
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid

import assistente as A
import db
import motores
import voz

JUNTAR_SEG = float(os.environ.get("BORA_WA_JUNTAR_SEG", "4"))
REVER_MIN = int(os.environ.get("BORA_WA_REVER_MIN", "30"))
CONVERSA_MIN = 60  # resposta da assistente há menos disto = a conversa continua (não volta a passar pelo filtro)
HIST_MAX = 12
GEMINI_MODELOS = [m.strip() for m in os.environ.get(
    "BORA_WA_GEMINI_TTS",
    "gemini-3.8-flash-tts,gemini-3.8-flash-lite-tts,gemini-3.1-flash-tts-preview,gemini-2.5-flash-preview-tts").split(",") if m.strip()]
VOZ_GOOGLE = os.environ.get("BORA_WA_VOZ", "Kore")
VOZ_EDGE = os.environ.get("BORA_WA_VOZ_EDGE", "pt-PT-RaquelNeural")
LOG = os.environ.get("ASSISTENTE_LOG", os.path.join(os.path.dirname(os.path.abspath(__file__)), "assistente.log"))
CLASSIFICADORES = ["porteiro:perfil:claude-classificar", "groq:openai/gpt-oss-20b", "groq:qwen/qwen3.8-27b",
                   "groq:openai/gpt-oss-120b", "gemini:gemini-3.1-flash-lite"]

_g = threading.Lock()
_timers = {}
_trancas = {}
_push = {}
_pausa_modelo = {}


def log(*a):
    linha = time.strftime("%Y-%m-%dT%H:%M:%S") + " bora_wa " + " ".join(str(x) for x in a)
    print(linha, flush=True)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(linha + "\n")
    except OSError:
        pass


def _tranca(numero):
    with _g:
        return _trancas.setdefault(numero, threading.Lock())


def _silenciado(ct):
    sil = (ct or {}).get("silenciado_ate")
    return bool(sil and A.hora_local(sil) > A.agora())


def _hhmm(iso):
    try:
        return A.hora_local(iso).strftime("%H:%M")
    except Exception:
        return ""


# ----------------------------------------------------------------------------- entrada (chamada pela porta)
def atender(t, porque, ev, simular=False):
    numero = A.so_digitos(ev.get("numero"))
    texto = (ev.get("texto") or "").strip()
    if porque == "blocklist":
        A.registar(t, numero, "entrada", texto or "[mensagem]", decisao="silencio-blocklist", msg_id_wa=ev.get("msg_id"),
                   simulado=simular)
        return {"tratado": True, "acao": "silencio-blocklist", "respostas": []}
    foi_audio, motor_ouvir = False, None
    if not texto and ev.get("audio_b64"):
        foi_audio = True
        texto, motor_ouvir, erros = voz.ouvir(ev["audio_b64"], ev.get("mime"))
        if not texto:
            A.registar(t, numero, "entrada", "[áudio que não se percebeu]", motivo="audio", decisao="audio-nao-percebido",
                       msg_id_wa=ev.get("msg_id"), simulado=simular, ferramentas={"erros": erros})
            ct = A.contacto(t, numero)
            if not _silenciado(ct):
                enviar(t, numero, "Desculpe, não consegui ouvir bem o áudio. Pode repetir, por favor?", True,
                       "audio_nao_percebido", simular)
            return {"tratado": True, "acao": "audio-nao-percebido", "respostas": []}
    if ev.get("imagem_b64"):
        texto = (texto + " " if texto else "") + "[imagem]"
    if not texto:
        return {"tratado": True, "acao": "sem-texto", "respostas": []}
    if ev.get("push_name"):
        _push[numero] = str(ev["push_name"])[:60]
    ct = A.contacto(t, numero)
    entrada = A.registar(t, numero, "entrada", ("🎤 " + texto) if foi_audio else texto, msg_id_wa=ev.get("msg_id"),
                         quoted_id=ev.get("quoted_id"), simulado=simular,
                         motivo=("audio:" + str(motor_ouvir)) if foi_audio else None)
    A.gravar_contacto(t, numero, {"ultima_msg_em": A.iso(A.agora())})
    if _silenciado(ct):
        db.atualizar("assistant_messages", f"id=eq.{entrada['id']}", {"decisao": "silencio-dono-assumiu"})
        return {"tratado": True, "acao": "silencio-dono-assumiu", "respostas": []}
    if simular:  # simulações: responde já, sem esperar por mais mensagens
        return processar(t, numero, simular=True)
    with _g:
        velho = _timers.pop(numero, None)
        if velho:
            velho.cancel()
        tm = threading.Timer(JUNTAR_SEG, _disparar, args=(t, numero))
        tm.daemon = True
        _timers[numero] = tm
        tm.start()
    return {"tratado": True, "acao": "na-fila", "respostas": []}


def _disparar(t, numero):
    with _g:
        _timers.pop(numero, None)
    try:
        r = processar(t, numero)
        log("respondeu", numero, r.get("acao"), r.get("motor") or "", r.get("ms") or "")
    except Exception as e:  # nunca deixar a thread morrer calada
        log("processar falhou", numero, repr(e)[:300])
        _avisar_equipa(numero, f"o robô do WhatsApp falhou a responder ({repr(e)[:120]})")


# ----------------------------------------------------------------------------- resposta
def processar(t, numero, simular=False):
    """Responde a todas as mensagens deste número que ainda não têm resposta (decisao vazia). Volta a ver no fim:
    o que chegou enquanto o cérebro pensava é respondido logo a seguir, com o contexto novo."""
    ultimo = {"tratado": True, "acao": "nada-pendente", "respostas": []}
    with _tranca(numero):
        for _ in range(4):
            pend = db.ler("assistant_messages",
                          f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}&direcao=eq.entrada&decisao=is.null"
                          f"&simulado=eq.{'true' if simular else 'false'}&order=id.asc&limit=20", "id,texto,created_at")
            if not pend:
                return ultimo
            ids = "(" + ",".join(str(p["id"]) for p in pend) + ")"
            ct = A.contacto(t, numero)
            if _silenciado(ct):
                db.atualizar("assistant_messages", f"id=in.{ids}", {"decisao": "silencio-dono-assumiu"})
                return {"tratado": True, "acao": "silencio-dono-assumiu", "respostas": []}
            textos = [re.sub(r"^🎤\s*", "", p["texto"] or "") for p in pend]
            em_voz = (pend[-1]["texto"] or "").startswith("🎤")
            junto = "\n".join(x for x in textos if x).strip()
            hist = ct.get("historico") or []
            em_conversa = bool(hist) and hist[-1].get("r") == "assistant" and \
                (A.agora() - A.hora_local(hist[-1]["ts"])) < dt.timedelta(minutes=CONVERSA_MIN)
            if not em_conversa:
                tipo, motor_c = classificar(ct, junto)
                if tipo == "pessoal":
                    db.atualizar("assistant_messages", f"id=in.{ids}", {"decisao": "silencio-pessoal", "modelo": motor_c})
                    A.gravar_contacto(t, numero, {"pessoal": True})
                    ultimo = {"tratado": True, "acao": "silencio-pessoal", "respostas": []}
                    continue
            ultimo = responder(t, numero, ct, hist, junto, em_voz, ids, simular)
        return ultimo


def responder(t, numero, ct, hist, junto, em_voz, ids, simular):
    t0 = time.time()
    msgs = []
    for h in hist[-HIST_MAX:]:
        papel = "user" if h.get("r") == "user" else "assistant"
        txt = (h.get("t") or "").strip()
        if not txt:
            continue
        if msgs and msgs[-1]["role"] == papel:
            msgs[-1]["content"] += "\n" + txt
        else:
            msgs.append({"role": papel, "content": txt})
    while msgs and msgs[0]["role"] != "user":
        msgs.pop(0)
    if msgs and msgs[-1]["role"] == "user":
        msgs[-1]["content"] += "\n" + junto
    else:
        msgs.append({"role": "user", "content": junto})
    dados = {"canal": "whatsapp", "telefone": numero, "conversa": f"{t['id']}:{numero}", "mensagens": msgs,
             "voz": em_voz, "push_name": _push.get(numero), "custo_acumulado_usd": 0, "teste": bool(simular),
             "chamada_id": ""}
    r, erro = {}, None
    try:
        r = cerebro("responder", dados, 120)
    except Exception as e:  # noqa: BLE001
        erro = repr(e)[:300]
    texto = (r.get("texto") or "").strip()
    acao = "respondeu" + (" (equipa avisada)" if r.get("escalado") else "")
    if not texto:
        texto = "Recebi a sua mensagem. A equipa da Bora vai responder-lhe aqui assim que possível."
        acao = "falha-cerebro-passou-a-equipa"
        _avisar_equipa(numero, f"o cérebro não respondeu ({erro or r.get('erro') or 'sem texto'}). Mensagem: {junto[:300]}")
    saida, voz_ok = enviar(t, numero, texto, em_voz, "resposta", simular)
    if em_voz and not voz_ok:
        acao += " (voz falhou: foi em texto)"
    ms = int((time.time() - t0) * 1000)
    db.atualizar("assistant_messages", f"id=in.{ids}", {"decisao": acao})
    if saida:
        db.atualizar("assistant_messages", f"id=eq.{saida['id']}", {
            "modelo": r.get("motor"), "decisao": acao, "latencia_ms": ms,
            "custo_eur": round(float(r.get("custo_usd") or 0) * 0.95, 6),
            "tokens_in": int((r.get("uso") or {}).get("input_tokens") or 0),
            "tokens_out": int((r.get("uso") or {}).get("output_tokens") or 0)})
    ct2 = db.ler("assistant_contacts", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}", "historico")
    h = (ct2[0].get("historico") if ct2 else hist) or []
    agora = A.iso(A.agora())
    h = (h + [{"r": "user", "t": junto, "ts": agora}, {"r": "assistant", "t": texto, "ts": agora}])[-HIST_MAX:]
    A.gravar_contacto(t, numero, {"historico": h, "pessoal": False})
    return {"tratado": True, "acao": acao, "respostas": [texto], "motor": r.get("motor"), "ms": ms, "erro": erro}


def cerebro(op, dados, timeout):
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/functions/v1/voz-cerebro"
    req = urllib.request.Request(url, json.dumps({"op": op, "dados": dados}).encode(),
                                 {"Content-Type": "application/json", "x-voz-token": os.environ["VOZ_SENHA"]})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"voz-cerebro {op} {e.code} {e.read().decode(errors='ignore')[:200]}")


def classificar(ct, texto):
    """negocio | pessoal. Na dúvida: negocio (a não ser que o contacto já tenha tido conversa pessoal)."""
    ja_pessoal = bool(ct.get("pessoal"))
    hist = (ct.get("historico") or [])[-4:]
    ctx = "\n".join(f"{'pessoa' if h.get('r') == 'user' else 'bora'}: {h.get('t')}" for h in hist)
    sistema = (
        "Filtras as mensagens que chegam ao WhatsApp da Bora, uma app de entregas e serviços da Guarda (clientes, "
        "estafetas, parceiros, lojas e quem quer saber da app). Responde só JSON {\"tipo\":\"negocio\"} ou {\"tipo\":\"pessoal\"}.\n"
        "negocio = tudo o que pode ser da Bora ou de quem a usa ou quer usar: pedidos, entregas, lojas, preços, registo de "
        "estafeta ou parceiro, pagamentos, reclamações, perguntas sobre a app, propostas de negócio para a Bora, "
        "cumprimentos simples (olá, bom dia, boa noite), agradecimentos e respostas curtas.\n"
        "pessoal = conversa privada com a pessoa que gere o número: família, amigos, namoro, convites pessoais, futebol, "
        "saudades, combinar encontros, assuntos de vida pessoal que nada têm a ver com a Bora.\n"
        + ("Este contacto JÁ teve conversa pessoal antes: um cumprimento solto ou uma mensagem vaga é pessoal; só é "
           "negocio se falar claramente da Bora." if ja_pessoal else "Na dúvida: negocio."))
    msgs = [{"role": "system", "content": sistema},
            {"role": "user", "content": (f"Conversa recente:\n{ctx}\n\n" if ctx else "") + f"Mensagem nova: {texto}"}]
    try:
        msg, meta = motores.conversar(CLASSIFICADORES, msgs)
        m = re.search(r'"tipo"\s*:\s*"(\w+)"', msg.get("content") or "")
        return (m.group(1) if m else ("pessoal" if ja_pessoal else "negocio")), meta and meta.get("motor")
    except motores.MotorFalhou:
        return ("pessoal" if ja_pessoal else "negocio"), None


# ----------------------------------------------------------------------------- saída (texto ou nota de voz)
def enviar(t, numero, texto, em_voz, motivo, simular):
    """Devolve (linha_da_fila, voz_ok). Áudio: SÓ a nota de voz (nada de texto antes ou depois)."""
    if em_voz:
        try:
            ogg = falar(texto)
            return A.enfileirar(t, numero, "[nota de voz] " + texto, motivo, simular, media_path=ogg), True
        except Exception as e:  # noqa: BLE001
            log("voz falhou, vai em texto", numero, repr(e)[:200])
    return A.enfileirar(t, numero, texto, motivo, simular), False


def falar(texto):
    """Nota de voz (ogg/opus mono 48 kHz) com a voz de mulher do telefone. Google primeiro, Microsoft de reserva."""
    dito = voz.para_falar(texto)
    os.makedirs(voz.PASTA_VOZ, exist_ok=True)
    base = os.path.join(voz.PASTA_VOZ, time.strftime("%Y%m%d-%H%M%S-bora-") + uuid.uuid4().hex[:8])
    ogg = base + ".ogg"
    chave = os.environ.get("GEMINI_TTS_KEY") or os.environ.get("GEMINI_API_KEY_FATURACAO")
    if chave:
        for modelo in GEMINI_MODELOS:
            if _pausa_modelo.get(modelo, 0) > time.time():
                continue
            try:
                pcm = _gemini_pcm(dito, modelo, chave)
                r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", "24000", "-ac", "1", "-i", "pipe:0",
                                    "-ac", "1", "-ar", "48000", "-c:a", "libopus", "-b:a", "32k", "-application", "voip", ogg],
                                   input=pcm, capture_output=True, timeout=60)
                if r.returncode == 0 and os.path.exists(ogg):
                    return ogg
                raise RuntimeError("ffmpeg " + (r.stderr or b"")[-150:].decode(errors="ignore"))
            except urllib.error.HTTPError as e:
                _pausa_modelo[modelo] = time.time() + (60 if e.code == 429 else 300)
                log("voz google", modelo, e.code)
            except Exception as e:  # noqa: BLE001
                _pausa_modelo[modelo] = time.time() + 30
                log("voz google", modelo, repr(e)[:150])
    mp3 = base + ".mp3"
    r = subprocess.run([voz.EDGE_TTS, "--voice", VOZ_EDGE, "--text", dito, "--write-media", mp3],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0 or not os.path.exists(mp3):
        raise RuntimeError("edge-tts falhou: " + (r.stderr or "")[-200:])
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-ac", "1", "-ar", "48000", "-c:a", "libopus",
                        "-b:a", "32k", "-application", "voip", ogg], capture_output=True, text=True, timeout=60)
    os.unlink(mp3)
    if r.returncode != 0 or not os.path.exists(ogg):
        raise RuntimeError("ffmpeg falhou: " + (r.stderr or "")[-200:])
    return ogg


def _gemini_pcm(texto, modelo, chave):
    corpo = {"contents": [{"parts": [{"text": texto}]}],
             "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {
                 "languageCode": "pt-PT", "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": VOZ_GOOGLE}}}}}
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent",
        json.dumps(corpo).encode(), {"Content-Type": "application/json", "x-goog-api-key": chave})
    with urllib.request.urlopen(req, timeout=45) as r:
        j = json.loads(r.read().decode())
    pcm = b""
    for parte in ((j.get("candidates") or [{}])[0].get("content") or {}).get("parts") or []:
        if "inlineData" in parte:
            pcm += base64.b64decode(parte["inlineData"]["data"])
    if len(pcm) < 4800:
        raise RuntimeError("google sem som")
    return pcm


def _avisar_equipa(numero, texto):
    try:
        db.inserir("porteiro_entrada", {"origem": "whatsapp-bora", "nivel": "URGENTE",
                                        "texto": f"💬 WHATSAPP DA BORA — {numero}: {texto}"[:3900]}, devolver=False)
    except Exception as e:  # noqa: BLE001
        log("aviso à equipa falhou", repr(e)[:200])


# ----------------------------------------------------------------------------- aprender com os erros
def tenant_bora():
    r = db.ler("assistant_tenants", "slug=eq.bora")
    return r[0] if r else None


def rever_conversas():
    t = tenant_bora()
    if not t:
        return 0
    agora = A.agora()
    limite = A.iso(agora - dt.timedelta(minutes=REVER_MIN))
    desde_max = A.iso(agora - dt.timedelta(days=2))
    cts = db.ler("assistant_contacts",
                 f"tenant_id=eq.{t['id']}&ultima_msg_em=lt.{db.q(limite)}&ultima_msg_em=gt.{db.q(desde_max)}",
                 "numero,ultima_msg_em,revisto_ia_ate")
    feitas = 0
    for c in cts:
        if c.get("revisto_ia_ate") and A.hora_local(c["revisto_ia_ate"]) >= A.hora_local(c["ultima_msg_em"]):
            continue
        desde = c.get("revisto_ia_ate") or A.iso(agora - dt.timedelta(days=1))
        msgs = db.ler("assistant_messages",
                      f"tenant_id=eq.{t['id']}&numero=eq.{db.q(c['numero'])}&simulado=eq.false&created_at=gt.{db.q(desde)}"
                      f"&order=id.asc&limit=80", "direcao,texto,motivo,decisao,entrega_estado,created_at")
        falas = []
        for m in msgs:
            if m["direcao"] == "entrada":
                if str(m.get("decisao") or "").startswith("silencio"):
                    continue
                falas.append({"quem": "pessoa", "texto": m.get("texto") or "", "hora": _hhmm(m["created_at"])})
            elif m.get("entrega_estado") not in ("bloqueado",):
                falas.append({"quem": "equipa" if m.get("motivo") == "equipa" else "assistente",
                              "texto": m.get("texto") or "", "hora": _hhmm(m["created_at"])})
        rev = {"nota": None, "correu_bem": "sem conversa para rever", "falhas": []}
        if any(f["quem"] == "assistente" for f in falas) and any(f["quem"] == "pessoa" for f in falas):
            try:
                papel = (db.rpc("voz_identificar", {"p_telefone": c["numero"]}) or {}).get("papel") or "desconhecido"
            except Exception:  # noqa: BLE001
                papel = "desconhecido"
            try:
                r = cerebro("aprender", {"canal": "whatsapp", "conversa": f"{t['id']}:{c['numero']}", "papel": papel,
                                         "falas": falas}, 200)
                rev = {k: r.get(k) for k in ("nota", "correu_bem", "falhas", "licoes_novas", "licoes_reforcadas", "custo_usd")}
                log("revisao", c["numero"], "nota", r.get("nota"), "licoes", r.get("licoes_novas"))
                feitas += 1
            except Exception as e:  # noqa: BLE001
                log("revisao falhou", c["numero"], repr(e)[:200])
                continue
        db.atualizar("assistant_contacts", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(c['numero'])}",
                     {"revisao_ia": rev, "revisto_ia_ate": c["ultima_msg_em"]})
    return feitas


def laco_revisao():
    log("laço de revisão no ar", REVER_MIN, "min")
    while True:
        try:
            rever_conversas()
        except Exception as e:  # noqa: BLE001
            log("revisao: ciclo falhou", repr(e)[:200])
        time.sleep(300)
