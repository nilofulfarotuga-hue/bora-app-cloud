"""Prova web da home com faixas + pesquisa (05/10). python prova_home.py <fase> [args]"""
import json, os, sys, time, urllib.request

from playwright.sync_api import sync_playwright

PASTA = r"C:\BoraLocal\projetosflutter\bora_app\.claude\.ai\provas\home-faixas-2026-10-05"
os.makedirs(PASTA, exist_ok=True)
D = json.load(open(r"C:\BoraLocal\projetosflutter\bora_app\.dart_defines", encoding="utf-8"))
U, K = D["SUPABASE_URL"], D["SUPABASE_ANON_KEY"]
REF = U.split("//")[1].split(".")[0]
URL = "https://app.boraguarda.com/"
EMAIL, SENHA = os.environ.get("PROVA_EMAIL", "demo@bora.app"), os.environ.get("PROVA_SENHA", "BoraDemo2026!")


def sessao():
    req = urllib.request.Request(
        U + "/auth/v1/token?grant_type=password",
        data=json.dumps({"email": EMAIL, "password": SENHA}).encode(),
        headers={"apikey": K, "Content-Type": "application/json"})
    s = json.load(urllib.request.urlopen(req, timeout=30))
    return s


def arranque(s):
    js = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
localStorage.setItem('flutter.bora_app.user_role', '"client"');
"""
    if s:
        val = json.dumps(json.dumps(s))  # string JSON guardada como string
        js += f"localStorage.setItem('flutter.sb-{REF}-auth-token', {json.dumps(val)});\n"
    return js


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, nome + ".png"), timeout=120000)
    print("foto:", nome)


def acessibilidade(page):
    try:
        page.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
    except Exception as e:
        print("acess:", str(e)[:80])
    time.sleep(2)


def rotulos(page, n=80):
    labs = page.evaluate("""() => [...document.querySelectorAll('flt-semantics [aria-label], flt-semantics[role=button], flt-semantics')]
      .map(e => (e.getAttribute('aria-label') || e.innerText || '').trim()).filter(t => t).slice(0, 400)""")
    vistos = []
    for l in labs:
        l = l.replace("\n", " ")[:70]
        if l not in vistos:
            vistos.append(l)
    print("ROTULOS:", " | ".join(vistos[:n]))


def clicar(page, texto):
    # Procura o no de semantica pelo aria-label ou pelo texto; espera ate 24 s
    # (o carrossel avanca sozinho de 6 em 6 s).
    for _ in range(12):
        ok = page.evaluate("""(t) => {
          const ns = [...document.querySelectorAll('flt-semantics')]
            .filter(e => ((e.getAttribute('aria-label')||'') + ' ' + (e.innerText||'')).includes(t));
          if (!ns.length) return false;
          const e = ns[ns.length-1];
          const r = e.getBoundingClientRect();
          if (r.width === 0 || r.bottom < 0 || r.top > innerHeight) return 'fora';
          e.click(); return true;
        }""", texto)
        if ok is True:
            time.sleep(5)
            return
        time.sleep(2)
    info = page.evaluate("""(t) => [...document.querySelectorAll('flt-semantics')].filter(e => ((e.getAttribute('aria-label')||'') + ' ' + (e.innerText||'')).includes(t)).map(e => { const r = e.getBoundingClientRect(); return [e.getAttribute('role'), Math.round(r.top), Math.round(r.height), (e.getAttribute('aria-label')||'').slice(0,40)]; })""", texto)
    print("DEBUG", texto, info, "total", page.evaluate("() => document.querySelectorAll('flt-semantics').length"))
    raise RuntimeError("nao achei/nao visivel: " + texto)


def entrar(page):
    page.mouse.click(195, 321); time.sleep(1)
    page.keyboard.type(EMAIL, delay=40); time.sleep(1)
    page.mouse.click(195, 384); time.sleep(1)
    page.keyboard.type(SENHA, delay=40); time.sleep(1)
    page.mouse.click(195, 463)
    time.sleep(int(os.environ.get("ESPERA2", "20")))


def main():
    print("inicio", time.strftime("%X"), flush=True)
    fase = sys.argv[1]
    s = None if os.environ.get("SEM_SESSAO") else sessao()
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=["--disable-gpu", "--js-flags=--max-old-space-size=256"])
        ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1,
                            geolocation={"latitude": 40.5373, "longitude": -7.2676},
                            permissions=["geolocation"], locale="pt-PT")
        ctx.add_init_script(arranque(s))
        if os.environ.get("FALHAR_FAIXAS"):
            ctx.route("**/rest/v1/home_banners*", lambda r: r.abort())
        if os.environ.get("MAIS_ZERO"):
            def _mz(route):
                resp = route.fetch()
                rows = resp.json()
                for i, r in enumerate(rows):
                    r["pedidos_30d"] = 2 if i == 0 else 0
                route.fulfill(response=resp, json=rows)
            ctx.route("**/rpc/home_mais_pedidos*", _mz)
        page = ctx.new_page()
        page.goto(URL, wait_until="commit", timeout=120000); print("goto ok", time.strftime("%X"), flush=True)
        time.sleep(int(os.environ.get("ESPERA", "25")))
        if s is not None:
            entrar(page)
        acessibilidade(page); print("pronto", time.strftime("%X"), flush=True)
        if fase == "home":
            foto(page, "01_home_topo")
            rotulos(page)
            for i in range(1, 7):
                page.mouse.move(195, 600)
                page.mouse.wheel(0, 600)
                time.sleep(3)
                foto(page, f"02_home_desce_{i}")
            rotulos(page, 200)
        elif fase == "clicar":
            # clicar <texto> [<texto2>...] — cada um a partir do ecra anterior
            for i, t in enumerate(sys.argv[2:]):
                if t.startswith("rolar:"):
                    page.mouse.move(195, 600)
                    page.mouse.wheel(0, int(t[6:]))
                    time.sleep(3)
                    continue
                if t.startswith("faixa:"):
                    alvo = t[6:]
                    for _ in range(8):
                        r = page.evaluate("""(t) => { const e = [...document.querySelectorAll('flt-semantics')].find(e => (e.getAttribute('aria-label')||'').includes(t) || (e.innerText||'').startsWith(t)); if (!e) return null; const b = e.getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; }""", alvo)
                        if r and r[2] > 200 and 0 < r[1] < 700:
                            break
                        page.mouse.move(340, 200); page.mouse.down(); page.mouse.move(60, 200, steps=12); page.mouse.up(); time.sleep(2)
                    foto(page, f"{os.environ.get('PREFIXO','c')}_{i}_antes")
                    page.mouse.click(200, 200); time.sleep(6)
                    foto(page, f"{os.environ.get('PREFIXO','c')}_{i}"); rotulos(page, 40)
                    continue
                if t == "foto":
                    foto(page, f"{os.environ.get('PREFIXO','c')}_{i}"); rotulos(page, 30)
                    continue
                if t.startswith("tocar:"):
                    x, y = t[6:].split(","); page.mouse.click(int(x), int(y)); time.sleep(5)
                    foto(page, f"{os.environ.get('PREFIXO','c')}_{i}"); rotulos(page, 40)
                    continue
                if t == "limpar":
                    page.keyboard.press("Control+A"); page.keyboard.press("Backspace"); time.sleep(1)
                    continue
                if t == "voltar":
                    page.go_back(); time.sleep(4)
                    continue
                if t.startswith("escrever:"):
                    page.keyboard.type(t[9:], delay=60)
                    time.sleep(5)
                    foto(page, f"{os.environ.get('PREFIXO','c')}_{i}_escrito")
                    rotulos(page, 60)
                    continue
                clicar(page, t)
                foto(page, f"{os.environ.get('PREFIXO','c')}_{i}")
                rotulos(page, 40)
        b.close()


main()
