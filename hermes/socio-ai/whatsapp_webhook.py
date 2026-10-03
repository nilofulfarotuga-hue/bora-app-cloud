#!/usr/bin/env python3
"""
whatsapp_webhook.py — receiver do WhatsApp Cloud API (Meta) para o Sócio-AI.

STDLIB ONLY (http.server + urllib). Responde dentro da janela grátis de 24h (service msgs).

Endpoints:
  GET  /health   -> "ok"
  GET  /webhook  -> verificação do challenge do Meta (hub.verify_token == WA_VERIFY_TOKEN)
  POST /webhook  -> mensagens recebidas -> gera resposta (OpenRouter) -> envia via Graph API

Env (de /opt/data/.env — só existem DEPOIS do setup Meta, que precisa do Danilo):
  WA_VERIFY_TOKEN        (o token que o Danilo cola no painel Meta)
  WA_ACCESS_TOKEN        (token permanente do System User)
  WA_PHONE_NUMBER_ID     (phone_number_id do número novo)
  OPENROUTER_API_KEY     (reutilizado do Hermes)
  WA_ENABLED             (default false — interruptor mestre)
  WA_DRY_RUN             (default true — não envia, só loga)
  WA_PORT                (default 8088)

Sem WA_ACCESS_TOKEN / WA_PHONE_NUMBER_ID o receiver ainda arranca e verifica o challenge,
mas NÃO envia (loga 'no_token'). Assim o webhook pode ser validado no Meta antes de haver token.
"""
import json, os, re, urllib.request, urllib.error
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ENV_FILE = "/opt/data/.env"
LOG_FILE = "/opt/data/whatsapp-autolog.jsonl"
GRAPH = "https://graph.facebook.com/v20.0"
SAFETY = re.compile(r"\b(refund|reembolso|estorno|advogad|legal|contrat|GDPR|RGPD|iban|nif|cancel)\w*", re.I)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def load_env(path=ENV_FILE):
    env = dict(os.environ)
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    except FileNotFoundError:
        pass
    return env


def flag(env, k, d=False):
    return str(env.get(k, str(d))).lower() in ("1", "true", "yes", "on")


def log_entry(e):
    e["ts"] = now_iso()
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(e, ensure_ascii=False) + "\n")


def generate_reply(env, text):
    key = env.get("OPENROUTER_API_KEY")
    if not key:
        return None
    payload = json.dumps({
        "model": env.get("WA_REPLY_MODEL", "openai/gpt-oss-120b:free"),
        "messages": [
            {"role": "system", "content": (
                "És o apoio do Bora App (delivery, Guarda, Portugal) no WhatsApp. Respondes "
                "curto (1-3 frases), caloroso, em PT-PT. NUNCA prometas reembolsos/valores/"
                "prazos legais — nesses casos diz que a equipa liga. Sem emojis a mais.")},
            {"role": "user", "content": text[:1500]},
        ],
        "temperature": 0.4, "max_tokens": 220,
    }).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=payload,
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.loads(r.read())["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


def send_whatsapp(env, to, body):
    token, pnid = env.get("WA_ACCESS_TOKEN"), env.get("WA_PHONE_NUMBER_ID")
    if not token or not pnid:
        return "no_token"
    payload = json.dumps({"messaging_product": "whatsapp", "to": to,
                          "type": "text", "text": {"body": body}}).encode()
    req = urllib.request.Request(f"{GRAPH}/{pnid}/messages", data=payload,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return "sent" if r.status in (200, 201) else f"http_{r.status}"
    except urllib.error.HTTPError as ex:
        return f"http_error_{ex.code}"
    except urllib.error.URLError as ex:
        return f"net_error_{ex.reason}"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body="", ctype="text/plain"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):  # silencia log default para stderr
        pass

    def do_GET(self):
        env = load_env()
        u = urlparse(self.path)
        if u.path == "/health":
            return self._send(200, "ok")
        if u.path == "/webhook":
            q = parse_qs(u.query)
            mode = (q.get("hub.mode") or [""])[0]
            token = (q.get("hub.verify_token") or [""])[0]
            challenge = (q.get("hub.challenge") or [""])[0]
            if mode == "subscribe" and token and token == env.get("WA_VERIFY_TOKEN"):
                return self._send(200, challenge)
            return self._send(403, "forbidden")
        return self._send(404, "not found")

    def do_POST(self):
        env = load_env()
        if urlparse(self.path).path != "/webhook":
            return self._send(404, "not found")
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        self._send(200, "EVENT_RECEIVED")  # responder já ao Meta (evita retries)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return
        enabled, dry = flag(env, "WA_ENABLED", False), flag(env, "WA_DRY_RUN", True)
        for entry in data.get("entry", []):
            for ch in entry.get("changes", []):
                for msg in (ch.get("value", {}).get("messages") or []):
                    if msg.get("type") != "text":
                        continue
                    frm = msg.get("from")
                    text = msg.get("text", {}).get("body", "")
                    reply = generate_reply(env, text) or "Recebemos a sua mensagem — a equipa Bora responde já a seguir."
                    held = bool(SAFETY.search(text))
                    rec = {"from": frm, "in": text[:280], "reply": reply[:280],
                           "held": held, "enabled": enabled, "dry_run": dry}
                    if held:
                        rec["event"] = "held_safety"
                    elif enabled and not dry:
                        rec["event"] = send_whatsapp(env, frm, reply)
                    else:
                        rec["event"] = "dry_run_draft"
                    log_entry(rec)


def main():
    env = load_env()
    port = int(env.get("WA_PORT", "8088"))
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"whatsapp_webhook a escutar em 127.0.0.1:{port} (proxy TLS via traefik/tailscale)")
    srv.serve_forever()


if __name__ == "__main__":
    main()
