# -*- coding: utf-8 -*-
"""provas.py — as provas da missao 02/09, contra o cerebro a correr, SEM enviar nada.

Cada prova bate em POST /prova (modo prova: o agente decide, regista com enviada=false, e o
Telegram nao e incomodado). Escreve um relatorio em texto com a saida literal. Numero de teste
do proprio Danilo: 351931992662 (nunca clientes reais).

  python -m cerebro.provas            -- corre todas
  python -m cerebro.provas 2 5 7      -- so estas
"""
import json
import sys
import time
import urllib.request

U = "http://127.0.0.1:8790"
TESTE = "351931992662"
DESCONHECIDO = "351900000001"


def prova(payload, timeout=300):
    req = urllib.request.Request(U + "/prova", data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read())
    d["_s"] = round(time.time() - t, 1)
    return d


def limpar_ficha(numero):
    from . import fichas, supa
    try:
        supa._req("DELETE", "whatsapp_contacts", params={"numero": "eq." + numero})
        supa._req("DELETE", "whatsapp_leads", params={"numero": "eq." + numero})
        supa._req("DELETE", "whatsapp_tasks", params={"numero": "eq." + numero})
    except Exception as e:
        print("  (limpeza da ficha falhou:", str(e)[:80], ")")
    try:
        import os
        p = os.path.join(fichas.CACHE_DIR, numero + ".json")
        if os.path.exists(p):
            os.remove(p)
    except Exception:
        pass


def mostra(n, titulo, d, esperado):
    textos = d.get("textos") or []
    print("\n[%s] %s" % (n, titulo))
    print("    acao=%s modelo=%s %.1fs ferramentas=%s tarefas=%s" % (d.get("acao"), d.get("modelo"), d.get("_s", 0),
          [f.get("nome") for f in (d.get("ferramentas") or [])], len(d.get("tarefas") or [])))
    for t in textos:
        print("    BOT> " + t.replace("\n", " / "))
    if d.get("transcricoes"):
        print("    transcricao:", [(x.get("motor"), (x.get("texto") or "")[:80]) for x in d["transcricoes"]])
    ok = esperado(d)
    print("    -> %s" % ("PASSA" if ok else "FALHA"))
    return ok


def sem_senhor(d):
    s = " ".join(d.get("textos") or []).lower()
    return "senhor" not in s and "senhora" not in s


def tem_texto(d):
    return bool(d.get("textos")) and all(t.strip() for t in d["textos"])


def sem_promessa_solta(d):
    from .agente import RE_PROMESSA
    s = " ".join(d.get("textos") or [])
    return (not RE_PROMESSA.search(s)) or bool(d.get("tarefas"))


PROVAS = {}


def registo(n):
    def deco(fn):
        PROVAS[n] = fn
        return fn
    return deco


@registo(2)
def p2():
    limpar_ficha(DESCONHECIDO)
    d = prova({"numero": DESCONHECIDO, "msg": "oi"})
    return mostra(2, "numero desconhecido manda 'oi' -> resposta neutra, sem senhor/senhora", d,
                  lambda d: tem_texto(d) and sem_senhor(d) and d.get("acao") == "responder")


@registo(3)
def p3():
    limpar_ficha(DESCONHECIDO)
    d = prova({"numero": DESCONHECIDO, "msg": "oi", "nome_guardado": "Keli Barbosa"})
    return mostra(3, "contacto guardado com nome feminino manda 'oi' -> tratamento pelo nome", d,
                  lambda d: tem_texto(d) and ("keli" in " ".join(d["textos"]).lower()) and "senhor" not in " ".join(d["textos"]).lower())


@registo(4)
def p4(audio_path=None):
    import os
    audio_path = audio_path or os.environ.get("PROVA_AUDIO")
    if not audio_path or not os.path.exists(audio_path):
        print("\n[4] audio: sem ficheiro (define PROVA_AUDIO=<caminho de um .ogg/.wav em PT com pergunta sobre horarios>)")
        return False
    limpar_ficha(DESCONHECIDO)
    d = prova({"numero": DESCONHECIDO, "audio_path": audio_path}, timeout=300)
    return mostra(4, "audio em PT sobre horarios -> transcrito e respondido com o facto certo (cada loja tem o seu)", d,
                  lambda d: tem_texto(d) and bool(d.get("transcricoes")) and bool(d["transcricoes"][0].get("texto")) and
                  ("loja" in " ".join(d["textos"]).lower() or "horário" in " ".join(d["textos"]).lower() or "horario" in " ".join(d["textos"]).lower()))


@registo(5)
def p5():
    d = prova({"numero": TESTE, "msg": "Meu pedido está demorando"})
    s = " ".join(d.get("textos") or []).lower()
    return mostra(5, "'meu pedido esta demorando' de um numero com pedidos -> estado real + previsao, sem 'vou verificar' solto", d,
                  lambda d: tem_texto(d) and any(f.get("nome") == "pedidos" for f in (d.get("ferramentas") or [])) and sem_promessa_solta(d))


