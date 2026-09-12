#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""atendimento.py — cerebro do WhatsApp da loja (Bora). Modo rascunho.
Carrega o MANUAL-ATENDIMENTO-BORA.md como contexto OBRIGATORIO, identifica o tipo de
mensagem e decide a acao. NUNCA envia — devolve a acao e o texto para a vigia tratar.

Uso: python atendimento.py --numero <9digitos> --grupo <sim|nao> "<ultima mensagem literal>"
Saida JSON: {"acao": ..., "texto": ..., "aviso_danilo": ...}
  acao: ignorar-grupo | responder-sozinho | rascunho-danilo | estafeta-lista

Regras (do manual): grupos ignorados; gerais respondo sozinho; estafeta -> lista de espera;
pedido/dinheiro/reembolso/desconto/reclamacao/estafeta-ou-parceiro-em-falta -> rascunho p/ Danilo.
"""
import argparse, json, re, sys, os
sys.path.insert(0, r"C:\BoraLocal\Desktop-PC-antigo\ferramentas\ollama-pontos")
from motor_local import perguntar, vivo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recolha  # recolha conversacional com estado por contacto (fichas no vault)

MANUAL = r"C:\BoraLocal\Bora\MANUAL-ATENDIMENTO-BORA.md"
LISTA_ESPERA = r"C:\BoraLocal\Bora\ESTAFETAS-LISTA-ESPERA.md"

def carrega_manual():
    try:
        return open(MANUAL, encoding="utf-8").read()
    except OSError:
        return ""

def guarda_estafeta(numero, msg):
    """Acrescenta o interessado a lista de espera (idempotente por numero)."""
    import datetime
    try:
        conteudo = open(LISTA_ESPERA, encoding="utf-8").read()
    except OSError:
        conteudo = ""
    if numero and numero in conteudo:
        return
    hoje = datetime.date.today().isoformat()
    linha = f"| {hoje} | {numero} |  | \"{msg[:60]}\" |\n"
    try:
        with open(LISTA_ESPERA, "a", encoding="utf-8") as f:
            f.write(linha)
    except OSError:
        pass

def regista_correcao(o_que):
    """O Danilo corrigiu uma resposta -> entra no manual (secao 12)."""
    import datetime
    hoje = datetime.date.today().isoformat()
    linha = f"- {hoje}: {o_que}\n"
    try:
        t = open(MANUAL, encoding="utf-8").read()
        t = t.replace("- _(ainda sem correções)_\n", "").rstrip() + "\n" + linha
        open(MANUAL, "w", encoding="utf-8").write(t)
        return True
    except OSError:
        return False

# --- ABREVIACOES / escrita de telemovel -> significado real (para reconhecer e perceber) ---
# Os clientes escrevem curto. Expandimos ANTES de classificar e antes de mandar ao modelo.
# Lista larga; cresce com o tempo (ver secao 14 do manual). NAO se incluem aqui os "acks"
# puros (blz, vlw, obg, flw, tmj) — esses vao direto ao RE_ACK.
ABREV = {
    "vc": "você", "vcs": "vocês", "voce": "você", "voces": "vocês",
    "tb": "também", "tbm": "também", "tmb": "também", "tambem": "também",
    "pq": "porque", "pqp": "porque", "oq": "o que", "oqe": "o que", "q": "que", "qq": "qualquer",
    "msg": "mensagem", "sla": "sei lá", "kd": "cadê", "cd": "cadê", "cade": "cadê",
    "qnd": "quando", "qdo": "quando", "qando": "quando",
    "pra": "para", "pro": "para o", "vdd": "verdade", "mt": "muito", "mto": "muito", "mtt": "muito",
    "dnv": "de novo", "hj": "hoje", "amanha": "amanhã", "agr": "agora", "agora": "agora",
    "pfv": "por favor", "pf": "por favor", "fvr": "favor", "fzr": "fazer", "fz": "faz",
    "n": "não", "ñ": "não", "naum": "não", "nao": "não", "nn": "não",
    "td": "tudo", "tds": "todos", "dps": "depois", "msm": "mesmo", "mesm": "mesmo",
    "qto": "quanto", "qnto": "quanto", "knto": "quanto", "qts": "quantos", "qtos": "quantos",
    "cmg": "comigo", "ctg": "contigo", "add": "adicionar", "aki": "aqui", "aq": "aqui",
    "mds": "meu deus", "vlws": "valeu", "brigado": "obrigado", "brigada": "obrigada",
    "pdd": "pedido", "entrga": "entrega", "restaurnte": "restaurante", "cmida": "comida",
    "gnt": "gente", "blza": "beleza", "flw": "falou", "tmj": "tamo junto", "eh": "é", "naum": "não",
    "blz": "beleza", "vlw": "valeu", "obg": "obrigado", "obgd": "obrigado", "obgg": "obrigado",
}
def expande_abreviacoes(msg):
    def rep(m):
        w = m.group(0); return ABREV.get(w.lower(), w)
    return re.sub(r"[A-Za-zÀ-ÿ]+", rep, msg or "")

def reduz_senhor(t):
    """Uma vez por resposta chega. Mantem o 1o 'o senhor', remove os seguintes e limpa a
    pontuacao/preposicao a volta (senao soa a robo)."""
    parts = re.split(r'(\bo senhor\b)', t or "", flags=re.I)
    out, seen = [], 0
    for p in parts:
        if re.fullmatch(r'o senhor', p, flags=re.I):
            seen += 1
            out.append(p if seen == 1 else '\x00')
        else:
            out.append(p)
    t2 = ''.join(out)
    t2 = re.sub(r'\s*,?\s*\x00\s*,?\s*', ' ', t2)   # tira a marca e virgulas coladas
    t2 = re.sub(r'\s+([.!?,;:])', r'\1', t2)         # cola a pontuacao
    t2 = re.sub(r'\s{2,}', ' ', t2).strip()
    return t2

# --- classificadores por palavras (a rede de seguranca; o modelo afina depois) ---
RE_ESTAFETA = re.compile(r'\bestafeta|\bentregador|\bmotoboy|\brider|quero traballhar|quero trabalhar|vaga|ser motorista|fazer entregas|trabalhar convosco|trabalhar com voces', re.I)
RE_PEDIDO   = re.compile(r'\bpedido|\bencomenda\b|onde está|onde esta|cadê|cade\b|demora|atras|atraso|chega quando|quanto tempo|a caminho|entrega.*hoje|meu pedido|nao chegou|não chegou', re.I)
RE_DINHEIRO = re.compile(r'preç|preco|quanto|valor|custa|custo|euro|€|pagar|pagament|mbway|mb ?way|reembols|troco|desconto|fatura|orç|cobran|estorno', re.I)
RE_RECLAMA  = re.compile(r'reclam|péssimo|pessimo|horr[ií]vel|nojo|frio|errad|faltou|nunca mais|processar|denunc|inaceit|revoltad|indignad', re.I)
RE_FALTA    = re.compile(r'estafeta.*(nao|não|sem|falta|desapareceu|sumiu)|parceiro.*(nao|não|fechad|sem)|ninguém veio|ninguem veio|nao apareceu|não apareceu', re.I)
# Saudacao PURA (so um cumprimento, sem pergunta): respondo com uma frase fixa e limpa,
# sem passar pelo modelo local — evita a variancia e o "colar" de frases de exemplo do manual.
RE_SAUDACAO = re.compile(r'^\W*(oi+|ol[aá]+|opa|hey|hi|ola|e a[ií]|bo[am]\s*(dia|tarde|noite)|boas|ola\s+bora|oi\s+bora)\W*$', re.I)
# Interessado em ser PARCEIRO (por o restaurante/loja no Bora) -> resposta fixa e CORRETA (manual §0/§4),
# porque o modelo 7b troca factos (ja mandou "email para <numero>"). Facto e' fonte de verdade, nao improviso.
RE_PARCEIRO = re.compile(r'\bparceir|parceria|(colocar|por|pôr|meter|cadastrar|registar|anunciar|divulgar|meu|minha).{0,20}(restaurante|loja|negóci|negoci|mercado|estabelecimento)|(restaurante|loja|negóci|negoci).{0,20}(no bora|na app|convosco|com voces|com vocês)|quero (ser|entrar como) parceir', re.I)
# Reconhecimentos triviais (nao vale a pena responder nem rascunhar) -> silencio educado.
RE_ACK = re.compile(r'^(?:\W*(?:ok+|okay|okey|blz|blza|beleza|certo|combinado|👍|👌|🙏|obrigad[oa]?|obg|obgd|valeu|vlw|flw|falou|tmj|tamo junto|tá|ta|tá bom|ta bom|d ?boa|dboa|suave|tranquilo|de boa|entendi|perfeito|[óo]timo|top|show))+\W*$', re.I)
# COMO PEDIR (cliente quer saber como faz um pedido) -> explico o passo-a-passo na app (nao e' pedido em curso).
RE_COMO_PEDIR = re.compile(r'como\s+(faço|faco|fazer|se faz|peço|peco|pedir|posso pedir|faço um pedido|faco um pedido|funciona.*pedir|é que peço|e que peco|dá para pedir|da para pedir)|como comprar|como uso a app|como usar a app', re.I)
# VERTICAIS (cliente quer o servico) -> resposta fixa CORRETA (o modelo troca factos, ex.: interior/exterior).
RE_RESERVA  = re.compile(r'reserv\w*.{0,15}mesa|mesa.{0,15}reserv|marcar (uma )?mesa|reservar.{0,10}restaurante', re.I)
RE_LAVAGEM  = re.compile(r'lav\w*.{0,12}(carro|auto|viatura|carr)|lavagem auto|lava.?jato', re.I)
RE_LIMPEZA  = re.compile(r'limpeza|limpar.{0,12}(casa|apartament|escrit[óo]rio)|faxina|empregada de limpeza|fazem limpeza', re.I)
RE_TVDE     = re.compile(r'\btvde\b|boleia|boleias|\buber\b|t[áa]xi|transporte de passageiro', re.I)
RE_FAVORES  = re.compile(r'\bfavores\b|fazer um favor|preciso de um favor|(enviar|mandar|levar|entregar).{0,12}(uma )?encomenda|enviar.{0,6}(um )?pacote', re.I)
# CORRECAO do cliente (ele contradiz/corrige) -> NUNCA deixar a conversa morta; re-engajar com calor.
RE_CORRECAO = re.compile(r'não sou|nao sou|eu não sou|eu nao sou|não é isso|nao e isso|não era isso|nao era isso|não é bem|enganou|se enganou|pessoa errada|número errado|numero errado|não fui eu|nao fui eu|é engano|e engano|me confundiu|confundiu', re.I)
# Feedback POSITIVO isolado ("gostei", "adorei") -> resposta fixa, calorosa (nao vale a pena o modelo).
RE_POSITIVO = re.compile(r'^\W*(gostei( muito)?|adorei|amei|excelente|maravilh\w*|que bom|que [óo]timo|show de bola)\W*$', re.I)
# HORARIO: o manual NAO tem horario -> o modelo inventa (ja inventou "21:00"). Resposta honesta fixa.
RE_HORARIO = re.compile(r'que horas|a que hora|horári|horari|\bhoras?\b.*(abre|fecha|funciona|aberto)|(abre|fecha|funciona|aberto|abrem|fecham).*horas?|quando (abre|fecha|abrem|fecham)|(abre|fecha|abrem|fecham) quando|que dias?.*(abre|aberto|funciona)|estão abertos|estao abertos|até que horas|ate que horas|a partir de que horas', re.I)
# DISPONIBILIDADE que o manual NAO garante (dias/feriados/horas especificas) -> o modelo inventa
# ("sim, entregamos ao domingo, operacao diaria"). Nao chutar: confirmar e avisar o Danilo.
RE_DISPONIBILIDADE = re.compile(r'(entregam|entrega|trabalham|trabalha|funciona|funcionam|abrem|abre|estão|estao|fazem|há|ha|tem|dá|da)\b.{0,30}\b(domingo|sábado|sabado|feriado|natal|ano novo|páscoa|pascoa|de noite|à noite|a noite|de madrugada|madrugada|24 ?horas|agora|neste momento|hoje à noite|hoje a noite)|\b(ao|no|neste|este|aos|nos)\s+(domingo|sábado|sabado|feriado)s?\b', re.I)

SAUDACAO_FIXA = "Olá, tudo bem? Aqui é o Bora, o senhor precisa de alguma coisa?"
POSITIVO_FIXA = "Fico contente que tenha gostado, o senhor! Se precisar de mais alguma coisa, é só dizer."
CORRECAO_FIXA = "Peço desculpa pela confusão, o senhor! Diga-me então, em que posso ajudar?"
COMO_PEDIR_FIXA = ("Pedir é fácil, o senhor: abra a app do Bora, escolha a loja ou o serviço, monte o "
                   "carrinho, confirme a morada e pague — depois acompanha o estado do pedido ali mesmo. "
                   "Quer que eu explique algum passo?")
RESERVA_FIXA = ("Para reservar mesa é nos restaurantes parceiros, o senhor, pela app, na página do "
                "restaurante. Há um sinal de 3€ que depois é descontado na conta final. Quer que eu veja algum?")
LAVAGEM_FIXA = ("Sim, o senhor — temos lavagem auto pela app. De momento fazemos a parte exterior (o "
                "interior está de fora por agora). Pede-se na app, como os outros serviços.")
LIMPEZA_FIXA = ("Fazemos limpeza da casa, o senhor, pela app: escolhe o serviço, agenda, e o preço "
                "confirma-se ali mesmo. Quer que eu explique como se pede?")
TVDE_FIXA = ("Sim, o senhor — o Bora também tem boleias (TVDE). Pede-se pela app, como um transporte normal.")
FAVORES_FIXA = ("Fazemos, o senhor — favores e entrega de encomendas: o estafeta vai buscar e entregar o "
                "que precisar, aqui na Guarda. Pede-se na app, em Favores ou Enviar Encomenda, dizendo o "
                "que é e as moradas.")
# Factos dados pelo Danilo (2026-08-31): horario/dias/disponibilidade -> respondo na hora, no tom.
HORARIO_FIXA = reduz_senhor("O Bora não tem horário próprio, o senhor — cada loja e restaurante tem o seu, "
                "e o senhor vê-o na página da loja aqui na app. Assim sabe logo quem está aberto agora.")
DISPONIBILIDADE_FIXA = ("Funcionamos todos os dias, o senhor, até aos domingos e feriados. A entrega naquele "
                        "momento é só se houver um estafeta livre — havendo, vai logo; se não houver, aí não "
                        "dá àquela hora.")
# Conversa de VENDA, no tom do Danilo. O cliente JA esta a falar connosco -> resolve-se aqui.
# NUNCA mandar contactar outro numero/email/site nem preencher formulario. Comissao real: 10%
# sobre os pedidos, no acerto semanal (business_rules.md 2.4/2.4.1). Ofereco montar a loja por ele.
PARCEIRO_FIXA = reduz_senhor("Boa, o senhor vai gostar — é simples e rende. Funciona assim: pomos o seu "
                 "restaurante ou loja dentro da app do Bora, os clientes aqui da Guarda fazem o pedido e os "
                 "nossos estafetas entregam; o senhor só prepara. A nossa comissão é de 10% sobre os pedidos, "
                 "no acerto semanal. E a montagem da loja fica comigo: o senhor manda-me as fotos e a "
                 "lista dos produtos com os preços, ou então o Instagram ou Facebook da casa, que eu vou "
                 "buscar as imagens e monto-lhe a loja toda para ver e aprovar. Quer começar "
                 "por onde — manda-me as fotos e os produtos, ou o link das redes?")

def classifica(msg):
    s = (msg or "").strip()
    if RE_POSITIVO.match(s): return "positivo"
    if RE_ACK.match(s):      return "ack"
    if RE_SAUDACAO.match(s): return "saudacao"
    if RE_FALTA.search(msg):    return "falta"
    if RE_RECLAMA.search(msg):  return "reclamacao"
    if RE_DINHEIRO.search(msg): return "dinheiro"       # preço/dinheiro -> Danilo (antes das verticais)
    if RE_ESTAFETA.search(msg): return "estafeta"       # quer ENTRAR como estafeta/motorista
    if RE_PARCEIRO.search(msg): return "parceiro"       # quer ENTRAR como parceiro
    # verticais (cliente quer o SERVICO) -> resposta fixa correta
    if RE_RESERVA.search(msg):  return "reserva"
    if RE_LAVAGEM.search(msg):  return "lavagem"
    if RE_LIMPEZA.search(msg):  return "limpeza"
    if RE_TVDE.search(msg):     return "tvde"
    if RE_FAVORES.search(msg):  return "favores"
    if RE_COMO_PEDIR.search(msg): return "como_pedir"
    if RE_PEDIDO.search(msg):   return "pedido"
    if RE_HORARIO.search(msg):  return "horario"
    if RE_DISPONIBILIDADE.search(msg): return "disponibilidade"
    if RE_CORRECAO.search(msg): return "correcao"   # ultimo antes do geral: correcao nunca fica sem resposta
    return "geral"

def tom_base(manual):
    # Tira do contexto TODAS as frases de EXEMPLO de tom (entre parenteses com aspas) — o modelo
    # 7b copia-as tal e qual (ja saiu "passa a usar" e "Agora percebi tudo, Junior").
    m = re.sub(r'\([^)]*["“”][^)]*\)', '', manual)
    m = m.replace('passa a usar', '')
    return ("Es o atendimento do Bora (Guarda, Portugal) no WhatsApp. O manual abaixo e' a tua "
            "FONTE DE FACTOS (o que o Bora e', verticais, como ser parceiro, etc.) — usa-o para saber o "
            "que dizer, mas NAO copies as frases de exemplo do manual; escreve com as TUAS palavras. "
            "Estilo: 1-2 frases, tratamento por 'o senhor', caloroso e humano, sem enrolar, portugues de "
            "Portugal, sem emojis a mais. Responde APENAS a pergunta que o cliente fez. Se nao souberes um "
            "facto, diz que confirmas e respondes. Nunca fales de precos/pagamentos de um pedido concreto.\n"
            "NUNCA INVENTES factos que nao estejam no manual — horarios, prazos, moradas, numeros, datas, "
            "disponibilidade. Se te perguntarem algo que o manual nao diz, responde so: 'Deixe-me confirmar "
            "isso e ja lhe digo, o senhor.' — nunca chutes um valor.\n"
            "PROIBIDO escrever a expressao 'passa a usar' — nao faz sentido como resposta.\n"
            "REGRA DE OURO: o cliente JA esta a falar contigo — e' aqui que se resolve. NUNCA o mandes "
            "contactar outro numero/email/site, nem preencher formularios sozinho, nem 'aguardar contacto'. "
            "Se precisares de algo, PEDE-LHE aqui e trata tu. Empurrar o cliente para fora da conversa e' erro.\n\n"
            "=== MANUAL (factos, nao copiar frases) ===\n" + m[:2200])

def limpa_resposta(r):
    """Rede de seguranca: tira frases com a expressao colada do manual e normaliza espacos."""
    r = (r or "").strip()
    frases = re.split(r'(?<=[.!?])\s+', r)
    frases = [f for f in frases if 'passa a usar' not in f.lower()]
    r = " ".join(frases)
    r = re.sub(r'\s+', ' ', r).strip()
    r = re.sub(r'^[\s.,;:!?]+', '', r)   # tira pontuacao solta no inicio (se caiu a 1a frase)
    r = reduz_senhor(r)                  # "o senhor" uma vez por resposta (senao soa a robo)
    return r or "Com certeza. Em que mais posso ajudar?"

def responde(numero, msg, grupo):
    if grupo:
        return {"acao": "ignorar-grupo", "texto": "", "aviso_danilo": ""}
    manual = carrega_manual()
    msg_exp = expande_abreviacoes(msg)   # entende abreviacoes/escrita de telemovel (blz, vc, kd, ...)

    # Se o contacto esta a preencher uma FICHA (recolha que EU abri):
    if recolha.em_fluxo(numero):
        if recolha.parece_pergunta(msg_exp):
            # fez uma PERGUNTA em vez de responder -> respondo normalmente e RETOMO a ficha
            # (nunca guardo a pergunta como se fosse resposta da ficha, e nunca fico mudo)
            dec = _responde_categoria(numero, msg_exp, manual, permitir_entrar_fluxo=False)
            reask = recolha.reask_texto(numero)
            acao = dec.get("acao")
            if acao == "responder-sozinho":
                corpo = dec.get("texto") or ""
            elif acao == "ignorar-ack":
                corpo = ""                                   # era so' um "ok" -> so' retomo
            else:
                corpo = "Deixe-me ver isso e já lhe digo."   # dinheiro/pedido/reclamacao: nao auto-respondo, mas nao fico mudo
            texto = (corpo + ("\n\n" if corpo and reask else "") + (reask or "")).strip()
            return {"acao": "responder-sozinho", "texto": texto or reask,
                    "aviso_danilo": dec.get("aviso_danilo", "")}
        # e' uma resposta a ficha -> guarda e avanca (continuacao NUNCA leva "vou confirmar")
        dofluxo = recolha.trata(numero, msg_exp)
        if dofluxo is not None:
            return dofluxo

    return _responde_categoria(numero, msg_exp, manual, permitir_entrar_fluxo=True)

def _responde_categoria(numero, msg_exp, manual, permitir_entrar_fluxo=True):
    cat = classifica(msg_exp)

    if cat == "ack":
        # "ok/obrigado/blz/vlw/👍" -> nao ha nada a responder; nao incomodar o cliente nem o Danilo
        return {"acao": "ignorar-ack", "texto": "", "aviso_danilo": ""}

    if cat == "correcao":
        # o cliente corrigiu/contradisse -> NUNCA deixar a conversa morta; re-engajar com calor
        return {"acao": "responder-sozinho", "texto": CORRECAO_FIXA, "aviso_danilo": ""}

    if cat == "saudacao":
        # cumprimento puro -> resposta fixa, limpa, no tom, sem modelo (sozinho, sem aprovacao)
        return {"acao": "responder-sozinho", "texto": SAUDACAO_FIXA, "aviso_danilo": ""}

    if cat == "positivo":
        # feedback positivo isolado -> resposta fixa e calorosa
        return {"acao": "responder-sozinho", "texto": POSITIVO_FIXA, "aviso_danilo": ""}

    if cat == "como_pedir":
        # como fazer um pedido -> passo-a-passo na app (nao e' pedido em curso)
        return {"acao": "responder-sozinho", "texto": COMO_PEDIR_FIXA, "aviso_danilo": ""}

    _VERTICAIS = {"reserva": RESERVA_FIXA, "lavagem": LAVAGEM_FIXA, "limpeza": LIMPEZA_FIXA,
                  "tvde": TVDE_FIXA, "favores": FAVORES_FIXA}
    if cat in _VERTICAIS:
        # cliente quer o servico -> resposta fixa CORRETA (nao deixar o modelo trocar factos)
        return {"acao": "responder-sozinho", "texto": _VERTICAIS[cat], "aviso_danilo": ""}

    if cat == "horario":
        # facto do Danilo: cada loja tem o seu horario, na app -> respondo na hora
        return {"acao": "responder-sozinho", "texto": HORARIO_FIXA, "aviso_danilo": ""}

    if cat == "disponibilidade":
        # facto do Danilo: todos os dias (incl. domingos/feriados); entrega depende de estafeta livre
        return {"acao": "responder-sozinho", "texto": DISPONIBILIDADE_FIXA, "aviso_danilo": ""}

    if cat == "parceiro":
        # interesse em ser parceiro -> pitch + ENTRO no fluxo de recolha (a proxima msg ja e' recolha)
        if permitir_entrar_fluxo:
            recolha.entra_fluxo(numero, "parceiro")
        return {"acao": "responder-sozinho", "texto": PARCEIRO_FIXA,
                "aviso_danilo": (f"Novo interessado em ser PARCEIRO: {numero}. Abri a venda e a recolha da "
                                 f"ficha (fichas\\{numero}.md). Aviso-te quando estiver completa para montar.")}

    if cat == "estafeta":
        texto = ("Olá! Obrigado pelo interesse em ser estafeta do Bora. Neste momento a equipa está "
                 "completa e as aprovações dependem da procura, por isso não temos vagas abertas. Fica "
                 "em lista de espera e assim que abrir vaga entramos em contacto. Pode deixar-me o seu nome?")
        guarda_estafeta(numero, msg_exp)
        return {"acao": "estafeta-lista", "texto": texto,
                "aviso_danilo": f"Novo interessado em ser estafeta: {numero}. Guardado na lista de espera."}

    if cat in ("dinheiro", "reembolso", "reclamacao", "falta", "pedido"):
        # tudo isto NAO se responde sozinho -> rascunho para o Danilo
        motivo = {"dinheiro": "toca dinheiro/preço", "reclamacao": "é uma reclamação",
                  "falta": "envolve estafeta/parceiro em falta", "pedido": "é sobre um pedido específico"}[cat if cat!="reembolso" else "dinheiro"]
        if cat == "pedido":
            sugestao = "Vou já ver o seu pedido, um momento."
            return {"acao": "rascunho-danilo", "texto": sugestao,
                    "aviso_danilo": f"Pedido específico de {numero}: \"{msg_exp[:120]}\". Ver estado no Supabase (orders, client_phone {numero}) e confirmar a previsão antes de enviar."}
        return {"acao": "rascunho-danilo", "texto": "(preparar resposta — NÃO enviar sozinho)",
                "aviso_danilo": f"Mensagem de {numero} que {motivo}: \"{msg_exp[:140]}\". Prepara/aprova a resposta."}

    # geral -> respondo sozinho
    if not vivo():
        return {"acao": "rascunho-danilo", "texto": "(motor local em baixo — resposta manual)",
                "aviso_danilo": f"Ollama em baixo; mensagem geral de {numero} por responder."}
    # usa a versao com abreviacoes expandidas para o modelo perceber escrita de telemovel
    prompt = tom_base(manual) + f"\n\nMensagem do cliente (número {numero}): \"{msg_exp}\"\n\nResposta (curta, 'o senhor'):"
    r = perguntar(prompt, tokens=90, temp=0.2, keep_alive="30m")  # mantem o qwen quente; menos tokens = mais rapido
    return {"acao": "responder-sozinho", "texto": limpa_resposta(r), "aviso_danilo": ""}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mensagem", nargs="?", default="")
    ap.add_argument("--numero", default="")
    ap.add_argument("--grupo", default="nao")
    ap.add_argument("--correcao", default="", help="registar uma correção do Danilo no manual")
    a = ap.parse_args()
    if a.correcao:
        ok = regista_correcao(a.correcao)
        print(json.dumps({"acao": "correcao-registada", "ok": ok}, ensure_ascii=False)); return
    grupo = a.grupo.lower() in ("sim", "true", "1", "yes")
    print(json.dumps(responde(a.numero, a.mensagem, grupo), ensure_ascii=False))

if __name__ == "__main__":
    main()
