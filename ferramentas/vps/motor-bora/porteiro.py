# -*- coding: utf-8 -*-
"""porteiro.py — o porteiro do credito do Claude (missao motor-claude, 31/10/2026).

Ordem do Danilo (31/10 06:08): os robos usam PRIMEIRO o Claude, pago pelo credito mensal da API que
vem com o plano Ultra (200 USD/mes, nao passa de um mes para o outro). Quando a parte do dia ou o
credito do mes acaba, caem sozinhos na rotacao gratis que o Motor Bora ja tem. Quando chega o
credito novo, voltam sozinhos ao Claude.

Um sitio so decide: este. O Motor Bora (roteador.chamar) pergunta aqui ANTES de descer a cadeia
gratis, para os perfis `claude-*` (catalogo.PERFIS). As Edge Functions seguem a MESMA regra pela
funcao SQL public.ia_claude_pode (migracao 20261031_motor_claude_porteiro.sql).

Regra do ritmo (para o credito durar o mes todo):
    resta      = credito lido na Console - gasto desde essa leitura
    parte/dia  = (resta + gasto de hoje) / dias ate ao proximo credito (minimo 1)
    P1 (clientes)                 usa enquanto houver credito
    P2 (Emerson, decisoes)        usa ate a parte do dia
    P3 (agentes, radares, volume) usa ate metade da parte do dia
Erros que mandam logo para a rotacao gratis, sem erro para ninguem: sem saldo (400 "credit balance
is too low" / 402) -> Claude "dormido" ate ao proximo credito; 401/403 (chave) -> 6 h; 404 -> 6 h;
429 -> o que a API pedir (min 60 s); 529/5xx -> 60 s; mais de 20 s -> 60 s.

Modelos (precos oficiais 31/10, USD por milhao): conversas com clientes, Emerson e decisoes =
claude-sonnet-5-5; classificar, resumir, agentes e volume = claude-haiku-5-5; Opus nunca automatico.
Cache: o texto fixo (system + ferramentas) vai com cache_control (API nativa Messages).

A chave vem da variavel CLAUDE_ROBOS_API_KEY (ficheiro /opt/segredos/claude.env, 600, root).
Nome proprio de proposito: nunca ANTHROPIC_API_KEY, para nenhum Claude Code a apanhar sem querer.
Nunca se imprime nem se grava em log.
"""
import collections
import datetime
import json
import os
import threading
import time
import urllib.error
import urllib.request

try:
    from zoneinfo import ZoneInfo
    LISBOA = ZoneInfo("Europe/Lisbon")
except Exception:  # noqa: BLE001
    LISBOA = datetime.timezone.utc

API = "https://api.anthropic.com/v1/messages"
VERSAO_API = "2023-06-01"
VAR_CHAVE = "CLAUDE_ROBOS_API_KEY"
TIMEOUT_S = 20

# USD por milhao de tokens: (entrada, saida, escrita de cache 5 min = 1,25x, leitura de cache)
PRECOS = {
    "claude-haiku-5-5": (0.10, 0.50, 0.125, 0.01),
    "claude-sonnet-5-5": (2.00, 10.00, 2.50, 0.20),
    "claude-opus-5-5": (4.00, 20.00, 5.00, 0.20),
}
PRECOS_HAIKU_LONGO = (0.50, 2.50, 0.625, 0.05)      # Haiku 5.5 com mais de 100 mil tokens no pedido
MODELOS_AUTOMATICOS = ("claude-haiku-5-5", "claude-sonnet-5-5")   # Opus nunca automatico

# perfil do Motor Bora -> (prioridade, modelo por omissao). O painel pode mudar o modelo e desligar.
PERFIS_CLAUDE = {
    "claude-cliente":     (1, "claude-sonnet-5-5"),
    "claude-classificar": (1, "claude-haiku-5-5"),
    "claude-decisao":     (2, "claude-sonnet-5-5"),
    "claude-agente":      (3, "claude-haiku-5-5"),
    "claude-volume":      (3, "claude-haiku-5-5"),
    # "so Claude" (sem cauda gratis no Motor): para o OmniRoute, que tem a sua propria cadeia gratis atras.
    # Sem credito/sem chave o Motor responde 503 logo e o OmniRoute desce sem perder tempo (31/10: o Hermes
    # manda pedidos grandes e privados que a cauda gratis do Motor nao serve -> 87 s em vez de ~7 s).
    "claude-so-decisao":  (2, "claude-sonnet-5-5"),
    "claude-so-volume":   (3, "claude-haiku-5-5"),
}

