#!/usr/bin/env python3
"""
email_autoresponder.py — motor de resposta automática de email do Sócio-AI (Hermes).

Lê não-lidos das 2 contas Gmail (via himalaya CLI), gera resposta com a chain de modelos
(OpenRouter), classifica risco, e — se autorizado — envia. Loga TUDO em JSONL auditável.

STDLIB ONLY (sem pip). himalaya + curl já existem no container.

GATES DE SEGURANÇA (ordem):
  1. EMAIL_AUTORESPONDER_ENABLED  (default false) — interruptor mestre. Nada corre se false.
  2. EMAIL_DRY_RUN                (default true)  — gera e loga rascunho, NÃO envia.
  3. EMAIL_AUTO_SEND_SAFETY_HOLD  (default false) — quando true, segura emails com gatilhos
                                                    jurídico/financeiro/contrato/Play policy.
  Enviar de verdade exige: ENABLED=true E DRY_RUN=false E (não segurado).

Config lida de /opt/data/.env (mesmo ficheiro do Hermes) + env do processo.
"""
import json, os, re, subprocess, sys, urllib.request, urllib.error
from datetime import datetime, timezone

ENV_FILE = "/opt/data/.env"
LOG_FILE = "/opt/data/email-autolog.jsonl"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

SAFETY_TRIGGERS = re.compile(
    r"\b(refund|reembolso|estorno|devolu|charg[eb]|litígio|litigio|dispute|advogad|"
    r"lawyer|legal|jurídic|juridic|contrat|contract|GDPR|RGPD|Google Play|policy|"
    r"política de|fatura|invoice|nif|iban|cancel)\w*", re.IGNORECASE)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def load_env(path=ENV_FILE):
    env = dict(os.environ)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    except FileNotFoundError:
        pass
    return env


def flag(env, key, default=False):
    return str(env.get(key, str(default))).lower() in ("1", "true", "yes", "on")


