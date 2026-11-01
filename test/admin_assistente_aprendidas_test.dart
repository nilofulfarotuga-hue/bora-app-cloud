// Painel /admin/assistente, separador "Aprendidas" (missão app-fechar
// 01/11/2026, B6): lista `assistant_learned` e desliga uma linha. Sem rede: o
// servidor é trocado por uma porta de mentira e os textos são inventados.
import 'package:bora_app/screens/admin/admin_assistente_aprendidas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ApiFalsa implements AprendidasApi {
  _ApiFalsa(this.linhas);
  List<Map<String, dynamic>> linhas;
  final List<String> chamadas = [];

  @override
  Future<List<AssistenteAprendida>> listar() async =>
      linhas.map(AssistenteAprendida.fromMap).toList();

  @override
  Future<void> definirAtiva(String id, bool ativa) async {
    chamadas.add('ativa:$id=$ativa');
  }
}

final _linhas = <Map<String, dynamic>>[
  {
    'id': 'a1',
    'kind': 'licao',
    'question': 'Cliente pediu pão e mostrei pão ralado',
    'answer': 'Pão sem mais nada é pão fresco, não pão ralado.',
    'source': 'cliente',
    'active': true,
    'hits': 1,
    // 15:00 UTC no fim de outubro (inverno) = 15:00 em Lisboa.
    'created_at': '2026-10-29T15:00:00Z',
    'updated_at': '2026-10-29T15:00:00Z',
  },
  {
    'id': 'b2',
    'kind': 'resposta',
    'question': 'Como funciona o Favor?',
    'answer': 'Um estafeta vai buscar o que precisas a qualquer loja.',
    'source': 'manual',
    'active': false,
    'hits': 3,
    'created_at': '2026-07-31T14:00:00Z',
    'updated_at': '2026-07-31T14:00:00Z',
  },
];

void main() {
  testWidgets('lista o que aprendeu: tipo, data de Lisboa e estado', (t) async {
    final api = _ApiFalsa(_linhas);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: AdminAssistenteAprendidasTab(api: api))));
    await t.pumpAndSettle();
    expect(
        find.text('O que o assistente aprendeu (2, 1 ativas)'), findsOneWidget);
    expect(find.text('Cliente pediu pão e mostrei pão ralado'), findsOneWidget);
    expect(find.textContaining('Lição · aprendida em 29/10 15:00'),
        findsOneWidget);
    expect(find.textContaining('· ativa'), findsOneWidget);
    expect(find.text('Como funciona o Favor?'), findsOneWidget);
    expect(
        find.textContaining(
            'Resposta do manual · aprendida em 31/07 15:00 · usada 3x · desligada'),
        findsOneWidget);
    expect(t.widget<Switch>(find.byKey(const Key('aprendida-switch-a1'))).value,
        isTrue);
    expect(t.widget<Switch>(find.byKey(const Key('aprendida-switch-b2'))).value,
        isFalse);
  });

  testWidgets('o interruptor desliga só aquela linha e mostra o novo estado',
      (t) async {
    final api = _ApiFalsa(_linhas);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: AdminAssistenteAprendidasTab(api: api))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('aprendida-switch-a1')));
    await t.pumpAndSettle();
    expect(api.chamadas, ['ativa:a1=false']);
    expect(t.widget<Switch>(find.byKey(const Key('aprendida-switch-a1'))).value,
        isFalse);
    expect(find.text('Desligada: o assistente deixa de usar isto.'),
        findsOneWidget);
    expect(
        find.text('O que o assistente aprendeu (2, 0 ativas)'), findsOneWidget);
  });

  testWidgets('sem nada aprendido diz isso', (t) async {
    await t.pumpWidget(MaterialApp(
        home:
            Scaffold(body: AdminAssistenteAprendidasTab(api: _ApiFalsa([])))));
    await t.pumpAndSettle();
    expect(find.text('O assistente ainda não aprendeu nada.'), findsOneWidget);
  });

  test('lê a linha da tabela mesmo com tipos soltos', () {
    final a = AssistenteAprendida.fromMap({
      'id': 7,
      'kind': 'licao',
      'question': 'q',
      'answer': 'r',
      'active': 'false',
      'hits': '4',
    });
    expect(a.id, '7');
    expect(a.eLicao, isTrue);
    expect(a.active, isFalse);
    expect(a.hits, 4);
  });
}
