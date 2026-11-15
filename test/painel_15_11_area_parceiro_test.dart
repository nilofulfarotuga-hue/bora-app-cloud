// ÁREA DO PARCEIRO (painel admin, 15/11/2026, missão painel-admin-15-11):
// o admin escolhe uma loja e faz por ela o que o parceiro faz na app dele,
// com motivo e auditoria. Testes sem rede: o servidor é um falso que regista
// cada chamada; relógio fixo.
//
// 15/11 (tarde): aceitar, recusar, marcar pronto, retirada no balcão, decidir
// reservas e "Cliente chegou" passam pelas funções admin_loja_* (lidas no
// servidor com pg_get_functiondef); a lista de pedidos vem de
// admin_pedidos_da_loja, com o caminho antigo só se ela falhar.
import 'dart:async';
import 'dart:io';

import 'package:bora_app/screens/admin/_admin_rpc_errors.dart'
    show humanizeAdminRpcError, kErroReservaPaga;
import 'package:bora_app/screens/admin/admin_area_parceiro_screen.dart';
import 'package:bora_app/screens/admin/admin_opcoes_produto_screen.dart'
    show AdminEscolherLoja;
import 'package:bora_app/services/admin_area_parceiro_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const String _lojaId = 'loja-teste';
const String _idNovo = 'aaaa1111-0000-0000-0000-000000000001';
const String _idChamando = 'bbbb2222-0000-0000-0000-000000000002';
const String _idACaminho = 'cccc3333-0000-0000-0000-000000000003';
const String _idPreparo = 'dddd4444-0000-0000-0000-000000000004';
const String _idRetiradaNova = 'abab0001-0000-0000-0000-000000000005';
const String _idRetiradaPreparo = 'acac0002-0000-0000-0000-000000000006';
const String _idRetiradaPronta = 'adad0003-0000-0000-0000-000000000007';
const String _rsvNova = 'eeee5555-0000-0000-0000-000000000008';
const String _rsvPaga = 'ffff6666-0000-0000-0000-000000000009';
const String _rsvHoje = '99997777-0000-0000-0000-000000000010';

/// O texto do servidor quando se recusa uma reserva paga.
const String _marcaReservaPaga = 'reserva_paga: recusar ainda nao devolve os 3 '
    'EUR; usa Cancelar reserva (devolve o dinheiro)';

/// 15/11/2026 12:00 UTC (inverno: igual à hora de Lisboa).
final DateTime _agora = DateTime.utc(2026, 11, 15, 12);

LojaAgora _loja({int ocupado = 0, int? minutosPadrao = 20}) => LojaAgora(
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
      minutosPreparoPadrao: minutosPadrao,
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
      PedidoDaLoja(
        id: _idRetiradaNova,
        status: 'created',
        tipoServico: 'takeaway',
        loja: 'Pizzaria Teste',
        cliente: 'Lia',
        total: 9,
        criadoEm: _agora.subtract(const Duration(minutes: 1)),
      ),
      PedidoDaLoja(
        id: _idRetiradaPreparo,
        status: 'preparing',
        tipoServico: 'takeaway',
        loja: 'Pizzaria Teste',
        cliente: 'Tó',
        total: 11,
        criadoEm: _agora.subtract(const Duration(minutes: 6)),
      ),
      PedidoDaLoja(
        id: _idRetiradaPronta,
        status: 'readyForPickup',
        tipoServico: 'takeaway',
        loja: 'Pizzaria Teste',
        cliente: 'Bia',
        total: 7,
        criadoEm: _agora.subtract(const Duration(minutes: 20)),
      ),
    ];

const List<ProdutoDoMenu> _produtos = <ProdutoDoMenu>[
  ProdutoDoMenu(id: 'p1', nome: 'Pizza Margherita', preco: 9.5, categoria: 'Pizzas'),
  ProdutoDoMenu(
      id: 'p2', nome: 'Coca-Cola', preco: 2, disponivel: false, categoria: 'Bebidas'),
];

List<ReservaDaLoja> _reservasDaLoja() => <ReservaDaLoja>[
      ReservaDaLoja(
        id: _rsvNova,
        status: 'pending',
        quando: _agora.add(const Duration(hours: 8)),
        pessoas: 4,
        cliente: 'Rita',
      ),
      ReservaDaLoja(
        id: _rsvPaga,
        status: 'pending',
        quando: _agora.add(const Duration(days: 1)),
        pessoas: 2,
        cliente: 'Hugo',
        pagoCents: 300,
      ),
      ReservaDaLoja(
        id: _rsvHoje,
        status: 'approved',
        quando: _agora.add(const Duration(hours: 1)),
        pessoas: 3,
        cliente: 'Íris',
        pagoCents: 300,
      ),
    ];

class _Falso extends AdminAreaParceiroService {
  _Falso({LojaAgora? loja}) : loja = loja ?? _loja();

  LojaAgora loja;
  final List<String> chamadas = <String>[];
  final List<Map<String, dynamic>> auditorias = <Map<String, dynamic>>[];

  /// A lista veio do caminho antigo (pelo nome da loja).
  bool pedidosPeloNome = false;

  /// Resposta de marcarPronto (para provar a resposta do servidor em palavras).
  Map<String, dynamic> respostaPronto = <String, dynamic>{
    'ok': true,
    'status': 'callingDriver',
    'admin': true,
  };

  /// Quando posto, aceitarPedido só responde quando o teste o completar.
  Completer<Map<String, dynamic>>? segurarAceitar;

  /// Quando posto, decidirReserva lança este erro (como o servidor).
  Object? erroReserva;

