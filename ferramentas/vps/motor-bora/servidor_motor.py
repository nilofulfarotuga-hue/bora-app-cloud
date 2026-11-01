# -*- coding: utf-8 -*-
"""servidor_motor.py  [31/10/2026 missao motor-claude: porteiro do Claude] — o Motor Bora como servico HTTP local (compativel OpenAI), porta 8792.

  POST /v1/chat/completions   model = "perfil:chat-rapido" | "perfil:raciocinio" | "perfil:volume" | "perfil:visao"
                              | "groq:openai/gpt-oss-120b" | id solto (procura-se). stream=true -> SSE com uma so fatia.
  GET  /v1/models             perfis + modelos vivos (com context_length, que o Hermes exige >= 64k)
  GET  /saude  /motores  /perfis      POST /pausar {fornecedor, pausado}   POST /autoteste   POST /descobrir
Ambiente: le os .env do Motor, do cerebro do WhatsApp e do Hermes (chaves ficam la; nunca se imprimem).
PC: 127.0.0.1:8792 · VPS: 127.0.0.1 e 172.16.1.1 (gateway docker, para o Hermes e o Conselho), MOTOR_BINDS.
"""
import datetime
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from motor_bora import Roteador  # noqa: E402
from motor_bora import catalogo as C  # noqa: E402

PORT = int(os.environ.get("MOTOR_PORT", "8792"))
BINDS = [b.strip() for b in os.environ.get("MOTOR_BINDS", "127.0.0.1").split(",") if b.strip()]
# 01/11/2026 (missao infra-claude-tudo): porta FECHADA (com senha) para quem vem de fora da VPS (o Dipsy do PC,
# pela Tailscale: o `tailscale serve` do contentor do Hermes encaminha <ip-tailscale>:8792 -> 172.16.1.1:8793).
# Exige o cabecalho X-Porteiro-Token (ou Authorization: Bearer) igual ao que esta em /opt/segredos/porteiro.env.
# So deixa conversar e ler o estado; nada de /pausar, /simular, /autoteste.
BINDS_FECHADOS = [b.strip() for b in os.environ.get("MOTOR_BINDS_FECHADOS", "").split(",") if b.strip()]
PORTEIRO_ENV = os.environ.get("PORTEIRO_ENV", "/opt/segredos/porteiro.env")
CAMINHOS_FECHADOS = {"GET": ("/porteiro", "/v1/models", "/models", "/saude", "/health"),
                     "POST": ("/v1/chat/completions", "/chat/completions")}


def _ler_senha():
    try:
        for ln in open(PORTEIRO_ENV, encoding="utf-8"):
            k, _, v = ln.strip().partition("=")
            if k == "PORTEIRO_TOKEN":
                return v.strip().strip('"').strip("'")
    except Exception:  # noqa: BLE001
        pass
    return ""
MAQUINA = os.environ.get("MOTOR_MAQUINA") or ("vps" if os.path.exists("/opt/whatsapp-bora") else "pc")
LOG = os.path.join(AQUI, "motor.log.jsonl")
ESTADO = os.path.join(AQUI, "_estado.json")
MOTORES_MD = os.path.join(AQUI, "MOTORES.md")
CEREBRO_DIRS = [os.environ.get("MOTOR_CEREBRO_DIR") or "", os.path.join(AQUI, "..", "whatsapp-loja"), "/opt/whatsapp-bora"]
ENV_FILES = ["/opt/segredos/claude.env", os.path.join(AQUI, ".env"), os.path.join(AQUI, "..", "whatsapp-loja", "cerebro", ".env"), "/opt/whatsapp-bora/.env", "/opt/data/.env",
             r"C:\BoraLocal\projetosflutter\bora_app\backend\.env"] + [p for p in (os.environ.get("MOTOR_ENV_FILES") or "").split(";") if p]


def registar(obj):
    obj = dict(obj, ts=datetime.datetime.now().isoformat(timespec="seconds"))
    try:
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass


def ler_env():
    env = {}
    for p in ENV_FILES:
        try:
            if p and os.path.exists(p):
                for ln in open(p, encoding="utf-8"):
                    ln = ln.strip()
                    if ln and not ln.startswith("#") and "=" in ln:
                        k, v = ln.split("=", 1)
                        k, v = k.strip(), v.strip().strip('"').strip("'")
                        if k and v and k not in env:
                            env[k] = v
        except Exception:
            pass
    for k, v in os.environ.items():
        env.setdefault(k, v)
    return env


