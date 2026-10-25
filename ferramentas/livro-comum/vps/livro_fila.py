#!/usr/bin/env python3
"""Host: processa /opt/data/livro-fila/*.json (pedidos do comando aprender do Hermes) e chama
public.livro_aprender com a service key. Escreve <id>.resposta para o Hermes ler.
Corrido pela unidade systemd livro-fila.service (disparada por livro-fila.path).
Missão livro-comum-2026-10-23."""
import glob, io, json, os, urllib.request, urllib.error

FILA = '/opt/data/livro-fila'
FEITOS = os.path.join(FILA, 'feitos')
ENVF = '/opt/whatsapp-bora/.env'
UID = 10000


def env():
    e = {}
    for ln in io.open(ENVF, encoding='utf-8', errors='replace'):
        ln = ln.strip()
        if ln and not ln.startswith('#') and '=' in ln:
            k, v = ln.split('=', 1)
            e[k.strip()] = v.strip().strip('"').strip("'")
    return e


def rpc(e, corpo):
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/rpc/livro_aprender',
                                 data=json.dumps(corpo).encode(), method='POST',
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return 'GRAVADO no livro (erros-aprendidos): ' + json.load(r)
    except urllib.error.HTTPError as ex:
        try:
            msg = json.load(ex).get('message', '')
        except Exception:
            msg = str(ex)
        return 'RECUSADO: ' + msg


def main():
    os.makedirs(FEITOS, exist_ok=True)
    e = None
    for p in sorted(glob.glob(os.path.join(FILA, '*.json'))):
        e = e or env()
        try:
            d = json.load(io.open(p, encoding='utf-8'))
            txt = rpc(e, {'p_quem': d.get('quem', 'hermes'), 'p_errei': d.get('errei', ''), 'p_regra': d.get('regra', '')})
        except Exception as ex:
            txt = 'ERRO no host: %s' % ex
        r = p[:-5] + '.resposta'
        io.open(r, 'w', encoding='utf-8').write(txt + '\n')
        os.chown(r, UID, UID)
        os.replace(p, os.path.join(FEITOS, os.path.basename(p)))
        print(os.path.basename(p), '->', txt[:120])


if __name__ == '__main__':
    main()
