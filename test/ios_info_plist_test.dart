// PORQUE ESTE TESTE EXISTE (2026-09-10).
//
// Num só dia a app iOS morreu por DUAS coisas que nenhum teste via, porque
// nenhuma delas é código Dart:
//
//   1. `Info.plist` pedia `$(GOOGLE_MAPS_API_KEY)` e essa definição de build
//      só era passada num `xcodebuild` do CI. O `flutter build ipa` nunca a
//      passava, a chave ficava vazia, e o SDK do Google Maps ABORTAVA o
//      processo ao criar o primeiro mapa. Foi para a Apple assim, três vezes.
//
//   2. `Info.plist` não declarava `NSFaceIDUsageDescription` e a app usa
//      `local_auth`. Desde o iOS 17 o sistema MATA a app por violação de
//      privacidade quando se pede biometria sem essa chave.
//
// Nenhuma das duas dá excepção Dart, nenhuma aparece no simulador do CI (que
// não tem biometria inscrita), e ambas só se veem num iPhone a sério. Isto
// apanha-as em segundos, antes de haver build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Chaves que a app PRECISA de declarar, e a razão de cada uma. Se um dia
/// deixarmos de usar a funcionalidade, tira-se daqui — não se enfraquece o
/// teste.
const Map<String, String> _obrigatorias = {
  'NSFaceIDUsageDescription': 'a app usa local_auth (Face ID / Touch ID)',
  'NSCameraUsageDescription': 'foto de perfil, de encomenda e de compras',
  'NSPhotoLibraryUsageDescription': 'escolher foto da galeria',
  'NSLocationWhenInUseUsageDescription': 'morada e mapa do cliente',
  'NSLocationAlwaysAndWhenInUseUsageDescription':
      'localização do estafeta em segundo plano',
};

