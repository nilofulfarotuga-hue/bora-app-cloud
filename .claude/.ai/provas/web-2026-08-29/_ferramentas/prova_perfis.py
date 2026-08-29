"""PROVA: uma conta, uma pessoa, todos os perfis — e nenhum ecra preso.

Corre pela web, em app.boraguarda.com, com o Playwright. Sem cabo.

  python prova_perfis.py <fase> [args]
"""
import os
import shutil
import sys

from playwright.sync_api import sync_playwright

PASTA = os.path.join(
    r"C:\Users\danil\Desktop\projetosflutter\_wt-prod\.claude\.ai\provas",
    "perfis-2026-08-29")
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfis"
URL = "https://app.boraguarda.com/"

CONSENTIMENTO = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

# Ecra de 430x880 (telemovel). Com as legendas novas por baixo de cada porta,
# os botoes desceram — medidos na foto 00.
PORTA_CLIENTE = (215, 543)
PORTA_ESTAFETA = (215, 626)
PORTA_PARCEIRO = (215, 709)
CAMPO_EMAIL = (215, 285)
CAMPO_SENHA = (215, 348)
BOTAO_ENTRAR = (215, 427)


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, nome + ".png"))
    print("   foto:", nome)


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


def abrir(p, gps=True, limpar=False):
    if limpar and os.path.isdir(PERFIL):
        shutil.rmtree(PERFIL, ignore_errors=True)
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=False,
        viewport={"width": 430, "height": 880},
        geolocation={"latitude": 40.5373, "longitude": -7.2676} if gps else None,
        # SEM permissao de localizacao = a recusa que se quer provar.
        permissions=["geolocation"] if gps else [],
        locale="pt-PT", timezone_id="Europe/Lisbon",
        args=["--disable-dev-shm-usage", "--no-sandbox"])
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.add_init_script(CONSENTIMENTO)
    page.goto(URL, wait_until="load", timeout=180000)
    page.wait_for_timeout(14000)
    return ctx, page


def entrar(page, porta, email, senha):
    page.mouse.click(*porta)
    page.wait_for_timeout(6000)
    escrever(page, CAMPO_EMAIL, email)
    escrever(page, CAMPO_SENHA, senha)
    page.mouse.click(*BOTAO_ENTRAR)
    page.wait_for_timeout(26000)


# ── fases ──────────────────────────────────────────────────────────────────

def portas():
    """As tres portas, com as legendas que dizem a quem se destinam."""
    with sync_playwright() as p:
        ctx, page = abrir(p, limpar=True)
        foto(page, "00-as-tres-portas")
        ctx.close()


def estafeta_pendente_como_cliente():
    """PROVA 1 — estafeta com candidatura em analise entra como CLIENTE."""
    with sync_playwright() as p:
        ctx, page = abrir(p, limpar=True)
        foto(page, "01a-portas")
        entrar(page, PORTA_CLIENTE, "prova.multi@bora.app", "ProvaMulti!2026")
        foto(page, "01-estafeta-pendente-a-usar-como-cliente")
        ctx.close()


def trocar_para_estafeta():
    """PROVA 2 — a mesma conta troca para estafeta SEM palavra-passe."""
    with sync_playwright() as p:
        ctx, page = abrir(p)
        foto(page, "02a-onde-estou")
        y = int(sys.argv[2]) if len(sys.argv) > 2 else 28
        x = int(sys.argv[3]) if len(sys.argv) > 3 else 380
        page.mouse.click(x, y)
        page.wait_for_timeout(6000)
        foto(page, "02b-folha-de-perfis")
        ctx.close()


def parceiro_como_cliente():
    """PROVA 3 — conta de parceiro entra como cliente."""
    with sync_playwright() as p:
        ctx, page = abrir(p, limpar=True)
        entrar(page, PORTA_CLIENTE, "prova.loja@bora.app", "ProvaLoja!2026")
        foto(page, "03-parceiro-a-usar-como-cliente")
        ctx.close()


def porta_do_parceiro():
    """PROVA 4 — a porta do parceiro com o botao de voltar."""
    with sync_playwright() as p:
        ctx, page = abrir(p, limpar=True)
        page.mouse.click(*PORTA_PARCEIRO)
        page.wait_for_timeout(8000)
        foto(page, "04-porta-do-parceiro-com-voltar")
        ctx.close()


def sem_localizacao():
    """PROVA 5 — recusar a localizacao mostra a explicacao, nao o carregador."""
    with sync_playwright() as p:
        ctx, page = abrir(p, gps=False, limpar=True)
        entrar(page, PORTA_ESTAFETA, "prova.multi@bora.app", "ProvaMulti!2026")
        foto(page, "05a-logo-a-seguir")
        page.wait_for_timeout(40000)
        foto(page, "05-sem-localizacao")
        ctx.close()


def trocar_sem_senha():
    """PROVA 2 — do ecra de escolha para o perfil de estafeta, SEM escrever a
    palavra-passe. O ecra de escolha ja nao faz logout."""
    with sync_playwright() as p:
        ctx, page = abrir(p)
        foto(page, "02a-no-cliente")
        page.mouse.click(393, 31)          # a seta "Mudar modo"
        page.wait_for_timeout(6000)
        foto(page, "02b-ecra-de-escolha")
        page.mouse.click(*PORTA_ESTAFETA)  # Sou Estafeta
        page.wait_for_timeout(20000)
        foto(page, "02-trocou-para-estafeta-sem-senha")
        ctx.close()


def porta_parceiro2():
    """PROVA 4 — a porta do parceiro, vista em varios momentos."""
    with sync_playwright() as p:
        ctx, page = abrir(p, limpar=True)
        foto(page, "04a-portas")
        page.mouse.click(*PORTA_PARCEIRO)
        for i, espera in enumerate([4000, 6000, 8000], start=1):
            page.wait_for_timeout(espera)
            foto(page, "04b-parceiro-%d" % i)
        ctx.close()


if __name__ == "__main__":
    os.makedirs(PASTA, exist_ok=True)
    {
        "portas": portas,
        "cliente": estafeta_pendente_como_cliente,
        "trocar": trocar_para_estafeta,
        "parceiro_cliente": parceiro_como_cliente,
        "porta_parceiro": porta_do_parceiro,
        "sem_gps": sem_localizacao,
        "trocar_sem_senha": trocar_sem_senha,
        "porta_parceiro2": porta_parceiro2,
    }[sys.argv[1]]()
