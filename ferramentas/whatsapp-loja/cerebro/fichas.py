# -*- coding: utf-8 -*-
"""fichas.py — a FICHA VIVA de cada contacto. Uma por numero, no vault (markdown) e no Supabase.

Criada na primeira mensagem, actualizada a cada conversa. Guarda so o que esta PROVADO: nome
(com a fonte), tratamento, registo (tu/voce), lingua, papel (cruzado com o Supabase), o que ja
pediu, o que lhe foi prometido (com estado), o que falta recolher, o estilo de escrita, notas.
"""
import datetime
import json
import os
import re
import threading

from . import supa

VAULT_DIR = next((p for p in (r"C:\BoraLocal\Bora\whatsapp\contactos", "/opt/whatsapp-bora/vault/whatsapp/contactos")
                  if os.path.isdir(os.path.dirname(os.path.dirname(p))) or os.path.isdir(p)), r"C:\BoraLocal\Bora\whatsapp\contactos")
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_fichas")
_lock = threading.Lock()
CAMPOS_TABELA = ("numero", "nome", "nome_fonte", "tratamento", "registo", "lingua", "papel", "papel_detalhe",
                 "supabase_user_id", "supabase_driver_id", "supabase_restaurant_id", "estilo", "notas",
                 "o_que_pediu", "prometido", "falta_recolher", "lead_id", "bot_pausado", "bot_pausado_ate",
                 "bot_pausado_por", "assumido_por_danilo", "cumprimentado_em", "primeira_msg_em",
                 "ultima_msg_em", "ultima_resposta_bot_em")


def so_digitos(s):
    return re.sub(r"\D", "", str(s or ""))


def agora():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def nova(numero):
    return {"numero": numero, "nome": None, "nome_fonte": None, "tratamento": "neutro", "registo": None,
            "lingua": "pt-PT", "papel": "desconhecido", "papel_detalhe": {}, "estilo": {}, "notas": None,
            "o_que_pediu": [], "prometido": [], "falta_recolher": [], "lead_id": None,
            "bot_pausado": False, "bot_pausado_ate": None, "bot_pausado_por": None,
            "assumido_por_danilo": False, "cumprimentado_em": None, "primeira_msg_em": agora(),
            "ultima_msg_em": None, "ultima_resposta_bot_em": None}


def _cache_path(numero):
    os.makedirs(CACHE_DIR, exist_ok=True)
    return os.path.join(CACHE_DIR, numero + ".json")


def carregar(numero):
    """Supabase primeiro (partilhado pelas duas portas); cache local se o Supabase estiver em baixo."""
    numero = so_digitos(numero)
    f = None
    try:
        f = supa.um("whatsapp_contacts", numero="eq." + numero)
    except Exception:
        f = None
    if not f:
        try:
            f = json.load(open(_cache_path(numero), encoding="utf-8"))
        except Exception:
            f = None
    if not f:
        f = nova(numero)
        f["_nova"] = True
    # o genero vive dentro de `estilo` na tabela; aqui sobe para o topo (identidade.py le ficha["genero"])
    est = f.get("estilo") or {}
    if est.get("genero"):
        f["genero"], f["genero_fonte"] = est.get("genero"), est.get("genero_fonte")
    return f


