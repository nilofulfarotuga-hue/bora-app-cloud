"""Capturas do painel — documentos de todos os papéis (missão geral-sabado-24-10, bloco 3).

Ecrãs REAIS do site (app.boraguarda.com, bundle no ar). Sessão da conta de
demonstração (sem admin): as leituras do ecrã recebem as linhas REAIS, lidas
aqui na base com a chave do servidor (nunca escrita nem impressa). Nada é
escrito no banco. As fotos privadas abrem com endereços assinados por 10 min
(só o POST de assinatura é respondido aqui; o GET da imagem vai ao servidor).

As capturas levam dados pessoais: SÓ na pasta privada, nunca no git.
Uso: python -I captura_fichas_prestadores.py <raiz_repo> <pasta_privada> <user_id_tvde> <user_id_limpeza>
"""
import json
import pathlib
import sys
import urllib.parse
import urllib.request

from playwright.sync_api import sync_playwright

raiz = pathlib.Path(sys.argv[1])
privada = pathlib.Path(sys.argv[2])
UID_TVDE, UID_LIMPEZA = sys.argv[3], sys.argv[4]
defs = json.loads((raiz / ".dart_defines").read_text(encoding="utf-8-sig"))
URL = defs["SUPABASE_URL"].rstrip("/")
ANON = defs["SUPABASE_ANON_KEY"]
REF = URL.split("//")[1].split(".")[0]
CHAVE = next(l.split("=", 1)[1].strip().strip('"')
             for l in (raiz / "backend" / ".env").read_text(encoding="utf-8").splitlines()
             if l.startswith("SUPABASE_SERVICE_ROLE_KEY="))


