"""Instala o WhatsApp da Bora (bora_wa.py) no assistente de negócio da VPS. Corre-se na VPS:

    cd /opt/voz && git pull -q && python3 voz/whatsapp/instalar_bora_wa.py

1. copia bora_wa.py para /opt/assistente-negocio (cópia de segurança do anterior);
2. assistente.py: o tenant tipo 'bora' passa para bora_wa.atender (logo a seguir a encontrar o tenant);
3. servidor.py: arranca o laço de revisão (aprender com os erros) ao lado das rotinas;
4. .env: copia GEMINI_TTS_KEY e VOZ_SENHA do .env da central de voz, ficheiro para ficheiro (nunca aparecem no ecrã);
5. reinicia o assistente-negocio e mostra a saúde.
Pode correr-se várias vezes: o que já está feito não se repete."""
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
DEST = "/opt/assistente-negocio"
ENV_VOZ = "/opt/voz/voz/atendente/.env"
CARIMBO = time.strftime("%Y%m%d-%H%M")


def copia_seguranca(caminho):
    if os.path.exists(caminho):
        shutil.copy2(caminho, f"{caminho}.bak-bora-wa-{CARIMBO}")


def main():
    # 1
    destino = os.path.join(DEST, "bora_wa.py")
    copia_seguranca(destino)
    shutil.copy2(os.path.join(AQUI, "bora_wa.py"), destino)
    print("1 bora_wa.py copiado")

    # 2
    p = os.path.join(DEST, "assistente.py")
    s = open(p, encoding="utf-8").read()
    if "bora_wa.atender" not in s:
        m = re.search(r'(    t, porque = tenant_para\(sessao, numero[^\n]*\)\n    if not t:\n'
                      r'        return \{"tratado": False, "acao": "nao-e-do-assistente"\}\n)', s)
        if not m:
            sys.exit("2 FALHOU: não encontrei o sítio do gancho em assistente.py (nada mudou)")
        gancho = ('    if tipo_de(t) == "bora":  # 27/11/2026: WhatsApp da Bora -> mesma assistente do telefone (bora_wa.py)\n'
                  '        import bora_wa\n'
                  '        return bora_wa.atender(t, porque, ev, simular)\n')
        copia_seguranca(p)
        s = s[:m.end()] + gancho + s[m.end():]
        open(p, "w", encoding="utf-8").write(s)
        print("2 gancho posto em assistente.py")
    else:
        print("2 gancho já estava")

    # 3
    p = os.path.join(DEST, "servidor.py")
    s = open(p, encoding="utf-8").read()
    if "bora_wa.laco_revisao" not in s:
        ancora = '        threading.Thread(target=laco_pedidos, daemon=True).start()\n'
        if ancora not in s:
            sys.exit("3 FALHOU: não encontrei o arranque das rotinas em servidor.py")
        novo = ancora + ('        try:  # 27/11/2026: WhatsApp da Bora aprende com cada conversa (bora_wa.py)\n'
                         '            import bora_wa\n'
                         '            threading.Thread(target=bora_wa.laco_revisao, daemon=True).start()\n'
                         '        except Exception as e:  # noqa: BLE001\n'
                         '            log("bora_wa: revisao nao arrancou", e)\n')
        copia_seguranca(p)
        open(p, "w", encoding="utf-8").write(s.replace(ancora, novo, 1))
        print("3 laço de revisão posto em servidor.py")
    else:
        print("3 laço já estava")

    # 4
    env_dest = os.path.join(DEST, ".env")
    atual = open(env_dest, encoding="utf-8").read()
    tem = {l.split("=", 1)[0].strip() for l in atual.splitlines() if "=" in l and not l.startswith("#")}
    novas = []
    for l in open(ENV_VOZ, encoding="utf-8").read().splitlines():
        k = l.split("=", 1)[0].strip() if "=" in l else ""
        if k in ("GEMINI_TTS_KEY", "VOZ_SENHA") and k not in tem:
            novas.append(l)
    if novas:
        with open(env_dest, "a", encoding="utf-8") as f:
            f.write(("" if atual.endswith("\n") else "\n") + "\n".join(novas) + "\n")
    print("4 chaves copiadas:", [l.split("=", 1)[0] for l in novas] or "nenhuma (já estavam)")

    # 5
    for f in ("assistente.py", "servidor.py", "bora_wa.py"):
        r = subprocess.run([sys.executable, "-m", "py_compile", os.path.join(DEST, f)], capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"5 FALHOU a compilar {f}: {r.stderr[-300:]}")
    subprocess.run(["systemctl", "restart", "assistente-negocio"], check=True)
    time.sleep(3)
    try:
        print("5 saude:", urllib.request.urlopen("http://127.0.0.1:8795/saude", timeout=5).read().decode()[:400])
    except Exception as e:  # noqa: BLE001
        print("5 saude falhou:", e)


if __name__ == "__main__":
    main()