def _cerebro():
    """O cerebro do WhatsApp (mesma maquina) da o supa (estado no Supabase), o telegram e o prompt real."""
    for d in CEREBRO_DIRS:
        if d and os.path.exists(os.path.join(d, "cerebro", "supa.py")):
            if d not in sys.path:
                sys.path.insert(0, d)
            try:
                from cerebro import supa, telegram  # noqa: E402
                return supa, telegram, d
            except Exception as e:  # noqa: BLE001
                registar({"evento": "cerebro-import-falhou", "dir": d, "erro": str(e)[:160]})
    return None, None, None


SUPA, TELEGRAM, CEREBRO_DIR = _cerebro()


def avisar(texto):
    if TELEGRAM:
        try:
            TELEGRAM.enviar(texto, registar)
        except Exception as e:  # noqa: BLE001
            registar({"evento": "telegram-erro", "erro": str(e)[:120]})
    registar({"evento": "aviso", "texto": texto[:300]})


R = Roteador(ler_env(), maquina=MAQUINA, estado_path=ESTADO, avisar=avisar, registar=registar, supa=SUPA)
# 31/10/2026 (missao motor-claude): porteiro do credito do Claude (Claude primeiro, gratis depois)
from motor_bora.porteiro import Porteiro  # noqa: E402
R.porteiro = Porteiro(R.env, AQUI, registar=registar, supa=SUPA)


def prompt_real():
    try:
        from cerebro import agente, fichas  # noqa: E402
        return agente._sistema_rapido(fichas.nova("351000000000"), "neutro", "pt-PT", "voce")
    except Exception:
        return None