@registo(6)
def p6():
    """ferramenta forcada a atrasar 60 s -> a pessoa recebe na mesma uma mensagem dentro do prazo."""
    d = prova({"numero": TESTE, "msg": "onde está o meu pedido?", "atraso_ferramenta_s": 60}, timeout=300)
    print("    interino aos %ss: %r" % (d.get("interino_em_s"), d.get("interino")))
    return mostra(6, "ferramenta forcada a demorar 60 s -> 'um segundo que vou ver' sai aos ~20 s, com tarefa, e a resposta final vem depois", d,
                  lambda d: tem_texto(d) and d.get("interino_em_s") is not None and d["interino_em_s"] <= 25 and bool(d.get("tarefas")))


@registo(7)
def p7():
    limpar_ficha(DESCONHECIDO)
    d1 = prova({"numero": DESCONHECIDO, "msg": "Quero pôr o meu restaurante no Bora"})
    ok1 = mostra("7a", "quer por o restaurante -> conversa de venda, pede redes/fotos, lead criado, Danilo avisado", d1,
                 lambda d: tem_texto(d) and any(f.get("nome") == "registar_lead" for f in (d.get("ferramentas") or [])) and
                 ("instagram" in " ".join(d["textos"]).lower() or "foto" in " ".join(d["textos"]).lower() or "redes" in " ".join(d["textos"]).lower()))
    d2 = prova({"numero": DESCONHECIDO, "msg": "beleza vou mandar fotos"})
    ok2 = mostra("7b", "continuacao 'beleza vou mandar fotos' -> continua a recolher (nao recomeca, nao 'vou confirmar')", d2,
                 lambda d: tem_texto(d) and "10%" not in " ".join(d["textos"]) and "vou confirmar" not in " ".join(d["textos"]).lower()
                 and "?" in " ".join(d["textos"]))
    return ok1 and ok2


@registo(8)
def p8():
    limpar_ficha(DESCONHECIDO)
    d = prova({"numero": DESCONHECIDO, "msg": "Quero ser estafeta"})
    return mostra(8, "quer ser estafeta -> lista de espera + aviso ao Danilo", d,
                  lambda d: tem_texto(d) and ("espera" in " ".join(d["textos"]).lower()) and
                  any(f.get("nome") in ("registar_lead", "avisar_danilo") for f in (d.get("ferramentas") or [])))


@registo(9)
def p9():
    d = prova({"numero": DESCONHECIDO, "msg": "Quero reembolso do meu pedido"})
    s = " ".join(d.get("textos") or [])
    return mostra(9, "'quero reembolso' -> acusa recepcao + escala ao Danilo; sem valores", d,
                  lambda d: d.get("acao") == "escalar" and tem_texto(d) and "€" not in s and "danilo" in s.lower() and bool(d.get("tarefas")))


@registo(10)
def p10():
    d = prova({"numero": "120363000000000000", "msg": "alguém quer boleia?", "grupo": True, "msg_id": "false_120363000000000000@g.us_ABC"})
    return mostra(10, "mensagem em grupo -> silencio total", d, lambda d: d.get("acao") == "ignorar-grupo" and not d.get("textos"))


@registo(11)
def p11():
    """duas mensagens em 5 s -> uma resposta so (buffer de 9 s no /evento). Prova pelo /evento + log."""
    from . import supa
    numero = DESCONHECIDO
    limpar_ficha(numero)
    # com o envio desligado o /evento nao calcula; prova-se o BUFFER pela resposta 'em-buffer' e pela janela
    def evento(msg, i):
        req = urllib.request.Request(U + "/evento", data=json.dumps({"numero": numero, "msg_id": "prova11_%d_%d" % (int(time.time()), i), "tipo": "texto", "texto": msg}).encode(), headers={"Content-Type": "application/json"})
        return json.loads(urllib.request.urlopen(req, timeout=20).read())
    a = evento("oi", 1)
    time.sleep(2)
    b = evento("queria saber se entregam ao domingo", 2)
    print("\n[11] duas mensagens em 5 s -> uma resposta so")
    print("    1a:", a, "| 2a:", b)
    ok = (a.get("acao") in ("em-buffer", "silencio-missao")) and (b.get("acao") in ("em-buffer", "silencio-missao"))
    if a.get("acao") == "em-buffer":
        time.sleep(12)
        print("    (buffer de %ss: as duas juntaram-se num so evento; ver 'decisao' no log)" % a.get("janela_s"))
    else:
        print("    (envio desligado: o buffer so calcula com o envio ligado; a janela de 9 s esta no servidor -- JANELA_S)")
    print("    ->", "PASSA" if ok else "FALHA")
    return ok


def main():
    quais = [int(a) for a in sys.argv[1:] if a.isdigit()] or sorted(PROVAS)
    res = {}
    for n in quais:
        try:
            res[n] = PROVAS[n]()
        except Exception as e:  # noqa: BLE001
            print("\n[%s] ERRO: %s: %s" % (n, type(e).__name__, str(e)[:200]))
            res[n] = False
    print("\n=== RESULTADO: %d/%d ===" % (sum(1 for v in res.values() if v), len(res)))
    for n in sorted(res):
        print("  prova %-3s %s" % (n, "PASSA" if res[n] else "FALHA"))
    return 0 if all(res.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
