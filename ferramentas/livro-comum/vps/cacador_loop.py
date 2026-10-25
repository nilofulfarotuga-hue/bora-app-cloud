#!/usr/bin/env python3
"""Caçador em loop (missão livro-comum-2026-10-23, Bloco 5b/5c). Corre no HOST da VPS, dias úteis 07:30 Lisboa.

O que faz, sem comprar listas e sem a Places API (paga):
 1. escolhe a próxima (zona, nicho) da rotação — Portugal inteiro + Brasil;
 2. procura no OpenStreetMap (Overpass) negócios desse nicho com site;
 3. procura o email no SITE DO PRÓPRIO NEGÓCIO (onde a lei manda pô-lo) e confirma o MX do domínio;
 4. mede o gancho (sem https, site não abre, sem telemóvel, sem livro de reclamações) — só o medido;
 5. regista em prospects_presenca (RPC prospect_registar + prospect_contacto_registar);
 6. faz uma maquete honesta (só dados públicos do negócio) e regista-a (prospect_amostra_registar).
Daí para a frente é a máquina que já existe: redator (08:00, molde fixo) → carteiro (09:30-11:30, máx/dia).
Uso: cacador_loop.py [--seco] [--max N] [--zona NOME] [--nicho CHAVE]"""
import argparse, hashlib, html, json, os, re, ssl, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import E, SUPA_URL  # noqa: E402

CHAVE = E.get('PROSPECTS_KEY') or ''
ANON = E.get('SUPABASE_ANON_KEY') or ''
ESTADO = '/opt/data/rotinas/cacador_estado.json'
LOG = '/var/log/cacador-loop.log'
PUBLICO = '/opt/data/social/publico/demo'
URL_DEMO = 'https://social.srv1786862.hstgr.cloud/demo/%s/'
UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
CTX = ssl.create_default_context(); CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE
OVERPASS = ('https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter',
            'https://maps.mail.ru/osm/tools/overpass/api/interpreter')

# (nome no OSM, admin_level, país) — municípios PT são admin_level 7; no Brasil 8.
ZONAS = [('Viseu', 7, 'PT'), ('Coimbra', 7, 'PT'), ('Aveiro', 7, 'PT'), ('Braga', 7, 'PT'), ('Leiria', 7, 'PT'),
         ('Évora', 7, 'PT'), ('Faro', 7, 'PT'), ('Castelo Branco', 7, 'PT'), ('Covilhã', 7, 'PT'),
         ('Viana do Castelo', 7, 'PT'), ('Vila Real', 7, 'PT'), ('Bragança', 7, 'PT'), ('Santarém', 7, 'PT'),
         ('Setúbal', 7, 'PT'), ('Portimão', 7, 'PT'), ('Lagos', 7, 'PT'), ('Funchal', 7, 'PT'),
         ('Ponta Delgada', 7, 'PT'), ('Porto', 7, 'PT'), ('Lisboa', 7, 'PT'), ('Seia', 7, 'PT'), ('Gouveia', 7, 'PT'),
         ('Florianópolis', 8, 'BR'), ('Curitiba', 8, 'BR')]
# chave → (filtro Overpass, categoria em português, cliente_tipo)
NICHOS = {
    'alojamento': ('["tourism"~"^(guest_house|hotel|apartment|hostel)$"]', 'alojamento', 'site'),
    'clinicas': ('["amenity"~"^(dentist|clinic|doctors)$"]', 'clínica', 'site'),
    'advogados': ('["office"="lawyer"]', 'advogados', 'site'),
    'imobiliarias': ('["office"="estate_agent"]', 'imobiliária', 'site'),
    'estetica': ('["shop"~"^(hairdresser|beauty)$"]', 'barbearia/estética', 'site'),
    'oficinas': ('["shop"="car_repair"]', 'oficina', 'site'),
}
CADEIAS = ('springfield', 'lanidor', 'telepizza', 'ibis', 'pestana', 'vila galé', 'meliá', 'tivoli', 'novotel',
           'remax', 're/max', 'era ', 'century 21', 'kw ', 'keller williams', 'decathlon', 'norauto', 'midas',
           'carglass', 'bosch car service', 'montebelo', 'hotel ibis', 'b&b hotels', 'eurostars', 'dom pedro', 'wells', 'pingo doce', 'continente', 'jumbo', 'hospital', 'cuf', 'luz saúde')