def escrever_motores_md(relatorio=None):
    est = R.estado()
    ls = ["# MOTORES — o roteador Motor Bora (%s), gerado %s" % (MAQUINA, datetime.datetime.now().isoformat(timespec="minutes")),
          "", "Chaves vivem so nos `.env` (PC: `motor-bora/.env` + `whatsapp-loja/cerebro/.env`; VPS: `/opt/whatsapp-bora/.env` + `/opt/data/.env`).",
          "Perfis: `chat-rapido` (WhatsApp ao vivo) · `raciocinio` (juiz, revisão, propostas) · `volume` (lotes) · `visao` · `audio`.",
          "", "| fornecedor | chave | hoje (pedidos/ok/falhas) | tokens hoje | latência mediana | castigado | último erro | nota |", "|---|---|---|---|---|---|---|---|"]
    lim = lambda s, n: " ".join(str(s or "").split())[:n].replace("|", "/")     # uma linha, sem quebrar a tabela
    for f, e in est.items():
        h = e["hoje"]
        ls.append("| %s | %s | %d/%d/%d | %d | %s | %s | %s | %s |" % (
            f, "sim" if e["chave"] else ("opcional" if C.FORNECEDORES[f].get("opcional") or not C.FORNECEDORES[f].get("chave") else "**sem chave**"),
            h["pedidos"], h["ok"], h["falhas"], h["tokens"], ("%d ms" % e["latencia_mediana_ms"]) if e["latencia_mediana_ms"] else "—",
            lim((e["castigado_ate"] or "") + (" (" + (e["castigo_motivo"] or "")[:40] + ")" if e["castigo_motivo"] else ""), 70) if e["castigado_ate"] else ("modelos: " + ", ".join(e["modelos_castigados"][:3]) if e["modelos_castigados"] else "não"),
            lim(e["ultimo_erro"], 60), lim(e["nota"], 70)))
    total = sum((e.get("custo_simulado_eur_hoje") or 0) for e in est.values())
    ls += ["", "**Custo simulado de hoje: %.4f €** (não se paga nada — é o que isto custaria ao preço de tabela "
                "dos modelos pagos equivalentes; por fornecedor na coluna abaixo)." % total, ""]
    ls += ["| fornecedor | custo simulado hoje (€) | pedidos na última hora |", "|---|---|---|"]
    for f, e in est.items():
        if e["hoje"]["pedidos"]:
            ls.append("| %s | %.4f | %d |" % (f, e.get("custo_simulado_eur_hoje") or 0, e.get("ultima_hora") or 0))
    ls += ["", "## Ordem por perfil (o auto-teste das 05:30 reordena; `rodizio` roda entre os melhores a cada pedido)"]
    for p, o in R.ordem.items():
        modo = (C.PERFIS.get(p) or {}).get("modo", "cadeia")
        topo = (C.PERFIS.get(p) or {}).get("rodizio_topo")
        ls.append("- **%s** (%s%s): " % (p, modo, (", topo %d" % topo) if modo == "rodizio" and topo else "") + " → ".join("%s:%s" % x for x in o))
    if R.retirados:
        ls += ["", "## Modelos retirados sozinhos (a vigia apanhou 'já não existe')", "| modelo | quando | estado | motivo |", "|---|---|---|---|"]
        for k, v in R.retirados.items():
            ls.append("| %s | %s | %s | %s |" % (k, v.get("quando"), v.get("status"), lim(v.get("motivo"), 90)))
    if relatorio:
        ls += ["", "## Auto-teste %s (3 perguntas reais a cada motor)" % (R.autoteste_ultimo or "")]
        for p, rs in relatorio.items():
            ls += ["", "### " + p, "| motor | latência média | pontos (0–9) | erro |", "|---|---|---|---|"]
            for x in rs:
                ls.append("| %s:%s | %s | %s | %s |" % (x["fornecedor"], x["modelo"], ("%d ms" % x["latencia_ms"]) if x["latencia_ms"] else "—", x["pontos"] if x["pontos"] is not None else "—", (x["erro"] or "")[:60].replace("|", "/")))
    # NOTAS FIXAS (04/09): este ficheiro e reescrito de 10 em 10 minutos, por isso tudo o que
    # se escrevia a mao aqui durava 10 minutos e desaparecia sem aviso. As decisoes vivem em
    # NOTAS.md, ao lado, e sao coladas no fim de cada geracao.
    try:
        _notas = os.path.join(AQUI, "NOTAS.md")
        if os.path.exists(_notas):
            ls += ["", "---", ""]
            ls.append(open(_notas, encoding="utf-8", errors="replace").read().rstrip())
    except Exception as e:  # noqa: BLE001
        registar({"evento": "notas-md-erro", "erro": str(e)[:120]})
    try:
        with open(MOTORES_MD, "w", encoding="utf-8") as fh:
            fh.write("\n".join(ls) + "\n")
    except Exception as e:  # noqa: BLE001
        registar({"evento": "motores-md-erro", "erro": str(e)[:120]})


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False, default=str).encode("utf-8")
        if code != 200 or not self.path.startswith(("/saude", "/motores")):
            registar({"evento": "http", "metodo": self.command, "caminho": self.path[:120], "codigo": code, "ua": (self.headers.get("User-Agent") or "")[:60],
                      "de": self.client_address[0]})
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _barrado(self):
        """Na porta com senha: True (e ja respondeu) se o pedido nao traz a senha ou nao e permitido."""
        if not getattr(self.server, "com_token", False):
            return False
        import hmac
        esperado = getattr(self.server, "token", "") or ""
        dado = (self.headers.get("X-Porteiro-Token") or "").strip()
        if not dado:
            a = (self.headers.get("Authorization") or "").strip()
            dado = a[7:].strip() if a.lower().startswith("bearer ") else ""
        if not esperado or not dado or not hmac.compare_digest(dado.encode(), esperado.encode()):
            self._json(401, {"error": {"message": "sem senha do porteiro"}})
            return True
        if self.path.split("?")[0] not in CAMINHOS_FECHADOS.get(self.command, ()):
            self._json(403, {"error": {"message": "caminho fechado nesta porta"}})
            return True
        return False

    def _corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            return {}

    def do_GET(self):
        if self._barrado():
            return
        p = self.path.split("?")[0]
        if p in ("/saude", "/health"):
            est = R.estado()
            return self._json(200, {"ok": True, "servico": "motor-bora", "maquina": MAQUINA, "versao": "v1-2026-09-02",
                                    "com_chave": [f for f, e in est.items() if e["chave"]], "pausados": sorted(R.pausados),
                                    "castigados": [f for f, e in est.items() if e["castigado_ate"]], "supabase": bool(SUPA), "autoteste_ultimo": R.autoteste_ultimo})
        if p == "/motores":
            return self._json(200, {"maquina": MAQUINA, "fornecedores": R.estado(), "ordem": {k: ["%s:%s" % x for x in v] for k, v in R.ordem.items()}})
        if p == "/perfis":
            return self._json(200, {k: {"timeout": v.get("timeout"), "orcamento": v.get("orcamento"), "candidatos": ["%s:%s" % x for x in R.ordem.get(k, [])]} for k, v in C.PERFIS.items()})
        if p == "/porteiro":
            return self._json(200, R.porteiro.estado())
        if p in ("/v1/models", "/models"):
            agora = int(time.time())
            data = [{"id": "perfil:" + k, "object": "model", "created": agora, "owned_by": "motor-bora", "context_length": 131072, "max_model_len": 131072} for k in C.PERFIS]
            for forn, ids in R.modelos_vivos.items():
                for i in sorted(ids)[:80]:
                    data.append({"id": forn + ":" + i, "object": "model", "created": agora, "owned_by": forn, "context_length": 131072, "max_model_len": 131072})
            return self._json(200, {"object": "list", "data": data})
        return self._json(404, {"error": {"message": "nao encontrado"}})

    def do_POST(self):
        if self._barrado():
            return
        p = self.path.split("?")[0]
        d = self._corpo()
        try:
            if p in ("/v1/chat/completions", "/chat/completions"):
                t0 = time.time()
                ua = self.headers.get("User-Agent", "")[:40]
                # "undici" e o OmniRoute (Node): por ele passam o Hermes/Emerson, a torre, o critico e o despachante
                origem = self.headers.get("X-Motor-Origem") or ("dipsy" if getattr(self.server, "com_token", False) else
                                                                ("hermes-omniroute" if ua.startswith("undici") else ua))
                r = R.chamar(d.get("model") or "perfil:chat-rapido", d.get("messages") or [], tools=d.get("tools"), max_tokens=d.get("max_tokens"),
                             temperatura=d.get("temperature", 0.2) or 0.2, origem=origem)
                if r.get("error"):
                    registar({"evento": "falha-total", "modelo": d.get("model"), "tentativas": r.get("tentativas")})
                    return self._json(503, {"error": r["error"]})
                r.setdefault("id", "motor-%d" % int(t0 * 1000))
                r.setdefault("object", "chat.completion")
                r.setdefault("created", int(t0))
                if d.get("stream"):
                    # streaming: UMA fatia com a resposta inteira + [DONE] (o Hermes pede stream; a resposta e curta)
                    ch = r["choices"][0]
                    fatia = {"id": r["id"], "object": "chat.completion.chunk", "created": r["created"], "model": r["model"],
                             "choices": [{"index": 0, "delta": {"role": "assistant", "content": ch["message"].get("content", ""), "tool_calls": ch["message"].get("tool_calls")},
                                          "finish_reason": ch.get("finish_reason") or "stop"}]}
                    body = ("data: " + json.dumps(fatia, ensure_ascii=False) + "\n\ndata: [DONE]\n\n").encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                return self._json(200, r)
            if p == "/porteiro/simular":
                # so para provas: muda a MEMORIA do porteiro, nada na Console. Um reinicio repoe tudo.
                if "sem_saldo" in d:
                    R.porteiro.simular["sem_saldo"] = bool(d["sem_saldo"])
                if "gasto_hoje_extra_usd" in d:
                    R.porteiro.simular["gasto_hoje_extra_usd"] = float(d["gasto_hoje_extra_usd"] or 0)
                registar({"evento": "porteiro-simular", "simular": dict(R.porteiro.simular)})
                return self._json(200, {"ok": True, "simular": R.porteiro.simular, "decisoes": R.porteiro.estado()["decisoes"]})
            if p == "/porteiro/recarregar":
                R.porteiro.recarregar_config(d.get("config") if isinstance(d.get("config"), dict) else None)
                return self._json(200, {"ok": True, "contas": R.porteiro.contas()})
            if p == "/pausar":
                f = d.get("fornecedor")
                if f not in C.FORNECEDORES:
                    return self._json(400, {"error": "fornecedor desconhecido"})
                if d.get("pausado", True):
                    R.pausados.add(f)
                else:
                    R.pausados.discard(f)
                if SUPA:
                    try:
                        SUPA.upsert("motor_estado", {"fornecedor": f, "pausado": f in R.pausados, "dados": R.estado()[f]}, "fornecedor")
                    except Exception:
                        pass
                R.guardar_estado()
                return self._json(200, {"ok": True, "pausados": sorted(R.pausados)})
            if p == "/autoteste":
                rel = R.autoteste(prompt_real(), tuple(d.get("perfis") or ("chat-rapido", "raciocinio")))
                escrever_motores_md(rel)
                return self._json(200, {"ok": True, "relatorio": rel, "ordem": {k: ["%s:%s" % x for x in v] for k, v in R.ordem.items()}})
            if p == "/descobrir":
                R.descobrir()
                return self._json(200, {"ok": True, "modelos_vivos": {f: sorted(v)[:40] for f, v in R.modelos_vivos.items()}})
            return self._json(404, {"error": {"message": "nao encontrado"}})
        except Exception as e:  # noqa: BLE001
            registar({"evento": "http-erro", "caminho": p, "erro": "%s: %s" % (type(e).__name__, str(e)[:300])})
            return self._json(500, {"error": {"message": str(e)[:300]}})

    def log_message(self, *a):
        pass


