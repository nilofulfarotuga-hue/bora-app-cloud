#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""radar_opcoes.py — depois da revisao das 21:00, o radar AUTO-ANALISA-SE e manda ao Danilo ate 5 opcoes numeradas.

Missao sistema-conteudo-14-11, blocos 4.1, 4.3 e 4.5. Corre no HOST da VPS (/opt/data/rotinas), 21:30 de Lisboa.

  python3 radar_opcoes.py                      # caixa -> radar; analisa; verde -> despacho; resto -> 5 opcoes
  RADAR_SEM_ENVIO=1 python3 radar_opcoes.py    # mostra o que sairia (porteiro em ensaio), nao grava nada
  RADAR_TESTE=1 ...                            # marca a mensagem com "[teste do radar]"

Antes (medido 14/11): 333 pendentes e 244 novos sem acao; o resumo da revisao das 21:00 (tarefa do Claude.ai)
so ia para o Cortex; o Danilo nao recebia escolhas.
4.1: cada linha = o que e (mudar X em Y), o que se faz, quanto custa; a resposta "1 3 faz" vira tarefa no
     despacho (opcoes_danilo.py ler, de 3 em 3 min).
4.3: linhas da caixa_guardados com tipo='video' entram no radar_videos com nota 10 e prioridade (pesquisa
     'caixa:<id>'); sem youtube_id procura links no conteudo e na pagina do livro citada em `ref`; sem link
     nenhum regista no e2e_log (uma vez por linha). O estado da caixa NAO muda aqui: e do agente de segunda.
4.5: (adendo 14/11 12:30) cada novidade boa e comparada com o sistema inteiro e vira "mudar X em Y" (onde, o
     que, custo). Verde (sem dinheiro, sem contas, sem custo, sem publicar) vai sozinho para o despacho (no
     maximo RADAR_MAX_VERDES=3 por noite); o resto entra nas 5 opcoes.
"""
import json
import os
import re
import sys
import time
import urllib.parse

sys.path.insert(0, "/opt/data/rotinas")
import opcoes_danilo as O  # noqa: E402
import motor_claude as M  # noqa: E402

ENSAIO = os.environ.get("RADAR_SEM_ENVIO") == "1" or "--ensaio" in sys.argv
RUN = os.environ.get("RADAR_RUN_ID", "radar-opcoes")
VISTOS = os.path.join(O.PASTA, "caixa_videos_vistos.json")
RE_YT = re.compile(r"(?:youtu\.be/|[?&]v=|/shorts/|/embed/)([A-Za-z0-9_-]{11})")
MAX_VERDES = int(os.environ.get("RADAR_MAX_VERDES", "3"))
RE_VERM = re.compile(r"(?i)pago|paga |pre[cç]o|assinatura|stripe|cart[aã]o|pagamento|comiss|carteira|\brls\b|seguran|"
                     r"criar conta|abrir conta|conta nova|publicar|cobrar|vend[ae]|mensalidade|atualizar o hermes|reinici")

SISTEMA = """O sistema do Danilo (Guarda, Portugal):
- bora-app: app Bora em Flutter (cliente, estafeta, parceiro) com Supabase; entregas, mercados, TVDE, limpeza, reservas, Favores.
- painel-admin: painel web do Bora (PT-BR); tudo o que a app faz tem ecra la.
- em-dia: app Em Dia (prazos e papeis para brasileiros em Portugal) e o seu conteudo.
- sites: boraguarda.com, paginas de PMEs que vendemos, site do Jai.
- estudio-filme: BoraStudio (roteiros, vozes, clipes) e o filme "A Semente da Luz".
- fabrica-conteudo: reels, carrosseis, grupos do Facebook, Postiz; nichos novos gospel, pets, vida em Portugal, financas/IA.
- robos: Hermes/Emerson na VPS (agentes, fila despacho, porteiro do Telegram), Dipsy no PC, Claude Code no PC,
  Motor Bora (rotacao de motores gratis + credito Claude), radar de videos.
