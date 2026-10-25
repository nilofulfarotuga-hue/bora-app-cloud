#!/usr/bin/env python3
"""Radar diário de freelas (missão livro-comum-2026-10-23, Bloco 5f). HOST, 08:30 Lisboa.
O Danilo deu autorização permanente (28/09) para propostas no Upwork, 99Freelas, Contra e Freelancer.com.
Fontes que respondem sem conta: API pública da Freelancer.com e a lista pública do 99Freelas.
(Upwork fechou o RSS em 2024 e o Contra não tem lista pública: ficam para o Chrome do PC.)
Escolhe até 6 trabalhos que encaixam (Flutter, Supabase, sites, apps feitas com IA), escreve uma proposta curta
para cada um com o motor grátis (sem dados pessoais) e manda a lista em TEXTO ao Telegram. Não envia propostas:
isso faz-se pelo Chrome do PC, com a conta certa.  Uso: radar_freelas.py [--seco]"""
import html, json, os, re, subprocess, sys, time, urllib.parse, urllib.request

sys.path.insert(0, '/opt/data/rotinas')
VISTOS = '/opt/data/rotinas/radar_freelas_vistos.json'
UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36'
TERMOS = ['flutter', 'supabase', 'landing page', 'website', 'mobile app', 'aplicativo', 'site']
BOM = re.compile(r'flutter|supabase|firebase|landing|website|web site|site|app|aplicativo|wordpress|delivery|booking|marca', re.I)
MAU = re.compile(r'\bgame\b|blockchain|crypto|nft|betting|casino|adult|seo backlinks|data entry', re.I)
ROTEADOR = 'http://172.16.1.1:8792/v1/chat/completions'
PORTFOLIO = ('Sou o Danilo, da Bora App (Guarda, Portugal). Construí sozinho, com IA, a app Bora em Flutter + Supabase '
             '(delivery, TVDE, reservas; publicada na Google Play, App Store e web), com painel de administração, '
             'pagamentos Stripe/MB Way e notificações. Também faço sites rápidos com maquete antes do contrato.')


def get(url, timeout=30):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=timeout) as r:
        return r.read().decode('utf-8', 'replace')


def freelancer():
    out, agora = [], time.time()
    for t in TERMOS[:5]:
        try:
            j = json.loads(get('https://www.freelancer.com/api/projects/0.1/projects/active/?query=%s&limit=15&full_description=true'
                               % urllib.parse.quote(t)))
        except Exception as ex:
            print('freelancer %s: %s' % (t, ex)); continue
        for p in j.get('result', {}).get('projects', []):
            if agora - p.get('time_submitted', 0) > 26 * 3600:
                continue
            b = p.get('budget') or {}
            taxa = {'USD': 1, 'EUR': 1.1, 'GBP': 1.3, 'INR': 0.012, 'AUD': 0.65, 'CAD': 0.73}.get((p.get('currency') or {}).get('code'), 0.5)
            if (b.get('maximum') or b.get('minimum') or 0) * taxa < 100:
                continue
            out.append({'id': 'fl-%s' % p['id'], 'fonte': 'Freelancer.com', 'titulo': p.get('title', ''),
                        'link': 'https://www.freelancer.com/projects/%s' % p.get('seo_url', p['id']),
                        'orcamento': '%s %s-%s' % ((p.get('currency') or {}).get('code', ''), b.get('minimum', '?'), b.get('maximum', '?')),
                        'texto': (p.get('description') or p.get('preview_description') or '')[:1200]})
    return out


def noventa_e_nove():
    out = []
    for t in ('flutter', 'aplicativo', 'site'):
        try:
            h = get('https://www.99freelas.com.br/projects?q=%s' % t)
        except Exception as ex:
            print('99freelas %s: %s' % (t, ex)); continue
        for m in re.finditer(r'<h1 class="title">\s*<a href="([^"]+)"[^>]*>([^<]+)</a>(.*?)(?=<h1 class="title">|$)', h, re.S):
            link = 'https://www.99freelas.com.br' + m.group(1).split('?')[0]
            desc = re.sub(r'<[^>]+>', ' ', m.group(3))
            out.append({'id': '99-' + link.rsplit('-', 1)[-1], 'fonte': '99Freelas', 'titulo': html.unescape(m.group(2).strip()),
                        'link': link, 'orcamento': 'a combinar', 'texto': html.unescape(re.sub(r'\s+', ' ', desc))[:800]})
    return out


def motor(titulo, texto, fonte):
    lingua = 'português do Brasil' if fonte == '99Freelas' else 'inglês'
    corpo = {'model': 'perfil:volume', 'max_tokens': 350, 'temperature': 0.5, 'messages': [
        {'role': 'system', 'content': 'Escreves propostas curtas de freelancer em %s, máximo 90 palavras, tom humano. Usa só estes '
                                      'factos sobre quem propõe: %s Não inventes clientes, prazos nem preços; termina com uma '
                                      'pergunta concreta sobre o projeto.' % (lingua, PORTFOLIO)},
        {'role': 'user', 'content': 'Projeto: %s\n%s\n\nEscreve a proposta SÓ em %s.' % (titulo, texto[:1000], lingua)}]}
    req = urllib.request.Request(ROTEADOR, data=json.dumps(corpo, ensure_ascii=False).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return (json.load(r)['choices'][0]['message']['content'] or '').strip()


def main():
    seco = '--seco' in sys.argv
    vistos = set(json.load(open(VISTOS))) if os.path.exists(VISTOS) else set()
    todos, ja = [], set()
    for x in freelancer() + noventa_e_nove():
        if x['id'] in vistos or x['id'] in ja:
            continue
        ja.add(x['id'])
        alvo = x['titulo'] + ' ' + x['texto']
        if BOM.search(alvo) and not MAU.search(alvo):
            todos.append(x)
    escolhidos = todos[:6]
    linhas = ['Radar de freelas %s — %d trabalhos novos que encaixam (de %d vistos). As propostas estão escritas; '
              'enviam-se pelo Chrome do PC com a tua conta.' % (time.strftime('%d/%m'), len(escolhidos), len(ja))]
    for i, x in enumerate(escolhidos, 1):
        try:
            prop = motor(x['titulo'], x['texto'], x['fonte'])
        except Exception as ex:
            prop = '(o motor não respondeu: %s)' % str(ex)[:60]
        linhas.append('\n%d) %s — %s — %s\n%s\nProposta:\n%s' % (i, x['fonte'], x['titulo'], x['orcamento'], x['link'], prop))
        vistos.add(x['id'])
    msg = '\n'.join(linhas)
    print(msg)
    if escolhidos and not seco:
        subprocess.run(['/opt/data/scripts/gritar.sh', msg[:3900]], timeout=60)
        json.dump(sorted(vistos)[-3000:], open(VISTOS, 'w'))


if __name__ == '__main__':
    main()
