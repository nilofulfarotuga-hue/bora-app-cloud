#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DIPSY-MISSAO (missao m3-dipsy-acesso-total-2026-11-08): uma missao grande para o Dipsy, sem conversa.

  python missao.py [pasta] [--prompt CAMINHO] [--minutos N]

- Le a missao de Desktop\\Bora\\prompt-dsh.md (ou --prompt). O nome da missao (= fluxo do e2e_log) vem da linha
  "MISSAO DIPSY: <nome>" / "MISSAO: <nome>" / "fluxo: <nome>"; sem ela, dipsy-missao-AAAA-MM-DD-HHMM.
- Pasta: um nome de ~/.dsh/pastas-dipsy.json (bora_app, em_dia, BoraStudio...); por omissao a do /pasta do Telegram.
- Se a pasta for um repositorio git, trabalha num WORKTREE PROPRIO: C:\\BoraLocal\\wt-dipsy-<nome>, ramo ai/AAAA-MM-DD-dipsy-<nome>,
  a partir do ramo atual (nunca mexe na arvore viva nem envia nada: o push precisa do "sim" do Danilo).
- Corre no perfil headless (a mesma guarda, o mesmo proxy com registo, as mesmas perguntas ao Danilo, o mesmo motor
  escolhido no Telegram com reservas), ate N minutos (por omissao 120).
- Regista no e2e_log (fluxo = nome da missao): inicio e fim. Grava a resposta em Desktop\\Bora\\dsh-saidas\\.
- Manda o fecho pelo PORTEIRO da VPS (fila porteiro_entrada -> Telegram do Danilo, em texto e voz).
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ponte  # noqa: E402   (reaproveita correr_dsh, registar_e2e, pastas, motor e o redator de segredos)

DESKTOP_BORA = r"C:\Users\danil\Desktop\Bora"
PROMPT = os.path.join(DESKTOP_BORA, "prompt-dsh.md")
SAIDAS = os.path.join(DESKTOP_BORA, "dsh-saidas")
NO_WINDOW = 0x08000000


def nome_missao(texto):
    m = re.search(r"(?im)^\s*(?:miss[aã]o(?:\s+dipsy)?|fluxo)\s*:\s*([a-z0-9][a-z0-9._-]{2,80})", texto)
    return m.group(1).lower() if m else datetime.now().strftime("dipsy-missao-%Y-%m-%d-%H%M")


def git(*args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, timeout=180, creationflags=NO_WINDOW)
    return r.returncode, (r.stdout or b"").decode("utf-8", "replace").strip(), (r.stderr or b"").decode("utf-8", "replace").strip()


def preparar_worktree(pasta, nome):
    """Worktree proprio (se a pasta for git). Devolve (caminho, ramo, nota)."""
    rc, topo, _ = git("rev-parse", "--show-toplevel", cwd=pasta)
    if rc != 0:
        return pasta, None, "a pasta nao e um repositorio git: trabalha nela diretamente"
    curto = re.sub(r"[^a-z0-9-]", "-", nome.lower())[:40].strip("-")
    destino = os.path.join(r"C:\BoraLocal", f"wt-dipsy-{curto}")
    ramo = f"ai/{datetime.now():%Y-%m-%d}-dipsy-{curto}"
    if os.path.isdir(destino):
        return destino, ramo, "worktree ja existia: continua nele"
    rc, _, erro = git("worktree", "add", "-b", ramo, destino, "HEAD", cwd=topo)
    if rc != 0:
        rc, _, erro = git("worktree", "add", destino, ramo, cwd=topo)   # o ramo ja existia
    if rc != 0:
        return pasta, None, f"nao consegui criar o worktree ({erro[:160]}); trabalha na pasta"
    sub = os.path.relpath(pasta, topo)
    return (os.path.join(destino, sub) if sub != "." else destino), ramo, f"worktree novo {destino} no ramo {ramo}"


