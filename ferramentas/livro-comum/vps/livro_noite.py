#!/usr/bin/env python3
"""Todas as noites (host da VPS): o que o Hermes aprendeu sozinho vai para o livro comum.
- livro-hermes-aprendeu : memories/MEMORY.md + memories/USER.md
- livro-hermes-skills   : skills que o Hermes criou (fora do .bundled_manifest), com o texto,
                          + lista das que vieram de fábrica
- livro-indice          : índice de todas as páginas (regenerado)
Missão livro-comum-2026-10-23. Usa livro_gravar.gravar (recusa segredos e [PESSOAL])."""
import glob, io, json, os, re, sys, time, urllib.request
sys.path.insert(0, '/opt/data/bin')
from livro_gravar import gravar, env  # noqa: E402

D = '/opt/data'
HOJE = time.strftime('%Y-%m-%d')


def ler(p):
    try:
        return io.open(p, encoding='utf-8', errors='replace').read().strip()
    except FileNotFoundError:
        return '(não existe)'


def frontmatter(txt):
    m = re.match(r'^---\s*\n(.*?)\n---', txt, re.S)
    fm = {}
    if m:
        for ln in m.group(1).splitlines():
            if ':' in ln and not ln.startswith(' '):
                k, v = ln.split(':', 1)
                fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm


def aprendeu():
    t = ('# O que o Hermes aprendeu sozinho (cópia de %s)\n\nGerado todas as noites por /opt/data/bin/livro_noite.py. '
         'A Claude.ai lê e funde no livro o que valer; contradições vão para a faxina de domingo.\n\n'
         '## memories/MEMORY.md (notas do próprio Hermes)\n\n%s\n\n## memories/USER.md (o que ele sabe do Danilo)\n\n%s\n'
         % (HOJE, ler(D + '/memories/MEMORY.md'), ler(D + '/memories/USER.md')))
    return gravar('livro-hermes-aprendeu', 'O que o Hermes aprendeu sozinho (MEMORY.md + USER.md), cópia noturna', t, 'hermes')


def skills():
    fabrica = set()
    for ln in ler(D + '/skills/.bundled_manifest').splitlines():
        if ':' in ln:
            fabrica.add(ln.split(':', 1)[0].strip())
    proprias, de_fabrica = [], []
    for p in sorted(glob.glob(D + '/skills/**/SKILL.md', recursive=True)):
        if '/.archive/' in p or '/.curator_backups/' in p or '/.hub/' in p:
            continue
        txt = ler(p)
        fm = frontmatter(txt)
        nome = fm.get('name') or os.path.basename(os.path.dirname(p))
        rel = os.path.relpath(os.path.dirname(p), D + '/skills')
        desc = (fm.get('description') or '').replace('\n', ' ')[:200]
        if os.path.basename(os.path.dirname(p)) in fabrica or nome in fabrica or rel.startswith('mattpocock/'):
            de_fabrica.append('- %s (%s) — %s' % (nome, rel, desc))
        else:
            corpo = txt if len(txt) < 3000 else txt[:3000] + '\n[... cortado]'
            proprias.append('### %s (%s)\n\n%s\n' % (nome, rel, corpo))
    t = ('# Skills do Hermes (cópia de %s)\n\nSkills que o Hermes criou sozinho: %d. Vindas de fábrica ou instaladas: %d. '
         'Fonte única das skills partilhadas: .claude/skills/ do repo bora-app-cloud (espelho na VPS em '
         '/opt/data/cortex-brain/.claude/skills). Skill nova do Hermes entra lá como hermes-<nome>, revista pelo critico.\n\n'
         '## Criadas pelo Hermes\n\n%s\n\n## De fábrica / instaladas (nome, pasta, descrição)\n\n%s\n'
         % (HOJE, len(proprias), len(de_fabrica), '\n'.join(proprias) or '(nenhuma)', '\n'.join(de_fabrica)))
    return gravar('livro-hermes-skills', 'Skills do Hermes (as que criou + lista das de fábrica), cópia noturna', t, 'hermes')


def indice():
    e = env()
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/claude_ai_memoria?select=pagina,titulo,atualizado_em&order=pagina',
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k})
    rows = json.load(urllib.request.urlopen(req, timeout=40))
    linhas = ['- %s — %s (%s)' % (r['pagina'], (r['titulo'] or '')[:140], (r['atualizado_em'] or '')[:10])
              for r in rows if r['pagina'] != 'livro-indice']
    t = ('# Índice do livro\n\nGerado automaticamente (missão livro-comum-2026-10-23; regenerado todas as noites pela VPS, '
         'última vez %s). Para ler uma página: select conteudo from claude_ai_memoria where pagina = \'<nome>\'; ou '
         'cortex "memoria-claude-ai-<nome>". Páginas com título [PESSOAL] são da vida do Danilo: só se leem quando a tarefa '
         'é dele, e nunca vão para motores grátis que treinam com o conteúdo.\n\n%s\n' % (HOJE, '\n'.join(linhas)))
    return gravar('livro-indice', 'Índice do livro — todas as páginas de claude_ai_memoria (gerado)', t, 'claude-code')


def resumo():
    """livro-resumo para o ChatGPT (projeto "Bora"): regras + erros + índice, sem páginas [PESSOAL]."""
    e = env()
    k = e['SUPABASE_SERVICE_ROLE_KEY']

    def get(q):
        req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/claude_ai_memoria?' + q,
                                     headers={'apikey': k, 'Authorization': 'Bearer ' + k})
        return json.load(urllib.request.urlopen(req, timeout=40))
    fx = {r['pagina']: r['conteudo'] for r in get('select=pagina,conteudo&pagina=in.(regras-do-danilo,erros-aprendidos)')}
    idx = ['- %s — %s' % (r['pagina'], (r['titulo'] or '')[:120]) for r in get('select=pagina,titulo&order=pagina')
           if not (r['titulo'] or '').upper().startswith('[PESSOAL]') and r['pagina'] != 'livro-indice']
    t = ('# Livro do Bora — resumo para o ChatGPT (%s)\n\nLê isto antes de responder ao Danilo. É a mesma verdade que a '
         'Claude.ai, o Hermes, o Claude Code e o OpenCode leem (tabela public.claude_ai_memoria). Gerado todas as noites '
         'pela VPS; páginas pessoais ficam de fora.\n\n## Regras do Danilo\n\n%s\n\n## Erros aprendidos (correções dele)\n\n%s\n\n'
         '## Índice do livro (sem páginas pessoais)\n\n%s\n'
         % (HOJE, fx.get('regras-do-danilo', ''), fx.get('erros-aprendidos', ''), '\n'.join(idx)))
    io.open(D + '/livro-resumo.md', 'w', encoding='utf-8').write(t)
    os.chown(D + '/livro-resumo.md', 10000, 10000)
    return gravar('livro-resumo', 'Livro do Bora — resumo para o ChatGPT (regras + erros + índice, sem pessoais), gerado', t, 'claude-code')


if __name__ == '__main__':
    for f in (aprendeu, skills, indice, resumo):
        try:
            print(time.strftime('[%F %T]'), f.__name__, 'OK %s %d' % f())
        except BaseException as ex:  # SystemExit do gravar também
            print(time.strftime('[%F %T]'), f.__name__, 'FALHOU', ex)
