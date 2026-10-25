#!/usr/bin/env python3
"""Faxina semanal do livro (domingo à noite, host da VPS). Missão livro-comum-2026-10-23, Bloco 3e.
O bot escriba procura regras repetidas ou contraditórias e páginas paradas há mais de 30 dias;
o bot critico revê a proposta. Resultado na página livro-faxina-AAAA-MM-DD. NÃO apaga nada.
Páginas [PESSOAL] ficam de fora (os bots correm em motores grátis)."""
import json, subprocess, sys, time, urllib.request
sys.path.insert(0, '/opt/data/bin')
from livro_gravar import gravar, env  # noqa: E402

C = 'hermes-agent-fvnc-hermes-agent-1'
HOJE = time.strftime('%Y-%m-%d')


def get(q):
    e = env()
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/claude_ai_memoria?' + q,
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k})
    return json.load(urllib.request.urlopen(req, timeout=40))


def bot(nome, pedido, tecto=600):
    guiao = 'cd /opt/data && exec hermes -p "$1" --provider custom -z "$2"'
    r = subprocess.run(['docker', 'exec', '-u', 'hermes', '-e', 'HOME=/opt/data', C, 'sh', '-lc', guiao, '_', nome, pedido],
                       capture_output=True, text=True, timeout=tecto)
    return ((r.stdout or '').strip() or (r.stderr or '').strip())[:12000]


def main():
    fixas = {r['pagina']: r['conteudo'] for r in get('select=pagina,conteudo&pagina=in.(erros-aprendidos,regras-do-danilo)')}
    todas = get('select=pagina,titulo,atualizado_em&order=atualizado_em.asc')
    limite = time.strftime('%Y-%m-%d', time.gmtime(time.time() - 30 * 86400))
    velhas = ['- %s (%s) — %s' % (r['pagina'], r['atualizado_em'][:10], (r['titulo'] or '')[:90])
              for r in todas if (r['atualizado_em'] or '') < limite and not (r['titulo'] or '').upper().startswith('[PESSOAL]')
              and not r['pagina'].startswith(('digest-', 'arquivo-', 'livro-faxina-'))]
    pedido = ('És o escriba do Bora. Faxina semanal do LIVRO comum. NÃO apagas nada: só PROPÕES, em português de Portugal, '
              'em texto corrido curto. Tarefa: (1) regras repetidas entre as duas páginas abaixo (diz quais e qual versão '
              'ficar); (2) regras que se CONTRADIZEM (cita as duas frases); (3) das páginas com mais de 30 dias sem '
              'atualização, quais parecem ultrapassadas e precisam de o Danilo/Claude.ai confirmar. Máximo 40 linhas.\n\n'
              '=== erros-aprendidos ===\n%s\n\n=== regras-do-danilo ===\n%s\n\n=== páginas paradas há mais de 30 dias (%d) ===\n%s'
              % (fixas.get('erros-aprendidos', ''), fixas.get('regras-do-danilo', ''), len(velhas), '\n'.join(velhas[:80])))
    proposta = bot('escriba', pedido)
    revisao = bot('critico', 'És o critico do Bora. Revê esta proposta de faxina do livro: o que está errado, exagerado ou '
                             'inventado (aponta a frase), e o que falta. Não apagas nada. Máximo 20 linhas, português de Portugal.'
                             '\n\n=== PROPOSTA DO ESCRIBA ===\n' + proposta)
    t = ('# Faxina do livro — %s\n\nProposta automática (escriba) revista pelo critico. NADA foi apagado nem mudado: a '
         'Claude.ai e o Danilo decidem. Gerado por /opt/data/bin/livro_faxina.py (domingo à noite).\n\n## Proposta do escriba\n\n%s\n\n'
         '## Revisão do critico\n\n%s\n\n## Páginas paradas há mais de 30 dias (%d, sem [PESSOAL], digests e arquivos)\n\n%s\n'
         % (HOJE, proposta, revisao, len(velhas), '\n'.join(velhas)))
    print('OK %s %d' % gravar('livro-faxina-' + HOJE, 'Faxina do livro %s (proposta do escriba + revisão do critico; nada apagado)' % HOJE, t, 'hermes'))


if __name__ == '__main__':
    main()