NAO_E_SITE = ('facebook.com', 'instagram.com', 'booking.com', 'tripadvisor.', 'airbnb.', 'google.', 'linktr.ee',
              'wa.me', 'whatsapp.com', 'youtube.com', 'linkedin.com', 'olx.', 'idealista.', 'imovirtual.')
INSTITUICOES = ('.gov.', 'gov.pt', 'sns.', 'min-saude', '.uc.pt', 'ulisboa', '.up.pt', 'uminho', '.ua.pt', '.edu', 'ipleiria',
                'ipv.pt', 'ipcb.pt', 'cm-', 'jf-', 'santacasa', 'scml', 'hospital', 'universidade', 'municipio')
EMAIL_RE = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
EMAIL_LIXO = ('example.', 'sentry', 'wixpress', 'domain.', 'email.com', 'yourmail', 'seuemail', '.png', '.jpg',
              '.webp', '.gif', 'noreply', 'no-reply', 'u003e', '@2x')
PAGINAS = ('', 'contactos', 'contacto', 'contactos/', 'contacto/', 'contact', 'contato', 'politica-de-privacidade',
           'privacidade', 'termos-e-condicoes')


def log(msg):
    linha = time.strftime('[%Y-%m-%d %H:%M:%S] ') + msg
    print(linha, flush=True)
    try:
        open(LOG, 'a', encoding='utf-8').write(linha + '\n')
    except OSError:
        pass


