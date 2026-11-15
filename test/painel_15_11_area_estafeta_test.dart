// Área do estafeta (15/11/2026, missão app-15-11 — ordem do Danilo): o admin
// escolhe um entregador e faz por ele o que ele faz no app, tudo registrado.
// Sem rede: o ecrã usa um serviço falso e o Supabase nunca é inicializado; as
// chamadas verdadeiras (nome da função e parâmetros) provam-se com o SDK
// verdadeiro e um servidor de mentira (MockClient). Dados inventados.
import 'dart:convert';
import 'dart:io';

import 'package:bora_app/screens/admin/admin_area_estafeta_screen.dart';
import 'package:bora_app/services/admin_area_estafeta_service.dart';
import 'package:bora_app/services/minha_conta.dart';
import 'package:bora_app/services/robo_documentos.dart';
import 'package:bora_app/utils/periodo_entregas.dart';
import 'package:bora_app/widgets/admin/escolher_estafeta_sheet.dart'
    show EstafetaParaAtribuir;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

const _userId = '11111111-1111-4111-8111-111111111111';
const _driverId = '22222222-2222-4222-8222-222222222222';
const _idDele = 'aaaaaaaa-0000-4000-8000-000000000001';
const _idEspera = 'bbbbbbbb-0000-4000-8000-000000000002';
const _idAceito = 'cccccccc-0000-4000-8000-000000000003';
const _idACaminho = 'dddddddd-0000-4000-8000-000000000004';

