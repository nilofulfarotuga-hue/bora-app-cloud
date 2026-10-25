#!/usr/bin/env python3
"""Respostas do caça-clientes (missão livro-comum-2026-10-23, Bloco 5d/5e). Usado pelo carteiro_caca.ler().

Classes de resposta:
  automatica — resposta automática, ausência, ou só assinatura (como a do Yahoo de 06/10) → ignora
  recusa     — "não"/"remover" → o carteiro marca e nunca mais (já fazia)
  fechar     — preço, reunião, avançar, contrato → rascunho + NOTA DE VOZ ao Danilo; só sai com "manda"
  pergunta   — pergunta simples sobre o serviço → o Hermes responde SOZINHO com o que está no livro
Preço e contrato nunca saem sem o "manda" do Danilo.
Rascunhos em /opt/data/rotinas/caca_rascunhos/<id>.json; a ordem do Danilo chega pela fila
/opt/data/caca-fila (comando `caca` do Hermes) e é tratada por caca_fila.py no host."""
import json, os, re, time

RASC = '/opt/data/rotinas/caca_rascunhos'
VISTOS = '/opt/data/rotinas/caca_vistos.json'
AUTO = ('resposta automática', 'resposta automatica', 'out of office', 'automatic reply', 'auto-reply', 'autoreply',
        'ausente', 'estou fora', 'em férias', 'em ferias', 'fora do escritório', 'fora do escritorio', 'mensagem automática',
        'não responda', 'nao responda', 'do not reply', 'noreply', 'no-reply')
FECHAR = ('preço', 'preco', 'quanto custa', 'quanto fica', 'quanto cobram', 'quanto é o', 'valores', 'orçamento',
          'orcamento', 'mensalidade', 'reunião', 'reuniao', 'liguem', 'ligar-nos', 'ligue-nos', 'podem ligar',
          'falar por telefone', 'avançar', 'avancar', 'fechar negócio', 'contrato', 'queremos avançar', 'estamos interessados',
          'tenho interesse', 'temos interesse', 'podem passar', 'vamos fazer', 'aceitamos')
ASSINATURA = re.compile(r'^(enviado (do|a partir do) |sent from |obter o outlook|get outlook|yahoo mail|--\s*$)', re.I)
FACTOS = ('A Bora App — Guarda faz sites para negócios (desenho, textos com o negócio, ligação segura, versão para '
          'telemóvel, livro de reclamações e Google), trata da presença online por avença mensal (publicações, ficha do '
          'Google, respostas), e tem um Secretário Virtual que responde no WhatsApp do negócio e marca na agenda. '
          'A maquete enviada é só uma pré-visualização; o site a sério faz-se com o negócio. Preços e prazos: só depois '
          'de uma conversa curta (o responsável liga).')


def _vistos():
    try:
        return set(json.load(open(VISTOS)))
    except Exception:
        return set()


def ja_visto(msg_id):
    return msg_id in _vistos()


def marcar_visto(msg_id):
    v = _vistos(); v.add(msg_id)
    json.dump(sorted(v)[-2000:], open(VISTOS, 'w'))


def limpar(corpo):
    linhas = [l for l in corpo.splitlines() if l.strip() and not ASSINATURA.match(l.strip())]
    return '\n'.join(linhas).strip()


def classificar(assunto, cabecalhos, corpo, recusa_lista):
    baixo = (assunto + ' ' + corpo).lower()
    if (cabecalhos.get('auto-submitted', 'no').lower() not in ('', 'no') or cabecalhos.get('x-autoreply')
            or any(a in baixo for a in AUTO)):
        return 'automatica'
    util = limpar(corpo)
    if len(re.sub(r'\W', '', util)) < 4:
        return 'automatica'  # só assinatura / vazio
    if any(r in util.lower() for r in recusa_lista) or util.strip().lower().rstrip('.!') in ('não', 'nao'):
        return 'recusa'
    if any(f in util.lower() for f in FECHAR):
        return 'fechar'
    return 'pergunta'


def valida_auto(texto):
    erros = []
    if re.search(r'€|\beur\b|\beuros?\b|\d+\s*%|\bgr[aá]tis\b|\bgarant', texto, re.I):
        erros.append('fala de preço/garantia')
    if len(texto.split()) > 90:
        erros.append('mais de 90 palavras')
    if re.search(r'\bvocê\b|\bcelular\b', texto, re.I):
        erros.append('português do Brasil')
    return erros


