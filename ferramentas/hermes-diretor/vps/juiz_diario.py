#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
juiz_diario.py — o juiz diario das conversas dos robos (missao hermes-diretor-2026-11-20, B6.2).

Todos os dias as 03:30 de Lisboa le TODAS as conversas da vespera do suporte, do Amigo Bora e do WhatsApp da
loja; tira os factos que o robo afirmou (botao, preco, horario, zona, tokens, app); confere os botoes com o
MAPA DA APP (lido do codigo) e as regras com as licoes que ja existem; e, quando o erro e confirmado, grava a
licao em licoes_robos (se ja existe, soma) e um caso de teste (pergunta real + o que a resposta deve e nao
pode ter). 1.a passagem em Haiku; so os casos duvidosos vao ao Sonnet.

Privacidade: as conversas tem dados de clientes, por isso SO vao ao Claude (pelo porteiro). Se o Claude nao
responder, a corrida pára: nunca cai nos motores gratis. Telefones e emails sao tapados antes de sair, e nas
licoes nunca entram dados pessoais.

Corre no HOST como root (a chave da base so existe ai).
  juiz_diario.py                 a vespera (dia de Lisboa)
  juiz_diario.py 2026-11-21      esse dia
  juiz_diario.py --seco [dia]    julga e mostra, sem gravar licoes nem casos
