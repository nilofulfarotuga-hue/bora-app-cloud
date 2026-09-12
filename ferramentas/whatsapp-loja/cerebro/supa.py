# -*- coding: utf-8 -*-
"""supa.py — acesso ao Supabase pelo cerebro (service_role). So corre no PC e na VPS, nunca no browser.

A chave vem do backend/.env do bora_app (PC) ou de um .env ao lado (VPS). Nunca se imprime.
Tudo passa pelo REST do PostgREST: select/insert/upsert/update/rpc, com 20 s de espera.
"""
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

_AQUI = os.path.dirname(os.path.abspath(__file__))
ENV_PATHS = [
    os.path.join(_AQUI, ".env"),
    os.path.join(_AQUI, "..", ".env"),
    r"C:\BoraLocal\projetosflutter\bora_app\backend\.env",
    "/opt/whatsapp-bora/.env",
]


def _ler_env():
    d = {}
    for p in ENV_PATHS:
        if not os.path.exists(p):
            continue
        for ln in open(p, encoding="utf-8", errors="replace"):
            m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*(.*)$", ln.strip())
            if m and m.group(1) not in d:
                d[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return d


ENV = _ler_env()
URL = (ENV.get("SUPABASE_URL") or "").rstrip("/")
KEY = ENV.get("SUPABASE_SERVICE_ROLE_KEY") or ""
PROJECT = "ojykpzwqrtusfeakzrna"


class SupaErro(Exception):
    pass


def _req(method, path, body=None, params=None, prefer=None, timeout=20):
    if not URL or not KEY:
        raise SupaErro("sem SUPABASE_URL/SERVICE_ROLE no .env")
    q = ("?" + urllib.parse.urlencode(params, safe="*.,()")) if params else ""
    cab = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
    if prefer:
        cab["Prefer"] = prefer
    elif method in ("POST", "PATCH"):
        cab["Prefer"] = "return=representation"
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = urllib.request.Request(URL + "/rest/v1/" + path + q, data=data, method=method, headers=cab)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        raise SupaErro("HTTP %s em %s %s: %s" % (e.code, method, path, e.read()[:300].decode("utf-8", "replace")))
    return json.loads(raw) if raw else None


def select(tabela, **params):
    return _req("GET", tabela, params=params) or []


def um(tabela, **params):
    params.setdefault("limit", "1")
    r = select(tabela, **params)
    return r[0] if r else None


def insert(tabela, linha, devolve=True):
    return _req("POST", tabela, body=linha, prefer="return=representation" if devolve else "return=minimal")


def upsert(tabela, linha, on_conflict):
    return _req("POST", tabela, body=linha, params={"on_conflict": on_conflict},
                prefer="resolution=merge-duplicates,return=representation")


def update(tabela, patch, **filtros):
    return _req("PATCH", tabela, body=patch, params=filtros)


def upsert_muitos(tabela, linhas, on_conflict, ignorar_duplicados=True):
    """Muitas linhas numa chamada so. O censo inseria uma a uma (200 chamadas por conversa -- minutos)."""
    if not linhas:
        return []
    pref = "resolution=ignore-duplicates,return=minimal" if ignorar_duplicados else "resolution=merge-duplicates,return=minimal"
    return _req("POST", tabela, body=linhas, params={"on_conflict": on_conflict}, prefer=pref, timeout=40)


def rpc(fn, args=None):
    return _req("POST", "rpc/" + fn, body=args or {}, prefer="")


def vivo():
    try:
        select("whatsapp_settings", select="key", limit="1")
        return True
    except Exception:
        return False


def definicao(key, por_defeito=None):
    try:
        r = um("whatsapp_settings", select="value", key="eq." + key)
        return r["value"] if r else por_defeito
    except Exception:
        return por_defeito


def definir(key, value):
    return upsert("whatsapp_settings", {"key": key, "value": value}, "key")


if __name__ == "__main__":
    print("supabase vivo:", vivo(), "| envio_ligado:", definicao("envio_ligado"))