"""
CORES = ("verde = sem dinheiro, sem precos/pagamentos/carteiras, sem criar contas, custo 0, sem publicar nem mandar "
         "mensagens para fora, sem mexer em seguranca/RLS, sem atualizar ou reiniciar o Hermes, reversivel; "
         "amarelo = precisa de decisao do Danilo (custo, conta nova, publicar, vender a clientes); "
         "vermelho = dinheiro, seguranca ou coisa que nao se desfaz")

PROMPT = """Es o radar do Bora. Compara cada video abaixo com o sistema inteiro do Danilo e diz o que MUDAR e ONDE.
%s
Para CADA video escreve, em portugues simples e frases curtas (o Danilo ouve em voz alta, sem jargao):
- onde: uma destas: bora-app, painel-admin, em-dia, sites, estudio-filme, fabrica-conteudo, robos
- mudar: "Mudar X em Y" em ate 14 palavras
- o_que_e: ate 8 palavras (o que e a coisa)
- o_que_se_faz: ate 16 palavras (o que nos fazemos)
- custo: "0 €" se for gratis; senao o valor que o texto diz; "desconhecido" se nao se sabe
- cor: verde, amarelo ou vermelho. %s
Responde SO com JSON: [{"youtube_id": "...", "onde": "...", "mudar": "...", "o_que_e": "...", "o_que_se_faz": "...", "custo": "...", "cor": "..."}]

