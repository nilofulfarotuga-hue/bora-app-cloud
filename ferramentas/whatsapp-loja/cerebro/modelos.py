# -*- coding: utf-8 -*-
"""modelos.py — a cadeia de motores do cerebro, todos com TOOL CALLING, e nenhum erro mata a resposta.

Ordem (custo zero primeiro): Ollama local qwen2.5:7b-instruct (capacidade `tools`, ctx 32k)
-> gemini-3.6-flash (chave viva em backend/.env; provado com functionCall a 02/09)
-> gemini-3-flash-preview. Os modelos Go NAO entram (plano esgotado ate ~08/09).

Livro de esgotamentos: um 429/5xx/timeout marca o modelo como esgotado por uns minutos e a
chamada desce ao seguinte, sem bater a porta fechada. So se TODOS cairem e que se devolve erro
-- e ai o agente responde na mesma com uma frase fixa (nunca silencio).
"""
import json
import os
import threading
import time
import urllib.error
import urllib.request

from . import supa

OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
_MODELO_FICHEIRO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "modelo_local.txt")
MODELO_LOCAL = (os.environ.get("CEREBRO_MODELO_LOCAL") or
                (open(_MODELO_FICHEIRO, encoding="utf-8").read().strip() if os.path.exists(_MODELO_FICHEIRO) else "") or
                "qwen2.5:7b-instruct")
_CADEIA_FICHEIRO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cadeia.txt")


def _ler_cadeia():
    """Ordem dos motores: variavel de ambiente > ficheiro cerebro/cadeia.txt > omissao (custo zero 1o)."""
    txt = os.environ.get("CEREBRO_CADEIA", "")
    if not txt and os.path.exists(_CADEIA_FICHEIRO):
        txt = open(_CADEIA_FICHEIRO, encoding="utf-8").read().strip()
    return [m.strip() for m in (txt or "ollama,gemini-3.6-flash,gemini-3-flash-preview").split(",") if m.strip()]


CADEIA = _ler_cadeia()
_esgotados = {}           # modelo -> epoch ate quando
_ultimo_erro = {}


def esgotado(modelo):
    return _esgotados.get(modelo, 0) > time.time()


def _marcar(modelo, segundos, erro):
    _esgotados[modelo] = time.time() + segundos
    _ultimo_erro[modelo] = str(erro)[:300]


def estado():
    return {m: {"esgotado_ate": _esgotados.get(m), "ultimo_erro": _ultimo_erro.get(m)} for m in CADEIA}


def _post(url, corpo, timeout, cab=None):
    req = urllib.request.Request(url, data=json.dumps(corpo).encode("utf-8"),
                                 headers=dict({"Content-Type": "application/json"}, **(cab or {})))
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


# ---------------------------------------------------------------- Ollama
def ollama_vivo():
    try:
        urllib.request.urlopen(OLLAMA + "/api/tags", timeout=3)
        return True
    except Exception:
        return False


def _to_ollama(mensagens):
    out = []
    for m in mensagens:
        if m["role"] == "assistant" and m.get("tool_calls"):
            out.append({"role": "assistant", "content": m.get("content") or "",
                        "tool_calls": [{"function": {"name": c["name"], "arguments": c.get("args") or {}}}
                                       for c in m["tool_calls"]]})
        elif m["role"] == "tool":
            out.append({"role": "tool", "content": m.get("content") or ""})
        else:
            out.append({"role": m["role"], "content": m.get("content") or ""})
    return out


def _chamar_ollama(mensagens, tools, max_tokens, temperatura, timeout):
    # num_ctx EXPLICITO: por omissao o Ollama usa uma janela pequena e, se o prompt nao cabe, corta o
    # INICIO -- que e o system prompt inteiro. O prompt do agente anda nos 3 mil tokens.
    corpo = {"model": MODELO_LOCAL, "messages": _to_ollama(mensagens), "stream": False,
             "keep_alive": "30m", "options": {"num_predict": max_tokens, "temperature": temperatura, "num_ctx": 8192}}
    if tools:
        corpo["tools"] = [{"type": "function", "function": t} for t in tools]
    d = _post(OLLAMA + "/api/chat", corpo, timeout)
    msg = d.get("message") or {}
    calls = []
    for i, c in enumerate(msg.get("tool_calls") or []):
        fn = c.get("function") or {}
        args = fn.get("arguments") or {}
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except Exception:
                args = {"_bruto": args}
        calls.append({"id": "ollama_%d_%d" % (int(time.time()), i), "name": fn.get("name"), "args": args})
    return {"texto": (msg.get("content") or "").strip() or None, "tool_calls": calls}


