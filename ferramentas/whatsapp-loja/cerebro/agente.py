# -*- coding: utf-8 -*-
"""agente.py — o cerebro com maos. Recebe um evento (mensagens agrupadas de uma pessoa) e decide.

O ciclo e FERRAMENTA -> RESPOSTA. Passos:
  1. ficha viva (cruzada com o Supabase na 1a vez) + tratamento (neutro por defeito)
  2. audio -> transcricao; imagem -> descricao (entram na conversa como texto)
  3. portao deterministico: grupo (nunca), ack (silencio educado), pausado/assumido (silencio),
     dinheiro/reembolso/desconto/reclamacao/falta -> ESCALAR (acusa recepcao + Danilo + tarefa 30 min)
  4. modelo com ferramentas (ate 4 voltas, orcamento 20 s): so diz o que verificou
  5. pos-processamento: tratamento so com prova e 1x, sem listas/titulos, <=2 bolhas, sem repetir
     o cumprimento do dia, PROMESSA = TAREFA (se disse "vou ver" sem tarefa, cria-se uma de 3 min)
  6. regista tudo (jsonl local + whatsapp_messages) e devolve a decisao
"""
import datetime
import json
import os
import re
import threading
import time

from . import ferramentas_bot as FB
from . import fichas, fio, identidade, manual, modelos, supa, tarefas, telegram

OWN = "351937501673"
ORCAMENTO_S = 20.0
MAX_VOLTAS = 6      # a prova 8 gastou 5 ferramentas certas em 4 voltas e ficou sem texto (02/09)
RE_ESTAFETA = re.compile(r"\bestafeta|\bentregador|\bmotoboy|\brider|quero trabalhar|\bvaga|ser motorista|fazer entregas|trabalhar (convosco|com voc[eê]s|no bora)", re.I)
RE_PARCEIRO = re.compile(r"\bparceir|parceria|(colocar|p[oô]r|meter|cadastrar|registar|anunciar|divulgar|meu|minha).{0,20}(restaurante|loja|neg[oó]ci|mercado|estabelecimento|pastelaria|caf[eé]|bar\b)|(restaurante|loja|neg[oó]ci).{0,20}(no bora|na app|convosco|com voc[eê]s)", re.I)

RE_ACK = re.compile(r"^(?:\W*(?:ok+|okay|okey|blz|blza|beleza|certo|combinado|👍|👌|🙏|obrigad[oa]?|obg|obgd|valeu|vlw|flw|falou|tmj|tá|ta|tá bom|ta bom|t[aá] bem|tudo bem|d ?boa|dboa|suave|tranquilo|de boa|entendi|perfeito|[óo]timo|top|show|boa|👏|❤️|😊|kk+|haha+|rs+))+\W*$", re.I)
# FERRAMENTA -> RESPOSTA, garantido em codigo para a intencao mais importante: quem fala de um pedido
# tem os dados verificados ANTES de o modelo escrever (o 7b prometia "vou verificar" sem chamar nada).
RE_PEDIDO = re.compile(r"\bpedido|\bencomenda\b|onde est[aá]|cad[eê]\b|demora|atras|chega quando|quanto tempo|a caminho|n[aã]o chegou|ainda n[aã]o (chegou|veio)|est[aá] a demorar|t[aá] demorando", re.I)
RE_DINHEIRO = re.compile(r"reembols|estorno|devolv\w* (o )?dinheiro|desconto|cupão|cupao|cobra\w+ (a mais|errad|duas vezes)|cobrança|cobranca|pagamento (nao|não) (saiu|foi)|\bmb ?way\b.*(nao|não)|fatura|preç\w+ (errad|diferente)|quanto (é|e|custa|fica)|valor|\beuro|€", re.I)
RE_RECLAMA = re.compile(r"reclam|péssimo|pessimo|horr[ií]vel|nojo|(chegou|veio) (frio|errad|estragad|aberto|partid)|faltou|nunca mais|processar|denunc|inaceit|revoltad|indignad|absurdo|vergonha", re.I)
RE_FALTA = re.compile(r"estafeta.{0,25}(nao|não|sem|falta|desapareceu|sumiu|não apareceu|nao apareceu)|parceiro.{0,20}(nao|não|fechad)|ninguém (veio|apareceu|responde)|ninguem (veio|apareceu|responde)|(nao|não) apareceu|(loja|restaurante).{0,15}(nao|não) (responde|atende)", re.I)
RE_GRUPO_HINT = re.compile(r"@g\.us", re.I)
# DETETOR DE URGENCIA (02/09 noite): sobe logo ao Danilo com resumo, antes de o bot responder
RE_URGENTE = re.compile(r"pedido errado|veio errado|trocaram|n[aã]o chegou|ainda n[aã]o (chegou|veio|recebi)|chegou frio|\bfrio\b|cobrad[oa] (duas|2) vezes|cobraram (duas|2)|duas vezes|acidente|urgente|urg[eê]ncia|socorro|assalt|pol[ií]cia|intoxica|passou mal", re.I)
RE_PROMESSA = re.compile(r"\b(vou (já )?(ver|verificar|confirmar|tratar|perguntar)|já (lhe|te) digo|já (lhe|te) respondo|dou-(lhe|te) (resposta|novidades)|deixe-me (ver|confirmar)|um (segundo|momento|instante)|vou confirmar|vou saber)\b", re.I)
RE_CUMPRIMENTO = re.compile(r"^(olá|ola|oi|bom dia|boa tarde|boa noite|hey|hi|hello)[\s,!.]*", re.I)
# OS TRES FACTOS DA OPERACAO RESPONDEM-SE POR TEXTO FIXO (02/09). O 7b local, com o facto escrito no
# prompt, ainda assim inventou "aberta todos os dias, das 8h as 22h". Um facto que o Danilo deu nao
# passa por um modelo: escreve-se e pronto.
RE_HORARIO = re.compile(r"que horas|a que hora|hor[aá]ri|\bhoras?\b.*(abre|fecha|funciona|aberto)|(abre|fecha|funciona|aberto|abrem|fecham).*horas?|quando (abre|fecha|abrem|fecham)|que dias?.*(abre|aberto|funciona)|est[aã]o abertos|at[eé] que horas|a partir de que horas", re.I)
RE_DISPONIBILIDADE = re.compile(r"(entregam|entrega|trabalham|trabalha|funciona|funcionam|abrem|abre|est[aã]o|fazem|h[aá]|tem|d[aá])\b.{0,30}\b(domingo|s[aá]bado|feriado|natal|ano novo|p[aá]scoa|de noite|à noite|a noite|madrugada|24 ?horas|agora|neste momento|hoje [aà] noite)|\b(ao|no|neste|este|aos|nos)\s+(domingo|s[aá]bado|feriado)s?\b", re.I)
RE_OUTRA_INTENCAO = re.compile(r"pedido|encomenda|reembols|parceir|estafeta|reserv|limpeza|lavagem|boleia|tvde|pre[cç]o|quanto|custa|€", re.I)
HORARIO_FIXO = ("O Bora não tem horário próprio — cada loja e restaurante tem o seu, e vê-o na app, na página da loja. "
                "Assim sabe logo quem está aberto agora.")
# iPHONE (facto do Danilo, 04/09/2026): NAO ha app para iPhone. Quem tem iPhone pede pela web.
# Vale por texto fixo (pergunta directa) E por rede de seguranca no pos-processamento: o modelo ja
# respondeu "Sim, temos! Podes descarregar na App Store" numa prova a 02/09 -- isso nao pode sair.
RE_IPHONE = re.compile(r"\biphone|\bios\b|\bapple\b|app ?store|\bipad\b|\bsafari\b", re.I)
# NEGAR UM SERVICO QUE O BORA FAZ (04/09): na rajada de prova o gemini respondeu a "Vocês fazem limpezas?"
# com "Não, nós somos uma plataforma de entrega de comida". Isso perde dinheiro. Se a pergunta e sobre uma
# vertical NOSSA e a resposta comeca por negar, sai o texto certo.
VERTICAIS = {
    "limpeza": (r"limpez|faxin|limpar a casa|empregada",
                "Fazemos sim: limpeza de casa é um dos nossos serviços. Escolhe na app, em Limpeza, e nós tratamos."),
    "lavagem": (r"lavagem|lavar o carro|lavar carro",
                "Fazemos sim: lavagem auto (por agora só exterior). Está na app, em Lavagem."),
    "tvde": (r"\btvde\b|boleia|corrida|motorista para mim|uber|bolt",
             "Fazemos sim: temos boleias (TVDE) na Guarda, e dá para reservar com antecedência na app."),
    "reservas": (r"reserv\w* de mesa|marcar mesa|reservar mesa",
                 "Fazemos sim: dá para reservar mesa nos restaurantes parceiros, na app, com um sinal de 3 €."),
    "farmacia": (r"farm[aá]ci|medicament",
                 "Fazemos sim: entregamos de farmácia aqui na Guarda. É pedir na app, em Farmácia."),
    "compras": (r"supermercad|mercado|compras|continente|pingo doce|lidl|auchan|intermarch|mercadona",
                "Fazemos sim: o estafeta faz as compras no supermercado pela sua lista e entrega em casa."),
    "encomenda": (r"encomenda|entregar (uma|um) |levar (uma|um) |favor|estafeta ir buscar",
                  "Fazemos sim: levamos e trazemos encomendas e fazemos favores aqui na Guarda. Está na app."),
}
RE_NEGA = re.compile(r"^\s*(n[ãa]o\b|infelizmente n[ãa]o|de momento n[ãa]o|ainda n[ãa]o|lamento[, ]|"
                     r"n[ãa]o (fazemos|temos|oferecemos|trabalhamos|prestamos|disponibilizamos))", re.I)
