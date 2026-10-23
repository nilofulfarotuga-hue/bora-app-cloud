#!/usr/bin/env python3
"""Bloco 7 (omniroute-23-10): escreve o estado do OmniRoute em public.omniroute_estado (id 'vps').

Corre no host da VPS de 10 em 10 minutos (cron). Para cada ligacao faz o teste do proprio OmniRoute
(so verifica a chave, nao gasta tokens) e junta as chamadas de hoje; para cada combo diz qual o nivel
que vai responder agora. Nunca envia chaves. Upsert com merge (o ignore-duplicates congelou o
motor_estado em 09/2026 — cicatriz no MOTORES.md).
"""
import datetime
import json
import os
import sys
import urllib.request

sys.path.insert(0, "/opt/omniroute")
import or_admin  # noqa: E402
from or_combos import COMBOS  # noqa: E402

AGENTES_POR_COMBO = {
    "agentes": ["emerson (principal)", "fiscal", "batedor", "escriba", "critico", "vendedor", "conselho (juiz)", "OpenCode do PC"],
    "privado": ["torre"],
    "rapido": [], "volume": [], "visao": [],
}
NOMES = {"openai-compatible-chat-716d6685-9ad8-4cdb-8ee8-25a83ce136d8": "motor"}


def pedir(metodo, caminho, corpo=None):
    ck = open(or_admin.COOKIE).read().strip() if os.path.exists(or_admin.COOKIE) else or_admin.entrar()
    st, txt, _ = or_admin.pedir(metodo, caminho, corpo, ck)
    if st in (401, 403):
        st, txt, _ = or_admin.pedir(metodo, caminho, corpo, or_admin.entrar())
    try:
        return st, json.loads(txt)
    except Exception:
        return st, {}


def env(path):
    out = {}
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v.strip().strip('"').strip("'")
    return out


def main():
    agora = datetime.datetime.now(datetime.timezone.utc)
    hoje = agora.strftime("%Y-%m-%d")
    _, prov = pedir("GET", "/api/providers")
    _, logs = pedir("GET", "/api/usage/request-logs?limit=500")
    _, an = pedir("GET", "/api/usage/analytics?range=today")
    _, saude = pedir("GET", "/api/system/version")

    por_conta = {}
    for linha in logs if isinstance(logs, list) else []:
        p = [x.strip() for x in str(linha).split("|")]
        if len(p) < 7 or not p[0].startswith(hoje):
            continue
        c = por_conta.setdefault(p[3], {"pedidos": 0, "ok": 0, "falhas": 0, "ultimo_status": None, "ultima_vez": None})
        c["pedidos"] += 1
        ok = p[6].startswith("2")
        c["ok" if ok else "falhas"] += 1
        if c["ultima_vez"] is None or p[0] > c["ultima_vez"]:
            c["ultima_vez"], c["ultimo_status"] = p[0], p[6]

    fornecedores, vivo_por_prov = [], {}
    for c in prov.get("connections", []):
        st, t = pedir("POST", f"/api/providers/{c['id']}/test", {})
        teste_ok = bool(t.get("valid"))
        uso = por_conta.get(c["name"], {})
        ultimo = str(uso.get("ultimo_status") or "")
        morto_pelo_uso = ultimo[:3] in ("401", "402", "403", "410")
        vivo = bool(c.get("isActive")) and teste_ok and not morto_pelo_uso
        nome_prov = NOMES.get(c["provider"], c["provider"])
        vivo_por_prov[nome_prov] = vivo_por_prov.get(nome_prov, False) or vivo
        erro = None if vivo else (t.get("error") or (f"ultima chamada {ultimo}" if morto_pelo_uso else "inativo"))
        fornecedores.append({"nome": c["name"], "fornecedor": nome_prov, "vivo": vivo, "teste_chave": teste_ok,
                             "erro": (erro or "")[:160] or None, "pedidos_hoje": uso.get("pedidos", 0),
                             "ok_hoje": uso.get("ok", 0), "falhas_hoje": uso.get("falhas", 0),
                             "ultima_vez": uso.get("ultima_vez")})

    combos = []
    for nome, cfg in COMBOS.items():
        ativo = next((m for m in cfg["models"] if vivo_por_prov.get(m.split("/", 1)[0])), None)
        combos.append({"nome": nome, "niveis": len(cfg["models"]), "nivel_ativo": ativo,
                       "primeiro_nivel": cfg["models"][0], "agentes": AGENTES_POR_COMBO.get(nome, [])})

    s = (an or {}).get("summary") or {}
    dados = {
        "versao": (saude or {}).get("current"),
        "gerado_em": agora.isoformat(timespec="seconds"),
        "fornecedores": sorted(fornecedores, key=lambda f: (not f["vivo"], f["nome"])),
        "vivos": sum(1 for f in fornecedores if f["vivo"]),
        "mortos": sum(1 for f in fornecedores if not f["vivo"]),
        "combos": combos,
        "combo_em_uso": "agentes",
        "consumo_hoje": {"pedidos": s.get("totalRequests", 0), "ok": s.get("successfulRequests", 0),
                         "tokens": s.get("totalTokens", 0), "recuos": s.get("fallbackCount", 0),
                         "custo_tabela_usd": s.get("totalCost", 0)},
        "por_fornecedor_hoje": [{"fornecedor": p.get("provider"), "pedidos": p.get("requests"),
                                 "tokens": p.get("totalTokens"), "taxa_ok": p.get("successRatePct")}
                                for p in (an or {}).get("byProvider", [])][:15],
    }
    e = env("/opt/whatsapp-bora/.env")
    url, chave = e["SUPABASE_URL"].rstrip("/"), e["SUPABASE_SERVICE_ROLE_KEY"]
    corpo = json.dumps([{"id": "vps", "dados": dados, "updated_at": agora.isoformat()}]).encode()
    req = urllib.request.Request(url + "/rest/v1/omniroute_estado?on_conflict=id", data=corpo, method="POST",
                                 headers={"apikey": chave, "Authorization": "Bearer " + chave,
                                          "Content-Type": "application/json",
                                          "Prefer": "resolution=merge-duplicates,return=minimal"})
    with urllib.request.urlopen(req, timeout=30) as r:
        print(agora.strftime("%H:%M:%S"), "omniroute_estado", r.status, "vivos", dados["vivos"], "mortos", dados["mortos"],
              "pedidos_hoje", dados["consumo_hoje"]["pedidos"])


if __name__ == "__main__":
    main()
