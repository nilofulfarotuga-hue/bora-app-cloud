#!/usr/bin/env python3
"""Grava (upsert) uma pagina no livro public.claude_ai_memoria a partir de um ficheiro de texto.
Uso: livro_gravar.py <pagina> <titulo> <ficheiro|-> [origem]
Usa a service key do .env (nunca a imprime). Missao livro-comum-2026-10-23.
Recusa paginas cujo titulo comece por [PESSOAL] e conteudos com cara de segredo."""
import io, json, re, sys, urllib.request

ENVF = '/opt/whatsapp-bora/.env'
SEGREDO = re.compile(r'(sk_live_|sk_test_|sb_secret_|eyJhbGciOi|ghp_[A-Za-z0-9]{20}|AIza[0-9A-Za-z_-]{30}|-----BEGIN [A-Z ]*PRIVATE KEY)')


def env():
    e = {}
    for ln in io.open(ENVF, encoding='utf-8', errors='replace'):
        ln = ln.strip()
        if ln and not ln.startswith('#') and '=' in ln:
            k, v = ln.split('=', 1)
            e[k.strip()] = v.strip().strip('"').strip("'")
    return e


def gravar(pagina, titulo, conteudo, origem='claude-code'):
    if titulo.strip().upper().startswith('[PESSOAL]'):
        raise SystemExit('recusado: pagina [PESSOAL] nao se grava por aqui')
    if SEGREDO.search(conteudo):
        raise SystemExit('recusado: o conteudo parece ter um segredo')
    e = env()
    url = e['SUPABASE_URL'].rstrip('/') + '/rest/v1/claude_ai_memoria?on_conflict=pagina'
    corpo = json.dumps([{'pagina': pagina, 'titulo': titulo, 'conteudo': conteudo, 'origem': origem,
                         'atualizado_em': 'now()'}]).encode()
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(url, data=corpo, method='POST', headers={
        'apikey': k, 'Authorization': 'Bearer ' + k, 'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=representation'})
    with urllib.request.urlopen(req, timeout=40) as r:
        linhas = json.load(r)
    return linhas[0]['pagina'], len(linhas[0]['conteudo'])


if __name__ == '__main__':
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    pg, tit, f = sys.argv[1], sys.argv[2], sys.argv[3]
    org = sys.argv[4] if len(sys.argv) > 4 else 'claude-code'
    txt = sys.stdin.read() if f == '-' else io.open(f, encoding='utf-8').read()
    print('OK %s %d caracteres' % gravar(pg, tit, txt, org))
