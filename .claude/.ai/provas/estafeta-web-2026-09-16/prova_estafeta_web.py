"""PROVA DO ESTAFETA NO NAVEGADOR — missão estafeta-web-2026-09-16.

Abre a build web local (build/web servida em http://localhost:8765) num
navegador do tamanho de um telemóvel, com GPS fixo na Guarda e consentimento
gravado antes do arranque (as três lições de 29/08), entra com o estafeta demo
e fica à espera de COMANDOS num ficheiro — para a sessão do Claude Code poder
conduzir passo a passo (inserir o pedido de teste por SQL, ver a oferta,
aceitar, …) sem fechar o navegador entre passos.

  python prova_estafeta_web.py chromium   # Android (Chrome), notificações permitidas
  python prova_estafeta_web.py webkit     # iPhone (Safari-like)

Comandos (uma linha cada, em comandos-<motor>.txt; a resposta vai para
respostas-<motor>.txt):
  foto <nome>            captura de ecrã
  clique <x> <y>         clique por coordenadas (ecrã 430x880)
  escrever <x> <y> <t>   clica no campo e escreve
  rolar <px>             roda a lista
  esperar <segundos>
  js <expressão>         avalia JS na página
  fim                    fecha tudo (o vídeo fica gravado)
"""
import os
import sys
import time

from playwright.sync_api import sync_playwright

MOTOR = sys.argv[1] if len(sys.argv) > 1 else "chromium"
AQUI = os.path.dirname(os.path.abspath(__file__))
PASTA = os.path.join(AQUI, MOTOR)
URL = os.environ.get("BORA_URL", "http://localhost:8765/")
EMAIL = os.environ.get("BORA_EMAIL", "demo-estafeta@bora.app")
SENHA = os.environ.get("BORA_SENHA", "BoraDemo2026!")

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

UA_ANDROID = ("Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36")
UA_IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0_1 like Mac OS X) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")


def foto(page, nome):
    caminho = os.path.join(PASTA, nome + ".png")
    page.screenshot(path=caminho)
    return caminho


def escrever(page, x, y, texto):
    page.mouse.click(x, y)
    page.wait_for_timeout(700)
    ok = page.evaluate(
        """(t) => {
            const el = document.activeElement;
            if (!el || el.tagName !== 'INPUT') return false;
            const s = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value').set;
            s.call(el, t);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            return true;
        }""", texto)
    page.wait_for_timeout(500)
    return ok