/// A resposta de admin_fatura_mes_estafeta (inventada): com entregas em
/// novembro, sem entregas em outubro.
Map<String, dynamic> _faturaJson({
  bool comEntregas = true,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) =>
    <String, dynamic>{
      'ano': 2026,
      'mes': comEntregas ? 11 : 10,
      'nome_mes': comEntregas ? 'novembro' : 'outubro',
      'user_id': _userId,
      'driver_id': _driverId,
      'tem_entregas': comEntregas,
      'estafeta': comEntregas
          ? <String, dynamic>{
              'user_id': _userId,
              'nome': 'João Teste',
              'nif': '123456789',
              'atividade_aberta': true,
              'entregas': 5,
              'total_a_faturar': 24.9,
              'cliente': 'Bora Teste Lda',
              'cliente_nif': '500000000',
              'texto_recibo': 'Serviços prestados em novembro de 2026 através da '
                  'plataforma Bora (5 entregas)',
              'iva': 'IVA: depende do seu regime.',
              'retencao': 'Retenção: o contabilista confirma.',
              'prazo': 'Fatura-recibo até ao 5.º dia útil.',
              'recibo_passado': false,
              ...extra,
            }
          : null,
      'adquirente': <String, dynamic>{'nome': 'Bora Teste Lda', 'nif': '500000000'},
    };

List<PedidoAberto> _pedidos() => [
      const PedidoAberto(
        id: _idDele,
        status: 'pickedUp',
        loja: 'Pizzaria Central',
        entrega: 'Rua Direita 10, Guarda',
        entregadorId: _userId,
      ),
      PedidoAberto(
        id: _idEspera,
        status: 'callingDriver',
        loja: 'Mercado do Bairro',
        entrega: 'Avenida Rainha D. Amélia 5, Guarda',
        criadoEm: DateTime.utc(2026, 11, 15, 9, 30),
      ),
    ];

List<TrabalhoGanho> _trabalhosDeAgora() => [
      TrabalhoGanho(
        tipo: 'entrega',
        quando: DateTime.now().toUtc(),
        quandoTxt: '15/11 10:00',
        descricao: 'Entrega Pizzaria Central',
        pagamento: 'cash',
        ganhouCents: 450,
        clientePagouCents: 1890,
      ),
      TrabalhoGanho(
        tipo: 'entrega',
        quando: DateTime.now().toUtc(),
        quandoTxt: '15/11 11:00',
        descricao: 'Entrega Mercado do Bairro',
        pagamento: 'card',
        ganhouCents: 380,
        clientePagouCents: 2500,
      ),
    ];

class _Falso extends AdminAreaEstafetaService {
  _Falso({
    List<PedidoAberto>? pedidos,
    List<TrabalhoGanho>? trabalhos,
    this.modo = const ModoTrabalho(modo: 'everything', veiculo: 'carro_passageiros'),
    this.ligado = true,
    this.respostaLigar = const <String, dynamic>{
      'ok': true,
      'antes': true,
      'depois': false,
      'pedidos_em_curso': 1,
      'avisos': <String>[],
    },
    this.respostaAvancar = const <String, dynamic>{
      'ok': true,
      'status': 'pickedUp',
      'de': 'driverAccepted',
    },
  })  : pedidos = pedidos ?? _pedidos(),
        trabalhos = trabalhos ?? _trabalhosDeAgora();

  final List<PedidoAberto> pedidos;
  final List<TrabalhoGanho> trabalhos;
  final ModoTrabalho modo;

  /// O botão "ligado" dele (is_online) que a presença devolve.
  final bool ligado;

  /// O que admin_set_driver_online e admin_estafeta_avancar respondem.
  final Map<String, dynamic> respostaLigar;
  final Map<String, dynamic> respostaAvancar;
  final List<String> chamadas = [];

  @override
  Future<PresencaEstafeta?> presenca(String driverId) async {
    chamadas.add('presenca:$driverId');
    return PresencaEstafeta(
      ligado: ligado,
      ligadoAgora: ligado,
      ultimoSinal: DateTime.now().toUtc(),
      temNotificacoes: true,
      aparelhos: 1,
      plataforma: 'android_app',
      pedidosEmCurso: 1,
      gpsIdadeS: 12,
    );
  }

  @override
  Future<PosicaoEstafeta?> posicao({required String userId, required String driverId}) async {
    chamadas.add('posicao');
    return PosicaoEstafeta(lat: 40.5373, lng: -7.2676, quando: DateTime.now().toUtc());
  }

  @override
  Future<List<PedidoAberto>> pedidosAbertos() async {
    chamadas.add('pedidos');
    return pedidos;
  }

  @override
  Future<List<EstafetaParaAtribuir>> outrosEntregadores(String orderId) async {
    chamadas.add('outros:$orderId');
    return [
      // Ele próprio também vem do servidor: o ecrã tem de o tirar da lista.
      EstafetaParaAtribuir.fromRow(const {
        'user_id': _userId,
        'driver_id': _driverId,
        'name': 'João Teste',
        'is_online': true,
        'online_agora': true,
        'tem_notificacoes': true,
      }),
      EstafetaParaAtribuir.fromRow(const {
        'user_id': 'outro-1',
        'driver_id': 'd-outro-1',
        'name': 'Maria Outra',
        'is_online': true,
        'online_agora': true,
        'tem_notificacoes': true,
      }),
    ];
  }

  @override
  Future<Map<String, dynamic>> atribuirPedido({
    required String orderId,
    required String novoEntregador,
    required String motivo,
  }) async {
    chamadas.add('atribuir:$orderId:$novoEntregador:$motivo');
    return <String, dynamic>{'ok': true, 'estafeta': 'Quem Recebeu', 'pre_atribuicao': false};
  }

  @override
  Future<Map<String, dynamic>> devolverAFila({
    required String orderId,
    required String motivo,
  }) async {
    chamadas.add('devolver:$orderId:$motivo');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(String orderId, String motivo) async {
    chamadas.add('sem_codigo:$orderId:$motivo');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> avancarPedido({
    required String orderId,
    required String status,
    required String motivo,
  }) async {
    chamadas.add('avancar:$orderId:$status:$motivo');
    return Map<String, dynamic>.from(respostaAvancar);
  }

  @override
  Future<Map<String, dynamic>> avisarGps(String driverId) async {
    chamadas.add('aviso_gps:$driverId');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> avisarSemSinal(String userId) async {
    chamadas.add('aviso_sem_sinal:$userId');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> ligarDesligar({
    required String driverId,
    required bool ligar,
    required String motivo,
  }) async {
    chamadas.add('online:$driverId:$ligar:$motivo');
    return Map<String, dynamic>.from(respostaLigar);
  }

  @override
  Future<FaturaDoMes> faturaDoMes({required String userId, required DateTime mes}) async {
    chamadas.add('fatura:$userId:${mesParaServidor(mes)}');
    // O mês passado (pelo calendário de Lisboa) não teve entregas.
    final passado = mes == primeiroDiaDoMes(MesFatura.mesPassado, DateTime.now());
    return FaturaDoMes.fromJson(_faturaJson(comEntregas: !passado));
  }

  @override
  Future<ExtratoGanhos> ganhos(String userId) async {
    chamadas.add('ganhos:$userId');
    return ExtratoGanhos(trabalhos: trabalhos);
  }

  @override
  Future<ContaDoEstafeta> conta(String userId) async {
    chamadas.add('conta:$userId');
    return const ContaDoEstafeta(
      estado: EstadoMinhaConta(
        itens: [
          ItemConta(
            chave: 'iban',
            rotulo: 'IBAN',
            rotuloCurto: 'IBAN',
            estado: EstadoItemConta.falta,
            detalhe: 'Falta o IBAN para receber.',
          ),
          ItemConta(
            chave: 'selfie',
            rotulo: 'Selfie',
            rotuloCurto: 'selfie',
            estado: EstadoItemConta.ok,
          ),
        ],
        doServidor: true,
      ),
      aprovacao: 'approved',
    );
  }

  @override
  Future<List<VereditoRobo>> documentos(String userId) async {
    chamadas.add('documentos:$userId');
    return const <VereditoRobo>[];
  }

  @override
  Future<Map<String, dynamic>> lembrarDocumentos(String userId) async {
    chamadas.add('lembrar:$userId');
    return <String, dynamic>{
      'ok': true,
      'faltas': ['iban'],
    };
  }

  @override
  Future<ModoTrabalho> modoTrabalho(String driverId) async {
    chamadas.add('modo_ler:$driverId');
    return modo;
  }

  @override
  Future<Map<String, dynamic>> definirModoTrabalho({
    required String driverId,
    required String modo,
  }) async {
    chamadas.add('modo:$driverId:$modo');
    return <String, dynamic>{'ok': true, 'work_mode': modo};
  }

  @override
  Future<bool> registarAuditoria({
    required String acao,
    required String driverId,
    required Map<String, dynamic> detalhes,
  }) async {
    chamadas.add('auditoria:$acao:$driverId:${detalhes['motivo']}');
    return true;
  }

  @override
  Future<List<RegistoAdmin>> historico({
    required String userId,
    required String driverId,
  }) async {
    chamadas.add('historico:$userId:$driverId');
    return [
      RegistoAdmin(
        quando: DateTime.utc(2026, 11, 15, 10),
        acao: 'driver_avisado_gps',
        quem: 'admin@bora.pt',
      ),
    ];
  }
}

void _ecraGrande(WidgetTester t) {
  t.view.physicalSize = const Size(1280, 4200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<_Falso> _abrir(WidgetTester t, {_Falso? falso}) async {
  _ecraGrande(t);
  final f = falso ?? _Falso();
  await t.pumpWidget(MaterialApp(
    home: AdminAreaEstafetaScreen(
      driverId: _driverId,
      userId: _userId,
      nome: 'João Teste',
      servico: f,
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

ButtonStyleButton _botao(WidgetTester t, String chave) =>
    t.widget<ButtonStyleButton>(find.byKey(Key(chave)));

/// O SDK verdadeiro contra um servidor de mentira: guarda cada pedido e
/// responde o JSON que [responder] devolver.
SupabaseClient _servidorDeMentira(
  List<http.Request> pedidos,
  Object? Function(http.Request pedido) responder,
) =>
    SupabaseClient(
      'http://127.0.0.1:1',
      'teste',
      httpClient: MockClient((r) async {
        pedidos.add(r);
        return http.Response(jsonEncode(responder(r)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'}, request: r);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presença numa frase', () {
    final agora = DateTime.utc(2026, 11, 15, 12);

    test('ligado de verdade: "Ligado, GPS há 12 s"', () {
      final p = PresencaEstafeta(
          ligado: true, ligadoAgora: true, ultimoSinal: agora, gpsIdadeS: 12);
      expect(textoPresenca(p, agora), 'Ligado, GPS há 12 s');
      expect(nivelPresenca(p), NivelPresenca.ligado);
    });

    test('botão ligado mas o sinal parou há 7 min', () {
      final p = PresencaEstafeta(
        ligado: true,
        ligadoAgora: false,
        ultimoSinal: agora.subtract(const Duration(minutes: 7)),
        gpsIdadeS: 420,
      );
      expect(textoPresenca(p, agora), 'Ligado mas sem sinal há 7 min');
      expect(nivelPresenca(p), NivelPresenca.semSinal);
    });

    test('sinal vivo mas GPS parado: diz que é o GPS', () {
      final p = PresencaEstafeta(
        ligado: true,
        ligadoAgora: false,
        ultimoSinal: agora.subtract(const Duration(seconds: 20)),
        gpsIdadeS: 19 * 60,
        gpsFresco: false,
      );
      expect(textoPresenca(p, agora), 'Ligado mas GPS parado há 19 min');
    });

    test('desligado, sem sinal nunca e sem dados', () {
      expect(
          textoPresenca(const PresencaEstafeta(ligado: false, ligadoAgora: false), agora),
          'Desligado');
      expect(
          textoPresenca(const PresencaEstafeta(ligado: true, ligadoAgora: false), agora),
          'Ligado mas nunca mandou sinal');
      expect(textoPresenca(null, agora), 'Sem dados de presença');
      expect(nivelPresenca(null), NivelPresenca.desligado);
    });

    test('linha do servidor: lê as colunas e aguenta a linha vazia', () {
      final p = PresencaEstafeta.fromRow(const {
        'is_online': true,
        'online_agora': true,
        'last_heartbeat_at': '2026-11-15T11:59:50+00:00',
        'tem_notificacoes': true,
        'tokens_ativos': 2,
        'last_platform': 'ios_app',
        'pedidos_em_curso': 1,
        'gps_age_s': 12,
        'gps_fresco': true,
      });
      expect(p.ligadoAgora, isTrue);
      expect(p.aparelhos, 2);
      expect(p.gpsIdadeS, 12);
      expect(textoUltimoSinal(p.ultimoSinal, agora), '15/11 11:59 (há 10 s)');

      final vazia = PresencaEstafeta.fromRow(const {});
      expect(vazia.ligado, isFalse);
      expect(vazia.gpsFresco, isTrue, reason: 'sem a coluna não se inventa alarme');
      expect(vazia.aparelhos, 0);
      expect(textoUltimoSinal(null, agora), 'nunca');
    });
  });

  group('ganhos por período (dias de Lisboa)', () {
    // Domingo 15/11/2026 ao meio-dia (inverno: Lisboa = UTC).
    final agora = DateTime.utc(2026, 11, 15, 12);
    final trabalhos = [
      TrabalhoGanho(tipo: 'entrega', quando: DateTime.utc(2026, 11, 15, 9), ganhouCents: 500),
      TrabalhoGanho(tipo: 'entrega', quando: DateTime.utc(2026, 11, 10, 18), ganhouCents: 320),
      TrabalhoGanho(tipo: 'corrida', quando: DateTime.utc(2026, 11, 5, 12), ganhouCents: 410),
      TrabalhoGanho(tipo: 'entrega', quando: DateTime.utc(2026, 10, 31, 23, 30), ganhouCents: 999),
      TrabalhoGanho(tipo: 'entrega', quando: DateTime.utc(2026, 11, 15, 10)),
      const TrabalhoGanho(tipo: 'entrega', ganhouCents: 777),
    ];

    test('Hoje, Esta semana, Semana passada e Este mês', () {
      final hoje = trabalhosDoPeriodo(trabalhos, PeriodoEntregas.hoje, agora);
      expect(hoje.length, 2);
      expect(totalGanhoCents(hoje), 500);
      expect(trabalhosSemValor(hoje), 1, reason: 'o sem valor fica fora do total');

      final semana = trabalhosDoPeriodo(trabalhos, PeriodoEntregas.estaSemana, agora);
      expect(semana.length, 3);
      expect(totalGanhoCents(semana), 820);

      final passada = trabalhosDoPeriodo(trabalhos, PeriodoEntregas.semanaPassada, agora);
      expect(passada.length, 1);
      expect(totalGanhoCents(passada), 410);

      final mes = trabalhosDoPeriodo(trabalhos, PeriodoEntregas.esteMes, agora);
      expect(mes.length, 4, reason: '31/10 fica fora; sem data nunca entra');
      expect(totalGanhoCents(mes), 1230);
    });

    test('o extrato do servidor: lê os trabalhos e recusa resposta sem ok', () {
      final e = ExtratoGanhos.fromJson(const {
        'ok': true,
        'trabalhos': [
          {
            'tipo': 'entrega',
            'quando': '2026-11-15T09:00:00+00:00',
            'quando_txt': '15/11 09:00',
            'descricao': 'Entrega Pizzaria Central',
            'pagamento': 'cash',
            'ganhou_cents': 450,
            'cliente_pagou_cents': 1890,
          },
          {'tipo': 'corrida', 'ganhou_cents': null},
          'lixo',
        ],
      });
      expect(e.trabalhos.length, 2);
      expect(e.trabalhos.first.ganhouCents, 450);
      expect(e.trabalhos.first.emDinheiro, isTrue);
      expect(e.trabalhos.first.quandoTxt, '15/11 09:00');
      expect(e.trabalhos.last.ganhouCents, isNull, reason: 'nunca se finge zero');

      expect(
        () => ExtratoGanhos.fromJson(const {'ok': false, 'error': 'forbidden'}),
        throwsA(isA<AreaEstafetaErro>()
            .having((x) => x.mensagem, 'mensagem', contains('sem permissão de admin'))),
      );
      expect(() => ExtratoGanhos.fromJson('lixo'), throwsA(isA<AreaEstafetaErro>()));
    });
  });

  group('pedidos', () {
    test('código curto igual ao do servidor', () {
      expect(codigoPedido(_idEspera), 'BBBBBB');
      expect(codigoPedido('abc'), 'ABC');
    });

    test('os dele (id de login ou drivers.id antigo) e os que esperam entregador', () {
      final todos = [
        const PedidoAberto(id: 'p-dele', status: 'driverAccepted', entregadorId: _driverId),
        const PedidoAberto(id: 'p-outro', status: 'onTheWay', entregadorId: 'outro'),
        const PedidoAberto(id: 'p-retirar', status: 'callingDriver', tipoServico: 'takeaway'),
        PedidoAberto(id: 'p-novo', status: 'created', criadoEm: DateTime.utc(2026, 11, 15, 9)),
        PedidoAberto(id: 'p-preparo', status: 'preparing', criadoEm: DateTime.utc(2026, 11, 15, 9, 10)),
        PedidoAberto(id: 'p-chama-2', status: 'callingDriver', criadoEm: DateTime.utc(2026, 11, 15, 9, 20)),
        PedidoAberto(id: 'p-chama-1', status: 'callingDriver', criadoEm: DateTime.utc(2026, 11, 15, 9, 5)),
      ];
      expect(pedidosDele(todos, userId: _userId, driverId: _driverId).map((p) => p.id),
          ['p-dele']);
      expect(pedidosEsperandoEntregador(todos).map((p) => p.id),
          ['p-chama-1', 'p-chama-2', 'p-preparo', 'p-novo'],
          reason: 'retirar na loja não leva entregador; os que já chamam vêm primeiro');
    });

    test('devolver à fila só antes de ele ter a encomenda', () {
      expect(motivoSemDevolverAFila(const PedidoAberto(id: 'a', status: 'driverAccepted')),
          isNull);
      expect(motivoSemDevolverAFila(const PedidoAberto(id: 'a', status: 'pickedUp')),
          contains('já está com a encomenda'));
      expect(motivoSemDevolverAFila(const PedidoAberto(id: 'a', status: 'preparing')),
          isNotNull);
    });

    test('avisos antes de dar: agendado, ainda não pronto e ele sem sinal', () {
      final agora = DateTime.utc(2026, 11, 15, 12);
      final agendado = PedidoAberto(
          id: 'a', status: 'preparing', agendadoPara: DateTime.utc(2026, 11, 15, 20, 30));
      final aviso = avisoAntesDeDar(agendado, agora: agora)!;
      expect(aviso, contains('Pedido agendado para 15/11 20:30'));
      expect(aviso, contains('fica reservado para ele'));

      const pronto = PedidoAberto(id: 'b', status: 'callingDriver');
      expect(
          avisoAntesDeDar(pronto,
              presenca: const PresencaEstafeta(ligado: true, ligadoAgora: true),
              agora: agora),
          isNull);
      expect(
          avisoAntesDeDar(pronto,
              presenca: const PresencaEstafeta(ligado: false, ligadoAgora: false),
              agora: agora),
          contains('Desligado'));
    });

    test('a hora dos agendados vem de admin_scheduled_orders', () {
      final m = horasAgendadasDaResposta([
        {'id': 'x', 'scheduled_for': '2026-11-15T20:30:00+00:00'},
        {'id': null, 'scheduled_for': '2026-11-15T20:30:00+00:00'},
        'lixo',
      ]);
      expect(m.keys, ['x']);
      expect(m['x'], DateTime.utc(2026, 11, 15, 20, 30));
      expect(horasAgendadasDaResposta(null), isEmpty);
    });

    test('respostas do servidor em palavras simples', () {
      expect(mensagemDoServidor(const {'ok': false, 'error': 'estafeta_ja_tem_a_encomenda'}),
          contains('já tem a encomenda'));
      expect(
          mensagemDoServidor(
              const {'ok': false, 'error': 'pedido_ja_terminal', 'status': 'delivered'}),
          'o pedido já terminou (Entregue).');
      expect(
          mensagemDoServidor(const {
            'ok': false,
            'motivo': 'Está desligado (botão desligado) — não há aviso para enviar.'
          }),
          'Está desligado (botão desligado) — não há aviso para enviar.');
      expect(mensagemDoServidor(const {'ok': false, 'motivo': 'nada_a_pedir'}),
          'não falta nenhum documento para pedir.');
      expect(mensagemDoServidor(const {}), 'o servidor não confirmou.');
    });

    test('motivo mínimo de 3 letras', () {
      expect(motivoSuficiente(null), isFalse);
      expect(motivoSuficiente('  ab  '), isFalse);
      expect(motivoSuficiente('abc'), isTrue);
    });

    test('posição dele no Google Maps', () {
      final pos = posicaoDoEntregador([
        {'driver_id': 'outro', 'latitude': 1, 'longitude': 2},
        {
          'driver_id': _userId,
          'latitude': '40.5373',
          'longitude': -7.2676,
          'last_updated': '2026-11-15T12:00:00Z',
        },
      ], userId: _userId, driverId: _driverId);
      expect(pos, isNotNull);
      expect(pos!.linkMaps.toString(),
          'https://www.google.com/maps/search/?api=1&query=40.5373,-7.2676');
      expect(posicaoDoEntregador(const [], userId: _userId, driverId: _driverId), isNull);
    });
  });

  group('o que o admin já fez por ele', () {
    test('junta as duas fontes sem repetidos, mais recentes primeiro', () {
      final a = [
        RegistoAdmin(
          quando: DateTime.utc(2026, 11, 15, 10, 0, 0, 100),
          acao: 'order_reassigned',
          pedidoId: 'p1',
          detalhes: const {'para': _userId, 'motivo': 'cliente com pressa'},
        ),
        // A mesma ação gravada duas vezes na mesma transação.
        RegistoAdmin(
          quando: DateTime.utc(2026, 11, 15, 10, 0, 0, 900),
          acao: 'order_reassigned',
          pedidoId: 'p1',
        ),
      ];
      final b = [
        RegistoAdmin(quando: DateTime.utc(2026, 11, 15, 11), acao: 'driver_avisado_gps'),
        const RegistoAdmin(acao: 'sem_data'),
      ];
      final l = juntarHistorico(a, b);
      expect(l.map((r) => r.acao), ['driver_avisado_gps', 'order_reassigned', 'sem_data']);
    });

    test('nomes das ações em PT-BR, a dizer se foi para ele ou dele', () {
      const ids = {_userId, _driverId};
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(acao: 'order_reassigned', detalhes: {'para': _userId}),
              idsDele: ids),
          'Pedido dado a ele (painel)');
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(acao: 'order_reassigned', detalhes: {'de': _driverId}),
              idsDele: ids),
          'Pedido passado para outro entregador (painel)');
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(
                  acao: 'area_estafeta_modo_trabalho', detalhes: {'depois': 'rides_only'}),
              idsDele: ids),
          contains('Só corridas de passageiros'));
    });

    test('linha do log: pedido, quem e motivo', () {
      final r = RegistoAdmin.doRegisto(const {
        'created_at': '2026-11-15T10:00:00+00:00',
        'action': 'entregue_sem_codigo',
        'admin_email': 'admin@bora.pt',
        'entity_type': 'order',
        'entity_id_text': 'abcdef12-0000-4000-8000-000000000003',
        'details': {'motivo': 'cliente confirmou'},
      });
      expect(r.pedidoId, 'abcdef12-0000-4000-8000-000000000003');
      final linha = linhaDoHistorico(r, idsDele: const {_userId});
      expect(linha, contains('15/11 10:00'));
      expect(linha, contains('pedido ABCDEF'));
      expect(linha, contains('por admin@bora.pt'));
      expect(linha, contains('motivo: cliente confirmou'));
    });

    test('ligado/desligado e "Recolhi"/"A caminho" pelo painel', () {
      const ids = {_userId, _driverId};
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(acao: 'driver_set_online', detalhes: {'depois': true}),
              idsDele: ids),
          'Ligado pelo painel');
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(acao: 'driver_set_online', detalhes: {'depois': false}),
              idsDele: ids),
          'Desligado pelo painel');
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(
                  acao: 'order_estafeta_avancar',
                  detalhes: {'de': 'driverAccepted', 'para': 'pickedUp'}),
              idsDele: ids),
          'Pedido marcado "Recolhi" (painel)');
      expect(
          rotuloRegistoAdmin(
              const RegistoAdmin(
                  acao: 'order_estafeta_avancar',
                  detalhes: {'de': 'pickedUp', 'para': 'onTheWay'}),
              idsDele: ids),
          'Pedido marcado "A caminho" (painel)');
    });
  });

  group('ligar, desligar, "Recolhi" e "A caminho": respostas do servidor', () {
    test('recusas em palavras simples, sem nomes técnicos', () {
      expect(
        mensagemDaRecusa(const {
          'ok': false,
          'error': 'SEM_SINAL',
          'ultimo_sinal': '2026-11-15T13:58:00+00:00',
          'mensagem': 'O celular dele não deu sinal nos últimos 2 minutos.',
        }),
        'O celular dele não está mandando sinal agora: peça para ele abrir o app. '
        'Último sinal: 15/11 13:58 (hora de Lisboa).',
      );
      expect(
          mensagemDaRecusa(
              const {'ok': false, 'error': 'SEM_SINAL', 'ultimo_sinal': null}),
          endsWith('Ele nunca mandou sinal.'));
      expect(
        mensagemDaRecusa(const {
          'ok': false,
          'error': 'CONTA_NAO_APROVADA',
          'faltas': ['foto do documento', 'matrícula'],
        }),
        'O cadastro dele ainda não foi aprovado. Falta: foto do documento, matrícula.',
      );
      expect(
        mensagemDaRecusa(const {
          'ok': false,
          'error': 'DOCUMENTO_EXPIRADO',
          'mensagem': 'O servidor recusou: Carta de condução expirada.',
        }),
        startsWith('Ele tem um documento vencido (Carta de condução expirada):'),
      );
      expect(
          mensagemDaRecusa(
              const {'ok': false, 'error': 'invalid_status', 'status': 'cancelled'}),
          'O pedido agora está em "Cancelado". Atualize a lista e veja de novo.');
      expect(
        mensagemDaRecusa(const {
          'ok': false,
          'error': 'sem_estafeta',
          'mensagem': 'Este pedido não tem entregador. Use "Passar pedido" '
              '(nome_tecnico_da_funcao).',
        }),
        'Este pedido não tem entregador.',
      );
      expect(
        mensagemDaRecusa(const {
          'ok': false,
          'error': 'concurrent_transition',
          'mensagem': 'O pedido mudou nesse meio tempo (nome_tecnico_da_funcao). '
              'Atualize e tente de novo.',
        }),
        'O pedido mudou nesse meio tempo. Atualize e tente de novo.',
        reason: 'sem frase própria: a do servidor, sem o nome técnico',
      );
      expect(mensagemDaRecusa(const {'ok': false, 'error': 'resposta_vazia'}),
          'O servidor não respondeu.');
    });

    test('o que se diz depois de ligar ou desligar', () {
      expect(
        textoLigouDesligou(
            const {'ok': true, 'antes': true, 'depois': false, 'pedidos_em_curso': 2},
            nome: 'João',
            ligar: false),
        'João foi desligado: não recebe pedidos novos. Ele tem 2 pedido(s) em '
        'andamento: continuam com ele.',
      );
      expect(
          textoLigouDesligou(const {'ok': true, 'antes': false, 'depois': false},
              nome: 'João', ligar: false),
          'João já estava desligado.');
      expect(
          textoLigouDesligou(
              const {'ok': true, 'antes': true, 'depois': true, 'nada_mudou': true},
              nome: 'João',
              ligar: true),
          'João já estava ligado.');
      final ligou = textoLigouDesligou(const {
        'ok': true,
        'antes': false,
        'depois': true,
        'avisos': ['Ficou online, mas sem notificações ativas (nome_tecnico_da_funcao).'],
      }, nome: 'João', ligar: true);
      expect(ligou, startsWith('João está ligado'));
      expect(ligou, endsWith('Ficou online, mas sem notificações ativas.'));
    });

    test('ligar só quando está desligado; desligar só quando está ligado', () {
      const desligado = PresencaEstafeta(ligado: false, ligadoAgora: false);
      const ligado = PresencaEstafeta(ligado: true, ligadoAgora: true, pedidosEmCurso: 1);
      expect(podeLigarPorEle(desligado), isTrue);
      expect(podeDesligarPorEle(desligado), isFalse);
      expect(podeLigarPorEle(ligado), isFalse);
      expect(podeDesligarPorEle(ligado), isTrue);
      expect(podeLigarPorEle(null), isTrue, reason: 'sem dados, o servidor decide');
      expect(podeDesligarPorEle(null), isTrue);
      expect(avisoAntesDeDesligar(ligado), contains('1 pedido(s) em andamento'));
      expect(avisoAntesDeDesligar(desligado), isNull);
    });

    test('o próximo passo: aceito → Recolhi; retirado → A caminho; o resto, nenhum', () {
      expect(proximoPasso('driverAccepted'), ProximoPasso.recolhi);
      expect(ProximoPasso.recolhi.status, 'pickedUp');
      expect(proximoPasso('pickedUp'), ProximoPasso.aCaminho);
      expect(ProximoPasso.aCaminho.status, 'onTheWay');
      for (final s in [
        'created',
        'preparing',
        'callingDriver',
        'onTheWay',
        'delivered',
        'cancelled',
      ]) {
        expect(proximoPasso(s), isNull, reason: s);
      }
      expect(
        textoAvancou(const {'ok': true, 'status': 'pickedUp', 'de': 'driverAccepted'},
            codigo: 'CCCCCC', passo: ProximoPasso.recolhi),
        'Pedido CCCCCC marcado como "Retirado na loja (está com ele)".',
      );
      expect(
        textoAvancou(const {'ok': true, 'status': 'onTheWay', 'idempotent': true},
            codigo: 'CCCCCC', passo: ProximoPasso.aCaminho),
        'O pedido CCCCCC já estava em "A caminho do cliente": nada mudou.',
      );
    });
  });

  group('fatura do mês', () {
    test('este mês e mês passado pelo calendário de Lisboa', () {
      // 31/03 23:30 UTC já é 1 de abril em Lisboa (horário de verão desde 29/03).
      final virada = DateTime.utc(2026, 3, 31, 23, 30);
      expect(mesParaServidor(primeiroDiaDoMes(MesFatura.esteMes, virada)), '2026-04-01');
      expect(mesParaServidor(primeiroDiaDoMes(MesFatura.mesPassado, virada)), '2026-03-01');
      // Em janeiro, o mês passado é dezembro do ano anterior.
      expect(
          mesParaServidor(
              primeiroDiaDoMes(MesFatura.mesPassado, DateTime.utc(2026, 1, 10, 12))),
          '2025-12-01');
      expect(
          mesParaServidor(
              primeiroDiaDoMes(MesFatura.esteMes, DateTime.utc(2026, 11, 30, 23, 30))),
          '2026-11-01',
          reason: 'no inverno Lisboa = UTC: ainda é dia 30');
    });

    test('lê a resposta: euros viram cêntimos; sem entregas não há recibo', () {
      final f = FaturaDoMes.fromJson(_faturaJson());
      expect(f.temEntregas, isTrue);
      expect(f.totalCents, 2490);
      expect(f.entregas, 5);
      expect(f.mesTexto, 'novembro de 2026');
      expect(f.paraQuem, 'Bora Teste Lda (NIF 500000000)');
      expect(f.nif, '123456789');
      expect(f.notas, hasLength(3));
      expect(textoReciboPassado(f), 'Ainda não');

      final emitido = FaturaDoMes.fromJson(_faturaJson(extra: const {
        'recibo_passado': true,
        'recibo_numero': 7,
        'recibo_data': '2026-12-05',
        'marcado_em': '2026-12-05T10:00:00+00:00',
      }));
      expect(textoReciboPassado(emitido),
          'Sim, n.º 7, de 05/12/2026 (marcado em 05/12 10:00)');

      final vazia = FaturaDoMes.fromJson(_faturaJson(comEntregas: false));
      expect(vazia.temEntregas, isFalse);
      expect(vazia.totalCents, isNull);
      expect(vazia.mesTexto, 'outubro de 2026');
      expect(vazia.paraQuem, 'Bora Teste Lda (NIF 500000000)',
          reason: 'sem linha dele, a quem emitir vem do adquirente');
      expect(() => FaturaDoMes.fromJson('lixo'), throwsA(isA<AreaEstafetaErro>()));
    });
  });

  group('ecrã', () {
    testWidgets('as 6 secções aparecem com os dados do servidor', (t) async {
      final falso = await _abrir(t);
      for (final titulo in [
        'Agora',
        'Pedidos dele agora',
        'Dar um pedido a ele',
        'Ganhos',
        'Conta e documentos',
        'O que o admin já fez por ele',
      ]) {
        expect(find.text(titulo), findsOneWidget, reason: titulo);
      }
      expect(find.text('Ligado, GPS há 12 s'), findsOneWidget);
      expect(find.byKey(const Key('area_ver_mapa')), findsOneWidget);
      expect(find.text('AAAAAA'), findsOneWidget, reason: 'o pedido dele');
      expect(find.text('BBBBBB'), findsOneWidget, reason: 'o pedido à espera');
      expect(find.text('Pedido agendado? Confira a hora antes.'), findsOneWidget);
      expect(find.text('Falta o IBAN para receber.'), findsOneWidget);
      expect(find.textContaining('Aviso de GPS enviado para o celular'), findsOneWidget);
      expect(
        falso.chamadas,
        containsAll(<String>[
          'presenca:$_driverId',
          'pedidos',
          'ganhos:$_userId',
          'conta:$_userId',
          'modo_ler:$_driverId',
          'historico:$_userId:$_driverId',
        ]),
      );
    });

    testWidgets('ganho em número grande; o valor do cliente só em dinheiro', (t) async {
      await _abrir(t);
      expect(t.widget<Text>(find.byKey(const Key('area_total_ganhos'))).data, '8,30 €');
      expect(find.text('Cliente pagou em dinheiro: 18,90 €'), findsOneWidget);
      expect(find.textContaining('25,00'), findsNothing,
          reason: 'pago com cartão: o valor do cliente não aparece');

      await _tocar(t, find.byKey(const Key('area_periodo_semanaPassada')));
      expect(t.widget<Text>(find.byKey(const Key('area_total_ganhos'))).data, '0,00 €');
    });

    testWidgets('"Dar este pedido a ele" pede motivo e manda o id de login dele',
        (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_dar_$_idEspera')));
      expect(find.text('Dar o pedido BBBBBB a João Teste?'), findsOneWidget);

      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull,
          reason: 'sem motivo não confirma');
      await t.enterText(find.byKey(const Key('area_motivo')), 'ok');
      await t.pump();
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull,
          reason: 'menos de 3 letras não chega');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Cliente ligou com pressa');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas,
          contains('atribuir:$_idEspera:$_userId:Cliente ligou com pressa'));
      expect(find.textContaining('dado a João Teste'), findsOneWidget);
    });

    testWidgets('"Passar para outro entregador" escolhe outro (nunca ele) com motivo',
        (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_passar_$_idDele')));
      expect(falso.chamadas, contains('outros:$_idDele'));
      expect(find.byKey(const Key('area_outro_$_userId')), findsNothing,
          reason: 'ele não aparece na lista para quem passar');

      await _tocar(t, find.byKey(const Key('area_outro_outro-1')));
      expect(find.text('Passar o pedido AAAAAA para Maria Outra?'), findsOneWidget);
      expect(find.byKey(const Key('area_motivo_aviso')), findsOneWidget,
          reason: 'ele já recolheu: o aviso diz que o outro vai buscar com ele');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Mota avariou');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('atribuir:$_idDele:outro-1:Mota avariou'));
    });

    testWidgets('com a encomenda: "Devolver à fila" desligado e diz porquê', (t) async {
      await _abrir(t);
      expect(_botao(t, 'area_devolver_$_idDele').onPressed, isNull);
      expect(find.text('Ele já está com a encomenda: não dá para devolver à fila.'),
          findsOneWidget);
      expect(find.byKey(const Key('btn_entregue_sem_codigo')), findsOneWidget);
    });

    testWidgets('"Marcar entregue sem código" passa pelo serviço e fica ligado a ele',
        (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('btn_entregue_sem_codigo')));
      await t.enterText(
          find.byKey(const Key('motivo_sem_codigo')), 'Cliente confirmou por telefone');
      await t.tap(find.byKey(const Key('confirmar_sem_codigo')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('sem_codigo:$_idDele:Cliente confirmou por telefone'));
      expect(falso.chamadas,
          contains('auditoria:entregue_sem_codigo:$_driverId:Cliente confirmou por telefone'));
    });

    testWidgets('aviso de GPS: confirma e chama o servidor', (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_aviso_gps')));
      await t.tap(find.byKey(const Key('area_confirmar')));
      await t.pumpAndSettle();
      expect(falso.chamadas, contains('aviso_gps:$_driverId'));
    });

    testWidgets('modo de trabalho: pede motivo e grava o motivo na auditoria', (t) async {
      final falso = await _abrir(t);
      expect(_botao(t, 'area_modo_everything').onPressed, isNull,
          reason: 'já está em "Tudo"');
      await _tocar(t, find.byKey(const Key('area_modo_rides_only')));
      await t.enterText(find.byKey(const Key('area_motivo')), 'Só quer fazer corridas');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('modo:$_driverId:rides_only'));
      expect(falso.chamadas,
          contains('auditoria:modo_trabalho:$_driverId:Só quer fazer corridas'));
    });

    testWidgets('quem não faz corridas de passageiros não muda de modo', (t) async {
      await _abrir(t,
          falso: _Falso(modo: const ModoTrabalho(modo: 'everything', veiculo: 'motorcycle')));
      expect(find.byKey(const Key('area_modo_rides_only')), findsNothing);
      expect(find.textContaining('Só se muda para quem faz corridas de passageiros'),
          findsOneWidget);
    });

    testWidgets('o que ainda não existe no servidor fica desligado e diz porquê',
        (t) async {
      await _abrir(t);
      expect(find.text(kFrasePrecisaFuncaoNova), findsOneWidget,
          reason: 'só falta "Enviar documento por ele" (Conta e documentos)');
      expect(find.byKey(const Key('area_enviar_documento')), findsOneWidget);
      expect(_botao(t, 'area_enviar_documento').onPressed, isNull);
      // As três que já têm função no servidor (15/11 15:06) estão ligadas.
      for (final chave in [
        'area_desligar_por_ele',
        'area_a_caminho_$_idDele',
        'area_fatura_mes',
      ]) {
        expect(find.byKey(Key(chave)), findsOneWidget, reason: chave);
        expect(_botao(t, chave).onPressed, isNotNull, reason: chave);
      }
      expect(_botao(t, 'area_ligar_por_ele').onPressed, isNull,
          reason: 'ele já está ligado: só dá para desligar');
      expect(find.byKey(const Key('area_recolhi_$_idDele')), findsNothing,
          reason: 'já recolheu: o passo seguinte é "A caminho"');
    });

    testWidgets('"Desligar por ele": pede motivo, avisa dos pedidos e manda o drivers.id',
        (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_desligar_por_ele')));
      expect(find.text('Desligar João Teste agora?'), findsOneWidget);
      expect(find.textContaining('1 pedido(s) em andamento'), findsOneWidget);
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull,
          reason: 'sem motivo não confirma');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Esqueceu o app ligado');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('online:$_driverId:false:Esqueceu o app ligado'));
      expect(find.textContaining('João Teste foi desligado'), findsOneWidget);
      expect(falso.chamadas.where((c) => c.startsWith('auditoria:')), isEmpty,
          reason: 'o servidor já grava no log com o motivo');
    });

    testWidgets('"Ligar por ele": a recusa do servidor aparece em palavras simples',
        (t) async {
      final falso = await _abrir(t,
          falso: _Falso(
            ligado: false,
            respostaLigar: const {
              'ok': false,
              'error': 'SEM_SINAL',
              'ultimo_sinal': '2026-11-14T13:58:00+00:00',
              'mensagem': 'O celular dele não deu sinal nos últimos 2 minutos.',
            },
          ));
      expect(find.text('Desligado'), findsOneWidget);
      expect(_botao(t, 'area_ligar_por_ele').onPressed, isNotNull);
      expect(_botao(t, 'area_desligar_por_ele').onPressed, isNull,
          reason: 'já está desligado');

      await _tocar(t, find.byKey(const Key('area_ligar_por_ele')));
      expect(find.text('Ligar João Teste agora?'), findsOneWidget);
      await t.enterText(find.byKey(const Key('area_motivo')), 'ab');
      await t.pump();
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull,
          reason: 'menos de 3 letras não chega');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Pediu por telefone');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('online:$_driverId:true:Pediu por telefone'));
      expect(
          find.textContaining(
              'O celular dele não está mandando sinal agora: peça para ele abrir o app.'),
          findsOneWidget);
      expect(find.textContaining('Último sinal: 14/11 13:58'), findsOneWidget);
    });

    testWidgets('"Recolhi" e "A caminho": só o passo certo de cada pedido', (t) async {
      await _abrir(t,
          falso: _Falso(pedidos: const [
            PedidoAberto(id: _idAceito, status: 'driverAccepted', entregadorId: _userId),
            PedidoAberto(id: _idDele, status: 'pickedUp', entregadorId: _driverId),
            PedidoAberto(id: _idACaminho, status: 'onTheWay', entregadorId: _userId),
          ]));
      expect(_botao(t, 'area_recolhi_$_idAceito').onPressed, isNotNull);
      expect(find.byKey(const Key('area_a_caminho_$_idAceito')), findsNothing);
      expect(_botao(t, 'area_a_caminho_$_idDele').onPressed, isNotNull);
      expect(find.byKey(const Key('area_recolhi_$_idDele')), findsNothing);
      expect(find.byKey(const Key('area_recolhi_$_idACaminho')), findsNothing);
      expect(find.byKey(const Key('area_a_caminho_$_idACaminho')), findsNothing,
          reason: 'já está a caminho: falta só entregar');
    });

    testWidgets('"Recolhi": avisa do dinheiro na loja, pede motivo e chama o servidor',
        (t) async {
      final falso = await _abrir(t,
          falso: _Falso(pedidos: const [
            PedidoAberto(
              id: _idAceito,
              status: 'driverAccepted',
              loja: 'Mercado do Bairro',
              entregadorId: _userId,
            ),
          ]));
      await _tocar(t, find.byKey(const Key('area_recolhi_$_idAceito')));
      expect(find.text('Marcar "Recolhi" no pedido CCCCCC?'), findsOneWidget);
      expect(
          t.widget<Text>(find.byKey(const Key('area_motivo_aviso'))).data,
          'Em pedido a dinheiro com pagamento na loja, marcar Recolhi registra a '
          'compra como paga.');
      expect(_botao(t, 'area_motivo_confirmar').onPressed, isNull,
          reason: 'sem motivo não confirma');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Loja confirmou a recolha');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('avancar:$_idAceito:pickedUp:Loja confirmou a recolha'));
      expect(find.text('Pedido CCCCCC marcado como "Retirado na loja (está com ele)".'),
          findsOneWidget);
      expect(falso.chamadas.where((c) => c.startsWith('auditoria:')), isEmpty,
          reason: 'o servidor já grava no log com o motivo');
    });

    testWidgets('"A caminho" recusado: diz porquê, sem nomes técnicos', (t) async {
      final falso = await _abrir(t,
          falso: _Falso(respostaAvancar: const {
            'ok': false,
            'error': 'invalid_status',
            'status': 'cancelled',
            'mensagem': 'O pedido está em "cancelled"; para ir para "onTheWay" tem que '
                'estar em "pickedUp".',
          }));
      await _tocar(t, find.byKey(const Key('area_a_caminho_$_idDele')));
      expect(find.text('Marcar "A caminho" no pedido AAAAAA?'), findsOneWidget);
      expect(find.byKey(const Key('area_motivo_aviso')), findsNothing,
          reason: 'o aviso do dinheiro é só do "Recolhi"');

      await t.enterText(find.byKey(const Key('area_motivo')), 'Saiu da loja');
      await t.pump();
      await t.tap(find.byKey(const Key('area_motivo_confirmar')));
      await t.pumpAndSettle();

      expect(falso.chamadas, contains('avancar:$_idDele:onTheWay:Saiu da loja'));
      expect(find.textContaining('O pedido agora está em "Cancelado"'), findsOneWidget);
      expect(find.textContaining('onTheWay'), findsNothing);
    });

    testWidgets('"Fatura do mês" (Conta e documentos): este mês e mês passado, só leitura',
        (t) async {
      final falso = await _abrir(t);
      await _tocar(t, find.byKey(const Key('area_fatura_mes')));
      final agora = DateTime.now();
      final esteMes = mesParaServidor(primeiroDiaDoMes(MesFatura.esteMes, agora));
      final mesPassado = mesParaServidor(primeiroDiaDoMes(MesFatura.mesPassado, agora));

      expect(falso.chamadas, contains('fatura:$_userId:$esteMes'));
      expect(t.widget<Text>(find.byKey(const Key('area_fatura_total'))).data, '24,90 €');
      expect(find.text('5 entrega(s) no mês'), findsOneWidget);
      expect(find.textContaining('Bora Teste Lda (NIF 500000000)'), findsOneWidget);
      expect(find.textContaining('Mês ainda em andamento'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsOneWidget,
        reason: 'só leitura: o único botão é "Fechar"',
      );

      await _tocar(t, find.byKey(const Key('area_fatura_mesPassado')));
      expect(falso.chamadas, contains('fatura:$_userId:$mesPassado'));
      expect(find.byKey(const Key('area_fatura_vazia')), findsOneWidget);
      expect(find.byKey(const Key('area_fatura_total')), findsNothing);

      await _tocar(t, find.byKey(const Key('area_fatura_fechar')));
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('as funções novas (SDK verdadeiro, servidor de mentira)', () {
    test('ligar/desligar, "Recolhi" e fatura: nome da função e parâmetros', () async {
      final pedidos = <http.Request>[];
      final s = AdminAreaEstafetaSupabase(
        client: _servidorDeMentira(pedidos, (r) {
          if (r.url.path.endsWith('/rpc/admin_fatura_mes_estafeta')) return _faturaJson();
          if (r.url.path.endsWith('/rpc/admin_set_driver_online')) {
            return const {'ok': false, 'error': 'SEM_SINAL', 'ultimo_sinal': null};
          }
          return const {'ok': true, 'status': 'pickedUp', 'de': 'driverAccepted'};
        }),
      );

      final ligar =
          await s.ligarDesligar(driverId: _driverId, ligar: true, motivo: 'Pediu por telefone');
      expect(pedidos.last.url.path, endsWith('/rpc/admin_set_driver_online'));
      expect(jsonDecode(pedidos.last.body),
          {'p_driver': _driverId, 'p_online': true, 'p_motivo': 'Pediu por telefone'},
          reason: 'o drivers.id (a função aceita também o id de login)');
      expect(mensagemDaRecusa(ligar), startsWith('O celular dele não está mandando sinal'));

      await s.ligarDesligar(driverId: _driverId, ligar: false, motivo: 'Fim do turno');
      expect(jsonDecode(pedidos.last.body),
          {'p_driver': _driverId, 'p_online': false, 'p_motivo': 'Fim do turno'});

      final avancou =
          await s.avancarPedido(orderId: _idAceito, status: 'pickedUp', motivo: 'Loja confirmou');
      expect(pedidos.last.url.path, endsWith('/rpc/admin_estafeta_avancar'));
      expect(jsonDecode(pedidos.last.body),
          {'p_order_id': _idAceito, 'p_status': 'pickedUp', 'p_motivo': 'Loja confirmou'});
      expect(avancou['ok'], isTrue);

      final fatura = await s.faturaDoMes(userId: _userId, mes: DateTime.utc(2026, 10, 1));
      expect(pedidos.last.url.path, endsWith('/rpc/admin_fatura_mes_estafeta'));
      expect(jsonDecode(pedidos.last.body), {'p_user_id': _userId, 'p_mes': '2026-10-01'},
          reason: 'o id de login (uuid) e o 1.º dia do mês');
      expect(fatura.totalCents, 2490);

      expect(pedidos.where((p) => p.url.path.contains('admin_audit_log')), isEmpty,
          reason: 'nenhuma auditoria do lado da app: o servidor já grava');
    });

    test('o histórico lê "Recolhi"/"A caminho" pelo id de login gravado nos detalhes',
        () async {
      final pedidos = <http.Request>[];
      final s = AdminAreaEstafetaSupabase(
        client: _servidorDeMentira(pedidos, (r) {
          if (r.url.path.endsWith('/admin_audit_log') &&
              r.url.queryParameters['action'] == 'eq.order_estafeta_avancar') {
            return [
              {
                'created_at': '2026-11-15T14:05:00+00:00',
                'action': 'order_estafeta_avancar',
                'admin_email': 'admin@bora.pt',
                'entity_type': 'order',
                'entity_id_text': _idAceito,
                'details': {
                  'de': 'driverAccepted',
                  'para': 'pickedUp',
                  'motivo': 'Loja confirmou',
                  'estafeta_user_id': _userId,
                },
              },
            ];
          }
          return const <Object?>[];
        }),
      );

      final lista = await s.historico(userId: _userId, driverId: _driverId);
      final leitura = pedidos.singleWhere(
          (p) => p.url.queryParameters['action'] == 'eq.order_estafeta_avancar');
      expect(leitura.method, 'GET');
      expect(leitura.url.queryParameters['details->>estafeta_user_id'], 'eq.$_userId');
      expect(lista, hasLength(1));
      expect(
        linhaDoHistorico(lista.single, idsDele: const {_userId, _driverId}),
        allOf(
          contains('Pedido marcado "Recolhi" (painel)'),
          contains('pedido CCCCCC'),
          contains('por admin@bora.pt'),
          contains('motivo: Loja confirmou'),
        ),
      );
    });
  });

  group('regras do código', () {
    const ficheiros = [
      'lib/screens/admin/admin_area_estafeta_screen.dart',
      'lib/services/admin_area_estafeta_service.dart',
    ];

    test('só funções de admin auditadas: nada de ops_ nem escrita direta', () {
      for (final caminho in ficheiros) {
        final src = File(caminho).readAsStringSync();
        expect(RegExp(r'\bops_\w+').hasMatch(src), isFalse,
            reason: '$caminho chama funções ops_ (são dos agentes)');
        expect(
            RegExp(r'''from\(\s*['"]orders['"]\s*\)[^;]*\.(update|insert|delete|upsert)\(''')
                .hasMatch(src),
            isFalse,
            reason: '$caminho escreve em orders');
        expect(RegExp(r'''from\(\s*['"]orders['"]''').hasMatch(src), isFalse,
            reason: '$caminho mexe em orders direto (só pelas funções do servidor)');
        expect(RegExp(r'\.(update|insert|delete|upsert)\(').hasMatch(src), isFalse,
            reason: '$caminho escreve direto numa tabela');
        expect(RegExp(r'\.tr\b').hasMatch(src), isFalse,
            reason: '$caminho usa .tr (o painel é PT-BR fixo)');
      }
    });

    test('dar e passar usam admin_reassign_order com o motivo; auditoria pela app', () {
      final src = File(ficheiros[1]).readAsStringSync();
      expect(src, contains("'admin_reassign_order'"));
      expect(src, contains("'p_new_driver': novoEntregador"));
      expect(src, contains("'p_motivo': motivo"));
      expect(src, contains("'admin_release_order_driver'"));
      expect(src, contains('AdminAuditService.logAction('));
    });
  });
}
