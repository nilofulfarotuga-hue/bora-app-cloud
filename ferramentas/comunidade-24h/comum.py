"""Peças comuns do gestor de comunidade 24h (corre na VPS, dentro do contentor do Hermes).

Só biblioteca padrão. Segredos vêm do cofre (ficheiros 600 em /opt/data/cofre) ou do
ambiente; nunca do repositório.
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

COFRE = os.environ.get("COMUNIDADE_COFRE", "/opt/data/cofre")
CONTAS = os.environ.get("COMUNIDADE_CONTAS", "/opt/data/missoes/comunidade-contas.json")
LOG = os.environ.get("COMUNIDADE_LOG", "/opt/data/missoes/comunidade.log.jsonl")


def agora():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def registo(evento, **campos):
    linha = {"quando": agora(), "evento": evento, **campos}
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(linha, ensure_ascii=False) + "\n")


def ler_cofre(nome):
    with open(os.path.join(COFRE, nome), encoding="utf-8") as f:
        return json.load(f)


def gravar_cofre(nome, dados):
    caminho = os.path.join(COFRE, nome)
    os.makedirs(os.path.dirname(caminho), mode=0o700, exist_ok=True)
    tmp = caminho + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dados, f)
    os.replace(tmp, caminho)


def contas():
    with open(CONTAS, encoding="utf-8") as f:
        return json.load(f)["contas"]


def http(metodo, url, dados=None, cabecalhos=None, forma="json", tentativas=3):
    """Pedido HTTP. Devolve (codigo, corpo_json_ou_texto). Nunca levanta por 4xx."""
    cab = dict(cabecalhos or {})
    corpo = None
    if dados is not None:
        if forma == "json":
            corpo = json.dumps(dados).encode()
            cab.setdefault("Content-Type", "application/json")
        else:
            corpo = urllib.parse.urlencode(dados).encode()
            cab.setdefault("Content-Type", "application/x-www-form-urlencoded")
    for i in range(tentativas):
        req = urllib.request.Request(url, data=corpo, headers=cab, method=metodo)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                txt = r.read().decode("utf-8", "replace")
                codigo = r.status
        except urllib.error.HTTPError as e:
            txt = e.read().decode("utf-8", "replace")
            codigo = e.code
        except (urllib.error.URLError, TimeoutError) as e:
            if i == tentativas - 1:
                return 0, str(e)
            time.sleep(2 * (i + 1))
            continue
        if codigo >= 500 and i < tentativas - 1:
            time.sleep(2 * (i + 1))
            continue
        try:
            return codigo, json.loads(txt) if txt else {}
        except json.JSONDecodeError:
            return codigo, txt
    return 0, "sem resposta"


# ---------- Supabase (chave de serviço no cofre: supabase.json {url, service_key}) ----------

def _sb():
    c = ler_cofre("supabase.json")
    return c["url"].rstrip("/"), {"apikey": c["service_key"], "Authorization": "Bearer " + c["service_key"]}


def sb_get(tabela, consulta):
    url, cab = _sb()
    return http("GET", f"{url}/rest/v1/{tabela}?{consulta}", cabecalhos=cab)


def sb_upsert(tabela, linhas, conflito):
    url, cab = _sb()
    cab = {**cab, "Prefer": "resolution=merge-duplicates,return=representation"}
    return http("POST", f"{url}/rest/v1/{tabela}?on_conflict={conflito}", linhas, cab)


def sb_patch(tabela, filtro, campos):
    url, cab = _sb()
    cab = {**cab, "Prefer": "return=representation"}
    return http("PATCH", f"{url}/rest/v1/{tabela}?{filtro}", campos, cab)


def e2e(passo, estado, detalhe):
    url, cab = _sb()
    return http("POST", f"{url}/rest/v1/e2e_log", {
        "fluxo": "comunidade-24h", "passo": passo, "estado": estado,
        "detalhe": detalhe[:4000], "device": "vps-hermes", "run_id": "comunidade-24h"}, cab)


# ---------- Motor de texto (OmniRoute, compatível OpenAI) ----------

def llm(sistema, utilizador, modelo=None, max_tokens=300):
    url = os.environ.get("COMUNIDADE_LLM_URL", "http://omniroute:20128/v1").rstrip("/")
    chave = ler_cofre("llm.json")["key"]
    modelo = modelo or os.environ.get("COMUNIDADE_LLM_MODELO", "agentes")
    codigo, r = http("POST", f"{url}/chat/completions", {
        "model": modelo, "max_tokens": max_tokens, "temperature": 0.6,
        "messages": [{"role": "system", "content": sistema}, {"role": "user", "content": utilizador}],
    }, {"Authorization": "Bearer " + chave})
    if codigo != 200 or not isinstance(r, dict):
        raise RuntimeError(f"motor HTTP {codigo}: {str(r)[:300]}")
    return r["choices"][0]["message"]["content"].strip(), r.get("model", modelo)