def rascunhar(motor, nome, corpo, classe):
    sistema = ('Escreves em nome da «Bora App — Guarda», em português de Portugal, trata por «vocês», no máximo 70 '
               'palavras, sem assinatura. Usa SÓ estes factos: %s Nunca digas preços, valores, percentagens nem prazos; '
               'nunca prometas nada. Se perguntarem preço ou quiserem avançar, propõe uma chamada curta e pede o melhor '
               'número e hora.' % FACTOS)
    pedido = 'O negócio %s respondeu ao nosso email (classe: %s):\n%s\n\nEscreve a resposta.' % (nome, classe, corpo[:1500])
    return motor(sistema, pedido, 300).strip()


def guardar_rascunho(r):
    os.makedirs(RASC, exist_ok=True)
    rid = time.strftime('%m%d%H%M%S')
    r.update({'id': rid, 'estado': 'espera_danilo', 'criado_em': time.strftime('%Y-%m-%d %H:%M:%S')})
    json.dump(r, open(os.path.join(RASC, rid + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    return rid


def tratar(c, t, msg, corpo):
    """c = módulo carteiro_caca (para motor, enviar_email, rpc, dizer, log, cabecalho, RECUSA).
    t = {proposta_id, nome, para, thread_id, assunto}; msg = mensagem Gmail. Devolve a classe."""
    mid = msg.get('id') or ''
    if mid and ja_visto(mid):
        return 'visto'
    cab = {k: c.cabecalho(msg, k) for k in ('Auto-Submitted', 'X-Autoreply', 'Subject', 'Message-ID')}
    cab = {k.lower(): v for k, v in cab.items()}
    classe = classificar(cab.get('subject', ''), cab, corpo, c.RECUSA)
    em_resp = cab.get('message-id') or None
    assunto = t['assunto'] if t['assunto'].lower().startswith('re:') else 'Re: ' + t['assunto']
    pid = t.get('proposta_id')
    if classe == 'automatica':
        c.log('  automática/assinatura ignorada: %s' % t['nome'])
    elif classe == 'recusa':
        if pid:
            c.rpc('carteiro_marcar', {'p_proposta': pid, 'p_evento': 'recusou', 'p_dados': {'resposta': corpo[:1500]}})
        c.dizer('O %s respondeu ao email da Bora a dizer que não quer. Fica marcado como recusou e nunca mais é contactado.' % t['nome'],
                resumo='Caça-clientes: %s recusou' % t['nome'])
    else:
        try:
            txt = rascunhar(c.motor, t['nome'], limpar(corpo), classe)
        except Exception as ex:
            txt = ''
            c.log('  motor falhou: %s' % ex)
        erros = valida_auto(txt) if txt else ['motor sem resposta']
        if classe == 'pergunta' and not erros:
            x = c.enviar_email(t['para'], assunto, txt, thread_id=t.get('thread_id'), em_resposta_a=em_resp)
            if pid:
                c.rpc('carteiro_marcar', {'p_proposta': pid, 'p_evento': 'respondeu',
                                          'p_dados': {'resposta': corpo[:1500], 'classe': 'pergunta', 'respondido_sozinho': txt}})
            c.dizer('O %s fez uma pergunta sobre o serviço e eu respondi sozinho, sem preços. Perguntaram: %s. Respondi: %s'
                    % (t['nome'], limpar(corpo)[:300], txt), resumo='Caça-clientes: respondi a %s' % t['nome'])
            c.log('  pergunta respondida sozinho: %s (%s)' % (t['nome'], x.get('message_id')))
            classe = 'pergunta-respondida'
        else:
            rid = guardar_rascunho({'proposta_id': pid, 'nome': t['nome'], 'para': t['para'], 'assunto': assunto,
                                    'thread_id': t.get('thread_id'), 'em_resposta_a': em_resp, 'recebido': limpar(corpo)[:1500],
                                    'rascunho': txt, 'classe': classe, 'avisos': erros})
            if pid:
                c.rpc('carteiro_marcar', {'p_proposta': pid, 'p_evento': 'espera_danilo',
                                          'p_dados': {'resposta': corpo[:1500], 'classe': classe, 'rascunho_id': rid}})
            c.dizer('Danilo, o %s respondeu ao email da Bora: %s. Proponho responder assim: %s. Digo que sim? Responde '
                    'manda, ou muda para o que quiseres. É o rascunho %s.'
                    % (t['nome'], limpar(corpo)[:300], txt or '(o motor não escreveu; diz-me tu o texto)', rid),
                    resumo='Caça-clientes: %s quer avançar (rascunho %s)' % (t['nome'], rid))
            c.log('  à espera do Danilo: %s, rascunho %s' % (t['nome'], rid))
            classe = 'espera-danilo'
    if mid:
        marcar_visto(mid)
    return classe
