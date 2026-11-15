// ÁREA DO PARCEIRO (painel admin, 15/11/2026, missão painel-admin-15-11):
// o admin escolhe uma loja e faz por ela o que o parceiro faz na app dele,
// com motivo e auditoria. Testes sem rede: o servidor é um falso que regista
// cada chamada; relógio fixo.
import 'dart:io';

import 'package:bora_app/screens/admin/admin_area_parceiro_screen.dart';
import 'package:bora_app/screens/admin/admin_opcoes_produto_screen.dart'
    show AdminEscolherLoja;
import 'package:bora_app/services/admin_area_parceiro_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _lojaId = 'loja-teste';
const String _idNovo = 'aaaa1111-0000-0000-0000-000000000001';
const String _idChamando = 'bbbb2222-0000-0000-0000-000000000002';
const String _idACaminho = 'cccc3333-0000-0000-0000-000000000003';
const String _idPreparo = 'dddd4444-0000-0000-0000-000000000004';

/// 15/11/2026 12:00 UTC (inverno: igual à hora de Lisboa).
final DateTime _agora = DateTime.utc(2026, 11, 15, 12);

LojaAgora _loja({int ocupado = 0}) => LojaAgora(
      id: _lojaId,
      nome: 'Pizzaria Teste',
      parceira: true,
      aprovacao: 'approved',
      aberta: true,
      fechaEmMinutos: 90,
      ocupadoMinutos: ocupado,
      ocupadoAte: ocupado > 0 ? _agora.add(const Duration(hours: 1)) : null,
      retirada: true,
      reservas: true,
    );

List<PedidoDaLoja> _pedidos() => <PedidoDaLoja>[
      PedidoDaLoja(
        id: _idNovo,
        status: 'created',
        loja: 'Pizzaria Teste',
        cliente: 'Ana',
        total: 12.5,
        criadoEm: _agora.subtract(const Duration(minutes: 2)),
      ),
      PedidoDaLoja(
        id: _idChamando,
        status: 'callingDriver',
        loja: 'Pizzaria Teste',
        cliente: 'Rui',
        total: 20,
        criadoEm: _agora.subtract(const Duration(minutes: 10)),
      ),
      PedidoDaLoja(
        id: _idACaminho,
        status: 'onTheWay',
        loja: 'Pizzaria Teste',
        cliente: 'Eva',
        total: 8,
        entregadorId: 'user-entregador',
        criadoEm: _agora.subtract(const Duration(minutes: 30)),
      ),
      PedidoDaLoja(
        id: _idPreparo,
        status: 'preparing',
        loja: 'Pizzaria Teste',
        cliente: 'Zé',
        total: 15,
        criadoEm: _agora.subtract(const Duration(minutes: 5)),
      ),
    ];

const List<ProdutoDoMenu> _produtos = <ProdutoDoMenu>[
  ProdutoDoMenu(id: 'p1', nome: 'Pizza Margherita', preco: 9.5, categoria: 'Pizzas'),
  ProdutoDoMenu(
      id: 'p2', nome: 'Coca-Cola', preco: 2, disponivel: false, categoria: 'Bebidas'),
];

class _Falso extends AdminAreaParceiroService {
  _Falso({LojaAgora? loja}) : loja = loja ?? _loja();

  LojaAgora loja;
  final List<String> chamadas = <String>[];
  final List<Map<String, dynamic>> auditorias = <Map<String, dynamic>>[];

  @override
  Future<LojaAgora> lerLoja(String restaurantId) async {
    chamadas.add('lerLoja:$restaurantId');
    return loja;
  }

  @override
  Future<List<PedidoDaLoja>> pedidosAgora({required String nomeLoja}) async {
    chamadas.add('pedidos:$nomeLoja');
    return _pedidos();
  }

  @override
  Future<Map<String, int>> lojaRecebeCents(List<String> pedidoIds) async =>
      <String, int>{_idNovo: 1090};

  @override
  Future<Set<String>> encomendasPorTelefoneAbertas(String restaurantId) async =>
      <String>{_idPreparo};

  @override
  Future<List<ProdutoDoMenu>> menu(String restaurantId, {String? procurar}) async {
    chamadas.add('menu:$restaurantId:${procurar ?? ''}');
    return _produtos;
  }

