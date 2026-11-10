// M10 b2-nif (09/11/2026) — painel admin (PT-BR) do NIF no caixa:
//  - linha "NIF na caixa" na ficha do pedido (AdminFaturaNifSection.pedido);
//  - ecrã "NIF nas compras": 7/30 dias, "só os não dados" e CSV.
// Regra de 10/11/2026 (Danilo, fechada com o contabilista): só o NIF do CLIENTE
// vai no caixa; sem NIF do cliente o talão é consumidor final. O NIF da Bora
// saiu do sistema (o cartão e o editor dele saíram do ecrã).
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_nif_compras_screen.dart';
import 'package:bora_app/widgets/admin/admin_fatura_nif_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _linha(String id,
        {bool? dado, String? motivo, String tipo = 'cliente', String? cliente}) =>
    {
      'order_id': id,
      'criado_em': '2026-11-08T18:30:00Z',
      'loja': 'Auchan Guarda',
      'cliente': cliente,
      'estado': 'delivered',
      'tipo': tipo,
      'nif': tipo == 'cliente' ? '265148502' : '519686233',
      'dado': dado,
      'motivo': motivo,
      'confirmado_em': dado == null ? null : '2026-11-08T18:50:00Z',
    };

void main() {
  group('Linha "NIF na caixa" (ficha do pedido)', () {
    test('o texto diz o NIF, de quem é e o que o entregador respondeu', () {
      const t = AdminFaturaNifSection.textoNifNaCaixa;
      expect(
          t({
            'ok': true,
            'mostrar': true,
            'tipo': 'cliente',
            'nif': '265148502',
            'confirmado': {'dado': true},
          }),
          'NIF na caixa (o que o entregador deu no caixa): 265 148 502 — do cliente — dado ✓');
      expect(
          t({
            'ok': true,
            'mostrar': true,
            'tipo': 'cliente',
            'nif': '265148502',
            'confirmado': {'dado': false, 'motivo': 'A loja não aceitou'},
          }),
          'NIF na caixa (o que o entregador deu no caixa): 265 148 502 — do cliente — não dado: A loja não aceitou');
      // 10/11/2026: o NIF da Bora nunca vai no caixa — mesmo que um servidor
      // antigo o devolva, a linha não o mostra.
      expect(
          t({'ok': true, 'mostrar': true, 'tipo': 'bora', 'nif': '519686233'}),
          isNull);
      expect(
          t({'ok': true, 'mostrar': true, 'pediu_fatura': false, 'nif': '519686233'}),
          isNull);
      expect(t({'ok': true, 'mostrar': false, 'motivo': 'cliente_sem_nif'}),
          'NIF na caixa: o cliente não pediu fatura com NIF — talão consumidor final.');
      expect(t({'ok': true, 'mostrar': false, 'loja_parceira': true}),
          'NIF na caixa: não se aplica (loja parceira — quem emite a fatura é a loja).');
      expect(t({'ok': true, 'mostrar': false, 'motivo': 'favor_sem_compra'}), isNull);
      expect(t({'ok': false, 'error': 'nao_e_o_teu_pedido'}), isNull);
      expect(t(null), isNull);
    });

    Widget app(Widget s) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: s)));

    testWidgets('aparece por baixo do NIF da fatura', (t) async {
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async => null,
        guardar: (nif, nome) async {},
        carregarCaixa: () async => {
          'ok': true,
          'mostrar': true,
          'tipo': 'cliente',
          'nif': '265148502',
          'confirmado': {'dado': true},
        },
      )));
      await t.pumpAndSettle();
      expect(find.text('Sem NIF (consumidor final).'), findsOneWidget);
      expect(
          find.text(
              'NIF na caixa (o que o entregador deu no caixa): 265 148 502 — do cliente — dado ✓'),
          findsOneWidget);
      expect(find.textContaining('da Bora'), findsNothing);
    });

    testWidgets('função ainda fora do servidor: a linha não aparece e o resto funciona',
        (t) async {
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async => null,
        guardar: (nif, nome) async {},
        carregarCaixa: () async => throw Exception('PGRST202'),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_nif_caixa_linha')), findsNothing);
      expect(find.text('Sem NIF (consumidor final).'), findsOneWidget);
    });

    testWidgets('no cliente não há linha do caixa', (t) async {
      await t.pumpWidget(app(AdminFaturaNifSection.cliente(
        userId: 'u1',
        carregar: () async => null,
        guardar: (nif, nome) async {},
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_nif_caixa_linha')), findsNothing);
    });
  });

  group('Ecrã "NIF nas compras"', () {
    testWidgets('lista, resume, filtra "só os não dados" e troca para 30 dias',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final pedidos = <int>[];
      await t.pumpWidget(MaterialApp(
        home: AdminNifComprasScreen(
          listar: (dias) async {
            pedidos.add(dias);
            return [
              _linha('a1', dado: true),
              _linha('a2', dado: false, motivo: 'Esqueci-me', tipo: 'cliente'),
              _linha('a3'),
            ];
          },
        ),
      ));
      await t.pumpAndSettle();

      expect(pedidos, [7], reason: 'abre nos últimos 7 dias');
      expect(find.byKey(const Key('admin_nif_bora_cartao')), findsNothing,
          reason: 'o NIF da Bora saiu do sistema a 10/11');
      expect(
          find.text(
              '3 compras · 1 com NIF dado · 1 não dados · 1 sem resposta'),
          findsOneWidget);
      expect(find.text('NIF 265 148 502 (do cliente) — Dado ✓'), findsOneWidget);
      expect(find.text('NIF 265 148 502 (do cliente) — Não dado: Esqueci-me'),
          findsOneWidget);
      expect(find.text('NIF 265 148 502 (do cliente) — Ainda não confirmado'),
          findsOneWidget);

      await t.tap(find.byKey(const Key('admin_nif_so_nao_dados')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_nif_linha_a1')), findsNothing);
      expect(find.byKey(const Key('admin_nif_linha_a2')), findsOneWidget);
      expect(find.byKey(const Key('admin_nif_linha_a3')), findsOneWidget);

      await t.tap(find.byKey(const Key('admin_nif_dias_30')));
      await t.pumpAndSettle();
      expect(pedidos, [7, 30]);
      expect(find.byTooltip('Descarregar CSV'), findsOneWidget);
    });

    test('CSV: as colunas e a resposta em palavras', () {
      final l = NifCompraLinha.deMapa(
          _linha('a2', dado: false, motivo: 'Esqueci-me', tipo: 'cliente'));
      final csv = l.paraCsv();
      expect([for (final c in AdminNifComprasScreen.colunasCsv) c.$1],
          ['order_id', 'criado_em', 'loja', 'cliente', 'estado', 'tipo', 'nif', 'resposta', 'confirmado_em']);
      expect(csv['tipo'], 'do cliente');
      expect(csv['resposta'], 'Não dado: Esqueci-me');
      expect(l.problema, isTrue);
      expect(NifCompraLinha.deMapa(_linha('a1', dado: true)).problema, isFalse);
    });

    testWidgets('sem NIF da Bora: nem cartão nem editor, e a regra escrita',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: AdminNifComprasScreen(listar: (_) async => const []),
      ));
      await t.pumpAndSettle();
      expect(find.text('Nada nestes dias.'), findsOneWidget);
      expect(find.byKey(const Key('admin_nif_bora_cartao')), findsNothing);
      expect(find.byKey(const Key('admin_nif_bora_editar')), findsNothing);
      expect(find.textContaining('Sem NIF do cliente o talão é consumidor final'),
          findsOneWidget);
    });

    testWidgets('sem a migração no servidor: aviso claro', (t) async {
      await t.pumpWidget(MaterialApp(
        home: AdminNifComprasScreen(
          listar: (_) async =>
              throw Exception('PGRST202 Could not find the function'),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text(kNifComprasNaoPublicada), findsOneWidget);
    });
  });

  test('o ecrã está no menu do painel (Dinheiro → Mais)', () {
    AdminMenuItem? achado;
    void procurar(List<AdminMenuItem> itens) {
      for (final i in itens) {
        if (i.id == 'dinheiro_nif_nas_compras') achado = i;
        procurar(i.filhos);
      }
    }

    for (final s in adminMenuSections()) {
      procurar(s.items);
    }
    expect(achado, isNotNull);
    expect(achado!.title, 'NIF nas compras');
    expect(achado!.builder(), isA<AdminNifComprasScreen>());
    expect(achado!.matches('nif'), isTrue);
    expect(achado!.matches('consumidor final'), isTrue);
  });
}
