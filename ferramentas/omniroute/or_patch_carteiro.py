#!/usr/bin/env python3
"""23/10/2026 (2.a ronda omniroute): o recurso do carteiro deixa de depender da chave do OpenCode Go.

- carteiro.sh: GO_CADEIA = "omniroute zen-glm" (antes qwen3.8-max qwen3.7-max minimax-m3) e
  GO_FAILOVER_MODELO = omniroute; o selftest passa a usar os nomes novos.
- pc-loop-go: deixa de ir ao portatil velho (hermes@100.71.105.7) e ao claude.exe com o Go por tras;
  vai ao PC actual pelo alias bora-pc (/opt/data/.ssh/config) e corre o OpenCode (programa gratis):
  omniroute -> omniroute/agentes ; zen-glm -> opencode/glm-5.3-flash-free.
Copias antes em /root/backups/carteiro-antes-sem-go-20261023/. Ancoras exactas: falha alto se faltarem.
Uso: or_patch_carteiro.py [--desfazer]
"""
import os
import shutil
import subprocess
import sys

CART = "/root/orquestracao/carteiro.sh"
PCLG = "/docker/hermes-agent-fvnc/data/.local/bin/pc-loop-go"
BK = "/root/backups/carteiro-antes-sem-go-20261023"

TROCAS = [
    ('GO_FAILOVER_MODELO="${GO_FAILOVER_MODELO:-qwen3.7-max}"\n',
     '# 23/10/2026: o Danilo NAO renova o OpenCode Go (chave expirada). O recurso passou a ser o OpenCode\n'
     '# (programa gratis) no PC, pelo OmniRoute da VPS; ver pc-loop-go e run-opencode-recurso.ps1.\n'
     'GO_FAILOVER_MODELO="${GO_FAILOVER_MODELO:-omniroute}"\n'),
    ('GO_CADEIA="${GO_CADEIA:-qwen3.8-max qwen3.7-max minimax-m3}"\n',
     '# 23/10/2026: degraus novos (o nome "GO_" ficou por historia): omniroute = OpenCode + combo agentes do\n'
     '# OmniRoute; zen-glm = OpenCode + modelo gratis do OpenCode Zen (glm-5.3-flash-free). Depois, o Hermes.\n'
     'GO_CADEIA="${GO_CADEIA:-omniroute zen-glm}"\n'),
    ('  eh_motor_go "qwen3.7-max" && ok "qwen3.7-max reconhecido como degrau da cadeia" || bad "eh_motor_go"\n',
     '  eh_motor_go "omniroute" && ok "omniroute reconhecido como degrau da cadeia" || bad "eh_motor_go"\n'),
    ('  motor_marcar_esgotado "minimax-m3" "$((_now+900))" "teste" >/dev/null 2>&1\n',
     '  motor_marcar_esgotado "zen-glm" "$((_now+900))" "teste" >/dev/null 2>&1\n'),
    ('&& ok "cadeia toda esgotada -> espera pelo PRIMEIRO a repor (minimax-m3, +15min)"',
     '&& ok "cadeia toda esgotada -> espera pelo PRIMEIRO a repor (zen-glm, +15min)"'),
]

PC_LOOP_GO = r'''#!/bin/sh
# pc-loop-go — degrau de recurso do carteiro quando o plano Claude esgota.
# 23/10/2026: o OpenCode Go saiu (o Danilo nao renova; a chave expirou). Agora corre o OpenCode
# (programa gratis) no PC ACTUAL, com ferramentas, pelo alias bora-pc de /opt/data/.ssh/config:
#   --modelo omniroute -> omniroute/agentes (OmniRoute da VPS pelo Tailscale)
#   --modelo zen-glm   -> opencode/glm-5.3-flash-free (gratis, so dentro do OpenCode)
# Nao mexe no Claude Code (nada de ANTHROPIC_BASE_URL). Versao anterior: pc-loop-go.bak-go-20261023.
MODELO=""
case "$1" in
  --modelo) MODELO="$2"; shift 2 ;;
  --modelo=*) MODELO="${1#--modelo=}"; shift ;;
esac
case "$MODELO" in
  omniroute|"") OC="omniroute/agentes" ;;
  zen-glm)      OC="opencode/glm-5.3-flash-free" ;;
  *) echo "pc-loop-go: degrau desconhecido '$MODELO'"; exit 2 ;;
esac
REMOTO="powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\danil\\Desktop\\produtividade-ia\\hermes-bridge\\run-opencode-recurso.ps1 -Modelo $OC"
printf '%s' "$*" | base64 | tr -d '\n=' | ssh -F /opt/data/.ssh/config -o BatchMode=yes -o ConnectTimeout=25 -o ServerAliveInterval=30 -o ServerAliveCountMax=6 bora-pc "$REMOTO"
'''


def main():
    if "--desfazer" in sys.argv:
        shutil.copy2(os.path.join(BK, "carteiro.sh"), CART)
        shutil.copy2(os.path.join(BK, "pc-loop-go"), PCLG)
        print("reposto")
        return
    os.makedirs(BK, mode=0o700, exist_ok=True)
    for src, nome in ((CART, "carteiro.sh"), (PCLG, "pc-loop-go")):
        if not os.path.exists(os.path.join(BK, nome)):
            shutil.copy2(src, os.path.join(BK, nome))
    txt = open(CART, encoding="utf-8").read()
    for antes, depois in TROCAS:
        if txt.count(antes) != 1:
            raise SystemExit("ancora em falta/repetida no carteiro.sh: %r" % antes[:80])
        txt = txt.replace(antes, depois)
    with open(CART, "w", encoding="utf-8") as fh:
        fh.write(txt)
    r = subprocess.run(["bash", "-n", CART], capture_output=True, text=True)
    print("carteiro.sh remendado; bash -n rc=%d %s" % (r.returncode, r.stderr[:200]))
    shutil.copy2(PCLG, PCLG + ".bak-go-20261023")
    with open(PCLG, "w", encoding="utf-8") as fh:   # mesmo ficheiro: mantem dono e permissoes
        fh.write(PC_LOOP_GO)
    r = subprocess.run(["sh", "-n", PCLG], capture_output=True, text=True)
    print("pc-loop-go reescrito; sh -n rc=%d %s" % (r.returncode, r.stderr[:200]))


if __name__ == "__main__":
    main()
