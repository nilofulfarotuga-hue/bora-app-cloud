// Missão fechar-tudo-15-11 (ajudante B, 15/11/2026).
//
// Duas coisas que esta prova guarda, só a ler o código (sem widgets):
// 1. Os textos das apps cliente, estafeta e parceiro ficam em PT-PT: nenhuma
//    palavra de PT-BR dentro de aspas em lib/screens e lib/widgets. O painel
//    admin é PT-BR por regra da casa e fica de fora da varredura.
// 2. Os achados graves da varredura 9166 continuam fechados: partilha sem
//    origem (iPad e iPhone com iOS 26), botão Cancelar que o servidor recusa e
//    diálogo do código de entrega a escrever depois de fechado.
import 'dart:io';

import 'package:bora_app/l10n/strings_en.dart';
import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

/// Ficheiros das apps: lib/screens e lib/widgets sem o painel admin
/// (pasta `admin/` e ficheiros com "admin" no nome).
List<String> _ficheirosDasApps() {
  final out = <String>[];
  for (final raiz in const ['lib/screens', 'lib/widgets']) {
    for (final f in Directory(raiz).listSync(recursive: true)) {
      if (f is! File) continue;
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart')) continue;
      if (p.contains('/admin/')) continue;
      if (p.split('/').last.toLowerCase().contains('admin')) continue;
      out.add(p);
    }
  }
  out.sort();
  return out;
}

/// Conteúdo dos literais entre aspas de uma linha, ignorando o que está em
/// comentário `//`. Chega para apanhar o texto que a pessoa vê no ecrã.
List<String> _literais(String linha) {
  final out = <String>[];
  String? aspas;
  final atual = StringBuffer();
  for (var i = 0; i < linha.length; i++) {
    final c = linha[i];
    if (aspas != null) {
      if (c == r'\' && i + 1 < linha.length) {
        atual.write(linha[i + 1]);
        i++;
        continue;
      }
      if (c == aspas) {
        out.add(atual.toString());
        atual.clear();
        aspas = null;
        continue;
      }
      atual.write(c);
      continue;
    }
    if (c == "'" || c == '"') {
      aspas = c;
      continue;
    }
    if (c == '/' && i + 1 < linha.length && linha[i + 1] == '/') break;
  }
  return out;
}

/// Palavras de PT-BR que não podem aparecer em texto das apps (PT-PT diz
/// tu, telemóvel, utilizador, palavra-passe, ecrã, guardar, equipa).
final RegExp _ptBr = RegExp(
  r'(?<![A-Za-zÀ-ÿ])(você|vocês|celular|celulares|usuário|usuários|usuária|usuárias|usuario|usuarios|senha|senhas|tela|telas|salvar|equipe|equipes)(?![A-Za-zÀ-ÿ])',
  caseSensitive: false,
);

/// Exceções legítimas, cada uma com o motivo.
const Map<String, Set<String>> _excecoes = {
  // O mesmo editor serve o parceiro (PT-PT) e o painel admin (PT-BR):
  // `EditorDestaqueTextos.admin` tem "Salvar" de propósito.
  'lib/widgets/editor_destaque_loja.dart': {'salvar'},
  // É o próprio Portal das Finanças que chama "senha" à chave de acesso;
  // o texto repete o que a pessoa vê lá para não a confundir.
  'lib/screens/shared/comprovativo_atividade_screen.dart': {'senha'},
};