  @override
  Future<DinheiroDaSemana> dinheiroDaSemana(String restaurantId) async {
    chamadas.add('dinheiro:$restaurantId');
    return DinheiroDaSemana(
      semanaLida: true,
      inicio: DateTime.utc(2026, 11, 9),
      fim: DateTime.utc(2026, 11, 15, 23),
      pedidos: 12,
      vendas: 240.5,
      parteBora: 36.08,
      ficaParaLoja: 204.42,
      saldo: 204.42,
      direcao: 'bora_pays_partner',
      extratoLido: true,
      linhas: const <LinhaDoExtrato>[
        LinhaDoExtrato(
          quando: '14/11 20:10',
          cliente: 'Ana',
          pagamento: 'cartão',
          clientePagouCents: 1450,
          parteBoraCents: 145,
          ficaCents: 1090,
        ),
      ],
      transferidoCents: 50000,
      semanasTransferidas: 3,
      porTransferirCents: 20442,
      semanasPorTransferir: 1,
    );
  }

  @override
  Future<ResumoReservas> reservas(String restaurantId,
      {required DateTime agora}) async {
    chamadas.add('reservas:$restaurantId');
    return const ResumoReservas(hoje: 2, proximas: 5, porDecidir: 1);
  }

  @override
  Future<List<AcaoDoAdmin>> historico(String restaurantId) async {
    chamadas.add('historico:$restaurantId');
    return <AcaoDoAdmin>[
      AcaoDoAdmin(
        acao: 'partner_status_override_set',
        quem: 'admin@bora.pt',
        quando: DateTime.utc(2026, 11, 15, 10),
        tipo: 'restaurant',
        entidade: _lojaId,
        detalhes: const <String, dynamic>{
          'forced_state': 'closed',
          'reason': 'falta de pessoal',
        },
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> forcarEstado(String restaurantId,
      {required bool abrir, required String motivo, DateTime? ate}) async {
    chamadas.add('forcar:$restaurantId:$abrir:$motivo');
    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> voltarAoHorario(String restaurantId) async {
    chamadas.add('voltarAoHorario:$restaurantId');
    return <String, dynamic>{'success': true, 'cleared_count': 1};
  }

  @override
  Future<Map<String, dynamic>> pausarLoja(String restaurantId, int minutos) async {
    chamadas.add('pausar:$restaurantId:$minutos');
    return <String, dynamic>{'ok': true, 'volta_as': '12:30'};
  }

  @override
  Future<Map<String, dynamic>> ligarModoOcupado(
      String restaurantId, int minutos) async {
    chamadas.add('ligarOcupado:$restaurantId:$minutos');
    return <String, dynamic>{'ok': true, 'extra_minutes': minutos, 'ate_as': '14:00'};
  }

  @override
  Future<Map<String, dynamic>> desligarModoOcupado(String restaurantId) async {
    chamadas.add('desligarOcupado:$restaurantId');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> definirDisponivel(String productId,
      {required bool disponivel, required String motivo}) async {
    chamadas.add('disponivel:$productId:$disponivel:$motivo');
    return <String, dynamic>{
      'success': true,
      'product_id': productId,
      'is_available': disponivel,
    };
  }

  @override
  Future<Map<String, dynamic>> chamarEntregadorJa(String pedidoId) async {
    chamadas.add('chamarJa:$pedidoId');
    return <String, dynamic>{'ok': true, 'chamado_as': '12:01'};
  }

  @override
  Future<Map<String, dynamic>> forcarChamada(String pedidoId) async {
    chamadas.add('forcarChamada:$pedidoId');
    return <String, dynamic>{'ok': true, 'nome': 'João'};
  }

  @override
  Future<Map<String, dynamic>> prometerHoraPronto(
      String pedidoId, DateTime? hora) async {
    chamadas.add('horaPronto:$pedidoId:${hora?.toIso8601String()}');
    return <String, dynamic>{'ok': true, 'pronto_as': '12:20'};
  }

  @override
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(
      String pedidoId, String motivo) async {
    chamadas.add('semCodigo:$pedidoId:$motivo');
    return <String, dynamic>{'ok': true, 'status_antes': 'onTheWay'};
  }

  @override
  Future<bool> registarAuditoria({
    required String acao,
    required String restaurantId,
    required Map<String, dynamic> detalhes,
  }) async {
    chamadas.add('auditoria:$acao:$restaurantId');
    auditorias.add(<String, dynamic>{'acao': acao, ...detalhes});
    return true;
  }
}

void _ecraGrande(WidgetTester t) {
  t.view.physicalSize = const Size(1280, 4600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<_Falso> _abrir(WidgetTester t, {_Falso? falso}) async {
  _ecraGrande(t);
  final f = falso ?? _Falso();
  await t.pumpWidget(MaterialApp(
    home: AdminAreaParceiroScreen(
      restaurantId: _lojaId,
      service: f,
      agora: () => _agora,
    ),
  ));
  await t.pumpAndSettle();
  return f;
}

Future<void> _tocar(WidgetTester t, Finder alvo) async {
  await t.ensureVisible(alvo);
  await t.pumpAndSettle();
  await t.tap(alvo);
  await t.pumpAndSettle();
}

Future<void> _escreverMotivoEConfirmar(WidgetTester t, String motivo) async {
  await t.enterText(find.byKey(const Key('area_motivo_campo')), motivo);
  await t.pump();
  await t.tap(find.byKey(const Key('area_motivo_confirmar')));
  await t.pumpAndSettle();
}

ButtonStyleButton _botao(WidgetTester t, String chave) =>
    t.widget<ButtonStyleButton>(find.byKey(Key(chave)));

void main() {
  group('regras puras', () {
    test('pedidos da loja: só os desta loja (pelo nome), mais recentes primeiro', () {
      final linhas = <Map<String, dynamic>>[
        {
          'id': 'o1',
          'status': 'preparing',
          'vendor_name': 'Pizzaria Teste',
          'created_at': '2026-11-15T10:00:00Z',
          'total': 10,
        },
        {
          'id': 'o2',
          'status': 'created',
          'vendor_name': '  pizzaria   TESTE ',
          'created_at': '2026-11-15T11:00:00Z',
          'total': '7.5',
          'is_test_order': true,
        },
        {
          'id': 'o3',
          'status': 'created',
          'vendor_name': 'Outra Loja',
          'created_at': '2026-11-15T11:30:00Z',
        },
        {'status': 'created', 'vendor_name': 'Pizzaria Teste'},
      ];
      final p = pedidosDaLoja(linhas, 'Pizzaria Teste');
      expect(p.map((e) => e.id).toList(), <String>['o2', 'o1']);
      expect(p.first.total, 7.5);
      expect(p.first.teste, isTrue);
      expect(p.last.temEntregador, isFalse);
      expect(pedidosDaLoja(linhas, '   '), isEmpty);
      expect(codigoCurtoPedido('abcd1234-ef00-0000-0000-000000000000'), '#ABCD1234');
    });

    test('a loja: lê as colunas e o estado; sem estado não confia no "aberta"', () {
      final l = LojaAgora.deMapas(
        <String, dynamic>{
          'id': 'x',
          'name': 'Loja X',
          'is_partner': true,
          'is_online': false,
          'approval_status': 'approved',
          'busy_extra_minutes': 20,
          'busy_until': '2026-11-15T13:00:00Z',
          'pausa_ate': '2026-11-15T12:30:00Z',
          'takeaway_enabled': true,
          'reservations_enabled': false,
        },
        <String, dynamic>{
          'is_open': true,
          'override_active': true,
          'override_reason': 'evento na praça',
          'closes_in_minutes': 45,
        },
      );
      expect(l.nome, 'Loja X');
      expect(l.parceira, isTrue);
      expect(l.online, isFalse);
      expect(l.aberta, isTrue);
      expect(l.forcada, isTrue);
      expect(l.motivoForcada, 'evento na praça');
      expect(l.fechaEmMinutos, 45);
      expect(l.ocupadaEm(_agora), isTrue);
      expect(l.ocupadaEm(DateTime.utc(2026, 11, 15, 14)), isFalse);
      expect(l.pausadaEm(_agora), isTrue);
      expect(l.retirada, isTrue);
      expect(l.reservas, isFalse);

      final semEstado = LojaAgora.deMapas(<String, dynamic>{'id': 'y'}, null);
      expect(semEstado.estadoLido, isFalse);
      expect(semEstado.nome, 'y');
      expect(semEstado.online, isTrue);
      expect(semEstado.aprovada, isTrue);
    });

    test('dinheiro: a semana em euros (fecho) e o extrato em cêntimos', () {
      final d = DinheiroDaSemana.deMapas(
        fecho: <String, dynamic>{
          'current_week': <String, dynamic>{
            'week_start': '2026-11-09T00:00:00Z',
            'week_end': '2026-11-15T23:59:59Z',
            'total_orders': 3,
            'gross_sales': '45.50',
            'commission_total': 6.83,
            'partner_share': 38.67,
            'net_balance': 38.67,
            'direction': 'bora_pays_partner',
          },
        },
        extrato: <String, dynamic>{
          'ok': true,
          'transferido': <String, dynamic>{'total_cents': 12000, 'semanas': 2},
          'por_transferir': <String, dynamic>{'total_cents': 3867, 'semanas': 1},
          'pedidos': <Map<String, dynamic>>[
            <String, dynamic>{
              'pedido_id': 'o1',
              'quando_txt': '14/11 20:10',
              'cliente': 'Ana',
              'fica_para_o_parceiro_cents': 1090,
            },
          ],
        },
      );
      expect(d.semanaLida, isTrue);
      expect(d.pedidos, 3);
      expect(d.vendas, 45.5);
      expect(d.ficaParaLoja, 38.67);
      expect(d.boraPagaALoja, isTrue);
      expect(d.lojaPagaABora, isFalse);
      expect(d.transferidoCents, 12000);
      expect(d.porTransferirCents, 3867);
      expect(d.linhas.single.ficaCents, 1090);
      expect(d.linhas.single.cliente, 'Ana');

      final vazio = DinheiroDaSemana.deMapas(fecho: <String, dynamic>{});
      expect(vazio.semanaLida, isFalse);
      expect(vazio.extratoLido, isFalse);
      expect(
          DinheiroDaSemana.deMapas(fecho: <String, dynamic>{
            'current_week': <String, dynamic>{'direction': 'partner_pays_bora'},
          }).lojaPagaABora,
          isTrue);
    });

    test('reservas: hoje, próximas e por decidir; canceladas não contam', () {
      final r = ResumoReservas.contar(<Map<String, dynamic>>[
        <String, dynamic>{'status': 'pending', 'reserved_for': '2026-11-15T20:00:00Z'},
        <String, dynamic>{'status': 'confirmed', 'reserved_for': '2026-11-15T09:00:00Z'},
        <String, dynamic>{'status': 'confirmed', 'reserved_for': '2026-11-17T20:00:00Z'},
        <String, dynamic>{'status': 'cancelled', 'reserved_for': '2026-11-15T21:00:00Z'},
      ], _agora);
      expect(r.hoje, 2);
      expect(r.proximas, 2);
      expect(r.porDecidir, 1);
    });

    test('o histórico em palavras do painel, com motivo e pedido', () {
      expect(
          rotuloAcaoNaLoja(const AcaoDoAdmin(
              acao: 'partner_status_override_set',
              detalhes: <String, dynamic>{'forced_state': 'open'})),
          'Forçou ABRIR a loja');
      expect(
          rotuloAcaoNaLoja(const AcaoDoAdmin(
              acao: 'product_deactivate',
              detalhes: <String, dynamic>{'product_name': 'Coca-Cola'})),
          'Marcou esgotado: Coca-Cola');
      expect(rotuloAcaoNaLoja(const AcaoDoAdmin(acao: AcoesAreaParceiro.pausar)),
          'Área do parceiro: Pausou a loja');
      expect(rotuloAcaoNaLoja(const AcaoDoAdmin(acao: 'coisa_nova')), 'coisa_nova');

      final a = AcaoDoAdmin(
        acao: AcoesAreaParceiro.chamarEntregadorJa,
        quem: 'admin@bora.pt',
        quando: DateTime.utc(2026, 11, 15, 10, 5),
        detalhes: const <String, dynamic>{
          'motivo': 'cliente ligou',
          'order_id': 'abcd1234-ef00-0000-0000-000000000000',
        },
      );
      expect(detalheAcaoNaLoja(a),
          '15/11 10:05 · admin@bora.pt · motivo: cliente ligou · pedido #ABCD1234');
    });

    test('respostas do servidor em palavras simples', () {
      expect(chamarJaEmPalavras(<String, dynamic>{'ok': true, 'chamado_as': '14:05'}),
          'Entregador chamado às 14:05.');
      expect(
          chamarJaEmPalavras(
              <String, dynamic>{'ok': false, 'motivo': 'nao_e_encomenda_por_telefone'}),
          contains('encomendas feitas por telefone'));
      expect(respostaLojaEmPalavras(<String, dynamic>{'ok': false, 'error': 'desligado'}),
          contains('modo ocupado está desligado'));
      expect(respostaLojaEmPalavras(<String, dynamic>{'ok': false, 'error': 'forbidden'}),
          'Sem permissão para agir nesta loja.');
      expect(estadoPedidoLojaPtBr('onTheWay'), 'A caminho do cliente');
      expect(aprovacaoLojaPtBr(null), 'aprovada');
      expect(aprovacaoLojaPtBr('pending'), 'por aprovar');
    });

    test('motivo mínimo de 3 letras', () {
      expect(motivoAreaParceiroOk(null), isFalse);
      expect(motivoAreaParceiroOk(' ab '), isFalse);
      expect(motivoAreaParceiroOk('abc'), isTrue);
    });
  });

  group('ecrã', () {
    testWidgets('as 6 secções aparecem, cada uma com a frase do que serve',
        (t) async {
      final f = await _abrir(t);
      for (final s in kAreaParceiroSecoes) {
        expect(find.byKey(Key('area_secao_${s.$1}')), findsOneWidget, reason: s.$1);
        expect(find.text(s.$2), findsOneWidget, reason: s.$2);
        expect(find.text(s.$3), findsOneWidget, reason: s.$3);
      }
      // 1 Loja agora
      expect(find.text('Pizzaria Teste'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('area_estado_loja'))).data,
          'ABERTA agora');
      // 2 Pedidos
      expect(find.textContaining('#AAAA1111'), findsOneWidget);
      expect(find.textContaining('a loja recebe 10,90 €'), findsOneWidget);
      // 3 Menu
      expect(find.text('Pizza Margherita'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('area_menu_estado_p2'))).data,
          'Esgotado');
      // 4 Dinheiro (só leitura)
      expect(t.widget<Text>(find.byKey(const Key('area_dinheiro_fica'))).data,
          '204,42 €');
      expect(find.byKey(const Key('area_dinheiro_so_leitura')), findsOneWidget);
      // 5 Reservas
      expect(find.text('Hoje: 2 · próximas: 5 · por decidir: 1'), findsOneWidget);
      // 6 Histórico
      expect(find.text('Forçou FECHAR a loja'), findsOneWidget);
      expect(find.textContaining('motivo: falta de pessoal'), findsOneWidget);

      expect(
          f.chamadas,
          containsAll(<String>[
            'lerLoja:$_lojaId',
            'pedidos:Pizzaria Teste',
            'menu:$_lojaId:',
            'dinheiro:$_lojaId',
            'reservas:$_lojaId',
            'historico:$_lojaId',
          ]));
    });

    testWidgets(
        'esgotar um produto pede motivo e chama o servidor com ele; sem auditoria '
        'a mais (o servidor já grava)', (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_menu_switch_p1')));
      expect(find.byKey(const Key('area_motivo_campo')), findsOneWidget);

      // Motivo curto: o confirmar fica desligado e nada vai ao servidor.
      await t.enterText(find.byKey(const Key('area_motivo_campo')), 'ab');
      await t.pump();
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull);
      expect(f.chamadas.where((c) => c.startsWith('disponivel:')), isEmpty);

      await _escreverMotivoEConfirmar(t, 'acabou a massa');
      expect(f.chamadas, contains('disponivel:p1:false:acabou a massa'));
      expect(f.auditorias, isEmpty,
          reason: 'admin_set_product_availability já grava o motivo e a loja');
      expect(t.widget<Text>(find.byKey(const Key('area_menu_estado_p1'))).data,
          'Esgotado');
    });

    testWidgets('voltar a deixar disponível também pede motivo', (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_menu_switch_p2')));
      await _escreverMotivoEConfirmar(t, 'chegou stock');
      expect(f.chamadas, contains('disponivel:p2:true:chegou stock'));
      expect(t.widget<Text>(find.byKey(const Key('area_menu_estado_p2'))).data,
          'Disponível');
    });

    testWidgets('desligar o modo ocupado: servidor e depois o motivo na auditoria',
        (t) async {
      final f = await _abrir(t, falso: _Falso(loja: _loja(ocupado: 20)));
      expect(find.byKey(const Key('area_loja_ocupada')), findsOneWidget);
      await _tocar(t, find.byKey(const Key('area_desligar_ocupado')));
      await _escreverMotivoEConfirmar(t, 'loja pediu por telefone');

      final iServidor = f.chamadas.indexOf('desligarOcupado:$_lojaId');
      final iAuditoria = f.chamadas
          .indexOf('auditoria:${AcoesAreaParceiro.desligarModoOcupado}:$_lojaId');
      expect(iServidor, greaterThanOrEqualTo(0));
      expect(iAuditoria, greaterThan(iServidor));
      expect(f.auditorias.single['motivo'], 'loja pediu por telefone');
      expect(f.auditorias.single['minutos_antes'], 20);
    });

    testWidgets('pausar a loja: escolhe o tempo, pede motivo e grava na auditoria',
        (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_pausar')));
      await t.tap(find.byKey(const Key('area_opcao_30')));
      await t.pump();
      await _escreverMotivoEConfirmar(t, 'falta de pessoal');

      expect(f.chamadas, contains('pausar:$_lojaId:30'));
      final a = f.auditorias.single;
      expect(a['acao'], AcoesAreaParceiro.pausar);
      expect(a['minutos'], 30);
      expect(a['motivo'], 'falta de pessoal');
    });

    testWidgets('chamar entregador já: só na encomenda por telefone em preparo',
        (t) async {
      final f = await _abrir(t);
      expect(find.byKey(const Key('area_chamar_ja_$_idNovo')), findsNothing);
      expect(find.byKey(const Key('area_forcar_chamada_$_idChamando')), findsOneWidget);
      expect(find.byKey(const Key('area_forcar_chamada_$_idNovo')), findsNothing);

      await _tocar(t, find.byKey(const Key('area_chamar_ja_$_idPreparo')));
      await _escreverMotivoEConfirmar(t, 'cliente ligou a pedir');
      expect(f.chamadas, contains('chamarJa:$_idPreparo'));
      expect(f.auditorias.single['acao'], AcoesAreaParceiro.chamarEntregadorJa);
      expect(f.auditorias.single['order_id'], _idPreparo);
      expect(f.auditorias.single['motivo'], 'cliente ligou a pedir');
    });

    testWidgets('"Marcar entregue sem código" passa pelo serviço e fica na loja',
        (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('btn_entregue_sem_codigo')));
      await t.enterText(find.byKey(const Key('motivo_sem_codigo')), 'cliente já recebeu');
      await t.tap(find.byKey(const Key('confirmar_sem_codigo')));
      await t.pumpAndSettle();

      expect(f.chamadas, contains('semCodigo:$_idACaminho:cliente já recebeu'));
      expect(f.auditorias.single['acao'], AcoesAreaParceiro.entregueSemCodigo);
      expect(f.auditorias.single['order_id'], _idACaminho);
    });

    testWidgets('o que o servidor ainda não deixa fazer fica desligado e diz porquê',
        (t) async {
      await _abrir(t);
      for (final chave in <String>[
        'area_pendente_aceitar_$_idNovo',
        'area_pendente_recusar_$_idNovo',
        'area_pendente_pronto_$_idPreparo',
        'area_pendente_falta_$_idPreparo',
        'area_pendente_reserva',
        'area_pendente_chegada',
      ]) {
        expect(find.byKey(Key(chave)), findsOneWidget, reason: chave);
        expect(_botao(t, chave).onPressed, isNull, reason: chave);
      }
      expect(find.text(kAreaParceiroFraseFuncaoNova), findsNWidgets(3),
          reason: 'o pedido novo, o pedido em preparo e as reservas');
      // O que já funciona fica ligado.
      expect(_botao(t, 'area_pausar').onPressed, isNotNull);
      expect(_botao(t, 'area_ligar_ocupado').onPressed, isNotNull);
      expect(_botao(t, 'area_forcar_fechar').onPressed, isNotNull);
      // Voltar ao horário só quando há abrir/fechar à força.
      expect(_botao(t, 'area_voltar_horario').onPressed, isNull);
    });

    testWidgets('sem loja: começa pela escolha da loja e não chama o servidor',
        (t) async {
      _ecraGrande(t);
      final f = _Falso();
      await t.pumpWidget(MaterialApp(
        home: AdminAreaParceiroScreen(service: f, agora: () => _agora),
      ));
      await t.pump();
      expect(find.text(kAreaParceiroEscolhaLoja), findsOneWidget);
      expect(find.byType(AdminEscolherLoja), findsOneWidget);
      expect(find.byKey(const Key('area_secao_loja')), findsNothing);
      expect(f.chamadas, isEmpty);
    });
  });

  group('regras do código', () {
    const ecra = 'lib/screens/admin/admin_area_parceiro_screen.dart';
    const servico = 'lib/services/admin_area_parceiro_service.dart';

    test('nada de ops_, escrita direta em tabelas, orders direto nem .tr', () {
      for (final caminho in <String>[ecra, servico]) {
        final src = File(caminho).readAsStringSync();
        expect(RegExp(r'\bops_\w+').hasMatch(src), isFalse,
            reason: '$caminho chama funções ops_ (são dos agentes)');
        expect(RegExp(r'''from\(\s*['"]orders['"]''').hasMatch(src), isFalse,
            reason: '$caminho mexe em orders direto (só pelas funções do servidor)');
        expect(RegExp(r'\.(update|insert|delete|upsert)\(').hasMatch(src), isFalse,
            reason: '$caminho escreve direto numa tabela');
        expect(RegExp(r'\.tr\b').hasMatch(src), isFalse,
            reason: '$caminho usa .tr (o painel é PT-BR fixo)');
      }
    });

    test('o ecrã não fala com o servidor: tudo passa pelo serviço', () {
      final src = File(ecra).readAsStringSync();
      expect(src.contains('.rpc('), isFalse);
      expect(src.contains('.from('), isFalse);
      expect(src.contains('Supabase.instance'), isFalse);
    });

    test('só as funções verificadas no servidor; nenhuma de preços nem pagamentos',
        () {
      final src = File(servico).readAsStringSync();
      final rpcs = RegExp(r"_rpc\(\s*'([a-z0-9_]+)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(rpcs, <String>{
        'is_partner_open',
        'admin_live_orders',
        'partner_loja_recebe',
        'admin_list_products_by_partner_v3',
        'partner_my_weekly_closeout',
        'extrato_parceiro',
        'admin_set_partner_override',
        'admin_clear_partner_override',
        'partner_pausar_loja',
        'partner_set_busy',
        'admin_partner_busy_desligar',
        'admin_set_product_availability',
        'admin_chamar_estafeta_ja',
        'admin_forcar_chamada',
        'partner_set_ready_at',
        'admin_marcar_entregue_sem_codigo',
        'log_admin_action',
      });
      for (final r in rpcs) {
        expect(
            RegExp('price|preco|pricing|payout|settlement|refund|wallet|token|pagar')
                .hasMatch(r),
            isFalse,
            reason: '$r mexe em preços ou dinheiro');
      }
      final tabelas = RegExp(r"\.from\(\s*'([a-z_]+)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(tabelas, <String>{
        'restaurants',
        'encomendas_telefone',
        'reservations',
        'admin_audit_log',
      });
      expect(src, contains("'p_action_type': acao"),
          reason: 'auditoria pela sobrecarga de texto (grava entity_id_text)');
      expect(src, contains("'p_reason': motivo.trim()"));
      expect('.timeout(kAreaParceiroLimite)'.allMatches(src).length,
          greaterThanOrEqualTo(6),
          reason: 'toda a chamada ao servidor tem tempo limite');
    });
  });
}