# ---------------------------------------------------------------- Gemini
def _gemini_key():
    return supa.ENV.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY") or ""


def _to_gemini(mensagens, tools):
    sistema = "\n\n".join(m.get("content") or "" for m in mensagens if m["role"] == "system")
    contents = []
    for m in mensagens:
        if m["role"] == "system":
            continue
        if m["role"] == "user":
            contents.append({"role": "user", "parts": [{"text": m.get("content") or ""}]})
        elif m["role"] == "assistant":
            # GEMINI 3.x EXIGE O thoughtSignature DE VOLTA (02/09): cada functionCall que o modelo
            # devolve vem com uma assinatura; se a volta seguinte nao a devolver no mesmo part, o
            # servidor responde 400 "Function call is missing a thought_signature". Foi o que fez a
            # cadeia inteira cair na 2a volta de todas as provas.
            parts = []
            if m.get("content"):
                pt = {"text": m["content"]}
                if m.get("thought_signature"):
                    pt["thoughtSignature"] = m["thought_signature"]
                parts.append(pt)
            for c in m.get("tool_calls") or []:
                pc = {"functionCall": {"name": c["name"], "args": c.get("args") or {}}}
                if c.get("thought_signature"):
                    pc["thoughtSignature"] = c["thought_signature"]
                parts.append(pc)
            contents.append({"role": "model", "parts": parts or [{"text": ""}]})
        elif m["role"] == "tool":
            try:
                resp = json.loads(m.get("content") or "{}")
            except Exception:
                resp = {"resultado": m.get("content")}
            if not isinstance(resp, dict):
                resp = {"resultado": resp}
            contents.append({"role": "user", "parts": [{"functionResponse": {"name": m.get("name") or "ferramenta",
                                                                              "response": resp}}]})
    corpo = {"contents": contents}
    if sistema:
        corpo["systemInstruction"] = {"parts": [{"text": sistema}]}
    if tools:
        corpo["tools"] = [{"functionDeclarations": tools}]
    return corpo


def _chamar_gemini(modelo, mensagens, tools, max_tokens, temperatura, timeout):
    corpo = _to_gemini(mensagens, tools)
    # Nos Gemini 3.x o maxOutputTokens conta tambem o "pensamento": com 380 a resposta saia cortada a
    # meio da frase ("...pode mandar por aqui mesmo! En"). Da-se folga; o tamanho da resposta e' regra
    # do prompt (1-3 frases), nao do tecto de tokens.
    corpo["generationConfig"] = {"temperature": temperatura, "maxOutputTokens": max(max_tokens, 1500)}
    url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % (modelo, _gemini_key())
    d = _post(url, corpo, timeout)
    cand = (d.get("candidates") or [{}])[0]
    parts = (cand.get("content") or {}).get("parts") or []
    texto = "".join(p.get("text", "") for p in parts if "text" in p).strip() or None
    calls = [{"id": "gem_%d_%d" % (int(time.time()), i), "name": p["functionCall"].get("name"),
              "args": p["functionCall"].get("args") or {}, "thought_signature": p.get("thoughtSignature")}
             for i, p in enumerate(parts) if "functionCall" in p]
    sig_texto = next((p.get("thoughtSignature") for p in parts if "text" in p and p.get("thoughtSignature")), None)
    return {"texto": texto, "tool_calls": calls, "thought_signature": sig_texto}


# ---------------------------------------------------------------- OpenAI-compativel (OpenCode Zen: nemotron/hy3 gratis)
ZEN_URL = (os.environ.get("OPENCODE_ZEN_URL") or supa.ENV.get("OPENCODE_ZEN_URL") or "https://opencode.ai/zen/v1").rstrip("/")


def _zen_key():
    return supa.ENV.get("OPENCODE_ZEN_API_KEY") or os.environ.get("OPENCODE_ZEN_API_KEY") or ""


def _to_openai(mensagens):
    out = []
    for m in mensagens:
        if m["role"] == "assistant" and m.get("tool_calls"):
            out.append({"role": "assistant", "content": m.get("content") or None,
                        "tool_calls": [{"id": c["id"], "type": "function",
                                        "function": {"name": c["name"], "arguments": json.dumps(c.get("args") or {}, ensure_ascii=False)}}
                                       for c in m["tool_calls"]]})
        elif m["role"] == "tool":
            out.append({"role": "tool", "tool_call_id": m.get("tool_call_id") or "", "content": m.get("content") or ""})
        else:
            out.append({"role": m["role"], "content": m.get("content") or ""})
    return out


