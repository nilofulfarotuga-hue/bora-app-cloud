"""Navegador de prova (missão cadastro-estafeta-fotos-22-10).

Abre app.boraguarda.com num Chromium (Playwright) e fica à espera de comandos
em <fila>/cmd/<n>.json; escreve o resultado em <fila>/res/<n>.txt. Assim o
Flutter web (canvas) explora-se passo a passo sem perder o estado da página.

Comandos (lista JSON): ver prova_web.py da missão tvde-pedir-nunca-trava, mais:
  ["file", texto_do_botao, caminho]   toca no botão e entrega o ficheiro ao seletor
  ["click_xy", x, y]                  clique por coordenadas (último recurso)
  ["fill_label", rotulo, texto]       escreve num campo pelo rótulo acessível
  ["quit"]
Capturas e árvores vão para a pasta indicada em PASTA_SAIDA (por defeito esta).
"""
import json
import os
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

FILA = pathlib.Path(sys.argv[1])
SAIDA = pathlib.Path(os.environ.get("PASTA_SAIDA", str(pathlib.Path(__file__).parent)))
PERFIL = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else FILA / "perfil"
URL = os.environ.get("URL_PROVA", "https://app.boraguarda.com/")
(FILA / "cmd").mkdir(parents=True, exist_ok=True)
(FILA / "res").mkdir(parents=True, exist_ok=True)
SAIDA.mkdir(parents=True, exist_ok=True)
LOG = SAIDA / "prova-web.log"


def log(msg):
    linha = f"{time.strftime('%H:%M:%S')} {msg}"
    with LOG.open("a", encoding="utf-8") as f:
        f.write(linha + "\n")
    return linha


def semantica(page):
    return page.evaluate(
        "() => { const p = document.querySelector('flt-semantics-placeholder');"
        " if (p) p.click(); return !!p; }")


def correr(page, cmd):
    nome = cmd[0]
    if nome == "goto":
        page.goto(cmd[1] if len(cmd) > 1 else URL, wait_until="load", timeout=120000)
        page.wait_for_timeout(9000)
        semantica(page)
        page.wait_for_timeout(1500)
        return "ok"
    if nome == "sem":
        return str(semantica(page))
    if nome == "wait":
        page.wait_for_timeout(int(cmd[1]))
        return "ok"
    if nome == "click":
        page.get_by_text(cmd[1], exact=len(cmd) > 2 and cmd[2] == "exact").first.click(timeout=15000)
        return "ok"
    if nome == "click_role":
        page.get_by_role(cmd[1], name=cmd[2]).first.click(timeout=15000)
        return "ok"
    if nome == "click_xy":
        page.mouse.click(float(cmd[1]), float(cmd[2]))
        return "ok"
    if nome in ("type_into", "fill_label"):
        campo = page.get_by_label(cmd[1]).first
        campo.click(timeout=15000)
        page.wait_for_timeout(1200)
        page.keyboard.press("Control+A")
        page.keyboard.type(cmd[2], delay=40)
        return "ok"
    if nome == "type":
        page.keyboard.type(cmd[1], delay=40)
        return "ok"
    if nome == "key":
        page.keyboard.press(cmd[1])
        return "ok"
    if nome == "scroll":
        page.mouse.move(260, 500)
        page.mouse.wheel(0, int(cmd[1]))
        page.wait_for_timeout(600)
        return "ok"
    if nome == "file":
        with page.expect_file_chooser(timeout=20000) as fc:
            page.get_by_text(cmd[1], exact=False).first.click(timeout=15000)
        fc.value.set_files(cmd[2])
        return "ok"
    if nome == "file_last":
        # Galeria: o seletor de ficheiro abre a partir da folha "Câmara/Galeria".
        with page.expect_file_chooser(timeout=20000) as fc:
            page.get_by_text(cmd[1], exact=False).last.click(timeout=15000)
        fc.value.set_files(cmd[2])
        return "ok"
    if nome == "shot":
        page.screenshot(path=str(SAIDA / f"{cmd[1]}.png"), timeout=60000, full_page=False)
        return f"captura {cmd[1]}.png"
    if nome == "tree":
        snap = page.locator("flt-semantics-host").aria_snapshot(timeout=30000)
        (SAIDA / f"{cmd[1]}.txt").write_text(snap, encoding="utf-8")
        return snap[-3500:]
    if nome == "js":
        return str(page.evaluate(cmd[1]))[:3000]
    return "comando desconhecido"


def main():
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            str(PERFIL), headless=True, viewport={"width": 480, "height": 960},
            locale="pt-PT", service_workers="block")
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on("console", lambda m: m.type == "error" and log(f"consola {m.text[:200]}"))

        def resp(r):
            u = r.url
            if any(k in u for k in ("upload-driver-document", "driver_register_or_update",
                                     "admin_send_push", "/rest/v1/e2e_log", "delete-account")):
                log(f"rede {r.request.method} {r.status} {u.split('.co')[-1][:90]}")
        page.on("response", resp)
        log("pronto")
        feitos = set()
        while True:
            for f in sorted((FILA / "cmd").glob("*.json")):
                if f.name in feitos:
                    continue
                feitos.add(f.name)
                try:
                    cmds = json.loads(f.read_text(encoding="utf-8"))
                except Exception as e:  # noqa: BLE001
                    (FILA / "res" / (f.stem + ".txt")).write_text(f"JSON invalido: {e}", encoding="utf-8")
                    continue
                saida = []
                for c in cmds:
                    if c[0] == "quit":
                        ctx.close()
                        (FILA / "res" / (f.stem + ".txt")).write_text("bye", encoding="utf-8")
                        return
                    try:
                        r = correr(page, c)
                        saida.append(log(f"OK {json.dumps(c, ensure_ascii=False)[:160]} -> {r[:200] if c[0] != 'tree' else ''}"))
                        if c[0] == "tree":
                            saida.append(r)
                    except Exception as e:  # noqa: BLE001
                        saida.append(log(f"FALHOU {json.dumps(c, ensure_ascii=False)[:160]}: {str(e)[:300]}"))
                        break
                (FILA / "res" / (f.stem + ".txt")).write_text("\n".join(saida), encoding="utf-8")
            time.sleep(0.5)


if __name__ == "__main__":
    main()
