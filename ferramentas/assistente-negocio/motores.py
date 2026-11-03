"""[31/10/2026 missao motor-claude: porteiro do Claude a frente]
Motores do Assistente de Negocio — chamadas com ferramentas (formato OpenAI), cadeia com reserva.

Ordem: o motor principal do cliente (pago) primeiro; se falhar (sem chave, tecto, 429, 5xx), desce
para a reserva. Cada resposta diz que motor respondeu, os tokens e o custo REAL (motores gratis = 0 €).

Motores conhecidos (prefixo:modelo):
  gemini-pago:<modelo>  Gemini com faturacao (GEMINI_API_KEY_FATURACAO) — conta para o orcamento
  go:<modelo>           OpenCode Go (assinatura paga, preco fixo; OPENCODE_GO_KEY) — custo 0 por mensagem
  gemini:<modelo>       Gemini sem faturacao (GEMINI_API_KEY) — gratis, quota por projeto
  groq:<modelo>         Groq (GROQ_API_KEY) — gratis
"""
import json
import os
import time
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

FORNECEDORES = {
    "gemini-pago": {"url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                    "chave": "GEMINI_API_KEY_FATURACAO", "pago": True},
    "go": {"url": "https://opencode.ai/zen/go/v1/chat/completions", "chave": "OPENCODE_GO_KEY", "pago": False,
           "assinatura": True, "cabecalhos": {"x-opencode-session": "ses_assistente-negocio"}},
    "gemini": {"url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
               "chave": "GEMINI_API_KEY", "pago": False},
    # segundo projeto Google sem faturacao (outra quota gratis); so reserva
    "gemini2": {"url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                "chave": "GEMINI_API_KEY_2", "pago": False},
    "groq": {"url": "https://api.groq.com/openai/v1/chat/completions", "chave": "GROQ_API_KEY", "pago": False},
    # 31/10/2026 (missao motor-claude): o Motor Bora local com o PORTEIRO do credito do Claude.
    # porteiro:perfil:claude-cliente -> Claude Sonnet 5.5 enquanto houver credito, senao a rotacao gratis.
    # O credito e do plano do Danilo, nao do cliente: custo 0 para o orcamento do tenant (vai para ia_gastos).
    "porteiro": {"url": "http://127.0.0.1:8792/v1/chat/completions", "chave": None, "pago": False, "porteiro": True,
                 "cabecalhos": {"X-Motor-Origem": "assistente-negocio"}},
}

CLAUDE_PRIMEIRO = os.environ.get("CLAUDE_PRIMEIRO", "1") != "0"
MORTOS = ("go", "gemini2")     # 29/10: go 401 (chave expirada), gemini2 402 (sem creditos)

# EUR por 1 M de tokens (entrada, saida) — preco de tabela publico (USD x 0,92), outubro 2026.
PRECO = {
    "gemini-3-flash-preview": (0.46, 2.76),
    "gemini-3.1-flash-lite": (0.09, 0.37),
    "gemini-2.5-flash": (0.28, 2.30),
}


class MotorFalhou(Exception):
    pass


# Castigo: motor que respondeu "tecto/quota/limite" nao volta a ser tentado durante uns minutos.
# Sem isto, cada mensagem perdia segundos a bater em motores que ja se sabe que estao fechados.
CASTIGO = {}


def _castigar(motor, erro):
    if "HTTP 403" in erro and "Spend cap" in erro:
        seg = 1800
    elif "GoUsageLimitError" in erro:
        seg = 3600
    elif "HTTP 429" in erro:
        seg = 90 if motor.startswith("groq") else 600
    elif "sem chave" in erro:
        seg = 3600
    elif "HTTP 401" in erro or "HTTP 402" in erro or "HTTP 404" in erro:
        seg = 6 * 3600      # 31/10: chave expirada / sem creditos / modelo morto -- nao insistir a cada mensagem
    else:
        return
    CASTIGO[motor] = time.time() + seg


def _achatar(mensagens):
    """Troca de motor a meio de uma resposta: o historico de chamadas de ferramentas passa a texto.
    O Gemini recusa chamadas que nao trazem a assinatura dele (feitas por outro motor) — HTTP 400."""
    out = []
    for m in mensagens:
        if m.get("role") == "assistant" and m.get("tool_calls"):
            feitas = "; ".join(f"{c['function']['name']}({c['function'].get('arguments') or ''})" for c in m["tool_calls"])
            out.append({"role": "assistant", "content": (m.get("content") or "") + f"[consultei: {feitas}]"})
        elif m.get("role") == "tool":
            out.append({"role": "user", "content": f"[resultado de {m.get('name') or 'ferramenta'}]: {m.get('content')}"})
        else:
            out.append(m)
    return out


def _chamar(motor, mensagens, ferramentas, timeout=20):
    forn, _, modelo = motor.partition(":")
    f = FORNECEDORES.get(forn)
    if not f:
        raise MotorFalhou(f"fornecedor desconhecido {forn}")
    chave = "motor-bora-local" if f.get("porteiro") else os.environ.get(f["chave"], "").strip()
    if f.get("porteiro"):
        timeout = max(timeout, 30)      # Claude ate 20 s + rotacao gratis
    if not chave:
        raise MotorFalhou(f"sem chave {f['chave']}")
    # `_de` marca que motor fez cada chamada de ferramenta. Se nao foi este, o historico vai em texto.
    if any(m.get("tool_calls") and m.get("_de") != motor for m in mensagens):
        mensagens = _achatar(mensagens)
    mensagens = [{k: v for k, v in m.items() if k != "_de"} for m in mensagens]
    if not forn.startswith("gemini"):
        # campos so do Gemini (assinatura de pensamento, nome na resposta da ferramenta) rebentam noutros
        limpas = []
        for m in mensagens:
            m = dict(m)
            if m.get("role") == "tool":
                m.pop("name", None)
            if m.get("tool_calls"):
                m["tool_calls"] = [{k: v for k, v in c.items() if k in ("id", "type", "function")} for c in m["tool_calls"]]
            limpas.append(m)
        mensagens = limpas
    corpo = {"model": modelo, "messages": mensagens, "temperature": 0.3}
    if ferramentas:
        corpo["tools"] = ferramentas
        corpo["tool_choice"] = "auto"
    if forn.startswith("gemini") and modelo.startswith("gemini-3"):
        corpo["reasoning_effort"] = "low"
    if forn == "groq" and "gpt-oss" in modelo:
        corpo["reasoning_effort"] = "low"
    h = {"Content-Type": "application/json", "Authorization": "Bearer " + chave, "User-Agent": UA}
    h.update(f.get("cabecalhos", {}))
    req = urllib.request.Request(f["url"], json.dumps(corpo).encode(), h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            j = json.load(r)
    except urllib.error.HTTPError as e:
        raise MotorFalhou(f"HTTP {e.code} {e.read().decode(errors='ignore')[:200]}")
    except Exception as e:  # rede, timeout
        raise MotorFalhou(f"{type(e).__name__}: {str(e)[:150]}")
    ms = int((time.time() - t0) * 1000)
    if not j.get("choices"):
        raise MotorFalhou("resposta sem choices: " + json.dumps(j)[:200])
    uso = j.get("usage") or {}
    tin, tout = int(uso.get("prompt_tokens") or 0), int(uso.get("completion_tokens") or 0)
    custo = 0.0
    if f.get("pago"):
        pin, pout = PRECO.get(modelo, (0.5, 3.0))
        custo = (tin * pin + tout * pout) / 1e6
    meta = {"motor": motor, "tokens_in": tin, "tokens_out": tout, "custo_eur": custo, "ms": ms, "pago": bool(f.get("pago"))}
    if f.get("porteiro"):
        # quem respondeu de facto (claude:claude-sonnet-5-5 ou groq:...), o que o porteiro decidiu e o custo do credito
        meta["motor"] = j.get("model") or motor
        meta["via"] = motor
        meta["custo_usd_claude"] = float(uso.get("custo_usd") or 0)
        mot = j.get("motor") or {}
        meta["porteiro"] = mot.get("porteiro") or next((t.get("porteiro") for t in (mot.get("tentativas") or []) if isinstance(t, dict) and t.get("porteiro")), None)
    return j["choices"][0]["message"], meta


def conversar(cadeia, mensagens, ferramentas=None, pode_pago=True):
    """Tenta cada motor da cadeia por ordem. Devolve (mensagem, meta). meta['falhas'] lista o que caiu."""
    falhas = []
    cadeia = list(cadeia or [])
    if CLAUDE_PRIMEIRO and not any(str(c).startswith("porteiro:") for c in cadeia):
        cadeia.insert(0, "porteiro:perfil:claude-cliente")
    for motor in cadeia:
        forn = motor.split(":", 1)[0]
        if forn in MORTOS:
            falhas.append(f"{motor}: fornecedor morto (29/10)")
            continue
        if FORNECEDORES.get(forn, {}).get("pago") and not pode_pago:
            falhas.append(f"{motor}: orcamento do mes esgotado")
            continue
        if CASTIGO.get(motor, 0) > time.time():
            falhas.append(f"{motor}: de castigo ({int(CASTIGO[motor] - time.time())} s)")
            continue
        for tentativa in range(2):
            try:
                msg, meta = _chamar(motor, mensagens, ferramentas)
                meta["falhas"] = falhas
                return msg, meta
            except MotorFalhou as e:
                txt = str(e)
                # 503/500 = sobrecarga momentanea -> uma segunda tentativa; o resto desce logo
                # 31/10: so se repete em 500/503 rapidos; em timeout NAO (o cliente ficava ate ~90 s a espera)
                if tentativa == 0 and ("HTTP 503" in txt or "HTTP 500" in txt) and "timeout" not in txt.lower():
                    time.sleep(1.5)
                    continue
                falhas.append(f"{motor}: {txt[:160]}")
                _castigar(motor, txt)
                break
    raise MotorFalhou("todos os motores falharam: " + " | ".join(falhas))