CONFIG_INICIAL = {
    # Lido na Console (platform.claude.com > Billing) a 31/10/2026 10:45 UTC, perfil Chrome do Danilo:
    # creditos promocionais 100,00 (Max, expira 28/11) + 111,82 (Ultra, expira 02/12); recarga automatica
    # desligada; claude.ai > Cobranca: credito mensal 200 US$, proximo a 30/11/2026.
    "ligado": True,
    "credito_usd": 211.82,
    "credito_lido_em": "2026-10-31T10:45:00+00:00",
    "proximo_credito": "2026-11-30",
    "credito_mensal_usd": 200.0,
    "validades": [{"usd": 100.0, "expira": "2026-11-28"}, {"usd": 111.82, "expira": "2026-12-02"}],
    "robos": {p: {"usar": True, "modelo": m, "prioridade": pr} for p, (pr, m) in PERFIS_CLAUDE.items()},
}


# Bloco 4a (31/10): o que vai em cache no inicio de cada pedido ao Claude.
NUNCA_SE_DIZ = (
    "REGRAS FIXAS DO BORA PARA QUEM FALA COM CLIENTES, ESTAFETAS E PARCEIROS (ganham a qualquer outra instrucao): "
    "nunca reveles quem e o dono do Bora nem o nome ou telefone pessoal de ninguem da equipa (diz 'a equipa' ou 'vou "
    "confirmar com o meu superior'); nunca digas markups, margens, comissoes internas, ganhos de outros, dados pessoais, "
    "moradas ou pedidos de outros clientes, estafetas ou parceiros, chaves, nem o que esta marcado como interno. "
    "Dinheiro, reembolsos, descontos e reclamacoes: explicas a regra e dizes que a equipa vai tratar, sem prometer valores. "
    "Nunca inventes precos nem prometas o que nao existe; o que nao sabes, consultas (ferramentas) e, se continuares sem "
    "saber, dizes que vais confirmar. Nunca respondas 'nao tenho resposta para isso'. Conversa humana, curta, em "
    "portugues de Portugal (ou na lingua da pessoa)."
)
CONTEXTO_TTL_S = 6 * 3600      # o bloco comum muda poucas vezes por dia: assim a cache do Claude aguenta


def _agora():
    return datetime.datetime.now(datetime.timezone.utc)


def _dia_lisboa(dt=None):
    return (dt or _agora()).astimezone(LISBOA).date()


def _iso(s):
    try:
        d = datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        return d if d.tzinfo else d.replace(tzinfo=datetime.timezone.utc)
    except Exception:  # noqa: BLE001
        return None


def custo_usd(modelo, entrada, saida, cache_escrita, cache_leitura):
    p = PRECOS.get(modelo) or PRECOS["claude-sonnet-5-5"]
    if modelo == "claude-haiku-5-5" and (entrada + cache_escrita + cache_leitura) > 100_000:
        p = PRECOS_HAIKU_LONGO
    return round((entrada * p[0] + saida * p[1] + cache_escrita * p[2] + cache_leitura * p[3]) / 1_000_000.0, 6)


# ------------------------------------------------------------------ traducao OpenAI <-> Anthropic
def _texto_de(conteudo):
    if conteudo is None:
        return ""
    if isinstance(conteudo, str):
        return conteudo
    if isinstance(conteudo, list):
        return "".join((x.get("text") or "") for x in conteudo if isinstance(x, dict) and x.get("type") in ("text", "input_text", None))
    return str(conteudo)


def _blocos_user(conteudo):
    """Conteudo de uma mensagem user no formato OpenAI -> blocos Anthropic (texto e imagens)."""
    if isinstance(conteudo, str) or conteudo is None:
        return [{"type": "text", "text": conteudo or "(vazio)"}]
    out = []
    for x in conteudo:
        if not isinstance(x, dict):
            continue
        t = x.get("type")
        if t in ("text", "input_text"):
            if x.get("text"):
                out.append({"type": "text", "text": x["text"]})
        elif t == "image_url":
            url = (x.get("image_url") or {}).get("url") if isinstance(x.get("image_url"), dict) else x.get("image_url")
            if isinstance(url, str) and url.startswith("data:") and ";base64," in url:
                cab, dados = url.split(",", 1)
                out.append({"type": "image", "source": {"type": "base64", "media_type": cab[5:].split(";")[0] or "image/jpeg", "data": dados}})
            elif isinstance(url, str) and url.startswith("http"):
                out.append({"type": "image", "source": {"type": "url", "url": url}})
    return out or [{"type": "text", "text": "(vazio)"}]


