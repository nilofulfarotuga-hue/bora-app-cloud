#!/usr/bin/env python3
# Missao m6 08/11: a resposta de um negocio pode trazer quebras de linha; no retrato fica numa linha so.
import sys

p = sys.argv[1]
s = open(p, encoding="ascii").read()
velho = '(x.get("nome"), x.get("estado"), (x.get("resposta") or "")[:80])'
novo = '(x.get("nome"), x.get("estado"), " ".join((x.get("resposta") or "").split())[:80])'
if novo in s:
    print("ja estava")
elif s.count(velho) == 1:
    open(p, "w", encoding="ascii").write(s.replace(velho, novo))
    print("ok")
else:
    raise SystemExit("ANCORA NAO ENCONTRADA")
