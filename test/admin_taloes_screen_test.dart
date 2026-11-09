// Página "Talões" do painel (08/11/2026, missão m1-dinheiro-favores, adendo 1):
// filtros de mês (Lisboa), loja e entregador chegam ao servidor; o botão do
// ZIP leva os mesmos filtros e abre o link; contadores; pedidos sem talão.
import 'package:bora_app/screens/admin/admin_taloes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 08/11/2026 12:00 UTC = 12:00 em Lisboa (inverno).
DateTime _agora() => DateTime.utc(2026, 11, 8, 12);

Map<String, dynamic> _foto(String pedido, int cents, {String recebida = '2026-11-08T19:05:00Z'}) => {
      'order_id': pedido,
      'path': '2026/11/$pedido/f1.jpg',
      'bucket': 'receipts',
      'total_cents': cents,
      'recebida_em': recebida,
      'origem': 'upload-receipt',
      'copia_em': null,
      'loja': 'Continente Guarda',
      'restaurant_id': 'continente-guarda',
      'service_type': 'storeShopping',
      'payment_method': 'cash',
      'driver_uid': 'u-ana',
      'estafeta': 'Ana Estafeta',
      'nif': {'nif': '519686233', 'origem': 'bora'},
    };

void main() {
  group('funções puras', () {
    test('últimos 24 meses de Lisboa, do atual para trás', () {
      final m = AdminTaloesScreen.ultimosMeses(_agora());
      expect(m.length, 24);
      expect(m.first, '2026-11');
      expect(m[1], '2026-10');
      expect(m[10], '2026-01');
      expect(m[11], '2025-12');
      expect(m.last, '2024-12');
      // 31/12 às 23:30 UTC já é 1 de janeiro? Não: Lisboa no inverno = UTC.
      expect(AdminTaloesScreen.ultimosMeses(DateTime.utc(2026, 12, 31, 23, 30)).first, '2026-12');
      // 31/05 às 23:30 UTC = 01/06 00:30 em Lisboa (verão).
      expect(AdminTaloesScreen.ultimosMeses(DateTime.utc(2026, 5, 31, 23, 30)).first, '2026-06');
    });

    test('nome do mês e tamanho', () {
      expect(AdminTaloesScreen.nomeDoMes('2026-11'), 'Novembro de 2026');
      expect(AdminTaloesScreen.nomeDoMes('2026-03'), 'Março de 2026');
      expect(AdminTaloesScreen.tamanhoLegivel(19084083), '18,2 MB');
      expect(AdminTaloesScreen.tamanhoLegivel(655360), '640 KB');
    });

    test('filtros para o servidor e para o ZIP', () {
      const f = FiltroTaloes(mes: '2026-11', loja: 'continente', driverUid: 'u-ana');
      expect(f.paraRpc(), {'p_mes': '2026-11', 'p_loja': 'continente', 'p_driver_uid': 'u-ana', 'p_limite': 500});
      expect(f.paraZip(), {'mes': '2026-11', 'loja': 'continente', 'driver_uid': 'u-ana'});
      expect(const FiltroTaloes(mes: '2026-11').paraZip(), {'mes': '2026-11'});
    });

    test('mensagens do ZIP', () {
      expect(
          AdminTaloesScreen.mensagemZip(
              {'ok': true, 'fotos': 124, 'bytes': 19084083, 'faltaram': [], 'url': 'https://x/z.zip'}),
          startsWith('124 fotos, 18,2 MB'));
      expect(
          AdminTaloesScreen.mensagemZip(
              {'ok': true, 'fotos': 3, 'bytes': 655360, 'faltaram': ['a.jpg'], 'url': 'https://x/z.zip'}),
          contains('1 foto não foi encontrada'));
      expect(AdminTaloesScreen.mensagemZip({'ok': false, 'error': 'demasiadas_fotos', 'max': 1500}),
          contains('1500'));
      expect(AdminTaloesScreen.mensagemZip({'ok': false, 'error': 'funcao_nao_publicada'}),
          contains(kTaloesFuncaoNaoPublicada));
      expect(AdminTaloesScreen.mensagemZip({'ok': false, 'error': 'so_admin'}), contains('administradores'));
    });
  });

  group('tela', () {
    late List<FiltroTaloes> listados;
    late List<FiltroTaloes> zips;
    late List<Uri> abertos;
    late List<String?> semTalaoDesde;

    setUp(() {
      listados = [];
      zips = [];
      abertos = [];
      semTalaoDesde = [];
    });

    Widget tela({
      List<Map<String, dynamic>>? fotos,
      Object? erroListar,
      List<Map<String, dynamic>> semTalao = const [],
    }) =>
        MaterialApp(
          home: AdminTaloesScreen(
            agora: _agora,
            listar: (f) async {
              listados.add(f);
              final erro = erroListar;
              if (erro != null) throw erro;
              return {'ok': true, 'fotos': fotos ?? const []};
            },
            listarSemTalao: (desde) async {
              semTalaoDesde.add(desde);
              return semTalao;
            },
            carregarEntregadores: () async => [
              (uid: 'u-ana', nome: 'Ana Estafeta'),
              (uid: 'u-rui', nome: 'Rui Entregador'),
            ],
            gerarZip: (f) async {
              zips.add(f);
              return {
                'ok': true,
                'fotos': 124,
                'bytes': 19084083,
                'faltaram': <String>[],
                'url': 'https://exemplo.supabase.co/storage/v1/object/sign/receipts/zips/2026-10/t.zip?token=x',
              };
            },
            abrirLink: (u) async {
              abertos.add(u);
              return true;
            },
          ),
        );

    testWidgets('abre no mês atual de Lisboa; loja, entregador e mês vão para o servidor', (t) async {
      await t.pumpWidget(tela());
      await t.pumpAndSettle();
      expect(listados, [const FiltroTaloes(mes: '2026-11')]);
      expect(find.text('Novembro de 2026'), findsOneWidget);
      // "Pedidos sem talão": últimos 30 dias por defeito (data de Lisboa).
      expect(semTalaoDesde, ['2026-10-09']);

      await t.enterText(find.byKey(const Key('taloes_filtro_loja')), ' continente ');
      await t.tap(find.byKey(const Key('taloes_filtro_loja_aplicar')));
      await t.pumpAndSettle();
      expect(listados.last, const FiltroTaloes(mes: '2026-11', loja: 'continente'));

      await t.tap(find.byKey(const Key('taloes_filtro_entregador')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ana Estafeta').last);
      await t.pumpAndSettle();
      expect(listados.last, const FiltroTaloes(mes: '2026-11', loja: 'continente', driverUid: 'u-ana'));

      await t.tap(find.byKey(const Key('taloes_filtro_mes')));
      await t.pumpAndSettle();
      await t.tap(find.text('Outubro de 2026').last);
      await t.pumpAndSettle();
      expect(listados.last, const FiltroTaloes(mes: '2026-10', loja: 'continente', driverUid: 'u-ana'));
    });

    testWidgets('contadores: fotos, pedidos e soma dos valores (um por pedido)', (t) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(tela(fotos: [
        _foto('aaaaaaaa-1111', 2995, recebida: '2026-11-08T19:06:00Z'),
        _foto('aaaaaaaa-1111', 2995, recebida: '2026-11-08T19:05:00Z'),
        _foto('bbbbbbbb-2222', 1005),
      ]));
      await t.pumpAndSettle();
      expect(find.text('3 fotos · 2 pedidos · soma dos valores escritos: 40,00 €'), findsOneWidget);
      expect(find.byKey(const Key('talao_item_0')), findsOneWidget);
      // A lista é preguiçosa: o 3.º cartão pode estar fora do ecrã do teste.
      expect(find.textContaining('Pedido aaaaaaaa · Continente Guarda', skipOffstage: false),
          findsNWidgets(2));
      expect(find.text('Entregador: Ana Estafeta', skipOffstage: false), findsNWidgets(3));
    });

    testWidgets('o ZIP leva mês, loja e entregador e abre o link', (t) async {
      await t.pumpWidget(tela());
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('taloes_filtro_loja')), 'continente');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('taloes_filtro_entregador')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rui Entregador').last);
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('btn_taloes_zip')));
      await t.tap(find.byKey(const Key('btn_taloes_zip')));
      await t.pumpAndSettle();

      expect(zips, [const FiltroTaloes(mes: '2026-11', loja: 'continente', driverUid: 'u-rui')]);
      expect(abertos.single.toString(), contains('zips/2026-10/t.zip'));
      expect(find.byKey(const Key('taloes_zip_resultado')), findsOneWidget);
      expect(find.textContaining('124 fotos, 18,2 MB'), findsOneWidget);
      expect(find.byKey(const Key('btn_taloes_zip_link')), findsOneWidget);
    });

    testWidgets('servidor sem a função: mensagem gentil', (t) async {
      await t.pumpWidget(tela(erroListar: Exception('PGRST202 Could not find the function public.admin_taloes_listar')));
      await t.pumpAndSettle();
      expect(find.textContaining(kTaloesFuncaoNaoPublicada), findsOneWidget);
      expect(find.byKey(const Key('taloes_contadores')), findsNothing);
    });

    testWidgets('separador "Pedidos sem talão" lista e muda o período', (t) async {
      await t.pumpWidget(tela(semTalao: [
        {
          'order_id': 'cccccccc-3333',
          'delivered_at': '2026-11-07T20:00:00Z',
          'loja': 'Pingo Doce',
          'payment_method': 'cash',
          'foto': null,
        },
      ]));
      await t.pumpAndSettle();
      expect(find.text('Pedidos sem talão (1)'), findsOneWidget);
      await t.tap(find.text('Pedidos sem talão (1)'));
      await t.pumpAndSettle();
      expect(find.text('1 pedido entregue sem talão'), findsOneWidget);
      expect(find.textContaining('Pedido cccccccc · Pingo Doce'), findsOneWidget);

      await t.tap(find.byKey(const Key('sem_talao_sempre')));
      await t.pumpAndSettle();
      expect(semTalaoDesde.last, isNull);
    });
  });
}
