import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Missão TVDE 05/09, parte 2 — Bloco 4C] O guarda da regra 3.13 do
/// `PADRAO_BORA.md`.
///
/// **A regra:** um botão trava-se pelo SEU pedido, nunca por um estado global
/// de ocupado. O estado de envio é LOCAL ao ecrã que o disparou.
///
/// **A cicatriz (05/09, corrida real, passageiro a pagar):** no fim da viagem
/// carregou em "Enviar avaliação" e não aconteceu nada. O botão tinha
/// `loading: store.busy` e já **nascia** desligado, porque outra operação do
/// `TvdeStore` estava a meio. O `busy` é um flag ÚNICO mexido por dezenas de
/// operações. Só saiu pelo "Agora não", que era um `TextButton` sem essa
/// dependência.
///
/// A regra estava no papel desde essa manhã. Este teste dá-lhe dentes: se
/// alguém voltar a ligar um botão ao `busy` de um store, a bateria fica
/// vermelha antes de chegar a um telemóvel.
///
/// **O que NÃO é apanhado, de propósito:**
///  - `_busy`, `_busyId`, `_sending`, `_enviando` — campos do próprio `State`.
///    São locais: é exactamente o padrão certo. Vários ecrãs de admin usam
///    `_busyId == row.id`, que é ainda melhor — trava só a linha tocada.
///  - `store.busy && _local` — o "e" faz o guarda local mandar; o global
///    sozinho não mata o botão.
void main() {
  // Alimentadores de botão: se um destes receber um `busy` de store, o botão
  // pode nascer morto.
  const alvos = ['loading', 'onPressed', 'onTap', 'enabled', 'busy'];

  // O receptor é um store? (`store.busy`, `context.watch<X>().busy`,
  // `tvdeStore.busy`, `read<OrderStore>().busy`…)
  final receptorGlobal = RegExp(r'\b(?:[A-Za-z_]*[Ss]tore|context\.(?:watch|read)\s*<[^>]+>\s*\(\s*\))\s*\.busy\b');

  final excepcoes = <String, String>{
    // Formato: 'caminho:linha' -> porquê é legítimo.
    'lib/screens/driver/tvde/tvde_offer_screen.dart':
        'usa `store.busy && _acting`: o "e" faz o guarda LOCAL mandar. O '
            'global sozinho não desliga o botão. Padrão correcto, e foi este '
            'ecrã que pagou a cicatriz pela primeira vez.',
  };

  test('nenhum botão novo fica travado por um `busy` global de store', () {
    final infractores = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final caminho = f.path.replaceAll(r'\', '/');
      if (excepcoes.containsKey(caminho)) continue;

      final linhas = f.readAsStringSync().split('\n');
      for (var i = 0; i < linhas.length; i++) {
        final linha = linhas[i];
        final temAlvo = alvos.any((a) => linha.contains('$a:'));
        if (!temAlvo) continue;
        // O `dart format` parte estas expressões em várias linhas — o
        // `onPressed:` fica numa e o `store.busy ? null : …` na seguinte.
        // Sem esta janela o guarda tinha um buraco por onde já passavam
        // dois botões reais do ecrã da profissional de limpeza.
        final janela =
            linhas.sublist(i, (i + 3).clamp(0, linhas.length)).join(' ');
        if (!receptorGlobal.hasMatch(janela)) continue;
        // `&& _algumaCoisa` = há um guarda local a mandar. Aceite.
        if (RegExp(r'&&\s*_\w').hasMatch(janela)) continue;
        infractores.add('$caminho:${i + 1}  ${linha.trim()}');
      }
    }

    expect(
      infractores,
      isEmpty,
      reason: 'PADRAO_BORA.md 3.13 — um botão trava-se pelo SEU pedido, nunca '
          'por um estado global de ocupado.\n'
          'Estes ${infractores.length} sítios ligam um alimentador de botão ao '
          '`busy` de um store. Basta outra operação do store estar a meio para '
          'o botão nascer desligado — foi assim que um passageiro real ficou '
          'preso no ecrã de avaliação a 05/09/2026.\n'
          'Usa um estado LOCAL do próprio State (`bool _enviando`), reposto no '
          'fim e também em erro, com guarda de re-entrada.\n\n'
          '${infractores.join('\n')}',
    );
  });

  test('a lista de excepções continua a apontar a código que existe', () {
    // Uma excepção que aponta a um ficheiro apagado é uma excepção esquecida —
    // e uma excepção esquecida é um buraco por onde a regra volta a fugir.
    for (final caminho in excepcoes.keys) {
      expect(File(caminho).existsSync(), isTrue,
          reason: 'a excepção "$caminho" já não existe: apaga-a do teste');
    }
  });

  test('as excepções ainda são mesmo excepções', () {
    // Se o ficheiro deixou de ter o padrão que justificava a excepção, a
    // excepção deixa de fazer sentido e tem de sair — senão fica a tapar
    // problemas futuros nesse ficheiro.
    for (final entrada in excepcoes.entries) {
      final txt = File(entrada.key).readAsStringSync();
      expect(receptorGlobal.hasMatch(txt), isTrue,
          reason: 'a excepção "${entrada.key}" já não é precisa (o ficheiro '
              'deixou de usar um `busy` de store): apaga-a do teste');
    }
  });

  test('o guarda apanha mesmo o padrão errado (auto-verificação)', () {
    // Um teste-guarda que não apanha nada é um teste que dorme. Isto prova
    // que a expressão reconhece as formas reais que já apareceram no repo.
    const maus = [
      'loading: store.busy,',
      'onPressed: store.busy ? null : _submit,',
      'busy: context.watch<TvdeDriverStore>().busy,',
      'onPressed: cartStore.busy ? null : _pagar,',
      'enabled: !orderStore.busy,',
    ];
    for (final m in maus) {
      expect(receptorGlobal.hasMatch(m), isTrue, reason: 'não apanhou: $m');
    }

    const bons = [
      'loading: _sending,',
      'busy: _busy,',
      'busy: _busyId == rows[i]["id"].toString(),',
      'onPressed: _enviando ? null : _submit,',
      'busy: _busy.contains(items[i].id),',
      'loading: store.busy && _acting,', // o "e" protege
    ];
    for (final b in bons) {
      final apanhado = receptorGlobal.hasMatch(b) &&
          !RegExp(r'&&\s*_\w').hasMatch(b);
      expect(apanhado, isFalse, reason: 'falso positivo em: $b');
    }
  });
}
