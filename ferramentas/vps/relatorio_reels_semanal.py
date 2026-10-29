#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
relatorio_reels_semanal.py - relatorio semanal dos reels da Bora, em texto corrido.

Missao final-app-2026-10-29, Adendo 1, ponto E, item 2.

O QUE FAZ
  Le da Graph API da Meta os reels/videos dos ultimos 7 dias (conta profissional de
  Instagram e Pagina de Facebook da Bora), junta o que a Meta deixa ler (alcance,
  visualizacoes, gostos, comentarios, partilhas, guardados), escreve 10-20 linhas em
  portugues, ordenadas por alcance, com o que correu melhor e o pior, e grava-o como
  pagina `relatorio-semanal-reels-AAAA-MM-DD` em public.claude_ai_memoria
  (origem 'claude-code'). Se a pagina existir, atualiza-a (PATCH).

O QUE LE E DE ONDE (nada vive neste ficheiro: o repo e publico)
  - Meta:  /opt/data/.env  -> META_PAGE_TOKEN, META_PAGE_ID, IG_USER_ID
  - Banco: /opt/assistente-negocio/.env (ou /opt/whatsapp-bora/.env)
           -> SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
  O token nunca e impresso, nunca vai num URL (cabecalho Authorization) e nunca e
  gravado no relatorio.