def guardar(f):
    """Supabase + cache + markdown no vault. Nunca rebenta o atendimento."""
    f = dict(f)
    est = dict(f.get("estilo") or {})
    if f.get("genero"):
        est["genero"], est["genero_fonte"] = f["genero"], f.get("genero_fonte")
    f["estilo"] = est
    linha = {k: f.get(k) for k in CAMPOS_TABELA}
    with _lock:
        try:
            json.dump(f, open(_cache_path(f["numero"]), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        except OSError:
            pass
        try:
            supa.upsert("whatsapp_contacts", linha, "numero")
        except Exception as e:  # noqa: BLE001
            f["_erro_supabase"] = str(e)[:200]
        try:
            _escrever_markdown(f)
        except OSError:
            pass
    return f


def _escrever_markdown(f):
    os.makedirs(VAULT_DIR, exist_ok=True)
    n = f["numero"]
    mask = n[:-3] and ("+" + n[:3] + " " + "*" * (len(n) - 6) + n[-3:])
    linhas = ["# Contacto %s" % n, "> Ficha viva do atendimento do Bora (WhatsApp da loja). Actualiza-se a cada conversa.",
              "> Nada aqui e inventado: cada campo diz de onde veio.", "",
              "- **Nome:** %s%s" % (f.get("nome") or "—", (" _(fonte: %s)_" % f["nome_fonte"]) if f.get("nome_fonte") else ""),
              "- **Tratamento a usar:** %s" % (f.get("tratamento") or "neutro"),
              "- **Registo:** %s · **Língua:** %s" % (f.get("registo") or "—", f.get("lingua") or "pt-PT"),
              "- **Papel:** %s %s" % (f.get("papel") or "desconhecido", json.dumps(f.get("papel_detalhe") or {}, ensure_ascii=False)),
              "- **Bot:** %s%s" % ("PAUSADO" if f.get("bot_pausado") else "activo", " · assumido pelo Danilo" if f.get("assumido_por_danilo") else ""),
              "- **Primeira mensagem:** %s · **Última:** %s" % (f.get("primeira_msg_em") or "—", f.get("ultima_msg_em") or "—"),
              "", "## O que já pediu"]
    linhas += ["- %s" % p for p in (f.get("o_que_pediu") or [])] or ["- _(nada ainda)_"]
    linhas += ["", "## O que lhe foi prometido"]
    linhas += ["- [%s] %s (%s)" % (p.get("estado", "?"), p.get("texto", ""), p.get("quando", "")) for p in (f.get("prometido") or [])] or ["- _(nada)_"]
    linhas += ["", "## O que falta recolher"]
    linhas += ["- %s" % p for p in (f.get("falta_recolher") or [])] or ["- _(nada)_"]
    linhas += ["", "## Estilo (como a pessoa escreve)", "```json", json.dumps(f.get("estilo") or {}, ensure_ascii=False, indent=1), "```",
               "", "## Notas humanas", f.get("notas") or "_(nenhuma)_", ""]
    open(os.path.join(VAULT_DIR, n + ".md"), "w", encoding="utf-8").write("\n".join(linhas))


# ---------------------------------------------------------------- cruzar com o Supabase
def _likes(numero):
    """Os numeros no Supabase vem como '+351 937 402 120', '937402120' ou '351937402120': tenta os
    9 digitos seguidos e, se nada bater, os ultimos 6 (as pessoas escrevem com espacos)."""
    n9 = numero[-9:] if len(numero) >= 9 else numero
    return ["ilike.*" + n9 + "*", "ilike.*" + n9[-6:] + "*"]


def _procura(tabela, select, campos, numero):
    for like in _likes(numero):
        try:
            if len(campos) == 1:
                r = supa.um(tabela, select=select, **{campos[0]: like})
            else:
                r = supa.um(tabela, select=select, **{"or": "(" + ",".join("%s.%s" % (c, like) for c in campos) + ")"})
        except Exception:
            r = None
        if r:
            return r
    return None


def cruzar_supabase(f):
    """Quem e esta pessoa para o Bora? users / drivers / restaurants / orders, pelo numero."""
    numero = f["numero"]
    det = dict(f.get("papel_detalhe") or {})
    u = _procura("users", "id,name,email,role", ["phone"], numero)
    d = _procura("drivers", "id,name,approval_status,is_online,vehicle_type", ["phone", "mbway_phone"], numero)
    r = _procura("restaurants", "id,name,is_partner,is_online,approval_status,category", ["phone", "whatsapp", "mbway_phone"], numero)
    pedidos = []
    for like in _likes(numero):
        try:
            pedidos = supa.select("orders", select="id,status,created_at,vendor_name", client_phone=like,
                                  order="created_at.desc", limit="5")
        except Exception:
            pedidos = []
        if pedidos:
            break
    papel = f.get("papel") or "desconhecido"
    nome = None
    if r:
        papel = "parceiro"
        det.update({"loja": r.get("name"), "restaurant_id": r.get("id"), "loja_aberta": r.get("is_online"),
                    "is_partner": r.get("is_partner")})
        f["supabase_restaurant_id"] = r.get("id")
        nome = _nome_da_loja(r.get("name"))
    elif d:
        papel = "estafeta"
        det.update({"driver_id": d.get("id"), "estado": d.get("approval_status"), "online": d.get("is_online"),
                    "veiculo": d.get("vehicle_type")})
        f["supabase_driver_id"] = d.get("id")
        nome = d.get("name")
    elif u or pedidos:
        papel = "cliente" if papel in ("desconhecido", "cliente") else papel
        if u:
            det.update({"user_id": u.get("id"), "role": u.get("role")})
            f["supabase_user_id"] = u.get("id")
            nome = u.get("name")
    det["n_pedidos"] = len(pedidos)
    if pedidos:
        det["ultimo_pedido"] = {"id": pedidos[0]["id"], "status": pedidos[0]["status"], "quando": pedidos[0]["created_at"],
                                "loja": pedidos[0].get("vendor_name")}
    if nome and not f.get("nome"):
        f["nome"], f["nome_fonte"] = nome.strip(), "supabase"
    f["papel"], f["papel_detalhe"] = papel, det
    return f


def _nome_da_loja(nome_loja):
    """'Sabores do Brasil - Keli Barbosa' -> 'Keli Barbosa'. So quando o nome da loja traz a pessoa."""
    if not nome_loja or " - " not in nome_loja:
        return None
    pessoa = nome_loja.split(" - ", 1)[1].strip()
    return pessoa if re.match(r"^[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+(\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+)*$", pessoa) else None


# ---------------------------------------------------------------- aprender com a pessoa
def aprender_estilo(f, msg, lingua_, registo_):
    est = dict(f.get("estilo") or {})
    txt = msg or ""
    est["lingua"] = lingua_
    est["registo"] = registo_
    est["usa_emojis"] = bool(re.search(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", txt)) or est.get("usa_emojis", False)
    comp = len(txt)
    est["comprimento_medio"] = round(((est.get("comprimento_medio") or comp) * 3 + comp) / 4)
    h = datetime.datetime.now().hour
    horas = est.get("horas") or {}
    horas[str(h)] = horas.get(str(h), 0) + 1
    est["horas"] = horas
    f["estilo"] = est
    f["registo"] = registo_
    f["lingua"] = lingua_
    return f


def anotar_pedido(f, resumo):
    lst = list(f.get("o_que_pediu") or [])
    r = "%s — %s" % (datetime.date.today().isoformat(), (resumo or "").strip()[:140])
    if r not in lst:
        lst.append(r)
    f["o_que_pediu"] = lst[-30:]
    return f


def anotar_promessa(f, texto, estado="aberta", tarefa_id=None):
    lst = list(f.get("prometido") or [])
    lst.append({"texto": (texto or "")[:160], "estado": estado, "quando": agora(), "tarefa_id": tarefa_id})
    f["prometido"] = lst[-20:]
    return f


def fechar_promessa(f, tarefa_id, estado="cumprida"):
    for p in f.get("prometido") or []:
        if p.get("tarefa_id") == tarefa_id:
            p["estado"] = estado
    return f


def cumprimentado_hoje(f):
    return f.get("cumprimentado_em") == datetime.date.today().isoformat()


def marcar_cumprimento(f):
    f["cumprimentado_em"] = datetime.date.today().isoformat()
    return f


def pausado(f):
    if f.get("assumido_por_danilo"):
        return True
    if f.get("bot_pausado"):
        ate = f.get("bot_pausado_ate")
        if not ate:
            return True
        try:
            return datetime.datetime.fromisoformat(ate.replace("Z", "+00:00")) > datetime.datetime.now(datetime.timezone.utc)
        except Exception:
            return True
    return False


if __name__ == "__main__":
    f = carregar("351937402120")
    f = cruzar_supabase(f)
    print(json.dumps({k: f.get(k) for k in ("numero", "nome", "nome_fonte", "papel", "papel_detalhe")}, ensure_ascii=False))
