#!/usr/bin/env python3
"""Verificador da skill identidade-estafeta.

Falha (exit 2) se, numa cadeia Supabase sobre uma TABELA DE PAPEL
(drivers, cleaners, washers, restaurants), aparecer:
  * .eq('id', <variável de auth uid>)
  * onConflict: 'id'  /  on_conflict=id

Uso:
  python verificar.py [pasta ou ficheiro ...] [--json]
Sem argumentos varre lib/ a partir da raiz do repo (sobe até encontrar pubspec.yaml).

Excepção declarada na própria linha:  // identidade: id-ok <motivo>
"""
from __future__ import annotations

import io
import json
import os
import re
import sys

# Windows PT: a consola vem em cp1252 e engasga com acentos — força UTF-8 (renderer-safe).
try:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover
    pass

TABELAS_DE_PAPEL = ("drivers", "cleaners", "washers", "restaurants")

# Nomes que, por convenção do repo, carregam o auth uid (auth.users.id).
NOMES_UID = (
    r"uid", r"_uid", r"userId", r"user\.id", r"user!\.id", r"authUser\.id", r"authUserId",
    r"currentUser\??!?\.id", r"auth\.uid", r"driverId", r"_primaryDriverId",
    r"currentDriverId", r"myId", r"cleanerId", r"washerId", r"partnerUserId",
)
RE_EQ_ID = re.compile(
    r"\.eq\(\s*['\"]id['\"]\s*,\s*(?:" + "|".join(NOMES_UID) + r")\s*\)"
)
RE_ONCONFLICT_ID = re.compile(r"onConflict\s*:\s*['\"]id['\"]|on_conflict=id\b")
RE_FROM_PAPEL = re.compile(r"\.from\(\s*['\"](" + "|".join(TABELAS_DE_PAPEL) + r")['\"]\s*\)")
RE_FROM_QUALQUER = re.compile(r"\.from\(\s*['\"]([a-zA-Z0-9_]+)['\"]\s*\)")
RE_EXCEPCAO = re.compile(r"//\s*identidade:\s*id-ok")

JANELA = 20  # linhas: distância máxima entre o .from('drivers') e o .eq/onConflict (um upsert com payload de 10 campos passa dos 12)


def raiz_do_repo(inicio: str) -> str:
    d = os.path.abspath(inicio)
    while True:
        if os.path.exists(os.path.join(d, "pubspec.yaml")):
            return d
        pai = os.path.dirname(d)
        if pai == d:
            return os.path.abspath(inicio)
        d = pai


def ficheiros_dart(alvos: list[str]) -> list[str]:
    out: list[str] = []
    for a in alvos:
        if os.path.isfile(a) and a.endswith(".dart"):
            out.append(a)
            continue
        for base, _dirs, files in os.walk(a):
            for f in files:
                if f.endswith(".dart"):
                    out.append(os.path.join(base, f))
    return sorted(set(out))


def verificar_ficheiro(path: str) -> list[dict]:
    achados: list[dict] = []
    try:
        linhas = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError as e:  # pragma: no cover
        return [{"ficheiro": path, "linha": 0, "tipo": "erro-leitura", "texto": str(e)}]

    tabela_actual: str | None = None
    linha_from = -10_000
    for i, linha in enumerate(linhas, start=1):
        m_from = RE_FROM_QUALQUER.search(linha)
        if m_from:
            # Qualquer .from(...) fecha a janela anterior; só as tabelas de papel abrem uma nova.
            tabela_actual = m_from.group(1) if RE_FROM_PAPEL.search(linha) else None
            linha_from = i
        if tabela_actual is None or i - linha_from > JANELA:
            continue
        if RE_EXCEPCAO.search(linha):
            continue
        # Comentário não é código (lição da Trava, 16/09): não se julga texto.
        if linha.strip().startswith("//"):
            continue
        if RE_EQ_ID.search(linha):
            achados.append({
                "ficheiro": path, "linha": i, "tabela": tabela_actual,
                "tipo": "eq-id-com-auth-uid", "texto": linha.strip(),
                "correccao": ".eq('user_id', uid)  (ou .or('user_id.eq.$id,id.eq.$id') se o id vem de um pedido)",
            })
        if RE_ONCONFLICT_ID.search(linha):
            achados.append({
                "ficheiro": path, "linha": i, "tabela": tabela_actual,
                "tipo": "on-conflict-id", "texto": linha.strip(),
                "correccao": "onConflict: 'user_id'",
            })
    return achados


def main(argv: list[str]) -> int:
    como_json = "--json" in argv
    alvos = [a for a in argv if not a.startswith("--")]
    if not alvos:
        alvos = [os.path.join(raiz_do_repo(os.getcwd()), "lib")]
    ficheiros = ficheiros_dart(alvos)
    achados: list[dict] = []
    for f in ficheiros:
        achados.extend(verificar_ficheiro(f))

    if como_json:
        print(json.dumps({"ficheiros": len(ficheiros), "achados": achados}, ensure_ascii=False, indent=2))
    else:
        print(f"identidade-estafeta: {len(ficheiros)} ficheiro(s) Dart verificados")
        for a in achados:
            print(f"  [X] {a['ficheiro']}:{a['linha']} [{a['tabela']}] {a['tipo']}: {a['texto']}")
            print(f"      → {a['correccao']}")
        if not achados:
            print("  [OK] nenhuma escrita/leitura de papel por drivers.id com auth uid; nenhum onConflict:'id'")
    return 2 if achados else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
