# -*- coding: utf-8 -*-
"""Perfis "so Claude" para o OmniRoute (31/10/2026, depois da prova do Hermes).
O OmniRoute tem a sua propria cadeia gratis atras do Motor; se o Motor tentar a cauda gratis dele antes de
falhar, o Hermes (pedidos grandes e [PRIVADO]) espera ~87 s. Com claude-so-* o Motor so tenta o Claude pelo
porteiro e, sem credito/chave, responde 503 logo -> o OmniRoute desce na hora.
Correr na VPS como root com /tmp/porteiro.py novo:  python3 patch_porteiro_so_claude_20261031.py
"""
import os
import py_compile
import shutil

CAT = "/opt/motor-bora/motor_bora/catalogo.py"
POR = "/opt/motor-bora/motor_bora/porteiro.py"
COMBOS = "/opt/omniroute/or_combos.py"
SUF = ".bak-soclaude-20261031"
for p in (CAT, POR, COMBOS):
    if not os.path.exists(p + SUF):
        shutil.copy2(p, p + SUF)
shutil.copy2("/tmp/porteiro.py", POR)
t = open(CAT, encoding="utf-8").read()
if "claude-so-decisao" not in t:
    t += '''PERFIS["claude-so-decisao"] = dict(PERFIS["raciocinio"], modo="cadeia", candidatos=[])   # so o porteiro (OmniRoute)
PERFIS["claude-so-volume"] = dict(PERFIS["volume"], modo="cadeia", candidatos=[])         # so o porteiro (OmniRoute)
'''
    open(CAT, "w", encoding="utf-8").write(t)
c = open(COMBOS, encoding="utf-8").read()
c2 = c.replace('MOTOR + "perfil:claude-decisao",', 'MOTOR + "perfil:claude-so-decisao",').replace('MOTOR + "perfil:claude-volume",', 'MOTOR + "perfil:claude-so-volume",')
if c2 != c:
    st = os.stat(COMBOS)
    open(COMBOS, "w", encoding="utf-8").write(c2)
    os.chown(COMBOS, st.st_uid, st.st_gid)
for p in (CAT, POR, COMBOS):
    py_compile.compile(p, doraise=True)
print("perfis claude-so-* criados; combos do OmniRoute apontam para eles; py_compile OK")
