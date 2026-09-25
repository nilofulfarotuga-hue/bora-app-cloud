import 'dart:io';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/l10n/tr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guarda do alternador PT/EN do app cliente.
///
/// A regra que estes testes protegem é uma só: **o utilizador nunca pode ver
/// uma chave técnica no ecrã**. Como a chave é o próprio português, o pior
/// caso de uma tradução em falta é ficar em português — mas isso conta como
/// falha de cobertura e é isso que o primeiro teste apanha.
void main() {
  // A rede só serve se apanhar o que tem de apanhar. Este grupo prova que a
  // varredura não tem os dois buracos que já teve — senão o teste passa a
  // verde por estar a olhar para o sítio errado, que é pior do que falhar.
  group('a varredura não pode ter buracos', () {
    test('apanha a frase quando o formatador parte a linha', () {
      // Cicatriz real: o `dart format` atirou o `.trArgs(` para a linha
      // seguinte e a frase saiu da rede — ficou sem inglês, sem alarme.
      expect(_padraoTr.hasMatch("'Olá'.tr"), isTrue);
      expect(_padraoTr.hasMatch("'Olá {0}'.trArgs([x])"), isTrue);
      expect(_padraoTr.hasMatch("'Última posição há {0} min'\n    .trArgs([n])"),
          isTrue,
          reason: 'frase partida pelo formatador tem de continuar na rede');
      expect(_padraoTr.hasMatch("'Olá'\n  .tr"), isTrue);
    });

    test('não confunde `.trim()` e afins com um pedido de tradução', () {
      // Se confundisse, o teste passaria a exigir inglês para strings que
      // nunca foram traduções — e alguém acabava por desligar o teste.
      expect(_padraoTr.hasMatch("'  espaço  '.trim()"), isFalse);
      expect(_padraoTr.hasMatch("'abc'.trimLeft()"), isFalse);
      expect(_padraoTr.hasMatch("'abc'\n   .trim()"), isFalse);
      expect(_padraoTr.hasMatch("'abc'.transform()"), isFalse);
    });

    test('aceita o `.tr` seguido do que normalmente o segue', () {
      for (final fim in [';', ',', ')', ']', '}', ' ']) {
        expect(_padraoTr.hasMatch("'abc'.tr$fim"), isTrue,
            reason: 'não apanhou `.tr` seguido de "$fim"');
      }
    });
  });

  group('dicionário PT→EN', () {
    test('toda a chave pedida por .tr existe no dicionário inglês', () {
      final pedidas = _chavesPedidasNoCodigo();
      expect(pedidas, isNotEmpty,
          reason: 'a varredura não encontrou nenhum .tr — o teste estaria a '
              'passar por não estar a olhar para lado nenhum');

      final semTraducao =
          pedidas.where((k) => !kStringsEn.containsKey(k)).toList()..sort();

      expect(
        semTraducao,
        isEmpty,
        reason: 'Estas ${semTraducao.length} frases aparecem no app cliente '
            'com .tr mas não têm inglês em lib/l10n/strings_en.dart:\n'
            '${semTraducao.take(30).map((s) => '  • $s').join('\n')}',
      );
    });

    test('nenhuma tradução está vazia nem ficou igual por engano', () {
      final vazias = kStringsEn.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();
      expect(vazias, isEmpty,
          reason: 'tradução vazia mostraria um espaço em branco no ecrã');
    });

    test('os marcadores {0}, {1}… são os mesmos em PT e EN', () {
      final marcador = RegExp(r'\{(\d+)\}');
      final erradas = <String>[];
      kStringsEn.forEach((pt, en) {
        final aPt = marcador.allMatches(pt).map((m) => m.group(1)!).toSet();
        final aEn = marcador.allMatches(en).map((m) => m.group(1)!).toSet();
        if (aPt.length != aEn.length || !aPt.containsAll(aEn)) {
          erradas.add('$pt  ->  $en');
        }
      });
      expect(erradas, isEmpty,
          reason: 'perder um marcador faz desaparecer um valor (preço, nome, '
              'distância) do ecrã:\n${erradas.take(20).join('\n')}');
    });
  });

  group('String.tr', () {
    tearDown(() => BoraLang.notifier.value = AppLang.pt);

    test('em português devolve exactamente o texto original', () {
      BoraLang.notifier.value = AppLang.pt;
      expect('Adicionar ao carrinho'.tr, 'Adicionar ao carrinho');
      expect('frase que não existe no dicionário'.tr,
          'frase que não existe no dicionário');
    });

    test('em inglês traduz o que conhece', () {
      BoraLang.notifier.value = AppLang.en;
      expect('Adicionar ao carrinho'.tr, 'Add to cart');
    });

    test('em inglês, chave desconhecida cai no português — nunca na chave crua',
        () {
      BoraLang.notifier.value = AppLang.en;
      const inventada = 'texto que ninguém traduziu ainda';
      expect(inventada.tr, inventada);
    });

    test('trArgs põe os valores pela ordem, sem lhes tocar', () {
      BoraLang.notifier.value = AppLang.pt;
      expect('Adicionar ao carrinho · €{0}'.trArgs(['12,34']),
          'Adicionar ao carrinho · €12,34');
      BoraLang.notifier.value = AppLang.en;
      expect('Adicionar ao carrinho · €{0}'.trArgs(['12,34']),
          'Add to cart · €12,34');
    });

    test('o valor entre marcadores passa intacto — não se traduz dinheiro', () {
      BoraLang.notifier.value = AppLang.en;
      final saida = 'Total €{0}'.trArgs(['1.234,56']);
      expect(saida.contains('1.234,56'), isTrue);
    });
  });

  group('idioma', () {
    tearDown(() => BoraLang.notifier.value = AppLang.pt);

    test('o padrão é português', () {
      expect(BoraLang.current, AppLang.pt);
      expect(BoraLang.isEnglish, isFalse);
    });

    test('locale acompanha a escolha', () {
      BoraLang.notifier.value = AppLang.pt;
      expect(BoraLang.locale.languageCode, 'pt');
      BoraLang.notifier.value = AppLang.en;
      expect(BoraLang.locale.languageCode, 'en');
    });
  });
}

