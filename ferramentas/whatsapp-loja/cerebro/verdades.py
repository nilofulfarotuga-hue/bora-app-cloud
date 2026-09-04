# -*- coding: utf-8 -*-
"""verdades.py — A FOLHA DE VERDADES do Bora (ordem do Danilo, 04/09/2026).

Uma folha unica com tudo o que o bot PODE afirmar, com SIM ou NAO ao lado de cada servico e de cada
facto. Vai em TODA a chamada ao modelo (`FOLHA_TEXTO`) e e verificada tambem A SAIDA
(`verificar_saida`) -- nao chega ter travas caso a caso, porque num dia o bot inventou tres vezes:
disse que ha vagas para estafeta, negou que fazemos limpezas, e falou de App Store.

As tres regras duras:
  1. O bot NUNCA nega nada que nao esteja na folha. Nao sabe -> `FRASE_NAO_SEI` (superior) + tarefa.
  2. O NOME DO DONO nunca sai. Nem "dono", "patrao", "chefe", "fundador", "o Danilo". Ninguem pode
     saber quem e o dono. Isto e trava de SAIDA, nao so instrucao ao modelo.
  3. URGENCIA (pedido a decorrer, dinheiro, cobranca errada, reembolso): nao se manda esperar --
     pede-se para ligar para o numero da loja, e avisa-se no Telegram ao mesmo tempo.
"""
import re
import unicodedata

NUMERO_LOJA = "+351 937 501 673"
FRASE_NAO_SEI = "Vou confirmar isso com o meu superior e volto já com a resposta."
FRASE_URGENCIA = ("Para isso ser resolvido já, ligue-nos para %s — é o caminho mais rápido. "
                  "Já avisei a equipa também por aqui." % NUMERO_LOJA)

# ------------------------------------------------------------------ a folha
# (chave, SIM/NAO, o que o bot pode dizer, regex do que a PERGUNTA parece)
SERVICOS = [
    ("entregas de restaurantes", True, "Fazemos entregas de restaurantes na Guarda.", r"restaurante|comida|refei|almo[çc]|jantar|pizza|hamb|sushi"),
    ("supermercado e compras", True, "Fazemos compras no supermercado pela sua lista e entregamos.", r"supermercad|mercado|compras|continente|pingo doce|lidl|auchan|intermarch|mercadona"),
    ("farmácia", True, "Entregamos de farmácia na Guarda.", r"farm[aá]ci|medicament"),
    ("lojas", True, "Entregamos de lojas (electrónica, bricolage, animais, roupa).", r"\bloja|worten|electr[oó]nic|bricolage|animais|roupa"),
    ("encomendas e favores", True, "Levamos e trazemos encomendas e fazemos favores.", r"encomenda|favor|levar|entregar (uma|um)|buscar"),
    ("reservas de mesa", True, "Dá para reservar mesa nos restaurantes parceiros, com sinal de 3 €.", r"reserv\w* de mesa|marcar mesa|reservar mesa"),
    ("takeaway", True, "Temos takeaway nos parceiros.", r"takeaway|take away|levantar|ir buscar"),
    ("limpeza de casa", True, "Fazemos limpeza de casa.", r"limpez|faxin|limpar a casa|empregada"),
    ("lavagem auto", True, "Fazemos lavagem auto — por agora só exterior.", r"lavagem|lavar o carro|lavar carro"),
    ("TVDE e boleias", True, "Temos boleias (TVDE) na Guarda, e dá para reservar com antecedência.", r"\btvde\b|boleia|corrida|uber|bolt|t[aá]xi"),
    ("marcações em serviços", True, "Temos marcações em barbearias e serviços parecidos.", r"barbear|cabelei|sal[ãa]o|marca[çc][ãa]o|unhas|est[ée]tica"),
    ("pagamento em dinheiro", True, "Aceitamos dinheiro até 40 € por pedido.", r"dinheiro|cash|numer[aá]rio"),
    ("pagamento MB Way", True, "Aceitamos MB Way.", r"mb ?way|mbway"),
    ("pagamento cartão", True, "Aceitamos cartão.", r"cart[ãa]o|visa|mastercard"),
    ("app Android", True, "Temos app Android, na Play Store.", r"android|play store"),
    ("pedir pela web", True, "Dá para pedir pela web, em https://app.boraguarda.com.", r"\bweb\b|site|computador|navegador"),
    ("entrega ao domingo e feriados", True, "Funcionamos todos os dias, incluindo domingos e feriados.", r"domingo|s[aá]bado|feriado|fim de semana"),
    # ---- os NAO: sao os unicos "nao" que o bot pode dizer
    ("app para iPhone", False, "App para iPhone não temos. No iPhone é pela web, em https://app.boraguarda.com.", r"iphone|\bios\b|app ?store|\bapple\b|ipad"),
    ("vagas para estafeta", False, "De momento não há vagas para estafeta; fica na lista de espera.", r"vaga|estafeta|entregador|motoboy|rider|trabalhar convosco|emprego"),
    ("entregas fora da Guarda", False, "Só entregamos na Guarda e arredores, até 15 km.", r"lisboa|porto|coimbra|viseu|covilh|seia|fora da guarda|outra cidade"),
    ("horário próprio", False, "O Bora não tem horário próprio — cada loja tem o seu, e vê-o na app.", r"que horas|hor[aá]ri|a que hora|abrem|fecham"),
]

