"""Monitor diario do teste fechado (OPERACAO 12 TESTADORES) — pt.boraapp.bora.

Corre via Agendador de Tarefas do Windows (BoraTesteFechadoMonitor, 09:03 diario).
- Verifica via Play Developer API: release do track alpha (fechado) + ultimo build internal.
- Conta os dias desde o inicio da janela de 14 dias (config JSON ao lado).
- Escreve log em .claude/.ai/reports/teste-fechado-monitor.log
- Cria ALERTA_TESTADORES.txt no Desktop quando ha acao necessaria.

O numero de opt-ins NAO existe na API — ver no dashboard do Play Console:
https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/app-dashboard
"""
import json, os, time, datetime, urllib.request, urllib.parse, urllib.error, sys

try:
    import jwt
except ImportError:
    print("pip install pyjwt cryptography"); sys.exit(1)

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "monitor_teste_fechado_config.json")
LOG = os.path.normpath(os.path.join(HERE, "..", ".ai", "reports", "teste-fechado-monitor.log"))
DESKTOP_ALERT = r"C:\Users\danil\Desktop\ALERTA_TESTADORES.txt"
KEY_PATH = r"C:/Users/danil/Downloads/boraapp-d2bea-8abf3cc13bb0.json"
PACKAGE = "pt.boraapp.bora"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"

cfg = {"start_date": None, "mid_update_done": False}
if os.path.exists(CONFIG):
    cfg.update(json.load(open(CONFIG, encoding="utf-8")))

sa = json.load(open(KEY_PATH, encoding="utf-8"))
now = int(time.time())
assertion = jwt.encode({"iss": sa["client_email"], "scope": SCOPE,
    "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3600},
    sa["private_key"], algorithm="RS256")
tok = json.load(urllib.request.urlopen(urllib.request.Request(
    "https://oauth2.googleapis.com/token",
    data=urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                 "assertion": assertion}).encode())))
TOKEN = tok["access_token"]

def api(method, path, body=None):
    d = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://androidpublisher.googleapis.com" + path,
        data=d, method=method,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

st, edit = api("POST", f"/androidpublisher/v3/applications/{PACKAGE}/edits")
if st != 200:
    line = f"{datetime.date.today()} ERRO: edits.insert {st}"
    open(LOG, "a", encoding="utf-8").write(line + "\n"); print(line); sys.exit(1)
eid = edit["id"]
st, tracks = api("GET", f"/androidpublisher/v3/applications/{PACKAGE}/edits/{eid}/tracks")
api("DELETE", f"/androidpublisher/v3/applications/{PACKAGE}/edits/{eid}")

alpha_vc, internal_vc, alpha_status = None, None, None
for t in (tracks.get("tracks", []) if isinstance(tracks, dict) else []):
    for r in t.get("releases", []):
        vcs = [int(v) for v in (r.get("versionCodes") or [])]
        if t.get("track") == "alpha" and vcs:
            alpha_vc, alpha_status = max(vcs), r.get("status")
        if t.get("track") == "internal" and vcs:
            internal_vc = max(vcs)

today = datetime.date.today()
alerts, info = [], []
info.append(f"alpha={alpha_vc}({alpha_status}) internal={internal_vc}")

if alpha_vc is None or alpha_status != "completed":
    alerts.append("Track fechado sem release ativa! Verificar Play Console.")

if cfg["start_date"]:
    start = datetime.date.fromisoformat(cfg["start_date"])
    day = (today - start).days + 1
    target = start + datetime.timedelta(days=14)
    info.append(f"dia {day}/14 (alvo: {target})")
    if day >= 6 and not cfg.get("mid_update_done") and internal_vc and alpha_vc and internal_vc > alpha_vc:
        alerts.append(f"ATUALIZACAO DE MEIO DE PERIODO: promover build {internal_vc} do Interno "
                      f"para o Fechado (dia {day}). Pedir ao Claude: 'promove o build mais recente para o alpha'.")
    if day >= 14:
        alerts.append("14 DIAS COMPLETOS! Verificar no dashboard se o botao 'Candidatar-se a producao' "
                      "esta ativo e chamar o Claude para preparar o questionario.")
    if day in (3, 7, 10, 13):
        alerts.append(f"Dia {day}: confirmar no dashboard que os opt-ins continuam >=12 "
                      "(se <=14, pedir reposicao ao PrimeTestLab JA).")
else:
    info.append("start_date ainda nao definido (espera >=12 opt-ins)")

line = f"{today} {' | '.join(info)}" + (f" | ALERTAS: {' // '.join(alerts)}" if alerts else " | ok")
os.makedirs(os.path.dirname(LOG), exist_ok=True)
open(LOG, "a", encoding="utf-8").write(line + "\n")
print(line)

if alerts:
    with open(DESKTOP_ALERT, "w", encoding="utf-8") as f:
        f.write(f"OPERACAO 12 TESTADORES — {today}\n\n" + "\n\n".join("* " + a for a in alerts) +
                "\n\nDashboard: https://play.google.com/console/u/0/developers/5372142912736686834/app/4974665836977103534/app-dashboard\n")
elif os.path.exists(DESKTOP_ALERT):
    os.remove(DESKTOP_ALERT)
