# Prova pela app web (app.boraguarda.com) do Bora Assistente — missão embeddings-supabase-2026-11-03.
# Navegador à parte (perfil próprio no scratchpad), conta de teste e2e_client_a por link mágico.
# Nunca imprime chaves nem tokens. Uso: python -I prova_web.py <passo> [mensagem]
#   abrir     → entra com o link mágico, espera, captura
#   enviar    → (sessão já guardada) abre /assistente, liga a acessibilidade, escreve e envia a mensagem
import json, os, sys, time, urllib.request

SP = os.path.dirname(os.path.abspath(__file__))
RAIZ = 'C:/BoraLocal/projetosflutter/bora_app'
URL = 'https://ojykpzwqrtusfeakzrna.supabase.co'
APP = 'https://app.boraguarda.com'

def env():
    d = {}
    for l in open(f'{RAIZ}/backend/.env', encoding='utf-8'):
        if '=' in l:
            k, v = l.split('=', 1)
            d[k.strip()] = v.strip().strip('"')
    return d

def link_magico():
    srv = env()['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(f'{URL}/auth/v1/admin/generate_link', method='POST',
        data=json.dumps({'type': 'magiclink', 'email': 'e2e_client_a@boraapp.test', 'redirect_to': APP}).encode(),
        headers={'apikey': srv, 'Authorization': f'Bearer {srv}', 'Content-Type': 'application/json'})
    j = json.loads(urllib.request.urlopen(req).read())
    return j.get('action_link') or j.get('properties', {}).get('action_link')

from playwright.sync_api import sync_playwright

passo = sys.argv[1]
msg = sys.argv[2] if len(sys.argv) > 2 else ''
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(user_data_dir=os.path.join(SP, 'pw-web'), headless=True,
                                               viewport={'width': 420, 'height': 860})
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    respostas = []
    def guarda(r):
        if 'functions/v1/client-assistant' in r.url and r.request.method == 'POST':
            try:
                respostas.append({'status': r.status, 'corpo': r.json()})
            except Exception as e:
                respostas.append({'status': r.status, 'erro': str(e)[:120]})
    page.on('response', guarda)
    if passo == 'abrir':
        page.goto(link_magico(), wait_until='domcontentloaded', timeout=90000)
        page.wait_for_timeout(20000)
        print('url:', page.url.split('#')[0])
        page.screenshot(path=os.path.join(SP, 'web_1_abrir.png'))
    elif passo == 'cliques':
        # python prova_web.py cliques <foto.png> x,y x,y ...   (abre a app e carrega por ordem)
        page.goto(APP + '/', wait_until='domcontentloaded', timeout=90000)
        page.wait_for_timeout(15000)
        for xy in sys.argv[3:]:
            if xy.startswith('t:'):
                page.keyboard.type(xy[2:], delay=40); page.wait_for_timeout(800); continue
            if xy == 'enter':
                page.keyboard.press('Enter'); page.wait_for_timeout(1500); continue
            x, y = (float(v) for v in xy.split(','))
            page.mouse.click(x, y)
            page.wait_for_timeout(3500)
        for _ in range(70):
            if respostas or not any(a.startswith('t:') for a in sys.argv[3:]):
                break
            page.wait_for_timeout(1000)
        page.wait_for_timeout(5000)
        page.screenshot(path=os.path.join(SP, msg))
        print('url:', page.url.split('#')[0])
        for r in respostas:
            c = r.get('corpo') or {}
            print(json.dumps({'http': r['status'], 'ok': c.get('ok'), 'motor_vetores': c.get('motor_vetores'),
                              'propostas': len(c.get('propostas') or []), 'texto': str(c.get('texto', ''))[:200]},
                             ensure_ascii=False))
    elif passo == 'enviar':
        page.goto(APP + '/#/assistente', wait_until='domcontentloaded', timeout=90000)
        page.wait_for_timeout(15000)
        try:
            page.locator('flt-semantics-placeholder').click(force=True, timeout=5000)
        except Exception as e:
            print('acessibilidade:', str(e)[:80])
        page.wait_for_timeout(2000)
        page.screenshot(path=os.path.join(SP, 'web_2_assistente.png'))
        campo = page.locator('input, textarea').first
        campo.click(timeout=15000)
        page.keyboard.type(msg, delay=30)
        page.keyboard.press('Enter')
        for _ in range(60):
            if respostas:
                break
            page.wait_for_timeout(1000)
        page.wait_for_timeout(4000)
        page.screenshot(path=os.path.join(SP, 'web_3_resposta.png'))
        for r in respostas:
            c = r.get('corpo') or {}
            print(json.dumps({'http': r['status'], 'ok': c.get('ok'), 'motor_vetores': c.get('motor_vetores'),
                              'propostas': len(c.get('propostas') or []), 'texto': str(c.get('texto', ''))[:200]},
                             ensure_ascii=False))
        if not respostas:
            print('sem resposta do client-assistant')
    ctx.close()
