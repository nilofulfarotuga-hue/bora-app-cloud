#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""agente_segunda.py — o agente de segunda-feira: pega no que o Danilo guardou, analisa, faz o verde e pergunta o resto.

Missao sistema-conteudo-14-11, blocos 5.1 a 5.4. Corre no HOST da VPS (/opt/data/rotinas), como root.

  python3 agente_segunda.py correr [--ensaio] [--ids 1,2,3]   # a corrida (segunda 08:00 de Lisboa pelo cron)
  python3 agente_segunda.py verificar                         # de 5 em 5 min: botao "Correr agora" do painel + fecho da caixa

O que le: caixa_guardados com estado 'guardado' (NUNCA a linha 7, que e a missao que criou isto), o topo do radar
pendente (nota >= 8, ainda nao oferecido) e as propostas pendentes do Cortex (mesma regra do cortex-mcp:
proposals.jsonl menos as rejeitadas e as ja encaminhadas). Classifica com o motor (motor_claude.py: Claude Haiku 5.5
pelo credito da API primeiro, rotacao gratis do Motor Bora depois):
  verde    -> tarefa no despacho (para=emerson) e o Emerson faz; caixa fica 'em-curso' com o numero da tarefa
  amarelo/vermelho -> mensagem numerada ao Danilo (max 5, opcoes_danilo.py); caixa fica 'precisa-danilo'
  coberto  -> ja ha trabalho em curso que o cobre; caixa fica 'em-curso' com o motivo
Quando a tarefa do despacho acaba, o `verificar` passa a caixa a 'feito' com feito_em (ou 'precisa-danilo' se falhou).

Contrato com o painel admin (botao "Correr agora"): o painel faz
  insert into public.despacho (origem, para, tipo, titulo, tarefa, prioridade, estado)
  values ('painel-admin','agente-segunda','tarefa','agente-segunda: correr agora','...',90,'aberta')
e o `verificar` apanha a linha (qualquer origem, para='agente-segunda'), poe 'executando', corre e fecha com
'feita' ou 'falhou', `resultado` e `prova`. O emerson.py ignora para='agente-segunda' desde 14/11.
"""
import datetime as dt
import json
import os
import re
import sys
import time

sys.path.insert(0, "/opt/data/rotinas")
import opcoes_danilo as O  # noqa: E402
import motor_claude as M  # noqa: E402

RUN = "agente-segunda"
LINHA_PROIBIDA = 7     # a missao sistema-conteudo-14-11 ('em-curso'): nunca se toca
PROPOSALS = "/opt/data/cortex-brain/.claude/.ai/knowledge/inbox/_reports/proposals.jsonl"
FILA_CORTEX = "/opt/data/cortex-brain/orquestracao"
MAX_VERDES = int(os.environ.get("AGENTE_MAX_VERDES", "6"))
CORTEX_TRATADAS = os.path.join(O.PASTA, "cortex_tratadas.json")   # pid -> despacho/opcao (o Cortex nao sabe)


def _cortex_tratadas():
    try:
        return json.load(open(CORTEX_TRATADAS))
    except Exception:  # noqa: BLE001
        return {}


def _marcar_cortex(pid, valor):
    d = _cortex_tratadas()
    d[pid] = valor
    os.makedirs(O.PASTA, exist_ok=True)
    json.dump(d, open(CORTEX_TRATADAS, "w"), indent=1)
RE_VERM = re.compile(r"(?i)pre[cç]o|stripe|pagamento|comiss|carteira|\brls\b|criar conta|abrir conta|conta nova|"
                     r"publicar|cobrar|reinici|atualizar o hermes|apagar")

PROMPT = """Es o agente de segunda-feira do Bora. O Danilo (fundador, nao programador, ouve as mensagens em voz alta)
guardou coisas para alguem pegar, analisar e fazer. Para CADA item abaixo decide a cor:
- verde: da para fazer ja sem dinheiro, sem precos/pagamentos/carteiras, sem criar contas, sem custo, sem publicar,
  sem mandar mensagens a clientes ou parceiros, sem mexer em seguranca/RLS, sem reiniciar o Hermes. Se o item for
  grande, a tarefa verde e SO o primeiro passo seguro (pesquisar, escrever o plano, o roteiro ou o rascunho) e o motivo
  diz o que fica para o Danilo.