Videos:
%s
"""


def _hoje():
    return time.strftime("%d/%m")


def _limpa_acao(c):
    return re.sub(r"^(\[[^\]]*\]\s*)+", "", c.get("acao") or "").strip()


def _custo_zero(c):
    return bool(re.match(r"^\s*0\s*(€|eur|euros)?\s*$", str(c or ""), re.I))


# ------------------------------------------------------------------ 4.3 caixa -> radar
def caixa_para_radar():
    try:
        vistos = set(json.load(open(VISTOS)))
    except Exception:  # noqa: BLE001
        vistos = set()
    linhas = O.rest("caixa_guardados?tipo=eq.video&id=neq.7&estado=in.(guardado,analisado,em-curso,precisa-danilo)"
                    "&select=id,titulo,conteudo,ref&order=id")
    novos = 0
    for c in linhas:
        if c["id"] in vistos:
            continue
        texto = "%s\n%s" % (c.get("titulo") or "", c.get("conteudo") or "")
        ids = list(dict.fromkeys(RE_YT.findall(texto)))
        fonte = "conteudo"
        if not ids and c.get("ref"):
            p = O.rest("claude_ai_memoria?pagina=eq.%s&select=conteudo" % urllib.parse.quote(c["ref"]))
            if p:
                ids = list(dict.fromkeys(RE_YT.findall(p[0].get("conteudo") or "")))
                fonte = "pagina " + c["ref"]
        if not ids:
            if not ENSAIO:
                O.e2e("sistema-conteudo-14-11", "bloco-4.3-caixa-%d" % c["id"], "parcial",
                      "caixa #%d (tipo video) sem link do YouTube no conteudo nem na pagina %s: nao entra no radar; "
                      "fica para o agente de segunda ler o resumo." % (c["id"], c.get("ref")), RUN)
                vistos.add(c["id"])
            continue
        for vid in ids:
            linha = {"youtube_id": vid, "titulo": (c.get("titulo") or "video mandado pelo Danilo")[:200],
                     "link": "https://www.youtube.com/watch?v=" + vid, "tema": "danilo_mandou",
                     "pesquisa": "caixa:%d" % c["id"], "nota_utilidade": 10, "veredito": "pendente",
                     "acao": "[prioridade: o Danilo mandou, caixa #%d, %s] ver e aplicar" % (c["id"], fonte)}
            if not ENSAIO:
                O.rest("radar_videos?on_conflict=youtube_id", "POST", linha,
                       prefer="resolution=merge-duplicates,return=minimal")
            novos += 1
        if not ENSAIO:
            vistos.add(c["id"])
    if not ENSAIO:
        os.makedirs(O.PASTA, exist_ok=True)
        json.dump(sorted(vistos), open(VISTOS, "w"))
    return novos


# ------------------------------------------------------------------ candidatos
def candidatos(n=12):
    q = ("radar_videos?veredito=in.(pendente,novo)&nota_utilidade=gte.7"
         "&acao=not.like.*opcao%%20enviada*&acao=not.like.*escolhida%%20pelo*"
         "&select=youtube_id,titulo,tema,para,nota_utilidade,acao,link,pesquisa"
         "&order=nota_utilidade.desc,recolhido_em.desc&limit=%d" % (n * 3))
    linhas = O.rest(q)
    # o que o Danilo mandou (caixa) primeiro; depois variedade de tema/para
    linhas.sort(key=lambda l: (0 if str(l.get("pesquisa") or "").startswith("caixa:") else 1, -(l.get("nota_utilidade") or 0)))
    escolhidos, vistos = [], set()
    for l in linhas:
        chave = (l.get("tema"), l.get("para"))
        if chave in vistos and len(linhas) > n:
            continue
        vistos.add(chave)
        escolhidos.append(l)
        if len(escolhidos) >= n:
            break
    return escolhidos


# ------------------------------------------------------------------ 4.5 auto-analise
def analisar(cands):
    """-> (analise por video, nome do motor). Sem motor: tudo amarelo (nada vai sozinho para o despacho)."""
    linhas = "\n".join("- youtube_id=%s | tema=%s | para=%s | nota=%s | titulo=%s | acao=%s" % (
        c["youtube_id"], c.get("tema"), c.get("para"), c.get("nota_utilidade"), (c.get("titulo") or "")[:90],
        _limpa_acao(c)[:300]) for c in cands)
    try:
        txt, modelo, perfil, tent = M.pedir(PROMPT % (SISTEMA, CORES, linhas), 2500, origem="radar-opcoes")
        lista = M.json_de(txt)
        por_id = {c["youtube_id"]: c for c in cands}
        saida = [dict(x, _c=por_id[x["youtube_id"]]) for x in lista if x.get("youtube_id") in por_id]
        if saida:
            return saida, "%s via %s" % (modelo, perfil)
    except Exception as e:  # noqa: BLE001
        tent = [str(e)[:200]]
    saida = []
    for c in cands:
        acao = _limpa_acao(c)
        saida.append({"youtube_id": c["youtube_id"], "onde": c.get("para") or "?", "mudar": "",
                      "o_que_e": (c.get("titulo") or "")[:60], "o_que_se_faz": acao[:110] or "ver o video e aplicar",
                      "custo": "pode ter custo, vejo antes" if RE_VERM.search(acao) else "0 €", "cor": "amarelo", "_c": c})
    return saida, "sem motor (%s)" % "; ".join(tent)[:150]


def e_verde(x):
    texto = " ".join([x.get("mudar") or "", x.get("o_que_se_faz") or "", _limpa_acao(x["_c"])])
    return str(x.get("cor", "")).lower() == "verde" and _custo_zero(x.get("custo")) and not RE_VERM.search(texto)


def despachar_verde(x):
    c = x["_c"]
    link = c.get("link") or "https://www.youtube.com/watch?v=" + c["youtube_id"]
    mudar = (x.get("mudar") or x["o_que_e"]).strip()
    tarefa = ("MISSAO: radar-auto-%s\nO radar comparou este video com o sistema e a mudanca e VERDE (sem dinheiro, sem "
              "contas, sem custo, sem publicar): %s (onde: %s). O que se faz: %s.\nVideo: %s (tema %s, nota %s).\n"
              "Acao do radar: %s\nRegras: so o seguro e reversivel; se afinal precisar de dinheiro, conta, publicar ou "
              "mexer em seguranca, para e fica a-espera-do-danilo com o passo numa linha.\n"
              "FEITO quando: resultado nesta linha com o que mudou e a prova (ficheiro, e2e_log ou SELECT)."
              % (c["youtube_id"], mudar, x.get("onde"), x["o_que_se_faz"], link, c.get("tema"), c.get("nota_utilidade"),
                 _limpa_acao(c)[:600]))
    did = O.criar_despacho("radar auto (verde): " + mudar[:150], tarefa, para="emerson", origem="agente", prioridade=45)
    O.rest("radar_videos?youtube_id=eq.%s" % c["youtube_id"], "PATCH",
           {"veredito": "despachado", "revisto_em": O.agora_iso(),
            "acao": "[radar auto %s verde: despacho #%s; %s em %s] %s" % (_hoje(), did, mudar, x.get("onde"),
                                                                          c.get("acao") or "")}, prefer="return=minimal")
    return did


def opcao_de(x):
    c = x["_c"]
    link = c.get("link") or "https://www.youtube.com/watch?v=" + c["youtube_id"]
    o_que_e = (x.get("mudar") or x["o_que_e"]).strip()
    tarefa = ("MISSAO: radar-escolha-%s\nO Danilo escolheu esta opcao do radar: %s (onde: %s). O que se faz: %s. "
              "Custo dito: %s.\nVideo: %s (tema %s, nota %s).\nAcao escrita pelo radar: %s\n"
              "Regras: so o que e seguro e reversivel; nada de pagar, criar contas, publicar ou mandar mensagens para fora "
              "sem o autorizo dele (se for preciso, fica a-espera-do-danilo com o passo numa linha).\n"
              "FEITO quando: resultado nesta linha com o que foi feito e a prova (ficheiro, e2e_log ou SELECT)."
              % (c["youtube_id"], o_que_e, x.get("onde"), x["o_que_se_faz"], x.get("custo"), link, c.get("tema"),
                 c.get("nota_utilidade"), _limpa_acao(c)[:600]))
    return {"o_que_e": o_que_e, "o_que_se_faz": x["o_que_se_faz"], "custo": x.get("custo") or "0 €",
            "titulo": "radar escolhido: " + o_que_e[:120], "tarefa": tarefa, "para": "emerson",
            "ref": {"radar": c["youtube_id"]}}


def main():
    n_caixa = caixa_para_radar()
    cands = candidatos()
    if not cands:
        O.e2e("radar-opcoes", "noite", "ok", "sem candidatos novos (nada a mandar)", RUN)
        print("sem candidatos")
        return 0
    analise, motor = analisar(cands)
    verdes = [x for x in analise if e_verde(x)][:MAX_VERDES]
    resto = [x for x in analise if x not in verdes][:5]
    despachados = []
    for x in verdes:
        mudar = x.get("mudar") or x["o_que_e"]
        despachados.append(("ensaio" if ENSAIO else despachar_verde(x), mudar, x.get("onde")))
    opcoes = [opcao_de(x) for x in resto]
    nv = len(despachados)
    cab = "Radar de hoje: pus a fazer sozinho %d %s. Estas %d precisam de ti. Escolhe:" % (
        nv, "coisa verde" if nv == 1 else "coisas verdes", len(opcoes))
    if os.environ.get("RADAR_TESTE") == "1":
        cab = "[teste do radar] " + cab
    if ENSAIO:
        cab = "[ensaio] " + cab
    msg, r = O.enviar_opcoes("radar-opcoes", cab, opcoes, ensaio=ENSAIO, run_id=RUN)
    r = r or {}
    print(msg)
    print(json.dumps({k: r.get(k) for k in ("ok", "ensaio", "nivel", "destino", "ids_texto", "porque")}, ensure_ascii=False))
    print("verdes para o despacho: %s" % json.dumps(despachados, ensure_ascii=False))
    print("motor: %s | caixa->radar: %d | analisados: %d" % (motor, n_caixa, len(analise)))
    if not ENSAIO:
        O.e2e("radar-opcoes", "noite", "ok" if r.get("ok") else "falhou",
              "analisados=%d verdes=%s opcoes=%d destino=%s ids=%s motor=%s" % (
                  len(analise), [d[0] for d in despachados], len(opcoes), r.get("destino"), r.get("ids_texto"), motor), RUN)
    if not ENSAIO and r.get("ok"):
        for i, x in enumerate(resto, 1):
            c = x["_c"]
            O.rest("radar_videos?youtube_id=eq.%s" % c["youtube_id"], "PATCH",
                   {"acao": "[opcao enviada %s n.%d] %s" % (_hoje(), i, c.get("acao") or "")}, prefer="return=minimal")
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