  @override
  Future<LojaAgora> lerLoja(String restaurantId) async {
    chamadas.add('lerLoja:$restaurantId');
    return loja;
  }

  @override
  Future<PedidosAgora> pedidosAgora(
      {required String restaurantId, required String nomeLoja}) async {
    chamadas.add('pedidos:$restaurantId:$nomeLoja');
    return PedidosAgora(_pedidos(), peloNome: pedidosPeloNome);
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
    return ResumoReservas(
        hoje: 2, proximas: 5, porDecidir: 1, lista: _reservasDaLoja());
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
  Future<Map<String, dynamic>> aceitarPedido(String pedidoId,
      {required int minutos, required String motivo}) async {
    chamadas.add('aceitar:$pedidoId:$minutos:$motivo');
    final segurar = segurarAceitar;
    if (segurar != null) return segurar.future;
    return <String, dynamic>{
      'ok': true,
      'status': 'preparing',
      'prep_time_minutes': minutos,
      'admin': true,
    };
  }

  @override
  Future<Map<String, dynamic>> recusarPedido(String pedidoId,
      {required String motivo}) async {
    chamadas.add('recusar:$pedidoId:$motivo');
    return <String, dynamic>{'ok': true, 'status': 'rejected', 'admin': true};
  }

  @override
  Future<Map<String, dynamic>> marcarPronto(String pedidoId,
      {required String motivo}) async {
    chamadas.add('pronto:$pedidoId:$motivo');
    return respostaPronto;
  }

  @override
  Future<Map<String, dynamic>> passoDaRetirada(String pedidoId,
      {required PassoRetirada passo, required String motivo, int? minutos}) async {
    chamadas.add('retirada:$pedidoId:${passo.name}:$minutos:$motivo');
    return <String, dynamic>{
      'ok': true,
      'order_id': pedidoId,
      'passo': passo.name,
      if (minutos != null) 'prep_minutes': minutos,
      if (passo == PassoRetirada.pronto) 'pickup_code': '4321',
      'admin': true,
    };
  }

  @override
  Future<Map<String, dynamic>> decidirReserva(String reservaId,
      {required bool aceitar, required String motivo}) async {
    chamadas.add('reserva:$reservaId:$aceitar:$motivo');
    final erro = erroReserva;
    if (erro != null) throw erro;
    return <String, dynamic>{
      'success': true,
      'status': aceitar ? 'approved' : 'rejected_refunded',
      'admin': true,
    };
  }

  @override
  Future<Map<String, dynamic>> marcarChegada(String reservaId,
      {required String motivo}) async {
    chamadas.add('chegada:$reservaId:$motivo');
    return <String, dynamic>{
      'success': true,
      'credit_cents': 200,
      'payout_cents': 200,
      'admin': true,
    };
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

/// Tira o aviso de baixo (SnackBar) antes da ação seguinte, para não tapar
/// nenhum botão.
Future<void> _tirarAviso(WidgetTester t) async {
  t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await t.pumpAndSettle();
}

ButtonStyleButton _botao(WidgetTester t, String chave) =>
    t.widget<ButtonStyleButton>(find.byKey(Key(chave)));

bool _marcada(WidgetTester t, int minutos) =>
    t.widget<ChoiceChip>(find.byKey(Key('area_opcao_$minutos'))).selected;

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

    test(
        'admin_pedidos_da_loja: lê a retirada pronta, a loja parceira, o '
        'pagamento e o agendamento', () {
      final lista = pedidosDasLinhas(<Map<String, dynamic>>[
        {
          'id': 'o1',
          'status': 'preparing',
          'service_type': 'restaurant',
          'created_at': '2026-11-15T10:00:00Z',
          'total': 12,
          'is_partner_store': true,
          'payment_method': 'cash',
          'payment_status': 'pending',
        },
        {
          'id': 'o2',
          'status': 'readyForPickup',
          'service_type': 'takeaway',
          'created_at': '2026-11-15T11:00:00Z',
          'total': '9.50',
          'is_partner_store': true,
          'payment_method': 'mbway',
          'payment_status': 'pending',
          'scheduled_for': '2026-11-15T20:00:00Z',
        },
        {'status': 'created'},
      ]);
      expect(lista.map((e) => e.id).toList(), <String>['o2', 'o1'],
          reason: 'mais recentes primeiro; sem id não entra');
      final retirada = lista.first;
      expect(retirada.retirada, isTrue);
      expect(retirada.total, 9.5);
      expect(retirada.lojaParceira, isTrue);
      expect(retirada.pagamentoPorConfirmar, isTrue);
      expect(retirada.agendadoPara, DateTime.utc(2026, 11, 15, 20));
      expect(lista.last.pagamentoPorConfirmar, isFalse,
          reason: 'dinheiro na entrega não espera pagamento');
      expect(PedidoDaLoja.doMapa(<String, dynamic>{'id': 'x'})?.lojaParceira, isNull,
          reason: 'sem a coluna, vale a loja');
      expect(
          PedidoDaLoja.doMapa(<String, dynamic>{
            'id': 'y',
            'payment_method': 'card',
            'payment_status': 'paid',
          })?.pagamentoPorConfirmar,
          isFalse);
    });

    test('só a ação válida para o estado do pedido', () {
      List<AcaoLojaPedido> acoes(String status,
              {String? tipo, bool? doPedido, bool daLoja = true}) =>
          acoesDaLojaNoPedido(
              PedidoDaLoja(
                  id: 'x', status: status, tipoServico: tipo, lojaParceira: doPedido),
              lojaParceira: daLoja);

      // Entrega de loja parceira.
      expect(acoes('created'),
          <AcaoLojaPedido>[AcaoLojaPedido.aceitar, AcaoLojaPedido.recusar]);
      expect(acoes('created', tipo: 'restaurant'),
          <AcaoLojaPedido>[AcaoLojaPedido.aceitar, AcaoLojaPedido.recusar]);
      expect(acoes('preparing'), <AcaoLojaPedido>[AcaoLojaPedido.marcarPronto]);
      for (final s in <String>[
        'callingDriver',
        'driverAccepted',
        'pickedUp',
        'onTheWay',
        'readyForPickup',
        'delivered',
      ]) {
        expect(acoes(s), isEmpty, reason: s);
      }
      // Retirada no balcão.
      expect(acoes('created', tipo: 'takeaway'), <AcaoLojaPedido>[
        AcaoLojaPedido.retiradaAceitar,
        AcaoLojaPedido.recusar,
      ]);
      expect(acoes('preparing', tipo: 'takeaway'),
          <AcaoLojaPedido>[AcaoLojaPedido.retiradaPronto]);
      expect(acoes('readyForPickup', tipo: 'takeaway'),
          <AcaoLojaPedido>[AcaoLojaPedido.retiradaEntregue]);
      expect(acoes('delivered', tipo: 'takeaway'), isEmpty);
      // O que não passa pela loja: nenhuma ação.
      expect(acoes('created', daLoja: false), isEmpty);
      expect(acoes('created', doPedido: false), isEmpty);
      expect(acoes('created', doPedido: true, daLoja: false),
          <AcaoLojaPedido>[AcaoLojaPedido.aceitar, AcaoLojaPedido.recusar],
          reason: 'o is_partner_store do pedido ganha à loja');
      expect(acoes('created', tipo: 'market'), isEmpty);
    });

    test('minutos de preparo: começa no tempo da loja, senão 15', () {
      final (entrega, inicialEntrega) =
          opcoesDeMinutos(retirada: false, padraoDaLoja: 20);
      expect(entrega, kMinutosPreparoEntrega);
      expect(inicialEntrega, 20);
      final (comExtra, inicialExtra) =
          opcoesDeMinutos(retirada: false, padraoDaLoja: 35);
      expect(comExtra, <int>[10, 15, 20, 25, 30, 35, 40, 45, 60]);
      expect(inicialExtra, 35);
      expect(opcoesDeMinutos(retirada: false, padraoDaLoja: 200).$2, 15,
          reason: 'fora de 5 a 120 o servidor recusa');
      expect(opcoesDeMinutos(retirada: false).$2, 15);
      final (retirada, inicialRetirada) =
          opcoesDeMinutos(retirada: true, padraoDaLoja: 20);
      expect(retirada, kMinutosPreparoRetirada);
      expect(inicialRetirada, 20);
      expect(opcoesDeMinutos(retirada: true, padraoDaLoja: 25).$1,
          kMinutosPreparoRetirada,
          reason: 'na retirada o servidor só aceita a lista dele');
      expect(opcoesDeMinutos(retirada: true, padraoDaLoja: 25).$2, 15);
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
          'takeaway_default_prep_minutes': 25,
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
      expect(l.minutosPreparoPadrao, 25);

      final semEstado = LojaAgora.deMapas(<String, dynamic>{'id': 'y'}, null);
      expect(semEstado.estadoLido, isFalse);
      expect(semEstado.nome, 'y');
      expect(semEstado.online, isTrue);
      expect(semEstado.aprovada, isTrue);
      expect(semEstado.minutosPreparoPadrao, isNull);
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
      expect(r.lista, isEmpty, reason: 'linhas sem id não entram na lista');
    });

    test(
        'reservas: a lista só leva as que têm ação; recusar só sem pagamento; '
        'chegada só hoje; recusada sai da contagem', () {
      final r = ResumoReservas.contar(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'r1',
          'status': 'pending',
          'reserved_for': '2026-11-15T20:00:00Z',
          'people': 4,
          'client_name': 'Rita',
          'prepayment_cents': 0,
        },
        <String, dynamic>{
          'id': 'r2',
          'status': 'pending',
          'reserved_for': '2026-11-16T20:00:00Z',
          'prepayment_cents': 300,
        },
        <String, dynamic>{
          'id': 'r3',
          'status': 'approved',
          'reserved_for': '2026-11-15T13:00:00Z',
          'prepayment_cents': 300,
        },
        <String, dynamic>{
          'id': 'r4',
          'status': 'approved',
          'reserved_for': '2026-11-17T13:00:00Z',
          'prepayment_cents': 300,
        },
        <String, dynamic>{
          'id': 'r5',
          'status': 'approved',
          'reserved_for': '2026-11-15T12:30:00Z',
          'arrived_at': '2026-11-15T12:20:00Z',
          'prepayment_cents': 300,
        },
        <String, dynamic>{
          'id': 'r6',
          'status': 'rejected_refunded',
          'reserved_for': '2026-11-15T21:00:00Z',
        },
      ], _agora);
      expect(r.lista.map((e) => e.id).toList(), <String>['r1', 'r2', 'r3']);
      expect(r.hoje, 3, reason: 'r1, r3 e r5; a recusada não conta');
      expect(r.proximas, 5);
      expect(r.porDecidir, 2);
      expect(r.lista.first.cliente, 'Rita');
      expect(r.lista.first.pessoas, 4);
      expect(r.lista.first.paga, isFalse);
      expect(r.lista[1].paga, isTrue);
      expect(acoesDaReserva(r.lista.first, _agora),
          <AcaoReserva>[AcaoReserva.aceitar, AcaoReserva.recusar]);
      expect(acoesDaReserva(r.lista[1], _agora), <AcaoReserva>[AcaoReserva.aceitar],
          reason: 'reserva paga não se recusa aqui: Cancelar reserva devolve');
      expect(acoesDaReserva(r.lista[2], _agora), <AcaoReserva>[AcaoReserva.chegada]);
      expect(estadoReservaPtBr('pending'), 'por decidir');
      expect(estadoReservaPtBr('approved'), 'aceita');
      expect(estadoReservaPtBr('rejected_refunded'), 'recusada');
      expect(estadoReservaPtBr('cancelled_by_client'), 'cancelada');
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

    test('o histórico das funções da loja: rótulos e a reserva no detalhe', () {
      expect(rotuloAcaoNaLoja(const AcaoDoAdmin(acao: 'admin_loja_aceitar_pedido')),
          'Aceitou um pedido no lugar da loja');
      expect(rotuloAcaoNaLoja(const AcaoDoAdmin(acao: 'admin_loja_recusar_pedido')),
          'Recusou um pedido no lugar da loja');
      expect(rotuloAcaoNaLoja(const AcaoDoAdmin(acao: 'admin_loja_marcar_pronto')),
          'Marcou um pedido pronto (chamou entregador)');
      expect(
          rotuloAcaoNaLoja(const AcaoDoAdmin(acao: 'admin_loja_retirada_entregue')),
          'Marcou que o cliente retirou o pedido no balcão');
      expect(
          rotuloAcaoNaLoja(const AcaoDoAdmin(
              acao: 'admin_loja_decidir_reserva',
              detalhes: <String, dynamic>{'aceitar': true})),
          'Aceitou uma reserva');
      expect(
          rotuloAcaoNaLoja(const AcaoDoAdmin(
              acao: 'admin_loja_decidir_reserva',
              detalhes: <String, dynamic>{'aceitar': false})),
          'Recusou uma reserva');
      final chegada = AcaoDoAdmin(
        acao: 'admin_loja_marcar_chegada',
        quem: 'admin@bora.pt',
        quando: DateTime.utc(2026, 11, 15, 13),
        detalhes: const <String, dynamic>{
          'motivo': 'cliente na mesa',
          'reservation_id': _rsvNova,
        },
      );
      expect(rotuloAcaoNaLoja(chegada), 'Marcou a chegada do cliente de uma reserva');
      expect(detalheAcaoNaLoja(chegada),
          '15/11 13:00 · admin@bora.pt · motivo: cliente na mesa · reserva #EEEE5555');
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

    test('as respostas e os erros das funções da loja em palavras do painel', () {
      expect(
          respostaAcaoLojaEmPalavras(
              <String, dynamic>{'ok': false, 'error': 'payment_not_confirmed'}),
          contains('pagamento do cliente ainda não foi confirmado'));
      expect(
          respostaAcaoLojaEmPalavras(<String, dynamic>{
            'ok': false,
            'error': 'invalid_status',
            'status': 'callingDriver',
          }),
          contains('agora: Chamando entregador'));
      expect(
          respostaAcaoLojaEmPalavras(<String, dynamic>{
            'ok': false,
            'error': 'forbidden',
            'detalhe': 'loja_nao_elegivel',
          }),
          contains('parceira, ativa e aprovada'));
      expect(respostaAcaoLojaEmPalavras(<String, dynamic>{'ok': false, 'error': 'xpto'}),
          'Não foi possível: xpto.');

      expect(erroDaLojaEmPalavras('motivo_obrigatorio: escreve pelo menos 3 letras'),
          'Escreva o motivo (mínimo 3 letras).');
      expect(erroDaLojaEmPalavras('order_already_processed: preparing'),
          contains('agora: Em preparo'));
      expect(erroDaLojaEmPalavras('order_not_ready: created'),
          contains('ainda não está pronto'));
      expect(erroDaLojaEmPalavras('reservation_not_pending: approved'),
          contains('agora: aceita'));
      expect(
          erroDaLojaEmPalavras('AGE_CHECK_REQUIRED: este pedido tem produtos para '
              'maiores de 18.'),
          contains('maiores de 18'));
      expect(erroDaLojaEmPalavras('already_arrived'), contains('já estava marcada'));
      expect(erroDaLojaEmPalavras('restaurant_not_found'), 'Loja não encontrada.');
      expect(erroDaLojaEmPalavras(_marcaReservaPaga), isNull,
          reason: 'reserva_paga fica com humanizeAdminRpcError');
      expect(erroDaLojaEmPalavras('admin_required'), isNull);

      expect(
          chegadaEmPalavras(<String, dynamic>{
            'success': true,
            'credit_cents': 200,
            'payout_cents': 200,
          }),
          'Chegada marcada: o cliente ganhou 2,00 € de crédito para gastar nesta '
          'loja e a loja recebe 2,00 € no fechamento da semana.');
      expect(chegadaEmPalavras(<String, dynamic>{'success': true}),
          'Chegada do cliente marcada.');
    });

    test('reserva_paga: o painel explica que se usa Cancelar reserva', () {
      expect(kErroReservaPaga,
          'Esta reserva já foi paga: para a recusar use Cancelar reserva, que '
          'devolve o dinheiro ao cliente.');
      expect(
          humanizeAdminRpcError(
              const PostgrestException(message: _marcaReservaPaga, code: '22023')),
          kErroReservaPaga);
      expect(
          humanizeAdminRpcError(
              const PostgrestException(message: 'recusa', code: 'reserva_paga')),
          kErroReservaPaga);
      // O resto continua igual.
      expect(humanizeAdminRpcError(const PostgrestException(message: 'admin_required')),
          'Sem permissão de admin para esta ação.');
      expect(humanizeAdminRpcError(const PostgrestException(message: 'xpto')),
          'Erro do servidor: xpto');
    });

    test('motivo mínimo de 3 letras', () {
      expect(motivoAreaParceiroOk(null), isFalse);
      expect(motivoAreaParceiroOk(' ab '), isFalse);
      expect(motivoAreaParceiroOk('abc'), isTrue);
      expect(motivoAreaParceiroOk('12 3!'), isFalse,
          reason: 'o servidor só conta letras');
      expect(motivoAreaParceiroOk('a1 b2 ç'), isTrue);
    });
  });

  group('serviço: cada função com o nome e os parâmetros certos', () {
    test('pedidos: admin_pedidos_da_loja pelo id da loja', () async {
      final chamadas = <(String, Map<String, dynamic>?)>[];
      final s = SupabaseAdminAreaParceiroService(rpc: (nome, params) async {
        chamadas.add((nome, params));
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'o1',
            'status': 'preparing',
            'service_type': 'restaurant',
            'vendor_name': 'Nome antigo da loja',
            'created_at': '2026-11-15T10:00:00Z',
            'is_partner_store': true,
          },
          <String, dynamic>{
            'id': 'o2',
            'status': 'readyForPickup',
            'service_type': 'takeaway',
            'vendor_name': 'Pizzaria Teste',
            'created_at': '2026-11-15T11:00:00Z',
            'is_partner_store': true,
          },
        ];
      });
      final r = await s.pedidosAgora(restaurantId: _lojaId, nomeLoja: 'Pizzaria Teste');
      expect(chamadas.map((c) => c.$1).toList(), <String>['admin_pedidos_da_loja']);
      expect(chamadas.single.$2, <String, dynamic>{
        'p_restaurant_id': _lojaId,
        'p_limite': kAreaParceiroMaxPedidos,
      });
      expect(r.peloNome, isFalse);
      expect(r.pedidos.map((p) => p.id).toList(), <String>['o2', 'o1'],
          reason: 'a função já filtra pela loja: o nome não conta');
      expect(r.pedidos.first.status, 'readyForPickup');
    });

    test('pedidos: só se a função da loja falhar volta ao caminho antigo, pelo nome',
        () async {
      final nomes = <String>[];
      final params = <Map<String, dynamic>?>[];
      final s = SupabaseAdminAreaParceiroService(rpc: (nome, p) async {
        nomes.add(nome);
        params.add(p);
        if (nome == 'admin_pedidos_da_loja') {
          throw const PostgrestException(
              message: 'Could not find the function', code: 'PGRST202');
        }
        return <Map<String, dynamic>>[
          <String, dynamic>{'id': 'o1', 'status': 'created', 'vendor_name': 'Pizzaria Teste'},
          <String, dynamic>{'id': 'o2', 'status': 'created', 'vendor_name': 'Outra Loja'},
        ];
      });
      final r = await s.pedidosAgora(restaurantId: _lojaId, nomeLoja: 'Pizzaria Teste');
      expect(nomes, <String>['admin_pedidos_da_loja', 'admin_live_orders']);
      expect(params.last, <String, dynamic>{'p_include_test_orders': true});
      expect(r.peloNome, isTrue);
      expect(r.pedidos.map((p) => p.id).toList(), <String>['o1']);

      // Sem o nome da loja não há caminho antigo: o erro sobe.
      await expectLater(s.pedidosAgora(restaurantId: _lojaId, nomeLoja: '  '),
          throwsA(isA<PostgrestException>()));
    });

    test(
        'no lugar da loja: cada ação chama a sua função com o motivo, e nenhuma '
        'grava auditoria a mais', () async {
      final chamadas = <(String, Map<String, dynamic>?)>[];
      final s = SupabaseAdminAreaParceiroService(rpc: (nome, params) async {
        chamadas.add((nome, params));
        return <String, dynamic>{'ok': true, 'success': true};
      });
      await s.aceitarPedido('o1', minutos: 25, motivo: '  loja sem rede ');
      await s.recusarPedido('o1', motivo: 'sem massa');
      await s.marcarPronto('o2', motivo: 'loja pediu');
      await s.passoDaRetirada('o3',
          passo: PassoRetirada.aceitar, motivo: 'cliente ligou', minutos: 10);
      await s.passoDaRetirada('o3', passo: PassoRetirada.pronto, motivo: 'loja pediu');
      await s.passoDaRetirada('o3',
          passo: PassoRetirada.entregue, motivo: 'cliente levou');
      await s.decidirReserva('r1', aceitar: false, motivo: 'loja cheia');
      await s.decidirReserva('r2', aceitar: true, motivo: 'loja confirmou');
      await s.marcarChegada('r3', motivo: 'cliente na mesa');

      expect(chamadas.map((c) => c.$1).toList(), <String>[
        'admin_loja_aceitar_pedido',
        'admin_loja_recusar_pedido',
        'admin_loja_marcar_pronto',
        'admin_loja_retirada',
        'admin_loja_retirada',
        'admin_loja_retirada',
        'admin_loja_decidir_reserva',
        'admin_loja_decidir_reserva',
        'admin_loja_marcar_chegada',
      ]);
      expect(chamadas.map((c) => c.$2).toList(), <Map<String, dynamic>>[
        <String, dynamic>{
          'p_order_id': 'o1',
          'p_prep_minutes': 25,
          'p_motivo': 'loja sem rede',
        },
        <String, dynamic>{'p_order_id': 'o1', 'p_motivo': 'sem massa'},
        <String, dynamic>{'p_order_id': 'o2', 'p_motivo': 'loja pediu'},
        <String, dynamic>{
          'p_order_id': 'o3',
          'p_passo': 'aceitar',
          'p_motivo': 'cliente ligou',
          'p_prep_minutes': 10,
        },
        <String, dynamic>{
          'p_order_id': 'o3',
          'p_passo': 'pronto',
          'p_motivo': 'loja pediu',
          'p_prep_minutes': null,
        },
        <String, dynamic>{
          'p_order_id': 'o3',
          'p_passo': 'entregue',
          'p_motivo': 'cliente levou',
          'p_prep_minutes': null,
        },
        <String, dynamic>{
          'p_reservation_id': 'r1',
          'p_aceitar': false,
          'p_motivo': 'loja cheia',
        },
        <String, dynamic>{
          'p_reservation_id': 'r2',
          'p_aceitar': true,
          'p_motivo': 'loja confirmou',
        },
        <String, dynamic>{'p_reservation_id': 'r3', 'p_motivo': 'cliente na mesa'},
      ]);
      expect(chamadas.where((c) => c.$1 == 'log_admin_action'), isEmpty,
          reason: 'as admin_loja_* já gravam o motivo no log de auditoria');
    });

    test('o erro do servidor sobe tal e qual (o ecrã põe-no em palavras)', () async {
      final s = SupabaseAdminAreaParceiroService(rpc: (nome, params) async {
        throw const PostgrestException(message: _marcaReservaPaga, code: '22023');
      });
      await expectLater(s.decidirReserva('r1', aceitar: false, motivo: 'loja cheia'),
          throwsA(isA<PostgrestException>()));
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
      expect(find.textContaining('#ADAD0003 · Pronto para retirada'), findsOneWidget,
          reason: 'a retirada pronta, esperando o cliente, aparece');
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
      expect(find.byKey(const Key('area_reserva_$_rsvNova')), findsOneWidget);
      // 6 Histórico
      expect(find.text('Forçou FECHAR a loja'), findsOneWidget);
      expect(find.textContaining('motivo: falta de pessoal'), findsOneWidget);

      expect(
          f.chamadas,
          containsAll(<String>[
            'lerLoja:$_lojaId',
            'pedidos:$_lojaId:Pizzaria Teste',
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

    testWidgets(
        'cada pedido mostra só a ação válida para o estado dele, ligada; só a '
        'falta de item continua desligada e diz porquê', (t) async {
      await _abrir(t);
      // Ligados, no estado certo.
      for (final chave in <String>[
        'area_aceitar_$_idNovo',
        'area_recusar_$_idNovo',
        'area_marcar_pronto_$_idPreparo',
        'area_retirada_aceitar_$_idRetiradaNova',
        'area_recusar_$_idRetiradaNova',
        'area_retirada_pronto_$_idRetiradaPreparo',
        'area_retirada_entregue_$_idRetiradaPronta',
      ]) {
        expect(find.byKey(Key(chave)), findsOneWidget, reason: chave);
        expect(_botao(t, chave).onPressed, isNotNull, reason: chave);
      }
      // Nada fora do estado.
      for (final chave in <String>[
        'area_marcar_pronto_$_idNovo',
        'area_aceitar_$_idPreparo',
        'area_recusar_$_idPreparo',
        'area_aceitar_$_idChamando',
        'area_recusar_$_idChamando',
        'area_marcar_pronto_$_idChamando',
        'area_aceitar_$_idACaminho',
        'area_marcar_pronto_$_idACaminho',
        'area_aceitar_$_idRetiradaNova',
        'area_marcar_pronto_$_idRetiradaPreparo',
        'area_retirada_pronto_$_idRetiradaNova',
        'area_retirada_entregue_$_idRetiradaPreparo',
        'area_retirada_pronto_$_idRetiradaPronta',
      ]) {
        expect(find.byKey(Key(chave)), findsNothing, reason: chave);
      }
      // Os botões desligados de antes já não existem.
      for (final chave in <String>[
        'area_pendente_aceitar_$_idNovo',
        'area_pendente_recusar_$_idNovo',
        'area_pendente_pronto_$_idPreparo',
        'area_pendente_reserva',
        'area_pendente_chegada',
      ]) {
        expect(find.byKey(Key(chave)), findsNothing, reason: chave);
      }
      // Falta de item: ainda sem função no servidor.
      for (final chave in <String>[
        'area_pendente_falta_$_idPreparo',
        'area_pendente_falta_$_idRetiradaPreparo',
      ]) {
        expect(find.byKey(Key(chave)), findsOneWidget, reason: chave);
        expect(_botao(t, chave).onPressed, isNull, reason: chave);
      }
      expect(find.text(kAreaParceiroFraseFuncaoNova), findsNWidgets(2),
          reason: 'só os dois pedidos em preparo (falta de item)');
      expect(t.widget<Text>(find.byKey(const Key('area_pedidos_origem'))).data,
          contains('também as retiradas prontas'));
      // O que já funciona fica ligado.
      expect(_botao(t, 'area_pausar').onPressed, isNotNull);
      expect(_botao(t, 'area_ligar_ocupado').onPressed, isNotNull);
      expect(_botao(t, 'area_forcar_fechar').onPressed, isNotNull);
      // Voltar ao horário só quando há abrir/fechar à força.
      expect(_botao(t, 'area_voltar_horario').onPressed, isNull);
    });

    testWidgets(
        'aceitar: o tempo começa no da loja, o motivo precisa de 3 letras e vai à '
        'função certa sem auditoria a mais', (t) async {
      final f = await _abrir(t, falso: _Falso(loja: _loja(minutosPadrao: 35)));
      await _tocar(t, find.byKey(const Key('area_aceitar_$_idNovo')));
      expect(_marcada(t, 35), isTrue, reason: 'o tempo padrão da loja');
      expect(_marcada(t, 20), isFalse);

      // Números não contam como letras: o confirmar fica desligado.
      await t.enterText(find.byKey(const Key('area_motivo_campo')), '123');
      await t.pump();
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull);
      expect(f.chamadas.where((c) => c.startsWith('aceitar:')), isEmpty);

      await _escreverMotivoEConfirmar(t, 'loja sem internet');
      expect(f.chamadas, contains('aceitar:$_idNovo:35:loja sem internet'));
      expect(f.auditorias, isEmpty,
          reason: 'admin_loja_aceitar_pedido já grava o motivo e a loja');
      expect(find.text('Pedido aceito: fica pronto em 35 min.'), findsOneWidget);
    });

    testWidgets('enquanto a função corre, os botões desse pedido ficam desligados',
        (t) async {
      final segurar = Completer<Map<String, dynamic>>();
      final f = _Falso()..segurarAceitar = segurar;
      await _abrir(t, falso: f);
      await _tocar(t, find.byKey(const Key('area_aceitar_$_idNovo')));
      await _escreverMotivoEConfirmar(t, 'loja pediu ajuda');

      expect(_botao(t, 'area_aceitar_$_idNovo').onPressed, isNull);
      expect(_botao(t, 'area_recusar_$_idNovo').onPressed, isNull);
      expect(_botao(t, 'area_cancelar_$_idNovo').onPressed, isNull);
      expect(_botao(t, 'area_marcar_pronto_$_idPreparo').onPressed, isNotNull,
          reason: 'cada pedido trava só os seus botões');

      segurar.complete(<String, dynamic>{
        'ok': true,
        'status': 'preparing',
        'prep_time_minutes': 20,
      });
      await t.pumpAndSettle();
      expect(_botao(t, 'area_aceitar_$_idNovo').onPressed, isNotNull);
      expect(find.text('Pedido aceito: fica pronto em 20 min.'), findsOneWidget);
    });

    testWidgets('recusar: avisa que o cliente é avisado e o dinheiro volta sozinho',
        (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_recusar_$_idNovo')));
      expect(find.byKey(const Key('area_motivo_aviso')), findsOneWidget);
      expect(find.text(kAreaParceiroAvisoRecusar), findsOneWidget);
      expect(kAreaParceiroAvisoRecusar,
          'O cliente é avisado e, se pagou com cartão ou MB WAY, o dinheiro volta '
          'sozinho.');
      await _escreverMotivoEConfirmar(t, 'falta ingrediente principal');
      expect(f.chamadas, contains('recusar:$_idNovo:falta ingrediente principal'));
      expect(f.auditorias, isEmpty);
      expect(find.text('Pedido recusado. $kAreaParceiroAvisoRecusar'), findsOneWidget);

      // A retirada nova recusa-se pela mesma função.
      await _tirarAviso(t);
      await _tocar(t, find.byKey(const Key('area_recusar_$_idRetiradaNova')));
      await _escreverMotivoEConfirmar(t, 'loja fechou o forno');
      expect(f.chamadas, contains('recusar:$_idRetiradaNova:loja fechou o forno'));
    });

    testWidgets(
        'marcar pronto: avisa que chama um estafeta e mostra a resposta do '
        'servidor em palavras', (t) async {
      final f = _Falso()
        ..respostaPronto = <String, dynamic>{
          'ok': false,
          'error': 'payment_not_confirmed',
        };
      await _abrir(t, falso: f);
      await _tocar(t, find.byKey(const Key('area_marcar_pronto_$_idPreparo')));
      expect(find.text(kAreaParceiroAvisoPronto), findsOneWidget);
      expect(kAreaParceiroAvisoPronto, 'Isto chama um estafeta.');
      await _escreverMotivoEConfirmar(t, 'loja sem sistema');
      expect(f.chamadas, contains('pronto:$_idPreparo:loja sem sistema'));
      expect(
          find.text(respostaAcaoLojaEmPalavras(
              const <String, dynamic>{'error': 'payment_not_confirmed'})),
          findsOneWidget);
      expect(f.auditorias, isEmpty);
    });

    testWidgets('retirada no balcão: o passo certo de cada estado, com o tempo da loja',
        (t) async {
      final f = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_retirada_aceitar_$_idRetiradaNova')));
      expect(_marcada(t, 20), isTrue, reason: 'o tempo padrão da loja');
      await t.tap(find.byKey(const Key('area_opcao_10')));
      await t.pump();
      await _escreverMotivoEConfirmar(t, 'cliente ligou');
      expect(f.chamadas, contains('retirada:$_idRetiradaNova:aceitar:10:cliente ligou'));
      expect(find.text('Retirada aceita: fica pronta em 10 min.'), findsOneWidget);

      await _tirarAviso(t);
      await _tocar(t, find.byKey(const Key('area_retirada_pronto_$_idRetiradaPreparo')));
      expect(find.byKey(const Key('area_opcao_10')), findsNothing,
          reason: 'só o aceitar escolhe o tempo');
      await _escreverMotivoEConfirmar(t, 'loja pediu');
      expect(f.chamadas, contains('retirada:$_idRetiradaPreparo:pronto:null:loja pediu'));
      expect(find.text('Pronto para retirada: o cliente foi avisado (código 4321).'),
          findsOneWidget);

      await _tirarAviso(t);
      await _tocar(
          t, find.byKey(const Key('area_retirada_entregue_$_idRetiradaPronta')));
      expect(find.text(kAreaParceiroAvisoRetirou), findsOneWidget);
      await _escreverMotivoEConfirmar(t, 'cliente levou');
      expect(f.chamadas,
          contains('retirada:$_idRetiradaPronta:entregue:null:cliente levou'));
      expect(f.auditorias, isEmpty, reason: 'admin_loja_retirada já grava');
    });

    testWidgets(
        'reservas: aceitar, recusar só sem pagamento e "Cliente chegou" só na '
        'aceita de hoje', (t) async {
      final f = await _abrir(t);
      expect(_botao(t, 'area_reserva_aceitar_$_rsvNova').onPressed, isNotNull);
      expect(_botao(t, 'area_reserva_recusar_$_rsvNova').onPressed, isNotNull);
      expect(_botao(t, 'area_reserva_aceitar_$_rsvPaga').onPressed, isNotNull);
      expect(find.byKey(const Key('area_reserva_recusar_$_rsvPaga')), findsNothing,
          reason: 'reserva paga: Cancelar reserva devolve o dinheiro');
      expect(t.widget<Text>(find.byKey(const Key('area_reserva_paga_$_rsvPaga'))).data,
          kAreaParceiroReservaPaga);
      expect(_botao(t, 'area_reserva_chegada_$_rsvHoje').onPressed, isNotNull);
      expect(find.byKey(const Key('area_reserva_chegada_$_rsvNova')), findsNothing);
      expect(find.byKey(const Key('area_reserva_aceitar_$_rsvHoje')), findsNothing);

      await _tocar(t, find.byKey(const Key('area_reserva_aceitar_$_rsvNova')));
      await _escreverMotivoEConfirmar(t, 'loja confirmou por telefone');
      expect(f.chamadas, contains('reserva:$_rsvNova:true:loja confirmou por telefone'));
      expect(find.text('Reserva aceita: o cliente recebe a confirmação.'),
          findsOneWidget);

      await _tirarAviso(t);
      await _tocar(t, find.byKey(const Key('area_reserva_recusar_$_rsvNova')));
      await _escreverMotivoEConfirmar(t, 'loja cheia');
      expect(f.chamadas, contains('reserva:$_rsvNova:false:loja cheia'));

      await _tirarAviso(t);
      await _tocar(t, find.byKey(const Key('area_reserva_chegada_$_rsvHoje')));
      expect(find.text(kAreaParceiroAvisoChegada), findsOneWidget);
      expect(kAreaParceiroAvisoChegada, contains('pré-pagamento de 3 €'));
      await _escreverMotivoEConfirmar(t, 'cliente na mesa');
      expect(f.chamadas, contains('chegada:$_rsvHoje:cliente na mesa'));
      expect(
          find.text(chegadaEmPalavras(const <String, dynamic>{
            'credit_cents': 200,
            'payout_cents': 200,
          })),
          findsOneWidget);
      expect(f.auditorias, isEmpty, reason: 'as funções da loja já gravam no log');
    });

    testWidgets(
        'recusar uma reserva que afinal está paga: o servidor diz reserva_paga e '
        'o painel explica o caminho', (t) async {
      final f = _Falso()
        ..erroReserva =
            const PostgrestException(message: _marcaReservaPaga, code: '22023');
      await _abrir(t, falso: f);
      await _tocar(t, find.byKey(const Key('area_reserva_recusar_$_rsvNova')));
      await _escreverMotivoEConfirmar(t, 'loja cheia');
      expect(f.chamadas, contains('reserva:$_rsvNova:false:loja cheia'));
      expect(find.text(kErroReservaPaga), findsOneWidget);
      // Depois do erro o botão volta a ficar ligado.
      expect(_botao(t, 'area_reserva_recusar_$_rsvNova').onPressed, isNotNull);
    });

    testWidgets('lista pelo caminho antigo: o painel diz de onde veio', (t) async {
      final f = _Falso()..pedidosPeloNome = true;
      await _abrir(t, falso: f);
      expect(t.widget<Text>(find.byKey(const Key('area_pedidos_origem'))).data,
          contains('A lista da loja não respondeu'));
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
        'admin_pedidos_da_loja',
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
        'admin_loja_aceitar_pedido',
        'admin_loja_recusar_pedido',
        'admin_loja_marcar_pronto',
        'admin_loja_retirada',
        'admin_loja_decidir_reserva',
        'admin_loja_marcar_chegada',
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
      expect(src, contains("'p_motivo': motivo.trim()"),
          reason: 'as admin_loja_* recebem o motivo sem espaços nas pontas');
      expect('.timeout(kAreaParceiroLimite)'.allMatches(src).length,
          greaterThanOrEqualTo(6),
          reason: 'toda a chamada ao servidor tem tempo limite');
    });

    test(
        'as ações no lugar da loja não gravam auditoria a mais (as admin_loja_* '
        'já gravam o motivo)', () {
      final src =
          File(ecra).readAsStringSync().replaceAll(String.fromCharCode(13), '');
      for (final assinatura in <String>[
        'Future<void> _aceitar(',
        'Future<void> _recusar(',
        'Future<void> _marcarPronto(',
        'Future<void> _retirada(',
        'Future<void> _decidirReserva(',
        'Future<void> _marcarChegada(',
      ]) {
        final i = src.indexOf(assinatura);
        expect(i, greaterThanOrEqualTo(0), reason: 'falta $assinatura');
        final fim = src.indexOf('\n  }\n', i);
        final corpo = src.substring(i, fim < 0 ? src.length : fim);
        expect(corpo.contains('_registar('), isFalse, reason: assinatura);
        expect(corpo.contains('_pedirMotivo('), isTrue,
            reason: '$assinatura pede confirmação com motivo');
      }
    });
  });
}