def him(args):
    """Corre himalaya e devolve (rc, stdout, stderr)."""
    p = subprocess.run(["himalaya", *args], capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


def list_unseen(account, limit):
    """Lista envelopes não-lidos (JSON). Defensivo: várias builds do himalaya diferem."""
    rc, out, err = him(["envelope", "list", "-a", account, "-o", "json", "-s", str(limit)])
    if rc != 0:
        # tenta sintaxe antiga sem -s
        rc, out, err = him(["envelope", "list", "-a", account, "-o", "json"])
    if rc != 0:
        raise RuntimeError(f"himalaya envelope list falhou: {err.strip()}")
    try:
        envs = json.loads(out or "[]")
    except json.JSONDecodeError:
        raise RuntimeError("himalaya devolveu JSON inválido (verificar versão/CLI)")
    unseen = []
    for e in envs:
        flags = [str(f).lower() for f in (e.get("flags") or [])]
        if "seen" not in flags:
            unseen.append(e)
    return unseen[:limit]


def read_body(account, msg_id):
    rc, out, err = him(["message", "read", str(msg_id), "-a", account])
    if rc != 0:
        return ""
    return out.strip()[:4000]


def detect_lang(text):
    t = text.lower()
    if any(w in t for w in (" the ", " your ", " please ", " thanks", " hello")):
        return "en"
    return "pt-PT"


def generate_reply(env, sender, subject, body, lang):
    api_key = env.get("OPENROUTER_API_KEY")
    if not api_key:
        return None, "sem OPENROUTER_API_KEY"
    model = env.get("EMAIL_REPLY_MODEL", "openai/gpt-oss-120b:free")
    system = (
        "És o assistente de apoio do Bora App (delivery na Guarda, Portugal). Respondes a "
        "emails em nome da equipa. Tom: profissional, caloroso, breve. Responde no idioma do "
        f"remetente ({lang}; PT-PT para clientes/parceiros PT). NUNCA prometas reembolsos, "
        "valores, prazos legais ou compromissos contratuais — se o email for sobre isso, diz "
        "que a equipa vai analisar e responder pessoalmente. Assina 'Equipa Bora App'."
    )
    user = f"Email recebido de {sender}\nAssunto: {subject}\n\n{body}\n\n---\nEscreve só o corpo da resposta."
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": user}],
        "temperature": 0.4, "max_tokens": 500,
    }).encode()
    req = urllib.request.Request(OPENROUTER_URL, data=payload, headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://bora.app", "X-Title": "Bora Email Autoresponder",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read())
        return data["choices"][0]["message"]["content"].strip(), None
    except (urllib.error.URLError, KeyError, json.JSONDecodeError) as ex:
        return None, f"falha modelo: {ex}"


def send_reply(account, to_addr, subject, reply_body, in_reply_to=None):
    hdrs = f"To: {to_addr}\nSubject: Re: {subject}\n"
    if in_reply_to:
        hdrs += f"In-Reply-To: {in_reply_to}\n"
    template = hdrs + "\n" + reply_body + "\n"
    p = subprocess.run(["himalaya", "template", "send", "-a", account],
                       input=template, capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        raise RuntimeError(f"envio falhou: {p.stderr.strip()}")


def log_entry(entry):
    entry["ts"] = now_iso()
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def process_account(env, account, enabled, dry_run, safety_hold, max_per_run):
    try:
        unseen = list_unseen(account, max_per_run)
    except RuntimeError as ex:
        log_entry({"account": account, "event": "error", "detail": str(ex)})
        print(f"[{account}] erro a listar: {ex}", file=sys.stderr)
        return
    print(f"[{account}] {len(unseen)} não-lidos")
    for e in unseen:
        mid = e.get("id")
        frm = e.get("from") or {}
        sender = frm.get("addr") or frm.get("name") or "?"
        subject = e.get("subject") or "(sem assunto)"
        body = read_body(account, mid)
        lang = detect_lang(subject + " " + body)
        reply, gen_err = generate_reply(env, sender, subject, body, lang)
        held = bool(safety_hold and SAFETY_TRIGGERS.search(subject + " " + body))
        rec = {"account": account, "msg_id": mid, "from": sender, "subject": subject,
               "lang": lang, "held": held, "dry_run": dry_run, "enabled": enabled,
               "reply_preview": (reply or "")[:280], "gen_error": gen_err}
        if not reply:
            rec["event"] = "no_reply"; log_entry(rec); continue
        if held:
            rec["event"] = "held_safety"; log_entry(rec)
            print(f"[{account}] SEGURADO (gatilho de risco): {subject}"); continue
        if enabled and not dry_run:
            try:
                send_reply(account, sender, subject, reply)
                him(["flag", "add", str(mid), "Seen", "-a", account])
                rec["event"] = "sent"
            except RuntimeError as ex:
                rec["event"] = "send_error"; rec["detail"] = str(ex)
        else:
            rec["event"] = "dry_run_draft"
        log_entry(rec)


def main():
    env = load_env()
    enabled = flag(env, "EMAIL_AUTORESPONDER_ENABLED", False)
    dry_run = flag(env, "EMAIL_DRY_RUN", True)
    safety_hold = flag(env, "EMAIL_AUTO_SEND_SAFETY_HOLD", False)
    max_per_run = int(env.get("EMAIL_MAX_PER_RUN", "10"))
    accounts = [a.strip() for a in env.get("EMAIL_ACCOUNTS", "boraapp,cloudflare").split(",") if a.strip()]

    if "--selftest" in sys.argv:
        rc, out, _ = him(["--version"])
        print("himalaya:", out.strip().splitlines()[0] if out else "??")
        print("enabled:", enabled, "dry_run:", dry_run, "safety_hold:", safety_hold)
        print("accounts:", accounts, "openrouter_key:", bool(env.get("OPENROUTER_API_KEY")))
        return

    if not enabled:
        print("EMAIL_AUTORESPONDER_ENABLED=false — nada a fazer (interruptor mestre desligado).")
        return
    for acct in accounts:
        process_account(env, acct, enabled, dry_run, safety_hold, max_per_run)


if __name__ == "__main__":
    main()