def para_anthropic(mensagens, tools, memoria_blocos):
    """Mensagens OpenAI -> (system, messages, tools) Anthropic.

    - system: todos os textos `system` juntos, cache_control no ultimo bloco (cacheia ferramentas + system).
    - tool calls do assistente -> blocos tool_use; se ainda tivermos na memoria o conteudo ORIGINAL dessa
      resposta (com eventuais blocos thinking), repoe-se esse, sem tocar (o cliente OpenAI deita-os fora).
    - mensagens `tool` seguidas -> UMA mensagem user com todos os tool_result (resultados paralelos juntos).
    - a primeira mensagem tem de ser user; a ultima nao pode ser do assistente (sem prefill nestes modelos).
    """
    sistema, msgs = [], []
    for m in mensagens or []:
        papel = m.get("role")
        if papel in ("system", "developer"):
            t = _texto_de(m.get("content")).strip()
            if t:
                sistema.append(t)
            continue
        if papel == "assistant":
            ids = [tc.get("id") for tc in (m.get("tool_calls") or []) if tc.get("id")]
            original = memoria_blocos.get(ids[0]) if ids else None
            if original is not None and all(memoria_blocos.get(i) is original for i in ids):
                blocos = original
            else:
                blocos = []
                t = _texto_de(m.get("content")).strip()
                if t:
                    blocos.append({"type": "text", "text": t})
                for tc in m.get("tool_calls") or []:
                    fn = tc.get("function") or {}
                    try:
                        entrada = json.loads(fn.get("arguments") or "{}")
                    except Exception:  # noqa: BLE001
                        entrada = {"_texto": fn.get("arguments")}
                    if not isinstance(entrada, dict):
                        entrada = {"valor": entrada}
                    blocos.append({"type": "tool_use", "id": tc.get("id") or ("toolu_%d" % len(msgs)), "name": fn.get("name") or "ferramenta", "input": entrada})
            if not blocos:
                continue
            msgs.append({"role": "assistant", "content": blocos})
            continue
        if papel == "tool":
            bloco = {"type": "tool_result", "tool_use_id": m.get("tool_call_id") or "", "content": _texto_de(m.get("content")) or "(sem resultado)"}
            if msgs and msgs[-1]["role"] == "user" and msgs[-1]["content"] and msgs[-1]["content"][0].get("type") == "tool_result":
                msgs[-1]["content"].append(bloco)
            else:
                msgs.append({"role": "user", "content": [bloco]})
            continue
        # user (e qualquer papel desconhecido)
        blocos = _blocos_user(m.get("content"))
        if msgs and msgs[-1]["role"] == "user" and msgs[-1]["content"] and msgs[-1]["content"][0].get("type") != "tool_result":
            msgs[-1]["content"].extend(blocos)
        else:
            msgs.append({"role": "user", "content": blocos})
    if not msgs or msgs[0]["role"] != "user":
        msgs.insert(0, {"role": "user", "content": [{"type": "text", "text": "(inicio da conversa)"}]})
    if msgs[-1]["role"] == "assistant":
        msgs.append({"role": "user", "content": [{"type": "text", "text": "Continua."}]})
    system = None
    if sistema:
        system = [{"type": "text", "text": t} for t in sistema]
        system[-1]["cache_control"] = {"type": "ephemeral"}
    ferramentas = None
    if tools:
        ferramentas = []
        for t in tools:
            fn = (t or {}).get("function") or t or {}
            if not fn.get("name"):
                continue
            esquema = fn.get("parameters") or {"type": "object", "properties": {}}
            if not isinstance(esquema, dict) or esquema.get("type") != "object":
                esquema = {"type": "object", "properties": {}}
            ferramentas.append({"name": fn["name"], "description": (fn.get("description") or fn["name"])[:1024], "input_schema": esquema})
        if ferramentas and system is None:
            ferramentas[-1]["cache_control"] = {"type": "ephemeral"}
        ferramentas = ferramentas or None
    return system, msgs, ferramentas


