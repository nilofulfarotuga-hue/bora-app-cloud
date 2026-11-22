#!/usr/bin/env python3
"""Mantem a alma do Hermes CURTA e o livro ao lado dela.

Desde 22/11/2026 (missao hermes-diretor-2026-11-20):
  - /opt/data/SOUL.md e copia de /opt/data/SOUL-base.md, e so e reescrito quando a base muda.
    Antes colava-se aqui o livro inteiro de 30 em 30 min: a alma tinha 70 KB, ia em todas as
    chamadas e, como mudava a cada meia hora, obrigava a pagar de novo o cache do prompt.
  - /opt/data/LIVRO-AO-ACORDAR.md leva as paginas do livro que o Hermes le antes de trabalho
    de negocio (erros-aprendidos, regras-do-danilo, digest mais recente). So e reescrito
    quando o conteudo muda.
Corre de 30 em 30 min (cron do host, 8,38). Sem rede: mantem os ficheiros anteriores.
Missao original: livro-comum-2026-10-23."""
import io, json, os, sys, time, urllib.parse, urllib.request

ENVF = '/opt/whatsapp-bora/.env'
BASE = '/opt/data/SOUL-base.md'
SOUL = '/opt/data/SOUL.md'
COPIA = '/opt/data/LIVRO-AO-ACORDAR.md'
UID = 10000
TETO_ALMA = 10000  # bytes; a alma nunca passa disto


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


def ler(caminho):
    try:
        return io.open(caminho, encoding='utf-8').read()
    except OSError:
        return None


def escrever_se_mudou(caminho, texto):
    """So toca no ficheiro quando o conteudo e diferente (nao estraga o cache do prompt)."""
    if ler(caminho) == texto:
        return False
    tmp = caminho + '.tmp'
    io.open(tmp, 'w', encoding='utf-8', newline='\n').write(texto)
    os.chown(tmp, UID, UID)
    os.chmod(tmp, 0o644)
    os.replace(tmp, caminho)
    return True


def alma():
    base = ler(BASE)
    if base is None:
        raise SystemExit('falta %s: nao mexo no SOUL.md' % BASE)
    texto = base.rstrip() + '\n'
    tamanho = len(texto.encode('utf-8'))
    if tamanho > TETO_ALMA:
        raise SystemExit('alma com %d bytes passa o teto de %d: nao mexo no SOUL.md' % (tamanho, TETO_ALMA))
    return escrever_se_mudou(SOUL, texto), tamanho


def livro():
    e = env()
    fixas = get(e, 'select=pagina,titulo,conteudo,atualizado_em&pagina=in.(erros-aprendidos,regras-do-danilo)')
    dig = get(e, 'select=pagina,titulo,conteudo,atualizado_em&pagina=like.digest-*&order=atualizado_em.desc&limit=1')
    por = {r['pagina']: r for r in fixas}
    if 'erros-aprendidos' not in por or 'regras-do-danilo' not in por:
        raise SystemExit('livro incompleto: nao mexo no LIVRO-AO-ACORDAR.md')
    blocos = [por['erros-aprendidos'], por['regras-do-danilo']] + dig
    linhas = ['# LIVRO AO ACORDAR — o que o Hermes le antes de trabalho de negocio (nao editar)',
              '# Ordem: erros-aprendidos, regras-do-danilo, digest mais recente. Renovado de 30 em 30 minutos.\n']
    for r in blocos:
        linhas.append('## [livro] %s — %s (atualizada %s)\n' % (r['pagina'], r['titulo'], (r.get('atualizado_em') or '')[:16]))
        linhas.append((r.get('conteudo') or '').strip() + '\n')
    return escrever_se_mudou(COPIA, '\n'.join(linhas)), (dig[0]['pagina'] if dig else '-')


def main():
    mudou_alma, tamanho = alma()
    try:
        mudou_livro, digest = livro()
    except Exception as ex:  # noqa: BLE001 - sem rede o livro antigo continua a servir
        print('%s AVISO livro: %s' % (time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime()), str(ex)[:200]))
        mudou_livro, digest = False, '?'
    print('%s OK SOUL.md %d bytes (%s); LIVRO-AO-ACORDAR %s; digest=%s' % (
        time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime()), tamanho,
        'reescrito' if mudou_alma else 'igual', 'reescrito' if mudou_livro else 'igual', digest))


if __name__ == '__main__':
    main()
