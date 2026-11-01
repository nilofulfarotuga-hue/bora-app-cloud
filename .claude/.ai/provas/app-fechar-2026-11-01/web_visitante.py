# Prova do visitante na web em produção (app.boraguarda.com), só leitura: não cria conta nem pedido.
# Uso: python web_visitante.py <pasta_saida> <passos...>
#   passo "clica:<rótulo exato ou prefixo com *>", "espera:<ms>", "foto:<nome>", "lista", "rola:<dy>"
import sys, os, re, time
from playwright.sync_api import sync_playwright

SAIDA = sys.argv[1]
PASSOS = sys.argv[2:]
os.makedirs(SAIDA, exist_ok=True)
PROIBIDO = re.compile(r'(apagar|eliminar|cancelar|rejeitar|pagar agora|confirmar pedido|criar conta e|sair|terminar sess)', re.I)

def rotulos(page):
    out = []
    for el in page.query_selector_all('flt-semantics[role="button"], flt-semantics[role="link"], flt-semantics[role="tab"], [role="button"], [role="link"], [role="tab"]'):
        try:
            t = (el.get_attribute('aria-label') or el.inner_text() or '').strip().replace('\n', ' | ')
            if t:
                out.append(t[:90])
        except Exception:
            pass
    return out

def texto(page):
    try:
        return ' '.join(page.locator('flt-semantics').all_inner_texts())[:1500]
    except Exception:
        return ''

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    ctx = b.new_context(viewport={'width': 430, 'height': 900}, locale='pt-PT')
    page = ctx.new_page()
    page.goto('https://app.boraguarda.com/', wait_until='load', timeout=90000)
    time.sleep(12)
    try:
        page.evaluate("document.querySelector('flt-semantics-placeholder') && document.querySelector('flt-semantics-placeholder').click()")
    except Exception as e:
        print('placeholder', e)
    time.sleep(2)
    for i, passo in enumerate(PASSOS):
        if passo.startswith('espera:'):
            time.sleep(int(passo[7:]) / 1000)
        elif passo == 'lista':
            print(f'[{i}] BOTOES:', rotulos(page))
            print(f'[{i}] TEXTO:', texto(page))
        elif passo.startswith('foto:'):
            page.screenshot(path=os.path.join(SAIDA, passo[5:] + '.png'))
            print(f'[{i}] foto', passo[5:])
        elif passo.startswith('toque:'):
            x, y = [int(v) for v in passo[6:].split(',')]
            page.mouse.click(x, y); time.sleep(3)
            print(f'[{i}] toque', x, y)
        elif passo.startswith('rola:'):
            page.mouse.move(215, 500); page.mouse.wheel(0, int(passo[5:])); time.sleep(1.5)
        elif passo.startswith('clica:'):
            alvo = passo[6:]
            prefixo = alvo.endswith('*')
            alvo_l = alvo.rstrip('*').lower()
            feito = False
            for el in page.query_selector_all('flt-semantics, [role="button"], [role="link"], [role="tab"]'):
                try:
                    t = (el.get_attribute('aria-label') or el.inner_text() or '').strip()
                except Exception:
                    continue
                if not t:
                    continue
                prim = t.split('\n')[0].strip().lower()
                ok = prim.startswith(alvo_l) if prefixo else prim == alvo_l
                if ok:
                    if PROIBIDO.search(prim) and prim != 'rejeitar':
                        print(f'[{i}] RECUSADO (proibido):', prim); break
                    el.scroll_into_view_if_needed(); el.click(); feito = True
                    print(f'[{i}] clicou:', prim[:80]); break
            if not feito:
                print(f'[{i}] NAO ENCONTROU:', alvo)
            time.sleep(4)
    b.close()
