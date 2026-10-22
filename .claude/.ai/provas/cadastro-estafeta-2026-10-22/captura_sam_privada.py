"""Captura do ecrã de aprovação do SAM (missão cadastro-estafeta-fotos-22-10).

O ecrã é o REAL do site (app.boraguarda.com, bundle no ar). A sessão é de uma
conta de TESTE sem papel de admin, por isso as três leituras do ecrã
(drivers, provider_atividade, driver_fiscal_status) recebem as linhas reais do
SAM, tiradas da base por SELECT (ficheiro privado, fora do repositório), e o
endereço assinado do comprovativo é gerado aqui com a chave do servidor
(10 minutos; a chave nunca é escrita nem impressa).

As capturas levam dados pessoais: ficam SÓ na pasta privada, nunca no git.
Uso: python -I captura_sam_privada.py <raiz_repo> <perfil> <pasta_privada>
"""
import json
import pathlib
import sys
import urllib.request

from playwright.sync_api import sync_playwright

raiz = pathlib.Path(sys.argv[1])
perfil = sys.argv[2]
privada = pathlib.Path(sys.argv[3])
dados = json.loads((privada / "sam.json").read_text(encoding="utf-8"))
defs = json.loads((raiz / ".dart_defines").read_text(encoding="utf-8-sig"))
URL = defs["SUPABASE_URL"].rstrip("/")
chave = None
for linha in (raiz / "backend" / ".env").read_text(encoding="utf-8").splitlines():
    if linha.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        chave = linha.split("=", 1)[1].strip().strip('"')
caminho = dados["atividade"][0]["documento_path"]
req = urllib.request.Request(
    f"{URL}/storage/v1/object/sign/provider-atividade/{caminho}",
    data=json.dumps({"expiresIn": 600}).encode(),
    headers={"apikey": chave, "Authorization": f"Bearer {chave}", "Content-Type": "application/json"},
    method="POST")
with urllib.request.urlopen(req, timeout=30) as r:
    assinado = json.loads(r.read())["signedURL"]
chave = None
print("assinatura do comprovativo: ok")


def servir(rota, corpo):
    if rota.request.method != "GET":
        return rota.continue_()
    rota.fulfill(status=200, content_type="application/json", body=json.dumps(corpo))


with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        perfil, headless=True, viewport={"width": 480, "height": 960},
        locale="pt-PT", service_workers="block")
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.route("**/rest/v1/drivers?*", lambda r: servir(r, dados["drivers"]))
    page.route("**/rest/v1/provider_atividade?*", lambda r: servir(r, dados["atividade"]))
    page.route("**/rest/v1/driver_fiscal_status?*", lambda r: servir(r, dados["fiscal"]))
    # Só o POST que pede a assinatura; o GET da imagem segue para o servidor.
    page.route("**/storage/v1/object/sign/provider-atividade/**",
               lambda r: r.fulfill(status=200, content_type="application/json",
                                   body=json.dumps({"signedURL": assinado}))
               if r.request.method == "POST" else r.continue_())

    def shot(nome):
        page.screenshot(path=str(privada / f"{nome}.png"))
        print("captura", nome)

    page.goto("https://app.boraguarda.com/#/admin/drivers/approval", wait_until="load", timeout=120000)
    page.wait_for_timeout(10000)
    shot("sam-01-lista")
    page.mouse.click(220, 170)
    page.wait_for_timeout(7000)
    shot("sam-02-ficha-topo")
    for i, d in enumerate([700, 700, 900], start=3):
        page.mouse.move(240, 600)
        page.mouse.wheel(0, d)
        page.wait_for_timeout(2500)
        shot(f"sam-0{i}-ficha")
    page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
    page.wait_for_timeout(1000)
    snap = page.locator("flt-semantics-host").aria_snapshot(timeout=30000)
    (privada / "sam-arvore.txt").write_text(snap, encoding="utf-8")
    ctx.close()
