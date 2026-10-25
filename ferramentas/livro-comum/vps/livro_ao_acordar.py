#!/usr/bin/env python3
"""Gera /opt/data/SOUL.md = SOUL-base.md + paginas do livro que o Hermes le ao acordar.
Corre de 30 em 30 min (cron do host, 8,38). Sem rede: mantem o SOUL.md anterior.
Missao livro-comum-2026-10-23."""
import io, json, os, sys, time, urllib.parse, urllib.request

ENVF = '/opt/whatsapp-bora/.env'
BASE = '/opt/data/SOUL-base.md'
SOUL = '/opt/data/SOUL.md'
COPIA = '/opt/data/LIVRO-AO-ACORDAR.md'
UID = 10000


def env():
    e = {}
    for ln in io.open(ENVF, encoding='utf-8', errors='replace'):
        ln = ln.strip()
        if ln and not ln.startswith('#') and '=' in ln:
            k, v = ln.split('=', 1)
            e[k.strip()] = v.strip().strip('"').strip("'")
    return e


def get(e, query):
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/claude_ai_memoria?' + query,
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r)


def escrever(caminho, texto):
    tmp = caminho + '.tmp'
    io.open(tmp, 'w', encoding='utf-8', newline='\n').write(texto)
    os.chown(tmp, UID, UID)
    os.chmod(tmp, 0o644)
    os.replace(tmp, caminho)


def main():
    e = env()
    fixas = get(e, 'select=pagina,titulo,conteudo,atualizado_em&pagina=in.(erros-aprendidos,regras-do-danilo)')
    dig = get(e, 'select=pagina,titulo,conteudo,atualizado_em&pagina=like.digest-*&order=atualizado_em.desc&limit=1')
    por = {r['pagina']: r for r in fixas}
    if 'erros-aprendidos' not in por or 'regras-do-danilo' not in por:
        raise SystemExit('livro incompleto: nao mexo no SOUL.md')
    blocos = [por['erros-aprendidos'], por['regras-do-danilo']] + dig
    agora = time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())
    livro = ['\n\n# ════════════════════════════════════════════════════════════',
             '# LIVRO AO ACORDAR — colado automaticamente às %s (não editar)' % agora,
             '# Ordem: erros-aprendidos → regras-do-danilo → digest mais recente.',
             '# ════════════════════════════════════════════════════════════\n']
    for r in blocos:
        livro.append('## [livro] %s — %s (atualizada %s)\n' % (r['pagina'], r['titulo'], (r.get('atualizado_em') or '')[:16]))
        livro.append((r.get('conteudo') or '').strip() + '\n')
    corpo = '\n'.join(livro)
    escrever(COPIA, corpo.lstrip())
    escrever(SOUL, io.open(BASE, encoding='utf-8').read().rstrip() + corpo)
    print('OK SOUL.md %d bytes; digest=%s' % (os.path.getsize(SOUL), dig[0]['pagina'] if dig else '-'))


if __name__ == '__main__':
    main()