def mandar_porteiro(texto, nivel="RESULTADO"):
    """Fila do porteiro da VPS (porteiro_entrada): chega ao Danilo pelo Telegram, em texto e voz."""
    import secrets as _s
    try:
        with open(ponte.FICH_CRED_SUPABASE, encoding="utf-8") as f:
            credencial = f.readline().split("=", 1)[1].strip()
        tag = "dm" + _s.token_hex(4)
        sql = (f"insert into public.porteiro_entrada (origem, nivel, texto) values ('dipsy-missao', ${tag}${nivel}${tag}$, "
               f"${tag}${ponte.redigir(texto)[:3500]}${tag}$) returning id")
        req = urllib.request.Request("https://api.supabase.com/v1/projects/ojykpzwqrtusfeakzrna/database/query",
                                     data=json.dumps({"query": sql}).encode("utf-8"), method="POST",
                                     headers={"Authorization": "Bearer " + credencial, "Content-Type": "application/json",
                                              "User-Agent": "bora-dipsy-missao/1"})
        credencial = None
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))[0]["id"]
    except Exception as e:
        ponte.log(f"missao: porteiro falhou ({type(e).__name__})")
        return None


def main():
    args = sys.argv[1:]
    prompt = PROMPT
    minutos = 120
    pasta_nome = None
    i = 0
    while i < len(args):
        if args[i] == "--prompt" and i + 1 < len(args):
            prompt = args[i + 1]; i += 2
        elif args[i] == "--minutos" and i + 1 < len(args):
            minutos = max(5, min(600, int(args[i + 1]))); i += 2
        else:
            pasta_nome = args[i]; i += 1
    if not os.path.exists(prompt):
        print(f"Falta o ficheiro da missão: {prompt}")
        return 2
    with open(prompt, encoding="utf-8-sig") as f:
        texto = f.read()
    nome = nome_missao(texto)
    pastas = ponte.pastas_dipsy()
    if pasta_nome:
        chave = next((k for k in pastas if k.lower() == pasta_nome.lower()), None)
        if not chave:
            print(f"Pasta desconhecida: {pasta_nome}. Usa: {', '.join(sorted(pastas))}")
            return 2
        pasta = pastas[chave]
    else:
        chave, pasta = ponte.pasta_atual()
    cwd, ramo, nota = preparar_worktree(pasta, nome)
    motor = ponte.motor_escolhido()
    print(f"Missão {nome} | pasta {chave} | {nota} | motor escolhido: {motor} | até {minutos} min")
    ponte.registar_e2e(nome, "dipsy-missao:inicio", "em-curso",
                       f"DIPSY-MISSAO arrancou: pasta {chave}, {nota}, motor escolhido {motor}, limite {minutos} min, prompt {prompt} ({len(texto)} letras)")
    inicio = time.time()
    pedido = (f"MISSÃO DO DANILO ({nome}), lançada pelo DIPSY-MISSAO. Trabalhas em {cwd}"
              + (f" (worktree próprio, ramo {ramo}: nunca envies nada para o servidor sem o sim do Danilo)" if ramo else "")
              + f". Regista cada passo no e2e_log do Bora com fluxo = '{nome}'. No fim, escreve um relatório curto em português "
                "simples: o que fizeste, o que falta e porquê, erros que encontraste.\n\n" + texto)
    estado = {"cancelado": False, "proc": None}
    resposta, quem = ponte.correr_dsh(pedido, estado, cwd=cwd, limite_min=minutos)
    seg = int(time.time() - inicio)
    os.makedirs(SAIDAS, exist_ok=True)
    saida = os.path.join(SAIDAS, f"{datetime.now():%Y-%m-%d_%H%M}-{nome}.md")
    with open(saida, "w", encoding="utf-8") as f:
        f.write(f"<!-- DIPSY-MISSAO {nome} | pasta {cwd} | ramo {ramo or '-'} | motor {quem} | {seg} s | {datetime.now().isoformat(timespec='seconds')} -->\n\n")
        f.write(ponte.redigir(resposta or f"(sem resposta: {quem})"))
    ok = resposta is not None
    ponte.registar_e2e(nome, "dipsy-missao:fim", "ok" if ok else "erro",
                       f"{'acabou' if ok else 'falhou'} em {seg} s, motor {quem}; resposta em {saida}; "
                       f"inicio da resposta: {(resposta or quem)[:600]}")
    resumo = (resposta or "")[:1800]
    fecho = (f"Dipsy: a missão {nome} {'acabou' if ok else 'não acabou'} ({seg // 60} min, motor {quem}). "
             + (f"Trabalhou no ramo {ramo}, sem enviar nada para o servidor. " if ramo else "")
             + (f"Resumo: {resumo}" if ok else f"Motivo: {quem}.") + f" O relatório inteiro está em {saida}.")
    pid = mandar_porteiro(fecho)
    print(fecho)
    print(f"[porteiro_entrada id {pid}]")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
