# -*- coding: utf-8 -*-
"""DEPOIS DA APROVACAO DA APPLE: devolve os logotipos das lojas a app.

NAO CORRER ANTES DE A APP ESTAR APROVADA.

O que existe hoje
-----------------
`platform_settings.ios_hide_nonpartner_logos` esconde o logotipo de QUALQUER
loja nao-parceira, em TODA a app iOS. Os mercados e a farmacia ficam com uma
letra no lugar do logotipo. Foi decisao consciente para a revisao: a Apple e'
estrita com marca registada de terceiros sem parceria formal (Guideline
5.2.1), e a Bora nao tem acordo de marca com o Continente, o Auchan ou o Lidl.

O que este script faz
---------------------
Passa o interruptor a valer SO nas capturas para a App Store, e nao na app
que o cliente usa. A partir daqui:

  * o cliente volta a ver os logotipos, como ja acontece no Android ha meses;
  * as capturas que enviamos a Apple continuam sem logotipos de terceiros,
    porque so' nelas o arnes liga `CAPTURA_APP_STORE=true`.

Depois de correr: `flutter analyze lib/`, `flutter test`, e uma build nova.
O interruptor no servidor pode ficar como esta -- deixa de mandar na app.
"""
import io
import sys

CAMINHO = 'lib/config/ios_launch_flags.dart'

VELHO = """/// Esconder o logótipo desta loja nesta sessão? Só no iOS, só com o
/// interruptor ligado no servidor, e nunca para uma loja parceira.
bool shouldHideStoreLogo({required bool isPartner}) =>
    _isIOS && _hideNonPartnerLogos && !isPartner;"""

NOVO = """/// Esconder o logótipo desta loja nesta sessão?
///
/// DEPOIS DA APROVAÇÃO (ver `scripts/pos-aprovacao/logotipos_de_volta.py`):
/// o interruptor 5.2.1 passou a valer **só nas capturas para a App Store**.
/// Na app que o cliente usa os logótipos voltaram, como no Android. O que
/// vai para a Apple continua sem marcas de terceiros, porque só o arnês de
/// capturas corre com `CAPTURA_APP_STORE=true`.
const bool _modoCapturaAppStore =
    bool.fromEnvironment('CAPTURA_APP_STORE', defaultValue: false);

bool shouldHideStoreLogo({required bool isPartner}) =>
    _isIOS && _modoCapturaAppStore && _hideNonPartnerLogos && !isPartner;"""


def main():
    t = io.open(CAMINHO, encoding='utf-8').read()
    if _modoJaAplicado(t):
        print('ja estava aplicado — nada a fazer.')
        return 0
    if t.count(VELHO) != 1:
        print('O ficheiro mudou desde que isto foi escrito (2026-09-10).')
        print('Nao se aplica as cegas: abre %s e faz a mudanca a mao.' % CAMINHO)
        return 1
    io.open(CAMINHO, 'w', encoding='utf-8', newline='\n').write(
        t.replace(VELHO, NOVO))
    print('aplicado em', CAMINHO)
    print()
    print('agora: flutter analyze lib/  &&  flutter test  &&  build nova')
    return 0


def _modoJaAplicado(t):
    return 'CAPTURA_APP_STORE' in t


if __name__ == '__main__':
    sys.exit(main())
