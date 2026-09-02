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
import re
import threading
import time

from . import ferramentas_bot as FB
from . import fichas, identidade, manual, modelos, supa, tarefas, telegram

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
    "Fundador: Danilo. Pagamento na app: cartao, MB Way, ou dinheiro ate 40 EUR."
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
    t = re.sub(r"[*_#`>]+", "", t)                       # sem markdown
    t = re.sub(r"(?m)^\s*[-•]\s+", "", t)                # sem listas
    t = RE_TITULO_MANUAL.sub("", t)                       # titulos do manual colados na resposta (7b)
    t = re.sub(r"VERIFICADO AGORA[^\n]*", "", t, flags=re.I)
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
            dec["interino"] = "Um segundo que vou ver isso."
            dec["interino_em_s"] = round(time.time() - t0, 1)
            fichas.anotar_promessa(ctx["ficha"], "ver (" + str(c["name"]) + ")", "aberta", t["id"])
            if emitir:
                emitir(ctx["numero"], dec["interino"], "interino")
        th.join(150)
    return caixa.get("res") or {"ok": False, "erro": "a ferramenta nao respondeu a tempo"}


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
    ctx = {"numero": numero, "ficha": f, "registar": registar, "porta": porta}

    if fichas.pausado(f):
        fichas.guardar(f)
        dec.update(acao="silencio-pausado", motivo="bot pausado/assumido pelo Danilo neste contacto")
        return dec
    so_ack = all(RE_ACK.match(t) for t in textos if not t.startswith("[")) and "?" not in msg
    if so_ack and len(msg) <= 40:
        fichas.guardar(f)
        dec.update(acao="ignorar-ack", motivo="so agradecimento/ok")
        return dec

    motivo_escalar = "dinheiro" if RE_DINHEIRO.search(msg) else ("reclamacao" if RE_RECLAMA.search(msg) else ("falta" if RE_FALTA.search(msg) else None))
    if motivo_escalar:
        textos_out = _escalar_texto(motivo_escalar, tratamento, f, lingua_)
        ok, det = telegram.enviar("WhatsApp da loja — %s (%s) [%s]: \"%s\" — precisa de ti." % (
            numero, f.get("nome") or f.get("papel"), motivo_escalar, msg[:300]), registar)
        t = tarefas.criar(numero, "danilo: " + motivo_escalar + ": " + msg[:120], 30, "danilo-" + motivo_escalar)
        fichas.anotar_promessa(f, "Danilo responde (" + motivo_escalar + ")", "aberta", t["id"])
        fichas.marcar_cumprimento(f)
        f["ultima_resposta_bot_em"] = fichas.agora()
        fichas.guardar(f)
        dec.update(acao="escalar", textos=textos_out, motivo=motivo_escalar, tarefas=[t["id"]], danilo_avisado=ok,
                   telegram=det, segundos=round(time.time() - t0, 1))
        return dec

    # 3b. FACTOS DA OPERACAO por texto fixo: horario / dias / estafeta livre, quando e so isso que se pergunta.
    cumprimentou_hoje = fichas.cumprimentado_hoje(f)
    facto = None
    if len(msg) < 220 and not RE_OUTRA_INTENCAO.search(msg):
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

    # 4. o modelo com ferramentas -- numa thread, para o ORCAMENTO DE 20 s cobrir tambem a lentidao
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
        dec["interino"] = "Um segundo que vou ver isso."
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
        t = tarefas.criar(numero, "modelo sem resposta: " + msg[:100], 3, "agente")
        dec["tarefas"].append(t["id"])
        telegram.enviar("WhatsApp da loja — %s: não consegui responder (%s). Mensagem: \"%s\"" % (numero, erro or "sem texto", msg[:200]), registar)
        texto_final = "Recebi a sua mensagem. Estou a ver isso e dou-lhe resposta em 3 minutos, no máximo."
        fichas.anotar_promessa(f, "ver: " + msg[:80], "aberta", t["id"])

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


def registar_mensagens(evento, dec, enviada=False, porta="pc-extensao"):
    """Tudo vai para whatsapp_messages (entrada e saida). Nunca rebenta."""
    numero = fichas.so_digitos(evento.get("numero"))
    linhas = []
    ids = evento.get("msg_ids") or []
    for i, t in enumerate(evento.get("textos") or []):
        linhas.append({"msg_id": ids[i] if i < len(ids) else None, "numero": numero, "direcao": "entrada", "porta": porta,
                       "tipo": "texto", "texto": (t or "")[:2000], "ts_whatsapp": evento.get("ts")})
    for tr in dec.get("transcricoes") or []:
        linhas.append({"numero": numero, "direcao": "entrada", "porta": porta, "tipo": "audio", "transcricao": tr.get("texto"),
                       "modelo": tr.get("motor"), "media_url": tr.get("ficheiro")})
    for d in dec.get("descricoes") or []:
        linhas.append({"numero": numero, "direcao": "entrada", "porta": porta, "tipo": "imagem", "texto": d.get("descricao"),
                       "media_url": d.get("ficheiro")})
    for t in dec.get("textos") or []:
        linhas.append({"numero": numero, "direcao": "saida", "porta": porta, "tipo": "texto", "texto": t, "modelo": dec.get("modelo"),
                       "ferramentas": dec.get("ferramentas"), "latencia_ms": int((dec.get("segundos") or 0) * 1000),
                       "decisao": dec.get("acao"), "enviada": enviada,
                       "enviada_em": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds") if enviada else None})
    for ln in linhas:
        try:
            supa.insert("whatsapp_messages", ln, devolve=False)
        except Exception:
            pass
    return len(linhas)
