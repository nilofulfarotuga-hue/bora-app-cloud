"""Chamadas à API do Supabase com a chave pública e o JWT de uma conta de prova.

Uso:
  python sb.py signup                      cria a conta de prova (guarda credenciais em prova_conta.json)
  python sb.py rpc <quem> <funcao> <json>  chama uma RPC como 'prova' ou 'demo'
Nunca imprime tokens.
"""
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
DEFS = json.load(open(r'C:\BoraLocal\projetosflutter\bora_app\.dart_defines', encoding='utf-8'))
URL = DEFS['SUPABASE_URL']
ANON = DEFS['SUPABASE_ANON_KEY']
CONTA = os.path.join(AQUI, 'prova_conta.json')
DEMO = {'email': 'demo@bora.app', 'password': 'BoraDemo2026!'}


def http(metodo, caminho, corpo=None, token=None):
    req = urllib.request.Request(
        URL + caminho, method=metodo,
        data=json.dumps(corpo).encode() if corpo is not None else None,
        headers={'apikey': ANON, 'Content-Type': 'application/json',
                 'Authorization': 'Bearer ' + (token or ANON)})
    try:
        r = urllib.request.urlopen(req, timeout=40)
        txt = r.read().decode()
        return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, txt[:400]


def entrar(cred):
    st, d = http('POST', '/auth/v1/token?grant_type=password',
                 {'email': cred['email'], 'password': cred['password']})
    if st != 200:
        raise SystemExit(f'login falhou HTTP {st}: {d}')
    return d['access_token'], d['user']['id']


def credenciais(quem):
    return DEMO if quem == 'demo' else json.load(open(CONTA, encoding='utf-8'))


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'signup':
        cred = {'email': 'boraappbora+prova-limpeza-0210@gmail.com',
                'password': 'Prova-' + secrets.token_urlsafe(9)}
        st, d = http('POST', '/auth/v1/signup', {
            'email': cred['email'], 'password': cred['password'],
            'data': {'bora_role': 'client', 'bora_name': 'PROVA Limpeza (teste)',
                     'bora_phone': '900000210', 'bora_consent_version': '1.0'}})
        print('HTTP', st)
        if st == 200:
            uid = (d.get('user') or d).get('id')
            cred['user_id'] = uid
            json.dump(cred, open(CONTA, 'w', encoding='utf-8'))
            print('user_id', uid, '| sessão devolvida:', bool(d.get('access_token')))
        else:
            print(d)
    elif cmd == 'rpc':
        quem, funcao, args = sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
        tok, uid = entrar(credenciais(quem))
        st, d = http('POST', '/rest/v1/rpc/' + funcao, args, tok)
        print('como', quem, uid, '| HTTP', st)
        txt = json.dumps(d, ensure_ascii=False)
        print(txt[:1500])
