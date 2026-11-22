#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
batimento_torre.py — o batimento SEM IA de hora a hora (missao hermes-diretor-2026-11-20, B3.4).

Confirma tres coisas e so fala se alguma falhar:
  1. o gateway do Hermes responde;
  2. a fila do despacho anda (nada aberto ha mais de 40 min nem preso a executar ha mais de 30);
  3. o vigia por eventos (sentinela_varrer) correu nos ultimos 5 minutos — so quando ja estiver aplicado.
Falha -> evento 'urgente' no vigia (que cria a tarefa para o emerson). Enquanto o vigia nao estiver
aplicado na base, o aviso vai pelo porteiro (caso "app, site ou funcao em baixo").

TROCA AUTOMATICA DA TORRE: quando o vigia por eventos estiver vivo em 2 batimentos seguidos, a ronda de IA da
torre passa de hora a hora para 1 vez por dia (cadencia_min 60 -> 1440). Antes disso a torre continua de hora
a hora, para nunca ficarmos sem ninguem a olhar.

Cron do host: 52 * * * * /usr/bin/python3 /root/hermes-diretor/batimento_torre.py >> /var/log/batimento-torre.log 2>&1
  --ensaio   mede e mostra, sem avisar ninguem nem mudar nada
"""
import json
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, "/opt/data/rotinas")
import despachante as D  # noqa: E402  (traz o acesso a base com a chave do host)

C = "hermes-agent-fvnc-hermes-agent-1"
ESTADO = "/root/hermes-diretor/batimento.json"
ENSAIO = "--ensaio" in sys.argv


def iso(seg_atras):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - seg_atras))


def gateway_vivo():
    r = subprocess.run(["docker", "exec", C, "sh", "-lc",
                        'pgrep -f "[h]ermes gateway run|sys[.]exit[(]main[(][)][)] gateway run" >/dev/null'],
                       capture_output=True, timeout=40)
    return r.returncode == 0


def porteiro(texto):
    req = urllib.request.Request("http://127.0.0.1:8796/telegram_danilo",
                                 data=json.dumps({"texto": texto, "nivel": "URGENTE", "origem": "batimento-torre"}).encode(),
                                 headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=20).read()


def main():
    try:
        mem = json.load(open(ESTADO))
    except Exception:
        mem = {"vigia_ok_seguidos": 0}
    problemas = []

    try:
        if not gateway_vivo():
            time.sleep(20)
            if not gateway_vivo():
                problemas.append(("gateway", "o gateway do Hermes nao responde"))
    except Exception as e:  # noqa: BLE001
        problemas.append(("gateway", "nao consegui perguntar ao contentor: %s" % str(e)[:80]))

    abertas = D._rest("despacho?estado=eq.aberta&para=neq.agente-segunda&created_at=lt.%s&select=id&limit=5" % iso(2400))
    presas = D._rest("despacho?estado=eq.executando&para=neq.agente-segunda&iniciada_em=lt.%s&select=id&limit=5" % iso(1800))
    if abertas is None or presas is None:
        problemas.append(("base", "a base de dados nao respondeu ao batimento"))
    elif abertas or presas:
        problemas.append(("fila", "a fila do despacho esta parada: %d aberta(s) ha mais de 40 min, %d presa(s) a executar"
                          % (len(abertas), len(presas))))

    vigia = D._rest("sentinela_estado?select=*&limit=1")
    if vigia is None:
        estado_vigia = "por aplicar"           # a tabela ainda nao existe na base
        mem["vigia_ok_seguidos"] = 0
    else:
        linha = vigia[0] if vigia else {}
        ultima = next((v for k, v in linha.items() if "varredura" in k and v), None)
        fresco = bool(ultima) and str(ultima)[:19] >= iso(300)[:19]
        estado_vigia = "vivo" if fresco else "parado"
        mem["vigia_ok_seguidos"] = mem.get("vigia_ok_seguidos", 0) + 1 if fresco else 0
        if not fresco:
            problemas.append(("vigia", "o vigia por eventos nao corre ha mais de 5 minutos"))

    linha_log = "%s gateway=%s fila=%s vigia=%s problemas=%d" % (
        iso(0), "ok" if not any(p[0] == "gateway" for p in problemas) else "FALHA",
        "ok" if not any(p[0] in ("fila", "base") for p in problemas) else "FALHA", estado_vigia, len(problemas))
    print(linha_log)
    if ENSAIO:
        for p in problemas:
            print("  (ensaio) avisaria:", p[1])
        return 0

    for chave, texto in problemas:
        feito = None
        if estado_vigia != "por aplicar":
            feito = D._rest("rpc/sentinela_registar", "POST", {"p_tipo": "sistema", "p_gravidade": "urgente",
                            "p_chave": "batimento:" + chave, "p_titulo": "Batimento: " + texto, "p_dados": {"origem": "batimento_torre"}})
        if feito is None and mem.get("ultimo_aviso_" + chave, 0) < time.time() - 3600:
            try:
                porteiro("Precisas de ti: " + texto + ".")
                mem["ultimo_aviso_" + chave] = time.time()
            except Exception:
                pass

    # a torre passa a 1 resumo por dia quando o vigia por eventos ja provou que esta vivo
    if mem.get("vigia_ok_seguidos", 0) >= 2 and not mem.get("torre_trocada"):
        t = D._rest("agentes_estado?agente=eq.torre&select=cadencia_min")
        if t and t[0].get("cadencia_min") == 60:
            D._rest("agentes_estado?agente=eq.torre", "PATCH", {"cadencia_min": 1440})
            D._rest("e2e_log", "POST", {"fluxo": "hermes-diretor-2026-11-20", "passo": "B3-torre-por-eventos", "estado": "ok",
                                        "device": "vps-batimento",
                                        "detalhe": "O vigia por eventos esteve vivo em 2 batimentos seguidos: a ronda de IA da torre passou de hora a hora para 1 vez por dia (cadencia_min 60 -> 1440). O batimento sem IA continua de hora a hora."})
        mem["torre_trocada"] = True
    json.dump(mem, open(ESTADO, "w"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
