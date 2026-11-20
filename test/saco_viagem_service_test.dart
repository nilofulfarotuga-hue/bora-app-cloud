// Saco para viagem (missão saco-viagem-2026-11-20): quando a linha aparece e
// como a app fala com o servidor.

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/saco_viagem_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderModel _pedido({
  OrderServiceType tipo = OrderServiceType.restaurant,
  bool parceiro = false,
  int sacos = 1,
}) =>
    OrderModel(
      id: 'p1',
      total: 12.5,
      serviceType: tipo,
      vendorName: "McDonald's",
      isPartnerStore: parceiro,
      bagCount: sacos,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => SacoViagemService.rpcParaTeste = null);

  group('precisaSacoViagem', () {
    test('restaurante não-parceiro com saco: sim', () {
      expect(precisaSacoViagem(_pedido()), isTrue);
    });
    test('restaurante parceiro: não', () {
      expect(precisaSacoViagem(_pedido(parceiro: true)), isFalse);
    });
    test('mercado não-parceiro: não (o saco do mercado é da Bora)', () {
      expect(precisaSacoViagem(_pedido(tipo: OrderServiceType.storeShopping)),
          isFalse);
    });
    test('sem saco no pedido: não', () {
      expect(precisaSacoViagem(_pedido(sacos: 0)), isFalse);
    });
  });

  test('texto da linha do topo', () {
    expect(textoPedirSaco(1), 'Pede 1 saco ao balcão');
    expect(textoPedirSaco(2), 'Pede 2 sacos ao balcão');
    expect(textoPedirSaco(0), 'Pede 1 saco ao balcão');
  });

  test('envia p_comprado e lê a resposta do servidor', () async {
    Map<String, dynamic>? enviado;
    SacoViagemService.rpcParaTeste = (p) async {
      enviado = p;
      return {'ok': true, 'obrigatorio': true, 'marcado': true,
        'marcado_em': '2026-11-20T12:30:00Z'};
    };
    final r = await SacoViagemService.enviar('p1', comprado: true);
    expect(enviado, {'p_order_id': 'p1', 'p_comprado': true});
    expect(r?.marcado, isTrue);
    expect(r?.servidorSemFuncao, isFalse);
  });

  test('sem rede: null (o botão de seguir continua bloqueado)', () async {
    SacoViagemService.rpcParaTeste = (_) async => throw Exception('SocketException');
    expect(await SacoViagemService.enviar('p1', comprado: true), isNull);
  });

  test('função ainda por publicar: não prende o estafeta', () async {
    SacoViagemService.rpcParaTeste = (_) async => throw Exception(
        'PostgrestException(message: Could not find the function '
        'public.estafeta_saco_viagem, code: PGRST202)');
    final r = await SacoViagemService.enviar('p1', comprado: true);
    expect(r?.servidorSemFuncao, isTrue);
    expect(r?.marcado, isTrue);
  });

  test('podeSeguir: só a falta de marca num pedido com saco bloqueia', () {
    expect(const EstadoSacoServidor(obrigatorio: true, marcado: false).podeSeguir,
        isFalse);
    expect(const EstadoSacoServidor(obrigatorio: true, marcado: true).podeSeguir,
        isTrue);
    // O servidor diz que o pedido não pede saco: não prende.
    expect(EstadoSacoServidor.deResposta({'ok': true, 'obrigatorio': false})!
        .podeSeguir, isTrue);
    // Recusa do servidor (ok:false): o fecho do talão diz o erro real.
    final recusa = EstadoSacoServidor.deResposta(
        {'ok': false, 'error': 'NOT_ASSIGNED_DRIVER'})!;
    expect(recusa.erro, 'NOT_ASSIGNED_DRIVER');
    expect(recusa.podeSeguir, isTrue);
  });

  test('marca no telemóvel sobrevive e esquece-se no fim', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SacoViagemService.lerLocal('p1'), isNull);
    await SacoViagemService.gravarLocal('p1', true);
    expect(await SacoViagemService.lerLocal('p1'), isTrue);
    await SacoViagemService.esquecerLocal('p1');
    expect(await SacoViagemService.lerLocal('p1'), isNull);
  });
}
