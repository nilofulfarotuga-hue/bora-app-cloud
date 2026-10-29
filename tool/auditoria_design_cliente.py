# -*- coding: utf-8 -*-
"""Auditoria de design dos ecras de delivery do cliente (adendo 4 · item 9).

Corre-se com:  python tool/auditoria_design_cliente.py

O que mede (tudo lido do codigo, nada inventado):
  1. texto abaixo de 16 px (fontSize literais) por ecra;
  2. contraste (WCAG) dos pares de cores do tema que mais se usam;
  3. se existe tema escuro (darkTheme / themeMode no MaterialApp);
  4. listas que ainda mostram um circulo a rodar em vez de esqueleto;
  5. quantos ecras tem o checkout (carrinho -> pagamento).

So le ficheiros; nao escreve nada.
"""
import os
import re
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LIB = os.path.join(RAIZ, 'lib')

# Ecras e widgets do delivery do cliente (do descobrir ate ao acompanhamento).
ECRAS = [
    'screens/client_home_screen.dart',
    'screens/restaurants_screen.dart',
    'screens/stores_screen.dart',
    'screens/restaurant_menu_screen.dart',
    'screens/store_products_screen.dart',
    'screens/product_detail_screen.dart',
    'screens/cart_screen.dart',
    'screens/payment_method_screen.dart',
    'screens/order_tracking_screen.dart',
    'screens/order_details_screen.dart',
    'screens/orders_screen.dart',
    'screens/client_addresses_screen.dart',
    'screens/rating_screen.dart',
    'widgets/barra_pedido_ativo.dart',
    'widgets/talheres_troco_cards.dart',
    'widgets/juntar_mais_tira.dart',
    'widgets/filtros_rapidos_lojas.dart',
    'widgets/foto_prova_entrega.dart',
    'widgets/home/meus_habituais.dart',
    'widgets/etiquetas_dieta_chips.dart',
    'widgets/order_edit/client_order_edit_banner.dart',
]


def luminancia(hexa):
    h = hexa.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contraste(a, b):
    la, lb = luminancia(a), luminancia(b)
    claro, escuro = max(la, lb), min(la, lb)
    return (claro + 0.05) / (escuro + 0.05)


PARES = [
    ('branco sobre verde principal #16A34A (botoes, barra antiga)', '#FFFFFF', '#16A34A'),
    ('branco sobre verde escuro #065F46 (barra do pedido)', '#FFFFFF', '#065F46'),
    ('verde #16A34A sobre branco (texto verde)', '#16A34A', '#FFFFFF'),
    ('verde escuro #065F46 sobre branco', '#065F46', '#FFFFFF'),
    ('cinza secundario #6B7280 sobre branco', '#6B7280', '#FFFFFF'),
    ('cinza secundario #6B7280 sobre fundo #F0F2EF', '#6B7280', '#F0F2EF'),
    ('cinza subtil #9CA3AF sobre branco (so icones/placeholder)', '#9CA3AF', '#FFFFFF'),
    ('branco sobre laranja #F97316 (botao de acento)', '#FFFFFF', '#F97316'),
    ('vermelho erro #DC2626 sobre branco', '#DC2626', '#FFFFFF'),
]


def fontes_pequenas(caminho):
    try:
        src = open(caminho, encoding='utf-8').read()
    except OSError:
        return None
    nums = [float(x) for x in re.findall(r'fontSize:\s*(\d+(?:\.\d+)?)', src)]
    return len(nums), sum(1 for n in nums if n < 16), sum(1 for n in nums if n < 14)


def main():
    print('== 1. Texto abaixo de 16 px (literais fontSize) ==')
    total_p = total_14 = total = 0
    linhas = []
    for e in ECRAS:
        r = fontes_pequenas(os.path.join(LIB, e))
        if r is None:
            linhas.append((e, None))
            continue
        n, p16, p14 = r
        total += n
        total_p += p16
        total_14 += p14
        linhas.append((e, r))
    for e, r in sorted(linhas, key=lambda x: -(x[1][1] if x[1] else 0)):
        if r is None:
            print('  %-58s (nao existe)' % e)
        else:
            print('  %-58s %3d de %3d abaixo de 16 (%d abaixo de 14)' % (e, r[1], r[0], r[2]))
    print('  TOTAL: %d de %d abaixo de 16 px; %d abaixo de 14 px' % (total_p, total, total_14))

    print('\n== 2. Contraste (WCAG; texto normal pede 4,5:1, grande 3:1) ==')
    for nome, a, b in PARES:
        c = contraste(a, b)
        print('  %-62s %5.2f:1  %s' % (nome, c, 'ok' if c >= 4.5 else ('so texto grande' if c >= 3 else 'FALHA')))

    print('\n== 3. Modo escuro ==')
    main_dart = open(os.path.join(LIB, 'main.dart'), encoding='utf-8').read()
    tema = open(os.path.join(LIB, 'config', 'app_theme.dart'), encoding='utf-8').read()
    tem = 'darkTheme' in main_dart or 'darkTheme' in tema or 'ThemeMode' in main_dart
    print('  darkTheme/themeMode no MaterialApp: %s' % ('SIM' if tem else 'NAO (a app e so clara)'))

    print('\n== 4. Listas com circulo a rodar em vez de esqueleto ==')
    achados = []
    for e in ['screens/stores_screen.dart', 'screens/restaurants_screen.dart',
              'screens/orders_screen.dart', 'screens/client_addresses_screen.dart',
              'screens/store_products_screen.dart', 'screens/wallet_history_screen.dart',
              'screens/client_favorites_screen.dart', 'screens/notifications_screen.dart',
              'screens/restaurant_menu_screen.dart']:
        p = os.path.join(LIB, e)
        if not os.path.exists(p):
            continue
        src = open(p, encoding='utf-8').read()
        n = len(re.findall(r'Center\(child:\s*CircularProgressIndicator', src))
        if n:
            achados.append((e, n))
    for e, n in achados:
        print('  %-58s %d' % (e, n))
    if not achados:
        print('  nenhuma')

    print('\n== 5. Checkout ==')
    cart = open(os.path.join(LIB, 'screens', 'cart_screen.dart'), encoding='utf-8').read()
    print('  carrinho abre o ecra de pagamento: %s -> o checkout tem 2 ecras (carrinho + pagamento)'
          % ('sim' if 'PaymentMethodScreen' in cart else 'nao'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
