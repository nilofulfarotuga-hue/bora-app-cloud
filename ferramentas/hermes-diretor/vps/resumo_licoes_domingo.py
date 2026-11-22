#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
resumo_licoes_domingo.py — domingo a noite: arruma as licoes dos robos e conta ao Danilo, em voz, o que
aprenderam na semana (missao hermes-diretor-2026-11-20, B6.5). SEM IA: so conta e arruma.

  1. Junta as repetidas: a mesma regra (sem maiusculas nem espacos a mais) no mesmo robo -> fica a mais antiga
     com a soma das vezes; as outras ficam desligadas e arquivadas, com "[repetida da n.o X]" a frente do texto
     (assim nao chocam com a chave unica da base). Nada se apaga.
  2. Arquiva as velhas: licoes "por rever" (desligadas) que ninguem conferiu em 30 dias saem da lista
     (arquivada_em). Nada se apaga.
  3. Manda 3 linhas pelo porteiro (nivel RESULTADO: texto e voz): quantas licoes novas por robo, a mais
     repetida (ou a mais recente) e quantas estao por conferir no painel.
  Semana sem licoes novas nem nada por conferir: nao manda mensagem, so escreve no registo.

Cron do host (19:30 de Lisboa ao domingo; as duas horas UTC cobrem verao e inverno):
  30 18,19 * * 0 [ "$(TZ=Europe/Lisbon date +\\%H)" = "19" ] && /usr/bin/python3 /root/hermes-diretor/resumo_licoes_domingo.py >> /var/log/resumo-licoes.log 2>&1
  --ensaio   mostra o que arrumava e o texto, sem mudar nada nem mandar mensagem
"""
import json
import sys
import time
import urllib.request

sys.path.insert(0, "/opt/data/rotinas")
import despachante as D  # noqa: E402  (traz o acesso a base com a chave do host)

ENSAIO = "--ensaio" in sys.argv
NOMES = {"suporte": "o suporte", "amigo": "o Amigo Bora", "whatsapp": "o do WhatsApp", "hermes": "o Hermes"}


def iso(seg_atras):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - seg_atras))


def norma(t):
    return " ".join((t or "").lower().split())


def curta(t, teto=170):
    t = " ".join((t or "").split())
    if len(t) <= teto:
        return t.rstrip(". ") + "."
    return t[:teto].rsplit(" ", 1)[0].rstrip(",;:. ") + "…"


def porteiro(texto):
    req = urllib.request.Request("http://127.0.0.1:8796/telegram_danilo",
                                 data=json.dumps({"texto": texto, "nivel": "RESULTADO", "origem": "resumo-licoes-domingo"}).encode(),
                                 headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=30).read().decode()[:200]


def main():
    todas = D._rest("licoes_robos?arquivada_em=is.null&select=id,criada_em,robo,regra,origem,vezes,ativa&order=id.asc&limit=2000")
    if todas is None:
        print("%s a base nao respondeu: nao arrumo nem mando nada" % iso(0))
        return 1

    # 1. juntar as repetidas
    grupos = {}
    for l in todas:
        grupos.setdefault((l["robo"], norma(l["regra"])), []).append(l)
    juntas = 0
    for (_robo, _regra), linhas in grupos.items():
        if len(linhas) < 2:
            continue
        fica, resto = linhas[0], linhas[1:]
        soma = sum(int(x.get("vezes") or 1) for x in linhas)
        juntas += len(resto)
        print("  repetida: fica a n.o %s com %d vezes; arquiva %s" % (fica["id"], soma, [x["id"] for x in resto]))
        if ENSAIO:
            continue
        D._rest("licoes_robos?id=eq.%s" % fica["id"], "PATCH",
                {"vezes": soma, "ativa": bool(fica["ativa"] or any(x["ativa"] for x in resto)), "editada_em": "now()"})
        for x in resto:
            D._rest("licoes_robos?id=eq.%s" % x["id"], "PATCH",
                    {"ativa": False, "arquivada_em": "now()", "arquivada_por": "resumo-domingo",
                     "regra": ("[repetida da n.o %s] " % fica["id"] + x["regra"])[:700]})
        fica["vezes"] = soma
        for x in resto:
            todas.remove(x)

    # 2. arquivar as "por rever" que ninguem conferiu em 30 dias
    limite = iso(30 * 86400)
    velhas = [l for l in todas if not l["ativa"] and str(l["criada_em"])[:19] < limite[:19]]
    for l in velhas:
        print("  velha por rever: arquiva a n.o %s (%s)" % (l["id"], l["robo"]))
        if not ENSAIO:
            D._rest("licoes_robos?id=eq.%s" % l["id"], "PATCH", {"arquivada_em": "now()", "arquivada_por": "resumo-domingo"})
        todas.remove(l)

    # 3. o resumo
    semana = iso(7 * 86400)
    novas = [l for l in todas if l["ativa"] and str(l["criada_em"])[:19] >= semana[:19]]
    por_conferir = [l for l in todas if not l["ativa"]]
    ativas = [l for l in todas if l["ativa"]]
    print("%s ativas=%d novas_7d=%d por_conferir=%d juntas=%d velhas=%d" % (
        iso(0), len(ativas), len(novas), len(por_conferir), juntas, len(velhas)))
    if not novas and not por_conferir:
        print("  semana sem licoes novas: nao mando mensagem")
        return 0

    por_robo = {}
    for l in novas:
        por_robo[l["robo"]] = por_robo.get(l["robo"], 0) + 1
    partes = ", ".join("%s %d" % (NOMES.get(r, r), n) for r, n in sorted(por_robo.items(), key=lambda kv: -kv[1]))
    if novas:
        linha1 = "Resumo de domingo: esta semana os robôs aprenderam %d %s (%s)." % (
            len(novas), "lição nova" if len(novas) == 1 else "lições novas", partes)
    else:
        linha1 = "Resumo de domingo: esta semana os robôs não aprenderam lições novas; têm %d ao todo." % len(ativas)
    repetida = max(ativas, key=lambda l: (int(l.get("vezes") or 1), l["id"])) if ativas else None
    if repetida and int(repetida.get("vezes") or 1) > 1:
        linha2 = "A que mais se repetiu (%d vezes, %s): %s" % (
            int(repetida["vezes"]), NOMES.get(repetida["robo"], repetida["robo"]), curta(repetida["regra"]))
    elif novas:
        ultima = novas[-1]
        linha2 = "A mais recente (%s): %s" % (NOMES.get(ultima["robo"], ultima["robo"]), curta(ultima["regra"]))
    else:
        linha2 = "Nenhuma regra se repetiu."
    if por_conferir:
        linha3 = "Há %d por conferir no painel, em Lições dos robôs." % len(por_conferir)
    else:
        linha3 = "Não há nenhuma por conferir."
    texto = "\n".join([linha1, linha2, linha3])
    print(texto)
    if ENSAIO:
        print("  (ensaio) nao mandei nem mudei nada")
        return 0
    try:
        print("  porteiro:", porteiro(texto))
    except Exception as e:  # noqa: BLE001
        print("  porteiro falhou:", str(e)[:120])
        return 1
    D._rest("e2e_log", "POST", {"fluxo": "licoes-robos", "passo": "resumo-domingo-" + iso(0)[:10], "estado": "ok",
                                "device": "vps-resumo-licoes",
                                "detalhe": "Motor: nenhum (script sem IA). ativas=%d novas_7d=%d por_conferir=%d juntas=%d velhas=%d. Texto: %s"
                                           % (len(ativas), len(novas), len(por_conferir), juntas, len(velhas), texto)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
