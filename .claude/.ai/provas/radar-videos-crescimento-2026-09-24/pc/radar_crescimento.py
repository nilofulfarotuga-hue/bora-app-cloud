#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Radar diário de vídeos de CRESCIMENTO (missão radar-videos-crescimento-2026-09-24).

Corre NO PC do Danilo (IP de casa: as legendas do YouTube saem; da VPS não). Um processo
pesado de cada vez. Modos:
  python radar_crescimento.py recolher   # ~20 vídeos novos (últimos 7 dias), legendas, resumo, Supabase
  python radar_crescimento.py playbook   # destila regras vistas em >= 3 vídeos (semanal) -> PLAYBOOK-REDES.md + Supabase
  python radar_crescimento.py telegram   # 5 linhas ao Danilo com o dia (usa o gritar-do-pc.sh)

Ficheiros: .env (RADAR_VIDEOS_KEY, SUPABASE_URL, SUPABASE_ANON_KEY, GEMINI_API_KEY), dados/videos.jsonl
(cópia local do que foi guardado), dados/ids_processados.txt, logs/radar.log. Resumos por GLM
(opencode run -m opencode-go/glm-5.2), com Gemini de reserva e Ollama em último — nunca Claude.
"""
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
DADOS = os.path.join(BASE, "dados")
LOGS = os.path.join(BASE, "logs")
TMP = os.path.join(BASE, "_tmp")
for d in (DADOS, LOGS, TMP):
    os.makedirs(d, exist_ok=True)
LOG = os.path.join(LOGS, "radar.log")
IDS = os.path.join(DADOS, "ids_processados.txt")
JSONL = os.path.join(DADOS, "videos.jsonl")
PLAYBOOK_MD = r"C:\BoraLocal\projetosflutter\bora_app\docs\marketing\PLAYBOOK-REDES.md"
GRITAR = r"C:\BoraLocal\projetosflutter\bora_app\orquestracao\gritar-do-pc.sh"
ALVO = int(os.environ.get("RADAR_ALVO", "20"))
# Janela de publicacao. A 24/09, com 7 dias, 68 dos 70 candidatos foram deitados fora por
# serem mais velhos que uma semana e a recolha rendeu 2 videos. O YouTube ordena por
# relevancia, nao por data (ytsearchdate nao existe nesta versao do yt-dlp), por isso a
# janela tem de ser larga; a 1.a recolha semeia a base com RADAR_DIAS maior.
DIAS = int(os.environ.get("RADAR_DIAS", "45"))

# Pesquisas rotativas (PT-BR, PT-PT, EN): 6 por dia, a rodar pelo dia do ano.
PESQUISAS = [
    ("como crescer no instagram 2026", "crescer_redes"),
    ("reels viral estratégia 2026", "crescer_redes"),
    ("algoritmo instagram 2026 como funciona", "crescer_redes"),
    ("facebook orgânico alcance 2026", "crescer_redes"),
    ("tiktok como viralizar 2026", "crescer_redes"),
    ("hook primeiros 3 segundos vídeo", "crescer_redes"),
    ("como crescer no instagram do zero", "crescer_redes"),
    ("instagram growth strategy 2026", "crescer_redes"),
    ("reels that go viral 2026", "crescer_redes"),
    ("como ganhar dinheiro online 2026", "ganhar_dinheiro"),
    ("marketing digital pequenos negócios 2026", "marketing_apps"),
    ("marketing app delivery local", "marketing_apps"),
    ("growth hacking app 2026", "marketing_apps"),
    ("UGC conteúdo gerado por utilizadores marca", "marketing_apps"),
    ("como divulgar aplicativo sem pagar", "marketing_apps"),
    ("app marketing organic growth 2026", "marketing_apps"),
    ("carrossel instagram que converte", "crescer_redes"),
    ("melhor horário para postar instagram 2026", "crescer_redes"),
]


def log(msg):
    linha = "[%s] %s" % (dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + "\n")
    print(linha)


def env():
    e = {}
    p = os.path.join(BASE, ".env")
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#") and "=" in ln:
                k, v = ln.split("=", 1)
                e[k.strip()] = v.strip().strip('"').strip("'")
    for k, v in os.environ.items():
        e.setdefault(k, v)
    return e


E = env()


# ------------------------------------------------------------------ yt-dlp
def sh(cmd, timeout=180):
    # No Windows o `opencode`/`yt-dlp` sao .cmd/.exe fora do PATH do subprocess: resolve-se
    # o caminho completo (a 24/09 o GLM "rebentou" com WinError 2 e caiu sempre no Gemini).
    exe = shutil.which(cmd[0]) or shutil.which(cmd[0] + ".cmd") or cmd[0]
    return subprocess.run([exe] + list(cmd[1:]), capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")


def pesquisar(q, n=10):
    r = sh(["yt-dlp", "--no-warnings", "--flat-playlist", "--print", "%(id)s\t%(title)s\t%(channel)s\t%(view_count)s",
            "ytsearch%d:%s" % (n, q)], timeout=240)
    out = []
    for ln in r.stdout.splitlines():
        p = ln.split("\t")
        if len(p) >= 4 and re.match(r"^[A-Za-z0-9_-]{11}$", p[0]):
            out.append({"youtube_id": p[0], "titulo": p[1], "canal": p[2], "visualizacoes": p[3]})
    return out


def metadados(vid):
    r = sh(["yt-dlp", "--no-warnings", "--skip-download", "--print",
            "%(upload_date)s\t%(view_count)s\t%(duration)s\t%(language)s\t%(channel)s\t%(title)s",
            "https://www.youtube.com/watch?v=" + vid], timeout=120)
    ln = r.stdout.strip().splitlines()
    if not ln:
        return None
    p = ln[-1].split("\t")
    if len(p) < 6:
        return None
    return {"upload_date": p[0], "visualizacoes": p[1], "duracao_s": p[2], "lingua": p[3], "canal": p[4], "titulo": p[5]}


def limpa_vtt(texto):
    linhas = []
    prev = None
    for ln in texto.splitlines():
        ln = re.sub(r"<[^>]+>", "", ln).strip()
        if not ln or "-->" in ln or ln.startswith(("WEBVTT", "Kind:", "Language:")) or ln.isdigit():
            continue
        if ln != prev:
            linhas.append(ln)
            prev = ln
    return " ".join(linhas)


def legenda(vid):
    """Transcrição automática (pt ou en) sem cookies. None se não houver."""
    for f in os.listdir(TMP):
        if f.startswith("sub_" + vid):
            os.remove(os.path.join(TMP, f))
    sh(["yt-dlp", "--no-warnings", "--ignore-errors", "--skip-download", "--write-auto-sub", "--write-sub",
        "--sub-langs", "pt,pt-orig,en,en-orig", "--sub-format", "vtt", "-o", os.path.join(TMP, "sub_%(id)s"),
        "https://www.youtube.com/watch?v=" + vid], timeout=180)
    vtts = sorted(f for f in os.listdir(TMP) if f.startswith("sub_" + vid) and f.endswith(".vtt"))
    for nome in vtts:
        txt = limpa_vtt(open(os.path.join(TMP, nome), encoding="utf-8", errors="replace").read())
        if len(txt) > 300:
            return txt
    return None


def descricao(vid):
    r = sh(["yt-dlp", "--no-warnings", "--skip-download", "--print", "%(description)s", "https://www.youtube.com/watch?v=" + vid], timeout=120)
    return r.stdout.strip()[:3000]


# ------------------------------------------------------------------ resumo (GLM -> Gemini -> Ollama)
PROMPT_RESUMO = """Es um analista de marketing de redes sociais. Le o TEXTO (transcricao ou descricao) de um video do YouTube
e responde SO com JSON valido, sem markdown, com estas chaves:
{"tema": "crescer_redes" | "ganhar_dinheiro" | "marketing_apps" | "outro",
 "resumo": "resumo em portugues do Brasil, 3 a 5 frases, so o que o video diz mesmo",
 "ideias": ["ideia pratica 1", "ideia pratica 2", "ideia pratica 3"],
 "nota": 0 a 10 (utilidade para um app local de entregas e servicos numa cidade pequena e para um app de recibos verdes)}