def rest(caminho):
    req = urllib.request.Request(f"{URL}/rest/v1/{caminho}",
                                 headers={"apikey": CHAVE, "Authorization": f"Bearer {CHAVE}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def assinar(balde_caminho):
    req = urllib.request.Request(f"{URL}/storage/v1/object/sign/{balde_caminho}",
                                 data=json.dumps({"expiresIn": 600}).encode(),
                                 headers={"apikey": CHAVE, "Authorization": f"Bearer {CHAVE}",
                                          "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except Exception:  # noqa: BLE001
        return None


q = urllib.parse.quote
motorista = rest(f"drivers?select=*&user_id=eq.{UID_TVDE}")
driver_id = motorista[0]["id"] if motorista else None
dados = {
    "drivers": motorista,
    "ficha_legal": rest(f"motorista_ficha_legal?select=*&user_id=eq.{UID_TVDE}"),
    "driver_vehicle": rest(f"tvde_driver_vehicle?select=vehicle_id,ativo&driver_user_id=eq.{UID_TVDE}"),
    "tvde_docs": rest(f"tvde_driver_documents?select=*&driver_id=eq.{driver_id}") if driver_id else [],
    "atividade_tvde": rest(f"provider_atividade?select=*&user_id=eq.{UID_TVDE}"),
    "fiscal_tvde": rest(f"driver_fiscal_status?select=*&user_id=eq.{UID_TVDE}"),
    "cleaners": rest(f"cleaners?select=*&user_id=eq.{UID_LIMPEZA}"),
    "atividade_limpeza": rest(f"provider_atividade?select=*&user_id=eq.{UID_LIMPEZA}"),
    "fiscal_limpeza": rest(f"driver_fiscal_status?select=*&user_id=eq.{UID_LIMPEZA}"),
}
ids = [r["vehicle_id"] for r in dados["driver_vehicle"] if r.get("vehicle_id")]
dados["veiculos"] = rest("tvde_vehicles?select=*&id=in.(" + ",".join(ids) + ")") if ids else []
print("linhas:", {k: len(v) for k, v in dados.items()})
sessao = None
req = urllib.request.Request(
    f"{URL}/auth/v1/token?grant_type=password",
    data=json.dumps({"email": "demo@bora.app", "password": "BoraDemo2026!"}).encode(),
    headers={"apikey": ANON, "Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(req, timeout=30) as r:
    sessao = json.loads(r.read())
texto = json.dumps(sessao)


def servir(rota, corpo):
    rota.fulfill(status=200, content_type="application/json", body=json.dumps(corpo))


def tabela(nome, chave):
    def f(rota):
        if rota.request.method != "GET":
            return rota.continue_()
        corpo = dados[chave]
        # .maybeSingle() pede um objeto
        if "vnd.pgrst.object" in (rota.request.headers.get("accept") or ""):
            if not corpo:
                return rota.fulfill(status=406, content_type="application/json", body="{}")
            return rota.fulfill(status=200, content_type="application/json", body=json.dumps(corpo[0]))
        return servir(rota, corpo)
    return f


def sign(rota):
    if rota.request.method != "POST":
        return rota.continue_()
    caminho = rota.request.url.split("/storage/v1/object/sign/", 1)[1].split("?")[0]
    s = assinar(urllib.parse.unquote(caminho))
    if not s:
        return rota.continue_()
    return servir(rota, s)


def contexto(nav, atividade, fiscal):
    ctx = nav.new_context(viewport={"width": 1280, "height": 1000}, locale="pt-PT", service_workers="block")
    ctx.add_init_script(
        "(() => { const s = %s; const k = 'sb-%s-auth-token';"
        " localStorage.setItem(k, s); localStorage.setItem('flutter.' + k, JSON.stringify(s)); })()"
        % (json.dumps(texto), REF))
    page = ctx.new_page()
    page.route("**/rest/v1/drivers?*", tabela("drivers", "drivers"))
    page.route("**/rest/v1/motorista_ficha_legal?*", tabela("ficha_legal", "ficha_legal"))
    page.route("**/rest/v1/tvde_driver_vehicle?*", tabela("dv", "driver_vehicle"))
    page.route("**/rest/v1/tvde_vehicles?*", tabela("v", "veiculos"))
    page.route("**/rest/v1/tvde_driver_documents?*", tabela("d", "tvde_docs"))
    page.route("**/rest/v1/provider_atividade?*", tabela("a", atividade))
    page.route("**/rest/v1/driver_fiscal_status?*", tabela("f", fiscal))
    page.route("**/rest/v1/rpc/admin_tvde_motoristas_conformidade*", lambda r: servir(r, []))
    page.route("**/rest/v1/rpc/admin_list_cleaners*", lambda r: servir(r, dados["cleaners"]))
    page.route("**/storage/v1/object/sign/**", sign)
    return ctx, page


def shot(page, nome):
    page.screenshot(path=str(privada / f"{nome}.png"))
    print("captura", nome)


def acessibilidade(page):
    page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
    page.wait_for_timeout(1500)


with sync_playwright() as p:
    nav = p.chromium.launch(headless=True)
    # 1) Motorista TVDE — aprovações de motoristas (a ficha TVDE vive lá dentro)
    ctx, page = contexto(nav, "atividade_tvde", "fiscal_tvde")
    page.goto("https://app.boraguarda.com/#/admin/drivers/approval", wait_until="load", timeout=120000)
    page.wait_for_timeout(12000)
    shot(page, "b3-tvde-01-lista")
    acessibilidade(page)
    try:
        page.get_by_role("tab", name="Aprovados").first.click(timeout=8000)
    except Exception:  # noqa: BLE001
        page.get_by_text("Aprovados (").first.click(timeout=8000)
    page.wait_for_timeout(4000)
    shot(page, "b3-tvde-01b-aprovados")
    (privada / "b3-tvde-arvore-lista.txt").write_text(
        page.locator("flt-semantics-host").aria_snapshot(timeout=30000), encoding="utf-8")
    for alvo in ("Documentos", "Ver ficha completa"):
        try:
            page.get_by_role("button", name=alvo).first.click(timeout=6000)
            break
        except Exception:  # noqa: BLE001
            continue
    page.wait_for_timeout(7000)
    shot(page, "b3-tvde-02-ficha")
    for i in range(3):
        page.mouse.move(640, 600)
        page.mouse.wheel(0, 800)
        page.wait_for_timeout(2500)
        shot(page, f"b3-tvde-0{3 + i}-ficha")
    (privada / "b3-tvde-arvore-ficha.txt").write_text(
        page.locator("flt-semantics-host").aria_snapshot(timeout=30000), encoding="utf-8")
    ctx.close()
    # 2) Profissional de limpeza
    ctx, page = contexto(nav, "atividade_limpeza", "fiscal_limpeza")
    page.goto("https://app.boraguarda.com/#/admin/cleaning/cleaners", wait_until="load", timeout=120000)
    page.wait_for_timeout(12000)
    shot(page, "b3-limpeza-01-lista")
    acessibilidade(page)
    try:
        page.get_by_role("button", name="Ver ficha completa").first.click(timeout=8000)
    except Exception as e:  # noqa: BLE001
        print("ficha limpeza por botão falhou:", e)
    page.wait_for_timeout(7000)
    shot(page, "b3-limpeza-02-ficha")
    page.mouse.move(640, 600)
    page.mouse.wheel(0, 800)
    page.wait_for_timeout(2500)
    shot(page, "b3-limpeza-03-ficha")
    (privada / "b3-limpeza-arvore.txt").write_text(
        page.locator("flt-semantics-host").aria_snapshot(timeout=30000), encoding="utf-8")
    ctx.close()
    nav.close()
CHAVE = None