"""
import datetime
import hashlib
import json
import re
import sys
import time
import unicodedata
import urllib.request

sys.path.insert(0, "/opt/data/rotinas")
import despachante as D  # noqa: E402  (acesso a base com a chave do host)

PORTEIRO = "http://127.0.0.1:8792/v1/chat/completions"
MAPA = "/root/hermes-diretor/mapa_app.json"
PENDENTES = "/root/hermes-diretor/casos_pendentes.jsonl"
SECO = "--seco" in sys.argv
ROBOS = ("suporte", "amigo", "whatsapp")


def norm(t):
    t = unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]+", " ", t)).strip()


def tapar(t):
    t = re.sub(r"[\w.+-]+@[\w-]+\.[\w.-]+", "<email>", t or "")
    t = re.sub(r"(?<!\d)(\+?\d[\d ().-]{7,}\d)(?!\d)", "<numero>", t)
    return t


def claude(perfil, sistema, texto, max_tokens=700):
    corpo = json.dumps({"model": "perfil:" + perfil, "temperature": 0, "max_tokens": max_tokens,
                        "messages": [{"role": "system", "content": sistema}, {"role": "user", "content": texto}]}).encode()
    req = urllib.request.Request(PORTEIRO, data=corpo, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.load(r)
    bruto = d["choices"][0]["message"]["content"]
    m = re.search(r"\{.*\}", bruto, re.S)
    return json.loads(m.group(0)) if m else {}


def dia_lisboa(arg):
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Europe/Lisbon")
    except Exception:
        tz = datetime.timezone.utc
    dia = datetime.date.fromisoformat(arg) if arg else (datetime.datetime.now(tz).date() - datetime.timedelta(days=1))
    ini = datetime.datetime.combine(dia, datetime.time.min, tz).astimezone(datetime.timezone.utc)
    fim = ini + datetime.timedelta(days=1)
    f = "%Y-%m-%dT%H:%M:%SZ"
    return dia, ini.strftime(f), fim.strftime(f)


def conversas(ini, fim):
    """{robo: {chave_da_conversa: [(quem, texto)]}}"""
    q = "&created_at=gte.%s&created_at=lt.%s&order=created_at.asc&limit=2000" % (ini, fim)
    out = {r: {} for r in ROBOS}
    for robo, caminho, chave in (("suporte", "support_chatbot_messages?select=session_id,role,content", "session_id"),
                                 ("amigo", "assistant_chat_messages?select=conversation_id,role,content", "conversation_id")):
        for l in D._rest(caminho + q) or []:
            if l.get("role") not in ("user", "assistant", "admin") or not (l.get("content") or "").strip():
                continue
            quem = {"user": "CLIENTE", "assistant": "ROBO", "admin": "EQUIPA"}[l["role"]]
            out[robo].setdefault(str(l[chave]), []).append((quem, tapar(l["content"])[:900]))
    for l in D._rest("whatsapp_messages?select=numero,direcao,texto" + q) or []:
        if not (l.get("texto") or "").strip():
            continue
        chave = "wa-" + hashlib.md5(str(l.get("numero")).encode()).hexdigest()[:10]   # nunca o numero
        out["whatsapp"].setdefault(chave, []).append(("CLIENTE" if l.get("direcao") == "entrada" else "ROBO", tapar(l["texto"])[:900]))
    return out


def licoes_ativas():
    por = {r: [] for r in ROBOS}
    for l in D._rest("licoes_robos?ativa=is.true&arquivada_em=is.null&select=id,robo,regra,vezes&order=vezes.desc&limit=300") or []:
        if l.get("robo") in por:
            por[l["robo"]].append(l)
    return por


def no_mapa(mapa, alvo):
    a = norm(alvo)
    if len(a) < 4:
        return None
    return [m for m in mapa if a in norm(m.get("elemento")) or norm(m.get("elemento")) == a][:3]


def mesma(a, b):
    pa, pb = set(w for w in norm(a).split() if len(w) > 3), set(w for w in norm(b).split() if len(w) > 3)
    return bool(pa and pb) and len(pa & pb) / float(len(pa | pb)) >= 0.5


SIS1 = ("Es o fiscal das conversas dos robos do Bora (app de entregas e servicos da Guarda). Le a conversa e devolve "
        "SO JSON, sem texto a mais: {\"afirmacoes\":[{\"tipo\":\"botao|preco|horario|zona|tokens|app|outro\",\"texto\":\"<o que o "
        "ROBO afirmou, curto>\",\"alvo\":\"<nome do botao, menu ou ecra referido, ou vazio>\"}],\"suspeita\":true|false,"
        "\"porque\":\"<1 frase>\"}. Afirmacao = facto que o ROBO disse ao cliente e que se pode conferir. suspeita=true se o "
        "robo pode ter inventado algo, contrariou uma das REGRAS, mandou o cliente para um sitio da app que pode nao existir, "
        "ou deixou a pergunta sem resposta. Conversa normal e correta: suspeita=false. Nunca copies telefones, emails ou nomes.")
SIS2 = ("Es o fiscal. Decide se o ROBO ERROU nesta conversa. So e ERRO quando o robo CONTRARIA um facto que tens a frente: "
        "uma linha dos FACTOS DO NEGOCIO, uma das REGRAS, ou a CONFERENCIA DO MAPA DA APP (lista real de botoes lida do "
        "codigo). Se o robo disse uma coisa que NAO consegues conferir com esses dados (um preco, um prazo, um horario que "
        "nao esta nos factos), isso NAO e erro: e \"por_conferir\". Nunca inventes uma regra a proibir o robo de dizer coisas "
        "que podem ser verdade. Devolve SO JSON: {\"erro\":true|false,\"facto_contrariado\":\"<copia a linha exata dos FACTOS, "
        "das REGRAS ou da CONFERENCIA que o robo contrariou; vazio se nao houver>\",\"por_conferir\":[\"<afirmacao do robo que "
        "nao deu para conferir>\"],\"errou\":\"<o que o robo errou, 1 frase, sem dados pessoais>\",\"regra\":\"<a regra certa, "
        "1 a 2 frases, para o robo ler no futuro>\",\"pergunta_teste\":\"<a pergunta do cliente, generica, sem dados "
        "pessoais>\",\"deve_conter\":[\"<palavra ou expressao curta>\"],\"nao_pode_conter\":[\"<palavra ou expressao curta>\"],"
        "\"confianca\":<0 a 1>}.")


def factos_do_negocio():
    """O que o juiz tem para conferir: o glossario do Bora e as regras de negocio do Danilo (ficheiros do Hermes)."""
    partes = []
    try:
        partes.append(open("/opt/data/CONTEXT-BORA.md", encoding="utf-8").read()[:7000])
    except Exception:
        pass
    try:
        livro = open("/opt/data/LIVRO-AO-ACORDAR.md", encoding="utf-8").read()
        m = re.search(r"## 8\. Regras de neg.cio.*?(?=\n## |\Z)", livro, re.S)
        if m:
            partes.append(m.group(0)[:2500])
    except Exception:
        pass
    return "\n\n".join(partes) or "(sem factos: nada se pode dar como erro alem do mapa da app)"


def provado(p2, factos, bloco_regras, conf):
    """Erro PROVADO = o juiz copiou a linha que o robo contrariou e essa linha existe mesmo nos dados que recebeu."""
    fc = norm(p2.get("facto_contrariado"))
    if len(fc) < 15:
        return False
    onde = norm(factos + "\n" + bloco_regras + "\n" + "\n".join(conf))
    return fc[:60] in onde


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dia, ini, fim = dia_lisboa(args[0] if args else None)
    convs = conversas(ini, fim)
    regras = licoes_ativas()
    try:
        mapa = [m for m in json.load(open(MAPA, encoding="utf-8")) if m.get("app") in ("cliente", "estafeta", "parceiro")]
    except Exception:
        mapa = []
    total = {r: len(convs[r]) for r in ROBOS}
    n_msgs = sum(len(v) for r in ROBOS for v in convs[r].values())
    achados, duvidosos, haiku, sonnet, falhas, por_conferir = [], 0, 0, 0, 0, 0
    factos = factos_do_negocio()
    for robo in ROBOS:
        bloco_regras = "\n".join("- " + l["regra"] for l in regras[robo][:20]) or "(sem regras ainda)"
        for chave, falas in convs[robo].items():
            if not any(q == "ROBO" for q, _ in falas):
                continue
            texto = "\n".join("%s: %s" % f for f in falas)[-6000:]
            try:
                p1 = claude("claude-volume", SIS1, "REGRAS:\n%s\n\nCONVERSA (%s):\n%s" % (bloco_regras, robo, texto))
                haiku += 1
            except Exception as e:  # noqa: BLE001 - sem Claude nao se julga (nunca gratis: sao dados de clientes)
                falhas += 1
                print("PARO: o Claude nao respondeu (%s). Conversas de clientes nao vao a motores gratis." % str(e)[:120])
                break
            conf = []
            for a in p1.get("afirmacoes") or []:
                if a.get("tipo") == "botao" and a.get("alvo") and mapa:
                    onde = no_mapa(mapa, a["alvo"])
                    if onde is not None:
                        conf.append("botao/ecra \"%s\": %s" % (a["alvo"][:60], ("EXISTE em " + ", ".join("%s/%s" % (m["app"], m["ecra"]) for m in onde)) if onde else "NAO ENCONTRADO no mapa da app"))
            if not p1.get("suspeita") and not any("NAO ENCONTRADO" in c for c in conf):
                continue
            duvidosos += 1
            try:
                p2 = claude("claude-decisao", SIS2, "FACTOS DO NEGOCIO:\n%s\n\nREGRAS:\n%s\n\nCONFERENCIA DO MAPA DA APP:\n%s\n\nSUSPEITA DA 1.a PASSAGEM: %s\n\nCONVERSA (%s):\n%s"
                            % (factos, bloco_regras, "\n".join(conf) or "(nada a conferir)", p1.get("porque", ""), robo, texto), 700)
                sonnet += 1
            except Exception as e:  # noqa: BLE001
                falhas += 1
                print("PARO: o Claude (Sonnet) nao respondeu (%s)." % str(e)[:120])
                break
            por_conferir += len(p2.get("por_conferir") or [])
            if p2.get("erro") and float(p2.get("confianca") or 0) >= 0.7 and p2.get("regra"):
                p2["_provado"] = provado(p2, factos, bloco_regras, conf)
                achados.append((robo, chave, p2, conf))
    gravadas, somadas, casos = 0, 0, 0
    for robo, chave, p2, conf in achados:
        print("%s [%s %s] %s -> %s (confianca %s; contrariou: %s)" % ("ERRO PROVADO" if p2["_provado"] else "ERRO POR REVER", robo, chave[:12],
              p2.get("errou", "")[:140], p2.get("regra", "")[:160], p2.get("confianca"), (p2.get("facto_contrariado") or "-")[:110]))
        if SECO:
            continue
        if not p2["_provado"]:
            # sem a linha do facto contrariado nao e licao: fica desligada, para rever no painel (nunca ensina o robo sozinha)
            D._rest("licoes_robos", "POST", {"robo": robo, "errou": ("[POR REVER] " + p2.get("errou", ""))[:600], "regra": p2["regra"][:600],
                                             "origem": "fiscal-por-rever", "vezes": 1, "ativa": False})
            continue
        igual = next((l for l in regras[robo] if mesma(l["regra"], p2["regra"])), None)
        if igual:
            D._rest("licoes_robos?id=eq.%s" % igual["id"], "PATCH", {"vezes": int(igual.get("vezes") or 1) + 1, "editada_em": "now()"})
            somadas += 1
            lid = igual["id"]
        else:
            D._rest("licoes_robos", "POST", {"robo": robo, "errou": p2.get("errou", "")[:600], "regra": p2["regra"][:600], "origem": "fiscal", "vezes": 1, "ativa": True})
            gravadas += 1
            lid = None
            regras[robo].append({"id": None, "regra": p2["regra"], "vezes": 1})
        caso = {"robo": robo, "pergunta": (p2.get("pergunta_teste") or "")[:500], "deve_conter": (p2.get("deve_conter") or [])[:6],
                "nao_pode_conter": (p2.get("nao_pode_conter") or [])[:6], "origem": "fiscal"}
        if caso["pergunta"]:
            if lid:
                caso["licao_id"] = lid
            if D._rest("robos_casos_teste", "POST", caso) is None:      # a tabela ainda nao existe: guarda para depois
                caso.pop("licao_id", None)
                with open(PENDENTES, "a", encoding="utf-8") as fh:
                    fh.write(json.dumps(dict(caso, dia=str(dia)), ensure_ascii=False) + "\n")
            casos += 1
    resumo = ("Juiz diario de %s: %d conversas (suporte %d, amigo %d, whatsapp %d), %d mensagens. 1.a passagem (Haiku): %d. "
              "Duvidosas vistas pelo Sonnet: %d. Erros provados: %d (licoes novas %d, repetidas %d, casos de teste %d). Por rever "
              "(sem facto que prove): %d. Afirmacoes que nao deu para conferir: %d. Falhas do motor: %d.%s"
              % (dia, sum(total.values()), total["suporte"], total["amigo"], total["whatsapp"], n_msgs, haiku, sonnet,
                 sum(1 for a in achados if a[2]["_provado"]), gravadas, somadas, casos, sum(1 for a in achados if not a[2]["_provado"]),
                 por_conferir, falhas, " (ENSAIO: nada gravado)" if SECO else ""))
    print(resumo)
    if not SECO:
        D._rest("e2e_log", "POST", {"fluxo": "juiz-diario", "passo": "dia-%s" % dia, "estado": "ok" if not falhas else "falhou",
                                    "device": "vps-juiz", "detalhe": resumo + " " + " | ".join("[%s] %s" % (r, p.get("errou", "")[:120]) for r, _, p, _ in achados)[:1500]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
