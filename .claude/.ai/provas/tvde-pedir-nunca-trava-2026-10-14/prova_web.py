"""Prova web da missão tvde-pedir-nunca-trava-2026-10-14.

Corre a app (build/web servido em http://127.0.0.1:8766) num Chromium com
sessão persistente e o GPS RECUSADO de propósito, e executa os comandos de um
ficheiro JSON (lista de [comando, argumentos...]). Cada passo fica no log e as
capturas ficam nesta pasta — o artefacto da prova (PADRAO_BORA 3.10).

Comandos:
  ["goto", url]                 abre a página e liga a acessibilidade do Flutter
  ["sem"]                       liga a acessibilidade (flt-semantics-placeholder)
  ["wait", ms]
  ["click", texto]              clica no elemento acessível com esse nome
  ["click_role", role, nome]    clica por papel + nome (ex.: button, "Solicitar corrida")
  ["type_into", rotulo, texto]  foca o campo com esse rótulo e escreve como teclado
  ["key", tecla]                carrega numa tecla (Tab, Enter…)
  ["blur"]                      tira o foco do campo (sair do campo)
  ["shot", nome]                captura de ecrã nome.png
  ["tree", nome]                árvore de acessibilidade em nome.txt
  ["js", codigo]                corre JS e regista o resultado
"""
import json
import os
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

PASTA = pathlib.Path(__file__).parent
# O perfil guarda a sessão da conta demo: fica FORA do repositório.
PERFIL = pathlib.Path(
    os.environ.get("PERFIL_PROVA", str(pathlib.Path.home() / "AppData/Local/Temp/bora-prova-tvde-perfil"))
)
LOG = PASTA / "prova-web.log"


def log(msg: str) -> None:
    linha = f"{time.strftime('%H:%M:%S')} {msg}"
    print(linha, flush=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(linha + "\n")


def ligar_semantica(page) -> None:
    try:
        page.evaluate(
            "() => { const p = document.querySelector('flt-semantics-placeholder');"
            " if (p) p.click(); return !!p; }"
        )
    except Exception as e:  # noqa: BLE001
        log(f"semantica: {e}")


def main() -> int:
    comandos = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            str(PERFIL),
            headless=True,
            viewport={"width": 520, "height": 1000},
            locale="pt-PT",
            permissions=[],  # GPS recusado: a app tem de deixar escrever
            service_workers="block",
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on("console", lambda m: m.type in ("error", "warning") and log(f"consola[{m.type}] {m.text[:300]}"))

        # Rede que interessa à prova: o evento pedido_travado e qualquer
        # tentativa de criar corrida (tem de haver ZERO).
        def _resposta(r):
            u = r.url
            if any(k in u for k in ("web_health_events", "tvde_request_ride", "tvde_rides?", "tvde_calculate_fare")):
                corpo = ""
                try:
                    if r.request.method == "POST":
                        corpo = (r.request.post_data or "")[:200]
                except Exception:  # noqa: BLE001
                    pass
                log(f"rede {r.request.method} {r.status} {u.split('/rest/v1/')[-1][:80]} {corpo}")

        page.on("response", _resposta)
        for cmd in comandos:
            nome = cmd[0]
            try:
                if nome == "goto":
                    page.goto(cmd[1], wait_until="load", timeout=120000)
                    page.wait_for_timeout(8000)
                    ligar_semantica(page)
                    page.wait_for_timeout(1500)
                elif nome == "sem":
                    ligar_semantica(page)
                    page.wait_for_timeout(800)
                elif nome == "wait":
                    page.wait_for_timeout(int(cmd[1]))
                elif nome == "click":
                    page.get_by_text(cmd[1], exact=False).first.click(timeout=15000)
                elif nome == "click_role":
                    page.get_by_role(cmd[1], name=cmd[2]).first.click(timeout=15000)
                elif nome == "type_into":
                    campo = page.get_by_label(cmd[1]).first
                    campo.click(timeout=15000)
                    page.wait_for_timeout(300)
                    page.keyboard.press("Control+A")
                    # "$ENV:NOME" lê de uma variável de ambiente (a senha da
                    # conta demo nunca fica escrita nos ficheiros de prova).
                    texto = cmd[2]
                    if texto.startswith("$ENV:"):
                        texto = os.environ.get(texto[5:], "")
                    page.keyboard.type(texto, delay=40)
                elif nome == "key":
                    page.keyboard.press(cmd[1])
                elif nome == "blur":
                    page.evaluate("() => document.activeElement && document.activeElement.blur()")
                elif nome == "shot":
                    page.screenshot(path=str(PASTA / f"{cmd[1]}.png"), timeout=60000)
                elif nome == "tree":
                    snap = page.locator("flt-semantics-host").aria_snapshot(timeout=30000)
                    (PASTA / f"{cmd[1]}.txt").write_text(snap, encoding="utf-8")
                    log(f"arvore {cmd[1]}: {len(snap)} chars")
                elif nome == "js":
                    log(f"js => {page.evaluate(cmd[1])}")
                log(f"OK {json.dumps(cmd, ensure_ascii=False)}")
            except Exception as e:  # noqa: BLE001
                log(f"FALHOU {json.dumps(cmd, ensure_ascii=False)}: {str(e)[:400]}")
                try:
                    page.screenshot(path=str(PASTA / f"erro-{nome}.png"), timeout=30000)
                except Exception:  # noqa: BLE001
                    pass
        ctx.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