def _chamar_openai(base, key, modelo, mensagens, tools, max_tokens, temperatura, timeout):
    corpo = {"model": modelo, "messages": _to_openai(mensagens), "max_tokens": max_tokens, "temperature": temperatura}
    if tools:
        corpo["tools"] = [{"type": "function", "function": t} for t in tools]
    # O Cloudflare a frente do opencode.ai barra o User-Agent do urllib com 403 "error code: 1010"
    # (medido 02/09); com uma identificacao de browser passa, como no Hermes.
    d = _post(base + "/chat/completions", corpo, timeout,
              {"Authorization": "Bearer " + key, "Accept": "application/json",
               "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 hermes-agent/1.0"})
    msg = ((d.get("choices") or [{}])[0].get("message")) or {}
    calls = []
    for i, c in enumerate(msg.get("tool_calls") or []):
        fn = c.get("function") or {}
        args = fn.get("arguments") or {}
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except Exception:
                args = {"_bruto": args}
        calls.append({"id": c.get("id") or "zen_%d_%d" % (int(time.time()), i), "name": fn.get("name"), "args": args})
    return {"texto": (msg.get("content") or "").strip() or None, "tool_calls": calls}


# ---------------------------------------------------------------- Groq (gratis, rapido, com tools) -- exige conta: a chave e do Danilo
GROQ_URL = "https://api.groq.com/openai/v1"


def _groq_key():
    return supa.ENV.get("GROQ_API_KEY") or os.environ.get("GROQ_API_KEY") or ""


# ---------------------------------------------------------------- MOTOR BORA (roteador partilhado, 02/09 noite)
# O cerebro deixa de ter a sua propria cadeia como 1a escolha: pede ao roteador local (perfil chat-rapido /
# raciocinio / volume), que roda chaves e fornecedores gratis e conta quotas. Se o roteador estiver em
# baixo, a cadeia directa (abaixo) continua a existir -- o bot nunca fica mudo por o roteador cair.
MOTOR_URL = (supa.ENV.get("MOTOR_BORA_URL") or os.environ.get("MOTOR_BORA_URL") or "http://127.0.0.1:8792").rstrip("/")
USAR_MOTOR = os.environ.get("CEREBRO_MOTOR", "1") != "0"
TIMEOUT_PERFIL = {"chat-rapido": 18, "raciocinio": 75, "volume": 90, "visao": 40}
_motor_morto_ate = 0.0
_motor_lock = threading.Lock()


def _via_motor(mensagens, tools, max_tokens, temperatura, perfil):
    global _motor_morto_ate
    if time.time() < _motor_morto_ate:
        return None
    corpo = {"model": "perfil:" + perfil, "messages": mensagens, "max_tokens": max_tokens, "temperature": temperatura, "stream": False}
    if tools:
        corpo["tools"] = [{"type": "function", "function": t} for t in tools]
    try:
        req = urllib.request.Request(MOTOR_URL + "/v1/chat/completions", data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                                     headers={"Content-Type": "application/json", "X-Motor-Origem": "cerebro-whatsapp"})
        with urllib.request.urlopen(req, timeout=TIMEOUT_PERFIL.get(perfil, 30)) as r:
            d = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            corpo_e = e.read()[:300].decode("utf-8", "replace")
        except Exception:
            corpo_e = ""
        return {"erro": "motor HTTP %s %s" % (e.code, corpo_e), "texto": "", "tool_calls": [], "modelo": None}
    except Exception as e:  # noqa: BLE001
        if "refused" in str(e).lower() or "10061" in str(e) or "111" in str(e):
            with _motor_lock:
                _motor_morto_ate = time.time() + 60      # roteador em baixo: cadeia directa durante 60 s
        return {"erro": "motor em baixo: %s" % str(e)[:120], "texto": "", "tool_calls": [], "modelo": None}
    if d.get("error"):
        return {"erro": "motor: " + str(d["error"])[:200], "texto": "", "tool_calls": [], "modelo": d.get("model")}
    ch = (d.get("choices") or [{}])[0]
    m = ch.get("message") or {}
    tcs = []
    for c in m.get("tool_calls") or []:
        fn = c.get("function") or {}
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except Exception:
            args = {}
        tcs.append({"id": c.get("id"), "name": fn.get("name"), "args": args})
    return {"texto": (m.get("content") or "").strip(), "tool_calls": tcs, "modelo": d.get("model") or ("motor:" + perfil), "erro": None,
            "motor": d.get("motor")}


