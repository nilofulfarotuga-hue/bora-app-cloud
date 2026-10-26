"""Captura do painel "Ligado sem sinal" (missão geral-sabado-24-10, bloco 1).

O ecrã é o REAL do site (app.boraguarda.com, bundle no ar = commit 68ef7ce5).
A sessão é da conta de demonstração (cliente, sem admin); o RLS não lhe dá a
lista de motoristas, por isso as DUAS leituras do ecrã (GET drivers da lista e
RPC admin_drivers_for_assignment) recebem as linhas reais tiradas da base por
SELECT a 26/10 (ficheiro privado, fora do repositório). Nada é escrito no banco.

As capturas levam nomes e telefones: ficam SÓ na pasta privada, nunca no git.
Uso: python -I captura_painel_sem_sinal.py <raiz_repo> <pasta_privada>
"""
import json
import pathlib
import sys
import urllib.request

from playwright.sync_api import sync_playwright

raiz = pathlib.Path(sys.argv[1])
privada = pathlib.Path(sys.argv[2])
dados = json.loads((privada / "motoristas.json").read_text(encoding="utf-8"))
defs = json.loads((raiz / ".dart_defines").read_text(encoding="utf-8-sig"))
URL = defs["SUPABASE_URL"].rstrip("/")
ANON = defs["SUPABASE_ANON_KEY"]
REF = URL.split("//")[1].split(".")[0]

req = urllib.request.Request(
    f"{URL}/auth/v1/token?grant_type=password",
    data=json.dumps({"email": "demo@bora.app", "password": "BoraDemo2026!"}).encode(),
    headers={"apikey": ANON, "Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(req, timeout=30) as r:
    sessao = json.loads(r.read())
print("sessao demo:", "ok" if sessao.get("access_token") else "FALHOU")
texto = json.dumps(sessao)


def servir(rota, corpo):
    rota.fulfill(status=200, content_type="application/json", body=json.dumps(corpo))


def lista_drivers(rota):
    u = rota.request.url
    if rota.request.method == "GET" and "order=name" in u and "approval_status" in u:
        return servir(rota, dados["drivers"])
    return rota.continue_()


with sync_playwright() as p:
    nav = p.chromium.launch(headless=True)
    for nome, vp in (("largo", {"width": 1280, "height": 900}), ("telemovel", {"width": 430, "height": 932})):
        ctx = nav.new_context(viewport=vp, locale="pt-PT", service_workers="block")
        ctx.add_init_script(
            "(() => { const s = %s; const k = 'sb-%s-auth-token';"
            " localStorage.setItem(k, s); localStorage.setItem('flutter.' + k, JSON.stringify(s)); })()"
            % (json.dumps(texto), REF))
        page = ctx.new_page()
        page.route("**/rest/v1/drivers?*", lista_drivers)
        page.route("**/rest/v1/rpc/admin_drivers_for_assignment*",
                   lambda r: servir(r, dados["presenca"]))
        page.goto("https://app.boraguarda.com/#/admin/drivers", wait_until="load", timeout=120000)
        page.wait_for_timeout(12000)
        page.screenshot(path=str(privada / f"painel-{nome}-todos.png"))
        page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
        page.wait_for_timeout(1500)
        try:
            page.get_by_role("tab", name="Online").first.click(timeout=10000)
        except Exception as e:  # noqa: BLE001
            print("aba Online por nome falhou:", e)
            page.get_by_text("Online (").first.click(timeout=10000)
        page.wait_for_timeout(4000)
        page.screenshot(path=str(privada / f"painel-{nome}-online.png"))
        snap = page.locator("flt-semantics-host").aria_snapshot(timeout=30000)
        (privada / f"painel-{nome}-arvore.txt").write_text(snap, encoding="utf-8")
        print("captura", nome, "| 'Ligado sem sinal' na arvore:", "Ligado sem sinal" in snap,
              "| botao:", "Enviar aviso agora" in snap)
        ctx.close()
    nav.close()
