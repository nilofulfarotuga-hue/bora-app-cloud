"""Acesso ao Supabase (REST + RPC) com a service role. So biblioteca padrao."""
import json
import os
import urllib.error
import urllib.parse
import urllib.request


def _base():
    return os.environ["SUPABASE_URL"].rstrip("/")


def _h(extra=None):
    k = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    h = {"apikey": k, "Authorization": "Bearer " + k, "Content-Type": "application/json"}
    if extra:
        h.update(extra)
    return h


class ErroDB(Exception):
    pass


def _pedir(metodo, caminho, corpo=None, extra=None, timeout=20):
    url = _base() + caminho
    data = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(url, data, _h(extra), method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        raise ErroDB(f"{metodo} {caminho.split('?')[0]} -> {e.code} {e.read().decode(errors='ignore')[:300]}")


def rpc(nome, args):
    return _pedir("POST", f"/rest/v1/rpc/{nome}", args)


def ler(tabela, filtros="", seleciona="*"):
    q = f"/rest/v1/{tabela}?select={urllib.parse.quote(seleciona, safe='*,()!:.')}"
    if filtros:
        q += "&" + filtros
    return _pedir("GET", q) or []


def inserir(tabela, linha, devolver=True):
    extra = {"Prefer": "return=representation" if devolver else "return=minimal"}
    r = _pedir("POST", f"/rest/v1/{tabela}", linha, extra)
    return r[0] if devolver and r else None


def upsert(tabela, linha, chave):
    extra = {"Prefer": "return=representation,resolution=merge-duplicates"}
    r = _pedir("POST", f"/rest/v1/{tabela}?on_conflict={chave}", linha, extra)
    return r[0] if r else None


def atualizar(tabela, filtros, campos):
    extra = {"Prefer": "return=representation"}
    return _pedir("PATCH", f"/rest/v1/{tabela}?{filtros}", campos, extra) or []


def q(v):
    """Valor seguro para filtros PostgREST."""
    return urllib.parse.quote(str(v), safe="")
