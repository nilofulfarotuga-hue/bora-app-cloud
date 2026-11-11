"""Varredura mundial por país (M10 2B.2, 08-09/11/2026).
Fonte primária: API do GitHub (repo real, licença, estrelas, pushed_at). Nada é inventado:
cada linha do resultado vem de um objecto devolvido pela API.
Uso no PC (completo, confirma o país pela localização do dono):
    GH_LIGACAO=<credencial do git> python -I radar_mundo.py <pasta_saida>
Uso na VPS (leve, sem credencial: só as pesquisas por língua + organizações, 6,5 s entre pesquisas
porque a API sem credencial deixa 10 pesquisas/min e 60 chamadas/hora):
    RADAR_LEVE=1 python3 radar_mundo.py <pasta_saida>
Escreve <pasta_saida>/resultado.json e <pasta_saida>/resumo.md (top 5 por país, licença aberta, < 90 dias).
"""
import datetime as dt, json, os, re, sys, time, urllib.parse, urllib.request

LIGACAO = os.environ.get("GH_LIGACAO", "")
LEVE = os.environ.get("RADAR_LEVE") == "1" or not LIGACAO
OUT = sys.argv[1]
CORTE = (dt.date.today() - dt.timedelta(days=90)).isoformat()   # atualizado há menos de 90 dias
H = {"User-Agent": "bora-radar-m10", "Accept": "application/vnd.github+json"}
if LIGACAO:
    H["Authorization"] = "Bearer " + LIGACAO
OK_LIC = {"MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "AGPL-3.0", "GPL-3.0", "MPL-2.0", "LGPL-3.0", "ISC",
          "Unlicense", "CC0-1.0", "GPL-2.0", "EPL-2.0"}
os.makedirs(OUT, exist_ok=True)
sys.stdout.reconfigure(encoding="utf-8")

RELEV = re.compile(r"(agent|agente|agentic|llm|gpt|chatbot|whatsapp|crm|automat|automa[cç]|rag\b|mcp|assistant|assistente|"
                   r"delivery|marketplace|n8n|workflow|ollama|claude|gemini|deepseek|qwen|glm|kimi|minimax|voice|tts|ocr|"
                   r"chat|bot\b|copilot|智能体|代理|大模型|エージェント|에이전트|агент|ии\b|yapay|kecerdasan|sztuczn)", re.I)

PAISES = {
    "Brasil": {"loc": ["Brazil", "Brasil", "São Paulo", "Rio de Janeiro"], "q": [
        "agente whatsapp", "atendimento ia", "automação whatsapp", "agentes de ia", "chatbot português"]},
    "Portugal": {"loc": ["Portugal", "Lisboa", "Lisbon", "Porto", "Coimbra", "Braga"], "q": [
        "portugal agent", "português europeu", "portugal ai", "pt-pt"]},
    "Espanha": {"loc": ["Spain", "España", "Madrid", "Barcelona", "Valencia"], "q": [
        "agente ia español", "asistente whatsapp", "automatización ia"]},
    "França": {"loc": ["France", "Paris", "Lyon"], "q": ["agent ia français", "assistant ia entreprise", "agents autonomes"]},
    "Alemanha": {"loc": ["Germany", "Deutschland", "Berlin", "München", "Munich", "Hamburg"], "q": [
        "KI Agent", "deutsch llm", "ki assistent"]},
    "Índia": {"loc": ["India", "Bangalore", "Bengaluru", "Mumbai", "Delhi", "Hyderabad", "Pune"], "q": [
        "whatsapp ai agent india", "hindi llm", "indic llm"]},
    "China": {"loc": ["China", "Beijing", "Shanghai", "Hangzhou", "Shenzhen"], "q": [
        "智能体", "大模型 agent", "微信 机器人 ai"], "orgs": ["deepseek-ai", "QwenLM", "zai-org", "MoonshotAI", "MiniMax-AI"]},
    "Japão": {"loc": ["Japan", "Tokyo", "Osaka"], "q": ["エージェント", "日本語 llm", "生成ai"]},
    "Coreia": {"loc": ["Korea", "Seoul"], "q": ["에이전트", "한국어 llm", "챗봇"]},
    "Rússia": {"loc": ["Russia", "Moscow", "Saint Petersburg"], "q": ["агент ии", "llm русский", "telegram бот ии"]},
    "Turquia": {"loc": ["Turkey", "Türkiye", "Istanbul", "Ankara"], "q": ["yapay zeka ajan", "türkçe llm", "türkçe chatbot"]},
    "Indonésia": {"loc": ["Indonesia", "Jakarta", "Bandung"], "q": ["agen ai indonesia", "bahasa indonesia llm", "chatbot whatsapp indonesia"]},
    "Nigéria": {"loc": ["Nigeria", "Lagos", "Abuja"], "q": ["nigeria ai", "africa llm", "naija"]},
    "Polónia": {"loc": ["Poland", "Polska", "Warsaw", "Warszawa", "Kraków", "Krakow", "Wrocław"], "q": [
        "polski llm", "agent ai polska", "bielik"]},
}

CHAMADAS = {"search": 0, "core": 0}