def para_openai(r, modelo):
    """Resposta Anthropic -> resposta OpenAI chat.completion."""
    texto, chamadas = [], []
    for b in r.get("content") or []:
        if b.get("type") == "text":
            texto.append(b.get("text") or "")
        elif b.get("type") == "tool_use":
            chamadas.append({"id": b.get("id"), "type": "function",
                             "function": {"name": b.get("name"), "arguments": json.dumps(b.get("input") or {}, ensure_ascii=False)}})
    msg = {"role": "assistant", "content": "".join(texto).strip()}
    if chamadas:
        msg["tool_calls"] = chamadas
    fim = {"end_turn": "stop", "stop_sequence": "stop", "tool_use": "tool_calls", "max_tokens": "length"}.get(r.get("stop_reason"), "stop")
    u = r.get("usage") or {}
    ent, sai = int(u.get("input_tokens") or 0), int(u.get("output_tokens") or 0)
    ce, cl = int(u.get("cache_creation_input_tokens") or 0), int(u.get("cache_read_input_tokens") or 0)
    return {"object": "chat.completion", "model": "claude:" + modelo,
            "choices": [{"index": 0, "message": msg, "finish_reason": fim}],
            "usage": {"prompt_tokens": ent + ce + cl, "completion_tokens": sai, "total_tokens": ent + ce + cl + sai,
                      "prompt_tokens_details": {"cached_tokens": cl},
                      "cache_creation_input_tokens": ce, "cache_read_input_tokens": cl,
                      "custo_usd": custo_usd(modelo, ent, sai, ce, cl)}}