void main() {
  group('textos das apps em PT-PT (cliente, estafeta, parceiro)', () {
    test('nenhuma palavra de PT-BR dentro de aspas', () {
      final ficheiros = _ficheirosDasApps();
      expect(ficheiros.length, greaterThan(300),
          reason: 'a varredura tem de olhar para as apps todas');
      final achados = <String>[];
      var literaisVistos = 0;
      for (final caminho in ficheiros) {
        final linhas = _ler(caminho).split('\n');
        final permitidas = _excecoes[caminho] ?? const <String>{};
        for (var i = 0; i < linhas.length; i++) {
          final linha = linhas[i];
          if (linha.trimLeft().startsWith('//')) continue;
          if (linha.contains('debugPrint') || linha.contains('import ')) {
            continue;
          }
          for (final lit in _literais(linha)) {
            literaisVistos++;
            for (final m in _ptBr.allMatches(lit)) {
              final palavra = m.group(1)!.toLowerCase();
              if (permitidas.contains(palavra)) continue;
              achados.add('$caminho:${i + 1}  "$palavra" em: $lit');
            }
          }
        }
      }
      expect(literaisVistos, greaterThan(5000),
          reason: 'a varredura tem de ler texto a sério');
      expect(achados, isEmpty,
          reason: 'PT-BR nas apps (as apps são PT-PT; o admin é que é PT-BR):\n'
              '${achados.join('\n')}');
    });

    test('as exceções continuam a existir (senão a lista é lixo)', () {
      for (final e in _excecoes.entries) {
        final fonte = _ler(e.key).toLowerCase();
        for (final palavra in e.value) {
          expect(fonte, contains(palavra),
              reason: '${e.key} já não tem "$palavra": tirar da lista');
        }
      }
    });

    test('os textos corrigidos nesta missão ficaram em PT-PT', () {
      final ganhos = _ler('lib/screens/ganhos_screen.dart');
      expect(ganhos, contains('Podes levantar mais na próxima semana.'));
      expect(ganhos, isNot(contains('Podes sacar')));

      final login = _ler('lib/screens/login_screen.dart');
      expect(login, contains("'Conta criada com sucesso. Já pode entrar.'.tr"));
      expect(login, isNot(contains('Faça login')));

      final parceiroLogin = _ler('lib/screens/partner_login_screen.dart');
      expect(parceiroLogin, contains("'Indique o email do parceiro.'"));
      expect(parceiroLogin, contains("'Indique a palavra-passe.'"));
      expect(parceiroLogin, isNot(contains("'Informe ")));

      final registoParceiro = _ler('lib/screens/register_partner_screen.dart');
      expect(registoParceiro, contains("'Indique o telefone'"));
      expect(registoParceiro,
          contains('Ao submeter, a sua conta ficará pendente de análise'));
      expect(registoParceiro, isNot(contains("'Informe ")));

      final estafeta = _ler('lib/screens/driver_home_screen.dart');
      expect(estafeta, contains('"Entrega em curso"'));
      expect(estafeta, isNot(contains('Entrega em andamento')));
    });

    test('as chaves renomeadas têm inglês no dicionário e no JSON de origem',
        () {
      expect(kStringsEn['Conta criada com sucesso. Já pode entrar.'],
          'Account created successfully. Please sign in.');
      expect(kStringsEn.containsKey('Conta criada com sucesso. Faça login.'),
          isFalse);
      expect(kStringsEn['Indique a palavra-passe.'], 'Enter the password.');
      expect(kStringsEn.containsKey('Informe a palavra-passe.'), isFalse);

      final json01 = _ler('tool/l10n/traducoes/pt-en-01.json');
      expect(json01, contains('"Conta criada com sucesso. Já pode entrar."'));
      expect(json01, isNot(contains('Faça login')));
      final json03 = _ler('tool/l10n/traducoes/pt-en-03.json');
      expect(json03, contains('"Indique a palavra-passe."'));
      expect(json03, isNot(contains('"Informe a palavra-passe."')));
    });
  });

  group('varredura 9166 — achados graves continuam fechados', () {
    test('toda a partilha leva sharePositionOrigin (iPad e iPhone com iOS 26)',
        () {
      final chamadas = RegExp(
          r'Share\.share\(|Share\.shareXFiles\(|Share\.shareUri\(|SharePlus\.instance\.share\(');
      var vistas = 0;
      final semOrigem = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final linhas = _ler(f.path).split('\n');
        for (var i = 0; i < linhas.length; i++) {
          if (!chamadas.hasMatch(linhas[i])) continue;
          vistas++;
          final fim = (i + 6) > linhas.length ? linhas.length : i + 6;
          final janela = linhas.sublist(i, fim).join('\n');
          if (!janela.contains('sharePositionOrigin')) {
            semOrigem.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(vistas, greaterThanOrEqualTo(5),
          reason: 'a varredura não encontrou as partilhas');
      expect(semOrigem, isEmpty,
          reason: 'partilhas sem origem (rebentam no iPad/iOS 26):\n'
              '${semOrigem.join('\n')}');
      expect(_ler('lib/utils/origem_partilha.dart'),
          contains('Rect origemDaPartilha('));
    });

    test('o botão Cancelar só aparece nos estados que o servidor aceita', () {
      final ecra = _ler('lib/screens/order_tracking_screen.dart');
      final bloco = RegExp(r'estadosQueOServidorDeixaCancelar = \{([^}]*)\}')
          .firstMatch(ecra);
      expect(bloco, isNotNull);
      final noEcra = RegExp(r'OrderStatus\.(\w+)')
          .allMatches(bloco!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(ecra,
          contains('estadosQueOServidorDeixaCancelar.contains(widget.order.status)'));

      // O servidor é a fonte da verdade: `baseTier` em client-cancel-order.
      final servidor =
          _ler('supabase/functions/client-cancel-order/index.ts');
      final inicio = servidor.indexOf('function baseTier(');
      expect(inicio, greaterThan(0));
      final corpo = servidor.substring(inicio, servidor.indexOf('\n}', inicio));
      final noServidor = RegExp(r"case '(\w+)'")
          .allMatches(corpo)
          .map((m) => m.group(1)!)
          .toSet();
      expect(noServidor, isNotEmpty);
      expect(noEcra, equals(noServidor),
          reason: 'o ecrã mostra Cancelar num estado que o servidor recusa '
              '(cannot_cancel_at_status) ou esconde-o num que aceita');
    });

    test('o diálogo do código de entrega não escreve depois de fechado', () {
      final mapa = _ler('lib/screens/driver_map_screen.dart');
      final i = mapa.indexOf('final DeliveryPinResult r;');
      expect(i, greaterThan(0));
      final trecho =
          mapa.substring(i, i + 1200 > mapa.length ? mapa.length : i + 1200);
      expect(trecho, contains('try {'));
      expect(trecho, contains('catch (e)'));
      expect(trecho, contains('if (ctx.mounted)'));
      expect(trecho, contains('if (!ctx.mounted) return;'));

      final inicio = _ler('lib/screens/driver_home_screen.dart');
      final j = inicio.indexOf('final DeliveryPinResult r;');
      expect(j, greaterThan(0));
      final trecho2 = inicio.substring(
          j, j + 1200 > inicio.length ? inicio.length : j + 1200);
      expect(trecho2, contains('.timeout(kAcaoTimeout)'));
      expect(trecho2, contains('on TimeoutException'));
      expect(trecho2, contains('dialogContext.mounted'));

      // O store nunca deixa uma exceção subir ao diálogo: falha de rede vira
      // resultado e o estafeta tenta de novo.
      final store = _ler('lib/stores/order_store.dart');
      expect(store,
          contains("return const DeliveryPinResult(ok: false, error: 'network');"));
    });
  });
}
