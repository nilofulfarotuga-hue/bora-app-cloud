import 'package:bora_app/screens/admin/admin_lembretes_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [final-app-2026-10-29 · 5.d] O ecrã "Lembretes" do painel: lista por dia,
/// filtros, criar, editar (texto, link, data), marcar como feito. Dados falsos,
/// nada vai à base. A tabela e a rotina das 9h30 estão provadas à parte
/// (supabase/migrations/20261029142732_lembretes_danilo_2026_10_29.sql).
class _FonteFalsa implements LembretesFonte {
  _FonteFalsa(this.itens);

  List<LembreteDono> itens;
  final criados = <Map<String, dynamic>>[];
  final atualizados = <int, Map<String, dynamic>>{};

  @override
  Future<List<LembreteDono>> listar() async => List.of(itens);

  @override
  Future<void> criar(Map<String, dynamic> campos) async {
    criados.add(campos);
    itens = [
      ...itens,
      LembreteDono(
        id: 100 + criados.length,
        texto: campos['texto'] as String,
        link: campos['link'] as String?,
        quando: DateTime.parse(campos['quando'] as String).toLocal(),
        urgente: campos['urgente'] == true,
      ),
    ];
  }

  @override
  Future<void> atualizar(int id, Map<String, dynamic> campos) async {
    atualizados[id] = campos;
    itens = [
      for (final l in itens)
        if (l.id != id)
          l
        else
          LembreteDono(
            id: l.id,
            texto: (campos['texto'] as String?) ?? l.texto,
            link: campos.containsKey('link') ? campos['link'] as String? : l.link,
            quando: campos['quando'] != null ? DateTime.parse(campos['quando'] as String).toLocal() : l.quando,
            enviadoEm: l.enviadoEm,
            feitoEm: campos.containsKey('feito_em')
                ? (campos['feito_em'] == null ? null : DateTime.parse(campos['feito_em'] as String))
                : l.feitoEm,
            urgente: campos['urgente'] == true || (campos['urgente'] == null && l.urgente),
          ),
    ];
  }
}

List<LembreteDono> _dados() => [
      LembreteDono(id: 1, texto: 'Aprovar os cartazes da Boom.', quando: DateTime(2026, 10, 29, 9, 30)),
      LembreteDono(
        id: 2,
        texto: 'Pagar o anuncio novo da Meta.',
        link: 'https://exemplo.test/pagar',
        quando: DateTime(2026, 11, 1, 9, 30),
      ),
      LembreteDono(
        id: 3,
        texto: 'Ir a Boom testar o robo.',
        quando: DateTime(2026, 11, 2, 9, 30),
        enviadoEm: DateTime(2026, 11, 2, 9, 31),
        urgente: true,
      ),
      LembreteDono(
        id: 4,
        texto: 'Coisa que ja foi feita.',
        quando: DateTime(2026, 10, 29, 9, 30),
        feitoEm: DateTime(2026, 10, 29, 12, 0),
      ),
    ];

Future<_FonteFalsa> _abrir(WidgetTester tester, {List<LembreteDono>? itens}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fonte = _FonteFalsa(itens ?? _dados());
  await tester.pumpWidget(MaterialApp(home: AdminLembretesScreen(fonte: fonte)));
  await tester.pumpAndSettle();
  return fonte;
}