RE_NEGA_MEIO = re.compile(r"\bn[ãa]o (fazemos|temos|oferecemos|prestamos|disponibilizamos|trabalhamos com)\b|"
                          r"\bapenas (fazemos|entregamos|somos)\b|\bs[oó] (fazemos|entregamos|somos)\b", re.I)


def _corrigir_negacao_de_vertical(msg, texto):
    """Devolve (texto, vertical_corrigida). Só actua quando a PERGUNTA é sobre a vertical."""
    for nome, (padrao, certo) in VERTICAIS.items():
        if re.search(padrao, msg or "", re.I) and (RE_NEGA.search(texto or "") or RE_NEGA_MEIO.search(texto or "")):
            return certo, nome
    return texto, None
IPHONE_FIXO = ("App para iPhone não temos. No iPhone é pela web, em https://app.boraguarda.com — abre no Safari e "
               "funciona igual à app; se quiser, dá para guardar no ecrã principal.")
RE_IPHONE_MENTIRA = re.compile(
    r"(?:(?:temos|tem|há|ha|existe|disponível|disponivel|baixar|descarregar|instalar|transferir|procur\w+)[^.!?\n]{0,60}"
    r"(?:app ?store|para ?o? ?iphone|para ?ios|no ios|de ios|vers[ãa]o (?:para )?ios))"
    r"|(?:app ?store)|(?:aplica[çc][ãa]o (?:para )?(?:iphone|ios))|(?:app (?:para )?(?:iphone|ios))", re.I)
DISPONIBILIDADE_FIXA = ("Funcionamos todos os dias, incluindo domingos e feriados. A entrega naquele momento é só se houver "
                        "um estafeta livre — havendo, vai logo; se não houver, aí não dá àquela hora.")
# UM NUMERO NA RESPOSTA SEM NENHUMA FERRAMENTA TER CORRIDO E INVENCAO: horas, euros, percentagens.
RE_FACTO_INVENTADO = re.compile(r"\b\d{1,2}\s*h(?:\d{2})?\s*(?:às|as|a|-|até|ate)\s*\d{1,2}\s*h|\d+[,.]?\d*\s*€|€\s*\d|\b\d+\s*%", re.I)

FACTOS_OPERACAO = (
    "FACTOS DA OPERACAO (responde na hora, sem 'vou confirmar'): o Bora NAO tem horario proprio -- cada loja e "
    "restaurante tem o seu, e esta na app, na pagina de cada loja. Trabalhamos TODOS os dias, incluindo domingos e "
    "feriados. A entrega naquele momento depende de haver estafeta/motorista disponivel; se nao houver, nao ha "
    "entrega aquela hora. O Bora e uma app de entregas e servicos locais na Guarda, Portugal (restaurantes, "
    "mercados/compras, farmacia, lojas, favores e encomendas, reservas de mesa, limpeza, lavagem auto, TVDE/boleias). "
    "Fundador: Danilo. Pagamento na app: cartao, MB Way, ou dinheiro ate 40 EUR. "
    "NAO EXISTE APP PARA IPHONE (facto do Danilo, 04/09/2026): a app e so Android (Play Store); quem tem iPhone "
    "faz o pedido pela WEB, em https://app.boraguarda.com. NUNCA digas que ha app para iPhone, iOS, App Store ou TestFlight."
)


def _sistema(f, tratamento, lingua_, registo_, porta):
    """O prompt do agente, COMPACTO (02/09): o custo de um 7b em CPU e o prompt, nao a resposta -- a
    versao longa (~3 mil tokens) levava >150 s a frio. Os factos vivem no manual e chegam por
    ler_manual; aqui ficam so as regras, a pessoa e o indice."""
    ficha = {k: f.get(k) for k in ("nome", "nome_fonte", "papel", "falta_recolher", "prometido")}
    if f.get("papel_detalhe"):
        ficha["detalhe"] = {k: v for k, v in (f.get("papel_detalhe") or {}).items() if k in ("loja", "n_pedidos", "ultimo_pedido", "estado")}
    sempre = manual.sempre()
    partes = [
        "Es o atendimento do Bora (app de entregas e servicos na Guarda) no WhatsApp da loja. Falas como o Danilo, o "
        "fundador: curto, humano, simples, 1 a 3 frases, sem listas nem markdown nem emojis em cadeia. Nunca dizes que es "
        "um bot a nao ser que perguntem (ai: assistente do Bora; o Danilo le tudo).",
        "SO DIZES O QUE VERIFICASTE: antes de um facto (preco, horario, pedido, regra) usa ler_manual / pedidos / loja / "
        "quem_e. Nunca inventes. Se depois de verificar nao sabes: diz isso, avisar_danilo + agendar_seguimento, e que o "
        "Danilo responde ja.",
        "PROMESSA = TAREFA: 'vou ver' / 'ja lhe digo' so depois de agendar_seguimento (3 min; 30 se depende do Danilo). "
        "Melhor: verificas agora e respondes com o resultado.",
        "NUNCA empurras a pessoa para fora (outro numero, email, formulario, 'aguarde contacto'); resolve-se aqui; guiar "
        "para a app do Bora e bom. DINHEIRO/reembolso/desconto/reclamacao/estafeta ou parceiro em falta: acusas recepcao, "
        "dizes que o Danilo responde ja, avisar_danilo + agendar_seguimento(30); nunca valores.",
        "Segue o fio da conversa; nao recomecas; nao repetes o cumprimento do dia; a 'obrigado' meia frase ou nada. "
        "ESTAFETAS: sem vagas; lista de espera; registar_lead(estafeta) com nome/veiculo/zona/disponibilidade, 1-2 coisas "
        "de cada vez; avisar_danilo. PARCEIROS: venda no tom do Danilo (pomos a loja na app, clientes da Guarda pedem, "
        "nossos estafetas entregam, so prepara; comissao 10% nos pedidos no acerto semanal; a montagem da loja fica "
        "connosco); registar_lead(parceiro) a cada dado; pede 1-2 coisas de cada vez (nome, tipo, morada, horario, "
        "Instagram/Facebook ou fotos+produtos, telefone, email; NIF so no fecho); se a pessoa promete mandar algo, "
        "agradece e pergunta JA a proxima coisa em falta. PEDIDO EM ANDAMENTO: pedidos -> estado real + previsao pela "
        "media; se passou, pede desculpa.",
        FACTOS_OPERACAO,
        "MANUAL (pede seccoes com ler_manual):\n" + manual.indice()[:1500],
    ]
    if sempre:
        partes.append("VALE SEMPRE:\n" + sempre[:1200])
    # As partes que VARIAM por pessoa ficam no FIM: o Ollama guarda em cache o prefixo do ultimo
    # prompt, e so o que vem depois da primeira diferenca e reavaliado. Com a ficha a meio, cada
    # chamada reavaliava o indice do manual inteiro (medido: 182 s a frio, 15 s com o prefixo quente).
    partes += [
        "TRATAMENTO: " + identidade.instrucao_tratamento(tratamento, f),
        "LINGUA: %s. %s" % ({"pt-PT": "portugues de Portugal", "pt-BR": "portugues do Brasil", "en": "short English"}.get(lingua_, "portugues de Portugal"),
                            "Trata por 'tu'." if registo_ == "tu" else "Trata por 'voce'."),
        "PESSOA: " + json.dumps(ficha, ensure_ascii=False)[:700],
    ]
    return "\n\n".join(partes)


