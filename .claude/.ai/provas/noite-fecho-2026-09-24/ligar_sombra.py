#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Liga o decisor EM SOMBRA em dois sitios do Hermes (noite-fecho-2026-09-24, B4).

Sombra quer dizer: pergunta-se, grava-se, e NAO se muda nada do que a maquina faz. Se a
pergunta falhar, ninguem da por isso. Os dois sitios:

  1. PORTEIRO DO TELEGRAM (rotinas/emerson.py) — o que decide se uma tarefa fechada fala ao
     Danilo no privado ou fica calada. Pergunta-se "isto devia chegar-lhe agora?" com o que
     de facto aconteceu, para depois se poder comparar.
  2. DESPACHANTE DE BOTS (rotinas/despachante.py) — o que escolhe qual agente responde.
     Pergunta-se "o agente escolhido e o certo para este pedido?".

Faz copia de seguranca de cada ficheiro e nao repete se ja tiver a marca.
"""
import io
import shutil
import sys

MARCA = "decisor em sombra (noite-fecho-2026-09-24)"

IMPORTA = '''
# --- %s ---------------------------
# A ferramenta vive em /opt/data/ferramentas/decidir.py. Se faltar, ou se a chave nao
# estiver no .env, `_sombra` fica None e tudo segue exactamente como seguia.
try:
    sys.path.insert(0, "/opt/data/ferramentas")
    from decidir import perguntar_em_sombra as _sombra
except Exception:  # noqa: BLE001
    _sombra = None


def _em_sombra(*a, **k):
    """Nunca rebenta quem chama: uma sombra que estraga trabalho nao e sombra."""
    if _sombra is None:
        return
    try:
        _sombra(*a, **k)
    except Exception:  # noqa: BLE001
        pass
# -----------------------------------------------------------------------------
''' % MARCA


def remendar(caminho, ancora, novo, precisa_sys=True):
    s = io.open(caminho, encoding="utf-8").read()
    if MARCA in s:
        print("%s: ja tinha a sombra" % caminho)
        return False
    if s.count(ancora) != 1:
        print("%s: ancora nao unica (%d) — NAO mexi" % (caminho, s.count(ancora)))
        return False
    if precisa_sys and "\nimport sys" not in s and "\nimport sys\n" not in s:
        s = s.replace("import os\n", "import os\nimport sys\n", 1)
    # o bloco do import entra depois do ultimo import de topo
    fim_imports = s.rfind("\nimport ")
    fim_linha = s.find("\n", fim_imports + 1)
    s = s[:fim_linha + 1] + IMPORTA + s[fim_linha + 1:]
    s = s.replace(ancora, novo)
    shutil.copyfile(caminho, caminho + ".bak-sombra-2026-09-25")
    io.open(caminho, "w", encoding="utf-8", newline="\n").write(s)
    print("%s: sombra ligada" % caminho)
    return True


# ── 1) Porteiro do Telegram ────────────────────────────────────────────────────
PORTEIRO_ANCORA = """        avisar(cabeca + chr(10) + corpo_aviso + chr(10) + resultado[:600])
    return estado"""
PORTEIRO_NOVO = """        avisar(cabeca + chr(10) + corpo_aviso + chr(10) + resultado[:600])

    # SOMBRA: o que o decisor do Bora teria dito sobre interromper o Danilo. So grava.
    _em_sombra(
        "hermes-porteiro",
        "Should this finished task interrupt the owner on his private Telegram right now?",
        {"origem": origem, "tipo": tipo, "estado": estado, "titulo": titulo[:200],
         "passos": len(subs), "resultado": (resultado or "")[:600]},
        {"true": "Interrupt him now: client or money is waiting, or the system is down",
         "false": "It can wait for the morning note"},
        str(id_))
    return estado"""

# ── 2) Despachante de bots ─────────────────────────────────────────────────────
DESPACHO_ANCORA = """    return b, porque, pontos"""
DESPACHO_NOVO = """    # SOMBRA: o decisor concorda com o agente escolhido? So grava; a escolha e a de cima.
    _em_sombra(
        "hermes-despachante",
        "Is the chosen agent the right one to answer this request?",
        {"pedido": (pedido or "")[:600], "agente_escolhido": b, "porque": porque,
         "pontos": {k: v for k, v in (pontos or {}).items()}},
        {"true": "Yes, this agent fits the request",
         "false": "No, another agent (or Emerson himself) would answer better"})
    return b, porque, pontos"""


if __name__ == "__main__":
    remendar("/opt/data/rotinas/emerson.py", PORTEIRO_ANCORA, PORTEIRO_NOVO)
    remendar("/opt/data/rotinas/despachante.py", DESPACHO_ANCORA, DESPACHO_NOVO)
    import py_compile
    for f in ("/opt/data/rotinas/emerson.py", "/opt/data/rotinas/despachante.py"):
        py_compile.compile(f, doraise=True)
        print("compila:", f)
