#!/usr/bin/env python3
"""hermes-email — a caixa de e-mail dos agentes (emerson@, suporte@, ... @boraguarda.com).

Missão agentes-email-2026-10-21. Corre NO HOST da VPS, porque é só aqui que vive a chave do
servidor (/opt/assistente-negocio/.env). O Emerson, dentro do contentor, não recebe a chave:
pede pelo comando `hermes-email` do contentor, que deixa um pedido em
/opt/data/agentes-email/fila/ ; uma unidade systemd (.path) acorda este script, que responde em
/opt/data/agentes-email/respostas/ .

Modos:
  ponte.py cli <comando> [args...]   — uso directo no host (Claude Code por SSH, cron)
  ponte.py fila                      — processa os pedidos do contentor (chamado pelo systemd)

Comandos:
  caixa <agente> [todos] [N]         — e-mails recebidos (por omissão só os novos), mais recentes primeiro
  ler <id>                           — mostra um e-mail e marca-o como lido
  responder <id> <texto>             — responde ao remetente (Re:, mesma conversa)
  enviar <agente> <para> <assunto> <texto>
  enviados <agente> [N]              — o que o agente enviou
  resumo                             — novos/total por agente
Só usa a biblioteca padrão do Python.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ENV_SERVIDOR = '/opt/assistente-negocio/.env'
BASE_FILA = '/docker/hermes-agent-fvnc/data/agentes-email'
AGENTES = ['emerson', 'suporte', 'parceiros', 'vendas', 'redes', 'radar', 'assinaturas']
RE_UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.I)
UID_HERMES = 10000


class Falha(Exception):
    pass


def ler_env(caminho):
    d = {}
    with open(caminho, encoding='utf-8') as f:
        for linha in f:
            linha = linha.strip()
            if not linha or linha.startswith('#') or '=' not in linha:
                continue
            k, v = linha.split('=', 1)
            d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def credenciais():
    e = ler_env(ENV_SERVIDOR)
    url = e.get('SUPABASE_URL', '').rstrip('/')
    cred = e.get('SUPABASE_SECRET_KEY') or e.get('SUPABASE_SERVICE_ROLE_KEY') or ''
    if not url or not cred:
        raise Falha('sem SUPABASE_URL ou chave do servidor em ' + ENV_SERVIDOR)
    return url, cred


def pedido(metodo, caminho, corpo=None, extra=None):
    url, cred = credenciais()
    cab = {'apikey': cred, 'Content-Type': 'application/json'}
    if cred.startswith('eyJ') or caminho.startswith('/functions/'):
        cab['Authorization'] = 'Bearer ' + cred
    if extra:
        cab.update(extra)
    dados = json.dumps(corpo).encode('utf-8') if corpo is not None else None
    req = urllib.request.Request(url + caminho, data=dados, headers=cab, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read().decode('utf-8')
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode('utf-8', 'replace')
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, {'erro': txt[:300]}


def agente_ok(a):
    a = (a or '').strip().lower()
    if a not in AGENTES:
        raise Falha('agente desconhecido: %r (válidos: %s)' % (a, ', '.join(AGENTES)))
    return a


def id_ok(i):
    i = (i or '').strip()
    if not RE_UUID.match(i):
        raise Falha('id inválido (usa o id completo que a caixa mostra): %r' % i)
    return i


def data_curta(iso):
    return (iso or '')[:16].replace('T', ' ')


def cmd_caixa(args):
    if not args:
        raise Falha('uso: caixa <agente> [todos] [N]')
    a = agente_ok(args[0])
    todos = 'todos' in args[1:]
    n = next((int(x) for x in args[1:] if x.isdigit()), 20)
    q = 'agente=eq.%s&direcao=eq.entrada&order=criado_em.desc&limit=%d&select=id,criado_em,de,assunto,estado,anexos' % (a, min(n, 100))
    if not todos:
        q += '&estado=eq.novo'
    st, linhas = pedido('GET', '/rest/v1/agentes_email?' + q)
    if st != 200:
        raise Falha('leitura falhou (%s): %s' % (st, linhas))
    if not linhas:
        return 'Caixa de %s@: %s.' % (a, 'vazia' if todos else 'nada novo')
    out = ['Caixa de %s@ (%d%s):' % (a, len(linhas), '' if todos else ' novos')]
    for r in linhas:
        nan = len([x for x in (r.get('anexos') or []) if x.get('guardado')])
        out.append('- %s | %s | %s | %s%s | %s' % (
            r['id'], data_curta(r['criado_em']), r.get('de') or '?', r.get('assunto') or '(sem assunto)',
            ' | %d anexo(s)' % nan if nan else '', r.get('estado')))
    return '\n'.join(out)


def cmd_ler(args):
    if not args:
        raise Falha('uso: ler <id>')
    i = id_ok(args[0])
    st, linhas = pedido('GET', '/rest/v1/agentes_email?id=eq.%s&select=*' % i)
    if st != 200 or not linhas:
        raise Falha('não encontrei o e-mail %s (%s)' % (i, st))
    r = linhas[0]
    texto = (r.get('texto') or '').strip() or '(sem texto)'
    if len(texto) > 8000:
        texto = texto[:8000] + '\n[... cortado; o resto está no painel]'
    out = [
        'De: %s' % r.get('de'), 'Para: %s' % r.get('para'), 'Assunto: %s' % (r.get('assunto') or '(sem assunto)'),
        'Data: %s UTC' % data_curta(r.get('criado_em')), 'Caixa: %s (%s) · estado: %s' % (r.get('agente'), r.get('direcao'), r.get('estado')),
    ]
    anexos = r.get('anexos') or []
    if anexos:
        out.append('Anexos: ' + '; '.join('%s (%s bytes%s)' % (x.get('nome'), x.get('bytes'), '' if x.get('guardado') else ', NÃO guardado: %s' % x.get('motivo')) for x in anexos))
    out += ['', texto]
    if r.get('direcao') == 'entrada' and r.get('estado') == 'novo':
        pedido('PATCH', '/rest/v1/agentes_email?id=eq.%s' % i, {'estado': 'lido'}, {'Prefer': 'return=minimal'})
        out.append('\n(marcado como lido)')
    return '\n'.join(out)


def edge_enviar(corpo):
    st, r = pedido('POST', '/functions/v1/agentes-email-enviar', corpo)
    if st == 200 and r and r.get('ok'):
        return 'Enviado de %s para %s (registo %s, resend %s).' % (r.get('de'), ', '.join(r.get('para') or []), r.get('id'), r.get('resend_id'))
    raise Falha('envio recusado (%s): %s' % (st, json.dumps(r, ensure_ascii=False)[:400]))


def cmd_responder(args):
    if len(args) < 2:
        raise Falha('uso: responder <id> "<texto>"')
    return edge_enviar({'responder_a': id_ok(args[0]), 'texto': ' '.join(args[1:])})


def cmd_enviar(args):
    if len(args) < 4:
        raise Falha('uso: enviar <agente> <para> "<assunto>" "<texto>"')
    return edge_enviar({'agente': agente_ok(args[0]), 'para': args[1], 'assunto': args[2], 'texto': ' '.join(args[3:])})


def cmd_enviados(args):
    if not args:
        raise Falha('uso: enviados <agente> [N]')
    a = agente_ok(args[0])
    n = next((int(x) for x in args[1:] if x.isdigit()), 20)
    st, linhas = pedido('GET', '/rest/v1/agentes_email?agente=eq.%s&direcao=eq.saida&order=criado_em.desc&limit=%d&select=id,criado_em,para,assunto,estado,erro' % (a, min(n, 100)))
    if st != 200:
        raise Falha('leitura falhou (%s): %s' % (st, linhas))
    if not linhas:
        return '%s@ ainda não enviou nada.' % a
    return '\n'.join(['Enviados por %s@:' % a] + ['- %s | %s | %s | %s | %s%s' % (
        r['id'], data_curta(r['criado_em']), r.get('para'), r.get('assunto'), r.get('estado'),
        (' | ' + r['erro']) if r.get('erro') else '') for r in linhas])


def cmd_resumo(_args):
    st, linhas = pedido('POST', '/rest/v1/rpc/agentes_email_resumo', {})
    if st != 200:
        raise Falha('resumo falhou (%s): %s' % (st, linhas))
    por = {r['agente']: r for r in (linhas or [])}
    return '\n'.join(['Caixas dos agentes (novos / total):'] + [
        '- %s@boraguarda.com: %s / %s' % (a, (por.get(a) or {}).get('nao_lidos', 0), (por.get(a) or {}).get('total', 0)) for a in AGENTES])


COMANDOS = {'caixa': cmd_caixa, 'ler': cmd_ler, 'responder': cmd_responder, 'enviar': cmd_enviar,
            'enviados': cmd_enviados, 'resumo': cmd_resumo}


def executar(cmd, args):
    f = COMANDOS.get((cmd or '').strip().lower())
    if not f:
        return 2, 'comandos: ' + ', '.join(COMANDOS) + '\n' + __doc__.split('Comandos:')[1].split('Só usa')[0]
    try:
        return 0, f([str(a) for a in args])
    except Falha as e:
        return 1, 'ERRO: %s' % e
    except Exception as e:  # rede, JSON, etc. — nunca morrer calado
        return 1, 'ERRO inesperado: %s' % e


def processar_fila():
    fila = os.path.join(BASE_FILA, 'fila')
    resp = os.path.join(BASE_FILA, 'respostas')
    os.makedirs(resp, exist_ok=True)
    for nome in sorted(os.listdir(fila)):
        p = os.path.join(fila, nome)
        pid = nome[:-5]
        if not nome.endswith('.json') or not re.match(r'^[A-Za-z0-9_-]{6,80}$', pid) or not os.path.isfile(p):
            # lixo na fila: sai, senão a unidade .path (DirectoryNotEmpty) volta a disparar sem fim
            if os.path.isfile(p):
                os.remove(p)
            continue
        pedido_json = {}
        try:
            with open(p, encoding='utf-8') as f:
                pedido_json = json.load(f)
            rc, txt = executar(pedido_json.get('cmd'), pedido_json.get('args') or [])
        except Exception as e:
            rc, txt = 1, 'ERRO: pedido ilegível: %s' % e
        os.remove(p)
        destino = os.path.join(resp, pid + '.txt')
        tmp = destino + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write('%d\n%s\n' % (rc, txt))
        os.chown(tmp, UID_HERMES, UID_HERMES)
        os.replace(tmp, destino)
        with open(os.path.join(BASE_FILA, 'registo.log'), 'a', encoding='utf-8') as f:
            f.write('%s %s %s rc=%d\n' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), pid, pedido_json.get('cmd') if isinstance(pedido_json, dict) else '?', rc))
    # respostas esquecidas há mais de 1 hora
    agora = time.time()
    for nome in os.listdir(resp):
        p = os.path.join(resp, nome)
        if agora - os.path.getmtime(p) > 3600:
            os.remove(p)


if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == 'fila':
        processar_fila()
        sys.exit(0)
    if len(sys.argv) >= 2 and sys.argv[1] == 'cli':
        rc, txt = executar(sys.argv[2] if len(sys.argv) > 2 else '', sys.argv[3:])
        print(txt)
        sys.exit(rc)
    print(__doc__)
    sys.exit(2)
