# -*- coding: utf-8 -*-
"""fio.py — o FIO da conversa (falha G, 02/09 noite).

Quando o bot pergunta algo, a ficha fica `a_espera_de` = {campo, tipo_lead, pergunta, desde, prazo}.
A mensagem seguinte e lida PRIMEIRO como resposta ao que se pediu; so se nao encaixar e que vai ao
fluxo normal. Tudo deterministico (zero modelos): "Danilo" depois de "preciso do seu nome" e o nome.
Os campos sao os do cartao de estafeta/parceiro (ferramentas_bot.registar_lead usa os mesmos nomes).
"""
import datetime
import re

from . import identidade

CAMPOS = {
    "estafeta": ["nome", "zona", "veiculo", "disponibilidade"],
    "parceiro": ["nome_loja", "tipo", "morada", "horario", "redes_ou_fotos", "contacto"],
}
PERGUNTAS = {
    "nome": "Como se chama?",
    "zona": "Em que cidade ou zona está?",
    "veiculo": "Que veículo tem (mota, carro ou bicicleta)?",
    "disponibilidade": "Que disponibilidade tem (manhãs, tardes, noites, fins de semana)?",
    "nome_loja": "Qual é o nome do negócio?",
    "tipo": "Que tipo de negócio é (restaurante, café, loja...)?",
    "morada": "Qual é a morada?",
    "horario": "Qual é o horário de funcionamento?",
    "redes_ou_fotos": "Tem Instagram ou Facebook? Ou pode mandar fotos e a lista de produtos com preços.",
    "contacto": "Qual é o melhor telefone ou email para o Danilo falar consigo?",
}
RE_ADIAR = re.compile(r"amanh[ãa]|depois|mais tarde|\blogo\b|vou mandar|vou enviar|envio (depois|amanh|logo)|mando (depois|amanh|logo)|quando puder|daqui a|\bespera\b|aguarda|assim que (puder|conseguir)", re.I)
RE_VEICULO = re.compile(r"\b(mota|moto|motorizada|scooter|carro|carrinha|bicicleta|bike|trotinete|a p[eé])\b", re.I)
RE_DISPON = re.compile(r"manh|tarde|noite|fim.?de.?semana|fins.?de.?semana|semana|todos os dias|qualquer|sempre|full|part|\d+\s*h\b|horas|dias|segunda|ter[çc]a|quarta|quinta|sexta|s[aá]bado|domingo", re.I)
RE_REDES = re.compile(r"instagram|facebook|\binsta\b|\bfb\b|https?://|www\.|@\w{3,}|\bfotos?\b|imagens?|\[imagem", re.I)
RE_MORADA = re.compile(r"\b(rua|avenida|av\.|pra[çc]a|largo|travessa|estrada|bairro|lote|urbaniza|n[º°o]\.?\s*\d)|\d{4}-\d{3}", re.I)
RE_HORARIO_T = re.compile(r"\d{1,2}\s*h\b|\d{1,2}:\d{2}|\bdas\s+\d|\bat[eé]\s+\d|\babre|\bfecha|todos os dias|24 ?h", re.I)
RE_CONTACTO = re.compile(r"\+?\d[\d\s]{8,}\d|[\w.+-]+@[\w-]+\.\w+", re.I)
RE_TIPO = re.compile(r"restaurante|pizzaria|hamburgueria|churrasqueira|caf[eé]|pastelaria|padaria|\bbar\b|tasca|sushi|\bloja\b|mercearia|minimercado|talho|peixaria|florista|farm[aá]cia|barbearia|sal[ãa]o|cabeleireiro|lavandaria|papelaria|livraria|frutaria|garrafeira|take.?away|marisqueira|snack|gelataria|doces|bolos|comida", re.I)
RE_OUTRA_COISA = re.compile(r"\?|pedido|encomenda|reembols|pre[çc]o|quanto|custa|hor[aá]rio|entregam|funciona", re.I)
NAO_NOME = {"oi", "ola", "olá", "sim", "não", "nao", "ok", "boa", "bom", "tarde", "noite", "dia", "obrigado", "obrigada",
            "quero", "posso", "tenho", "estou", "sou", "beleza", "certo", "claro", "pronto", "ainda", "nada", "nenhum", "nenhuma"}
PREFIXOS = re.compile(r"^(?:o meu nome (?:é|e)|meu nome (?:é|e)|chamo-me|me chamo|sou (?:o|a)|sou|eu sou|(?:é|e) o|(?:é|e) a|chama-se|o nome (?:é|e)|sou de|moro em|estou em|fico em|vivo em|na|no|em|de|tenho|uso|ando de|é|e)\s+", re.I)