def _sistema_longo(f, tratamento, lingua_, registo_, porta):
    """A versao longa, guardada para referencia; nao se usa (ver _sistema)."""
    partes = [
        "Es o atendimento do Bora no WhatsApp da loja (Guarda, Portugal). Falas como o Danilo, o fundador: curto, humano, "
        "palavras simples, sem listas, sem titulos, sem emojis em cadeia. Duas frases chegam na maioria dos casos. "
        "Nunca soas a robot e nunca dizes que es um bot, a nao ser que te perguntem directamente -- ai dizes que es o "
        "assistente do Bora e que o Danilo tambem le tudo.",
        "REGRA DE OURO: so dizes o que VERIFICASTE. Antes de afirmar um facto (preco, horario, estado de pedido, regra, "
        "como funciona algo) usa as ferramentas: ler_manual, pedidos, loja, quem_e. NUNCA inventes. Se depois de "
        "verificar continuas sem saber, diz isso, chama avisar_danilo E agendar_seguimento -- e diz a pessoa que o "
        "Danilo responde ja.",
        "PROMESSA = TAREFA: estas PROIBIDO de escrever 'vou ver', 'vou verificar', 'ja lhe digo' sem antes chamar "
        "agendar_seguimento (3 minutos; 30 se depende do Danilo). Melhor ainda: nem prometes -- verificas AGORA com as "
        "ferramentas e respondes ja com o resultado.",
        "NUNCA empurras a pessoa para fora da conversa: nada de 'contacte outro numero', 'mande email', 'preencha o "
        "formulario', 'aguarde contacto'. Resolve-se aqui; se precisas de algo, pedes aqui e tratas tu. Guiar para a "
        "app do Bora e bom (e o nosso produto).",
        "DINHEIRO, reembolsos, descontos, reclamacoes, estafeta ou parceiro em falta: nao decides -- acusas recepcao com "
        "uma frase humana, dizes que o Danilo responde ja, chamas avisar_danilo e agendar_seguimento(30). Nunca dizes "
        "valores nem prometes reembolso.",
        "Segue o fio da conversa: se a pessoa responde 'beleza, vou mandar as fotos', continua a recolher -- nao recomecas, "
        "nao confirmas o que ja esta confirmado. Nunca repetes o cumprimento na mesma conversa do dia. A 'obrigado' "
        "respondes com meia frase ou nada.",
        "ESTAFETAS: sem vagas de momento; educado; fica em lista de espera; recolhe nome, veiculo, zona e "
        "disponibilidade (uma ou duas coisas de cada vez) com registar_lead(tipo='estafeta'); avisa o Danilo.",
        "PARCEIROS interessados (por o restaurante/loja no Bora): conversa de venda no tom do Danilo -- explica que pomos "
        "a loja na app, os clientes da Guarda pedem, os nossos estafetas entregam, o parceiro so prepara; a comissao e "
        "10% sobre os pedidos, no acerto semanal; e a montagem da loja fica connosco. Vai pedindo ao ritmo da conversa, "
        "uma ou duas coisas de cada vez: nome da loja, tipo, morada, horario, Instagram/Facebook (para ir buscar fotos e "
        "produtos) ou fotos e lista de produtos com precos, telefone, email, takeaway/reservas; NIF so quando fechar. "
        "Cada dado entra com registar_lead. Quando tiveres nome + tipo + redes ou fotos, chama avisar_danilo com o resumo "
        "e diz a pessoa que a loja vai ser montada para ela ver e aprovar. Se a pessoa PROMETE mandar algo ('vou mandar "
        "as fotos', 'depois envio'), agradece numa frase curta e pergunta JA a proxima coisa em falta (ver "
        "falta_recolher na ficha: nome da loja, tipo, morada...) -- nunca recomecas a explicacao, nunca dizes 'vou confirmar'.",
        "PEDIDO EM ANDAMENTO ('demora', 'onde esta', 'cade'): chama pedidos, e responde com o estado real e a previsao "
        "pela media real. Se ja passou da media, pedes desculpa e explicas. Nunca dizes valores de dinheiro.",
        FACTOS_OPERACAO,
        "TRATAMENTO: " + identidade.instrucao_tratamento(tratamento, f),
        "LINGUA E REGISTO: responde em %s%s. %s" % (
            {"pt-PT": "portugues de Portugal", "pt-BR": "portugues do Brasil", "en": "ingles curto"}.get(lingua_, "portugues de Portugal"),
            "" if lingua_ != "en" else " (short English)",
            "Trata por 'tu' (a pessoa usa 'tu')." if registo_ == "tu" else "Trata por 'voce'."),
        "QUEM E A PESSOA (ficha): " + json.dumps({k: f.get(k) for k in ("nome", "nome_fonte", "papel", "papel_detalhe", "o_que_pediu", "prometido", "falta_recolher", "notas")}, ensure_ascii=False)[:1500],
        "INDICE DO MANUAL (pede a seccao com ler_manual):\n" + manual.indice(),
    ]
    sempre = manual.sempre()
    if sempre:
        partes.append("VALE SEMPRE (correcoes do Danilo, licoes, sobre o Danilo):\n" + sempre[:3500])
    partes.append("FORMATO DA RESPOSTA: texto corrido, 1 a 3 frases; se precisares de duas bolhas separa com uma linha vazia. "
                  "Sem markdown, sem listas, sem 'Ola' se ja cumprimentaste hoje.")
    return "\n\n".join(partes)


RE_TITULO_MANUAL = re.compile(r"\b\d{1,2}\.\d?\s*[A-ZÁÉÍÓÚÂÊÔÃÕÇ][A-ZÁÉÍÓÚÂÊÔÃÕÇ ,\-/\(\)\"“”']{5,}[:\-]?\s*", re.U)