String _valorDe(String plist, String chave) {
  final i = plist.indexOf('<key>$chave</key>');
  if (i < 0) return '';
  final a = plist.indexOf('<string>', i);
  final b = plist.indexOf('</string>', a);
  if (a < 0 || b < 0) return '';
  return plist.substring(a + '<string>'.length, b).trim();
}

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// MATRIZ PLUGIN -> O QUE O iOS EXIGE (ponto 3 da ordem do Danilo,
  /// 2026-09-10). Lida do pubspec: se um plugin destes entrar no projeto, a
  /// exigência entra sozinha; se o plugin sair, deixa de ser exigida. Cada
  /// linha diz o que o sistema faz quando falta — nenhuma é "aviso".
  const Map<String, List<String>> exigidasPorPlugin = {
    // Biometria: sem a chave o iOS MATA a app ao pedir Face ID (TCC).
    'local_auth': ['NSFaceIDUsageDescription'],
    // Câmara e galeria: sem a chave o iOS MATA a app ao abrir o selector.
    'image_picker': [
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
    ],
    // Localização: sem a chave o pedido de permissão nem aparece e o
    // estafeta fica sem GPS; com background precisa da "Always".
    'geolocator': [
      'NSLocationWhenInUseUsageDescription',
      'NSLocationAlwaysAndWhenInUseUsageDescription',
    ],
    // Mapa: precisa da chave do Google chegar ao binário (ver abaixo).
    'google_maps_flutter': ['GoogleMapsApiKey'],
    // Localização em segundo plano do estafeta.
    'flutter_foreground_task': ['UIBackgroundModes'],
    // Push: precisa do modo em fundo remote-notification.
    'firebase_messaging': ['UIBackgroundModes'],
  };

  bool usa(String plugin) =>
      RegExp('^\s+$plugin:', multiLine: true).hasMatch(pubspec);

  group('Info.plist do iOS', () {
    test('cada plugin nativo do pubspec tem o que o iOS exige', () {
      final faltam = <String>[];
      for (final e in exigidasPorPlugin.entries) {
        if (!usa(e.key)) continue;
        for (final chave in e.value) {
          if (!plist.contains('<key>$chave</key>')) {
            faltam.add('${e.key} precisa de $chave');
          }
        }
      }
      expect(faltam, isEmpty,
          reason: 'Plugins presentes sem a declaração que o iOS exige — o '
              'sistema MATA a app na primeira utilização: '
              '${faltam.join('; ')}');
    });

    test('os esquemas de URL que a app abre estão declarados', () {
      // `canLaunchUrl` devolve FALSO em silêncio para um esquema que não
      // esteja em LSApplicationQueriesSchemes — o botão "Ligar" não faz nada.
      final usados = <String>{};
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final m in RegExp(r"'(tel|mailto|whatsapp|sms):")
            .allMatches(f.readAsStringSync())) {
          usados.add(m.group(1)!);
        }
      }
      final semDeclarar = usados
          .where((s) => !plist.contains('<string>$s</string>'))
          .toList();
      expect(semDeclarar, isEmpty,
          reason: 'Esquemas lançados pela app mas ausentes de '
              'LSApplicationQueriesSchemes: ${semDeclarar.join(', ')}');
    });

    test('declara todas as permissões que a app usa', () {
      final faltam = <String>[];
      for (final e in _obrigatorias.entries) {
        if (!plist.contains('<key>${e.key}</key>')) {
          faltam.add('${e.key} (${e.value})');
        }
      }
      expect(faltam, isEmpty,
          reason: 'Sem estas chaves o iOS MATA a app quando a funcionalidade '
              'é usada. Faltam: ${faltam.join(', ')}');
    });

    test('nenhuma permissão declarada está vazia', () {
      for (final chave in _obrigatorias.keys) {
        expect(_valorDe(plist, chave), isNotEmpty,
            reason: '$chave está declarada mas sem texto. A Apple recusa, e '
                'o sistema trata-a como ausente.');
      }
    });

    test('toda a definição de build \$(VAR) tem quem a preencha', () {
      // Uma `$(VAR)` que ninguém define expande para string VAZIA, em
      // silêncio. Foi assim que a chave do Google Maps chegou vazia ao IPA.
      final usadas = RegExp(r'\$\(([A-Z0-9_]+)\)')
          .allMatches(plist)
          .map((m) => m.group(1)!)
          .toSet()
        // Estas vêm do próprio Xcode/Flutter, não somos nós que as definimos.
        ..removeAll({
          'DEVELOPMENT_LANGUAGE',
          'EXECUTABLE_NAME',
          'PRODUCT_BUNDLE_IDENTIFIER',
          'PRODUCT_NAME',
          'FLUTTER_BUILD_NAME',
          'FLUTTER_BUILD_NUMBER',
          'PRODUCT_MODULE_NAME',
        });

      final xcconfigs = [
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
      ].map((p) => File(p).readAsStringSync()).join('\n');

      final semDono = <String>[];
      for (final v in usadas) {
        // Ou está definida à cabeça, ou vem de um ficheiro incluído que o CI
        // escreve (o `#include?` é opcional de propósito).
        final temInclude = xcconfigs.contains('#include? "BoraSecrets.xcconfig"');
        final definidaAqui = xcconfigs.contains('$v=');
        if (!definidaAqui && !temInclude) semDono.add(v);
      }
      expect(semDono, isEmpty,
          reason: 'Estas definições são pedidas pelo Info.plist e ninguém as '
              'preenche — expandem para vazio sem avisar: '
              '${semDono.join(', ')}');
    });

    test('o Firebase tem o GoogleService-Info.plist DENTRO do projeto Xcode', () {
      // CICATRIZ (2026-09-10): o CI escrevia ios/Runner/GoogleService-Info.plist
      // a partir do segredo, mas o ficheiro nunca foi acrescentado ao alvo
      // Runner no project.pbxproj -- logo nunca ia para dentro do .app, o
      // Firebase nunca inicializava no iOS e nao havia push em iPhone nenhum.
      // Escrever o ficheiro nao chega: tem de estar REFERENCIADO no projeto.
      if (!usa('firebase_messaging') && !usa('firebase_core')) return;
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx.contains('GoogleService-Info.plist in Resources'), isTrue,
          reason: 'O plist do Firebase nao esta na fase Resources do alvo '
              'Runner: o Firebase nunca inicializa no iOS.');
    });

    test('o xcconfig do Release inclui o ficheiro de segredos do CI', () {
      // Sem este include, `flutter build ipa` produz um IPA sem a chave do
      // mapa — que foi exactamente o que aconteceu nas builds 51, 61 e 63.
      final release = File('ios/Flutter/Release.xcconfig').readAsStringSync();
      expect(release.contains('BoraSecrets.xcconfig'), isTrue,
          reason: 'O IPA de release fica sem as chaves que o Info.plist pede.');
    });
  });
}
