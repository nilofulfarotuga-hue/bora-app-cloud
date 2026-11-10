import 'dart:io';

import 'package:bora_app/config/legal_identity.dart';
import 'package:bora_app/widgets/livro_reclamacoes_entrada.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, blocos E1 e E2b — Livro de Reclamações na
/// Ajuda e nas Definições das três apps, sem a plataforma ODR (fechou, Reg.
/// (UE) 2024/3228), e a sociedade como operadora.
void main() {
  Widget app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

  testWidgets('a entrada abre o Livro de Reclamações Eletrónico',
      (tester) async {
    final pedidos = <Uri>[];
    await tester.pumpWidget(app(LivroReclamacoesEntrada(
      abrirLigacao: (u) async {
        pedidos.add(u);
        return true;
      },
    )));
    expect(find.text(LivroReclamacoesEntrada.titulo), findsOneWidget);
    expect(find.byType(LivroReclamacoesSelo), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('livro-reclamacoes-entrada')));
    await tester.pump();
    expect(pedidos.single.host, 'www.livroreclamacoes.pt');
    expect(pedidos.single.scheme, 'https');
  });

  testWidgets('sem conseguir abrir, avisa em vez de rebentar', (tester) async {
    await tester.pumpWidget(app(LivroReclamacoesEntrada(
      cartao: true,
      abrirLigacao: (_) async => throw StateError('sem plugin'),
    )));
    await tester.tap(find.byKey(const ValueKey('livro-reclamacoes-entrada')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Não foi possível abrir'), findsOneWidget);
  });

  test('está nas Definições (perfil dos três papéis) e na Ajuda', () {
    final perfil = File('lib/screens/profile_screen.dart').readAsStringSync();
    expect(perfil, contains('const LivroReclamacoesEntrada()'));
    final ajuda = File('lib/widgets/bora_support_sheet.dart').readAsStringSync();
    expect(ajuda, contains('const LivroReclamacoesEntrada(cartao: true)'));
  });

  test('a plataforma ODR saiu da app e da página legal', () {
    for (final f in [
      'lib/config/legal_identity.dart',
      'lib/screens/legal_info_screen.dart',
      'docs/legal/informacao-legal.html',
    ]) {
      final s = File(f).readAsStringSync();
      expect(s, isNot(contains('ec.europa.eu/consumers/odr')), reason: f);
      expect(s, isNot(contains('odrUrl')), reason: f);
    }
  });

  test('a identidade é a da sociedade, com NIPC e sede', () {
    expect(LegalIdentity.nome, 'Danilo Fulfaro da Silva - Unipessoal Lda');
    expect(LegalIdentity.nipc, '519686233');
    expect(LegalIdentity.morada, startsWith('Rua do Torreão 14, 6300-610 Guarda'));
    final html = File('docs/legal/informacao-legal.html').readAsStringSync();
    expect(html, contains('<dt>NIPC</dt><dd>519686233</dd>'));
    expect(html, isNot(contains('322151171')));
    expect(html, isNot(contains('mpresário em nome individual')));
  });
}