def api(url, search=False):
    for _ in range(4):
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers=H), timeout=30)
            CHAMADAS["search" if search else "core"] += 1
            if search:
                time.sleep(6.5 if LEVE else 2.2)
            return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                time.sleep(30)
                continue
            if e.code in (404, 422, 451):
                return None
            time.sleep(5)
        except Exception:
            time.sleep(5)
    return None


def repo_info(r):
    lic = (r.get("license") or {}).get("spdx_id")
    return {"repo": r["full_name"], "url": r["html_url"], "estrelas": r["stargazers_count"],
            "licenca": lic, "atualizado": (r.get("pushed_at") or "")[:10], "lingua": r.get("language"),
            "descricao": (r.get("description") or "")[:220], "topicos": r.get("topics", [])[:8],
            "dono": r["owner"]["login"], "arquivado": r.get("archived", False), "fork": r.get("fork", False)}


LOC_CACHE = {}


def local_do_dono(login):
    if login not in LOC_CACHE:
        u = api("https://api.github.com/users/" + urllib.parse.quote(login))
        LOC_CACHE[login] = (u or {}).get("location") or ""
    return LOC_CACHE[login]


def bate_pais(loc, pais):
    l = (loc or "").lower()
    return any(x.lower() in l for x in PAISES[pais]["loc"])


resultado = {}
for pais, cfg in PAISES.items():
    cands = {}
    for q in cfg["q"]:
        qq = "%s pushed:>=%s stars:>=20 fork:false archived:false" % (q, CORTE)
        j = api("https://api.github.com/search/repositories?" + urllib.parse.urlencode(
            {"q": qq, "sort": "stars", "order": "desc", "per_page": 30}), search=True)
        for r in (j or {}).get("items", []):
            x = repo_info(r)
            x["como"] = "palavras: " + q
            cands[x["repo"]] = x
    loc_q = 'location:"%s"' % cfg["loc"][0]
    j = None if LEVE else api("https://api.github.com/search/users?" + urllib.parse.urlencode(
        {"q": loc_q + " followers:>150", "sort": "followers", "order": "desc", "per_page": 25}), search=True)
    for u in (j or {}).get("items", []):
        reps = api("https://api.github.com/users/%s/repos?sort=pushed&per_page=30&type=owner" % urllib.parse.quote(u["login"])) or []
        for r in reps:
            if r.get("fork") or r.get("archived") or (r.get("pushed_at") or "") < CORTE or r["stargazers_count"] < 20:
                continue
            x = repo_info(r)
            x["como"] = "programador do pais: " + u["login"]
            LOC_CACHE.setdefault(u["login"], cfg["loc"][0])
            cands.setdefault(x["repo"], x)
    for org in cfg.get("orgs", []):
        reps = api("https://api.github.com/orgs/%s/repos?sort=pushed&per_page=30" % org) or []
        for r in reps:
            if r.get("archived") or (r.get("pushed_at") or "") < CORTE:
                continue
            x = repo_info(r)
            x["como"] = "organizacao: " + org
            LOC_CACHE.setdefault(r["owner"]["login"], cfg["loc"][0])
            cands.setdefault(x["repo"], x)
    filtrados = []
    for x in sorted(cands.values(), key=lambda v: -v["estrelas"]):
        texto = " ".join([x["repo"], x["descricao"], " ".join(x["topicos"])])
        if not RELEV.search(texto):
            continue
        if x["atualizado"] < CORTE or x["arquivado"]:
            continue
        if LEVE:   # sem credencial nao ha chamadas para a localizacao: o pais vem da lingua da pesquisa
            loc = LOC_CACHE.get(x["dono"], "")
            x["local_dono"] = loc
            x["pais_confirmado"] = x["como"].startswith("organizacao") or None
        else:
            loc = local_do_dono(x["dono"])
            x["local_dono"] = loc
            x["pais_confirmado"] = bate_pais(loc, pais) or x["como"].startswith("organizacao")
        filtrados.append(x)
        if len([f for f in filtrados if f["pais_confirmado"]]) >= 15 and len(filtrados) >= 25:
            break
    resultado[pais] = filtrados
    print(pais, "candidatos", len(cands), "relevantes", len(filtrados),
          "confirmados", sum(1 for f in filtrados if f["pais_confirmado"]), "chamadas", dict(CHAMADAS), flush=True)
    json.dump(resultado, open(os.path.join(OUT, "resultado.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

linhas = ["# Varredura mundial por pais — %s (%s, GitHub, atualizados desde %s, licenca aberta)" % (
    dt.date.today().isoformat(), "leve, pais pela lingua" if LEVE else "pais confirmado pela localizacao do dono", CORTE), ""]
for pais, l in resultado.items():
    bons = [x for x in l if x["licenca"] in OK_LIC and x["pais_confirmado"] is not False][:5]
    linhas.append("## %s" % pais)
    for x in bons:
        linhas.append("- %s — %d estrelas, %s, atualizado %s — %s" % (
            x["url"], x["estrelas"], x["licenca"], x["atualizado"], re.sub(r"\s+", " ", x["descricao"])[:140]))
    if not bons:
        linhas.append("- (nada que passe as regras esta semana)")
    linhas.append("")
open(os.path.join(OUT, "resumo.md"), "w", encoding="utf-8").write("\n".join(linhas))
print("FIM", dict(CHAMADAS), "leve" if LEVE else "completo")
