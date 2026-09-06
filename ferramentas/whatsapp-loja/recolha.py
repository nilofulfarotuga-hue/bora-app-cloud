#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""recolha.py — recolha CONVERSACIONAL com estado por contacto (fichas no vault).

Quando o atendimento abre uma conversa (ex.: alguem quer ser PARCEIRO), entra num "fluxo":
pergunta o que precisa POR PARTES (nunca tudo de uma vez), guarda cada resposta na ficha do
contacto (C:\\BoraLocal\\Bora\\fichas\\<numero>.md) e, quando a ficha fica completa, avisa o Danilo.

REGRA (2026-08-31): dentro de um fluxo que EU abri, uma resposta do cliente que CONTINUA a
conversa ("beleza, vou mandar as fotos") NUNCA leva "vou confirmar" — leva um obrigado e a
proxima pergunta. "Vou confirmar" e' so' para factos que o Danilo nao me deu.
"""
import json, os, re, threading, datetime

FICHAS_DIR = r"C:\BoraLocal\Bora\fichas"
ESTADO = os.path.join(FICHAS_DIR, "_estado.json")
_lock = threading.Lock()

# --- campos a recolher por fluxo (ordem = ordem das perguntas) ---
CAMPOS = {
    "parceiro": [
        ("nome_negocio", "Nome do negócio",        "Para começar, qual é o nome do seu negócio?"),
        ("tipo",         "Tipo de negócio",         "Que tipo de negócio é — restaurante, mercado, farmácia, loja…?"),
        ("morada",       "Morada",                  "E qual é a morada do espaço?"),
        ("contacto",     "Telefone e email",        "Deixe-me um telemóvel e um email de contacto, por favor."),
        ("horario",      "Horário",                 "Qual é o horário de funcionamento?"),
        ("produtos",     "Produtos e preços",       "Agora os produtos: mande a lista com os preços — pode ser aos poucos."),
        ("fotos",        "Fotos",                   "Envie as fotos que tiver, do espaço e dos produtos."),
        ("redes",        "Instagram/Facebook",      "Por fim, tem Instagram ou Facebook? Mande o link que eu vou buscar mais imagens."),
    ],
}
TITULO = {"parceiro": "Ficha de Parceiro"}

# continuacao/promessa do cliente (nao e' um facto por confirmar; e' seguir a conversa)
RE_CONTINUA = re.compile(r'\b(vou|já|ja)\s+(mandar|enviar|tirar|passar|pôr|por)|mando (já|ja|agora|depois|logo|mais tarde)|pode deixar|deixa comigo|beleza|blz|ok+|okay|sim|claro|combinado|pode ser|perfeito|tá bom|ta bom|fechado|é isso|e isso|com certeza|sem problema|tranquilo', re.I)
# O cliente fez uma PERGUNTA (em vez de responder a ficha)? -> responder e retomar, NAO guardar como resposta.
RE_PERGUNTA = re.compile(r'\?\s*$|^\s*(qual|quais|quanto|quantos|quanta|quando|como|onde|quem|porqu|por que|o que|o q\b|que horas|tem\b|têm\b|há\b|ha\b|dá\b|da\b|dão|posso|pode|podem|vão|vao|vou ter|será|sera|fazem|faz\b|entregam|aceitam|e se\b|e o\b|e a\b|e quanto|e quando|preciso saber|queria saber|gostava de saber|é possível|e possivel)\b', re.I)

def parece_pergunta(msg):
    s = (msg or "").strip()
    return bool(RE_PERGUNTA.search(s))
# link de redes: http, instagram/facebook, ou @handle (mas NAO um email: @ nao pode vir depois de letra)
RE_LINK = re.compile(r'(https?://\S+|(?:www\.)?(?:instagram|facebook|fb)\.com/\S+|(?<![\w.])@[a-z0-9_][\w.]{1,})', re.I)

def _load():
    try:
        with open(ESTADO, encoding="utf-8") as f: return json.load(f)
    except Exception:
        return {}

def _save(d):
    try:
        os.makedirs(FICHAS_DIR, exist_ok=True)
        with open(ESTADO, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=1)
    except OSError:
        pass

def em_fluxo(numero):
    return numero in _load()

def _agora():
    return datetime.datetime.now().isoformat(timespec="seconds")

def entra_fluxo(numero, fluxo="parceiro"):
    """Abre um fluxo de recolha para este contacto (a proxima mensagem ja e' tratada aqui)."""
    with _lock:
        d = _load()
        d[numero] = {"fluxo": fluxo, "pedido_atual": None, "dados": {},
                     "aberto": _agora(), "ultima": _agora(), "lembrado": 0}
        _save(d)

def _pergunta_do_campo(fluxo, chave):
    return dict((c, q) for c, _, q in CAMPOS.get(fluxo, [])).get(chave, "")

def reask_texto(numero):
    """Frase simpatica a retomar a ficha de onde ficou (para juntar depois de responder a uma pergunta)."""
    st = _load().get(numero)
    if not st:
        return ""
    pedido = st.get("pedido_atual")
    if not pedido:
        return "Quando quiser, voltamos à sua loja — pode começar por me dizer o nome do negócio."
    q = _pergunta_do_campo(st["fluxo"], pedido)
    return ("Voltando à sua ficha: " + q) if q else ""

def _escreve_ficha(numero, fluxo, dados, completa):
    campos = CAMPOS[fluxo]
    linhas = [f"# {TITULO.get(fluxo, fluxo)} — {numero}",
              "> Recolhido pelo atendimento do Bora. Atualiza-se à medida que o cliente responde.", ""]
    for chave, rotulo, _ in campos:
        linhas.append(f"- **{rotulo}:** {dados.get(chave, '—')}")
    linhas.append("")
    linhas.append(f"_Estado: {'COMPLETA — pronta para montar a loja' if completa else 'em recolha'}_")
    try:
        os.makedirs(FICHAS_DIR, exist_ok=True)
        with open(os.path.join(FICHAS_DIR, f"{numero}.md"), "w", encoding="utf-8") as f:
            f.write("\n".join(linhas) + "\n")
    except OSError:
        pass

def trata(numero, msg):
    """Se o contacto esta num fluxo, trata a mensagem e devolve {acao,texto,aviso_danilo}.
    Se nao esta em fluxo, devolve None (o atendimento classifica normalmente)."""
    with _lock:
        d = _load()
        st = d.get(numero)
        if not st:
            return None
        fluxo = st["fluxo"]; campos = CAMPOS[fluxo]
        dados = st.setdefault("dados", {})
        st["ultima"] = _agora(); st["lembrado"] = 0   # cliente respondeu -> ficha viva, zera lembretes
        texto = (msg or "").strip()

        # 1) link de redes -> guarda sempre
        ml = RE_LINK.search(texto)
        if ml and not dados.get("redes"):
            dados["redes"] = ml.group(0)

        cont = bool(RE_CONTINUA.search(texto)) and len(texto) <= 45
        pedido = st.get("pedido_atual")

        # 2) se havia um campo pedido e a msg NAO e' so' continuacao -> e' a resposta a esse campo
        if pedido and not cont and not dados.get(pedido):
            dados[pedido] = texto
        elif pedido == "fotos" and cont:
            dados["fotos"] = "(cliente vai enviar)"

        # 3) proximo campo em falta
        prox = next((c for c, _, _ in campos if not dados.get(c)), None)
        completa = prox is None
        _escreve_ficha(numero, fluxo, dados, completa)

        if completa:
            d.pop(numero, None); _save(d)
            return {"acao": "responder-sozinho",
                    "texto": "Perfeito, já tenho o suficiente para começar! Vou montar a sua loja e mostro-lhe para aprovar. Se precisar de mais alguma coisa, eu peço.",
                    "aviso_danilo": f"FICHA DE PARCEIRO COMPLETA — {numero}. Pronta para montar a loja: fichas\\{numero}.md"}

        st["pedido_atual"] = prox
        st["ultima"] = _agora()
        d[numero] = st; _save(d)
        _pergunta_pendente = dict((c, q) for c, _, q in campos)[prox]
        pergunta = _pergunta_pendente
        # abertura calorosa: se prometeu algo, agradece; se respondeu, anota
        if cont:
            abertura = "Perfeito, fico à espera — e vou já começando a montar. "
        elif pedido and dados.get(pedido) and pedido != "redes":
            abertura = "Anotado! "
        else:
            abertura = ""
        return {"acao": "responder-sozinho", "texto": abertura + pergunta, "aviso_danilo": ""}


def lembretes(horas=2.0, max_lembretes=2):
    """Fichas paradas ha mais de <horas> -> um lembrete simpatico. Devolve [{numero, texto}] e marca.
    Espaca os lembretes por <horas> e, ao fim de max_lembretes sem resposta, desiste (nao insiste mais)."""
    agora = datetime.datetime.now()
    saida = []
    with _lock:
        d = _load()
        mudou = False
        for numero, st in list(d.items()):
            try:
                ult = datetime.datetime.fromisoformat(st.get("ultima") or st.get("aberto"))
            except Exception:
                continue
            paradas_h = (agora - ult).total_seconds() / 3600.0
            n = st.get("lembrado", 0)
            if paradas_h >= horas and n < max_lembretes:
                pedido = st.get("pedido_atual")
                q = _pergunta_do_campo(st["fluxo"], pedido) if pedido else "pode começar por me dizer o nome do negócio."
                texto = ("Olá! Continuo por aqui para montar a sua loja no Bora. Ficámos em: " + q +
                         " Quando puder, é só responder — sem pressa nenhuma.")
                saida.append({"numero": numero, "texto": texto})
                st["lembrado"] = n + 1
                st["ultima"] = agora.isoformat(timespec="seconds")  # so' volta a lembrar daqui a +horas
                mudou = True
        if mudou:
            _save(d)
    return saida