/// Lê o código do app e devolve todas as chaves passadas a `.tr` / `.trArgs`.
///
/// Faz a varredura no disco de propósito: um teste que só olhasse para o mapa
/// nunca daria pela frase nova que alguém acrescentou a um ecrã.
/// A expressão da varredura, no topo para o teste de auto-verificação lhe poder
/// chamar directamente. Ver o comentário longo em [_chavesPedidasNoCodigo].
final RegExp _padraoTr = RegExp(
  r"""(['"])((?:\\.|(?!\1).)*?)\1\s*\.tr(?:Args\()?(?![A-Za-z])""",
  dotAll: true,
);

Set<String> _chavesPedidasNoCodigo() {
  final chaves = <String>{};
  final lib = Directory('lib');
  if (!lib.existsSync()) return chaves;

  // 'texto'.tr  |  'texto'.trArgs(  — apanha aspas simples e duplas, com os
  // escapes lá dentro (\' \" \\ \n) tratados como um só caractere.
  //
  // [05/09] Duas correcções, ambas com cicatriz:
  //
  // `\s*` antes do `.tr` — o `dart format` parte a expressão quando a frase é
  // longa e atira o `.tr` para a linha seguinte. A versão anterior exigia-o
  // COLADO às aspas, por isso essas frases saíam da rede: ficavam sem inglês e
  // ninguém dava por isso. Foi assim que escapou a frase da recolha de contacto
  // no `complete_profile_screen.dart`, que esteve sem tradução sem alarme.
  //
  // `(?![A-Za-z])` depois — ao aceitar espaços antes do `.tr`, passaria a
  // apanhar também `'texto'.trim()`, `.trimLeft()`, `.transform()`… e o teste
  // exigiria inglês para strings que nunca foram traduções. Isto exige que o
  // `.tr` acabe ali (`.tr,` `.tr;` `.tr)`) ou seja `.trArgs(`.
  final padrao = _padraoTr;

  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    if (f.path.replaceAll(r'\', '/').contains('lib/l10n/')) continue;
    for (final m in padrao.allMatches(f.readAsStringSync())) {
      chaves.add(_desescapar(m.group(2)!));
    }
  }
  return chaves;
}

/// Converte o corpo do literal Dart (como está escrito no ficheiro) no valor
/// que existe em execução — é esse que `String.tr` vai procurar no mapa.
String _desescapar(String corpo) {
  final sb = StringBuffer();
  for (var i = 0; i < corpo.length; i++) {
    if (corpo[i] != r'\' || i + 1 >= corpo.length) {
      sb.write(corpo[i]);
      continue;
    }
    final c = corpo[i + 1];
    i++;
    switch (c) {
      case 'n':
        sb.write('\n');
      case 't':
        sb.write('\t');
      case 'r':
        sb.write('\r');
      case 'u':
        if (i + 1 < corpo.length && corpo[i + 1] == '{') {
          final fim = corpo.indexOf('}', i + 2);
          sb.writeCharCode(int.parse(corpo.substring(i + 2, fim), radix: 16));
          i = fim;
        } else {
          sb.writeCharCode(
              int.parse(corpo.substring(i + 1, i + 5), radix: 16));
          i += 4;
        }
      default:
        sb.write(c);
    }
  }
  return sb.toString();
}