def _laco_fundo():
    ultimo_desc, ultimo_sync, ultimo_md = 0, 0, 0
    while True:
        try:
            agora = time.time()
            if agora - ultimo_desc > 6 * 3600:
                ultimo_desc = agora
                R.descobrir()
                R.guardar_estado()
            if agora - ultimo_sync > 20:
                ultimo_sync = agora
                R.guardar_estado()
                R.sincronizar_supabase()
            if agora - getattr(R.porteiro, "_ult_sync", 0) > 60:      # livro de gastos -> ia_gastos
                R.porteiro._ult_sync = agora
                R.porteiro.sincronizar()
            if agora - getattr(R.porteiro, "_ult_painel", 0) > 600:   # painel (platform_settings claude_*)
                R.porteiro._ult_painel = agora
                R.porteiro.ler_painel()
            if agora - getattr(R.porteiro, "_ult_acordar", 0) > 3600:  # dia do credito novo: volta sozinho
                R.porteiro._ult_acordar = agora
                R.porteiro.talvez_acordar()
            if agora - ultimo_md > 600:
                ultimo_md = agora
                escrever_motores_md()
            h = datetime.datetime.now()
            if h.hour == 5 and 30 <= h.minute < 36 and (R.autoteste_ultimo or "")[:10] != h.date().isoformat():
                rel = R.autoteste(prompt_real())
                escrever_motores_md(rel)
        except Exception as e:  # noqa: BLE001
            registar({"evento": "fundo-erro", "erro": "%s: %s" % (type(e).__name__, str(e)[:200])})
        time.sleep(5)