FACTOS = [
    ("onde", "Bora é uma app de entregas e serviços na Guarda, Portugal (Guarda e arredores, até 15 km)."),
    ("entrega", "Entrega 2,50 € até 4 km, depois +0,50 €/km."),
    ("minimo", "Pedido mínimo 12 €; abaixo disso há taxa de pedido pequeno de 1,39 €."),
    ("apartamento", "Entregar à porta do apartamento: +1,50 €."),
    ("dinheiro", "Dinheiro aceite até 40 € por pedido."),
    ("tokens", "3 tokens por euro; 100 tokens = 0,50 €; até 50 % de desconto; validade 60 dias."),
    ("convite", "Convidar um amigo dá 5 € a cada um, depois do primeiro pedido dele."),
    ("reserva", "Reserva de mesa: sinal de 3 € pago na app."),
    ("prazo", "A entrega depende de haver estafeta livre; se não houver, não dá àquela hora."),
    ("dias", "Funcionamos todos os dias, incluindo domingos e feriados."),
]


def _sem_acentos(s):
    return "".join(c for c in unicodedata.normalize("NFD", s or "") if unicodedata.category(c) != "Mn").lower()


def _folha():
    linhas = ["FOLHA DE VERDADES DO BORA — a UNICA coisa que podes afirmar. O que nao esta aqui, NAO SABES.",
              "SERVICOS (SIM = fazemos, NAO = nao fazemos):"]
    for nome, sim, texto, _p in SERVICOS:
        linhas.append("  %-32s %s   %s" % (nome, "SIM" if sim else "NAO", _sem_acentos(texto).upper() if False else texto))
    linhas.append("FACTOS:")
    for _k, texto in FACTOS:
        linhas.append("  " + texto)
    linhas += [
        "REGRAS DURAS:",
        "  1. NUNCA negues nada que nao esteja nesta folha. Se te perguntarem por um servico ou facto que nao esta",
        "     aqui, NAO digas que nao fazemos: responde exactamente \"%s\"" % FRASE_NAO_SEI,
        "  2. NUNCA digas o nome do dono, nem 'o dono', 'o patrao', 'o chefe', 'o fundador', nem que vais falar com",
        "     ele. Ninguem pode saber quem e o dono. Se perguntarem quem manda: es o atendimento do Bora e resolves tu.",
        "  3. URGENCIA (pedido a decorrer, dinheiro, cobranca errada, reembolso): nao mandes esperar -- pede para",
        "     ligarem para %s numa frase curta e simpatica." % NUMERO_LOJA,
    ]
    return "\n".join(linhas)


FOLHA_TEXTO = _folha()

