"""PROVA DE ECRAS PELA WEB — sem cabo nenhum.

A app corre inteira em app.boraguarda.com. Isto abre-a num browser do tamanho
de um telemovel, entra, percorre os ecras e fotografa cada passo.

Duas coisas que sao a diferenca entre isto funcionar e nao funcionar:

 1. O GPS vem do proprio contexto do Playwright, fixado na Guarda. Sem ele o
    ecra do estafeta fica no carregador PARA SEMPRE — `_buildIdleMapScaffold`
    bloqueia a render ate ter uma posicao, e no browser essa posicao nunca
    chega sozinha.

 2. O consentimento e gravado ANTES de a app arrancar. Recusar o consentimento
    tem o mesmo efeito: o ecra do estafeta nunca abre.

E uma terceira, sobre escrever em campos: o Flutter desenha em canvas e o
`input` do DOM so NASCE quando o campo ganha foco. Ha que clicar primeiro, e
depois disparar o evento `input` a serio — escrever no `.value` sozinho nao
move nada no ecra.

  python prova_web.py <fase>
"""
import os
import sys

from playwright.sync_api import sync_playwright

AQUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTA = AQUI
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
EMAIL = "prova.web@bora.app"
SENHA = "ProvaWeb!2026"
URL = "https://app.boraguarda.com/"

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

# Coordenadas num ecra de 430x880 (tamanho de telemovel).
PAPEL_ESTAFETA = (215, 653)
CAMPO_EMAIL = (215, 285)
CAMPO_SENHA = (215, 348)
BOTAO_ENTRAR = (215, 427)
ICONE_PERFIL = (297, 28)
# no perfil, depois de tres rolagens:
PERFIL_LIMPEZA = (215, 395)
PERFIL_GANHOS = (215, 457)
PERFIL_ADMIN = (215, 714)


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, nome + ".png"))
    print("   foto:", nome)


def rolar(page, quanto=420):
    """O Flutter so rola se a roda vier com o rato POR CIMA da lista."""
    page.mouse.move(215, 600)
    page.wait_for_timeout(200)
    page.mouse.wheel(0, quanto)
    page.wait_for_timeout(1400)


def escrever(page, ponto, texto):
    page.mouse.click(*ponto)
    page.wait_for_timeout(700)
    page.evaluate(
        """(t) => {
            const el = document.activeElement;
            if (!el || el.tagName !== 'INPUT') return false;
            const s = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value').set;
            s.call(el, t);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            return true;
        }""", texto)
    page.wait_for_timeout(600)


def ha_campo(page):
    page.mouse.click(*CAMPO_EMAIL)
    page.wait_for_timeout(600)
    return page.evaluate(
        "() => document.activeElement && document.activeElement.tagName === 'INPUT'")


def garantir_estafeta(page):
    page.mouse.click(*PAPEL_ESTAFETA)
    page.wait_for_timeout(6000)
    if ha_campo(page):
        print("   pediu credenciais")
        escrever(page, CAMPO_EMAIL, EMAIL)
        escrever(page, CAMPO_SENHA, SENHA)
        page.mouse.click(*BOTAO_ENTRAR)
        page.wait_for_timeout(28000)
    else:
        page.wait_for_timeout(12000)


def abrir_perfil(page):
    page.mouse.click(*ICONE_PERFIL)
    page.wait_for_timeout(9000)
    for _ in range(3):
        rolar(page)


def abrir(p, espera=14000):
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=False,
        viewport={"width": 430, "height": 880},
        geolocation={"latitude": 40.5373, "longitude": -7.2676},   # Guarda
        permissions=["geolocation"], locale="pt-PT",
        timezone_id="Europe/Lisbon",
        args=["--disable-dev-shm-usage", "--no-sandbox"])
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until="load", timeout=180000)
    page.wait_for_timeout(espera)
    return ctx, page


def admin_procurar():
    """Rola o painel admin todo, a procura das telas novas."""
    with sync_playwright() as p:
        ctx, page = abrir(p)
        garantir_estafeta(page)
        abrir_perfil(page)
        page.mouse.click(*PERFIL_ADMIN)
        page.wait_for_timeout(12000)
        inicio = int(sys.argv[2]) if len(sys.argv) > 2 else 0
        for i in range(inicio):
            rolar(page, 600)
        for i in range(inicio, inicio + 14):
            rolar(page, 600)
            foto(page, "f1-admin-%02d" % i)
        ctx.close()


def admin_ofertas():
    """Abre a tela das ofertas, na posicao dada."""
    y = int(sys.argv[2])
    rolagens = int(sys.argv[3])
    with sync_playwright() as p:
        ctx, page = abrir(p)
        garantir_estafeta(page)
        abrir_perfil(page)
        page.mouse.click(*PERFIL_ADMIN)
        page.wait_for_timeout(12000)
        for _ in range(rolagens):
            rolar(page, 600)
        foto(page, "f2-antes-de-abrir")
        page.mouse.click(215, y)
        page.wait_for_timeout(12000)
        foto(page, "06-admin-ofertas")
        ctx.close()


def admin_faixa():
    """Varre uma faixa do painel admin em passos pequenos.
       python prova_web.py admin_faixa <px_inicio> <passos>"""
    inicio = int(sys.argv[2])
    passos = int(sys.argv[3])
    with sync_playwright() as p:
        ctx, page = abrir(p)
        garantir_estafeta(page)
        abrir_perfil(page)
        page.mouse.click(*PERFIL_ADMIN)
        page.wait_for_timeout(12000)
        feito = 0
        while feito < inicio:
            rolar(page, 300)
            feito += 300
        for i in range(passos):
            foto(page, "f3-admin-%05d" % feito)
            rolar(page, 300)
            feito += 300
        ctx.close()


def trocar_papel():
    """PROVA 4 — o botao de trabalhar noutra coisa, no ecra que o estafeta ve."""
    with sync_playwright() as p:
        ctx, page = abrir(p)
        garantir_estafeta(page)
        foto(page, "04-botoes-do-mapa")
        x = int(sys.argv[2]) if len(sys.argv) > 2 else 345
        page.mouse.click(x, 28)
        page.wait_for_timeout(7000)
        foto(page, "04-saltar-entre-papeis")
        ctx.close()


if __name__ == "__main__":
    os.makedirs(PASTA, exist_ok=True)
    {"admin_procurar": admin_procurar, "admin_ofertas": admin_ofertas, "admin_faixa": admin_faixa, "trocar_papel": trocar_papel}[sys.argv[1]]()
