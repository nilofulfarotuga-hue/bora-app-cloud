# -*- coding: utf-8 -*-
"""Cerebro do WhatsApp da Bora (31/10/2026), dois erros vistos na prova do suporte:
1) 'oi' a meio da conversa caia no _retomar_fio, que NAO cumprimentava ("Diga-me o que precisa: ...").
   Regra do Danilo 31/10: cumprimento recebe cumprimento e "em que posso ajudar?".
2) RE_URGENTE tinha \\bfrio\\b solto: "hoje esta um frio" virava URGENCIA ("isto nao pode esperar, ligue-nos").
   Passa a exigir comida/pedido frio ("chegou frio", "a pizza veio fria", "comida fria").
Copia .bak-cumprimento-20261031 ao lado. --repor repoe.
"""
import os
import py_compile
import shutil
import sys

AG = "/opt/whatsapp-bora/cerebro/agente.py"
SUF = ".bak-cumprimento-20261031"
if "--repor" in sys.argv:
    shutil.copy2(AG + SUF, AG)
    print("reposto")
    sys.exit(0)
if not os.path.exists(AG + SUF):
    shutil.copy2(AG, AG + SUF)
t = open(AG, encoding="utf-8").read()
mud = 0
pares = [
    ("""        return ('Diga. Da última vez falou-me de "%s" — quer continuar por aí, ou hoje é outra coisa?' % ultimo)""",
     """        return ('Olá! Da última vez falou-me de "%s" — quer continuar por aí, ou em que posso ajudar hoje?' % ultimo)"""),
    ("""    return ("Diga-me o que precisa: comida ou compras entregues em casa, farmácia, limpeza, "
            "ou o horário de uma loja.")""",
     """    return ("Olá! Em que posso ajudar? Pode ser comida ou compras entregues em casa, farmácia, limpeza, "
            "ou o horário de uma loja.")"""),
    ("|chegou frio|\\bfrio\\b|", "|chegou frio|(?:comida|pedido|encomenda|hamb\\w*|pizza|batatas?|sopa)\\s+(?:est[aá]\\s+|veio\\s+|chegou\\s+)?fri[oa]\\b|veio fri[oa]\\b|"),
]
for velho, novo in pares:
    if t.count(velho) == 1:
        t = t.replace(velho, novo)
        mud += 1
    elif novo in t:
        pass
    else:
        raise SystemExit("ancora nao encontrada: " + velho[:60])
with open(AG + ".tmp", "w", encoding="utf-8") as fh:
    fh.write(t)
py_compile.compile(AG + ".tmp", doraise=True)
os.replace(AG + ".tmp", AG)
import re  # noqa: E402
ns = {}
exec(compile("import re\n" + [ln for ln in t.splitlines() if ln.startswith("RE_URGENTE")][0], "x", "exec"), ns)
for frase, esperado in (("hoje está um frio", False), ("a pizza chegou fria", True), ("chegou frio", True), ("a comida veio fria", True), ("que frio lá fora", False)):
    print("RE_URGENTE %-22r -> %s (esperado %s)" % (frase, bool(ns["RE_URGENTE"].search(frase)), esperado))
print("mudancas:", mud, "py_compile OK")
