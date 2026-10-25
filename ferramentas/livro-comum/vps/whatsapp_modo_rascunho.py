#!/usr/bin/env python3
"""Ponto de encaixe do futuro "modo rascunho" do WhatsApp (missão livro-comum-2026-10-23, Bloco 6). DESLIGADO.

Ideia (por decidir com o Danilo — página do livro whatsapp-a-discutir): mensagem nova numa conversa marcada
tipo_conversa='loja' → o Hermes escreve um rascunho → vai ao Telegram do Danilo → ele diz "manda" → sai.
Conversas 'pessoal-danilo' e 'incerto' NUNCA recebem nada automático.

Hoje este script só confirma que está tudo desligado e sai. Não tem relógio nem é chamado por ninguém.
Para o ligar é preciso: decisão do Danilo com data + whatsapp_settings.modo_rascunho_ligado=true +
escrever aqui a parte do rascunho (reaproveitar caca_respostas/caca_fila). envio_ligado fica fora disto."""
import json, sys, urllib.request

sys.path.insert(0, '/opt/data/rotinas')
from comum import E, SUPA_URL  # noqa: E402


def ler(chave):
    k = E.get('SUPABASE_SERVICE_ROLE_KEY') or E.get('SUPABASE_ANON_KEY') or ''
    req = urllib.request.Request(SUPA_URL + '/rest/v1/whatsapp_settings?select=value&key=eq.' + chave,
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.load(r)
    return d[0]['value'] if d else None


def main():
    try:
        rascunho, envio = ler('modo_rascunho_ligado'), ler('envio_ligado')
    except Exception as ex:
        print('DESLIGADO (não consegui ler os interruptores: %s) — não faço nada.' % ex)
        return 0
    if rascunho is not True:
        print('DESLIGADO: modo_rascunho_ligado=%s, envio_ligado=%s — não faço nada.' % (rascunho, envio))
        return 0
    print('modo_rascunho_ligado=true mas a parte do rascunho ainda não está escrita (ver whatsapp-a-discutir). Não faço nada.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