def _resumo_pedidos(res):
    """Texto deterministico a partir do resultado REAL da ferramenta pedidos (para quando o modelo
    promete 'vou verificar' com os dados ja na mao -- aconteceu com o 7b local, 02/09)."""
    ps = (res or {}).get("pedidos") or []
    if not ps:
        return "Vi agora e não encontro nenhum pedido activo neste número. Se fez o pedido com outro número ou conta, diga-me qual, que eu vejo."
    p = ps[0]
    loja = (" do %s" % p["loja"]) if p.get("loja") else ""
    if p.get("activo"):
        prev = p.get("previsao") or ""
        if "passou" in prev:
            return "Vi agora: o seu pedido%s está %s e já passou do tempo normal — peço desculpa. Estou em cima dele e aviso-o assim que sair." % (loja, p.get("estado"))
        return "Vi agora: o seu pedido%s está %s; previsão de %s." % (loja, p.get("estado"), prev or "poucos minutos")
    h = p.get("ha_minutos")
    quando = (" há cerca de %d min" % h) if h is not None and h < 180 else (" há cerca de %d h" % (h // 60) if h else "")
    return "Vi agora: o seu último pedido%s ficou %s%s. Se for outro pedido, diga-me qual." % (loja, p.get("estado"), quando)


def _pos_processar(texto, f, tratamento, cumprimentou_hoje):
    t = (texto or "").strip()
    t = re.sub(r"<think>.*?</think>\s*", "", t, flags=re.S)   # raciocinio de modelos "thinking" (qwen3.6 no Groq, 02/09)
    t = re.sub(r"<think>.*$", "", t, flags=re.S)
    t = re.sub(r"[*_#`>]+", "", t)                       # sem markdown
    t = re.sub(r"(?m)^\s*[-•]\s+", "", t)                # sem listas
    t = RE_TITULO_MANUAL.sub("", t)                       # titulos do manual colados na resposta (7b)
    t = re.sub(r"VERIFICADO AGORA[^\n]*", "", t, flags=re.I)
    if RE_IPHONE_MENTIRA.search(t):              # 04/09: nunca sai "há app para iPhone"/"App Store"
        t = IPHONE_FIXO
    t = identidade.limpar_tratamento(t, tratamento, f)
    if cumprimentou_hoje:
        t = RE_CUMPRIMENTO.sub("", t, count=1).strip()
        t = t[:1].upper() + t[1:] if t else t
    t = re.sub(r"([\U0001F300-\U0001FAFF☀-➿]\s*){3,}", lambda m: m.group(0)[:2], t)   # sem emojis em cadeia
    bolhas = [b.strip() for b in re.split(r"\n\s*\n", t) if b.strip()]
    if len(bolhas) > 2:
        bolhas = [bolhas[0], " ".join(bolhas[1:])]
    bolhas = [b[:900] for b in bolhas]
    return bolhas


def _escalar_texto(motivo, tratamento, f, lingua_):
    nome = (" " + f["nome"].split()[0]) if tratamento == "nome" else ""
    if lingua_ == "en":
        return ["Got it%s — I've passed this to Danilo and he'll reply here shortly." % (", " + f["nome"].split()[0] if nome else "")]
    base = {"dinheiro": "Recebi%s, e já passei ao Danilo — é ele que trata de valores e reembolsos, e responde-lhe já por aqui.",
            "reclamacao": "Lamento mesmo%s. Já passei ao Danilo com tudo o que me disse, e ele responde-lhe já por aqui.",
            "falta": "Percebo%s, isso não devia ter acontecido. Já avisei o Danilo agora mesmo e ele vem já responder-lhe."}
    return [base.get(motivo, base["dinheiro"]) % nome]


def _executar_com_orcamento(c, ctx, t0, dec, emitir):
    """Corre a ferramenta numa thread. Se os 20 s se esgotarem a meio, sai JA a frase de espera
    (pela porta, se houver `emitir`) + tarefa de 3 min, e continua-se a esperar pelo resultado.
    E a regra 'se a ferramenta demora mais de 20 s: envia um segundo que vou ver E cria a tarefa'."""
    caixa = {}

    def _run():
        caixa["res"] = FB.executar(c["name"], c.get("args"), ctx)

    th = threading.Thread(target=_run, daemon=True)
    th.start()
    th.join(max(0.5, ORCAMENTO_S - (time.time() - t0)))
    if th.is_alive():
        if not dec.get("interino"):
            t = tarefas.criar(ctx["numero"], "ferramenta lenta: " + str(c["name"]), 3, "agente-orcamento")
            dec["tarefas"].append(t["id"])
            dec["interino"] = _frase_especifica(ctx.get("msg_actual", ""), None, False)
            dec["interino_em_s"] = round(time.time() - t0, 1)
            fichas.anotar_promessa(ctx["ficha"], "ver (" + str(c["name"]) + ")", "aberta", t["id"])
            if emitir:
                emitir(ctx["numero"], dec["interino"], "interino")
        th.join(150)
    return caixa.get("res") or {"ok": False, "erro": "a ferramenta nao respondeu a tempo"}


# ---------------------------------------------------------------- CAMINHO RAPIDO (Danilo, 02/09 10:20)
# Provado no banco: 57 s e 90 s por resposta com o nemotron a encadear ferramentas. Regra nova:
#   - cumprimentos e perguntas do manual respondem-se SEM ferramenta nenhuma;
#   - `pedidos` corre so quando a pessoa fala de pedido/entrega (RE_PEDIDO), ANTES do modelo;
#   - UMA chamada ao modelo, sem tools, com os factos ja verificados no prompt;
#   - o modelo NUNCA escreve "vou ver"/"dou-lhe resposta em 3 minutos": sem resultado de ferramenta
#     por tras, o codigo rejeita e pede outra vez; a segunda vez cai num texto deterministico e o
#     Danilo entra -- nunca uma promessa vazia, nunca silencio.
# Meta medida: resposta em menos de 10 s em 9 de cada 10 mensagens.
RAPIDO = os.environ.get("CEREBRO_RAPIDO", "1") != "0"
RE_SO_CUMPRIMENTO = re.compile(
    r"^\W*(olá|ola|oi+|oie|bom dia|boa tarde|boa noite|boas|hey|hi|hello|e a[ií]|eai|opa)"
    r"(\W+(tudo bem|td bem|tudo bom|tudo certo|como (est[aá]|vai)|blz|beleza|bom dia|boa tarde|boa noite))*\W*$", re.I)
SEM_RESPOSTA_TEXTO = "Não tenho essa informação aqui à mão — já passei ao Danilo e ele responde-lhe por aqui."
TEXTO_ESTAFETA = ("De momento não há vagas para estafeta — a equipa está completa e as aprovações dependem da procura. "
                  "Fico com o seu contacto na lista de espera e aviso-o assim que abrir vaga. Pode dizer-me o seu nome e "
                  "que veículo tem (mota, carro ou bicicleta)?")
TEXTO_PARCEIRO = ("Boa! Funciona assim: pomos o seu negócio na app do Bora, os clientes da Guarda fazem o pedido e os nossos "
                  "estafetas entregam — só prepara. Entrar é grátis e a comissão é de 10% sobre os pedidos, no acerto semanal. "
                  "A montagem da loja fica connosco: manda-me o Instagram ou Facebook da casa, ou fotos e a lista de produtos "
                  "com preços. Qual é o nome do negócio?")


def _sistema_rapido(f, tratamento, lingua_, registo_):
    """Prompt do caminho rapido: sem ferramentas, so regras + factos + pessoa. Curto, porque num 7b em
    CPU o custo e o prompt; e as partes que variam ficam no fim (cache de prefixo do Ollama)."""
    ficha = {k: f.get(k) for k in ("nome", "papel", "falta_recolher")}
    det = f.get("papel_detalhe") or {}
    if det:
        ficha["detalhe"] = {k: v for k, v in det.items() if k in ("loja", "n_pedidos", "ultimo_pedido", "estado")}
    sempre = manual.sempre()
    partes = [
        "Es o atendimento do Bora (app de entregas e servicos na Guarda, Portugal) no WhatsApp da loja. Falas como o "
        "Danilo, o fundador: curto, humano, simples, 1 a 3 frases, sem listas, sem markdown, sem emojis em cadeia. Nunca "
        "dizes que es um bot a nao ser que perguntem (ai: assistente do Bora; o Danilo le tudo).",
        "SO DIZES O QUE ESTA VERIFICADO: nos FACTOS DA OPERACAO, no MANUAL que te derem, ou no resultado de 'pedidos'. "
        "Nunca inventes precos, horarios, prazos ou regras. Se nao tens a informacao, diz numa frase que nao tens isso a "
        "mao e que o Danilo responde por aqui. PROIBIDO escrever 'vou ver', 'vou verificar', 'ja lhe digo', 'um momento', "
        "'dou-lhe resposta em X minutos' -- nao ha nada para ir ver: ou respondes com o que tens, ou dizes que o Danilo "
        "responde.",
        "NUNCA empurras a pessoa para fora (outro numero, email, formulario, 'aguarde contacto'); resolve-se aqui; guiar "
        "para a app do Bora e bom. Dinheiro/reembolso/desconto/reclamacao: acusas recepcao e dizes que o Danilo responde "
        "ja; nunca valores.",
        "Segue o fio da conversa; nao recomecas; nao repetes o cumprimento; a 'obrigado' meia frase. ESTAFETAS: sem vagas, "
        "lista de espera, pede 1-2 dados (nome, veiculo, zona, disponibilidade). PARCEIROS: venda no tom do Danilo (pomos a "
        "loja na app, clientes da Guarda pedem, nossos estafetas entregam, so prepara; comissao 10% no acerto semanal; a "
        "montagem da loja fica connosco); pede 1-2 coisas de cada vez. PEDIDO: usa os dados de 'pedidos' -- estado real e "
        "previsao; se passou da media, pede desculpa.",
        "NOMES: so usas um nome se a linha TRATAMENTO o der. Nunca apanhes nomes de mensagens antigas nem de textos.",
        FACTOS_OPERACAO,
    ]
    if sempre:
        partes.append("VALE SEMPRE:\n" + sempre[:900])
    partes += [
        "TRATAMENTO: " + identidade.instrucao_tratamento(tratamento, f),
        "LINGUA: %s. %s" % ({"pt-PT": "portugues de Portugal", "pt-BR": "portugues do Brasil", "en": "short English"}.get(lingua_, "portugues de Portugal"),
                            "Trata por 'tu'." if registo_ == "tu" else "Trata por 'voce'."),
        "PESSOA: " + json.dumps(ficha, ensure_ascii=False)[:400],
    ]
    return "\n\n".join(partes)


def _socorro_recente(f):
    """A frase de espera generica sai UMA vez por conversa e por dia (02/09 noite: saiu 4x seguidas)."""
    ja = (f.get("extra") or {}).get("socorro_em")
    try:
        return bool(ja) and (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(ja)).total_seconds() < 86400
    except Exception:
        return False


def _marcar_socorro(f):
    f["extra"] = dict(f.get("extra") or {}, socorro_em=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"))


def _frase_especifica(msg, tipo_lead, tem_pedido):
    """UMA frase humana curta ESPECIFICA ao pedido -- nunca a generica 'estou a ver'."""
    if tem_pedido:
        return "Estou a ver o seu pedido no sistema agora mesmo."
    if tipo_lead == "estafeta":
        return "Recebi o seu interesse em ser estafeta — já lhe digo como funciona a lista de espera."
    if tipo_lead == "parceiro":
        return "Recebi — já lhe explico como pomos o seu negócio no Bora."
    tema = re.sub(r"[?!.]+", "", " ".join((msg or "").split()[:7])).strip().lower()
    return ("Recebi a sua pergunta sobre \"%s\" — já lhe respondo." % tema) if tema else "Recebi a sua mensagem — já lhe respondo."


def _fechar(dec, f, ctx, texto, tratamento, prova, lingua_, cumprimentou_hoje, modelo, ferramentas, erro, t0, registar, msg=None):
    """Pos-processamento + PROMESSA = TAREFA + FIO (ultimas trocas) + ficha + decisao."""
    numero = ctx["numero"]
    bolhas = _pos_processar(texto, f, tratamento, cumprimentou_hoje)
    if not bolhas:
        bolhas = [identidade.saudacao(tratamento, f, lingua_)] if not cumprimentou_hoje else ["Diga."]
    dec["tarefas"] += list(ctx.get("tarefas_criadas") or [])
    junto = " ".join(bolhas)
    if RE_PROMESSA.search(junto) and not dec["tarefas"]:
        t = tarefas.criar(numero, "promessa automatica: " + junto[:100], 3, "agente-auto")
        dec["tarefas"].append(t["id"])
        fichas.anotar_promessa(f, junto[:100], "aberta", t["id"])
    elif not RE_PROMESSA.search(junto) and not dec["tarefas"]:
        n = tarefas.cumprir_todas(numero, "respondeu com resultado")
        if n:
            for p in f.get("prometido") or []:
                if p.get("estado") == "aberta":
                    p["estado"] = "cumprida"
    if msg is not None:
        fio.anotar_troca(f, "entrada", msg)
    fio.anotar_troca(f, "saida", junto)
    fichas.marcar_cumprimento(f)
    f["ultima_resposta_bot_em"] = fichas.agora()
    fichas.guardar(f)
    dec.update(acao="responder", textos=bolhas, modelo=modelo, ferramentas=ferramentas,
               danilo_avisado=bool(ctx.get("danilo_avisado")), erro=erro, segundos=round(time.time() - t0, 1),
               tratamento=tratamento, prova_tratamento=prova, lingua=lingua_, caminho=dec.get("caminho") or "rapido")
    return dec


def _rapido(ctx, f, msg, tratamento, prova, lingua_, registo_, cumprimentou_hoje, t0, dec, registar, emitir):
    numero = ctx["numero"]
    ctx["msg_actual"] = msg
    desculpa = bool(f.pop("desculpa_nome", False))
    prefixo = "Peço desculpa pela confusão com o nome. " if desculpa else ""
    ferramentas_usadas = []

    # a) cumprimento puro: sem modelo, sem ferramenta
    if len(msg) <= 40 and RE_SO_CUMPRIMENTO.match(msg):
        if lingua_ == "en":
            texto = "Hi! How can I help?" if not cumprimentou_hoje else "Tell me — how can I help?"
        else:
            texto = identidade.saudacao(tratamento, f, lingua_) if not cumprimentou_hoje else "Diga, em que posso ajudar?"
        return _fechar(dec, f, ctx, prefixo + texto, tratamento, prova, lingua_, cumprimentou_hoje, "cumprimento-fixo", [], None, t0, registar, msg=msg)

    # b) o que precisa de dados verifica-se ANTES do modelo, em codigo
    factos, pre_resultados = [], {}
    tipo_lead = "parceiro" if RE_PARCEIRO.search(msg) else ("estafeta" if RE_ESTAFETA.search(msg) else None)
    if RE_PEDIDO.search(msg):
        res = _executar_com_orcamento({"name": "pedidos", "args": {}, "id": "pre_pedidos"}, ctx, t0, dec, emitir)
        pre_resultados["pedidos"] = res
        ferramentas_usadas.append({"nome": "pedidos", "args": {}, "ok": res.get("ok"), "origem": "pre"})
        factos.append("VERIFICADO AGORA com a ferramenta pedidos (responde com ESTES dados; nunca 'vou verificar'):\n" + FB.para_json(res)[:2500])
    if tipo_lead:
        # seguro dos leads: registar e avisar e contabilidade, nao opiniao do modelo. O Telegram vai em THREAD:
        # custava 3-5 s por resposta (o "Quero ser estafeta" de 21:07 levou 10,4 s).
        res = FB.executar("registar_lead", {"tipo": tipo_lead, "dados": {"mensagem": msg[:160]}}, ctx)
        ferramentas_usadas.append({"nome": "registar_lead", "args": {"tipo": tipo_lead}, "ok": res.get("ok"), "origem": "seguro"})
        if not ctx.get("danilo_avisado"):
            ctx["danilo_avisado"] = True
            threading.Thread(target=FB.executar, args=("avisar_danilo", {"texto": "Novo interessado em ser %s (%s): \"%s\"" % (
                tipo_lead, f.get("nome") or "sem nome", msg[:160])}, dict(ctx)), daemon=True).start()
            ferramentas_usadas.append({"nome": "avisar_danilo", "args": {"tipo": tipo_lead}, "ok": None, "origem": "seguro-async"})
        tema = "quer ser parceiro conversa de venda" if tipo_lead == "parceiro" else "quer ser estafeta sem vagas lista de espera"
        trecho = manual.ler(tema, max_chars=1400)
        if not trecho.startswith("NADA NO MANUAL"):
            factos.append("MANUAL (facto verificado, usa-o):\n" + trecho)
        falta = [c for c in (res.get("falta_recolher") or []) if c in fio.PERGUNTAS]
        if falta:
            fio.esperar(f, falta[0], tipo_lead)      # a proxima mensagem e lida como resposta a isto (FIO)
            factos.append("O LEAD JA ESTA REGISTADO e o Danilo JA FOI AVISADO pelo sistema: nao digas que vais registar ou avisar. "
                          "Pede APENAS isto, no fim da resposta: %s" % fio.PERGUNTAS[falta[0]])
        else:
            factos.append("O LEAD JA ESTA REGISTADO e o Danilo JA FOI AVISADO pelo sistema: nao digas que vais registar ou avisar.")
    else:
        trecho = manual.ler(msg[:200], max_chars=1400, registar=False) if len(msg) >= 4 else "NADA NO MANUAL"
        if not trecho.startswith("NADA NO MANUAL"):
            factos.append("MANUAL DO BORA (facto verificado; so respondes com o que esta aqui ou nos FACTOS DA OPERACAO):\n" + trecho)
    dados_na_mao = bool(pre_resultados) or bool(tipo_lead) or any(x.startswith("MANUAL") for x in factos)

    # c) UMA chamada ao modelo, sem ferramentas, com o FIO (ultimas 10 trocas) no contexto
    mensagens = [{"role": "system", "content": _sistema_rapido(f, tratamento, lingua_, registo_)}]
    mensagens += [{"role": "system", "content": x} for x in factos]
    if desculpa:
        mensagens.append({"role": "system", "content": "A pessoa acabou de dizer que NAO se chama assim. O sistema ja apagou o nome e ja "
                                                       "pede desculpa por ti: NAO uses nome nenhum e responde so ao resto."})
    historico = fio.historico_para_modelo(f)
    if historico:
        mensagens.append({"role": "system", "content": "CONVERSA ATE AGORA (segue o fio; nao recomeces; nao repitas o que ja disseste):"})
        mensagens += historico
    mensagens.append({"role": "user", "content": msg})
    caixa = {}

    def _chamar(perfil, extra=None):
        ms = mensagens + ([{"role": "system", "content": extra}] if extra else [])
        return modelos.chat(ms, tools=None, max_tokens=220, perfil=perfil)

    def _correr():
        r = _chamar("chat-rapido")
        caixa["modelo"], caixa["erro"] = r.get("modelo"), r.get("erro")
        texto = (r.get("texto") or "").strip()
        if not texto:
            # DUAS VELOCIDADES: os motores rapidos falharam -> UMA frase humana ESPECIFICA (nunca a generica,
            # e nunca duas vezes na mesma conversa), e o perfil de raciocinio completa a resposta.
            caixa["rapidos_falharam"] = True
            if emitir and not dec.get("interino") and not _socorro_recente(f):
                frase = _frase_especifica(msg, tipo_lead, bool(pre_resultados))
                _marcar_socorro(f)
                dec["interino"], dec["interino_em_s"] = frase, round(time.time() - t0, 1)
                emitir(numero, frase, "interino-especifico")
            r = _chamar("raciocinio")
            caixa["modelo"] = r.get("modelo") or caixa["modelo"]
            caixa["erro"] = r.get("erro") or caixa["erro"]
            texto = (r.get("texto") or "").strip()
        # d) PROMESSA SEM FERRAMENTA: rejeita-se e pede-se outra vez; a segunda cai no deterministico
        if texto and RE_PROMESSA.search(texto) and not pre_resultados:
            registar({"evento": "promessa-rejeitada", "numero": numero, "texto": texto[:160], "modelo": r.get("modelo")})
            caixa["rejeitada"] = texto[:160]
            r = _chamar("chat-rapido", "PROIBIDO prometer ('vou ver', 'vou verificar', 'ja lhe digo', 'um momento', 'dou-lhe resposta'): nao "
                                       "tens nada para ir ver. Responde AGORA com o que esta no manual e nos factos, ou diz numa frase que nao "
                                       "tens essa informacao e que o Danilo responde por aqui.")
            caixa["modelo"] = r.get("modelo") or caixa["modelo"]
            texto = (r.get("texto") or "").strip()
            if texto and RE_PROMESSA.search(texto):
                caixa["rejeitada2"] = texto[:160]
                texto = ""
        caixa["texto"] = texto

    th = threading.Thread(target=_correr, daemon=True)
    th.start()
    th.join(ORCAMENTO_S)
    if th.is_alive() and not dec.get("interino") and not _socorro_recente(f):
        frase = _frase_especifica(msg, tipo_lead, bool(pre_resultados))
        t = tarefas.criar(numero, "resposta lenta: " + msg[:80], 3, "agente-orcamento")
        dec["tarefas"].append(t["id"])
        dec["interino"], dec["interino_em_s"] = frase, round(time.time() - t0, 1)
        _marcar_socorro(f)
        fichas.anotar_promessa(f, "ver: " + msg[:60], "aberta", t["id"])
        if emitir:
            emitir(numero, frase, "interino")
    th.join(150)
    texto, modelo_usado, erro = caixa.get("texto") or "", caixa.get("modelo"), caixa.get("erro")
    if th.is_alive() and not texto:
        erro = ((erro or "") + " | a cadeia nao respondeu em 170 s").strip(" |")
    if caixa.get("rejeitada"):
        dec["promessa_rejeitada"] = caixa["rejeitada"]
    if caixa.get("rapidos_falharam"):
        dec["rapidos_falharam"] = True
    if desculpa and texto:
        texto = re.sub(r"^\s*(?:pe[çc]o(?: imensa)? desculpa|desculp[ae]|as minhas desculpas|lamento|sinto muito)[^.!?\n]*[.!?]\s*", "", texto, flags=re.I).strip()

    # e) pedido verificado mas o modelo prometeu na mesma (ou nao escreveu): resumo dos dados reais
    if pre_resultados.get("pedidos", {}).get("ok") and (not texto or RE_PROMESSA.search(texto)):
        if texto:
            registar({"evento": "promessa-com-dados-na-mao", "numero": numero, "texto": texto[:160], "modelo": modelo_usado})
        texto = _resumo_pedidos(pre_resultados["pedidos"])
        modelo_usado = modelo_usado or "resumo-pedidos"
    # f) numero (horas, euros, %) sem nada verificado = invencao
    if texto and not dados_na_mao and RE_FACTO_INVENTADO.search(texto):
        registar({"evento": "facto-inventado-bloqueado", "numero": numero, "texto": texto[:200], "modelo": modelo_usado})
        dec["facto_inventado_bloqueado"] = texto[:200]
        texto = HORARIO_FIXO if RE_HORARIO.search(msg) else (DISPONIBILIDADE_FIXA if RE_DISPONIBILIDADE.search(msg) else "")
    # f2) NEGOU UM SERVICO QUE NOS FAZEMOS: sai o texto certo (perder um cliente por isto e o pior que ha)
    if texto:
        novo, vertical = _corrigir_negacao_de_vertical(msg, texto)
        if vertical:
            registar({"evento": "negacao-de-vertical-corrigida", "numero": numero, "vertical": vertical,
                      "texto": texto[:200], "modelo": modelo_usado})
            dec["negacao_corrigida"] = vertical
            texto = novo
    # g) sem texto: NUNCA silencio e NUNCA "dou-lhe resposta em 3 minutos" -- a intencao ou o Danilo
    if not texto and tipo_lead == "estafeta":
        texto, dec["fallback_intencao"] = TEXTO_ESTAFETA, "estafeta"
    elif not texto and tipo_lead == "parceiro":
        texto, dec["fallback_intencao"] = TEXTO_PARCEIRO, "parceiro"
    if not texto:
        t = tarefas.criar(numero, "danilo: sem resposta do modelo: " + msg[:100], 30, "danilo-sem-resposta")
        dec["tarefas"].append(t["id"])
        threading.Thread(target=telegram.enviar, args=("WhatsApp da loja — %s escreveu \"%s\" e eu não soube responder (%s). Responde-lhe por aqui." % (
            numero, msg[:200], erro or caixa.get("rejeitada2") or "sem texto"), registar), daemon=True).start()
        fichas.anotar_promessa(f, "Danilo responde: " + msg[:60], "aberta", t["id"])
        texto, dec["fallback_intencao"] = SEM_RESPOSTA_TEXTO, dec.get("fallback_intencao") or "danilo"
    return _fechar(dec, f, ctx, prefixo + texto, tratamento, prova, lingua_, cumprimentou_hoje, modelo_usado, ferramentas_usadas, erro, t0, registar, msg=msg)


SOMBRAS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_sombras.jsonl")


def sombra_do_danilo(numero, texto_danilo, registar=None):
    """SOMBRA DO DANILO (02/09 noite): quando o Danilo responde a mao, o cerebro calcula o que ELE PROPRIO
    teria dito a mesma mensagem (so o prompt rapido -- sem ferramentas, sem tarefas, sem enviar), pede ao
    perfil de raciocinio UMA regra de tom que aproxime o bot do dono, e guarda-a como licao. A revisao
    diaria propoe a melhor ao Danilo. Sem efeitos secundarios na ficha alem da nota."""
    registar = registar or (lambda o: None)
    try:
        f = fichas.carregar(numero)
        f.pop("_nova", False)
        entradas = [t for t in (f.get("ultimas_trocas") or []) if t.get("dir") == "entrada"]
        if not entradas:
            return
        ultima = entradas[-1].get("texto") or ""
        tratamento = f.get("tratamento") or "neutro"
        mensagens = [{"role": "system", "content": _sistema_rapido(f, tratamento, f.get("lingua") or "pt-PT", f.get("registo") or "voce")}]
        mensagens += fio.historico_para_modelo(f)[:-1]
        mensagens.append({"role": "user", "content": ultima})
        r = modelos.chat(mensagens, tools=None, max_tokens=220, perfil="raciocinio")
        bot = (r.get("texto") or "").strip()
        r2 = modelos.chat([{"role": "system", "content": "Compara a resposta do DONO (Danilo, fundador do Bora) com a do BOT a mesma mensagem de cliente. "
                                                          "Devolve UMA regra de tom curta (maximo 160 caracteres), em portugues, que faria o BOT escrever mais como o dono. So a regra, sem explicacoes."},
                          {"role": "user", "content": "CLIENTE: %s\nDONO: %s\nBOT: %s" % (ultima[:400], texto_danilo[:400], bot[:400] or "(sem resposta)")}],
                         tools=None, max_tokens=120, perfil="raciocinio")
        regra = (r2.get("texto") or "").strip().split("\n")[0].strip("-• \"")[:160]
        linha = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "numero": numero, "cliente": ultima[:300],
                 "danilo": texto_danilo[:300], "bot": bot[:300], "regra": regra, "modelo": r2.get("modelo")}
        with open(SOMBRAS, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(linha, ensure_ascii=False) + "\n")
        if regra:
            manual.registar_licao("sombra do Danilo (%s): %s" % (numero[-3:], regra))
        f["extra"] = dict(f.get("extra") or {}, ultima_sombra={"em": linha["ts"], "regra": regra})
        fichas.guardar(f)
        registar({"evento": "sombra", "numero": numero, "regra": regra, "bot": bot[:120], "danilo": texto_danilo[:120]})
    except Exception as e:  # noqa: BLE001
        registar({"evento": "sombra-erro", "numero": numero, "erro": "%s: %s" % (type(e).__name__, str(e)[:200])})


def atender(evento, registar=None, modo_prova=False, emitir=None):
    """evento = {numero, msg_ids:[], textos:[], audios:[caminhos], imagens:[caminhos], nome_guardado, porta, grupo}
    Devolve decisao = {acao, textos, motivo, modelo, tarefas, ficha, transcricoes, segundos}."""
    t0 = time.time()
    registar = registar or (lambda o: None)
    if modo_prova:
        telegram.SILENCIO = True          # provas: o Danilo nao e incomodado; o log diz o que se teria enviado
    numero = fichas.so_digitos(evento.get("numero"))
    porta = evento.get("porta") or "pc-extensao"
    dec = {"acao": "silencio", "textos": [], "motivo": "", "modelo": None, "tarefas": [], "transcricoes": [], "descricoes": []}

    if evento.get("grupo") or RE_GRUPO_HINT.search(" ".join(evento.get("msg_ids") or [])):
        dec.update(acao="ignorar-grupo", motivo="grupo: nunca")
        return dec
    if not numero or numero == OWN:
        dec.update(acao="ignorar", motivo="sem numero ou e a propria loja")
        return dec

    # 1. ficha
    f = fichas.carregar(numero)
    nova = f.pop("_nova", False)
    if nova or not f.get("papel_detalhe"):
        fichas.cruzar_supabase(f)
    if evento.get("nome_guardado") and not f.get("nome"):
        f["nome"], f["nome_fonte"] = evento["nome_guardado"][:80], "contacto_guardado"
    f["ultima_msg_em"] = fichas.agora()

    # 2. audio e imagem -> texto
    textos = [t for t in (evento.get("textos") or []) if (t or "").strip()]
    from . import transcricao
    for a in evento.get("audios") or []:
        txt, motor, erros = transcricao.transcrever(a)
        dec["transcricoes"].append({"ficheiro": a, "texto": txt, "motor": motor, "erros": erros})
        textos.append(("[áudio transcrito] " + txt) if txt else "[áudio que não consegui ouvir]")
    for im in evento.get("imagens") or []:
        desc, erro = transcricao.ver_imagem(im, "papel=%s nome=%s" % (f.get("papel"), f.get("nome")))
        dec["descricoes"].append({"ficheiro": im, "descricao": desc, "erro": erro})
        textos.append(("[imagem: " + desc + "]") if desc else "[imagem que não consegui ver]")
    msg = "\n".join(textos).strip()
    if not msg:
        dec.update(acao="ignorar", motivo="sem conteudo")
        return dec

    # 3. identidade e portao deterministico
    lingua_ = identidade.lingua(msg, f.get("lingua"))
    registo_ = identidade.registo(msg, f.get("registo"))
    tratamento, prova = identidade.decidir_tratamento(f, msg)
    f["tratamento"] = tratamento
    fichas.aprender_estilo(f, msg, lingua_, registo_)
    fichas.anotar_pedido(f, msg[:140])
    ctx = {"numero": numero, "ficha": f, "registar": registar, "porta": porta, "msg_actual": msg}

    if fichas.pausado(f):
        fichas.guardar(f)
        dec.update(acao="silencio-pausado", motivo="bot pausado/assumido pelo Danilo neste contacto")
        return dec
    so_ack = all(RE_ACK.match(t) for t in textos if not t.startswith("[")) and "?" not in msg
    if so_ack and len(msg) <= 40:
        fichas.guardar(f)
        dec.update(acao="ignorar-ack", motivo="so agradecimento/ok")
        return dec

    # 3a. O FIO (falha G): se o bot pediu algo, a mensagem e lida PRIMEIRO como resposta a isso -- em codigo, sem modelo
    lead_dados = {}
    if fio.a_espera(f):
        try:
            l = supa.um("whatsapp_leads", id="eq." + str(f["lead_id"])) if f.get("lead_id") else None
            lead_dados = (l or {}).get("dados") or {}
        except Exception:
            lead_dados = {}
        r_fio = fio.responder_ao_que_se_pediu(f, msg, lead_dados)
        if r_fio:
            ferramentas_fio = []
            if r_fio.get("novos"):
                res = FB.executar("registar_lead", {"tipo": r_fio["tipo"], "dados": r_fio["novos"]}, dict(ctx, msg_actual=msg))
                ferramentas_fio.append({"nome": "registar_lead", "args": {"tipo": r_fio["tipo"], "dados": r_fio["novos"]}, "ok": res.get("ok"), "origem": "fio"})
                if f.get("lead_id") and (r_fio.get("lista_espera") or r_fio.get("fechou")):
                    try:
                        supa.update("whatsapp_leads", {"estado": "completo" if r_fio.get("fechou") else "lista_espera"}, id="eq." + str(f["lead_id"]))
                    except Exception:
                        pass
                if r_fio.get("fechou"):
                    threading.Thread(target=telegram.enviar, args=("WhatsApp da loja — cartão de %s completo (%s): %s" % (
                        r_fio["tipo"], numero, json.dumps(r_fio.get("todos"), ensure_ascii=False)[:400]), registar), daemon=True).start()
            cumprimentou_hoje = fichas.cumprimentado_hoje(f)
            dec["caminho"] = "fio"
            registar({"evento": "fio", "numero": numero, "novos": r_fio.get("novos"), "falta": r_fio.get("falta"), "adiou": r_fio.get("adiou")})
            return _fechar(dec, f, ctx, r_fio["texto"], tratamento, prova, lingua_, cumprimentou_hoje, "fio", ferramentas_fio, None, t0, registar, msg=msg)

    motivo_escalar = "dinheiro" if RE_DINHEIRO.search(msg) else ("reclamacao" if RE_RECLAMA.search(msg) else ("falta" if RE_FALTA.search(msg) else ("urgente" if RE_URGENTE.search(msg) else None)))
    if motivo_escalar:
        textos_out = _escalar_texto(motivo_escalar, tratamento, f, lingua_)
        # RESUMO para o Danilo (detetor de urgencia): quem e, ultimo pedido real, e o texto -- ANTES de o bot responder
        resumo = ""
        try:
            ped = FB.executar("pedidos", {}, ctx) if (RE_PEDIDO.search(msg) or motivo_escalar in ("urgente", "falta")) else {}
            ps = (ped or {}).get("pedidos") or []
            if ps:
                resumo = " Último pedido: %s, %s, há %s min%s." % (ps[0].get("loja"), ps[0].get("estado"), ps[0].get("ha_minutos"), " (ATIVO)" if ps[0].get("activo") else "")
                if ps[0].get("activo") and motivo_escalar == "urgente":
                    textos_out.append(_resumo_pedidos(ped))
        except Exception:
            pass
        aviso = "WhatsApp da loja — %s (%s, %s) [%s]: \"%s\".%s Precisa de ti." % (
            numero, f.get("nome") or "sem nome", f.get("papel"), motivo_escalar.upper(), msg[:300], resumo)
        threading.Thread(target=telegram.enviar, args=(aviso, registar), daemon=True).start()   # em thread: nunca atrasa a resposta
        t = tarefas.criar(numero, "danilo: " + motivo_escalar + ": " + msg[:120], 30, "danilo-" + motivo_escalar)
        fichas.anotar_promessa(f, "Danilo responde (" + motivo_escalar + ")", "aberta", t["id"])
        fio.anotar_troca(f, "entrada", msg)
        fio.anotar_troca(f, "saida", " ".join(textos_out))
        fichas.marcar_cumprimento(f)
        f["ultima_resposta_bot_em"] = fichas.agora()
        fichas.guardar(f)
        dec.update(acao="escalar", textos=textos_out, motivo=motivo_escalar, tarefas=[t["id"]], danilo_avisado=True,
                   telegram="async", segundos=round(time.time() - t0, 1))
        return dec

    # 3b. FACTOS DA OPERACAO por texto fixo: horario / dias / estafeta livre, quando e so isso que se pergunta.
    cumprimentou_hoje = fichas.cumprimentado_hoje(f)
    facto = None
    if RE_IPHONE.search(msg) and len(msg) < 220:
        facto = IPHONE_FIXO                      # antes de tudo: o iPhone responde-se por texto fixo, sempre
    elif len(msg) < 220 and not RE_OUTRA_INTENCAO.search(msg):
        if RE_HORARIO.search(msg):
            facto = HORARIO_FIXO
        elif RE_DISPONIBILIDADE.search(msg):
            facto = DISPONIBILIDADE_FIXA
    if facto:
        texto = facto if cumprimentou_hoje else ("Olá! " + facto)
        bolhas = _pos_processar(texto, f, tratamento, cumprimentou_hoje)
        fichas.marcar_cumprimento(f)
        f["ultima_resposta_bot_em"] = fichas.agora()
        fichas.guardar(f)
        dec.update(acao="responder", textos=bolhas, modelo="facto-fixo", ferramentas=[], motivo="facto da operacao",
                   segundos=round(time.time() - t0, 1), tratamento=tratamento, prova_tratamento=prova, lingua=lingua_)
        return dec

    if RAPIDO:
        return _rapido(ctx, f, msg, tratamento, prova, lingua_, registo_, cumprimentou_hoje, t0, dec, registar, emitir)

    # 4. (caminho antigo, CEREBRO_RAPIDO=0) o modelo com ferramentas -- numa thread, para o ORCAMENTO DE 20 s cobrir tambem a lentidao
    #    do proprio modelo (qwen 7b em CPU a frio) e nao so a das ferramentas. Aos 20 s sem resposta
    #    sai o interino + tarefa; a resposta final vem a seguir, quando vier.
    mensagens = [{"role": "system", "content": _sistema(f, tratamento, lingua_, registo_, porta)}]
    ferramentas_usadas = []
    # PRE-VERIFICACAO: para pedidos corre-se `pedidos` ja; para parceiro/estafeta le-se a seccao do
    # manual ja. Entra como facto verificado antes da mensagem -- o modelo so poe as palavras.
    pre = []
    if RE_PEDIDO.search(msg):
        pre.append(("pedidos", {}))
    if RE_PARCEIRO.search(msg):
        pre.append(("ler_manual", {"tema": "quer ser parceiro conversa de venda"}))
    if RE_ESTAFETA.search(msg) and not RE_PARCEIRO.search(msg):
        pre.append(("ler_manual", {"tema": "quer ser estafeta sem vagas lista de espera"}))
    pre_resultados = {}
    for nome_f, args_f in pre:
        res = _executar_com_orcamento({"name": nome_f, "args": args_f, "id": "pre_" + nome_f}, ctx, t0, dec, emitir)
        pre_resultados[nome_f] = res
        ferramentas_usadas.append({"nome": nome_f, "args": args_f, "ok": res.get("ok"), "origem": "pre"})
        mensagens.append({"role": "system", "content": "VERIFICADO AGORA com a ferramenta %s (usa estes dados, nao prometas verificar):\n%s" % (nome_f, FB.para_json(res)[:3000])})
    mensagens.append({"role": "user", "content": msg})
    caixa = {"texto_final": None, "modelo": None, "erro": None}

    def _correr_modelo():
        for volta in range(MAX_VOLTAS):
            r = modelos.chat(mensagens, tools=FB.DEFINICOES, max_tokens=380 if volta < MAX_VOLTAS - 1 else 300)
            caixa["modelo"] = r.get("modelo") or caixa["modelo"]
            if r.get("erro") and not r.get("tool_calls") and not r.get("texto"):
                caixa["erro"] = r["erro"]
                return
            if r.get("tool_calls"):
                mensagens.append({"role": "assistant", "content": r.get("texto") or "", "tool_calls": r["tool_calls"],
                                  "thought_signature": r.get("thought_signature")})
                for c in r["tool_calls"]:
                    chave = c["name"] + json.dumps(c.get("args") or {}, sort_keys=True, ensure_ascii=False)
                    if chave in caixa.setdefault("ja_correu", {}):
                        # a mesma ferramenta com os mesmos argumentos nao corre duas vezes (o nemotron repetia
                        # ler_manual e gastava as voltas): devolve-se o resultado anterior e pede-se a resposta
                        res = caixa["ja_correu"][chave]
                        mensagens.append({"role": "tool", "name": c["name"], "tool_call_id": c["id"],
                                          "content": FB.para_json(res)[:1500] + "\n(ja tinhas este resultado; responde agora a pessoa)"})
                        continue
                    res = _executar_com_orcamento(c, ctx, t0, dec, emitir)
                    caixa["ja_correu"][chave] = res
                    ferramentas_usadas.append({"nome": c["name"], "args": c.get("args"), "ok": res.get("ok")})
                    mensagens.append({"role": "tool", "name": c["name"], "tool_call_id": c["id"], "content": FB.para_json(res)})
                if time.time() - t0 > ORCAMENTO_S and volta < MAX_VOLTAS - 1:
                    mensagens.append({"role": "system", "content": "Passaste os 20 segundos: responde AGORA com o que ja verificaste, em 1-2 frases, sem mais ferramentas."})
                continue
            caixa["texto_final"] = r.get("texto")
            return
        # Esgotou as voltas so com ferramentas (aconteceu na prova 8: cinco ferramentas certas e nem
        # uma frase). Uma ultima chamada so para ESCREVER -- nunca a frase de socorro sem tentar.
        mensagens.append({"role": "system", "content": "Chega de ferramentas. Escreve AGORA a resposta a pessoa, em 1-2 frases, com o que ja verificaste."})
        # SEM ferramentas: com elas o nemotron voltava a pedir mais uma e acabava sem texto (02/09 09:55).
        r = modelos.chat(mensagens, tools=None, max_tokens=300)
        if r.get("erro") and not r.get("texto"):
            r = modelos.chat(mensagens, tools=FB.DEFINICOES, max_tokens=300)   # ha motores que exigem as tools no historico
        caixa["modelo"] = r.get("modelo") or caixa["modelo"]
        if r.get("texto"):
            caixa["texto_final"] = r["texto"]
        elif r.get("erro"):
            caixa["erro"] = ((caixa["erro"] or "") + " | " + r["erro"]).strip(" |")

    th = threading.Thread(target=_correr_modelo, daemon=True)
    th.start()
    th.join(ORCAMENTO_S)
    if th.is_alive() and not dec.get("interino"):
        t = tarefas.criar(numero, "resposta lenta: " + msg[:80], 3, "agente-orcamento")
        dec["tarefas"].append(t["id"])
        dec["interino"] = _frase_especifica(msg, None, False)
        dec["interino_em_s"] = round(time.time() - t0, 1)
        fichas.anotar_promessa(f, "ver: " + msg[:60], "aberta", t["id"])
        if emitir:
            emitir(numero, dec["interino"], "interino")
    th.join(170)
    texto_final, modelo_usado, erro = caixa["texto_final"], caixa["modelo"], caixa["erro"]
    if th.is_alive() and not texto_final:
        erro = (erro or "") + " | o modelo nao respondeu em 190 s"

    # SEGURO DOS LEADS: um interessado em ser estafeta ou parceiro fica SEMPRE registado e o Danilo
    # SEMPRE avisado, decida o modelo o que decidir. Registar e avisar e contabilidade, nao opiniao.
    usados = {u["nome"] for u in ferramentas_usadas}
    tipo_lead = "estafeta" if RE_ESTAFETA.search(msg) else ("parceiro" if RE_PARCEIRO.search(msg) else None)
    if tipo_lead and "registar_lead" not in usados:
        res = FB.executar("registar_lead", {"tipo": tipo_lead, "dados": {"mensagem": msg[:160]}}, ctx)
        ferramentas_usadas.append({"nome": "registar_lead", "args": {"tipo": tipo_lead}, "ok": res.get("ok"), "origem": "seguro"})
    if tipo_lead and "avisar_danilo" not in usados and not ctx.get("danilo_avisado"):
        res = FB.executar("avisar_danilo", {"texto": "Novo interessado em ser %s (%s): \"%s\"" % (tipo_lead, f.get("nome") or "sem nome", msg[:160])}, ctx)
        ferramentas_usadas.append({"nome": "avisar_danilo", "args": {"tipo": tipo_lead}, "ok": res.get("ok"), "origem": "seguro"})

    # PEDIDO VERIFICADO MAS O MODELO PROMETEU NA MESMA ("vou verificar"): sai o resumo dos dados reais.
    if texto_final and pre_resultados.get("pedidos", {}).get("ok") and RE_PROMESSA.search(texto_final):
        registar({"evento": "promessa-com-dados-na-mao", "numero": numero, "texto": texto_final[:160], "modelo": modelo_usado})
        texto_final = _resumo_pedidos(pre_resultados["pedidos"])

    # GUARDA DOS FACTOS: numero (horas, euros, %) sem nenhuma ferramenta ter corrido = invencao.
    if texto_final and not ferramentas_usadas and RE_FACTO_INVENTADO.search(texto_final):
        registar({"evento": "facto-inventado-bloqueado", "numero": numero, "texto": texto_final[:200], "modelo": modelo_usado})
        dec["facto_inventado_bloqueado"] = texto_final[:200]
        if RE_HORARIO.search(msg):
            texto_final = HORARIO_FIXO
        elif RE_DISPONIBILIDADE.search(msg):
            texto_final = DISPONIBILIDADE_FIXA
        else:
            t = tarefas.criar(numero, "facto por confirmar: " + msg[:100], 3, "agente-guarda")
            dec["tarefas"].append(t["id"])
            telegram.enviar("WhatsApp da loja — %s perguntou \"%s\" e o modelo inventou um numero; precisa de ti." % (numero, msg[:160]), registar)
            texto_final = "Deixe-me confirmar isso com o Danilo e já lhe digo, em poucos minutos."
            fichas.anotar_promessa(f, "confirmar: " + msg[:60], "aberta", t["id"])

    if not texto_final and tipo_lead == "estafeta":
        # o modelo correu as ferramentas (lead registado, Danilo avisado) e acabou sem frase: a frase e a do manual
        texto_final = ("De momento não há vagas para estafeta — a equipa está completa e as aprovações dependem da procura. "
                       "Fico com o seu contacto na lista de espera e aviso-o assim que abrir vaga. Pode dizer-me o seu nome e "
                       "que veículo tem (mota, carro ou bicicleta)?")
        dec["fallback_intencao"] = "estafeta"
    elif not texto_final and tipo_lead == "parceiro":
        texto_final = ("Boa! Funciona assim: pomos o seu negócio na app do Bora, os clientes da Guarda fazem o pedido e os nossos "
                       "estafetas entregam — só prepara. Entrar é grátis e a comissão é de 10% sobre os pedidos, no acerto semanal. "
                       "A montagem da loja fica connosco: manda-me o Instagram ou Facebook da casa, ou fotos e a lista de produtos "
                       "com preços. Qual é o nome do negócio?")
        dec["fallback_intencao"] = "parceiro"
    if not texto_final:
        # a cadeia caiu ou o modelo nao escreveu: NUNCA silencio
        t = tarefas.criar(numero, "danilo: sem resposta do modelo: " + msg[:100], 30, "danilo-sem-resposta")
        dec["tarefas"].append(t["id"])
        telegram.enviar("WhatsApp da loja — %s: não consegui responder (%s). Mensagem: \"%s\" — responde-lhe por aqui." % (numero, erro or "sem texto", msg[:200]), registar)
        texto_final = SEM_RESPOSTA_TEXTO
        fichas.anotar_promessa(f, "Danilo responde: " + msg[:80], "aberta", t["id"])

    # 5. pos-processamento + PROMESSA = TAREFA
    bolhas = _pos_processar(texto_final, f, tratamento, cumprimentou_hoje)
    if not bolhas:
        bolhas = [identidade.saudacao(tratamento, f, lingua_)] if not cumprimentou_hoje else ["Diga."]
    dec["tarefas"] += list(ctx.get("tarefas_criadas") or [])
    if RE_PROMESSA.search(" ".join(bolhas)) and not dec["tarefas"]:
        t = tarefas.criar(numero, "promessa automatica: " + " ".join(bolhas)[:100], 3, "agente-auto")
        dec["tarefas"].append(t["id"])
        fichas.anotar_promessa(f, " ".join(bolhas)[:100], "aberta", t["id"])
    elif not RE_PROMESSA.search(" ".join(bolhas)):
        n = tarefas.cumprir_todas(numero, "respondeu com resultado")
        if n:
            for p in f.get("prometido") or []:
                if p.get("estado") == "aberta":
                    p["estado"] = "cumprida"
    fichas.marcar_cumprimento(f)
    f["ultima_resposta_bot_em"] = fichas.agora()
    fichas.guardar(f)
    dec.update(acao="responder", textos=bolhas, modelo=modelo_usado, ferramentas=ferramentas_usadas,
               danilo_avisado=bool(ctx.get("danilo_avisado")), erro=erro, segundos=round(time.time() - t0, 1),
               tratamento=tratamento, prova_tratamento=prova, lingua=lingua_)
    return dec


def registar_mensagens(evento, dec, enviada=False, porta="pc-extensao", ids_saida=None):
    """Tudo vai para whatsapp_messages (entrada e saida). Nunca rebenta.
    ids_saida: ids da fila de saida, um por texto -- e por eles que o /enviado marca a entrega real."""
    numero = fichas.so_digitos(evento.get("numero"))
    linhas = []
    ids = evento.get("msg_ids") or []
    ids_saida = ids_saida or []
    for i, t in enumerate(evento.get("textos") or []):
        linhas.append({"msg_id": ids[i] if i < len(ids) else None, "numero": numero, "direcao": "entrada", "porta": porta,
                       "tipo": "texto", "texto": (t or "")[:2000], "ts_whatsapp": evento.get("ts")})
    for tr in dec.get("transcricoes") or []:
        linhas.append({"numero": numero, "direcao": "entrada", "porta": porta, "tipo": "audio", "transcricao": tr.get("texto"),
                       "modelo": tr.get("motor"), "media_url": tr.get("ficheiro")})
    for d in dec.get("descricoes") or []:
        linhas.append({"numero": numero, "direcao": "entrada", "porta": porta, "tipo": "imagem", "texto": d.get("descricao"),
                       "media_url": d.get("ficheiro")})
    for i, t in enumerate(dec.get("textos") or []):
        linhas.append({"msg_id": ids_saida[i] if i < len(ids_saida) and ids_saida[i] else None,
                       "numero": numero, "direcao": "saida", "porta": porta, "tipo": "texto", "texto": t, "modelo": dec.get("modelo"),
                       "ferramentas": dec.get("ferramentas"), "latencia_ms": int((dec.get("segundos") or 0) * 1000),
                       "decisao": (dec.get("acao") or "") + ("" if not dec.get("caminho") else ":" + dec["caminho"]), "enviada": enviada,
                       "enviada_em": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds") if enviada else None})
    for ln in linhas:
        try:
            supa.insert("whatsapp_messages", ln, devolve=False)
        except Exception:
            pass
    return len(linhas)
