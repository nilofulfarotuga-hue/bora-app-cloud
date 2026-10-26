#!/usr/bin/env python3
"""Remendo das respostas automáticas do Emerson (geral-sabado-24-10, bloco 6).

As empresas de obras da linha "Propostas diárias" (PT, FR, EN) passam a ter resposta na língua
delas e com os factos certos (assistente de orçamentos), em vez de português e factos de sites.
Preço, prazo e contrato continuam a ir ao Danilo pelo Telegram e só saem com o "manda" dele.
Cópia antes: caca_respostas.py.bak-lingua-2026-10-26.
"""
import io
import shutil

F = "/opt/data/rotinas/caca_respostas.py"
s = io.open(F, encoding="utf-8").read()
if "FACTOS_OBRAS" in s:
    print("ja remendado")
    raise SystemExit(0)
shutil.copy2(F, F + ".bak-lingua-2026-10-26")


def troca(a, b):
    global s
    assert s.count(a) == 1, a[:60]
    s = s.replace(a, b)


troca("""def rascunhar(motor, nome, corpo, classe):
    sistema = ('Escreves em nome da «Bora App — Guarda», em português de Portugal, trata por «vocês», no máximo 70 '
               'palavras, sem assinatura. Usa SÓ estes factos: %s Nunca digas preços, valores, percentagens nem prazos; '
               'nunca prometas nada. Se perguntarem preço ou quiserem avançar, propõe uma chamada curta e pede o melhor '
               'número e hora.' % FACTOS)""",
"""FACTOS_OBRAS = ('A Bora prepara para empresas de obras e remodelação um assistente com IA com o nome da empresa: '
                'responde aos pedidos de orçamento a qualquer hora (site e WhatsApp), na língua do cliente, pede fotos, '
                'medidas e prazo, marca a visita, manda a ficha ao responsável e segue os orçamentos sem resposta. '
                'A demonstração enviada é só um exemplo feito com dados públicos da empresa. Há um piloto com instalação '
                'grátis e 30 dias de teste, sem fidelização. Preços e prazos: só depois de uma conversa curta.')
LINGUAS = {'pt-PT': 'português de Portugal, trata por «vocês»', 'fr': 'francês, trata por «vous»',
           'en': 'inglês', 'pt-BR': 'português do Brasil'}


def rascunhar(motor, nome, corpo, classe, lingua='pt-PT', obras=False):
    sistema = ('Escreves em nome da «Bora App — Guarda», em %s, no máximo 70 '
               'palavras, sem assinatura. Usa SÓ estes factos: %s Nunca digas preços, valores, percentagens nem prazos; '
               'nunca prometas nada. Se perguntarem preço ou quiserem avançar, propõe uma chamada curta e pede o melhor '
               'número e hora.' % (LINGUAS.get(lingua or 'pt-PT', LINGUAS['pt-PT']), FACTOS_OBRAS if obras else FACTOS))""")
troca("""            txt = rascunhar(c.motor, t['nome'], limpar(corpo), classe)""",
      """            txt = rascunhar(c.motor, t['nome'], limpar(corpo), classe, lingua=t.get('lingua') or 'pt-PT',
                            obras=t.get('categoria') == 'obras-remodelacao')""")
troca("""            x = c.enviar_email(t['para'], assunto, txt, thread_id=t.get('thread_id'), em_resposta_a=em_resp)""",
      """            x = c.enviar_email(t['para'], assunto, txt, thread_id=t.get('thread_id'), em_resposta_a=em_resp,
                               rodape=c.rodape_de(t.get('lingua')))""")
io.open(F, "w", encoding="utf-8").write(s)
print("remendado; copia em", F + ".bak-lingua-2026-10-26")
