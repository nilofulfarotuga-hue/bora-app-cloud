"""Servidor do Assistente de Negocio (VPS, 127.0.0.1:8795). A porta vps-baileys (ligar.js) fala com ele:

  POST /evento      {numero, texto, msg_id, grupo, quoted_id, push_name, audio_b64, mime}
                    -> {tratado, acao}. tratado=false: a mensagem nao e de nenhum assistente; a porta segue
                       o caminho antigo (cerebro da Bora, que continua PAUSADO).
  GET  /pendentes   fila de saida do assistente (independente do interruptor da Bora)
  POST /enviado     {id, ok, estado, msg_id, erro} — aviso de entrega da propria WhatsApp
  POST /dono-falou  {numero} — alguem escreveu a mao nesta conversa: robo calado 12 h
  GET  /saude

As rotinas correm numa thread, de minuto a minuto."""
import base64
import json
import os
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)


def carregar_env(caminho):
    try:
        for l in open(caminho, encoding="utf-8"):
            l = l.strip()
            if l and not l.startswith("#") and "=" in l:
                k, v = l.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))
    except OSError:
        pass


carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))

import assistente as A  # noqa: E402
import db  # noqa: E402
import rotinas  # noqa: E402

SESSAO = os.environ.get("ASSISTENTE_SESSAO", "vps-baileys:351937501673")
PORTA = int(os.environ.get("ASSISTENTE_PORT", "8795"))
LOG = os.environ.get("ASSISTENTE_LOG", os.path.join(AQUI, "assistente.log"))
_trancas, _tranca_geral = {}, threading.Lock()


def log(*a):
    l = time.strftime("%Y-%m-%dT%H:%M:%S") + " " + " ".join(str(x) for x in a)
    print(l, flush=True)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(l + "\n")
    except OSError:
        pass


def tranca_de(numero):
    with _tranca_geral:
        return _trancas.setdefault(numero, threading.Lock())


def transcrever(b64, mime):
    """Nota de voz -> texto (Groq whisper). Sem chave ou erro: devolve ''."""
    import urllib.request
    chave = os.environ.get("GROQ_API_KEY", "")
    if not chave:
        return ""
    fronteira = "----assistente" + str(int(time.time() * 1000))
    corpo = (f"--{fronteira}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"
             f"--{fronteira}\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\npt\r\n"
             f"--{fronteira}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voz.ogg\"\r\nContent-Type: {mime or 'audio/ogg'}\r\n\r\n").encode()
    corpo += base64.b64decode(b64) + f"\r\n--{fronteira}--\r\n".encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/audio/transcriptions", corpo,
                                 {"Authorization": "Bearer " + chave, "Content-Type": "multipart/form-data; boundary=" + fronteira,
                                  "User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return (json.load(r).get("text") or "").strip()
    except Exception as e:
        log("transcricao falhou", e)
        return ""


def pendentes():
    t_cache = {}
    linhas = db.ler("assistant_messages", "direcao=eq.saida&entrega_estado=eq.pendente&order=created_at.asc&limit=5",
                    "id,tenant_id,numero,texto,motivo,created_at")
    saida = []
    for m in linhas:
        t = t_cache.get(m["tenant_id"]) or A.tenant_por_id(m["tenant_id"])
        t_cache[m["tenant_id"]] = t
        if not t or not A.pode_escrever_a(t, m["numero"]):  # segunda rede de seguranca, ja na saida
            db.atualizar("assistant_messages", f"id=eq.{m['id']}", {"entrega_estado": "bloqueado", "entrega_erro": "fora da allowlist/modo"})
            continue
        if time.time() - A.hora_local(m["created_at"]).timestamp() > 1800:  # nunca mandar rajadas velhas
            db.atualizar("assistant_messages", f"id=eq.{m['id']}", {"entrega_estado": "falhou", "entrega_erro": "ficou mais de 30 min na fila"})
            continue
        db.atualizar("assistant_messages", f"id=eq.{m['id']}", {"entrega_estado": "a-enviar"})
        saida.append({"id": "an-" + str(m["id"]), "numero": m["numero"], "texto": m["texto"], "motivo": m.get("motivo")})
    return saida


def enviado(d):
    mid = int(str(d.get("id", "")).replace("an-", "") or 0)
    estado = d.get("estado") or ("entregue" if d.get("ok") else "falhou")
    campos = {"entrega_estado": estado, "entrega_erro": d.get("erro")}
    if d.get("msg_id"):
        campos["msg_id_wa"] = d["msg_id"]
    if estado in ("entregue", "visto", "a-caminho"):
        campos["enviada_em"] = A.iso(A.agora())
    r = db.atualizar("assistant_messages", f"id=eq.{mid}", campos)
    if r and d.get("msg_id") and str(r[0].get("motivo") or "").startswith("pergunta_dono:"):
        db.atualizar("assistant_tasks", f"id=eq.{r[0]['motivo'].split(':', 1)[1]}", {"msg_id_wa": d["msg_id"]})
    return {"ok": True}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        try:
            if self.path.startswith("/pendentes"):
                return self._json(200, {"mensagens": pendentes()})
            if self.path.startswith("/saude"):
                return self._json(200, {"ok": True, "sessao": SESSAO, "tenants": [
                    {"nome": t["nome"], "mode": t["mode"]} for t in db.ler("assistant_tenants", "", "nome,mode")]})
            self._json(404, {"erro": "nao existe"})
        except Exception as e:
            log("GET erro", self.path, e)
            self._json(500, {"erro": str(e)[:200]})

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            d = json.loads(self.rfile.read(n) or b"{}")
            if self.path.startswith("/evento"):
                d.setdefault("sessao", SESSAO)
                t, _ = A.tenant_para(d["sessao"], d.get("numero"))
                if not t:
                    return self._json(200, {"tratado": False, "acao": "nao-e-do-assistente"})
                if not d.get("texto") and d.get("audio_b64"):
                    d["texto"] = transcrever(d["audio_b64"], d.get("mime"))
                with tranca_de(A.so_digitos(d.get("numero"))):
                    r = A.atender(d)
                log("evento", d.get("numero"), r.get("acao"), r.get("ferramentas"), r.get("modelos"), r.get("erro_motor") or "")
                return self._json(200, r)
            if self.path.startswith("/enviado"):
                return self._json(200, enviado(d))
            if self.path.startswith("/dono-falou"):
                r = A.dono_falou(d.get("sessao") or SESSAO, d.get("numero"))
                log("dono-falou", d.get("numero"), r)
                return self._json(200, r)
            self._json(404, {"erro": "nao existe"})
        except Exception as e:
            log("POST erro", self.path, e, traceback.format_exc()[-600:])
            self._json(500, {"tratado": False, "erro": str(e)[:200]})


def laco_rotinas():
    while True:
        try:
            r = rotinas.ciclo()
            if any(k.endswith("_erro") for k in r):
                log("rotinas", r)
        except Exception as e:
            log("rotinas falharam", e)
        time.sleep(60)


if __name__ == "__main__":
    if os.environ.get("ASSISTENTE_ROTINAS", "1") == "1":
        threading.Thread(target=laco_rotinas, daemon=True).start()
    log("ASSISTENTE no ar", PORTA, SESSAO)
    ThreadingHTTPServer(("127.0.0.1", PORTA), H).serve_forever()
