import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/checkin/premio_opcoes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// Prémios dos marcos do check-in (Bloco D, 21/10/2026).
///
/// As regras vivem no servidor (provadas em transação desfeita, ver
/// .claude/.ai/missoes/fechar-pendencias-2026-10-20/d/prova_rollback_resultado.txt).
/// Aqui prova-se o que a app faz com as respostas REAIS dessas provas:
///  - os marcos 7/10/15/30, os dias que faltam e o próximo marco;
///  - a sequência que falha (volta ao dia 1);
///  - o tecto do mês (vale guardado) e a regra do pedido pago (falta 1 pedido);
///  - o artigo-prémio no carrinho: uma linha só, a 0 €, sem "+"; o total da
///    linha é 0 € (salgados) ou só os extras pagos (açaí).

Map<String, dynamic> _marcos({int dias = 10}) => {
      'ok': true,
      'marcos_ativos': true,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': dias == 0 ? 0 : ((dias - 1) % 30) + 1,
      'hoje_feito': true,
      'texto': 'Faz o check-in todos os dias.',
      'marcos': [
        {'chave': 'semana', 'dia': 7, 'tipo': 'tokens', 'titulo': 'os tokens do Dia 7', 'descricao': '', 'tokens': 40, 'atingido': dias >= 7, 'faltam': dias >= 7 ? 0 : 7 - dias},
        {'chave': 'salgados', 'dia': 10, 'tipo': 'produto', 'titulo': '2 salgados da Keli', 'descricao': '', 'atingido': dias >= 10, 'faltam': dias >= 10 ? 0 : 10 - dias},
        {'chave': 'acai', 'dia': 15, 'tipo': 'produto', 'titulo': 'um açaí do Goola', 'descricao': '', 'atingido': dias >= 15, 'faltam': dias >= 15 ? 0 : 15 - dias},
        {'chave': 'mes', 'dia': 30, 'tipo': 'servico', 'titulo': '2 horas de limpeza ou uma lavagem exterior do carro', 'descricao': '', 'atingido': dias >= 30, 'faltam': dias >= 30 ? 0 : 30 - dias},
      ],
      'proximo': {'chave': 'acai', 'dia': 15, 'titulo': 'um açaí do Goola', 'faltam': 5},
      'vales': <Map<String, dynamic>>[
        {
          'id': 'v-salgados', 'marco': 10, 'chave': 'salgados', 'tipo': 'produto', 'estado': 'por_usar',
          'titulo': '2 salgados da Keli', 'loja_id': 'sabores-brasil-guarda', 'loja_nome': 'Sabores do Brasil - Keli Barbosa',
          'produto_id': 'premio-checkin-salgados', 'quantidade': 1, 'opcoes': <String>[], 'valor_cents': 630,
          'valido_ate': '2026-11-20T05:00:00+00:00', 'visto': false, 'origem': 'checkin',
        },
      ],
      'novos': ['v-salgados'],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('marcos (resposta de client_checkin_premios)', () {
    test('dia 10: vale dos salgados por usar, próximo o açaí a 5 dias', () {
      final e = CheckinPremiosEstado.fromJson(_marcos());
      expect(e.marcosAtivos, isTrue);
      expect(e.diasSeguidos, 10);
      expect(e.diaMarco, 10);
      expect(e.marcos.map((m) => m.dia), [7, 10, 15, 30]);
      expect(e.marcos.firstWhere((m) => m.dia == 7).tokens, 40);
      expect(e.marcos.where((m) => m.atingido).map((m) => m.dia), [7, 10]);
      expect(e.proximo!.titulo, 'um açaí do Goola');
      expect(e.proximo!.faltam, 5);
      expect(e.proximo!.tipo, 'produto');
      expect(e.porUsar.single.titulo, '2 salgados da Keli');
      expect(e.novos, ['v-salgados']);
    });

    test('falhou um dia: a sequência volta ao dia 1 e o próximo marco é o dos 7 dias', () {
      final j = _marcos(dias: 1)
        ..['proximo'] = {'chave': 'semana', 'dia': 7, 'titulo': 'os tokens do Dia 7', 'faltam': 6}
        ..['vales'] = <Map<String, dynamic>>[]
        ..['novos'] = <String>[];
      final e = CheckinPremiosEstado.fromJson(j);
      expect(e.diaMarco, 1);
      expect(e.marcos.where((m) => m.atingido), isEmpty);
      expect(e.proximo!.faltam, 6);
      expect(e.proximo!.tipo, 'tokens');
    });

    test('depois do dia 30 o ciclo recomeça: dia 31 é o dia 1 dos marcos', () {
      final e = CheckinPremiosEstado.fromJson(_marcos(dias: 31));
      expect(e.diasSeguidos, 31);
      expect(e.diaMarco, 1);
    });

    test('tecto do mês e pedido pago: o ecrã diz o que falta', () {
      final guardado = CheckinVale.fromJson({
        'id': 'g', 'marco': 30, 'chave': 'mes', 'tipo': 'servico', 'estado': 'guardado',
        'titulo': '2 horas de limpeza ou uma lavagem exterior do carro', 'ativar_em': '2026-11-01',
        'opcoes': ['limpeza', 'lavagem'],
      });
      final espera = CheckinVale.fromJson({
        'id': 'e', 'marco': 30, 'chave': 'mes', 'tipo': 'servico', 'estado': 'a_espera_pedido',
        'titulo': 'x', 'esperar_ate': '2026-11-20T05:00:00+00:00', 'opcoes': ['limpeza', 'lavagem'],
      });
      expect(guardado.ativo, isTrue);
      expect(guardado.usavel, isFalse);
      expect(textoEstadoVale(guardado), 'Guardado');
      expect(espera.usavel, isFalse);
      expect(textoEstadoVale(espera), 'Falta 1 pedido para desbloquear o prémio');
      expect(guardado.opcoes, ['limpeza', 'lavagem']);
    });

    test('o vale para aplicar no carrinho é o da loja certa, o primeiro a acabar', () {
      final j = _marcos();
      (j['vales'] as List<Map<String, dynamic>>).addAll(<Map<String, dynamic>>[
        {'id': 'v2', 'marco': 10, 'chave': 'salgados', 'tipo': 'produto', 'estado': 'reservado', 'titulo': 'b',
         'loja_id': 'sabores-brasil-guarda', 'produto_id': 'premio-checkin-salgados', 'valido_ate': '2026-11-01T00:00:00Z'},
        {'id': 'v3', 'marco': 15, 'chave': 'acai', 'tipo': 'produto', 'estado': 'usado', 'titulo': 'c',
         'loja_id': 'goola-acai-guarda', 'produto_id': 'premio-checkin-acai'},
      ]);
      final e = CheckinPremiosEstado.fromJson(j);
      expect(e.valeParaLoja('sabores-brasil-guarda')!.id, 'v2');
      expect(e.valeParaLoja('goola-acai-guarda'), isNull, reason: 'o do açaí já foi usado');
      expect(e.valeParaLoja(null), isNull);
      expect(e.historico.single.id, 'v3');
    });

    test('erros do servidor em PT-PT simples', () {
      expect(mensagemErroPremio('lead_time_too_short (min 12 h)'), contains('12 horas'));
      expect(mensagemErroPremio('checkin_premio_sem_vale: x'), 'Este prémio já não está disponível.');
      expect(mensagemErroPremio('out_of_service_area (9.1 km)'), contains('fora da zona'));
      expect(mensagemErroPremio('qualquer'), 'Não foi possível usar o prémio. Tenta de novo.');
    });

    test('escada (29/10/2026): lê a resposta real do servidor', () {
      // Exemplo real de client_checkin_premios() a 29/10/2026.
      final j = _marcos(dias: 15)
        ..['ciclo_inicio'] = '2026-10-15'
        ..['escada'] = {
          'ativa': true,
          'texto': 'Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.',
          'decisao': null,
          'guardado': null,
          'levantados': 0,
          'ultimo_dia': 30,
          'proximo_maior': {'dia': 30, 'chave': 'mes', 'faltam': 15, 'titulo': '2 horas de limpeza ou uma lavagem exterior do carro', 'descricao': '...'},
          'pode_continuar': false,
          'pendente_decisao': false,
        };
      final e = CheckinPremiosEstado.fromJson(j);
      expect(e.diaMarco, 15);
      expect(e.hojeFeito, isTrue);
      expect(e.diaDeHoje, 15);
      expect(e.cicloInicio, DateTime(2026, 10, 15));
      expect(e.escadaAtiva, isTrue);
      final esc = e.escada!;
      expect(esc.texto, startsWith('Em cada sequência levas UM prémio'));
      expect(esc.guardado, isNull);
      expect(esc.decisao, isNull);
      expect(esc.pendenteDecisao, isFalse);
      expect(esc.podeContinuar, isFalse);
      expect(esc.ultimoDia, 30);
      expect(esc.levantados, 0);
      expect(esc.proximoMaior!.dia, 30);
      expect(esc.proximoMaior!.chave, 'mes');
      expect(esc.proximoMaior!.faltam, 15);
      expect(esc.temGuardadoSemEscolha, isFalse);
    });

    test('escada: prémio guardado à espera da escolha e depois de continuar', () {
      Map<String, dynamic> com(String decisao, bool pendente) => _marcos()
        ..['escada'] = {
          'ativa': true,
          'texto': 't',
          'guardado': {
            'chave': 'salgados', 'dia': 10, 'titulo': '2 salgados da Keli', 'tipo': 'produto', 'descricao': 'd',
            'guardado_em': '2026-10-29T10:00:00+00:00', 'garantido_ate': '2026-11-28T10:00:00+00:00',
          },
          'decisao': decisao,
          'pendente_decisao': pendente,
          'pode_continuar': true,
          'proximo_maior': {'chave': 'acai', 'dia': 15, 'titulo': 'um açaí do Goola', 'descricao': '', 'faltam': 5},
          'ultimo_dia': 30,
          'levantados': 2,
          'reinicio_data': '2026-10-01',
          'ultimo_vale_id': 'aaaaaaaa-0000-0000-0000-000000000001',
        };
      final p = CheckinPremiosEstado.fromJson(com('pendente', true)).escada!;
      expect(p.pendenteDecisao, isTrue);
      expect(p.decisao, 'pendente');
      expect(p.guardado!.chave, 'salgados');
      expect(p.guardado!.dia, 10);
      expect(p.guardado!.tipo, 'produto');
      expect(p.guardado!.guardadoEmTexto, '2026-10-29T10:00:00+00:00');
      expect(p.guardado!.garantidoAte!.toUtc(), DateTime.utc(2026, 11, 28, 10));
      expect(p.temGuardadoSemEscolha, isFalse);
      expect(p.levantados, 2);
      expect(p.reinicioData, DateTime(2026, 10, 1));
      expect(p.ultimoValeId, 'aaaaaaaa-0000-0000-0000-000000000001');
      final c = CheckinPremiosEstado.fromJson(com('continuar', false)).escada!;
      expect(c.decisao, 'continuar');
      expect(c.temGuardadoSemEscolha, isTrue);
    });

    test('sem escada (servidor antigo, null ou lixo): desligada e sem rebentar', () {
      final antigo = CheckinPremiosEstado.fromJson(_marcos());
      expect(antigo.escada, isNull);
      expect(antigo.escadaAtiva, isFalse);
      expect(antigo.cicloInicio, isNull);
      expect(CheckinPremiosEstado.fromJson(_marcos()..['escada'] = null).escada, isNull);
      expect(CheckinPremiosEstado.fromJson(_marcos()..['escada'] = 'x').escada, isNull);
      final semCampos = CheckinPremiosEstado.fromJson(_marcos()..['escada'] = <String, dynamic>{});
      expect(semCampos.escadaAtiva, isFalse);
      expect(semCampos.escada!.guardado, isNull);
      expect(semCampos.escada!.proximoMaior, isNull);
    });

    test('levantou hoje depois do check-in: dia_marco 0 com hoje feito, amanhã é o Dia 1', () {
      final e = CheckinPremiosEstado.fromJson(_marcos()
        ..['dia_marco'] = 0
        ..['hoje_feito'] = true);
      expect(e.diaDeHoje, 0);
      final porFazer = CheckinPremiosEstado.fromJson(_marcos()
        ..['dia_marco'] = 11
        ..['hoje_feito'] = false);
      expect(porFazer.diaDeHoje, 12);
      final fimDoCiclo = CheckinPremiosEstado.fromJson(_marcos()
        ..['dia_marco'] = 30
        ..['hoje_feito'] = false);
      expect(fimDoCiclo.diaDeHoje, 1, reason: 'depois do dia 30 vem o Dia 1, nunca o "dia 31 de 30"');
    });

    test('Levantar / Continuar: resultado tipado, erros em PT-PT e estado junto', () {
      final ok = CheckinEscadaResultado.fromJson({
        'ok': true,
        'vale': _marcos()['vales'][0],
        'estado': {'marcos_ativos': true, 'ciclo_dias': 30, 'dias_seguidos': 0, 'dia_marco': 0, 'hoje_feito': true,
                   'marcos': <Map<String, dynamic>>[], 'escada': {'ativa': true, 'texto': 'x', 'guardado': null}},
      });
      expect(ok.ok, isTrue);
      expect(ok.vale!.titulo, '2 salgados da Keli');
      expect(ok.estado!.diaDeHoje, 0);
      final junto = CheckinPremiosEstado.fromJson(_marcos()).juntar(ok.estado!);
      expect(junto.diaMarco, 0);
      expect(junto.vales.single.id, 'v-salgados', reason: 'os vales e o texto ficam');
      expect(junto.texto, 'Faz o check-in todos os dias.');
      expect(junto.marcos.length, 4, reason: 'resposta sem marcos mantém os de antes');
      expect(junto.escada!.guardado, isNull);

      final nao = CheckinEscadaResultado.fromJson({'ok': false, 'reason': 'ultimo_degrau'});
      expect(nao.ok, isFalse);
      expect(nao.reason, 'ultimo_degrau');
      expect(nao.vale, isNull);
      expect(mensagemErroEscada('expirado'), 'Este prémio já expirou.');
      expect(mensagemErroEscada('ja_levantado'), 'Este prémio já foi levantado.');
      expect(mensagemErroEscada('sem_premio'), 'Já não tens nenhum prémio guardado.');
      expect(mensagemErroEscada('ultimo_degrau'), contains('prémio maior'));
      expect(mensagemErroEscada('sem_rede'), 'Não foi possível. Tenta de novo.');
    });

    test('reserva: o artigo-prémio vem a 0 € com a loja', () {
      final r = ReservaPremio.fromJson({
        'ok': true,
        'vale': _marcos()['vales'][0],
        'produto': {'id': 'premio-checkin-salgados', 'name': 'Prémio Bora Todo Dia: 2 Salgados Grandes', 'price': 0, 'restaurant_id': 'sabores-brasil-guarda'},
        'loja': {'id': 'sabores-brasil-guarda', 'name': 'Sabores do Brasil - Keli Barbosa', 'is_partner': true},
      });
      expect(r, isNotNull);
      expect(r!.produtoId, 'premio-checkin-salgados');
      expect(r.lojaId, 'sabores-brasil-guarda');
      expect(ReservaPremio.fromJson({'ok': false, 'reason': 'expirado'}), isNull);
    });
  });

  group('artigo-prémio no carrinho', () {
    CartStore sessao(String loja, String id) => CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: true,
        vendorName: loja,
        vendorRestaurantId: id,
        distanceKm: 1.0,
        pickupLocation: const LatLng(40.5323845, -7.2656677),
        deliveryLocation: const LatLng(40.5373, -7.2676),
      );

    test('uma linha só a 0 €; o "+" não soma; escolher de novo troca a linha', () {
      final cart = sessao('Sabores do Brasil - Keli Barbosa', 'sabores-brasil-guarda');
      final premio = CartItem(
        productId: 'premio-checkin-salgados',
        name: 'Prémio Bora Todo Dia: 2 Salgados Grandes',
        price: 0,
        basePrice: 0,
        selectedOptions: const [SelectedOption(group: '1.º salgado', items: ['Coxinha'])],
      );
      cart.addItem(premio);
      cart.increaseQuantity(cart.items.single);
      expect(cart.items.single.quantity, 1);
      cart.addItem(CartItem(
        productId: 'premio-checkin-salgados',
        name: 'Prémio Bora Todo Dia: 2 Salgados Grandes',
        price: 0,
        basePrice: 0,
        selectedOptions: const [SelectedOption(group: '1.º salgado', items: ['Esfirra'])],
      ));
      expect(cart.items.length, 1);
      expect(cart.items.single.selectedOptions.single.items, ['Esfirra']);
      expect(cart.temArtigoPremio, isTrue);
      expect(cart.vendorRestaurantId, 'sabores-brasil-guarda');
      expect(cart.subtotal, 0, reason: 'grátis só o produto: no pedido a linha vale 0 €');
    });

    test('artigo normal continua a somar como antes', () {
      final cart = sessao('Sabores do Brasil - Keli Barbosa', 'sabores-brasil-guarda');
      final normal = CartItem(productId: '09a9503f-1ef2-4a92-9486-e53848dc853c', name: 'Salgados Grandes', price: 3.15, basePrice: 3.15);
      cart.addItem(normal);
      cart.addItem(CartItem(productId: '09a9503f-1ef2-4a92-9486-e53848dc853c', name: 'Salgados Grandes', price: 3.15, basePrice: 3.15));
      cart.increaseQuantity(cart.items.single);
      expect(cart.items.single.quantity, 3);
      expect(cart.temArtigoPremio, isFalse);
      expect(cart.subtotal, closeTo(9.45, 0.001));
    });

    test('açaí do Goola: o bowl vale 0 €, só o extra pago (Oreo 1,17 €) entra na linha', () {
      final cart = sessao('Goola Açaí', 'goola-acai-guarda');
      cart.addItem(CartItem(
        productId: 'premio-checkin-acai',
        name: 'Prémio Bora Todo Dia: Goola Bowl',
        price: 1.17,
        basePrice: 0,
        selectedOptions: const [
          SelectedOption(group: 'Acompanhamentos', items: ['Banana', 'Morango', 'Granola tradicional']),
          SelectedOption(group: 'Extras', items: ['Oreo']),
        ],
      ));
      expect(cart.subtotal, closeTo(1.17, 0.001));
      expect(ehArtigoPremio(cart.items.single.productId), isTrue);
    });
  });

  testWidgets('a ficha do prémio só deixa pôr no carrinho com as escolhas feitas', (t) async {
    final cart = CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: true,
        vendorName: 'Sabores do Brasil - Keli Barbosa',
        vendorRestaurantId: 'sabores-brasil-guarda',
        distanceKm: 1.0,
        pickupLocation: const LatLng(40.5323845, -7.2656677),
        deliveryLocation: const LatLng(40.5373, -7.2676),
      );
    final reserva = ReservaPremio.fromJson({
      'ok': true,
      'vale': _marcos()['vales'][0],
      'produto': {'id': 'premio-checkin-salgados', 'name': 'Prémio Bora Todo Dia: 2 Salgados Grandes', 'restaurant_id': 'sabores-brasil-guarda'},
      'loja': {'id': 'sabores-brasil-guarda', 'name': 'Sabores do Brasil - Keli Barbosa'},
    })!;
    Future<List<ProductOptionGroup>> opcoes(String _) async => [
          for (final n in [1, 2])
            ProductOptionGroup.fromMap({
              'id': 'g$n', 'product_id': 'premio-checkin-salgados', 'name': '$n.º salgado', 'is_required': true,
              'min_choices': 1, 'max_choices': 1, 'sort_order': n,
              'product_option_items': [
                {'id': 'g$n-c', 'name': 'Coxinha', 'price_add': 0, 'is_available': true, 'sort_order': 1},
                {'id': 'g$n-e', 'name': 'Esfirra', 'price_add': 0, 'is_available': true, 'sort_order': 2},
              ],
            }),
        ];
    await t.pumpWidget(ChangeNotifierProvider<CartStore>.value(
      value: cart,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarPremioOpcoes(ctx, reserva, lojaParceira: true, carregarOpcoes: opcoes),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    final botao = find.byKey(const Key('btn_premio_carrinho'));
    expect(t.widget<ButtonStyleButton>(botao).onPressed, isNull);
    await t.tap(find.byKey(const Key('premio_opcao_g1-c')));
    await t.pump();
    await t.tap(find.byKey(const Key('premio_opcao_g2-e')));
    await t.pump();
    await t.tap(botao);
    await t.pumpAndSettle();
    expect(cart.items.single.productId, 'premio-checkin-salgados');
    expect(cart.items.single.price, 0);
    expect(cart.items.single.selectedOptions.map((o) => o.items.single), ['Coxinha', 'Esfirra']);
  });
}
