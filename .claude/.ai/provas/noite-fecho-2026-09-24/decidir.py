#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""decidir — o Hermes pergunta ao decisor do Bora, EM SOMBRA.

Missão noite-fecho-2026-09-24, bloco B4. Vive em /opt/data/ferramentas/decidir.py.

O QUE FAZ: manda uma pergunta de sim/não ao decisor (Edge `decidir` do Bora) e vai-se embora.
A resposta NÃO volta para quem perguntou e NÃO muda comportamento nenhum — fica só uma linha
em `decisoes`, para depois se poder comparar o que o decisor teria dito com o que o Hermes
fez de facto. É isso que "sombra" quer dizer.

PORQUE NÃO USA A CHAVE DE SERVIÇO: a Edge `decidir` só aceita service_role, e essa chave dá
poder para ler e escrever tudo na base. Pô-la nesta máquina por causa de uma pergunta em
sombra era desproporcionado. Em vez disso há uma porta estreita no Supabase,
`decidir_sombra`, que só aceita uma chave própria do Hermes (HERMES_DECISOR_KEY no .env) e
que faz a chamada por dentro, com a chave de serviço a nunca sair da base. Esta chave não
serve para mais nada: só para fazer perguntas em sombra.

NUNCA REBENTA QUEM A CHAMA. Se a chave faltar, se a rede cair, se o Supabase responder mal —
regista no log e devolve False. O Porteiro e o despachante seguem exactamente como seguiam.

Uso:
    from decidir import perguntar_em_sombra
    perguntar_em_sombra("hermes-porteiro", "Should this reach the owner right now?",
                        {"origem": "relogio", "texto": "..."},
                        {"true": "Interrupt the owner now", "false": "It can wait"})
"""
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENV = "/opt/data/.env"
LOG = "/opt/data/logs/decidir-sombra.log"
TEMPO = 8          # segundos; o Hermes não pode ficar pendurado à espera de uma sombra


def _ambiente():
    e = {}
    try:
        for linha in io.open(ENV, encoding="utf-8", errors="replace"):
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                k, v = linha.split("=", 1)
                e[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:                                             # noqa: BLE001
        pass
    return e


def _log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with io.open(LOG, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except Exception:                                             # noqa: BLE001
        pass


def perguntar_em_sombra(usado_por, pergunta, estado, criterios=None, contexto_id=None):
    """Dispara a pergunta e devolve True se o pedido saiu. Nunca levanta excepção."""
    e = _ambiente()
    url = (e.get("SUPABASE_URL") or "").rstrip("/")
    anon = e.get("SUPABASE_ANON_KEY") or ""
    chave = e.get("HERMES_DECISOR_KEY") or ""
    if not url or not anon:
        _log("sem SUPABASE_URL/ANON no .env — sombra saltada (%s)" % usado_por)
        return False
    if not chave:
        _log("sem HERMES_DECISOR_KEY no .env — sombra saltada (%s). "
             "Pôr a chave da porta decidir_sombra no /opt/data/.env." % usado_por)
        return False
    if not str(usado_por).startswith("hermes-"):
        _log("usado_por tem de comecar por hermes- (veio %r)" % usado_por)
        return False

    corpo = json.dumps({
        "p_chave": chave,
        "p_usado_por": usado_por,
        "p_pergunta": pergunta,
        "p_estado": estado,
        "p_criterios": criterios,
        "p_contexto_id": contexto_id,
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url + "/rest/v1/rpc/decidir_sombra", data=corpo,
        headers={"apikey": anon, "Authorization": "Bearer " + anon,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TEMPO) as r:
            resposta = r.read().decode("utf-8", "replace").strip()
        _log("ok %s -> pedido %s" % (usado_por, resposta[:40]))
        return True
    except urllib.error.HTTPError as ex:
        _log("HTTP %s em %s: %s" % (ex.code, usado_por, ex.read().decode("utf-8", "replace")[:160]))
    except Exception as ex:                                       # noqa: BLE001
        _log("falhou %s: %s" % (usado_por, str(ex)[:160]))
    return False


if __name__ == "__main__":
    # Uso à mão, para provar: python3 decidir.py "a pergunta" "o estado"
    q = sys.argv[1] if len(sys.argv) > 1 else "Should this message reach the owner right now?"
    est = sys.argv[2] if len(sys.argv) > 2 else "prova a mao da ferramenta decidir"
    ok = perguntar_em_sombra("hermes-prova", q, {"texto": est},
                             {"true": "Interrupt the owner now", "false": "It can wait"})
    print("disparado:", ok, "| log:", LOG)
    sys.exit(0 if ok else 1)
