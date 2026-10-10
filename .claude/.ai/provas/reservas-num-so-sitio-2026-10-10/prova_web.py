"""Prova web do separador Reserva com os 4 tipos (10/10/2026).

python prova_web.py <prefixo>      (ex.: antes / depois)

Entra como cliente demo em app.boraguarda.com e INTERCETA no navegador as
quatro leituras do separador (reservations, tvde_rides, cleaning_bookings,
appointments), devolvendo uma reserva inventada de cada tipo. Nada se escreve
no banco: inserir reservas de teste em produção é proibido (tvde_rides e
appointments) e uma corrida/limpeza marcada seria oferecida a gente real.

Com a versão antiga do site ("antes") o separador só mostra a mesa; com a
nova ("depois") mostra as quatro.
"""
import json, os, sys, time, urllib.request
from datetime import datetime, timedelta, timezone

from playwright.sync_api import sync_playwright

PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capturas_web")
os.makedirs(PASTA, exist_ok=True)
D = json.load(open(r"C:\BoraLocal\projetosflutter\bora_app\.dart_defines", encoding="utf-8"))
U, K = D["SUPABASE_URL"], D["SUPABASE_ANON_KEY"]
REF = U.split("//")[1].split(".")[0]
URL = os.environ.get("PROVA_URL", "https://app.boraguarda.com/")
EMAIL = os.environ.get("PROVA_EMAIL", "demo@bora.app")
SENHA = os.environ["PROVA_SENHA"]  # a da conta demo; não fica escrita aqui
PREFIXO = sys.argv[1] if len(sys.argv) > 1 else "x"


def iso(delta):
    return (datetime.now(timezone.utc) + delta).isoformat()


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


def linhas(uid):
    mesa = [{
        "id": "00000000-0000-4000-8000-00000000a001", "restaurant_id": "prova",
        "client_user_id": uid, "client_name": "Cliente de Teste", "client_phone": "910000000",
        "people": 4, "reserved_for": iso(timedelta(days=3, hours=6)), "status": "approved",
        "prepayment_cents": 300, "created_at": iso(timedelta(days=-1)),
        "restaurants": {"id": "prova", "name": "Restaurante de Teste", "photo_url": None},
    }]
    def corrida(i, delta, status, reserva, metodo, pagamento, para, de):
        return {
            "id": f"00000000-0000-4000-8000-00000000c00{i}", "client_id": uid, "status": status,
            "reservation_status": reserva, "payment_method": metodo, "payment_status": pagamento,
            "scheduled_at": iso(delta), "created_at": iso(timedelta(days=-1)),
            "origin_lat": 40.537, "origin_lng": -7.268, "dest_lat": 40.53, "dest_lng": -7.27,
            "est_distance_km": 3.1, "est_fare_cents": 500,
            "origin_label": de, "dest_label": para,
        }
    corridas = [
        corrida(1, timedelta(hours=1, minutes=10), "agendada", "atribuida", "mbway", "succeeded",
                "Hospital Sousa Martins, Guarda", "Praça Luís de Camões, Guarda"),
        corrida(2, timedelta(days=-5), "finalizada", "ativada", "cash", None,
                "Estação da Guarda", "Rua do Teste 12, Guarda"),
    ]
    limpezas = [{
        "id": "00000000-0000-4000-8000-00000000b001", "client_user_id": uid,
        "scheduled_at": iso(timedelta(hours=9)), "status": "accepted",
        "payment_method": "mbway", "payment_status": "held",
        "address_street": "Rua do Teste 12", "address_city": "Guarda", "cleaning_type": "standard",
    }]
    marcacoes = [{
        "id": "00000000-0000-4000-8000-00000000d001", "provider_id": "prova",
        "client_user_id": uid, "scheduled_at": iso(timedelta(days=2, hours=3)),
        "status": "confirmed", "deposit_status": "paid", "is_walk_in": False,
        "service_providers": {"id": "prova", "name": "Barbearia de Teste"},
        "provider_services": {"id": "prova", "name": "Corte e barba"},
    }]
    return mesa, corridas, limpezas, marcacoes


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, f"{PREFIXO}_{nome}.png"), timeout=120000)
    print("foto:", f"{PREFIXO}_{nome}", flush=True)


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
            time.sleep(5)
            return True
        time.sleep(2)
    print("nao achei:", texto, flush=True)
    return False


def main():
    s = sessao()
    uid = s["user"]["id"]
    mesa, corridas, limpezas, marcacoes = linhas(uid)
    intercetadas = []

    def responde(route, dados, nome):
        if route.request.method != "GET":
            return route.continue_()
        url = route.request.url
        # A retoma da corrida viva pede status=in.(...) — nunca lhe dar nada.
        if nome == "tvde_rides" and ("status=in." in url or "id=eq." in url):
            return route.fulfill(status=200, json=[])
        intercetadas.append(nome)
        return route.fulfill(status=200, json=dados)

    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=["--disable-gpu"])
        ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1,
                            geolocation={"latitude": 40.5373, "longitude": -7.2676},
                            permissions=["geolocation"], locale="pt-PT")
        ctx.add_init_script(arranque(s))
        ctx.route("**/rest/v1/reservations?*", lambda r: responde(r, mesa, "reservations"))
        ctx.route("**/rest/v1/tvde_rides?*", lambda r: responde(r, corridas, "tvde_rides"))
        ctx.route("**/rest/v1/cleaning_bookings?*", lambda r: responde(r, limpezas, "cleaning_bookings"))
        ctx.route("**/rest/v1/appointments?*", lambda r: responde(r, marcacoes, "appointments"))
        page = ctx.new_page()
        page.goto(URL, wait_until="commit", timeout=120000)
        time.sleep(int(os.environ.get("ESPERA", "40")))
        try:
            v = page.evaluate("() => fetch('/version.json',{cache:'no-store'}).then(r=>r.text())")
            print("version.json:", v.strip()[:200], flush=True)
        except Exception as e:
            print("version.json falhou:", str(e)[:100])
        page.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
        time.sleep(3)
        if any("Iniciar sessão" in t for t in textos(page)):
            # Mesmo caminho do prova_home.py (05/10): escrever e entrar.
            page.mouse.click(195, 321); time.sleep(1)
            page.keyboard.type(EMAIL, delay=40); time.sleep(1)
            page.mouse.click(195, 384); time.sleep(1)
            page.keyboard.type(SENHA, delay=40); time.sleep(1)
            page.mouse.click(195, 463)
            time.sleep(int(os.environ.get("ESPERA2", "25")))
            page.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
            time.sleep(3)
        foto(page, "00_home")
        clicar(page, "Reserva")
        time.sleep(6)
        foto(page, "01_reservas_proximas")
        print("TEXTOS:", " | ".join(textos(page)[:60]), flush=True)
        if clicar(page, "Passadas"):
            foto(page, "02_reservas_passadas")
            print("TEXTOS:", " | ".join(textos(page)[:40]), flush=True)
        print("leituras intercetadas:", sorted(set(intercetadas)), flush=True)
        b.close()


main()