void main() {
  testWidgets('lista por dia: cabeçalhos com a data e só os pendentes à partida', (tester) async {
    await _abrir(tester);
    expect(find.text('Lembretes'), findsOneWidget);
    expect(find.textContaining('qui 29/10'), findsOneWidget);
    expect(find.textContaining('dom 01/11'), findsOneWidget);
    expect(find.textContaining('seg 02/11'), findsOneWidget);
    expect(find.text('Aprovar os cartazes da Boom.'), findsOneWidget);
    expect(find.text('Pagar o anuncio novo da Meta.'), findsOneWidget);
    // o que já está feito não aparece no filtro "Pendentes"
    expect(find.text('Coisa que ja foi feita.'), findsNothing);
    // o link e o estado de envio aparecem na linha
    expect(find.textContaining('https://exemplo.test/pagar'), findsOneWidget);
    expect(find.textContaining('ainda não enviado'), findsWidgets);
    expect(find.textContaining('enviado 02/11 09:31'), findsOneWidget);
    // o urgente leva o ícone de aviso
    expect(find.byIcon(Icons.priority_high), findsOneWidget);
  });

  testWidgets('filtros: Feitos, Enviados e Todos', (tester) async {
    await _abrir(tester);

    await tester.tap(find.byKey(const Key('lembrete_filtro_feitos')));
    await tester.pumpAndSettle();
    expect(find.text('Coisa que ja foi feita.'), findsOneWidget);
    expect(find.text('Aprovar os cartazes da Boom.'), findsNothing);

    await tester.tap(find.byKey(const Key('lembrete_filtro_enviados')));
    await tester.pumpAndSettle();
    expect(find.text('Ir a Boom testar o robo.'), findsOneWidget);
    expect(find.text('Pagar o anuncio novo da Meta.'), findsNothing);

    await tester.tap(find.byKey(const Key('lembrete_filtro_todos')));
    await tester.pumpAndSettle();
    expect(find.text('Coisa que ja foi feita.'), findsOneWidget);
    expect(find.text('Pagar o anuncio novo da Meta.'), findsOneWidget);
    expect(find.text('Ir a Boom testar o robo.'), findsOneWidget);
  });

  testWidgets('marcar como feito grava feito_em e o item sai dos pendentes', (tester) async {
    final fonte = await _abrir(tester);
    await tester.tap(find.byKey(const Key('lembrete_feito_1')));
    await tester.pumpAndSettle();

    expect(fonte.atualizados.keys, contains(1));
    expect(fonte.atualizados[1]!['feito_em'], isA<String>());
    expect(find.text('Aprovar os cartazes da Boom.'), findsNothing);
    expect(find.text('Marcado como feito.'), findsOneWidget);

    // voltar a pendente: no filtro Feitos, desmarcar grava null
    await tester.tap(find.byKey(const Key('lembrete_filtro_feitos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lembrete_feito_1')));
    await tester.pumpAndSettle();
    expect(fonte.atualizados[1]!['feito_em'], isNull);
  });

  testWidgets('criar: texto vazio e link sem http são recusados; depois grava', (tester) async {
    final fonte = await _abrir(tester);
    await tester.tap(find.byKey(const Key('lembrete_novo')));
    await tester.pumpAndSettle();
    expect(find.text('Novo lembrete'), findsWidgets);

    await tester.tap(find.byKey(const Key('lembrete_salvar')));
    await tester.pumpAndSettle();
    expect(find.text('Escreva o texto do lembrete.'), findsOneWidget);
    expect(fonte.criados, isEmpty);

    await tester.enterText(find.byKey(const Key('lembrete_texto')), 'Ligar ao contabilista');
    await tester.enterText(find.byKey(const Key('lembrete_link')), 'sem-http.test');
    await tester.tap(find.byKey(const Key('lembrete_salvar')));
    await tester.pumpAndSettle();
    expect(find.text('O link tem de começar por http.'), findsOneWidget);
    expect(fonte.criados, isEmpty);

    await tester.enterText(find.byKey(const Key('lembrete_link')), 'https://exemplo.test/x');
    await tester.tap(find.byKey(const Key('lembrete_urgente')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lembrete_salvar')));
    await tester.pumpAndSettle();

    expect(fonte.criados, hasLength(1));
    expect(fonte.criados.single['texto'], 'Ligar ao contabilista');
    expect(fonte.criados.single['link'], 'https://exemplo.test/x');
    expect(fonte.criados.single['urgente'], isTrue);
    expect(DateTime.parse(fonte.criados.single['quando'] as String).isUtc, isTrue);
    expect(find.text('Lembrete criado.'), findsOneWidget);
    expect(find.text('Ligar ao contabilista'), findsOneWidget);
  });

  testWidgets('editar: o formulário traz o texto e o link; alterar grava no mesmo id', (tester) async {
    final fonte = await _abrir(tester);
    await tester.tap(find.byKey(const Key('lembrete_editar_2')));
    await tester.pumpAndSettle();
    expect(find.text('Editar lembrete'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pagar o anuncio novo da Meta.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'https://exemplo.test/pagar'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('lembrete_texto')), 'Pagar o anuncio da Meta (25 euros).');
    await tester.enterText(find.byKey(const Key('lembrete_link')), '');
    await tester.tap(find.byKey(const Key('lembrete_salvar')));
    await tester.pumpAndSettle();

    expect(fonte.atualizados.keys, contains(2));
    expect(fonte.atualizados[2]!['texto'], 'Pagar o anuncio da Meta (25 euros).');
    expect(fonte.atualizados[2]!['link'], isNull);
    expect(find.text('Lembrete atualizado.'), findsOneWidget);
    expect(find.text('Pagar o anuncio da Meta (25 euros).'), findsOneWidget);
    expect(find.textContaining('https://exemplo.test/pagar'), findsNothing);
  });

  testWidgets('editar a data: o botão da data abre o calendário e a nova data é gravada', (tester) async {
    final fonte = await _abrir(tester);
    await tester.tap(find.byKey(const Key('lembrete_editar_1')));
    await tester.pumpAndSettle();
    expect(find.text('29/10'), findsWidgets);

    await tester.tap(find.byKey(const Key('lembrete_data')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lembrete_salvar')));
    await tester.pumpAndSettle();

    final quando = DateTime.parse(fonte.atualizados[1]!['quando'] as String).toLocal();
    expect(quando.day, 30);
    expect(quando.month, 10);
    expect(quando.hour, 9);
    expect(quando.minute, 30);
  });

  testWidgets('erro ao ler mostra a mensagem e deixa tentar de novo', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: AdminLembretesScreen(fonte: _FonteQueFalha())));
    await tester.pumpAndSettle();
    expect(find.textContaining('sem ligação'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('lista vazia diz que não há lembretes', (tester) async {
    await _abrir(tester, itens: const []);
    expect(find.text('Nenhum lembrete aqui.'), findsOneWidget);
  });

  test('o ecrã está no painel (Operação) e a busca encontra-o por "lembrete" e "whatsapp"', () {
    final todos = adminMenuAllItems();
    for (final q in ['lembrete', 'whatsapp', 'tarefas']) {
      expect(todos.where((i) => i.matches(q)).map((i) => i.id), contains('operacao_lembretes'),
          reason: 'a busca por "$q" não encontrou o ecrã');
    }
  });

  test('LembreteDono.fromJson lê a linha da tabela, com link vazio = sem link', () {
    final l = LembreteDono.fromJson({
      'id': 7,
      'texto': 'x',
      'link': '  ',
      'quando': '2026-10-30T09:30:00+00:00',
      'enviado_em': null,
      'feito_em': '2026-10-30T10:00:00+00:00',
      'urgente': true,
      'origem': 'claude-code',
    });
    expect(l.id, 7);
    expect(l.link, isNull);
    expect(l.feitoEm, isNotNull);
    expect(l.enviadoEm, isNull);
    expect(l.urgente, isTrue);
    expect(l.origem, 'claude-code');
  });
}

class _FonteQueFalha implements LembretesFonte {
  @override
  Future<List<LembreteDono>> listar() async => throw Exception('sem ligação');

  @override
  Future<void> criar(Map<String, dynamic> campos) async {}

  @override
  Future<void> atualizar(int id, Map<String, dynamic> campos) async {}
}
