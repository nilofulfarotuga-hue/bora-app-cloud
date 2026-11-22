import 'package:bora_app/screens/admin/admin_autorizacoes_screen.dart';
import 'package:bora_app/stores/hermes_autorizacoes_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [hermes-diretor B10] Autorizações do Hermes no painel. Fonte falsa: sem rede, sem Supabase.
class _Fonte implements AutorizacoesFonte {
  _Fonte({this.linhas = const [], this.falha});

  final List<Map<String, dynamic>> linhas;
  final Object? falha;
  final decididas = <String>[];

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    if (falha != null) throw falha!;
    return linhas;
  }

  @override
  Future<Object?> decidir(int id, String decisao, String motivo) async {
    decididas.add('$id:$decisao');
    return {'ok': true, 'estado': decisao};
  }
}

final _agora = DateTime.utc(2026, 11, 22, 12, 0);

Map<String, dynamic> _pendente({int id = 12}) => {
      'id': id,
      'criada_em': '2026-11-22T11:50:00Z',
      'pedida_por': 'hermes',
      'acao': 'Devolver dinheiro a um cliente',
      'porque': 'O pedido chegou frio e o cliente pediu reembolso.',
      'valor_eur': 12.5,
      'operacao': {'op': 'rpc', 'nome': 'refund', 'args': {'pedido': 'abc'}},
      'estado': 'pendente',
      'expira_em': '2026-11-22T12:20:00Z',
      'teste': false,
    };

Map<String, dynamic> _usada({int id = 9}) => {
      'id': id,
      'criada_em': '2026-11-21T10:00:00Z',
      'acao': 'Apagar linhas de teste',
      'valor_eur': null,
      'operacao': {'op': 'delete'},
      'estado': 'usada',
      'expira_em': '2026-11-21T10:30:00Z',
      'decidida_em': '2026-11-21T10:05:00Z',
      'decidida_por': 'danilo',
      'via': 'telegram',
      'resultado': 'apagou 3 linhas',
      'teste': true,
    };

Future<void> _abrir(WidgetTester t, _Fonte f, {int? destacarId}) async {
  t.view.physicalSize = const Size(1200, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: AdminAutorizacoesScreen(
      store: AutorizacoesStore(fonte: f),
      relogio: false,
      agora: () => _agora,
      destacarId: destacarId,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('lista vazia: diz que não há pedidos à espera', (t) async {
    await _abrir(t, _Fonte());
    expect(find.textContaining('Nenhum pedido à espera'), findsOneWidget);
    expect(find.text('Autorizo'), findsNothing);
    expect(find.textContaining('Ainda não há pedidos decididos'), findsOneWidget);
  });

  testWidgets('com dados: pendente em cima com tempo e valor, histórico com etiqueta TESTE', (t) async {
    await _abrir(t, _Fonte(linhas: [_usada(), _pendente()]), destacarId: 12);
    expect(find.text('Devolver dinheiro a um cliente'), findsOneWidget);
    expect(find.text('Valor: 12,50 €'), findsOneWidget);
    expect(find.text('expira em 20 min'), findsOneWidget);
    expect(find.text('Autorizo'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.text('TESTE'), findsOneWidget);
    expect(find.text('Usada'), findsOneWidget);
    expect(find.textContaining('por danilo'), findsOneWidget);
    expect(find.textContaining('pelo Telegram'), findsOneWidget);
    expect(find.byKey(const ValueKey('autorizacao-12')), findsOneWidget);
  });

  testWidgets('ainda não ligado no servidor: faixa calma, sem erro vermelho', (t) async {
    await _abrir(t, _Fonte(falha: Exception('PGRST205: Could not find the table public.hermes_autorizacoes')));
    expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
    expect(find.textContaining('Não foi possível carregar'), findsNothing);
    expect(find.text('Autorizo'), findsNothing);
  });

  testWidgets('tocar em Autorizo e confirmar chama o store com o id certo', (t) async {
    final f = _Fonte(linhas: [_pendente(id: 12)]);
    await _abrir(t, f);
    await t.tap(find.text('Autorizo'));
    await t.pumpAndSettle();
    expect(find.text('Autorizar: Devolver dinheiro a um cliente — 12,50 €?'), findsOneWidget);
    expect(f.decididas, isEmpty, reason: 'só decide depois da confirmação');
    await t.tap(find.text('Sim, autorizar'));
    await t.pumpAndSettle();
    expect(f.decididas, ['12:autorizada']);
  });

  testWidgets('Recusar chama o store com recusada', (t) async {
    final f = _Fonte(linhas: [_pendente(id: 7)]);
    await _abrir(t, f);
    await t.tap(find.text('Recusar'));
    await t.pumpAndSettle();
    expect(f.decididas, ['7:recusada']);
  });
}
