"""PROVA NA WEB — sessão caída volta à página de entrar (missão 15/10/2026).

Conta de TESTE: demo-parceiro@bora.app (loja demo, invisível). Nunca a conta de
um dono de loja, nunca saída global numa conta real.

O que faz, em app.boraguarda.com, num browser do tamanho de um telemóvel:
  1. entra como parceiro de teste e abre um ecrã por cima do painel;
  2. revoga no servidor TODAS as sessões desta conta de teste (o que acontece
     quando a sessão cai: o refresh token deixa de valer);
  3. adianta o relógio do browser 65 minutos — o token de acesso expira e o
     SDK tenta renová-lo, como faria sozinho ao fim de uma hora;
  4. fotografa e lê o ecrã: com a correção, volta à entrada do parceiro e
     aparece "A tua sessão terminou. Entra outra vez."; sem ela, o ecrã fica
     aberto como se estivesse ligado.

  python -I prova_web_sessao_caida.py <etiqueta>     (ex.: antes / depois)
"""
import json
import os
import re
import subprocess
import sys

from playwright.sync_api import sync_playwright

AQUI = os.path.dirname(os.path.abspath(__file__))
URL = "https://app.boraguarda.com/"
EMAIL = "demo-parceiro@bora.app"
SENHA = "BoraDemo2026!"
CONTA = os.path.join(AQUI, "conta_teste.py")
AVISO = "A tua sessão terminou. Entra outra vez."

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ETIQ = sys.argv[1] if len(sys.argv) > 1 else "prova"
REGISTO = []


def log(*a):
    linha = " ".join(str(x) for x in a)
    print(linha, flush=True)
    REGISTO.append(linha)


def foto(page, nome):
    p = os.path.join(AQUI, f"{ETIQ}-{nome}.png")
    page.screenshot(path=p)
    log("   foto:", os.path.basename(p))


def textos(page):
    """Todos os rótulos que a camada de acessibilidade do Flutter expõe."""
    return page.evaluate(
        """() => Array.from(document.querySelectorAll('flt-semantics, [aria-label], [role]'))
              .map(e => (e.getAttribute('aria-label') || e.innerText || '').trim())
              .filter(t => t.length > 0 && t.length < 200)"""
    )


def ligar_acessibilidade(page):
    try:
        page.evaluate(
            "() => { const p = document.querySelector('flt-semantics-placeholder');"
            " if (p) p.click(); }"
        )
    except Exception as e:  # noqa: BLE001
        log("   acessibilidade:", e)
    page.wait_for_timeout(1200)


def tocar(page, padrao, papel=None, espera=2500):
    rx = re.compile(padrao, re.I)
    alvo = page.get_by_role(papel, name=rx) if papel else page.get_by_text(rx)
    alvo.first.click(timeout=15000)
    page.wait_for_timeout(espera)


def main():
    with sync_playwright() as pw:
        nav = pw.chromium.launch(headless=True)
        ctx = nav.new_context(
            viewport={"width": 430, "height": 880},
            geolocation={"latitude": 40.5373, "longitude": -7.2676},
            permissions=["geolocation"],
            locale="pt-PT",
        )
        ctx.add_init_script(ARRANQUE)
        page = ctx.new_page()
        page.clock.install()
        page.on("console", lambda m: REGISTO.append("[consola] " + m.text[:300])
                if ("AuthStore" in m.text or "auth" in m.text.lower()) else None)
        # O pedido de renovação da sessão e a resposta do servidor (prova do
        # mecanismo: sem isto, "o ecrã não mudou" podia ser só "não renovou").
        page.on("response", lambda r: log(
            "   [rede] renovar sessão ->", r.status)
            if "grant_type=refresh_token" in r.url else None)

        log("1. abrir", URL)
        page.goto(URL, wait_until="load", timeout=120000)
        page.wait_for_timeout(9000)
        ligar_acessibilidade(page)
        tam = page.evaluate(
            "() => performance.getEntriesByType('resource')"
            ".filter(r => /main\\.dart\\.js/.test(r.name)).map(r => r.decodedBodySize)")
        log("   main.dart.js carregado (bytes):", tam)
        foto(page, "01-inicio")

        log("2. papel parceiro")
        tocar(page, r"parceiro", "button")
        ligar_acessibilidade(page)
        foto(page, "02-entrada-parceiro")
        log("   no ecrã:", textos(page)[:25])

        log("3. entrar com a conta de teste")
        campos = page.locator("input")
        log("   campos de texto:", campos.count())
        # O Flutter só aceita teclas depois de o campo ganhar foco a sério.
        for i, valor in ((0, EMAIL), (1, SENHA)):
            campos.nth(i).click()
            page.wait_for_timeout(1200)
            page.keyboard.type(valor, delay=40)
            page.wait_for_timeout(600)
        log("   email escrito:", campos.nth(0).input_value())
        page.wait_for_timeout(500)
        tocar(page, r"^entrar$", "button", espera=9000)
        ligar_acessibilidade(page)
        foto(page, "03-painel")
        log("   no ecrã:", textos(page)[:30])

        log("4. abrir um ecrã por cima do painel (produtos)")
        try:
            tocar(page, r"produtos", "button", espera=5000)
        except Exception:  # noqa: BLE001
            tocar(page, r"produtos", None, espera=5000)
        ligar_acessibilidade(page)
        foto(page, "04-produtos")
        antes = textos(page)
        log("   no ecrã:", antes[:30])

        log("5. revogar no servidor as sessões da conta de TESTE")
        r = subprocess.run([sys.executable, "-I", CONTA, "sair-global"],
                           capture_output=True, text=True, timeout=120)
        log("  ", r.stdout.strip().replace("\n", " | "), r.stderr.strip()[:300])

        log("6. adiantar o relógio do browser 65 min (o token expira e o SDK renova)")
        page.clock.fast_forward("01:05:00")
        # Avança de segundo a segundo: o aviso dura 8 s e fotografa-se quando
        # aparece (saltos grandes de relógio fazem-no desaparecer antes).
        tem_aviso = False
        for _ in range(40):
            page.wait_for_timeout(1500)
            page.clock.fast_forward("00:00:01")
            if any(AVISO in t for t in textos(page)):
                tem_aviso = True
                foto(page, "05-aviso-sessao-terminou")
                log("   aviso no ecrã:", AVISO)
                break
        ligar_acessibilidade(page)
        foto(page, "06-depois-da-sessao-cair")
        depois = textos(page)
        log("   no ecrã:", depois[:30])

        voltou_entrada = any(re.search(r"^entrar$|palavra-passe|e-?mail", t, re.I)
                             for t in depois)
        ficou_produtos = any(re.search(r"produto", t, re.I) for t in depois)
        log("RESULTADO:", json.dumps({
            "aviso_sessao_terminou": tem_aviso,
            "ecrã_de_entrada": voltou_entrada,
            "ainda_mostra_produtos": ficou_produtos,
        }, ensure_ascii=False))
        nav.close()

    with open(os.path.join(AQUI, f"{ETIQ}-registo.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(REGISTO))


if __name__ == "__main__":
    main()