def rpc(nome, corpo):
    req = urllib.request.Request(SUPA_URL + '/rest/v1/rpc/' + nome, data=json.dumps(corpo).encode(), method='POST',
                                 headers={'apikey': ANON, 'Authorization': 'Bearer ' + ANON,
                                          'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=40) as r:
        t = r.read().decode()
        return json.loads(t) if t else None


def http(url, timeout=20, dados=None, ua=UA):
    req = urllib.request.Request(url, data=dados, headers={'User-Agent': ua, 'Accept': '*/*', 'Accept-Language': 'pt-PT,pt;q=0.9'})
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
        return r.geturl(), r.read(600000).decode('utf-8', 'replace')


def overpass(zona, nivel, filtro):
    q = ('[out:json][timeout:90];area["name"="%s"]["boundary"="administrative"]["admin_level"="%d"]->.a;'
         '(nwr%s["website"](area.a);nwr%s["contact:website"](area.a););out center tags 120;' % (zona, nivel, filtro, filtro))
    for ep in OVERPASS:
        try:
            _, t = http(ep, timeout=120, dados=urllib.parse.urlencode({'data': q}).encode(), ua='BoraCacador/1.0 (+https://boraguarda.com)')
            return json.loads(t).get('elements', [])
        except Exception as ex:
            log('  overpass %s falhou: %s' % (ep.split('/')[2], str(ex)[:80]))
    return None


def mx_ok(dominio):
    try:
        _, t = http('https://dns.google/resolve?name=%s&type=MX' % urllib.parse.quote(dominio), timeout=15)
        return any(a.get('type') == 15 for a in json.loads(t).get('Answer', []))
    except Exception:
        return False


def dominio_de(url):
    h = urllib.parse.urlparse(url if '://' in url else 'http://' + url).hostname or ''
    return h[4:] if h.startswith('www.') else h


def medir_e_achar_email(site):
    """Abre o site e as páginas de contacto; devolve (email, fonte, gancho[], viu_site)."""
    base = site if '://' in site else 'http://' + site
    dom = dominio_de(base)
    gancho, achados, viu, home = [], [], False, ''
    for i, pag in enumerate(PAGINAS):
        url = base.rstrip('/') + '/' + pag if pag else base
        try:
            final, t = http(url)
        except Exception:
            if i == 0:
                try:
                    final, t = http(base.replace('http://', 'https://'))
                except Exception:
                    gancho.append('o site %s nao abre' % dom)
                    return None, None, gancho, False
            else:
                continue
        viu = True
        if i == 0:
            home = t
            if len(t) < 3000:  # página-relé (redirecionamento por JS, moldura): não se mede nada nela
                return None, None, [], False
            if not final.startswith('https://'):
                try:
                    http('https://' + (urllib.parse.urlparse(final).hostname or dom), timeout=12)
                except Exception:
                    gancho.append('o site nao tem ligacao segura (https)')
            if not re.search(r'''name\s*=\s*["']?viewport''', t, re.I):
                gancho.append('o site nao esta preparado para telemovel')
        t2 = html.unescape(urllib.parse.unquote(t.replace('[at]', '@').replace('(at)', '@')))
        for e in EMAIL_RE.findall(t2):
            e = e.strip('.').strip().lower().lstrip('%20')
            if any(x in e for x in EMAIL_LIXO):
                continue
            achados.append((e, url))
        if achados and i >= 1:
            break
    if dom.endswith('.pt') and home and 'livroreclamacoes' not in home.lower():
        gancho.append('falta o livro de reclamacoes')
    # preferir o email do próprio domínio; depois qualquer um com MX
    achados.sort(key=lambda x: (dominio_de('x@' + x[0].split('@')[1]) != dom,))
    vistos = set()
    for e, fonte in achados:
        if e in vistos:
            continue
        vistos.add(e)
        if mx_ok(e.split('@')[1]):
            return e, fonte, gancho, viu
    return None, None, gancho, viu


def token_de(fonte_id):
    return hashlib.sha256((fonte_id + '|demo-bora-2026').encode()).hexdigest()[:14]


def maquete(p, gancho_pt):
    """Página de pré-visualização. Só dados públicos do negócio (nome, morada, telefone, site); sem
    avaliações nem elogios inventados. Paleta Bora; tipografia com carácter (Fraunces + Inter)."""
    esc = lambda s: html.escape(s or '')
    tel = p.get('telefone') or ''
    morada = p.get('morada') or p.get('concelho') or ''
    mapa = 'https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=18/%s/%s' % (p['lat'], p['lon'], p['lat'], p['lon'])
    servicos = {'alojamento': ['Quartos e preços à vista', 'Reserva direta, sem comissões de plataformas', 'Como chegar e o que ver perto'],
                'clínica': ['Especialidades e equipa', 'Marcação online a qualquer hora', 'Acordos e contactos'],
                'advogados': ['Áreas de prática', 'Primeira consulta: como marcar', 'Atendimento em várias línguas'],
                'imobiliária': ['Imóveis em destaque', 'Avaliação gratuita do seu imóvel', 'Contacto direto com o consultor'],
                'barbearia/estética': ['Serviços e duração', 'Marcação pelo telemóvel em 30 segundos', 'Galeria de trabalhos'],
                'oficina': ['Serviços e revisões', 'Pedido de orçamento em 1 minuto', 'Horário e como chegar']}.get(p['categoria'], ['Serviços', 'Contactos', 'Como chegar'])
    cards = ''.join('<div class="card"><span>%02d</span><p>%s</p></div>' % (i + 1, esc(s)) for i, s in enumerate(servicos))
    return '''<!doctype html><html lang="pt-PT"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>%(nome)s — pré-visualização</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=Inter:wght@400;600&display=swap" rel="stylesheet">
<style>:root{--verde:#16A34A;--laranja:#F97316;--tinta:#14201a;--papel:#F6F4EE}*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,sans-serif;color:var(--tinta);background:var(--papel)}
.faixa{background:var(--tinta);color:#e9efe9;font-size:13px;padding:10px 16px;text-align:center}.faixa b{color:#8ee0a8}
header{padding:64px 20px 40px;max-width:980px;margin:auto}h1{font-family:Fraunces,serif;font-size:clamp(40px,8vw,84px);line-height:.95;margin:0 0 18px;letter-spacing:-.02em}
.sub{font-size:19px;max-width:620px;opacity:.85}.cta{display:inline-block;margin-top:26px;background:var(--laranja);color:#fff;padding:15px 24px;border-radius:999px;text-decoration:none;font-weight:600}
main{max-width:980px;margin:auto;padding:0 20px 60px}.grelha{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin:30px 0}
.card{background:#fff;border-radius:18px;padding:22px;border:1px solid #e3e0d6}.card span{font-family:Fraunces,serif;color:var(--verde);font-size:28px}.card p{margin:10px 0 0;font-weight:600}
.nota{background:#fff;border-left:5px solid var(--verde);border-radius:12px;padding:20px 22px;margin:34px 0}.contactos{display:flex;flex-wrap:wrap;gap:12px}.contactos a,.contactos div{background:#fff;border:1px solid #e3e0d6;border-radius:12px;padding:12px 16px;color:var(--tinta);text-decoration:none}
footer{font-size:13px;opacity:.7;text-align:center;padding:30px 16px}</style></head><body>
<div class="faixa">Pré-visualização feita pela <b>Bora App — Guarda</b> para %(nome)s. Ainda não é o vosso site: é o que faríamos.</div>
<header><h1>%(nome)s</h1><div class="sub">%(categoria_cap)s em %(concelho)s. Tudo o que um cliente precisa, num ecrã de telemóvel: o que fazem, como marcar e onde estão.</div>
%(cta)s</header><main><div class="grelha">%(cards)s</div>
<div class="nota"><b>O que vimos ao procurar-vos na internet:</b> %(gancho)s. Numa página como esta isso fica resolvido, e quem vos procura no Google encontra logo como vos contactar.</div>
<h2 style="font-family:Fraunces,serif">Contactos</h2><div class="contactos">%(tel_html)s<div>%(morada)s</div><a href="%(mapa)s">Ver no mapa</a></div></main>
<footer>Página de demonstração preparada pela Bora App — Guarda (boraguarda.com). Dados públicos do negócio; sem fotos nem textos inventados.</footer></body></html>''' % {
        'nome': esc(p['nome']), 'categoria_cap': esc(p['categoria'].capitalize()), 'concelho': esc(p.get('concelho') or ''),
        'cta': ('<a class="cta" href="tel:%s">Ligar agora</a>' % esc(tel)) if tel else '', 'cards': cards,
        'gancho': esc(gancho_pt), 'tel_html': ('<a href="tel:%s">%s</a>' % (esc(tel), esc(tel))) if tel else '',
        'morada': esc(morada), 'mapa': esc(mapa)}


FRASE = {'nao abre': 'o vosso site não está a abrir', 'ligacao segura': 'o site não tem ligação segura (falta o https)',
         'telemovel': 'o site não está preparado para telemóvel', 'livro de reclamacoes': 'falta a ligação ao livro de reclamações eletrónico'}


def gancho_pt(g):
    partes = [v for k, v in FRASE.items() if any(k in x for x in g)]
    return ' e '.join(partes[:2]) if partes else 'há espaço para a vossa presença online trabalhar mais por vocês'


def ja_existem(ids):
    if not ids:
        return set()
    lista = ','.join('"%s"' % i for i in ids)
    req = urllib.request.Request(SUPA_URL + '/rest/v1/rpc/prospects_ler', data=json.dumps({'p_chave': CHAVE}).encode(),
                                 method='POST', headers={'apikey': ANON, 'Authorization': 'Bearer ' + ANON, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            todos = json.load(r) or []
        return {x.get('fonte_id') for x in todos} & set(ids)
    except Exception as ex:
        log('  prospects_ler falhou (%s): sigo e o on conflict trata dos repetidos' % str(ex)[:60])
        return set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seco', action='store_true'); ap.add_argument('--max', type=int, default=15)
    ap.add_argument('--zona'); ap.add_argument('--nicho'); ap.add_argument('--tudo', action='store_true')
    a = ap.parse_args()
    st = json.load(open(ESTADO)) if os.path.exists(ESTADO) else {'i': 0}
    feitos, tentativas = 0, 0
    while feitos < a.max and tentativas < 6:
        i = st['i']
        zona, nivel, pais = next((z for z in ZONAS if z[0] == a.zona), ZONAS[i % len(ZONAS)]) if a.zona else ZONAS[i % len(ZONAS)]
        chave = a.nicho or list(NICHOS)[(i // len(ZONAS) + i) % len(NICHOS)]
        filtro, categoria, tipo = NICHOS[chave]
        st['i'] = i + 1; tentativas += 1
        log('zona=%s (%s) nicho=%s' % (zona, pais, chave))
        els = overpass(zona, nivel, filtro)
        if els is None:
            log('  overpass sem resposta; passo à próxima'); continue
        cand = []
        for el in els:
            t = el.get('tags', {})
            nome = (t.get('name') or '').strip()
            site = (t.get('website') or t.get('contact:website') or '').strip()
            if not nome or not site or any(c in nome.lower() for c in CADEIAS) or any(x in site.lower() for x in NAO_E_SITE):
                continue
            lat = el.get('lat') or (el.get('center') or {}).get('lat'); lon = el.get('lon') or (el.get('center') or {}).get('lon')
            cand.append({'fonte_id': 'osm:%s/%s' % (el['type'], el['id']), 'nome': nome, 'categoria': categoria,
                         'website': site, 'telefone': t.get('phone') or t.get('contact:phone'), 'lat': lat, 'lon': lon,
                         'email_osm': t.get('email') or t.get('contact:email'), 'concelho': zona if pais == 'PT' else '%s (Brasil)' % zona,
                         'morada': ' '.join(x for x in (t.get('addr:street'), t.get('addr:housenumber'), t.get('addr:city')) if x) or None})
        velhos = ja_existem([c['fonte_id'] for c in cand])
        cand = [c for c in cand if c['fonte_id'] not in velhos]
        log('  %d com site; %d novos' % (len(els), len(cand)))
        for c in cand:
            if feitos >= a.max:
                break
            email, fonte, g, viu = medir_e_achar_email(c['website'])
            if not email and c.get('email_osm') and mx_ok(c['email_osm'].split('@')[-1]):
                email, fonte = c['email_osm'].strip().lower(), 'openstreetmap'
            if not email:
                continue
            if any(x in (email + ' ' + c['website'] + ' ' + c['nome']).lower() for x in INSTITUICOES):
                log('  - %s: instituição pública, fora' % c['nome'])
                continue
            if not g and not a.tudo:
                log('  - %s: email ok mas sem defeito medido no site; fica para depois' % c['nome'])
                continue
            gp = gancho_pt(g)
            log('  + %s | %s | %s | gancho: %s' % (c['nome'], email, fonte[:60], gp))
            if a.seco:
                feitos += 1; continue
            linha = {k: c[k] for k in ('fonte_id', 'nome', 'categoria', 'website', 'telefone', 'lat', 'lon', 'concelho', 'morada')}
            linha.update({'email': email, 'sem_site': False, 'sem_telefone': not c['telefone'], 'pontuacao': 60 + 10 * min(len(g), 3),
                          'notas': 'caçador em loop %s (%s/%s)' % (time.strftime('%Y-%m-%d'), zona, chave)})
            pid = rpc('prospect_registar', {'p_chave': CHAVE, 'p_linha': linha})
            rpc('prospect_contacto_registar', {'p_chave': CHAVE, 'p_id': pid, 'p_linha': {
                'email_verificado': True, 'email_fonte': fonte, 'gancho': '; '.join(g) or 'sem defeito medido',
                'cliente_tipo': tipo, 'canal_preferido': 'email'}})
            tok = token_de(c['fonte_id'])
            pasta = os.path.join(PUBLICO, tok); os.makedirs(pasta, exist_ok=True)
            open(os.path.join(pasta, 'index.html'), 'w', encoding='utf-8').write(maquete(dict(linha, **c), gp))
            rpc('prospect_amostra_registar', {'p_chave': CHAVE, 'p_prospect': pid, 'p_linha': {
                'link_unico': URL_DEMO % tok, 'mini_site': 'social/publico/demo/%s/index.html' % tok}})
            feitos += 1
        json.dump(st, open(ESTADO, 'w'))
    try:
        rpc('carteiro_registo', {'p_chave': CHAVE, 'p_passo': 'b5-cacador', 'p_estado': 'ok' if feitos else 'vazio',
                                 'p_detalhe': '%d negócios novos com email verificado e maquete%s' % (feitos, ' (seco)' if a.seco else '')})
    except Exception as ex:
        log('  carteiro_registo falhou: %s' % ex)
    log('FIM: %d novos%s' % (feitos, ' (seco)' if a.seco else ''))


if __name__ == '__main__':
    main()
