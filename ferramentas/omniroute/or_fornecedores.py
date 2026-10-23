#!/usr/bin/env python3
"""Bloco 2 (omniroute-23-10): liga ao OmniRoute so fornecedores por CHAVE DE API.

Le as chaves dos .env que ja existem na VPS (nunca as imprime; so tamanho e 8 chars de sha256),
tira duplicados pelo valor e cria uma ligacao por chave. Nada de contas por login, cookies ou
revendedores. Corre no host, como root.
"""
import hashlib
import json
import subprocess
import sys

ENVS = ["/opt/data/.env", "/opt/motor-bora/.env", "/opt/whatsapp-bora/.env"]


def ler(path):
    out = {}
    try:
        for linha in open(path, encoding="utf-8"):
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                k, v = linha.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return out


ENV = {p: ler(p) for p in ENVS}


def chaves(*nomes):
    vistos, res = set(), []
    for p in ENVS:
        for n in nomes:
            v = ENV[p].get(n, "")
            if v and v not in vistos:
                vistos.add(v)
                res.append((n, p, v))
    return res


def admin(metodo, caminho, corpo=None):
    args = ["python3", "/opt/omniroute/or_admin.py", metodo, caminho]
    if corpo is not None:
        args.append(json.dumps(corpo))
    r = subprocess.run(args, capture_output=True, text=True, env={"OR_RAW": "1", "PATH": "/usr/bin:/bin"})
    linhas = r.stdout.split("\n", 1)
    st = int(linhas[0]) if linhas[0].strip().isdigit() else 0
    try:
        return st, json.loads(linhas[1]) if len(linhas) > 1 and linhas[1].strip() else {}
    except json.JSONDecodeError:
        return st, {"_texto": linhas[1][:300] if len(linhas) > 1 else r.stderr[:300]}


PLANO = [
    # (provider id no OmniRoute, nome base, variaveis de chave, dados extra)
    ("opencode-go", "opencode-go", ["OPENCODE_GO_KEY", "OPENCODE_GO_API_KEY"], None),
    ("opencode-zen", "opencode-zen", ["OPENCODE_ZEN_API_KEY"], None),
    ("gemini", "gemini", ["GEMINI_API_KEY", "GOOGLE_API_KEY"], None),
    ("groq", "groq", ["GROQ_API_KEY"], None),
    ("cerebras", "cerebras", ["CEREBRAS_API_KEY"], None),
    ("openrouter", "openrouter", ["OPENROUTER_API_KEY"], None),
    ("nvidia", "nvidia", ["NVIDIA_API_KEY"], None),
    ("cloudflare-ai", "cloudflare", ["CLOUDFLARE_API_TOKEN"], "cf"),
]


def main():
    st, atuais = admin("GET", "/api/providers")
    ja = {(c.get("provider"), c.get("name")) for c in atuais.get("connections", [])}
    criadas = []
    for prov, base, nomes, extra in PLANO:
        lista = chaves(*nomes)
        if not lista:
            print(f"{prov}: SEM CHAVE em nenhum .env — fica de fora")
            continue
        for i, (n, p, v) in enumerate(lista, 1):
            nome = f"{base}-{i}"
            sha = hashlib.sha256(v.encode()).hexdigest()[:8]
            if (prov, nome) in ja:
                print(f"{prov}/{nome}: ja existia — nao mexi")
                continue
            corpo = {"provider": prov, "name": nome, "apiKey": v, "priority": i}
            if extra == "cf":
                acc = next((ENV[q].get("CLOUDFLARE_ACCOUNT_ID") for q in ENVS if ENV[q].get("CLOUDFLARE_ACCOUNT_ID")), "")
                corpo["providerSpecificData"] = {"accountId": acc}
            st, r = admin("POST", "/api/providers", corpo)
            cid = (r.get("connection") or {}).get("id") or r.get("id")
            print(f"{prov}/{nome}: POST {st} id={cid} chave={n}@{p} len={len(v)} sha={sha}"
                  + ("" if st in (200, 201) else f" erro={json.dumps(r)[:240]}"))
            if cid:
                criadas.append(cid)
    print(json.dumps({"criadas": criadas}))


if __name__ == "__main__":
    main()