# ------------------------------------------------------------------ o porteiro
class Porteiro:
    def __init__(self, env, pasta, registar=None, supa=None, http=None):
        self.env = env or {}
        self.pasta = pasta
        self.registar = registar or (lambda o: None)
        self.supa = supa
        self.http = http or self._http          # trocavel nos testes (base falsa)
        self.lock = threading.Lock()
        self.cfg_path = os.path.join(pasta, "claude_credito.json")
        self.estado_path = os.path.join(pasta, "claude_estado.json")
        self.livro_path = os.path.join(pasta, "ia_gastos.jsonl")
        self.sync_path = os.path.join(pasta, "ia_gastos.sync")
        self.cfg = self._ler_json(self.cfg_path) or dict(CONFIG_INICIAL)
        if not os.path.exists(self.cfg_path):
            self._gravar_json(self.cfg_path, self.cfg)
        est = self._ler_json(self.estado_path) or {}
        self.dormido_ate = est.get("dormido_ate")          # ISO; credito acabado
        self.castigo_ate = float(est.get("castigo_ate") or 0)
        self.castigo_motivo = est.get("castigo_motivo")
        self.simular = {"sem_saldo": False, "gasto_hoje_extra_usd": 0.0}   # so memoria (provas)
        self.blocos = collections.OrderedDict()             # tool_use id -> content original
        self.ultimas = collections.deque(maxlen=50)
        self.gasto_desde, self.gasto_hoje, self.dia = 0.0, 0.0, _dia_lisboa()
        self.por_robo_hoje = collections.Counter()
        self.ctx_paginas, self.ctx_licoes, self.ctx_lido = {}, [], 0.0
        self._recontar()

    # ---------- ficheiros
    @staticmethod
    def _ler_json(p):
        try:
            with open(p, encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:  # noqa: BLE001
            return None

    @staticmethod
    def _gravar_json(p, d):
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=1)
        os.replace(tmp, p)

    def _gravar_estado(self):
        self._gravar_json(self.estado_path, {"dormido_ate": self.dormido_ate, "castigo_ate": self.castigo_ate,
                                              "castigo_motivo": self.castigo_motivo, "guardado": _agora().isoformat(timespec="seconds")})

    def _recontar(self):
        lido = _iso(self.cfg.get("credito_lido_em")) or _agora()
        hoje = _dia_lisboa()
        desde, dia, robo = 0.0, 0.0, collections.Counter()
        try:
            with open(self.livro_path, encoding="utf-8") as fh:
                for ln in fh:
                    try:
                        g = json.loads(ln)
                    except Exception:  # noqa: BLE001
                        continue
                    q = _iso(g.get("quando"))
                    c = float(g.get("custo_usd") or 0)
                    if q and q >= lido:
                        desde += c
                    if q and _dia_lisboa(q) == hoje:
                        dia += c
                        robo[g.get("perfil") or "?"] += c
        except FileNotFoundError:
            pass
        self.gasto_desde, self.gasto_hoje, self.dia, self.por_robo_hoje = desde, dia, hoje, robo

    def recarregar_config(self, novo=None):
        """O painel muda o credito/interruptores em platform_settings; o laco de fundo chama isto."""
        with self.lock:
            if novo:
                self.cfg.update({k: v for k, v in novo.items() if v is not None})
                self._gravar_json(self.cfg_path, self.cfg)
            self._recontar()

    # ---------- chave e chamada HTTP
    def chave(self):
        return (self.env.get(VAR_CHAVE) or "").strip()

    def _http(self, corpo, timeout):
        req = urllib.request.Request(API, data=json.dumps(corpo).encode("utf-8"), method="POST", headers={
            "x-api-key": self.chave(), "anthropic-version": VERSAO_API, "content-type": "application/json",
            "user-agent": "motor-bora-porteiro/1"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, json.loads(r.read().decode("utf-8") or "{}"), dict(r.headers)
        except urllib.error.HTTPError as e:
            try:
                d = json.loads(e.read().decode("utf-8") or "{}")
            except Exception:  # noqa: BLE001
                d = {}
            return e.code, d, dict(e.headers or {})
        except Exception as e:  # noqa: BLE001  (rede, timeout)
            return 0, {"_erro": "%s: %s" % (type(e).__name__, str(e)[:160])}, {}

    # ---------- a regra
    def contas(self):
        with self.lock:
            if _dia_lisboa() != self.dia:
                self._recontar()
            credito = float(self.cfg.get("credito_usd") or 0)
            gasto_hoje = self.gasto_hoje + float(self.simular.get("gasto_hoje_extra_usd") or 0)
            resta = credito - self.gasto_desde - float(self.simular.get("gasto_hoje_extra_usd") or 0)
            try:
                prox = datetime.date.fromisoformat(str(self.cfg.get("proximo_credito"))[:10])
            except Exception:  # noqa: BLE001
                prox = _dia_lisboa() + datetime.timedelta(days=30)
            dias = max(1, (prox - _dia_lisboa()).days)
            parte = max(0.0, resta + gasto_hoje) / dias
            return {"credito_usd": round(credito, 4), "gasto_desde_leitura_usd": round(self.gasto_desde, 6),
                    "resta_usd": round(resta, 4), "gasto_hoje_usd": round(gasto_hoje, 6), "dias_ate_proximo": dias,
                    "parte_do_dia_usd": round(parte, 4), "proximo_credito": str(prox),
                    "por_robo_hoje_usd": {k: round(v, 6) for k, v in self.por_robo_hoje.items()}}

    def decidir(self, perfil, modelo_pedido=None):
        """-> (pode, motivo, modelo, prioridade)."""
        if perfil not in PERFIS_CLAUDE:
            return False, "perfil sem Claude", None, None
        pr, modelo = PERFIS_CLAUDE[perfil]
        robo = (self.cfg.get("robos") or {}).get(perfil) or {}
        modelo = robo.get("modelo") or modelo
        pr = int(robo.get("prioridade") or pr)
        if modelo_pedido and modelo_pedido in MODELOS_AUTOMATICOS:
            modelo = modelo_pedido
        if modelo not in MODELOS_AUTOMATICOS:
            modelo = "claude-sonnet-5-5" if pr <= 2 else "claude-haiku-5-5"   # Opus nunca automatico
        if not self.cfg.get("ligado", True):
            return False, "Claude desligado no painel", modelo, pr
        if robo.get("usar") is False:
            return False, "Claude desligado para %s" % perfil, modelo, pr
        if not self.chave():
            return False, "sem chave do Claude (%s)" % VAR_CHAVE, modelo, pr
        agora = _agora()
        if self.simular.get("sem_saldo"):
            return False, "sem saldo (simulado no porteiro)", modelo, pr
        if self.dormido_ate and (_iso(self.dormido_ate) or agora) > agora:
            return False, "Claude dormido (sem credito) ate %s" % self.dormido_ate, modelo, pr
        if self.castigo_ate > time.time():
            return False, "Claude em pausa: %s" % (self.castigo_motivo or "erro"), modelo, pr
        c = self.contas()
        if c["resta_usd"] <= 0:
            return False, "credito do mes acabado", modelo, pr
        if pr <= 1:
            return True, "P1 usa enquanto houver credito", modelo, pr
        limite = c["parte_do_dia_usd"] * (1.0 if pr == 2 else 0.5)
        if c["gasto_hoje_usd"] >= limite:
            return False, "parte do dia esgotada para P%d (%.4f de %.4f USD)" % (pr, c["gasto_hoje_usd"], limite), modelo, pr
        return True, "P%d dentro da parte do dia" % pr, modelo, pr

    def _pausar(self, segundos, motivo):
        with self.lock:
            self.castigo_ate = time.time() + segundos
            self.castigo_motivo = motivo
            self._gravar_estado()

    def _dormir(self, motivo):
        with self.lock:
            try:
                prox = datetime.date.fromisoformat(str(self.cfg.get("proximo_credito"))[:10])
            except Exception:  # noqa: BLE001
                prox = _dia_lisboa() + datetime.timedelta(days=30)
            ate = datetime.datetime.combine(prox, datetime.time(0, 5), tzinfo=LISBOA)
            if ate <= _agora():                              # o dia do credito ja passou e continua sem saldo
                ate = _agora() + datetime.timedelta(hours=6)
            self.dormido_ate = ate.astimezone(datetime.timezone.utc).isoformat(timespec="seconds")
            self.castigo_motivo = motivo
            self._gravar_estado()
        self.registar({"evento": "claude-dormido", "ate": self.dormido_ate, "motivo": motivo})

    def _livro(self, linha):
        with self.lock:
            with open(self.livro_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(linha, ensure_ascii=False) + "\n")
            q = _iso(linha["quando"])
            if q and q >= (_iso(self.cfg.get("credito_lido_em")) or q):
                self.gasto_desde += linha["custo_usd"]
            if q and _dia_lisboa(q) == self.dia:
                self.gasto_hoje += linha["custo_usd"]
                self.por_robo_hoje[linha.get("perfil") or "?"] += linha["custo_usd"]

    def tentar(self, perfil, mensagens, tools=None, max_tokens=None, origem="", modelo_pedido=None):
        """-> (resposta_openai | None, info). None = vai para a rotacao gratis (sem erro para ninguem)."""
        pode, motivo, modelo, pr = self.decidir(perfil, modelo_pedido)
        info = {"perfil": perfil, "decisao": "claude" if pode else "gratis", "porque": motivo, "modelo": modelo, "prioridade": pr}
        if not pode:
            self.ultimas.append(dict(info, quando=_agora().isoformat(timespec="seconds")))
            return None, info
        system, msgs, ferramentas = para_anthropic(mensagens, tools, self.blocos)
        comum = self.contexto_comum(pr, perfil)
        if comum:   # bloco comum PRIMEIRO e com a sua propria marca de cache (o resto do system varia por pessoa)
            system = [{"type": "text", "text": comum, "cache_control": {"type": "ephemeral"}}] + (system or [])
        corpo = {"model": modelo, "max_tokens": max(int(max_tokens or 0), 1024), "messages": msgs,
                 "output_config": {"effort": "low"}}
        # sem raciocinio visivel: respostas rapidas e sem blocos thinking para repor (Sonnet 5.5 nao aceita
        # "disabled": usa "between_tools"; Haiku 5.5 aceita "disabled" com effort ate high)
        corpo["thinking"] = {"type": "between_tools"} if modelo == "claude-sonnet-5-5" else {"type": "disabled"}
        if system:
            corpo["system"] = system
        if ferramentas:
            corpo["tools"] = ferramentas
            corpo["tool_choice"] = {"type": "auto"}
        t0 = time.time()
        st, d, h = self.http(corpo, TIMEOUT_S)
        ms = int((time.time() - t0) * 1000)
        erro_txt = json.dumps((d or {}).get("error") or (d or {}).get("_erro") or "", ensure_ascii=False)[:300]
        if st == 200 and isinstance(d, dict) and d.get("stop_reason") != "refusal" and (d.get("content") is not None):
            r = para_openai(d, modelo)
            u = r["usage"]
            if not r["choices"][0]["message"].get("content") and not r["choices"][0]["message"].get("tool_calls"):
                st, erro_txt = -1, "resposta vazia"
            else:
                for tc in r["choices"][0]["message"].get("tool_calls") or []:
                    self.blocos[tc["id"]] = d.get("content")
                while len(self.blocos) > 500:
                    self.blocos.popitem(last=False)
                linha = {"quando": _agora().isoformat(timespec="seconds"), "maquina": "vps", "robo": (origem or "")[:60] or None,
                         "perfil": perfil, "prioridade": pr, "modelo": modelo,
                         "tokens_entrada": int((d.get("usage") or {}).get("input_tokens") or 0), "tokens_saida": u["completion_tokens"],
                         "tokens_cache_escrita": u["cache_creation_input_tokens"], "tokens_cache_leitura": u["cache_read_input_tokens"],
                         "custo_usd": u["custo_usd"], "ms": ms, "ok": True}
                self._livro(linha)
                info.update(ms=ms, custo_usd=u["custo_usd"], cache_leitura=u["cache_read_input_tokens"], cache_escrita=u["cache_creation_input_tokens"])
                self.ultimas.append(dict(info, quando=linha["quando"]))
                r["motor"] = {"fornecedor": "claude", "modelo": modelo, "latencia_ms": ms, "perfil": perfil, "porteiro": info}
                return r, info
        # falhou: classificar e mandar para o gratis
        txt = erro_txt.lower()
        if st == 402 or (st == 400 and ("credit balance" in txt or "billing" in txt)):
            self._dormir("sem saldo: HTTP %s %s" % (st, erro_txt[:120]))
        elif st in (401, 403):
            self._pausar(6 * 3600, "chave recusada HTTP %s" % st)
        elif st == 404:
            self._pausar(6 * 3600, "modelo %s nao encontrado" % modelo)
        elif st == 429:
            try:
                seg = max(60, int(float((h or {}).get("retry-after") or (h or {}).get("Retry-After") or 60)))
            except Exception:  # noqa: BLE001
                seg = 60
            self._pausar(seg, "429 limite de pedidos")
        elif st == 0 or st >= 500 or st == 529:
            self._pausar(60, "HTTP %s %s" % (st, erro_txt[:80]))
        info.update(decisao="gratis", porque="Claude falhou: HTTP %s %s" % (st, erro_txt[:160]), ms=ms)
        self.ultimas.append(dict(info, quando=_agora().isoformat(timespec="seconds")))
        self.registar({"evento": "claude-falhou", "perfil": perfil, "status": st, "ms": ms, "erro": erro_txt[:200]})
        return None, info

    # ---------- acordar no dia do credito novo
    def talvez_acordar(self):
        if not self.dormido_ate or not self.chave():
            return None
        if (_iso(self.dormido_ate) or _agora()) > _agora():
            return None
        corpo = {"model": "claude-haiku-5-5", "max_tokens": 1, "thinking": {"type": "disabled"},
                 "output_config": {"effort": "low"}, "messages": [{"role": "user", "content": "ok"}]}
        st, d, _ = self.http(corpo, TIMEOUT_S)
        if st == 200:
            with self.lock:
                hoje = _dia_lisboa()
                try:
                    prox = datetime.date.fromisoformat(str(self.cfg.get("proximo_credito"))[:10])
                except Exception:  # noqa: BLE001
                    prox = hoje
                while prox <= hoje:                          # o proximo passa para o mes seguinte
                    m = prox.month + 1
                    prox = prox.replace(year=prox.year + (m > 12), month=(m - 1) % 12 + 1)
                self.cfg.update(credito_usd=float(self.cfg.get("credito_mensal_usd") or 200), credito_lido_em=_agora().isoformat(timespec="seconds"),
                                proximo_credito=str(prox), credito_estimado=True)
                self._gravar_json(self.cfg_path, self.cfg)
                self.dormido_ate, self.castigo_motivo = None, None
                self._gravar_estado()
                self._recontar()
            self.registar({"evento": "claude-acordou", "credito_usd": self.cfg["credito_usd"], "proximo": self.cfg["proximo_credito"]})
            return True
        self._dormir("ainda sem saldo no teste de acordar: HTTP %s" % st)
        return False

    # ---------- livro de gastos -> Supabase (ia_gastos), quando a tabela existir
    def sincronizar(self):
        if not self.supa:
            return 0
        try:
            pos = int(open(self.sync_path).read().strip() or 0)
        except Exception:  # noqa: BLE001
            pos = 0
        try:
            with open(self.livro_path, encoding="utf-8") as fh:
                fh.seek(pos)
                linhas = fh.readlines()
                fim = fh.tell()
        except FileNotFoundError:
            return 0
        lote = []
        for ln in linhas:
            try:
                lote.append(json.loads(ln))
            except Exception:  # noqa: BLE001
                pass
        if not lote:
            return 0
        try:
            self.supa.insert("ia_gastos", lote, devolve=False)
        except Exception as e:  # noqa: BLE001
            agora = time.time()
            if agora - getattr(self, "_ultimo_aviso_sync", 0) > 3600:
                self._ultimo_aviso_sync = agora
                self.registar({"evento": "ia-gastos-sync-erro", "erro": str(e)[:160], "pendentes": len(lote)})
            return 0
        with open(self.sync_path, "w") as fh:
            fh.write(str(fim))
        return len(lote)

    # ---------- Bloco 4: o livro e as licoes em cache no inicio de cada pedido
    def carregar_contexto(self, forcar=False):
        """Le do Supabase (so leitura) as paginas regras-do-danilo e erros-aprendidos do livro comum e as licoes
        ativas dos robos (public.licoes_robos; sem a tabela, fica vazio). Renova de 6 em 6 h."""
        if not self.supa or (not forcar and time.time() - self.ctx_lido < CONTEXTO_TTL_S):
            return False
        self.ctx_lido = time.time()
        try:
            pags = self.supa.select("claude_ai_memoria", select="pagina,conteudo", pagina="in.(regras-do-danilo,erros-aprendidos)", limit="5")
            self.ctx_paginas = {p["pagina"]: (p.get("conteudo") or "")[:12000] for p in pags or []}
        except Exception as e:  # noqa: BLE001
            self.registar({"evento": "porteiro-livro-erro", "erro": str(e)[:160]})
        try:
            self.ctx_licoes = self.supa.select("licoes_robos", select="robo,errou,regra", ativa="eq.true", order="criada_em.desc", limit="200") or []
        except Exception:  # noqa: BLE001  (tabela ainda nao criada: migracao no passo PUBLICAR)
            self.ctx_licoes = []
        return True

    def contexto_comum(self, prioridade, perfil):
        """P1 (clientes): regras fixas do que nunca se diz + licoes ativas. P2/P3 (Emerson, decisoes, agentes):
        tambem as regras do Danilo e os erros aprendidos do livro (nunca vao para conversas com clientes)."""
        partes = [NUNCA_SE_DIZ]
        lic = [x for x in self.ctx_licoes if (x.get("robo") or "todos") in ("todos", perfil) or perfil.startswith("claude-")]
        if lic:
            partes.append("LICOES ATIVAS DOS ROBOS (erros que ja se cometeram; nao repetir):\n" + "\n".join(
                "- [%s] errou: %s -> regra: %s" % (x.get("robo"), (x.get("errou") or "")[:200], (x.get("regra") or "")[:240]) for x in lic[:120]))
        if (prioridade or 3) >= 2 and self.ctx_paginas:
            for nome in ("regras-do-danilo", "erros-aprendidos"):
                if self.ctx_paginas.get(nome):
                    partes.append("LIVRO COMUM, pagina %s:\n%s" % (nome, self.ctx_paginas[nome]))
        return "\n\n".join(partes)

    def ler_painel(self):
        """platform_settings claude_* (editaveis no painel) -> config local. Sem tabela/chaves: nada muda.
        Aproveita a volta para renovar o livro e as licoes (de 6 em 6 h)."""
        if not self.supa:
            return False
        self.carregar_contexto()
        try:
            rows = self.supa.select("platform_settings", select="key,value", key="like.claude_*", limit="20")
        except Exception:  # noqa: BLE001
            return False
        v = {r["key"]: r.get("value") for r in rows or []}
        if not v:
            return False
        novo = {}
        if "claude_credito_atual_usd" in v:
            novo["credito_usd"] = float(v["claude_credito_atual_usd"])
        if "claude_credito_lido_em" in v:
            novo["credito_lido_em"] = v["claude_credito_lido_em"]
        if "claude_proximo_credito" in v:
            novo["proximo_credito"] = v["claude_proximo_credito"]
        if "claude_credito_mensal_usd" in v:
            novo["credito_mensal_usd"] = float(v["claude_credito_mensal_usd"])
        if isinstance(v.get("claude_robos"), dict):
            rb = v["claude_robos"]
            novo["ligado"] = rb.get("ligado", True)
            novo["robos"] = {k: x for k, x in rb.items() if isinstance(x, dict)}
        # so mexe se mudou alguma coisa (evita reescrever o ficheiro a cada volta)
        if any(self.cfg.get(k) != x for k, x in novo.items()):
            self.recarregar_config(novo)
            self.registar({"evento": "porteiro-config-do-painel", "chaves": sorted(novo)})
            return True
        return False

    def estado(self):
        return {"ligado": self.cfg.get("ligado", True), "tem_chave": bool(self.chave()), "dormido_ate": self.dormido_ate,
                "pausa_ate": datetime.datetime.fromtimestamp(self.castigo_ate, datetime.timezone.utc).isoformat(timespec="seconds") if self.castigo_ate > time.time() else None,
                "pausa_motivo": self.castigo_motivo if self.castigo_ate > time.time() or self.dormido_ate else None,
                "simular": self.simular, "contas": self.contas(), "robos": self.cfg.get("robos"),
                "contexto": {"paginas": {k: len(v) for k, v in self.ctx_paginas.items()}, "licoes_ativas": len(self.ctx_licoes),
                             "lido": datetime.datetime.fromtimestamp(self.ctx_lido, datetime.timezone.utc).isoformat(timespec="seconds") if self.ctx_lido else None},
                "decisoes": {p: self.decidir(p)[:2] for p in PERFIS_CLAUDE}, "ultimas": list(self.ultimas)[-10:]}
