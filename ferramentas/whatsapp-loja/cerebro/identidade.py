# -*- coding: utf-8 -*-
"""identidade.py — como se trata a pessoa. NEUTRO por defeito; senhor/senhora/nome so com PROVA.

Regra do Danilo (02/09/2026): se o contacto nao esta guardado e o bot nao sabe quem e, NAO usa
senhor nem senhora. Prova aceite: (1) contacto guardado com nome, (2) a pessoa disse o nome,
(3) o perfil do Supabase tem nome, (4) a propria pessoa se referiu no feminino/masculino
("obrigada"/"obrigado", "sou a"/"sou o", "estou cansada"). Nunca se inventa genero pelo nome
nem pelo numero. Uma vez por resposta, no maximo.
"""
import re

RE_NOME_DITO = re.compile(
    r"(?:\b(?:sou|chamo-me|me chamo|meu nome (?:é|e)|o meu nome (?:é|e)|aqui (?:é|e)|fala (?:a|o)|daqui (?:fala )?(?:a|o))\s+)"
    r"(?P<art>a|o)?\s*(?P<nome>[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]{2,}(?:\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]{2,})?)")
RE_FEM = re.compile(r"\b(obrigada|cansada|interessada|preocupada|chateada|satisfeita|sou a|eu sou a|dona)\b", re.I)
RE_MASC = re.compile(r"\b(obrigado|cansado|interessado|preocupado|chateado|satisfeito|sou o|eu sou o)\b", re.I)
RE_TU = re.compile(r"\b(tu|tens|estás|estas|podes|queres|vais|fazes|sabes|és|teu|tua|contigo)\b", re.I)
RE_PTBR = re.compile(r"\b(você|vc|tá|tô|cadê|a gente|beleza|valeu|legal|celular|ônibus|bacana|mano|cara)\b", re.I)
RE_PTPT = re.compile(r"\b(estás|fixe|pá|autocarro|telemóvel|pequeno-almoço|casa de banho|miúdo|malta|giro|bué)\b", re.I)
RE_EN = re.compile(r"\b(hello|hi|please|thanks|thank you|order|delivery|how|what|when|can you|i want|i need)\b", re.I)
PALAVRAS_NAO_NOME = {"Bora", "Guarda", "Portugal", "Ola", "Olá", "Boa", "Bom", "Sim", "Nao", "Não", "Oi",
                     "Cliente", "Senhor", "Senhora", "Danilo"}


def nome_dito(msg):
    """A pessoa disse o nome? Devolve (nome, artigo) ou (None, None)."""
    m = RE_NOME_DITO.search(msg or "")
    if not m:
        return None, None
    nome = m.group("nome").strip()
    if nome.split()[0] in PALAVRAS_NAO_NOME:
        return None, None
    return nome, ((m.group("art") or "").lower() or None)


def genero_por_auto_referencia(msg):
    s = msg or ""
    f, m = bool(RE_FEM.search(s)), bool(RE_MASC.search(s))
    if f and not m:
        return "f"
    if m and not f:
        return "m"
    return None


def lingua(msg, actual=None):
    s = msg or ""
    if RE_EN.search(s) and not re.search(r"[áéíóúãõçâêô]", s) and not RE_PTBR.search(s) and not RE_PTPT.search(s):
        return "en"
    if RE_PTBR.search(s):
        return "pt-BR"
    if RE_PTPT.search(s):
        return "pt-PT"
    return actual or "pt-PT"


def registo(msg, actual=None):
    if RE_TU.search(msg or ""):
        return "tu"
    if re.search(r"\b(você|vc|o senhor|a senhora)\b", msg or "", re.I):
        return "voce"
    return actual or "voce"


def decidir_tratamento(ficha, msg):
    """Devolve (tratamento, prova). tratamento: neutro | nome | senhor | senhora. Actualiza a ficha."""
    nome, art = nome_dito(msg)
    if nome and not ficha.get("nome"):
        ficha["nome"] = nome
        ficha["nome_fonte"] = "disse"
        if art == "a" and not ficha.get("genero"):
            ficha["genero"], ficha["genero_fonte"] = "f", "disse"
        elif art == "o" and not ficha.get("genero"):
            ficha["genero"], ficha["genero_fonte"] = "m", "disse"
    g = genero_por_auto_referencia(msg)
    if g and not ficha.get("genero"):
        ficha["genero"], ficha["genero_fonte"] = g, "auto_referencia"
    if ficha.get("nome") and ficha.get("nome_fonte") in ("contacto_guardado", "disse", "supabase"):
        return "nome", ficha["nome_fonte"]
    if ficha.get("genero") == "f":
        return "senhora", ficha.get("genero_fonte", "auto_referencia")
    if ficha.get("genero") == "m":
        return "senhor", ficha.get("genero_fonte", "auto_referencia")
    return "neutro", ""


