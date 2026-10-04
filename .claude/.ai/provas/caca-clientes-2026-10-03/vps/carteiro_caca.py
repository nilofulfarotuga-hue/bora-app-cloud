#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Carteiro do caca-clientes (missao caca-clientes-2026-10-03, Blocos 3 e 4).

PORQUE EXISTE: o `vendedor` escrevia mensagens que ninguem enviava. Este e o braco que
faltava: envia pela conta Bora (Gmail API), faz os dois seguimentos, le as respostas e
avisa o Danilo pelo Telegram com a resposta sugerida ja escrita.

Modos:
  redigir   escreve o email dos prospects com email verificado e peca pronta (motor gratis)
  enviar    dias uteis 09h40: ate 5 novos + seguimentos vencidos, 2-3 min entre envios
  ler       de hora a hora: respostas, recusas e devolucoes
  resumo    09h50: "hoje: N enviados, N seguimentos, N respostas" (cala-se sem novidade)
  teste     manda um email de teste para a propria conta Bora e guarda a conversa
  teste-ler le essa conversa de volta

Quem decide o que sai e a base de dados (RPC carteiro_fila): interruptor geral
`platform_settings.caca_clientes_enabled`, tecto de 5 novos por dia, janela 09h30-11h30.
Segredos em /opt/data/.env: PROSPECTS_KEY, GMAIL_BORA_CLIENT_ID, GMAIL_BORA_CLIENT_SECRET,
GMAIL_BORA_REFRESH_TOKEN. Nunca no repo.
"""
import base64
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from email.message import EmailMessage
from email.utils import formataddr, make_msgid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import E, SUPA_URL, dizer, registar_erro  # noqa: E402

CONTA = "boraappbora@gmail.com"
REMETENTE = formataddr(("Bora App - Guarda", CONTA))
ASSINATURA = "Bora App — Guarda"
RODAPE = ("--" + chr(10) + ASSINATURA + chr(10) + "boraguarda.com" + chr(10) +
          "Se preferir não receber mais mensagens nossas, basta responder «não».")
ROTEADOR = "http://172.16.1.1:8792/v1/chat/completions"
MODELO = "perfil:volume"
TESTE_FICH = "/opt/data/rotinas/carteiro_caca_teste.json"
LOG = "/var/log/carteiro-caca.log"
ANON = E.get("SUPABASE_ANON_KEY") or ""
CHAVE = E.get("PROSPECTS_KEY") or ""
RECUSA = ("não quero", "nao quero", "não estou interessad", "nao estou interessad", "não tenho interesse",
          "nao tenho interesse", "sem interesse", "não temos interesse", "nao temos interesse", "remov", "parem",
          "não me contact", "nao me contact", "unsubscribe", "deixem de", "não obrigad", "nao obrigad")
PROIBIDO = ("já está a funcionar com parceiros", "sou o danilo", "nunca fiz", "primeira vez que", "€", " eur")


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(linha + chr(10))
    except Exception:
        pass


def rpc(nome, corpo):
    corpo = dict(corpo)
    corpo["p_chave"] = CHAVE
    req = urllib.request.Request(SUPA_URL + "/rest/v1/rpc/" + nome, data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                                 headers={"apikey": ANON, "Authorization": "Bearer " + ANON, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        t = r.read().decode("utf-8")
    return json.loads(t) if t.strip() else None


def e2e(passo, estado, detalhe):
    try:
        rpc("carteiro_registo", {"p_passo": passo, "p_estado": estado, "p_detalhe": detalhe[:1800]})
    except Exception as ex:
        log("e2e falhou: %s" % ex)


# ------------------------------------------------------------------ Gmail
_tok = {}


def token():
    if _tok.get("v") and _tok.get("ate", 0) > time.time() + 60:
        return _tok["v"]
    faltam = [k for k in ("GMAIL_BORA_CLIENT_ID", "GMAIL_BORA_CLIENT_SECRET", "GMAIL_BORA_REFRESH_TOKEN") if not E.get(k)]
    if faltam:
        raise RuntimeError("sem autorizacao Gmail: faltam %s em /opt/data/.env" % ", ".join(faltam))
    dados = urllib.parse.urlencode({"client_id": E["GMAIL_BORA_CLIENT_ID"], "client_secret": E["GMAIL_BORA_CLIENT_SECRET"],
                                    "refresh_token": E["GMAIL_BORA_REFRESH_TOKEN"], "grant_type": "refresh_token"}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=dados), timeout=30) as r:
        d = json.loads(r.read().decode())
    _tok.update(v=d["access_token"], ate=time.time() + int(d.get("expires_in", 3000)))
    return _tok["v"]


def gmail(metodo, caminho, corpo=None):
    req = urllib.request.Request("https://gmail.googleapis.com/gmail/v1/users/me/" + caminho, method=metodo,
                                 data=json.dumps(corpo).encode() if corpo is not None else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def quem_sou():
    return gmail("GET", "profile").get("emailAddress", "")


def enviar_email(para, assunto, texto, thread_id=None, em_resposta_a=None):
    m = EmailMessage()
    m["From"] = REMETENTE
    m["To"] = para
    m["Subject"] = assunto
    m["Message-ID"] = make_msgid(domain="boraguarda.com")
    if em_resposta_a:
        m["In-Reply-To"] = em_resposta_a
        m["References"] = em_resposta_a
    m.set_content(texto.rstrip() + chr(10) + chr(10) + RODAPE + chr(10))
    corpo = {"raw": base64.urlsafe_b64encode(m.as_bytes()).decode()}
    if thread_id:
        corpo["threadId"] = thread_id
    r = gmail("POST", "messages/send", corpo)
    rfc = m["Message-ID"]
    try:  # o Gmail pode reescrever o Message-ID: le-se o que ficou
        meta = gmail("GET", "messages/%s?format=metadata&metadataHeaders=Message-ID" % r["id"])
        for h in meta.get("payload", {}).get("headers", []):
            if h.get("name", "").lower() == "message-id":
                rfc = h["value"]
    except Exception:
        pass
    return {"message_id": r["id"], "thread_id": r["threadId"], "rfc_message_id": rfc, "para": para}


def texto_de(payload):
    if payload.get("mimeType", "").startswith("text/plain") and payload.get("body", {}).get("data"):
        return base64.urlsafe_b64decode(payload["body"]["data"] + "==").decode("utf-8", "replace")
    for p in payload.get("parts", []) or []:
        t = texto_de(p)
        if t:
            return t
    return ""


def cabecalho(msg, nome):
    for h in msg.get("payload", {}).get("headers", []):
        if h.get("name", "").lower() == nome.lower():
            return h.get("value", "")
    return ""


def so_a_resposta(texto):
    """Corta a citacao do nosso email por baixo da resposta."""
    fora = []
    for linha in texto.splitlines():
        l = linha.strip()
        if l.startswith(">") or re.match(r"^(Em|On|No dia|A) .{5,80}(escreveu|wrote):?$", l) or "Bora App" in l and "<" in l:
            break
        fora.append(linha)
    return chr(10).join(fora).strip()[:3000]


# ------------------------------------------------------------------ motor gratis
def motor(sistema, pedido, tokens=500):
    corpo = {"model": MODELO, "max_tokens": tokens, "temperature": 0.6,
             "messages": [{"role": "system", "content": sistema}, {"role": "user", "content": pedido}]}
    req = urllib.request.Request(ROTEADOR, data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.loads(r.read().decode("utf-8"))
    return (d["choices"][0]["message"]["content"] or "").strip()


SISTEMA_REDATOR = """Escreves emails de primeiro contacto em nome da «Bora App — Guarda», em português de Portugal (nunca do Brasil).
Regras que não se quebram:
- No máximo 110 palavras no corpo. Tom humano, simples, de vizinho da Guarda. Trata por «vocês».
- Uma observação concreta sobre o negócio (o GANCHO dado), uma frase a dizer o que a Bora preparou para eles com o LINK dado (uma única vez, o endereço por extenso), e uma pergunta de fecho.
- Sem preços, sem valores, sem símbolo de euro. Sem promessas. Não inventes factos que não estejam nos dados.
- Nunca digas «sou o Danilo» nem fales na primeira pessoa do singular: é a Bora que escreve («preparámos», «reparámos»).
- Se falares da app Bora diz «em fase de arranque, app construída e a ser testada com alguns comerciantes da Guarda». Nunca digas que já funciona com parceiros a receber pedidos.
- Não assines: a assinatura é acrescentada depois.
Responde SÓ com JSON: {"assunto": "... (máximo 7 palavras)", "texto": "..."}"""

SISTEMA_PARCEIRO = SISTEMA_REDATOR + """
Este email é um convite para ser parceiro da app Bora: primeiro mês grátis, comissão só quando vende, sem mensalidade, estafetas da Guarda, pagamento por MB Way e cartão. Não escrevas percentagens."""


def validar(assunto, texto, link):
    erros = []
    if len(assunto.split()) > 7:
        erros.append("assunto com mais de 7 palavras")
    if len(texto.split()) > 120:
        erros.append("corpo com mais de 120 palavras")
    baixo = (assunto + " " + texto).lower()
    for p in PROIBIDO:
        if p in baixo:
            erros.append("contem «%s»" % p.strip())
    if link and texto.count(link) != 1:
        erros.append("o link tem de aparecer exactamente uma vez")
    if re.search(r"\bvocê\b|\bseu negócio\b|\bcelular\b|\bcadastr", baixo):
        erros.append("portugues do Brasil")
    return erros


FRASES = [
    ("nao tem site proprio", "ainda não têm um site próprio"),
    ("nao abre", None),  # so se confirma na hora, daqui (ver observacao())
    ("nao tem ligacao segura", "o vosso site não tem ligação segura (falta o https)"),
    ("nao esta preparado para telemovel", "o vosso site não está preparado para telemóvel"),
    ("livro de reclamacoes", "falta no vosso site a ligação ao livro de reclamações eletrónico, que a lei exige"),
]


def site_abre(url):
    for u in (url, url.replace("http://", "https://")):
        try:
            req = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=20) as r:
                if r.status < 400:
                    return True
        except Exception:
            pass
    return False


def observacao(p):
    """O gancho do cacador, em portugues escrito como deve ser. So entra o que foi medido;
    'o site nao abre' e confirmado outra vez daqui antes de se escrever a alguem."""
    gancho = p.get("gancho") or ""
    if any(c in gancho for c in "áéíóúãõç"):  # gancho escrito a mao (maquetes premium)
        return gancho.split(";")[0].strip().rstrip(".")
    partes = []
    for chave, frase in FRASES:
        if chave not in gancho:
            continue
        if frase is None:
            if p.get("website") and not site_abre(p["website"]):
                partes.append("o vosso site não está a abrir")
            continue
        partes.append(frase)
    partes = partes[:2]
    if not partes:
        return "há espaço para a vossa presença online trabalhar mais por vocês"
    return " e ".join(partes)


def escrever(p):
    """Email por molde fixo. O motor gratis escrevia frases que nao se mandam a ninguem
    (elogios inventados, "Mira Serra precisa de ajuda"): 03/10, 10 em 10 reprovados a olho."""
    nome, link = p.get("nome") or "", p.get("link") or ""
    curto = nome.split("(")[0].strip()
    assunto = "Uma página para %s" % curto
    if len(assunto.split()) > 7:
        assunto = "Preparámos uma página para vocês"
    if p.get("cliente_tipo") == "secretario-virtual":
        # Missao 03/10 bloco 5 (04/10): Secretario Virtual. Sem preco; numero de teste + codigo.
        assunto = "Um secretário no vosso WhatsApp"
        gancho = (p.get("gancho") or "Os pedidos por WhatsApp têm resposta fora de horas?").strip()
        texto = ("Bom dia,<P>Somos a Bora, da Guarda. Vimos que %s recebe marcações ou pedidos por WhatsApp. %s<P>"
                 "Criámos um Secretário Virtual: responde no WhatsApp do negócio a qualquer hora, marca na agenda, "
                 "lembra os clientes na véspera e pergunta-vos quando não sabe. Áudio tem resposta em áudio.<P>"
                 "Pode experimentar já, como se fosse um cliente: envie «TESTE %s» por WhatsApp para o %s. "
                 "O teste dura 7 dias.<P>Três conversas de exemplo:<L>%s<P>"
                 "Faz sentido conversarmos uns minutos?") % (
                     curto, gancho, p.get("codigo") or "", p.get("numero_teste") or "+351 937 501 673", link)
        return assunto, texto.replace("<P>", chr(10) + chr(10)).replace("<L>", chr(10))
    if p.get("cliente_tipo") == "parceiro-bora":
        if len(("%s na app Bora?" % curto).split()) <= 7:
            assunto = "%s na app Bora?" % curto
        texto = ("Bom dia,<P>Somos a Bora, a aplicação de entregas e serviços da Guarda. Está em fase de arranque: "
                 "a app está construída e a ser testada com alguns comerciantes da Guarda.<P>"
                 "Gostávamos de ter %s connosco. O primeiro mês é grátis, não há mensalidade e a Bora só ganha quando a loja vende; "
                 "as entregas são feitas por estafetas da Guarda e o cliente paga por MB Way ou cartão.<P>"
                 "Preparámos uma página a mostrar como a vossa casa apareceria na app:<L>%s<P>"
                 "Querem ser parceiros? Passamos aí e explicamos em dez minutos.") % (curto, link)
    else:
        texto = ("Bom dia,<P>Somos a Bora, da Guarda: fazemos sites e tratamos da presença online de negócios da região.<P>"
                 "Ao ver %s na internet reparámos numa coisa: %s.<P>"
                 "Em vez de pedir uma reunião, preparámos primeiro uma página só para vocês, com o que vimos e o que faríamos:<L>%s<P>"
                 "Faz sentido conversarmos uns minutos esta semana?") % (curto, observacao(p), link)
    return assunto, texto.replace("<P>", chr(10) + chr(10)).replace("<L>", chr(10))


def redigir():
    fila = rpc("redator_fila", {}) or []
    log("redator: %d por escrever" % len(fila))
    feitos = 0
    for p in fila:
        assunto, texto = escrever(p)
        erros = validar(assunto, texto, p.get("link") or "")
        if erros:
            log("  %s: reprovado (%s)" % (p.get("nome"), "; ".join(erros)))
            continue
        v = rpc("prospect_proposta_registar", {"p_prospect": p["id"], "p_linha": {"canal": "email", "assunto": assunto, "texto": texto, "estado": "pronta"}})
        log("  %s: proposta %s pronta" % (p.get("nome"), v))
        feitos += 1
    e2e("b3-redator", "ok", "%d de %d escritos" % (feitos, len(fila)))


SEGUIMENTO = {
    1: "Bom dia,\n\nEscrevemos há uns dias sobre o que preparámos para vocês. Sabemos que o dia a dia de um negócio não deixa muito tempo, por isso fica só a pergunta: conseguiram espreitar? Uma palavra vossa chega para sabermos se faz sentido conversar.",
    2: "Bom dia,\n\nÉ a última vez que escrevemos sobre isto, para não incomodar. O que preparámos continua disponível no link da primeira mensagem. Se um dia fizer sentido, basta responder a este email.",
}


def enviar(forcar=False):
    fila = rpc("carteiro_fila", {"p_forcar": forcar})
    if not fila.get("ligado"):
        log("carteiro desligado (platform_settings.caca_clientes_enabled)")
        return
    eu = quem_sou()
    if eu.lower() != CONTA:
        raise RuntimeError("a conta autorizada e %s, nao a da Bora" % eu)
    n = s = 0
    todos = [("nova", x) for x in fila.get("novas", [])] + [("seg", x) for x in fila.get("seguimentos", [])]
    log("enviar: %d novas, %d seguimentos, janela=%s" % (len(fila.get("novas", [])), len(fila.get("seguimentos", [])), fila.get("janela")))
    for i, (tipo, x) in enumerate(todos):
        if i:
            time.sleep(random.randint(120, 180))
        try:
            if tipo == "nova":
                r = enviar_email(x["para"], x["assunto"], x["texto"])
                rpc("carteiro_marcar", {"p_proposta": x["proposta_id"], "p_evento": "enviada", "p_dados": r})
                n += 1
            else:
                assunto = x["assunto"] if x["assunto"].lower().startswith("re:") else "Re: " + x["assunto"]
                enviar_email(x["para"], assunto, SEGUIMENTO[int(x["numero"])], thread_id=x.get("thread_id"), em_resposta_a=x.get("rfc_message_id"))
                rpc("carteiro_marcar", {"p_proposta": x["proposta_id"], "p_evento": "seguimento"})
                s += 1
            log("  %s -> %s (%s)" % (tipo, x["nome"], x["para"]))
        except Exception as ex:
            registar_erro("carteiro-caca enviar", ex)
            log("  ERRO %s %s: %s" % (tipo, x.get("nome"), ex))
    e2e("b4-enviar", "ok", "%d novos, %d seguimentos" % (n, s))


def ler():
    threads = rpc("carteiro_threads", {}) or []
    if not threads:
        return
    achou = 0
    for t in threads:
        try:
            d = gmail("GET", "threads/%s?format=full" % t["thread_id"])
        except Exception as ex:
            log("  thread %s: %s" % (t["thread_id"], ex))
            continue
        for msg in d.get("messages", []):
            de = cabecalho(msg, "From").lower()
            if CONTA in de:
                continue
            corpo = so_a_resposta(texto_de(msg.get("payload", {})) or msg.get("snippet", ""))
            if "mailer-daemon" in de or "postmaster" in de or "delivery status notification" in cabecalho(msg, "Subject").lower():
                rpc("carteiro_marcar", {"p_proposta": t["proposta_id"], "p_evento": "bounce", "p_dados": {"resposta": corpo[:500]}})
                log("  devolvido: %s" % t["nome"])
                break
            recusa = any(r in corpo.lower() for r in RECUSA) or corpo.strip().lower() in ("não", "nao", "não.", "nao.")
            rpc("carteiro_marcar", {"p_proposta": t["proposta_id"], "p_evento": "recusou" if recusa else "respondeu", "p_dados": {"resposta": corpo}})
            achou += 1
            if recusa:
                dizer("O %s respondeu ao email da Bora a dizer que não quer. Fica marcado como recusou e nunca mais é contactado." % t["nome"],
                      resumo="Caça-clientes: %s recusou" % t["nome"])
            else:
                try:
                    sugestao = motor("Escreves em nome da «Bora App — Guarda», em português de Portugal, sem preços e sem promessas. "
                                     "Responde em no máximo 70 palavras, a propor uma conversa curta (telefone ou passar no negócio).",
                                     "O negócio %s respondeu ao nosso email:\n%s\n\nEscreve a resposta." % (t["nome"], corpo[:1500]), 300)
                except Exception:
                    sugestao = "(o motor não respondeu; escreve-se à mão)"
                dizer("Boa notícia: o %s respondeu ao email da Bora. Disseram: %s. A resposta que eu mandava é: %s. Se concordas, diz manda."
                      % (t["nome"], corpo[:600], sugestao), resumo="Caça-clientes: %s respondeu" % t["nome"])
            log("  %s: %s" % ("recusou" if recusa else "respondeu", t["nome"]))
            break
    if achou:
        e2e("b4-ler", "ok", "%d respostas novas" % achou)


def resumo():
    r = rpc("carteiro_resumo_dia", {})
    if not (r.get("enviados") or r.get("seguimentos") or r.get("respostas")):
        log("resumo: SEM NOVIDADE")
        return
    dizer("Caça-clientes, hoje: %d enviados, %d seguimentos, %d respostas. Ficam %d prontos para as próximas manhãs."
          % (r["enviados"], r["seguimentos"], r["respostas"], r.get("prontas", 0)), resumo="Caça-clientes: resumo do dia")


def teste():
    eu = quem_sou()
    r = enviar_email(CONTA, "[TESTE carteiro] ciclo completo " + time.strftime("%d/%m %H:%M"),
                     "Este email foi enviado pelo carteiro do caça-clientes para provar o ciclo: envio, leitura e resposta.")
    r["conta"] = eu
    with open(TESTE_FICH, "w") as f:
        json.dump(r, f)
    print(json.dumps(r))


def teste_responder():
    """Responde na mesma conversa, da propria conta, para o leitor ter uma resposta para ler."""
    r = json.load(open(TESTE_FICH))
    d = gmail("GET", "threads/%s?format=metadata&metadataHeaders=Subject" % r["thread_id"])
    assunto = cabecalho(d["messages"][0], "Subject")
    x = enviar_email(CONTA, "Re: " + assunto, "Resposta de teste: recebido, o ciclo fecha.", thread_id=r["thread_id"], em_resposta_a=r["rfc_message_id"])
    print(json.dumps({"resposta_enviada": x["message_id"], "thread_id": x["thread_id"]}))


def teste_ler():
    r = json.load(open(TESTE_FICH))
    d = gmail("GET", "threads/%s?format=full" % r["thread_id"])
    msgs = [{"de": cabecalho(m, "From"), "assunto": cabecalho(m, "Subject"), "texto": so_a_resposta(texto_de(m.get("payload", {})))[:120]} for m in d.get("messages", [])]
    print(json.dumps({"thread_id": r["thread_id"], "mensagens": len(msgs), "lista": msgs}, ensure_ascii=False))


if __name__ == "__main__":
    modo = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        {"redigir": redigir, "enviar": enviar, "ler": ler, "resumo": resumo, "teste": teste, "teste-responder": teste_responder, "teste-ler": teste_ler}[modo]()
    except KeyError:
        print(__doc__)
        sys.exit(2)
    except Exception as ex:
        registar_erro("carteiro-caca " + modo, ex)
        log("FALHOU %s: %s" % (modo, ex))
        sys.exit(1)