def responder(linha):
    with open(os.path.join(AQUI, f"respostas-{MOTOR}.txt"), "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + linha + "\n")
    print(linha, flush=True)


def main():
    os.makedirs(PASTA, exist_ok=True)
    cmd_path = os.path.join(AQUI, f"comandos-{MOTOR}.txt")
    open(cmd_path, "w").close()
    open(os.path.join(AQUI, f"respostas-{MOTOR}.txt"), "w").close()

    with sync_playwright() as p:
        if MOTOR == "webkit":
            browser = p.webkit.launch(headless=os.environ.get("BORA_HEADED") != "1")
            ctx = browser.new_context(
                viewport={"width": 430, "height": 880}, device_scale_factor=1,
                user_agent=UA_IPHONE, is_mobile=True, has_touch=True,
                geolocation={"latitude": 40.5373, "longitude": -7.2676},
                permissions=["geolocation"], locale="pt-PT", timezone_id="Europe/Lisbon",
                record_video_dir=PASTA, record_video_size={"width": 430, "height": 880})
        else:
            # Contexto PERSISTENTE (perfil real, não incógnito): o Chrome não
            # suporta a Push API em incógnito (crbug 41124656) — sem isto o
            # getToken() falha com "permission denied" e o push web nunca se prova.
            perfil = os.path.join(os.environ.get("TEMP", AQUI), "bora-prova-estafeta-web-perfil")
            browser = None
            ctx = p.chromium.launch_persistent_context(
                perfil,
                headless=os.environ.get("BORA_HEADED") != "1",
                channel=os.environ.get("BORA_CHANNEL") or None,
                args=["--disable-dev-shm-usage", "--no-sandbox"],
                viewport={"width": 430, "height": 880}, device_scale_factor=1,
                user_agent=UA_ANDROID, is_mobile=True, has_touch=True,
                geolocation={"latitude": 40.5373, "longitude": -7.2676},
                permissions=["geolocation", "notifications"], locale="pt-PT",
                timezone_id="Europe/Lisbon",
                record_video_dir=PASTA, record_video_size={"width": 430, "height": 880})
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.add_init_script(ARRANQUE)
        consola = open(os.path.join(AQUI, f"consola-{MOTOR}.log"), "a", encoding="utf-8")
        def _on_console(m):
            try:
                consola.write(time.strftime("%H:%M:%S ") + f"[{m.type}] {m.text}" + chr(10)); consola.flush()
            except Exception:
                pass
            if (m.type in ("error", "warning") or "Heartbeat" in m.text or "WebPresence" in m.text
                    or "DriverHome" in m.text or "NotificationService" in m.text or "DriverStore" in m.text
                    or "[main]" in m.text or "Firebase" in m.text) and "GPU stall" not in m.text:
                responder(f"[console:{m.type}] {m.text[:300]}")
        page.on("console", _on_console)
        page.goto(URL, wait_until="load", timeout=180000)
        page.wait_for_timeout(15000)
        responder("aberto " + URL)
        foto(page, "00-arranque")
        responder("pronto: a aceitar comandos em " + cmd_path)

        feitos = 0
        inicio = time.time()
        while time.time() - inicio < 1800:
            try:
                linhas = open(cmd_path, encoding="utf-8").read().splitlines()
            except OSError:
                linhas = []
            novas = linhas[feitos:]
            if not novas:
                time.sleep(1)
                continue
            for linha in novas:
                feitos += 1
                linha = linha.strip()
                if not linha:
                    continue
                partes = linha.split(" ", 3)
                op = partes[0]
                try:
                    if op == "foto":
                        responder("foto " + foto(page, partes[1]))
                    elif op == "clique":
                        page.mouse.click(int(partes[1]), int(partes[2]))
                        page.wait_for_timeout(1500)
                        responder(f"clique {partes[1]} {partes[2]} ok")
                    elif op == "escrever":
                        ok = escrever(page, int(partes[1]), int(partes[2]), partes[3])
                        responder(f"escrever em ({partes[1]},{partes[2]}) input_activo={ok}")
                    elif op == "arrastar":
                        x1, y1, x2, y2 = [int(v) for v in linha.split()[1:5]]
                        page.mouse.move(x1, y1)
                        page.mouse.down()
                        page.mouse.move(x2, y2, steps=12)
                        page.mouse.up()
                        page.wait_for_timeout(1200)
                        responder("arrastar ok")
                    elif op == "rolar":
                        page.mouse.move(215, 600)
                        page.mouse.wheel(0, int(partes[1]))
                        page.wait_for_timeout(1200)
                        responder("rolar ok")
                    elif op == "rolar_em":
                        x, y, px = [int(v) for v in linha.split()[1:4]]
                        page.mouse.move(x, y)
                        page.mouse.wheel(0, px)
                        page.wait_for_timeout(1200)
                        responder("rolar_em ok")
                    elif op == "toque_arrastar":
                        # Arrasto por TOQUE (CDP): o Flutter web só deixa arrastar
                        # folhas/listas com o dedo, não com o rato.
                        x1, y1, x2, y2 = [int(v) for v in linha.split()[1:5]]
                        cdp = ctx.new_cdp_session(page)
                        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x1, "y": y1}]})
                        passos = 15
                        for i in range(1, passos + 1):
                            xi = x1 + (x2 - x1) * i // passos
                            yi = y1 + (y2 - y1) * i // passos
                            cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": xi, "y": yi}]})
                            time.sleep(0.03)
                        cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
                        cdp.detach()
                        page.wait_for_timeout(1500)
                        responder("toque_arrastar ok")
                    elif op == "toque":
                        x, y = int(partes[1]), int(partes[2])
                        page.touchscreen.tap(x, y)
                        page.wait_for_timeout(1500)
                        responder(f"toque {x} {y} ok")
                    elif op == "tecla":
                        page.keyboard.press(partes[1])
                        page.wait_for_timeout(800)
                        responder("tecla " + partes[1])
                    elif op == "ficheiro":
                        # próximo seletor de ficheiros recebe este caminho
                        caminho = linha[len("ficheiro "):].strip()
                        with page.expect_file_chooser(timeout=15000) as fc:
                            x, y = int(partes[1]), int(partes[2])
                            page.mouse.click(x, y)
                        fc.value.set_files(linha.split(" ", 3)[3].strip())
                        page.wait_for_timeout(2500)
                        responder("ficheiro enviado")
                    elif op == "esperar":
                        page.wait_for_timeout(int(float(partes[1]) * 1000))
                        responder("esperou " + partes[1])
                    elif op == "js":
                        expr = linha[3:]
                        responder("js => " + str(page.evaluate(expr))[:800])
                    elif op == "fim":
                        responder("a fechar")
                        ctx.close()
                        if browser is not None:
                            browser.close()
                        responder("FECHADO")
                        return
                    else:
                        responder("comando desconhecido: " + linha)
                except Exception as e:  # noqa: BLE001
                    responder(f"ERRO em '{linha}': {e}")
        responder("tempo esgotado; a fechar")
        ctx.close()
        if browser is not None:
            browser.close()


if __name__ == "__main__":
    main()