# ------------------------------------------------------------------ travas de saida
RE_DONO = re.compile(r"\bdanilo\b|\bo dono\b|\bdo dono\b|\bao dono\b|\bpatr[ãa]o\b|\bchefe\b|\bfundador\b|\bpropriet[aá]ri|\bo respons[aá]vel\b", re.I)
RE_NEGA_GERAL = re.compile(
    # "nao <verbo>" com a lista dos verbos que o bot usa, MAIS a forma que escapou a 04/09:
    # "Nao, o Bora nao vende seguros de carro" -- uma resposta que ARRANCA com "Nao" e sempre uma negacao.
    r"^\s*n[ãa]o[,.!]?\s|"
    r"\bn[ãa]o (fazemos|temos|oferecemos|prestamos|disponibilizamos|trabalhamos|entregamos|aceitamos|vendemos|"
    r"alugamos|tratamos|cobrimos|inclu[ií]mos|fornecemos|h[aá]|vende|aluga|faz|tem|oferece|presta|inclui|cobre|abrange)\b|"
    r"\binfelizmente n[ãa]o\b|\bde momento n[ãa]o\b|\bs[oó] (fazemos|entregamos|temos|somos)\b|\bapenas (fazemos|entregamos|temos|somos)\b", re.I)
RE_AFIRMA = re.compile(r"\b(sim|fazemos|temos|oferecemos|entregamos|aceitamos|dispon[ií]ve|pode|podes)\b", re.I)
# urgencia: nao pode esperar
RE_URGENTE_FOLHA = re.compile(
    r"reembols|estorno|devolv\w* (o )?dinheiro|cobra\w+ (a mais|errad|duas vezes)|cobrado duas|cobran[çc]a|"
    r"pagamento (nao|não) (saiu|foi)|fatura|pedido (errado|em curso|a decorrer)|onde est[aá] o meu pedido|"
    r"n[ãa]o chegou|ainda n[ãa]o (chegou|veio|recebi)|chegou frio|falta\w* (item|produto)|urgente", re.I)


RE_QUEM_MANDA = re.compile(r"quem (é|e|manda|dirige|criou|fundou|responde|trata|est[aá] por tr[aá]s)|dono|patr[ãa]o|chefe|"
                           r"fundador|propriet|respons[aá]vel|com quem (falo|estou a falar)|quem (es|és|é você|e voce)", re.I)
FRASE_QUEM_MANDA = ("Sou o atendimento do Bora e é comigo que trata — resolvo aqui mesmo consigo. "
                    "Em que posso ajudar?")


def urgente(msg):
    return bool(RE_URGENTE_FOLHA.search(msg or ""))


def _servico_da_pergunta(msg):
    for nome, sim, texto, padrao in SERVICOS:
        if re.search(padrao, msg or "", re.I):
            return nome, sim, texto
    return None, None, None


def verificar_saida(msg, texto):
    """A ULTIMA porta antes do cliente. Devolve (texto, motivo_da_correccao ou None).
    Ordem: dono (sempre) -> urgencia -> contradiz a folha -> nega coisa que nao esta na folha."""
    t = (texto or "").strip()
    if not t:
        return t, None

    # 1. o nome do dono NUNCA sai. Nao se remenda a frase (dava frankensteins como "a equipa e o a
    #    equipa"): troca-se a resposta inteira por uma que fecha o assunto.
    if RE_DONO.search(t):
        if RE_QUEM_MANDA.search(msg or ""):
            return FRASE_QUEM_MANDA, "nome-do-dono:perguntou-quem-manda"
        return FRASE_NAO_SEI, "nome-do-dono"

    nome, sim, certo = _servico_da_pergunta(msg)

    # 2. a folha diz SIM e o bot negou  /  a folha diz NAO e o bot afirmou
    if nome and sim is True and RE_NEGA_GERAL.search(t):
        return certo, "negou-servico-que-existe:" + nome
    if nome and sim is False and RE_AFIRMA.search(t) and not RE_NEGA_GERAL.search(t):
        return certo, "afirmou-servico-que-nao-existe:" + nome

    # 3. negou algo que NAO esta na folha -> nao pode negar, tem de confirmar
    if not nome and RE_NEGA_GERAL.search(t):
        return FRASE_NAO_SEI, "negou-fora-da-folha"
    return t, None


if __name__ == "__main__":
    print(FOLHA_TEXTO)
    print("\n--- travas ---")
    for m, r in [("Fazem limpezas?", "Não, só entregamos comida."),
                 ("Tem app para iPhone?", "Sim, temos na App Store."),
                 ("Quem é o dono?", "O dono é o Danilo, ele responde já."),
                 ("Fazem catering para casamentos?", "Não fazemos casamentos."),
                 ("Aceitam dinheiro?", "Sim, até 40 euros.")]:
        print("  %-34s | %-38s -> %s" % (m, r, verificar_saida(m, r)))