def instrucao_tratamento(tratamento, ficha):
    """A linha que entra no prompt do modelo."""
    if tratamento == "nome":
        return ("Trata a pessoa pelo primeiro nome, '%s', no maximo UMA vez na resposta. Nunca 'senhor' nem 'senhora'."
                % ficha["nome"].split()[0])
    if tratamento == "senhora":
        return "Podes dizer 'a senhora' UMA vez, no maximo. Nunca 'senhor'."
    if tratamento == "senhor":
        return "Podes dizer 'o senhor' UMA vez, no maximo. Nunca 'senhora'."
    # SEM exemplo literal: os modelos pequenos copiam-no tal e qual em vez de responder a pergunta
    # (o 7b e o 3b responderam a saudacao-exemplo a "quero ser estafeta", 02/09).
    return ("NAO sabes quem e a pessoa: NUNCA escrevas 'senhor', 'senhora', 'sr.', 'sra.' nem um nome. "
            "Trata por 'você', de forma neutra e calorosa, e responde AO QUE A PESSOA DISSE.")


def _uma_vez(texto, termo):
    partes = re.split(r"(\b%s\b)" % re.escape(termo), texto, flags=re.I)
    n, out = 0, []
    for p in partes:
        if p.lower() == termo.lower():
            n += 1
            out.append(p if n == 1 else "")
        else:
            out.append(p)
    return "".join(out)


def limpar_tratamento(texto, tratamento, ficha):
    """Rede de seguranca sobre o que o modelo escreveu: tira o que nao esta provado e deixa 1x."""
    t = texto or ""
    if tratamento != "senhor":
        t = re.sub(r"\b(o|ao|do)\s+senhor\b,?\s*", "", t, flags=re.I)
        t = re.sub(r"\bsenhor\b,?\s*", "", t, flags=re.I)
    if tratamento != "senhora":
        t = re.sub(r"\b(a|à|da)\s+senhora\b,?\s*", "", t, flags=re.I)
        t = re.sub(r"\bsenhora\b,?\s*", "", t, flags=re.I)
    t = re.sub(r"\b(sr|sra|dr|dra)\.\s*", "", t, flags=re.I)
    t = _uma_vez(t, "o senhor")
    t = _uma_vez(t, "a senhora")
    if tratamento == "nome" and ficha.get("nome"):
        primeiro = ficha["nome"].split()[0]
        vistos = [0]

        def _troca(m):
            vistos[0] += 1
            return m.group(0) if vistos[0] == 1 else ""
        t = re.sub(r",?\s*\b%s\b" % re.escape(primeiro), _troca, t)
    t = re.sub(r"\s+([.!?,;:])", r"\1", t)
    t = re.sub(r",\s*([.!?;:])", r"\1", t)              # "pedir,." -> "pedir."
    t = re.sub(r"(,\s*){2,}", ", ", t)                   # ", ," -> ","
    t = re.sub(r"\s{2,}", " ", t).strip()
    t = re.sub(r"^[,\s]+", "", t)
    t = re.sub(r"\s+,", ",", t)
    return t


def saudacao(tratamento, ficha, lingua_="pt-PT"):
    if lingua_ == "en":
        return "Hi! How can I help?"
    if tratamento == "nome":
        return "Oi %s, tudo bem? Precisa de alguma coisa? Posso ajudar?" % ficha["nome"].split()[0]
    if tratamento == "senhora":
        return "Olá, tudo bem? A senhora precisa de alguma coisa? Posso ajudar."
    if tratamento == "senhor":
        return "Olá, tudo bem? O senhor precisa de alguma coisa? Posso ajudar."
    return "Oi, tudo bem? Precisa de alguma coisa? Posso ajudar?"


if __name__ == "__main__":
    f = {}
    print("oi ->", decidir_tratamento(f, "oi"), f)
    f = {}
    print("obrigada! ->", decidir_tratamento(f, "obrigada!"), f)
    f = {}
    print("sou a Keli ->", decidir_tratamento(f, "Ola, sou a Keli do Sabores"), f)
    f = {"nome": "Keli Barbosa", "nome_fonte": "contacto_guardado"}
    print("contacto guardado ->", decidir_tratamento(f, "boa noite"), "|", saudacao("nome", f))
    print("limpeza neutro ->", limpar_tratamento("Olá, o senhor precisa de alguma coisa, o senhor?", "neutro", {}))
    print("limpeza senhora ->", limpar_tratamento("Sim senhora, a senhora pode pedir, a senhora.", "senhora", {}))
