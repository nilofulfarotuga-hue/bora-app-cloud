"""Prova Android (emulador) da missão tvde-pedir-nunca-trava-2026-10-14.

Mesma ideia do prova_web.py, por adb: cada comando do ficheiro JSON é um passo;
o ecrã lê-se pela árvore de acessibilidade (uiautomator dump), os toques vão ao
centro do elemento com aquele texto/descrição, e as capturas ficam aqui.

Comandos:
  ["wait", ms]
  ["tap", texto]            toca no 1.º elemento cujo text/content-desc contém texto
  ["type_into", rotulo, t]  toca no campo com esse rótulo e escreve t ("$ENV:X" lê do ambiente)
  ["key", nome]             ENTER | TAB | BACK | ESCAPE
  ["hide_kb"]               esconde o teclado (BACK só se o teclado estiver aberto)
  ["shot", nome]            captura nome.png (adb screencap)
  ["tree", nome]            textos visíveis em nome.txt
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PASTA = pathlib.Path(__file__).parent
ADB = os.environ.get(
    "ADB", str(pathlib.Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe")
)
LOG = PASTA / "prova-android.log"


def log(msg):
    linha = f"{time.strftime('%H:%M:%S')} {msg}"
    print(linha, flush=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(linha + "\n")


def adb(*args, binario=False):
    r = subprocess.run([ADB, *args], capture_output=True, timeout=120)
    return r.stdout if binario else r.stdout.decode("utf-8", "replace")


def nos():
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = adb("shell", "cat", "/sdcard/ui.xml")
    xml = xml[xml.find("<?xml"):] if "<?xml" in xml else xml
    try:
        raiz = ET.fromstring(xml)
    except ET.ParseError:
        return []
    out = []
    for n in raiz.iter("node"):
        b = re.findall(r"\d+", n.get("bounds", ""))
        if len(b) != 4:
            continue
        out.append({
            "texto": (n.get("text") or "") + " " + (n.get("content-desc") or ""),
            "classe": n.get("class", ""),
            "hint": n.get("hint") or "",
            "centro": ((int(b[0]) + int(b[2])) // 2, (int(b[1]) + int(b[3])) // 2),
        })
    return out


def achar(texto, so_campos=False):
    for n in nos():
        alvo = n["texto"] + " " + n["hint"]
        if texto.lower() in alvo.lower():
            if so_campos and "EditText" not in n["classe"]:
                continue
            return n
    return None


def main():
    comandos = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    for cmd in comandos:
        nome = cmd[0]
        try:
            if nome == "wait":
                time.sleep(int(cmd[1]) / 1000)
            elif nome == "tap":
                n = achar(cmd[1])
                if not n:
                    raise RuntimeError(f"não encontrei '{cmd[1]}'")
                adb("shell", "input", "tap", *map(str, n["centro"]))
            elif nome == "type_into":
                n = achar(cmd[1], so_campos=True) or achar(cmd[1])
                if not n:
                    raise RuntimeError(f"não encontrei o campo '{cmd[1]}'")
                adb("shell", "input", "tap", *map(str, n["centro"]))
                time.sleep(0.8)
                texto = cmd[2]
                if texto.startswith("$ENV:"):
                    texto = os.environ.get(texto[5:], "")
                # apaga o que lá estiver e escreve (espaços como %s)
                adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
                adb("shell", "input", "keyevent", *(["KEYCODE_DEL"] * 60))
                seguro = texto.replace(" ", "%s").replace("'", "")
                for ch in "()&;|<>":
                    seguro = seguro.replace(ch, "")
                adb("shell", "input", "text", seguro)
            elif nome == "key":
                adb("shell", "input", "keyevent", f"KEYCODE_{cmd[1]}")
            elif nome == "hide_kb":
                saida = adb("shell", "dumpsys", "input_method")
                if "mInputShown=true" in saida:
                    adb("shell", "input", "keyevent", "KEYCODE_BACK")
            elif nome == "shot":
                png = adb("exec-out", "screencap", "-p", binario=True)
                (PASTA / f"{cmd[1]}.png").write_bytes(png)
            elif nome == "tree":
                linhas = [n["texto"].strip() for n in nos() if n["texto"].strip()]
                (PASTA / f"{cmd[1]}.txt").write_text("\n".join(linhas), encoding="utf-8")
                log(f"arvore {cmd[1]}: {len(linhas)} linhas")
            log(f"OK {json.dumps(cmd, ensure_ascii=False)}")
        except Exception as e:  # noqa: BLE001
            log(f"FALHOU {json.dumps(cmd, ensure_ascii=False)}: {str(e)[:300]}")


if __name__ == "__main__":
    main()