Nao inventes nada que nao esteja no texto. Se o texto for so uma descricao, diz isso no resumo.

TITULO: %s
CANAL: %s
ORIGEM DO TEXTO: %s
TEXTO:
%s"""


def _json_de(txt):
    """O ultimo objecto JSON valido do texto.

    O `opencode` devolve o prompt ecoado + cores ANSI + a resposta entre ```json. Uma busca
    gulosa do primeiro "{" ao ultimo "}" apanhava o EXEMPLO que vai dentro do prompt e
    rebentava sempre (a 24/09 o GLM parecia mudo e o radar caiu todo no Gemini). Le-se de
    tras para a frente e fica o primeiro que der json valido.
    """
    if not txt:
        return None
    txt = re.sub(r"\[[0-9;]*[A-Za-z]", "", txt)
    cercas = re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", txt, re.S)
    for c in reversed(cercas):
        try:
            return json.loads(c)
        except Exception:                                         # noqa: BLE001
            pass
    fins = [m.end() for m in re.finditer(r"\}", txt)]
    inicios = [m.start() for m in re.finditer(r"\{", txt)]
    for fim in reversed(fins):
        for ini in reversed([i for i in inicios if i < fim]):
            try:
                j = json.loads(txt[ini:fim])
            except Exception:                                     # noqa: BLE001
                continue
            if isinstance(j, dict):
                return j
    return None


def resumir_glm(prompt):
    r = sh(["opencode", "run", "-m", "opencode-go/glm-5.2", prompt], timeout=150)
    j = _json_de(r.stdout)
    return (j, "glm-5.2") if j else (None, None)


def resumir_gemini(prompt):
    k = E.get("GEMINI_API_KEY", "")
    if not k:
        return None, None
    for modelo in ("gemini-3.1-flash-lite", "gemini-3.5-flash-lite", "gemini-3-flash-preview"):
        try:
            req = urllib.request.Request(
                "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % modelo,
                data=json.dumps({"contents": [{"parts": [{"text": prompt}]}],
                                 "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"}}).encode(),
                headers={"x-goog-api-key": k, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as resp:
                d = json.loads(resp.read().decode())
            txt = "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])
            j = _json_de(txt)
            if j:
                return j, modelo
        except Exception as ex:  # noqa: BLE001
            log("gemini %s falhou: %s" % (modelo, str(ex)[:120]))
    return None, None


def resumir_ollama(prompt):
    try:
        req = urllib.request.Request("http://127.0.0.1:11434/api/generate",
                                     data=json.dumps({"model": E.get("OLLAMA_MODEL", "qwen2.5:7b"), "prompt": prompt, "stream": False,
                                                      "format": "json"}).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as resp:
            d = json.loads(resp.read().decode())
        j = _json_de(d.get("response", ""))
        return (j, "ollama-" + E.get("OLLAMA_MODEL", "qwen2.5:7b")) if j else (None, None)
    except Exception as ex:  # noqa: BLE001
        log("ollama falhou: %s" % str(ex)[:120])
        return None, None


def resumir(v, texto, origem):
    prompt = PROMPT_RESUMO % (v["titulo"], v.get("canal", ""), origem, texto[:7000])
    # Ordem por VELOCIDADE, nao por preco: os dois sao baratos, mas a 24/09 o GLM levou
    # 4 minutos por video neste PC (Celeron) enquanto o Gemini flash-lite responde em
    # segundos. 20 videos x 4 min nao cabem numa corrida diaria. GLM fica de reserva para
    # quando o Gemini der 503 ou esgotar a quota; o Ollama local e' o ultimo recurso.
    for fn in (resumir_gemini, resumir_glm, resumir_ollama):
        try:
            j, motor = fn(prompt)
        except Exception as ex:  # noqa: BLE001
            log("%s rebentou: %s" % (fn.__name__, str(ex)[:120]))
            j, motor = None, None
        if j and isinstance(j.get("ideias"), list):
            return j, motor
    return None, "nenhum"


# ------------------------------------------------------------------ Supabase (RPC com chave)
def rpc(nome, corpo):
    url = E.get("SUPABASE_URL", "").rstrip("/") + "/rest/v1/rpc/" + nome
    req = urllib.request.Request(url, data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                                 headers={"apikey": E.get("SUPABASE_ANON_KEY", ""), "Authorization": "Bearer " + E.get("SUPABASE_ANON_KEY", ""),
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw.strip() else None


def registar(linha):
    try:
        return rpc("radar_videos_registar", {"p_chave": E.get("RADAR_VIDEOS_KEY", ""), "p_linha": linha})
    except Exception as ex:  # noqa: BLE001
        log("supabase registar falhou: %s" % str(ex)[:160])
        return None


def ids_conhecidos():
    ids = set()
    if os.path.exists(IDS):
        ids |= {ln.strip() for ln in open(IDS, encoding="utf-8") if ln.strip()}
    try:
        for r in rpc("radar_videos_ler", {"p_chave": E.get("RADAR_VIDEOS_KEY", ""), "p_dias": 365}) or []:
            ids.add(r["youtube_id"])
    except Exception as ex:  # noqa: BLE001
        log("supabase ler falhou (sigo com a cache local): %s" % str(ex)[:120])
    return ids


# ------------------------------------------------------------------ modos
def modo_recolher():
    inicio = time.time()
    hoje = dt.date.today()
    corte = (hoje - dt.timedelta(days=DIAS)).strftime("%Y%m%d")
    conhecidos = ids_conhecidos()
    k = hoje.timetuple().tm_yday
    pesquisas = [PESQUISAS[(k * 6 + i) % len(PESQUISAS)] for i in range(6)]
    log("START recolher alvo=%d pesquisas=%s conhecidos=%d" % (ALVO, [p[0] for p in pesquisas], len(conhecidos)))
    candidatos, vistos = [], set()
    for q, tema_q in pesquisas:
        for c in pesquisar(q, 12):
            if c["youtube_id"] in conhecidos or c["youtube_id"] in vistos:
                continue
            vistos.add(c["youtube_id"])
            c["pesquisa"], c["tema_pesquisa"] = q, tema_q
            candidatos.append(c)
        time.sleep(2)
    log("candidatos novos: %d" % len(candidatos))
    feitos, com_leg, sem_leg = 0, 0, 0
    for c in candidatos:
        if feitos >= ALVO or time.time() - inicio > 3300:
            break
        vid = c["youtube_id"]
        m = metadados(vid)
        if not m or not m["upload_date"].isdigit() or m["upload_date"] < corte:
            continue
        dur = int(m["duracao_s"]) if m["duracao_s"].isdigit() else 0
        if dur < 60 or dur > 2700:
            continue
        txt = legenda(vid)
        if txt:
            origem, tem = "LEGENDA (transcricao automatica real)", True
            com_leg += 1
        else:
            txt, origem, tem = descricao(vid), "DESCRICAO (sem transcricao)", False
            sem_leg += 1
        v = {"youtube_id": vid, "titulo": m["titulo"] or c["titulo"], "canal": m["canal"] or c["canal"],
             "visualizacoes": m["visualizacoes"] if m["visualizacoes"].isdigit() else None,
             "publicado_em": "%s-%s-%s" % (m["upload_date"][:4], m["upload_date"][4:6], m["upload_date"][6:]),
             "duracao_s": dur, "link": "https://www.youtube.com/watch?v=" + vid, "lingua": m["lingua"] if m["lingua"] != "NA" else None,
             "pesquisa": c["pesquisa"], "tem_transcricao": tem}
        j, motor = resumir(v, txt, origem)
        if j:
            v.update({"tema": j.get("tema") or c["tema_pesquisa"], "transcricao_resumida": (j.get("resumo") or "")[:2000],
                      "ideias": [str(x)[:300] for x in j.get("ideias", [])][:3],
                      "nota_utilidade": max(0, min(10, int(j.get("nota", 5) or 0)))})
        else:
            v.update({"tema": c["tema_pesquisa"], "transcricao_resumida": ("(sem resumo: nenhum motor respondeu) " + txt[:600]),
                      "ideias": [], "nota_utilidade": None})
        v["motor_resumo"] = motor
        registar(v)
        with open(JSONL, "a", encoding="utf-8") as f:
            f.write(json.dumps(dict(v, recolhido_em=dt.datetime.now().isoformat(timespec="seconds")), ensure_ascii=False) + "\n")
        with open(IDS, "a", encoding="utf-8") as f:
            f.write(vid + "\n")
        feitos += 1
        log("%d/%d %s | %s | %s | nota=%s motor=%s" % (feitos, ALVO, vid, v["tema"], (v["titulo"] or "")[:60], v.get("nota_utilidade"), motor))
        time.sleep(3)
    log("FIM recolher: %d videos (%d com legenda, %d so descricao) em %d s" % (feitos, com_leg, sem_leg, int(time.time() - inicio)))
    return feitos, com_leg, sem_leg


def _linhas_recentes(dias):
    try:
        return rpc("radar_videos_ler", {"p_chave": E.get("RADAR_VIDEOS_KEY", ""), "p_dias": dias}) or []
    except Exception as ex:  # noqa: BLE001
        log("supabase ler falhou, uso o jsonl local: %s" % str(ex)[:120])
        out = []
        if os.path.exists(JSONL):
            for ln in open(JSONL, encoding="utf-8"):
                try:
                    out.append(json.loads(ln))
                except Exception:
                    pass
        return out


PROMPT_PLAYBOOK = """Es o editor do LIVRO DE REGRAS das redes sociais de dois apps portugueses (Bora, entregas e servicos
na Guarda; Em Dia, recibos verdes). Em baixo estao as IDEIAS extraidas de varios videos do YouTube, cada uma com o id do
video. Escreve SO JSON valido: {"regras": [{"regra": "...", "categoria": "gancho|duracao|legendas|horarios|frequencia|cta|formato|outro",
"provas": ["id1","id2","id3"]}]}.
REGRAS: so entra uma regra que apareca em PELO MENOS 3 videos diferentes (3 ids distintos nas provas); frases curtas em
portugues do Brasil, praticas, que um robo de conteudo possa seguir; no maximo 15 regras; nao inventes ids.

IDEIAS:
%s"""


def modo_playbook():
    linhas = [l for l in _linhas_recentes(30) if l.get("ideias")]
    if len(linhas) < 3:
        log("playbook: so %d videos com ideias; nada a destilar" % len(linhas))
        return 0
    material = "\n".join("[%s] %s (%s): %s" % (l["youtube_id"], l["titulo"][:70], l.get("tema"), " | ".join(l["ideias"])) for l in linhas)
    prompt = PROMPT_PLAYBOOK % material[:60000]
    regras, motor = None, None
    for fn in (resumir_glm, resumir_gemini, resumir_ollama):
        j, motor = fn(prompt)
        if j and isinstance(j.get("regras"), list):
            regras = j["regras"]
            break
    if not regras:
        log("playbook: nenhum motor respondeu")
        return 0
    por_id = {l["youtube_id"]: l for l in linhas}
    validas = []
    for r in regras:
        provas = [p for p in dict.fromkeys(r.get("provas", [])) if p in por_id]
        if len(provas) >= 3 and r.get("regra"):
            validas.append({"regra": r["regra"].strip(), "categoria": r.get("categoria", "outro"),
                            "provas": [{"youtube_id": p, "link": por_id[p]["link"], "titulo": por_id[p]["titulo"][:80]} for p in provas],
                            "n_videos": len(provas)})
    versao = int(dt.date.today().strftime("%Y%m%d"))
    try:
        n = rpc("playbook_redes_registar", {"p_chave": E.get("RADAR_VIDEOS_KEY", ""), "p_versao": versao, "p_regras": validas})
    except Exception as ex:  # noqa: BLE001
        log("playbook supabase falhou: %s" % str(ex)[:120])
        n = None
    os.makedirs(os.path.dirname(PLAYBOOK_MD), exist_ok=True)
    with open(PLAYBOOK_MD, "w", encoding="utf-8", newline="\n") as f:
        f.write("# PLAYBOOK REDES — regras que os robôs de conteúdo do Bora e do Em Dia seguem\n\n")
        f.write("> Versão %d, gerada por `QG/radar-crescimento/radar_crescimento.py playbook` a partir de %d vídeos com ideias "
                "(últimos 30 dias). Só entra uma regra vista em **3 ou mais vídeos diferentes**; os links são a prova. "
                "Motor: %s. Atualiza-se 1x por semana. Os robôs (social-reel.sh, banco de peças, emdia_redes.py) e o "
                "fiscal_video leem `playbook-redes.json` gerado ao lado.\n\n" % (versao, len(linhas), motor))
        por_cat = {}
        for r in validas:
            por_cat.setdefault(r["categoria"], []).append(r)
        for cat in sorted(por_cat):
            f.write("## %s\n\n" % cat)
            for r in por_cat[cat]:
                f.write("- **%s** (%d vídeos) — %s\n" % (r["regra"], r["n_videos"], " · ".join("[%s](%s)" % (p["titulo"][:40], p["link"]) for p in r["provas"])))
            f.write("\n")
    with open(os.path.join(os.path.dirname(PLAYBOOK_MD), "playbook-redes.json"), "w", encoding="utf-8") as f:
        json.dump({"versao": versao, "gerado_em": dt.datetime.now().isoformat(timespec="seconds"), "motor": motor, "regras": validas}, f, ensure_ascii=False, indent=1)
    log("playbook v%d: %d regras validas (de %d propostas), supabase=%s, motor=%s" % (versao, len(validas), len(regras), n, motor))
    # Copia para a VPS: e' o ficheiro que social-reel.sh, emdia_redes.py e fiscal_video.py leem.
    pj = os.path.join(os.path.dirname(PLAYBOOK_MD), "playbook-redes.json")
    try:
        r = sh(["scp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=40", "-i", os.path.expanduser("~/.ssh/id_ed25519_vps"),
                pj, "root@srv1786862.hstgr.cloud:/opt/data/social/playbook-redes.json"], timeout=120)
        log("playbook -> VPS: %s" % ("OK" if r.returncode == 0 else "FALHOU rc=%s %s" % (r.returncode, r.stderr.strip()[:120])))
    except Exception as ex:  # noqa: BLE001
        log("playbook -> VPS rebentou: %s" % str(ex)[:120])
    return len(validas)


AVISO_CONF = os.environ.get("BORA_AVISO_CONF", r"C:\Users\danil\.bora\aviso.conf")


def gritar(msg):
    """Manda a mensagem ao Danilo pela API do Telegram, direto do Python.

    Nao se usa o `gritar-do-pc.sh` aqui por uma razao medida a 24/09: no Windows os
    argumentos passam pela pagina de codigos da consola e o Telegram devolvia
    400 "strings must be encoded in UTF-8" por causa dos acentos. Em Python o corpo vai
    em UTF-8 do principio ao fim. A credencial e a MESMA (C:/Users/danil/.bora/aviso.conf,
    fora do repo) e a prova tambem: nunca se confia no codigo HTTP, le-se o "ok":true do
    corpo (o curl ja devolveu 0 num 401 e o alarme mentiu).
    """
    conf = {}
    try:
        for linha in open(AVISO_CONF, encoding="utf-8"):
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                k, v = linha.split("=", 1)
                conf[k.strip()] = v.strip().strip('"').strip("'")
    except Exception as ex:  # noqa: BLE001
        return 3, "SEM-CONF %s (%s)" % (AVISO_CONF, str(ex)[:80])
    token, chat = conf.get("TELEGRAM_BOT_TOKEN", ""), conf.get("TELEGRAM_CHAT_ID", "")
    if not token or not chat:
        return 3, "conf sem TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID"
    dados = urllib.parse.urlencode({"chat_id": chat, "text": msg,
                                    "disable_web_page_preview": "true"}).encode("utf-8")
    req = urllib.request.Request("https://api.telegram.org/bot%s/sendMessage" % token, data=dados,
                                 headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            corpo = resp.read().decode("utf-8", "replace")
    except Exception as ex:  # noqa: BLE001
        return 1, "rede: %s" % str(ex)[:140]
    if '"ok":true' in corpo.replace(" ", ""):
        return 0, "ENVIADO " + (re.search(r'"message_id":(\d+)', corpo).group(0) if re.search(r'"message_id":(\d+)', corpo) else "")
    return 1, "FALHOU: " + corpo[:200]


def modo_telegram():
    hoje = dt.date.today().isoformat()
    linhas = [l for l in _linhas_recentes(1) if str(l.get("recolhido_em", "")).startswith(hoje)]
    if not linhas:
        msg = "Radar de videos de hoje: nao recolhi nada (ver logs/radar.log no PC)."
    else:
        melhor = max(linhas, key=lambda l: (l.get("nota_utilidade") or 0))
        ideia = (melhor.get("ideias") or [""])[0]
        n_leg = sum(1 for l in linhas if l.get("tem_transcricao"))
        msg = ("Radar de videos de hoje: vi %d videos (%d com transcricao).\n"
               "A ideia mais forte foi: %s (%s, nota %s).\n"
               "Vou aplicar: %s\n"
               "Link: %s\n"
               "Tudo guardado no Supabase (radar_videos) e no playbook semanal." % (
                   len(linhas), n_leg, ideia[:160], (melhor.get("titulo") or "")[:60], melhor.get("nota_utilidade"),
                   (melhor.get("ideias") or ["", ""])[1][:140] if len(melhor.get("ideias") or []) > 1 else ideia[:140], melhor.get("link")))
    rc, detalhe = gritar(msg)
    log("telegram rc=%s %s" % (rc, detalhe[-160:].replace("\n", " ")))
    return rc


if __name__ == "__main__":
    m = sys.argv[1] if len(sys.argv) > 1 else "recolher"
    if m == "recolher":
        modo_recolher()
    elif m == "playbook":
        modo_playbook()
    elif m == "telegram":
        modo_telegram()
    else:
        print(__doc__)