HONESTIDADE SOBRE O QUE A META DEIXA LER (provado a 29/10/2026 com o token da VPS)
  - Instagram: gostos e comentarios vem do proprio objeto do media (permissao
    instagram_basic, que o token tem). Alcance, visualizacoes, partilhas e guardados
    vivem em /{media}/insights e exigem instagram_manage_insights: com o token atual
    a Meta responde erro #10. O script tenta uma vez por execucao; se a Meta recusar,
    diz-o no relatorio e continua so com gostos e comentarios. Quando o token for
    renovado com essa permissao, o mesmo script passa a trazer tudo sem mexer em nada.
  - Facebook: a lista de videos, gostos e comentarios (contagens) vem; alcance e
    visualizacoes reais exigem read_insights (erro #200 com o token atual). O campo
    publico `views` devolveu sempre 0 nas provas, por isso e apresentado como "campo
    views", nunca como alcance. O mapeamento dos nomes das metricas de video_insights
    e o melhor palpite da documentacao e NAO foi provado (falta a permissao).
  - Quando nao ha alcance nenhum, o relatorio diz que ordenou por gostos+comentarios.

O PORTAO DE AUTENTICACAO
  Antes de falar com a Meta pergunta ao /opt/data/social/portao_auth.py se pode. Se
  estiver fechado (3 erros de autenticacao seguidos do publicador), nao toca na API e
  grava a pagina a dizer isso. Este script NAO regista falhas no portao: erro de
  permissao de insights e esperado e nao e credencial estragada; registar la
  travaria as publicacoes por uma hora.

USO
  python3 relatorio_reels_semanal.py            # le, escreve a pagina de hoje (Lisboa)
  python3 relatorio_reels_semanal.py --seco     # so imprime o texto, nao grava
  python3 relatorio_reels_semanal.py --data 2026-10-29

CRON (UTC; CRON_TZ nao pega neste Debian) - ver a linha no crontab da VPS:
  0 8,9 * * 1 [ "$(TZ=Europe/Lisbon date +\\%H)" = "09" ] && cd /opt/data/rotinas && ...
  08:00 UTC = 09:00 Lisboa no verao; 09:00 UTC = 09:00 Lisboa no inverno; a guarda
  deixa passar so a hora em que sao 09 em Lisboa.
"""
import argparse
import datetime
import json
import os
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Lisbon")
UTC = datetime.timezone.utc
CTX = ssl.create_default_context()

ENV_META = ["/opt/data/.env"]
ENV_SUPA = ["/opt/assistente-negocio/.env", "/opt/whatsapp-bora/.env"]
PORTAO = "/opt/data/social/portao_auth.py"
JANELA_DIAS = 7
MAX_LINHAS_RANKING = 8

# Conjuntos de metricas de /{media}/insights, do mais completo ao mais pobre. A Meta
# renomeou plays -> views em 2025; se um nome for recusado (erro 100) passa ao seguinte.
CONJUNTOS_IG = [
    "reach,views,likes,comments,shares,saved,total_interactions",
    "reach,plays,likes,comments,shares,saved,total_interactions",
    "reach,likes,comments,shares,saved,total_interactions",
]
# Nomes de video_insights do Facebook (palpite da documentacao, por provar).
FB_ALCANCE = ("total_video_impressions_unique", "post_impressions_unique")
FB_PLAYS = ("blue_reels_play_count", "total_video_views", "fb_reels_total_plays")


# --------------------------------------------------------------------------- ambiente
def ler_env(caminhos):
    """Junta os .env pela ordem dada; o primeiro que define uma chave ganha."""
    d = {}
    for p in caminhos:
        try:
            with open(p, encoding="utf-8") as fh:
                for ln in fh:
                    ln = ln.strip()
                    if ln and not ln.startswith("#") and "=" in ln:
                        k, v = ln.split("=", 1)
                        d.setdefault(k.strip(), v.strip().strip('"').strip("'"))
        except OSError:
            pass
    return d


def portao_aberto():
    """True se o portao de autenticacao deixa falar com a Meta (ou se nao existe)."""
    if not os.path.exists(PORTAO):
        return True, ""
    try:
        r = subprocess.run([sys.executable, PORTAO, "--pode-tentar"], capture_output=True, text=True, timeout=30)
        return r.returncode == 0, (r.stdout + r.stderr).strip()[:200]
    except Exception as e:  # noqa: BLE001
        return True, "portao ilegivel (%s); segui" % type(e).__name__


# --------------------------------------------------------------------------- Graph API
class GraphErro(Exception):
    def __init__(self, status, codigo, subcodigo, mensagem):
        super().__init__(mensagem)
        self.status = status
        self.codigo = codigo
        self.subcodigo = subcodigo
        self.mensagem = mensagem or ""

    @property
    def e_permissao(self):
        """Erros que dizem 'a credencial ou a permissao nao chegam'. Nunca se insiste neles."""
        m = self.mensagem.lower()
        return self.codigo in (3, 10, 102, 190, 200, 299) or "permission" in m or "oauth" in m

    def curto(self):
        sub = "/%s" % self.subcodigo if self.subcodigo else ""
        return "erro %s%s da Meta: %s" % (self.codigo, sub, self.mensagem[:160])


def _get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
        return json.loads(r.read().decode("utf-8") or "{}")


def graph(url, token):
    """GET na Graph API. Repete UMA vez so em falha de rede ou 5xx; nunca em erro de permissao."""
    ultimo = None
    for tentativa in range(2):
        try:
            return _get(url, token)
        except urllib.error.HTTPError as e:
            corpo = e.read().decode("utf-8", "replace")
            try:
                er = json.loads(corpo).get("error", {})
            except ValueError:
                er = {}
            ultimo = GraphErro(e.code, er.get("code"), er.get("error_subcode"), er.get("message") or corpo[:160])
            if e.code < 500:
                raise ultimo
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            ultimo = GraphErro(0, None, None, "rede: %s" % type(e).__name__)
        if tentativa == 0:
            time.sleep(3)
    raise ultimo


def url_graph(versao, caminho, params):
    return "https://graph.facebook.com/%s/%s?%s" % (versao, caminho, urllib.parse.urlencode(params))


def parse_ts(s):
    s = (s or "").replace("Z", "+0000")
    try:
        return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S%z")
    except ValueError:
        return datetime.datetime.fromisoformat(s)


def valor_metrica(m):
    vals = m.get("values")
    if vals:
        return vals[0].get("value")
    tv = m.get("total_value")
    return tv.get("value") if isinstance(tv, dict) else None


class EstadoInsights:
    """Lembra se a Meta recusou os insights, para nao insistir reel a reel."""

    def __init__(self):
        self.bloqueio = None   # GraphErro
        self.conjunto = None


def ig_insights(media_id, token, versao, est):
    if est.bloqueio:
        return None
    for c in ([est.conjunto] if est.conjunto else CONJUNTOS_IG):
        try:
            j = graph(url_graph(versao, "%s/insights" % media_id, {"metric": c}), token)
        except GraphErro as e:
            if e.e_permissao:
                est.bloqueio = e
                return None
            if e.codigo == 100:
                continue          # nome de metrica recusado: tenta o conjunto seguinte
            est.bloqueio = e
            return None
        est.conjunto = c
        return {m["name"]: valor_metrica(m) for m in j.get("data", [])}
    est.bloqueio = GraphErro(400, 100, None, "nenhum conjunto de metricas foi aceite")
    return None


def fb_insights(video_id, token, versao, est):
    if est.bloqueio:
        return None
    try:
        j = graph(url_graph(versao, "%s/video_insights" % video_id, {}), token)
    except GraphErro as e:
        est.bloqueio = e
        return None
    return {m["name"]: valor_metrica(m) for m in j.get("data", [])}


# --------------------------------------------------------------------------- recolha
def recolher_ig(env, desde, versao, est):
    token, ig = env["META_PAGE_TOKEN"], env["IG_USER_ID"]
    campos = "id,media_type,media_product_type,timestamp,permalink,caption,like_count,comments_count"
    url = url_graph(versao, "%s/media" % ig, {"fields": campos, "limit": 50})
    itens = []
    for _ in range(4):
        j = graph(url, token)
        data = j.get("data", [])
        for it in data:
            ts = parse_ts(it.get("timestamp"))
            if ts >= desde and (it.get("media_product_type") == "REELS" or it.get("media_type") == "VIDEO"):
                ins = ig_insights(it["id"], token, versao, est) or {}
                itens.append({
                    "rede": "Instagram", "quando": ts, "legenda": it.get("caption") or "",
                    "link": it.get("permalink") or "",
                    "alcance": ins.get("reach"),
                    "plays": ins.get("views", ins.get("plays")),
                    "gostos": ins.get("likes", it.get("like_count")),
                    "comentarios": ins.get("comments", it.get("comments_count")),
                    "partilhas": ins.get("shares"), "guardados": ins.get("saved"),
                    "views_campo": None,
                })
        prox = j.get("paging", {}).get("next")
        if not prox or not data or parse_ts(data[-1].get("timestamp")) < desde:
            break
        url = prox
    return itens


def recolher_fb(env, desde, versao, est):
    token, pg = env["META_PAGE_TOKEN"], env["META_PAGE_ID"]
    campos = ("id,created_time,permalink_url,length,description,views,"
              "likes.summary(true).limit(0),comments.summary(true).limit(0)")
    url = url_graph(versao, "%s/videos" % pg, {"fields": campos, "limit": 25})
    itens = []
    for _ in range(2):
        j = graph(url, token)
        data = j.get("data", [])
        for v in data:
            ts = parse_ts(v.get("created_time"))
            if ts < desde:
                continue
            ins = fb_insights(v["id"], token, versao, est) or {}
            link = v.get("permalink_url") or ""
            if link.startswith("/"):
                link = "https://www.facebook.com" + link
            itens.append({
                "rede": "Facebook", "quando": ts, "legenda": v.get("description") or "", "link": link,
                "alcance": next((ins[n] for n in FB_ALCANCE if ins.get(n) is not None), None),
                "plays": next((ins[n] for n in FB_PLAYS if ins.get(n) is not None), None),
                "gostos": (v.get("likes") or {}).get("summary", {}).get("total_count"),
                "comentarios": (v.get("comments") or {}).get("summary", {}).get("total_count"),
                "partilhas": None, "guardados": None,
                "views_campo": v.get("views"),
            })
        prox = j.get("paging", {}).get("next")
        if not prox or not data or parse_ts(data[-1].get("created_time")) < desde:
            break
        url = prox
    return itens


# --------------------------------------------------------------------------- texto
def n_pt(n, sing, plur):
    if n == 1:
        return "um %s" % sing
    if n == 0:
        return "nenhum %s" % sing
    return "%d %s" % (n, plur)


def num(x):
    return x if isinstance(x, (int, float)) else 0


def interacoes(it):
    return num(it["gostos"]) + num(it["comentarios"]) + num(it["partilhas"]) + num(it["guardados"])


def legenda_curta(txt, limite=70):
    t = re.sub(r"https?://\S+", "", txt or "")
    t = t.split("#")[0]
    t = re.sub(r"\s+", " ", t).strip()
    t = re.split(r"(?<=[.!?])\s", t)[0].rstrip(".")
    if len(t) > limite:
        t = t[:limite].rsplit(" ", 1)[0] + "..."
    return t or "sem legenda"


def descreve(it, com_insights):
    q = it["quando"].astimezone(TZ)
    partes = []
    if com_insights:
        for rot, k in (("alcance", "alcance"), ("visualizações", "plays"), ("partilhas", "partilhas"), ("guardados", "guardados")):
            if it[k] is not None:
                partes.append("%s %s" % (rot, it[k]))
    for v, sing, plur in ((it["gostos"], "gosto", "gostos"), (it["comentarios"], "comentário", "comentários")):
        partes.append("%s %s" % ("?" if v is None else v, sing if v == 1 else plur))
    return "%s de %s às %s, «%s»: %s - %s" % (
        it["rede"], q.strftime("%d/%m"), q.strftime("%H:%M"), legenda_curta(it["legenda"]), ", ".join(partes), it["link"])


def compor(ig, fb, est_ig, est_fb, agora, desde, versao):
    todos = ig + fb
    com_alcance = any(it["alcance"] is not None for it in todos)
    com_insights = com_alcance or any(it["plays"] is not None for it in todos)
    if com_alcance:
        todos.sort(key=lambda it: (num(it["alcance"]) if it["alcance"] is not None else -1, interacoes(it), it["quando"]), reverse=True)
    else:
        todos.sort(key=lambda it: (interacoes(it), num(it["plays"]), it["quando"]), reverse=True)

    L = []
    ini = desde.astimezone(TZ)
    fim = agora.astimezone(TZ)
    L.append("Relatório semanal dos reels da Bora, de %s a %s (últimos %d dias; lido da Meta em %s, hora de Lisboa)." % (
        ini.strftime("%d/%m"), fim.strftime("%d/%m/%Y"), JANELA_DIAS, fim.strftime("%d/%m às %H:%M")))

    if not todos:
        L.append("Nesta semana não encontrei nenhum reel nem vídeo publicado no Instagram ou na página do Facebook da Bora.")
    else:
        L.append("Contei %s no Instagram e %s na página do Facebook." % (
            n_pt(len(ig), "reel", "reels"), n_pt(len(fb), "vídeo ou reel", "vídeos ou reels")))
        g = sum(num(it["gostos"]) for it in todos)
        c = sum(num(it["comentarios"]) for it in todos)
        tot = "Somando tudo, deram %s e %s" % (n_pt(g, "gosto", "gostos"), n_pt(c, "comentário", "comentários"))
        if com_alcance:
            tot += ", %d de alcance, %d visualizações, %d partilhas e %d guardados" % (
                sum(num(it["alcance"]) for it in todos), sum(num(it["plays"]) for it in todos),
                sum(num(it["partilhas"]) for it in todos), sum(num(it["guardados"]) for it in todos))
        L.append(tot + ".")

    if est_ig.bloqueio and ig:
        falta = ("Falta a permissão instagram_manage_insights no token da app Bora Social."
                 if est_ig.bloqueio.e_permissao else "Foi um erro da Meta, não de permissão; volto a tentar na próxima semana.")
        L.append("No Instagram a Meta só me deixou ler gostos e comentários: o alcance, as visualizações, as partilhas e os "
                 "guardados foram recusados (%s). %s" % (est_ig.bloqueio.curto(), falta))
    if est_fb.bloqueio and fb:
        vs = sum(num(it["views_campo"]) for it in fb)
        falta = ("Falta a permissão read_insights." if est_fb.bloqueio.e_permissao
                 else "Foi um erro da Meta, não de permissão; volto a tentar na próxima semana.")
        L.append("No Facebook também só vieram gostos e comentários (%s). %s "
                 "O campo views da Meta somou %d, mas sem insights não consigo confirmar que seja fiável." % (est_fb.bloqueio.curto(), falta, vs))

    if todos:
        L.append("Por ordem de alcance:" if com_alcance else
                 "Como a Meta não deu alcance, ordenei por gostos e comentários somados:")
        for i, it in enumerate(todos[:MAX_LINHAS_RANKING], 1):
            L.append("%d.º - %s" % (i, descreve(it, com_insights)))
        if len(todos) > MAX_LINHAS_RANKING:
            L.append("E mais %d com resultado igual ou pior." % (len(todos) - MAX_LINHAS_RANKING))

        score = (lambda it: num(it["alcance"])) if com_alcance else interacoes
        melhor, pior = todos[0], todos[-1]
        if len(todos) == 1:
            L.append("Só houve um, por isso não há comparação.")
        elif score(melhor) == score(pior):
            L.append("Ficaram todos empatados%s, por isso não há melhor nem pior nesta semana." % (
                " com zero gostos e zero comentários" if not com_alcance and score(melhor) == 0 else ""))
        else:
            L.append("O que mais correu bem: %s %s de %s. O pior: %s %s de %s." % (
                melhor["rede"], legenda_curta(melhor["legenda"], 40), melhor["quando"].astimezone(TZ).strftime("%d/%m"),
                pior["rede"], legenda_curta(pior["legenda"], 40), pior["quando"].astimezone(TZ).strftime("%d/%m")))

    L.append("Fonte: Graph API %s da Meta (conta profissional de Instagram e Página da Bora), gerado por relatorio_reels_semanal.py na VPS." % versao)
    return "\n".join(L)


# --------------------------------------------------------------------------- banco
def supa(metodo, caminho, url, chave, corpo=None, prefer=None):
    h = {"apikey": chave, "Authorization": "Bearer " + chave, "Content-Type": "application/json"}
    if prefer:
        h["Prefer"] = prefer
    data = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request("%s/rest/v1/%s" % (url, caminho), data=data, headers=h, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=45, context=CTX) as r:
            txt = r.read().decode("utf-8")
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        raise RuntimeError("%s %s -> HTTP %s %s" % (metodo, caminho.split("?")[0], e.code, e.read().decode("utf-8", "ignore")[:200]))


def gravar_pagina(pagina, titulo, conteudo, url, chave):
    q = urllib.parse.quote(pagina, safe="")
    _, existe = supa("GET", "claude_ai_memoria?select=pagina&pagina=eq.%s" % q, url, chave)
    agora = datetime.datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    corpo = {"titulo": titulo, "conteudo": conteudo, "origem": "claude-code", "atualizado_em": agora}
    if existe:
        st, _ = supa("PATCH", "claude_ai_memoria?pagina=eq.%s" % q, url, chave, corpo, "return=minimal")
        acao = "PATCH"
    else:
        corpo["pagina"] = pagina
        st, _ = supa("POST", "claude_ai_memoria", url, chave, corpo, "return=minimal")
        acao = "POST"
    # prova: ler de volta
    _, lida = supa("GET", "claude_ai_memoria?select=pagina,origem,conteudo&pagina=eq.%s" % q, url, chave)
    if not lida or lida[0].get("conteudo") != conteudo:
        raise RuntimeError("a pagina %s foi gravada (%s HTTP %s) mas a leitura de volta nao bate" % (pagina, acao, st))
    return acao, st, len(lida[0]["conteudo"]), lida[0].get("origem")


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seco", action="store_true", help="so imprime o texto, nao grava no banco")
    ap.add_argument("--data", help="AAAA-MM-DD da pagina (por omissao: hoje em Lisboa)")
    a = ap.parse_args()

    agora = datetime.datetime.now(UTC)
    desde = agora - datetime.timedelta(days=JANELA_DIAS)
    dia = a.data or agora.astimezone(TZ).strftime("%Y-%m-%d")
    pagina = "relatorio-semanal-reels-%s" % dia
    titulo = "Relatório semanal dos reels - %s" % dia

    envm = ler_env(ENV_META)
    envs = ler_env(ENV_SUPA)
    versao = envm.get("META_GRAPH_VERSION") or "v21.0"
    faltam = [k for k in ("META_PAGE_TOKEN", "META_PAGE_ID", "IG_USER_ID") if not envm.get(k)]
    est_ig, est_fb = EstadoInsights(), EstadoInsights()

    ok, motivo = portao_aberto()
    if faltam:
        texto = "Relatório semanal dos reels da Bora (%s): não consegui ler a Meta porque faltam no .env da VPS: %s." % (dia, ", ".join(faltam))
        codigo = 1
    elif not ok:
        texto = ("Relatório semanal dos reels da Bora (%s): não li a Meta porque o portão de autenticação está fechado "
                 "(3 erros seguidos do publicador; só volta a tentar de hora a hora). Motivo registado: %s" % (dia, motivo or "sem texto"))
        codigo = 1
    else:
        try:
            ig = recolher_ig(envm, desde, versao, est_ig)
            fb = recolher_fb(envm, desde, versao, est_fb)
            texto = compor(ig, fb, est_ig, est_fb, agora, desde, versao)
            codigo = 0
        except GraphErro as e:
            texto = "Relatório semanal dos reels da Bora (%s): a Meta recusou a leitura básica - %s." % (dia, e.curto())
            codigo = 1

    print(texto)
    if a.seco:
        return codigo
    url, chave = (envs.get("SUPABASE_URL") or "").rstrip("/"), envs.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not url or not chave:
        print("ERRO: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY em falta nos .env", file=sys.stderr)
        return 2
    try:
        acao, st, comp, orig = gravar_pagina(pagina, titulo, texto, url, chave)
    except RuntimeError as e:
        print("ERRO ao gravar: %s" % e, file=sys.stderr)
        return 2
    print("\n[gravado] pagina=%s via %s HTTP %s, %d caracteres, origem=%s (lido de volta, igual)" % (pagina, acao, st, comp, orig))
    return codigo


if __name__ == "__main__":
    sys.exit(main())