def _agora():
    return datetime.datetime.now(datetime.timezone.utc)


def _limpa(msg):
    s = (msg or "").strip().strip(".!, ")
    s = PREFIXOS.sub("", s).strip().strip(".!, ")
    return s


def _titulo(s):
    return " ".join(w[:1].upper() + w[1:] for w in s.split())


def _primeiro_pedaco(m):
    """'Guarda, tenho mota' -> 'Guarda': o pedaco antes da virgula / do 'e' / do 'tenho'."""
    return re.split(r"[,;.]| e | tenho | uso | ando | com ", m, maxsplit=1)[0].strip()


def _encaixa(campo, msg, esperado=False):
    """Devolve o valor se a mensagem responde a este campo; senao None.
    `esperado`: e o campo que se pediu -> regras brandas (uma palavra chega). Os outros campos so
    entram com padrao POSITIVO (mota/carro, instagram, morada com numero...), senao "Danilo"
    virava zona e disponibilidade ao mesmo tempo (apanhado no auto-teste, 02/09)."""
    m = (msg or "").strip()
    if not m or m.startswith("[áudio que") or m.startswith("[imagem que"):
        return None
    if campo == "nome":
        nome, _art = identidade.nome_dito(m)
        if nome:
            return nome
        if not esperado or "?" in m or len(m) > 40 or RE_OUTRA_COISA.search(m):
            return None
        s = _limpa(_primeiro_pedaco(m))
        palavras = s.split()
        if not (1 <= len(palavras) <= 4) or any(ch.isdigit() for ch in s) or palavras[0].lower() in NAO_NOME:
            return None
        if not re.fullmatch(r"[A-Za-zÀ-ÿ' -]+", s):
            return None
        return _titulo(s)[:60]
    if campo == "veiculo":
        v = RE_VEICULO.search(m)
        return v.group(1).lower() if v else None
    if campo == "zona":
        if not esperado or "?" in m or len(m) > 60 or RE_OUTRA_COISA.search(m):
            return None
        s = _limpa(_primeiro_pedaco(m))
        return _titulo(s)[:60] if s and re.fullmatch(r"[A-Za-zÀ-ÿ' .-]+", s) and s.split()[0].lower() not in NAO_NOME else None
    if campo == "disponibilidade":
        if RE_DISPON.search(m) and "?" not in m:
            return m[:120]
        return m[:120] if (esperado and len(m) <= 80 and "?" not in m) else None
    if campo == "nome_loja":
        if not esperado or "?" in m or len(m) > 60:
            return None
        s = _limpa(m)
        return s[:60] if s and not RE_OUTRA_COISA.search(s) else None
    if campo == "tipo":
        t = RE_TIPO.search(m)
        return t.group(0).lower() if t else (m[:40] if esperado and len(m) <= 40 and "?" not in m else None)
    if campo == "morada":
        return m[:160] if (RE_MORADA.search(m) or (len(m) <= 100 and any(ch.isdigit() for ch in m) and "?" not in m)) else None
    if campo == "horario":
        return m[:120] if RE_HORARIO_T.search(m) else None
    if campo == "redes_ou_fotos":
        return m[:200] if RE_REDES.search(m) else None
    if campo == "contacto":
        c = RE_CONTACTO.search(m)
        return c.group(0).strip() if c else None
    return None


def a_espera(f):
    a = f.get("a_espera_de") or {}
    if not isinstance(a, dict) or not a.get("campo"):
        return None
    try:
        if a.get("prazo") and datetime.datetime.fromisoformat(a["prazo"]) < _agora():
            f["a_espera_de"] = None
            return None
    except Exception:
        pass
    return a


def esperar(f, campo, tipo_lead, horas=24):
    f["a_espera_de"] = {"campo": campo, "tipo_lead": tipo_lead, "pergunta": PERGUNTAS.get(campo, campo),
                        "desde": _agora().isoformat(timespec="seconds"),
                        "prazo": (_agora() + datetime.timedelta(hours=horas)).isoformat(timespec="seconds")}
    f["falta_recolher"] = [campo]


