# -*- coding: utf-8 -*-
"""Prova no emulador (01/10/2026) - pede UMA corrida de teste a dinheiro como
o cliente demo, pelo caminho do cliente (RPC tvde_request_ride com o JWT
dele), e vigia-a.

Seguranca (ha motoristas reais ligados): a corrida so pode ser oferecida ao
motorista DEMO. O vigia cancela-a como cliente (RPC tvde_cancel_ride) se:
  - a oferta for para outra pessoa que nao o demo, ou
  - ao fim de LIMITE segundos ainda ninguem a tiver aceite
    (a oferta vive 40 s; cancelar antes impede a roda de passar a um real).

Uso:  BORA_DEMO_PW=... py pedir_corrida_demo.py pedir
      BORA_DEMO_PW=... py pedir_corrida_demo.py cancelar <ride_id>
      BORA_DEMO_PW=... py pedir_corrida_demo.py ver <ride_id>
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), *['..'] * 5))
DEFS = json.load(open(os.path.join(RAIZ, '.dart_defines'), encoding='utf-8'))
URL = DEFS['SUPABASE_URL']
ANON = DEFS['SUPABASE_ANON_KEY']
CLIENTE = 'demo@bora.app'
DEMO_DRIVER = 'dede0000-0000-4000-8000-000000000001'
LIMITE = 28  # segundos; a oferta vive 40

# Recolha e destino em Lisboa: a 250 km dos motoristas reais (Guarda).
ORIGEM = (38.7075, -9.1364, 'Praca do Comercio (TESTE oferta fantasma)')
DESTINO = (38.7139, -9.1394, 'Rossio (TESTE oferta fantasma)')


def chamar(caminho, corpo=None, token=None, metodo='POST'):
    req = urllib.request.Request(
        URL + caminho,
        data=None if corpo is None else json.dumps(corpo).encode(),
        method=metodo,
        headers={
            'apikey': ANON,
            'Authorization': 'Bearer ' + (token or ANON),
            'Content-Type': 'application/json',
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def entrar():
    st, r = chamar('/auth/v1/token?grant_type=password',
                   {'email': CLIENTE, 'password': os.environ['BORA_DEMO_PW']})
    if st != 200:
        sys.exit('login do cliente demo falhou: %s %s' % (st, r))
    return r['access_token']


def ler(token, ride_id):
    st, r = chamar(
        '/rest/v1/tvde_rides?id=eq.%s&select=id,status,driver_id,'
        'current_offer_driver_id,offer_expires_at,payment_method,'
        'est_fare_cents,driver_earn_cents' % ride_id,
        token=token, metodo='GET')
    return r[0] if st == 200 and r else {'erro': st, 'corpo': r}


def cancelar(token, ride_id, motivo):
    st, r = chamar('/rest/v1/rpc/tvde_cancel_ride',
                   {'p_ride_id': ride_id, 'p_actor': 'cliente',
                    'p_reason': motivo}, token=token)
    estado = r.get('status') if isinstance(r, dict) else r
    print('CANCELADA http=%s status=%s motivo=%s' % (st, estado, motivo),
          flush=True)


def main():
    token = entrar()
    accao = sys.argv[1] if len(sys.argv) > 1 else 'pedir'
    if accao == 'ver':
        print(json.dumps(ler(token, sys.argv[2])))
        return
    if accao == 'cancelar':
        cancelar(token, sys.argv[2], 'teste oferta fantasma - cancelar')
        print(json.dumps(ler(token, sys.argv[2])))
        return

    st, r = chamar('/rest/v1/rpc/tvde_request_ride', {
        'p_origin_lat': ORIGEM[0], 'p_origin_lng': ORIGEM[1],
        'p_origin_label': ORIGEM[2],
        'p_dest_lat': DESTINO[0], 'p_dest_lng': DESTINO[1],
        'p_dest_label': DESTINO[2],
        'p_est_distance_km': 1.0,
        'p_payment_method': 'cash',
        'p_tokens_to_apply': 0,
    }, token=token)
    if st != 200:
        sys.exit('tvde_request_ride falhou: %s %s' % (st, r))
    ride_id = r['id']
    t0 = time.time()
    print('PEDIDA ride=%s pagamento=%s tarifa=%s ganho=%s' % (
        ride_id, r.get('payment_method'), r.get('est_fare_cents'),
        r.get('driver_earn_cents')), flush=True)

    ultimo = None
    while True:
        d = ler(token, ride_id)
        seg = time.time() - t0
        chave = (d.get('status'), d.get('current_offer_driver_id'),
                 d.get('driver_id'))
        if chave != ultimo:
            print('t=%.1fs status=%s oferta_a=%s motorista=%s expira=%s' % (
                seg, d.get('status'), d.get('current_offer_driver_id'),
                d.get('driver_id'), d.get('offer_expires_at')), flush=True)
            ultimo = chave
        oferta = d.get('current_offer_driver_id')
        if d.get('status') == 'solicitada' and oferta and oferta != DEMO_DRIVER:
            cancelar(token, ride_id, 'teste: oferta fugiu do demo')
            sys.exit(2)
        if d.get('status') != 'solicitada':
            if d.get('driver_id') == DEMO_DRIVER:
                print('ACEITE pelo demo aos %.1fs' % seg, flush=True)
                return
            print('FIM inesperado: %s' % json.dumps(d), flush=True)
            if d.get('driver_id') and d.get('driver_id') != DEMO_DRIVER:
                cancelar(token, ride_id, 'teste: aceite por outro')
            sys.exit(3)
        if seg > LIMITE:
            cancelar(token, ride_id, 'teste: nao aceite a tempo')
            sys.exit(4)
        time.sleep(0.7)


if __name__ == '__main__':
    main()