# ---------------------------------------------------------------- a cadeia
def chat(mensagens, tools=None, max_tokens=350, temperatura=0.2, timeouts=None, perfil=None):
    if USAR_MOTOR:
        r = _via_motor(mensagens, tools, max_tokens, temperatura, perfil or "chat-rapido")
        if r and not r.get("erro") and (r.get("texto") or r.get("tool_calls")):
            return r
        # o roteador nao deu resposta: cai na cadeia directa (e fica registado porque)
        _ultimo_erro["motor"] = (r or {}).get("erro") or "motor: sem texto"
    return _chat_directo(mensagens, tools, max_tokens, temperatura, timeouts)


def _chat_directo(mensagens, tools=None, max_tokens=350, temperatura=0.2, timeouts=None):
    """Devolve {"texto", "tool_calls", "modelo"} ou {"erro": ...} se a cadeia inteira cair."""
    # Ollama 45 s: medido a 02/09, o 7b local levou >150 s a avaliar o prompt a frio neste CPU em
    # todas as provas; e reserva, nao titular (ver cerebro/CADEIA.md). O interino dos 20 s cobre.
    # 02/09 09:00: os dois Gemini esgotaram a quota gratis do dia (429) a meio das provas. O Ollama e
    # entao o UNICO motor que resta na maior parte do dia: tem de poder acabar (120 s); o prompt
    # passou a compacto e o interino dos 20 s cobre a espera. Quando o Gemini volta, e reserva rapida.
    # 02/09 10:20 -- o Danilo quer resposta NA HORA (<10 s em 9 de 10). Medido sem ferramentas:
    # gemini-3.1-flash-lite 0,9 s · gemini-3-flash-preview 2,4 s · qwen 7b quente 2,4 s · nemotron 40-90 s.
    # Tempos curtos: um motor que nao responde em 12 s da a vez ao seguinte.
    timeouts = timeouts or {"gemini": 12, "groq": 12, "ollama": 25, "zen": 60}
    erros = []
    for modelo in CADEIA:
        if esgotado(modelo):
            erros.append("%s: esgotado" % modelo)
            continue
        t0 = time.time()
        try:
            if modelo == "ollama":
                if not ollama_vivo():
                    _marcar(modelo, 60, "ollama nao responde")
                    erros.append("ollama: em baixo")
                    continue
                r = _chamar_ollama(mensagens, tools, max_tokens, temperatura, timeouts["ollama"])
            elif modelo.startswith("zen:"):
                if not _zen_key():
                    erros.append("%s: sem chave" % modelo)
                    continue
                r = _chamar_openai(ZEN_URL, _zen_key(), modelo[4:], mensagens, tools, max_tokens, temperatura, timeouts.get("zen", 60))
            elif modelo.startswith("groq:"):
                if not _groq_key():
                    erros.append("%s: sem chave (GROQ_API_KEY no cerebro/.env)" % modelo)
                    continue
                r = _chamar_openai(GROQ_URL, _groq_key(), modelo[5:], mensagens, tools, max_tokens, temperatura, timeouts.get("groq", 20))
            else:
                if not _gemini_key():
                    erros.append("%s: sem chave" % modelo)
                    continue
                r = _chamar_gemini(modelo, mensagens, tools, max_tokens, temperatura, timeouts["gemini"])
            r["modelo"] = modelo
            r["segundos"] = round(time.time() - t0, 1)
            return r
        except urllib.error.HTTPError as e:
            corpo = e.read()[:200].decode("utf-8", "replace")
            # 429 no Gemini e a quota DO DIA (10 min de castigo); no Groq e o limite POR MINUTO (8 000 tokens
            # no plano gratis, 02/09) -- 65 s chegam, senao o melhor motor fica fora por 10 min a cada rajada.
            _marcar(modelo, (65 if modelo.startswith("groq:") else 600) if e.code == 429 else 120, "HTTP %s %s" % (e.code, corpo))
            erros.append("%s: HTTP %s" % (modelo, e.code))
        except Exception as e:  # noqa: BLE001 -- timeout, ligacao, JSON: desce ao seguinte
            _marcar(modelo, 90, "%s: %s" % (type(e).__name__, e))
            erros.append("%s: %s" % (modelo, type(e).__name__))
    return {"erro": " | ".join(erros), "texto": None, "tool_calls": [], "modelo": None}


if __name__ == "__main__":
    print("ollama vivo:", ollama_vivo(), "| cadeia:", CADEIA)
    r = chat([{"role": "system", "content": "Responde em portugues de Portugal, uma frase."},
              {"role": "user", "content": "Diz so: cadeia viva."}], max_tokens=20)
    print(r)
