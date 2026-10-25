#!/usr/bin/env python3
"""HOST: trata as ordens do Danilo sobre rascunhos do caça-clientes (comando `caca` do Hermes).
Pedidos em /opt/data/caca-fila/*.json: {"acao": "manda"|"muda"|"lista", "id": "<rascunho>", "texto": "..."}.
"manda" envia o rascunho tal como está; "muda" troca o texto e envia. Nada sai sem um destes pedidos.
Missão livro-comum-2026-10-23 (Bloco 5e). Corrido por caca-fila.path/caca-fila.service."""
import glob, io, json, os, sys, time

sys.path.insert(0, '/opt/data/rotinas')
FILA = '/opt/data/caca-fila'
RASC = '/opt/data/rotinas/caca_rascunhos'
UID = 10000


def responder(p, txt):
    r = p[:-5] + '.resposta'
    io.open(r, 'w', encoding='utf-8').write(txt + '\n')
    os.chown(r, UID, UID)
    os.makedirs(os.path.join(FILA, 'feitos'), exist_ok=True)
    os.replace(p, os.path.join(FILA, 'feitos', os.path.basename(p)))
    print(os.path.basename(p), '->', txt[:150])


def main():
    pedidos = sorted(glob.glob(os.path.join(FILA, '*.json')))
    if not pedidos:
        return
    import carteiro_caca as c
    for p in pedidos:
        try:
            d = json.load(io.open(p, encoding='utf-8'))
            if d.get('acao') == 'lista':
                pend = []
                for f in sorted(glob.glob(os.path.join(RASC, '*.json'))):
                    r = json.load(io.open(f, encoding='utf-8'))
                    if r.get('estado') == 'espera_danilo':
                        pend.append('%s — %s: %s' % (r['id'], r['nome'], (r.get('rascunho') or '')[:120]))
                responder(p, 'RASCUNHOS À ESPERA DO DANILO: %d\n%s' % (len(pend), '\n'.join(pend)))
                continue
            f = os.path.join(RASC, '%s.json' % d.get('id', ''))
            if not os.path.exists(f):
                responder(p, 'RECUSADO: não há rascunho %s (usa: caca lista)' % d.get('id'))
                continue
            r = json.load(io.open(f, encoding='utf-8'))
            if r.get('estado') != 'espera_danilo':
                responder(p, 'RECUSADO: o rascunho %s já está %s' % (r['id'], r.get('estado')))
                continue
            texto = (d.get('texto') or '').strip() if d.get('acao') == 'muda' else (r.get('rascunho') or '').strip()
            if len(texto) < 5:
                responder(p, 'RECUSADO: texto vazio; diz o texto com: caca muda %s "texto"' % r['id'])
                continue
            x = c.enviar_email(r['para'], r['assunto'], texto, thread_id=r.get('thread_id'), em_resposta_a=r.get('em_resposta_a'))
            r.update({'estado': 'enviada', 'texto_enviado': texto, 'enviado_em': time.strftime('%Y-%m-%d %H:%M:%S'),
                      'ordem': d.get('acao'), 'gmail_message_id': x.get('message_id')})
            json.dump(r, io.open(f, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
            if r.get('proposta_id'):
                try:
                    c.rpc('carteiro_marcar', {'p_proposta': r['proposta_id'], 'p_evento': 'danilo_mandou', 'p_dados': {}})
                except Exception as ex:
                    c.log('  marcar danilo_mandou falhou: %s' % ex)
            c.log('  rascunho %s enviado por ordem do Danilo (%s) para %s' % (r['id'], d.get('acao'), r['para']))
            responder(p, 'ENVIADO: rascunho %s para %s (%s), mensagem Gmail %s' % (r['id'], r['nome'], r['para'], x.get('message_id')))
        except Exception as ex:
            responder(p, 'ERRO no host: %s' % ex)


if __name__ == '__main__':
    main()