- amarelo: precisa de uma decisao do Danilo (custo, conta nova, publicar, escolher entre caminhos).
- vermelho: dinheiro, seguranca ou coisa que nao se desfaz.
- coberto: ja ha trabalho em curso que faz isto. Se o item aparece em "Em curso" (pelo numero da caixa ou pelo assunto),
  a cor e SEMPRE coberto, nunca verde.
Escreve em portugues simples, frases curtas, sem jargao:
- motivo: ate 15 palavras
- o_que_e: ate 8 palavras; o_que_se_faz: ate 16 palavras; custo: "0 €", um valor, ou "desconhecido"
- tarefa (so se verde): o que o agente faz, passo a passo curto, e a linha "FEITO quando: ..." com a prova esperada
Responde SO com JSON: [{"chave": "...", "cor": "...", "motivo": "...", "o_que_e": "...", "o_que_se_faz": "...", "custo": "...", "tarefa": "..."}]

Em curso:
%s

Itens:
%s
"""


def agora():
    return O.agora_iso()


# ------------------------------------------------------------------ fontes
def caixa(ids=None):
    q = "caixa_guardados?estado=eq.guardado&id=neq.%d&select=*&order=prioridade.asc,id.asc" % LINHA_PROIBIDA
    if ids:
        q += "&id=in.(%s)" % ",".join(str(int(i)) for i in ids if int(i) != LINHA_PROIBIDA)
    return O.rest(q)


def radar_top(n=5):
    return O.rest("radar_videos?veredito=eq.pendente&nota_utilidade=gte.8&acao=not.like.*opcao%%20enviada*"
                  "&acao=not.like.*escolhida%%20pelo*&select=youtube_id,titulo,tema,para,nota_utilidade,acao,link"
                  "&order=nota_utilidade.desc,recolhido_em.desc&limit=%d" % n)


def cortex_pendentes(n=8):
    """A mesma regra do t_propostas_pendentes do cortex-mcp (server.mjs), lida do disco."""
    recs = []
    try:
        for ln in open(PROPOSALS, encoding="utf-8"):
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r and r.get("pid"):
                recs.append(r)
    except OSError:
        return []
    rej = {r.get("pid_original") for r in recs if r.get("tipo") == "rejeicao_proposta"} | set(_cortex_tratadas())
    out = []
    for r in reversed(recs):
        if r.get("tipo") == "rejeicao_proposta" or r["pid"] in rej:
            continue
        oid = re.sub(r"[^a-zA-Z0-9_-]", "-", str(r.get("id") or ("ordem-" + r["pid"])))[:80]
        if os.path.exists(os.path.join(FILA_CORTEX, oid + "-aprovado.md")) or \
           os.path.exists(os.path.join(FILA_CORTEX, oid + "-aprovado-chat.md")):
            continue
        out.append({"pid": r["pid"], "zona": r.get("zona"), "ts": r.get("ts"),
                    "texto": re.sub(r"\s+", " ", str(r.get("tarefa") or r.get("conteudo") or ""))[:400]})
        if len(out) >= n:
            break
    return out


def em_curso():
    linhas = []
    for d in O.rest("despacho?estado=in.(aberta,executando)&select=id,titulo&order=id.desc&limit=15"):
        linhas.append("- despacho #%s: %s" % (d["id"], d.get("titulo")))
    extra = os.environ.get("AGENTE_CONTEXTO", "").strip()
    if extra:
        linhas.append("- " + extra)
    return "\n".join(linhas) or "- nada"


# ------------------------------------------------------------------ corrida
def correr(ensaio=False, ids=None, prova=False):
    t0 = time.time()
    try:   # 4.3: videos novos da caixa entram no radar (nota 10) antes de tudo
        import radar_opcoes as R
        R.ENSAIO = ensaio
        n_caixa_radar = R.caixa_para_radar()
    except Exception as e:  # noqa: BLE001
        n_caixa_radar = "erro: %s" % str(e)[:80]
    cx, rd, ct = caixa(ids), radar_top(), cortex_pendentes()
    itens = {}
    for c in cx:
        itens["caixa:%d" % c["id"]] = ("caixa #%d (%s, prioridade %s): %s — %s" % (
            c["id"], c.get("tipo"), c.get("prioridade"), c.get("titulo"), (c.get("conteudo") or "")[:600]), c)
    for v in rd:
        itens["radar:%s" % v["youtube_id"]] = ("video do radar (nota %s, %s): %s — %s" % (
            v.get("nota_utilidade"), v.get("para"), (v.get("titulo") or "")[:90],
            re.sub(r"^(\[[^\]]*\]\s*)+", "", v.get("acao") or "")[:300]), v)
    for p in ct:
        itens["cortex:%s" % p["pid"]] = ("proposta do Cortex %s (zona %s): %s" % (p["pid"], p.get("zona"), p["texto"]), p)
    if not itens:
        return {"ok": True, "resumo": "nada guardado para analisar", "verdes": [], "opcoes": 0}
    lista = "\n".join("- chave=%s | %s" % (k, t) for k, (t, _o) in itens.items())
    em_curso_txt = em_curso()
    txt, modelo, perfil, tent = M.pedir(PROMPT % (em_curso_txt, lista), 3500, origem="agente-segunda")
    analise = [a for a in M.json_de(txt) if a.get("chave") in itens]
    # regra dura (prova de 14/11: o modelo pos a verde as caixas 4 e 5, que ja eram o trabalho em curso):
    # uma caixa citada em "Em curso" ("caixa 4", "caixa #4") e sempre coberta, diga o modelo o que disser.
    citadas = {int(x) for x in re.findall(r"caixa\s*#?\s*(\d+)", em_curso_txt, re.I)}
    for a in analise:
        if a["chave"].startswith("caixa:") and int(a["chave"].split(":")[1]) in citadas:
            a["cor"] = "coberto"
    motor = "%s via %s" % (modelo, perfil)

    verdes, perguntas, cobertos, fica = [], [], [], []
    for a in analise:
        cor = str(a.get("cor", "")).lower()
        texto = " ".join([a.get("tarefa") or "", a.get("o_que_se_faz") or ""])
        if cor == "verde" and a.get("tarefa") and not RE_VERM.search(texto) and len(verdes) < MAX_VERDES:
            verdes.append(a)
        elif cor == "coberto":
            cobertos.append(a)
        else:
            perguntas.append(a)
    # o que o Danilo guardou vem primeiro nas perguntas; so cabem 5
    perguntas.sort(key=lambda a: {"caixa": 0, "cortex": 1, "radar": 2}.get(a["chave"].split(":")[0], 3))
    fica, perguntas = perguntas[5:], perguntas[:5]

    feitos = []
    for a in verdes:
        k = a["chave"]
        tipo, ref = k.split(":", 1)
        titulo = "agente-segunda: " + (a.get("o_que_e") or k)[:150]
        tarefa = "MISSAO: agente-segunda-%s\nDe: %s\n%s\nRegras: so o seguro e reversivel; se precisar de dinheiro, contas, " \
                 "publicar ou mensagens para fora, para e fica a-espera-do-danilo com o passo numa linha." % (
                     k, itens[k][0][:500], a["tarefa"])
        did = "ensaio" if ensaio else O.criar_despacho(titulo, tarefa, para="emerson", origem="agente", prioridade=60)
        feitos.append((k, did))
        if ensaio:
            continue
        if tipo == "caixa" and int(ref) != LINHA_PROIBIDA:
            O.rest("caixa_guardados?id=eq.%d&id=neq.%d" % (int(ref), LINHA_PROIBIDA), "PATCH",
                   {"estado": "em-curso", "decisao": "verde: " + (a.get("motivo") or ""), "resultado": "despacho #%s" % did,
                    "analisado_em": agora()}, prefer="return=minimal")
        elif tipo == "cortex":
            _marcar_cortex(ref, "despacho #%s %s" % (did, time.strftime("%d/%m")))
        elif tipo == "radar":
            v = itens[k][1]
            O.rest("radar_videos?youtube_id=eq.%s" % ref, "PATCH",
                   {"veredito": "despachado", "revisto_em": agora(),
                    "acao": "[agente-segunda %s verde: despacho #%s] %s" % (time.strftime("%d/%m"), did, v.get("acao") or "")},
                   prefer="return=minimal")

    opcoes = []
    for a in perguntas:
        k = a["chave"]
        tipo, ref = k.split(":", 1)
        tarefa = ("MISSAO: agente-segunda-escolha-%s\nO Danilo escolheu: %s. O que se faz: %s. Custo dito: %s.\nDe: %s\n"
                  "Regras: o que precisar de dinheiro, contas ou publicar fica a-espera-do-danilo com o passo numa linha.\n"
                  "FEITO quando: resultado nesta linha com o que foi feito e a prova (ficheiro, e2e_log ou SELECT)."
                  % (k, a.get("o_que_e"), a.get("o_que_se_faz"), a.get("custo"), itens[k][0][:500]))
        refd = {"caixa": int(ref)} if tipo == "caixa" else ({"radar": ref} if tipo == "radar" else {"cortex": ref})
        opcoes.append({"o_que_e": a.get("o_que_e") or k, "o_que_se_faz": a.get("o_que_se_faz") or "decidir",
                       "custo": a.get("custo") or "desconhecido", "titulo": "agente-segunda escolhido: " + (a.get("o_que_e") or k)[:120],
                       "tarefa": tarefa, "para": "emerson", "ref": refd, "_a": a})
    nv = len(feitos)
    cab = "Agente de segunda: li %d coisas guardadas. Pus a fazer %d %s. Estas %d precisam de ti:" % (
        len(itens), nv, "verde" if nv == 1 else "verdes", len(opcoes))
    if prova:
        cab = "[agente de segunda — corrida de prova] " + cab
    if ensaio:
        cab = "[ensaio] " + cab
    if opcoes:
        msg, r = O.enviar_opcoes("agente-segunda", cab, [dict((k, v) for k, v in o.items() if k != "_a") for o in opcoes],
                                 ensaio=ensaio, run_id=RUN)
    else:
        msg = cab.replace(" Estas 0 precisam de ti:", " Nada precisa de ti hoje.")
        r = O.falar(msg, "agente-segunda", ensaio=ensaio)
    r = r or {}

    if not ensaio:
        for i, o in enumerate(opcoes, 1):
            a = o["_a"]
            if "caixa" in o["ref"] and o["ref"]["caixa"] != LINHA_PROIBIDA:
                O.rest("caixa_guardados?id=eq.%d&id=neq.%d" % (o["ref"]["caixa"], LINHA_PROIBIDA), "PATCH",
                       {"estado": "precisa-danilo", "decisao": "%s: %s (opcao %d enviada %s)" % (
                           a.get("cor"), a.get("motivo"), i, time.strftime("%d/%m %H:%M")), "analisado_em": agora()},
                       prefer="return=minimal")
            if "cortex" in o["ref"]:
                _marcar_cortex(o["ref"]["cortex"], "opcao %d enviada %s" % (i, time.strftime("%d/%m")))
            if "radar" in o["ref"]:
                v = itens["radar:" + o["ref"]["radar"]][1]
                O.rest("radar_videos?youtube_id=eq.%s" % o["ref"]["radar"], "PATCH",
                       {"acao": "[opcao enviada %s agente-segunda n.%d] %s" % (time.strftime("%d/%m"), i, v.get("acao") or "")},
                       prefer="return=minimal")
        for a in cobertos + fica:
            tipo, ref = a["chave"].split(":", 1)
            if tipo == "caixa" and int(ref) != LINHA_PROIBIDA:
                est = "em-curso" if a in cobertos else "analisado"
                dec = ("coberto: " if a in cobertos else "fica para a proxima segunda (so cabem 5 perguntas): ") + (a.get("motivo") or "")
                O.rest("caixa_guardados?id=eq.%d&id=neq.%d" % (int(ref), LINHA_PROIBIDA), "PATCH",
                       {"estado": est, "decisao": dec, "analisado_em": agora()}, prefer="return=minimal")
    resumo = ("itens=%d (caixa %d, radar %d, cortex %d) verdes->despacho=%s perguntas=%d cobertos=%s fica=%d "
              "caixa->radar=%s motor=%s porteiro destino=%s ids=%s em %ds" % (
                  len(itens), len(cx), len(rd), len(ct), feitos, len(opcoes), [a["chave"] for a in cobertos], len(fica),
                  n_caixa_radar, motor, r.get("destino"), r.get("ids_texto"), int(time.time() - t0)))
    if not ensaio:
        O.e2e(RUN, "corrida", "ok" if r.get("ok") else "parcial", resumo, RUN)
    return {"ok": bool(r.get("ok")), "resumo": resumo, "mensagem": msg, "verdes": feitos, "opcoes": len(opcoes),
            "porteiro": {k: r.get(k) for k in ("destino", "ids_texto", "nivel")}}


# ------------------------------------------------------------------ verificar (painel + fecho da caixa)
def fechar_caixa():
    n = 0
    for c in O.rest("caixa_guardados?estado=eq.em-curso&id=neq.%d&resultado=like.despacho*&select=id,resultado" % LINHA_PROIBIDA):
        m = re.match(r"despacho #(\d+)", c.get("resultado") or "")
        if not m:
            continue
        d = O.rest("despacho?id=eq.%s&select=estado,resultado,terminada_em" % m.group(1))
        if not d or d[0]["estado"] not in ("feita", "falhou"):     # cancelada: quem cancelou escreve a caixa
            continue
        d = d[0]
        novo = {"resultado": ("%s | %s: %s" % (c["resultado"], d["estado"], (d.get("resultado") or "")[:400]))[:1500]}
        if d["estado"] == "feita":
            novo.update(estado="feito", feito_em=d.get("terminada_em") or agora())
        else:
            novo.update(estado="precisa-danilo")
        O.rest("caixa_guardados?id=eq.%d&id=neq.%d" % (c["id"], LINHA_PROIBIDA), "PATCH", novo, prefer="return=minimal")
        n += 1
    return n


def verificar():
    pedidos = O.rest("despacho?para=eq.agente-segunda&estado=eq.aberta&select=id,origem,titulo,tarefa&order=id.asc")
    for p in pedidos:
        O.rest("despacho?id=eq.%d&estado=eq.aberta" % p["id"], "PATCH",
               {"estado": "executando", "iniciada_em": agora()}, prefer="return=minimal")
        try:
            ensaio = "[ensaio]" in (p.get("tarefa") or "")      # o painel pode testar o botao sem efeitos
            r = correr(ensaio=ensaio)
            O.rest("despacho?id=eq.%d" % p["id"], "PATCH",
                   {"estado": "feita" if r["ok"] else "falhou",
                    "resultado": ("[ensaio, nada gravado nem enviado] " if ensaio else "") + r["resumo"][:1850],
                    "prova": "e2e_log fluxo agente-segunda passo corrida; porteiro %s" % json.dumps(r.get("porteiro")),
                    "terminada_em": agora()}, prefer="return=minimal")
        except Exception as e:  # noqa: BLE001
            O.rest("despacho?id=eq.%d" % p["id"], "PATCH",
                   {"estado": "falhou", "resultado": "erro: %s" % str(e)[:500], "prova": "agente_segunda.py verificar",
                    "terminada_em": agora()}, prefer="return=minimal")
            O.e2e(RUN, "pedido-painel", "falhou", "despacho #%d: %s" % (p["id"], str(e)[:300]), RUN)
    n = fechar_caixa()
    if pedidos or n:
        print("pedidos=%s caixa_fechadas=%d" % ([p["id"] for p in pedidos], n))
    return 0


if __name__ == "__main__":
    a = sys.argv[1:] or ["verificar"]
    if a[0] == "correr":
        ids = None
        if "--ids" in a:
            ids = [int(x) for x in a[a.index("--ids") + 1].split(",") if x.strip()]
        res = correr(ensaio="--ensaio" in a, ids=ids, prova="--prova" in a)
        print(res.get("mensagem") or "")
        print(res["resumo"])
        sys.exit(0 if res["ok"] else 1)
    if a[0] == "verificar":
        sys.exit(verificar())
    print(__doc__)