def main():
    servidores = []
    for b in BINDS:
        try:
            servidores.append(ThreadingHTTPServer((b, PORT), H))
        except OSError as e:
            print("MOTOR: nao consegui ouvir em %s:%d (%s)" % (b, PORT, e), flush=True)
    if not servidores:
        return
    token = _ler_senha()
    for b in BINDS_FECHADOS:
        if not token:
            print("MOTOR: sem PORTEIRO_TOKEN em %s: porta com senha NAO abre" % PORTEIRO_ENV, flush=True)
            break
        host, _, porta = b.rpartition(":")
        try:
            s = ThreadingHTTPServer((host, int(porta)), H)
            s.com_token, s.token = True, token
            servidores.append(s)
        except (OSError, ValueError) as e:
            print("MOTOR: nao consegui ouvir (com senha) em %s (%s)" % (b, e), flush=True)
    registar({"evento": "arranque", "maquina": MAQUINA, "binds": BINDS, "porta": PORT, "binds_com_senha": BINDS_FECHADOS if token else [],
              "com_chave": [f for f in C.FORNECEDORES if R.tem_chave(f)]})
    threading.Thread(target=_laco_fundo, daemon=True).start()
    print("MOTOR_BORA_ONLINE %s http://%s:%d" % (MAQUINA, BINDS[0], PORT), flush=True)
    for s in servidores[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    servidores[0].serve_forever()


if __name__ == "__main__":
    main()
