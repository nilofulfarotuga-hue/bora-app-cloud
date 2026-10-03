"""PROVA NO NAVEGADOR — missão limpeza-so-limpeza-2026-10-02.

  python prova_web.py porta     Sou Estafeta > Criar conta: tem de abrir a escolha de actividade
  python prova_web.py login <nome-da-foto>   entra pela porta do prestador com a conta de prova

Imprime o que o ecrã diz (árvore de acessibilidade do Flutter) e guarda fotos.
"""
import json
import os
import re
import sys

from playwright.sync_api import sync_playwright

AQUI = os.path.dirname(os.path.abspath(__file__))
URL = os.environ.get('BORA_URL', 'https://app.boraguarda.com/')
FOTOS = os.path.join(AQUI, 'fotos')
PERFIL = os.path.join(AQUI, 'perfil-chrome')
os.makedirs(FOTOS, exist_ok=True)

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

ROTULOS = """() => {
  const out = [];
  document.querySelectorAll('flt-semantics, [aria-label]').forEach(e => {
    const t = (e.getAttribute('aria-label') || '').trim() ||
              (e.children.length === 0 ? (e.textContent || '').trim() : '');
    if (t && !out.includes(t)) out.push(t);
  });
  return out;
}"""


def ligar_acessibilidade(page):
    page.wait_for_selector('flt-semantics-placeholder', state='attached', timeout=90000)
    page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
    page.wait_for_timeout(1500)


def rotulos(page):
    return page.evaluate(ROTULOS)


def mostra(page, titulo, nome_foto):
    page.wait_for_timeout(2500)
    page.screenshot(path=os.path.join(FOTOS, nome_foto + '.png'))
    r = rotulos(page)
    print(f'--- {titulo} ({nome_foto}.png) ---')
    for t in r[:45]:
        print('  ·', t.replace('\n', ' / ')[:140])
    return r


def carrega(page, nome, timeout=30000):
    alvo = page.get_by_role('button', name=re.compile(nome)).first
    alvo.wait_for(state='attached', timeout=timeout)
    alvo.click(force=True)
    page.wait_for_timeout(2500)


def escreve(page, identificador, texto):
    campo = page.locator(f'[flt-semantics-identifier="{identificador}"]').first
    campo.wait_for(state='attached', timeout=30000)
    campo.click(force=True)
    page.wait_for_timeout(800)
    page.keyboard.type(texto, delay=25)
    page.wait_for_timeout(500)


def bundle(page):
    return page.evaluate("""() => performance.getEntriesByType('resource')
        .filter(r => /main\\.dart\\.js/.test(r.name))
        .map(r => r.decodedBodySize + ' bytes (transfer ' + r.transferSize + ')')""")


def main():
    passo = sys.argv[1]
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            PERFIL, channel='chrome', headless=False,
            viewport={'width': 430, 'height': 880},
            geolocation={'latitude': 40.5373, 'longitude': -7.2676},
            permissions=['geolocation', 'notifications'], locale='pt-PT')
        ctx.add_init_script(ARRANQUE)
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on('console', lambda m: print('  [consola]', m.text[:220]) if re.search(r'PushToken|FCM|fcm|token|messaging', m.text) else None)
        # O main.dart.js fica na cache HTTP e a prova media o build anterior
        # (lição de 08/09): limpa-se a cache e o service worker antes de abrir.
        cdp = ctx.new_cdp_session(page)
        cdp.send('Network.clearBrowserCache')
        page.goto(URL, wait_until='load', timeout=120000)
        page.evaluate("""async () => {
          const rs = await navigator.serviceWorker.getRegistrations();
          // O service worker das notificações fica: apagá-lo mata o token FCM.
          for (const r of rs) {
            const u = (r.active || r.waiting || r.installing || {}).scriptURL || '';
            if (!/firebase-messaging/.test(u)) await r.unregister();
          }
          for (const k of await caches.keys()) await caches.delete(k);
        }""")
        cdp.send('Network.clearBrowserCache')
        page.reload(wait_until='load', timeout=120000)
        ligar_acessibilidade(page)
        print('main.dart.js carregado:', bundle(page))
        print('Notification.permission:', page.evaluate('Notification.permission'))
        r = mostra(page, 'arranque', passo + '-0-arranque')

        # Sessão de uma corrida anterior: volta à escolha de perfil.
        if not any('Sou Estafeta' in t for t in r):
            print('(não está na escolha de perfil — a limpar a sessão local)')
            page.evaluate('localStorage.clear()')
            page.reload(wait_until='load')
            ligar_acessibilidade(page)
            mostra(page, 'depois de limpar', passo + '-0b-limpo')

        carrega(page, 'Sou Estafeta')
        mostra(page, 'porta do prestador', passo + '-1-porta')

        if passo == 'porta':
            carrega(page, 'Criar conta')
            r = mostra(page, 'depois de "Criar conta"', passo + '-2-criar-conta')
            ok = any('Limpeza' in t for t in r) and any('Entregas' in t for t in r)
            print('RESULTADO porta: escolha de actividade aberta =', ok)
        elif passo == 'login':
            nome = sys.argv[2]
            cred = json.load(open(os.path.join(AQUI, 'prova_conta.json'), encoding='utf-8'))
            escreve(page, 'fld_email', cred['email'])
            escreve(page, 'fld_password', cred['password'])
            page.screenshot(path=os.path.join(FOTOS, nome + '-campos.png'))
            carrega(page, '^Entrar$')
            page.wait_for_timeout(9000)
            r = mostra(page, 'depois de Entrar', nome)
            print('RESULTADO login: painel da limpeza =',
                  any('Limpezas — Profissional' in t for t in r),
                  '| em análise =', any('em análise' in t.lower() for t in r))
            page.wait_for_timeout(int(os.environ.get('ESPERA_FINAL_MS', '20000')))
            mostra(page, 'passados uns segundos', nome + '-b')
        ctx.close()


if __name__ == '__main__':
    main()
