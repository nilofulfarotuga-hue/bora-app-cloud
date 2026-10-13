"""Prova web do cartão "Check-in diário" (13/10/2026).

python prova_web_checkin.py simulado   — o servidor ainda não tem as funções: o navegador
                                          INTERCETA client_checkin_status e client_daily_checkin
                                          e responde como o SQL provado no PGlite responderia.
python prova_web_checkin.py real        — sem intercetar nada: com as funções em falta o cartão
                                          NÃO pode aparecer (e a home continua inteira).

Entra como cliente demo em app.boraguarda.com (mesmo arranque do prova_web.py de 10/10:
consentimento e sessão gravados antes de a app arrancar). Nada se escreve no banco.
A senha vem de PROVA_SENHA (a da conta demo; não fica escrita aqui).
"""
import json, os, sys, time, urllib.request

from playwright.sync_api import sync_playwright

PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capturas_web")
os.makedirs(PASTA, exist_ok=True)
D = json.load(open(r"C:\BoraLocal\projetosflutter\bora_app\.dart_defines", encoding="utf-8"))
U, K = D["SUPABASE_URL"], D["SUPABASE_ANON_KEY"]
REF = U.split("//")[1].split(".")[0]
URL = os.environ.get("PROVA_URL", "https://app.boraguarda.com/")
EMAIL = os.environ.get("PROVA_EMAIL", "demo@bora.app")
SENHA = os.environ["PROVA_SENHA"]
MODO = sys.argv[1] if len(sys.argv) > 1 else "simulado"
PREMIOS = [5, 5, 10, 10, 15, 15, 40]


def estado(feito, dia):
    prox = (1 if dia >= 7 else dia + 1) if feito else dia
    return {"enabled": True, "eligible": True, "reason": None, "today": "2026-10-13",
            "already_done": feito, "streak_day": dia, "tokens_today": PREMIOS[dia - 1],
            "next_day": prox, "next_reward": PREMIOS[prox - 1], "rewards": PREMIOS,
            "streak_running": True, "require_phone": True}


def sessao():
    req = urllib.request.Request(
        U + "/auth/v1/token?grant_type=password",
        data=json.dumps({"email": EMAIL, "password": SENHA}).encode(),
        headers={"apikey": K, "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))


def arranque(s):
    val = json.dumps(json.dumps(s))
    return f"""
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
localStorage.setItem('flutter.bora_app.user_role', '"client"');
localStorage.setItem('flutter.sb-{REF}-auth-token', {json.dumps(val)});
"""


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, f"{MODO}_{nome}.png"), timeout=120000)
    print("foto:", f"{MODO}_{nome}", flush=True)


def textos(page):
    labs = page.evaluate("""() => [...document.querySelectorAll('flt-semantics')]
      .map(e => (e.getAttribute('aria-label') || e.innerText || '').trim()).filter(t => t)""")
    vistos = []
    for l in labs:
        l = l.replace("\n", " ")[:90]
        if l not in vistos:
            vistos.append(l)
    return vistos


def clicar(page, texto):
    for _ in range(12):
        ok = page.evaluate("""(t) => {
          const ns = [...document.querySelectorAll('flt-semantics')]
            .filter(e => ((e.getAttribute('aria-label')||'') + ' ' + (e.innerText||'')).trim() === t
                      || (e.getAttribute('aria-label')||'').startsWith(t));
          if (!ns.length) return false;
          const e = ns[ns.length-1];
          const r = e.getBoundingClientRect();
          if (r.width === 0) return false;
          e.click(); return true;
        }""", texto)
        if ok:
            time.sleep(4)
            return True
        time.sleep(2)
    print("nao achei:", texto, flush=True)
    return False


def main():
    s = sessao()
    chamadas = []

    def status(route):
        chamadas.append("client_checkin_status")
        feito = "client_daily_checkin" in chamadas
        return route.fulfill(status=200, json=estado(feito, 3))

    def checkin(route):
        chamadas.append("client_daily_checkin")
        r = estado(True, 3)
        r.update({"ok": True, "already_done": False, "tokens_awarded": 10, "balance": 115})
        return route.fulfill(status=200, json=r)

    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=["--disable-gpu"])
        ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1,
                            geolocation={"latitude": 40.5373, "longitude": -7.2676},
                            permissions=["geolocation"], locale="pt-PT")
        ctx.add_init_script(arranque(s))
        if MODO == "simulado":
            ctx.route("**/rest/v1/rpc/client_checkin_status*", status)
            ctx.route("**/rest/v1/rpc/client_daily_checkin*", checkin)
        else:
            ctx.on("response", lambda r: "client_checkin_status" in r.url and
                   print("servidor respondeu ao estado:", r.status, flush=True))
        page = ctx.new_page()
        page.goto(URL, wait_until="commit", timeout=120000)
        time.sleep(int(os.environ.get("ESPERA", "45")))
        try:
            v = page.evaluate("() => fetch('/version.json',{cache:'no-store'}).then(r=>r.text())")
            print("version.json:", v.strip()[:200], flush=True)
            js = page.evaluate("() => fetch('/main.dart.js',{cache:'no-store'}).then(r=>r.text())")
            print("bundle tem client_checkin_status:", "client_checkin_status" in js, flush=True)
        except Exception as e:
            print("leitura do bundle falhou:", str(e)[:100])
        page.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
        time.sleep(4)
        foto(page, "00_home")
        t = textos(page)
        print("TEXTOS:", " | ".join(t[:40]), flush=True)
        print("cartão visível:", any("Check-in diário" in x for x in t), flush=True)
        if MODO == "simulado":
            if clicar(page, "Fazer check-in"):
                time.sleep(1)
                foto(page, "01_depois_do_toque")
                time.sleep(3)
                foto(page, "02_feito")
                t = textos(page)
                print("TEXTOS:", " | ".join(t[:40]), flush=True)
                print("tem 'Volta amanhã para ganhar 10 tokens.':",
                      any("Volta amanhã para ganhar 10 tokens." in x for x in t), flush=True)
                print("tem 'Ganhaste 10 tokens!':", any("Ganhaste 10 tokens!" in x for x in t), flush=True)
        print("chamadas intercetadas:", chamadas, flush=True)
        b.close()


main()