def responder_ao_que_se_pediu(f, msg, dados_lead):
    """Se a ficha esta a espera de algo e a mensagem responde, devolve
    {texto, novos, todos, falta, fechou, tipo, adiou}; senao None (vai ao fluxo normal)."""
    a = a_espera(f)
    if not a:
        return None
    tipo = a.get("tipo_lead") or ("parceiro" if str(f.get("papel") or "").endswith("parceiro") else "estafeta")
    campos = CAMPOS.get(tipo, CAMPOS["estafeta"])
    dados = dict(dados_lead or {})
    novos = {}
    for c in [a["campo"]] + [c for c in campos if c != a["campo"]]:
        if c in dados and dados[c]:
            continue
        v = _encaixa(c, msg, esperado=(c == a["campo"]))
        if v:
            novos[c] = v
    if not novos:
        if RE_ADIAR.search(msg or "") and not RE_OUTRA_COISA.search(msg or ""):
            a["prazo"] = (_agora() + datetime.timedelta(hours=24)).isoformat(timespec="seconds")
            f["a_espera_de"] = a
            que = {"redes_ou_fotos": " das fotos", "morada": " da morada", "contacto": " do contacto", "nome_loja": " do nome do negócio"}.get(a["campo"], "")
            return {"texto": "Combinado! Fico à espera%s, sem pressa nenhuma. Quando enviar, continuo daqui." % que,
                    "novos": {}, "todos": dados, "falta": [c for c in campos if not dados.get(c)], "fechou": False, "tipo": tipo, "adiou": True}
        return None
    dados.update(novos)
    if novos.get("nome") and not f.get("nome"):
        f["nome"], f["nome_fonte"] = novos["nome"][:80], "disse"
    primeiro = (novos.get("nome") or dados.get("nome") or f.get("nome") or "").split()
    agradece = ("Obrigado, %s. " % primeiro[0]) if primeiro and f.get("nome_fonte") in ("disse", "contacto_guardado", "supabase", "danilo") else "Obrigado. "
    falta = [c for c in campos if not dados.get(c)]
    if tipo == "estafeta" and "nome" in novos:
        # a lista de espera fecha-se JA com o nome (o que o Danilo pediu); o cartao completa-se ao ritmo da conversa
        base = agradece + "Fica na nossa lista de espera e avisamos assim que abrir vaga."
        if falta:
            texto = base + " Só para completar o seu registo: " + PERGUNTAS[falta[0]][0].lower() + PERGUNTAS[falta[0]][1:]
            esperar(f, falta[0], tipo)
        else:
            texto = base
            f["a_espera_de"], f["falta_recolher"] = None, []
        return {"texto": texto, "novos": novos, "todos": dados, "falta": falta, "fechou": not falta, "tipo": tipo, "adiou": False, "lista_espera": True}
    if falta:
        texto = agradece + PERGUNTAS[falta[0]]
        esperar(f, falta[0], tipo)
        fechou = False
    else:
        texto = agradece + ("Fica na nossa lista de espera e avisamos assim que abrir vaga." if tipo == "estafeta"
                            else "Já tenho tudo para o Danilo montar a sua loja no Bora; ele fala consigo por aqui para a aprovar.")
        f["a_espera_de"], f["falta_recolher"] = None, []
        fechou = True
    return {"texto": texto, "novos": novos, "todos": dados, "falta": falta, "fechou": fechou, "tipo": tipo, "adiou": False}


def anotar_troca(f, direcao, texto, cap=20):
    """As ultimas 10 trocas (20 mensagens) ficam na ficha e vao sempre no contexto do modelo."""
    lst = list(f.get("ultimas_trocas") or [])
    lst.append({"dir": direcao, "texto": (texto or "")[:400], "ts": _agora().isoformat(timespec="seconds")})
    f["ultimas_trocas"] = lst[-cap:]


def historico_para_modelo(f, n=20):
    """Mensagens user/assistant alternadas a partir de ultimas_trocas (sem a mensagem actual)."""
    out = []
    for t in (f.get("ultimas_trocas") or [])[-n:]:
        out.append({"role": "user" if t.get("dir") == "entrada" else "assistant", "content": t.get("texto") or ""})
    return out


if __name__ == "__main__":
    f = {"papel": "prospect_estafeta"}
    esperar(f, "nome", "estafeta")
    print(responder_ao_que_se_pediu(f, "Danilo", {}))
    print("espera agora:", f.get("a_espera_de", {}).get("campo"))
    print(responder_ao_que_se_pediu(f, "Guarda, tenho mota", {"nome": "Danilo"}))
    f2 = {"papel": "prospect_parceiro"}
    esperar(f2, "redes_ou_fotos", "parceiro")
    print(responder_ao_que_se_pediu(f2, "espera, vou mandar amanhã", {"nome_loja": "Tasca do Zé", "tipo": "restaurante"}))
    print("prazo:", f2["a_espera_de"]["prazo"])
