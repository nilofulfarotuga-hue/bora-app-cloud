#!/usr/bin/env python3
"""Cliente de gestao do OmniRoute (missao omniroute-23-10).

Uso:  or_admin.py METODO /api/caminho [json-do-corpo | @ficheiro.json]
Entra com a palavra-passe do /opt/omniroute/.env (nunca a imprime), guarda o cookie
em /root/.omniroute-cookie (0600) e imprime a resposta com segredos tapados.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("OR_BASE", "http://127.0.0.1:20128")
COOKIE = "/root/.omniroute-cookie"
SEGREDO = re.compile(r'("(?:apiKey|api_key|key|token|secret|password|accessToken|refreshToken|rawKey)"\s*:\s*")([^"]{6})[^"]*(")', re.I)


def ler_env(path="/opt/omniroute/.env"):
    env = {}
    for linha in open(path, encoding="utf-8"):
        linha = linha.strip()
        if linha and not linha.startswith("#") and "=" in linha:
            k, v = linha.split("=", 1)
            env[k] = v
    return env


def pedir(metodo, caminho, corpo=None, cookie=None):
    dados = None if corpo is None else json.dumps(corpo).encode()
    req = urllib.request.Request(BASE + caminho, data=dados, method=metodo)
    req.add_header("Content-Type", "application/json")
    if cookie:
        req.add_header("Cookie", cookie)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read().decode("utf-8", "replace"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers


def entrar():
    senha = os.environ.get("OR_PASS") or ler_env().get("INITIAL_PASSWORD")
    st, txt, hd = pedir("POST", "/api/auth/login", {"password": senha})
    if st != 200:
        print(f"LOGIN FALHOU {st}: {txt[:300]}", file=sys.stderr)
        sys.exit(2)
    cookies = [c.split(";", 1)[0] for c in hd.get_all("Set-Cookie") or []]
    ck = "; ".join(cookies)
    fd = os.open(COOKIE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, ck.encode())
    os.close(fd)
    return ck


def main():
    metodo, caminho = sys.argv[1].upper(), sys.argv[2]
    corpo = None
    if len(sys.argv) > 3:
        a = sys.argv[3]
        corpo = json.load(open(a[1:], encoding="utf-8")) if a.startswith("@") else json.loads(a)
    ck = open(COOKIE).read().strip() if os.path.exists(COOKIE) else entrar()
    st, txt, _ = pedir(metodo, caminho, corpo, ck)
    if st in (401, 403):
        ck = entrar()
        st, txt, _ = pedir(metodo, caminho, corpo, ck)
    mostrar = os.environ.get("OR_RAW") != "1"
    print(st)
    print(SEGREDO.sub(r"\1\2…\3", txt) if mostrar else txt)


if __name__ == "__main__":
    main()
