import 'package:bora_app/screens/admin/admin_modo_ocupado_screen.dart';
import 'package:bora_app/services/modo_ocupado_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C6 (29/10/2026) — tela do admin (PT-BR): lista quem está ocupado, desliga uma
/// loja e liga/desliga o recurso para todos. Servidor falso; relógio fixo.
class _ApiAdmin implements ModoOcupadoApi {
  _ApiAdmin(this.painel);

  PainelOcupados? painel;
  final List<String> chamadas = [];
  bool desligarOk = true;
  bool interruptorOk = true;

  @override
  String get ultimoErro => '';

  @override
  Future<PainelOcupados?> listarOcupados() async {
    chamadas.add('listar');
    return painel;
  }

  @override
  Future<bool> desligarLoja(String restaurantId) async {
    chamadas.add('desligar:$restaurantId');
    if (desligarOk) {
      painel = PainelOcupados(
        ligado: painel!.ligado,
        lojas: painel!.lojas.where((l) => l.restaurantId != restaurantId).toList(),
      );
    }
    return desligarOk;
  }

  @override
  Future<bool> definirInterruptor(bool ligado) async {
    chamadas.add('interruptor:$ligado');
    if (interruptorOk) painel = PainelOcupados(ligado: ligado, lojas: painel!.lojas);
    return interruptorOk;
  }

  @override
  Future<EstadoOcupado?> definir(String restaurantId, int minutos) async => null;
  @override
  Future<bool> prometerPronto(String orderId, DateTime? hora) async => true;
}

void main() {
  final agora = DateTime.utc(2026, 10, 29, 14, 30);

  LojaOcupada loja(String id, String nome, int min, DateTime ate) => LojaOcupada(
      restaurantId: id, nome: nome, extraMinutos: min, ate: ate);

  Future<void> montar(WidgetTester t, ModoOcupadoApi api) async {
    await t.pumpWidget(MaterialApp(
      home: AdminModoOcupadoScreen(api: api, agora: () => agora),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('lista as lojas ocupadas: nome, minutos, até quando e quanto falta',
      (t) async {
    final api = _ApiAdmin(PainelOcupados(ligado: true, lojas: [
      loja('r1', 'Boom Burger', 20, DateTime.utc(2026, 10, 29, 15, 50)),
      loja('r2', 'Pizzaria Sol', 30, DateTime.utc(2026, 10, 29, 14, 55)),
    ]));
    await montar(t, api);

    expect(find.text('Modo ocupado dos parceiros'), findsOneWidget);
    expect(find.text('Lojas ocupadas agora (2)'), findsOneWidget);
    expect(find.text('Boom Burger'), findsOneWidget);
    expect(find.text('+20 min até 15:50 (faltam 1 h 20 min)'), findsOneWidget);
    expect(find.text('Pizzaria Sol'), findsOneWidget);
    expect(find.text('+30 min até 14:55 (faltam 25 min)'), findsOneWidget);
    expect(find.byKey(const Key('btn_desligar_r1')), findsOneWidget);
    expect(find.byKey(const Key('btn_desligar_r2')), findsOneWidget);
    expect(find.byKey(const Key('ocupados_vazio')), findsNothing);
  });

  testWidgets('ninguém ocupado: diz isso mesmo', (t) async {
    await montar(t, _ApiAdmin(const PainelOcupados(ligado: true, lojas: [])));
    expect(find.text('Lojas ocupadas agora (0)'), findsOneWidget);
    expect(find.byKey(const Key('ocupados_vazio')), findsOneWidget);
  });

  testWidgets('"Desligar" tira a loja da lista e confirma', (t) async {
    final api = _ApiAdmin(PainelOcupados(ligado: true, lojas: [
      loja('r1', 'Boom Burger', 20, DateTime.utc(2026, 10, 29, 15, 50)),
      loja('r2', 'Pizzaria Sol', 30, DateTime.utc(2026, 10, 29, 14, 55)),
    ]));
    await montar(t, api);

    await t.tap(find.byKey(const Key('btn_desligar_r1')));
    await t.pump();
    await t.pump();
    await t.pump();

    expect(api.chamadas, containsAllInOrder(['listar', 'desligar:r1', 'listar']));
    expect(find.text('Boom Burger'), findsNothing);
    expect(find.text('Pizzaria Sol'), findsOneWidget);
    expect(find.text('Lojas ocupadas agora (1)'), findsOneWidget);
    expect(find.textContaining('Modo ocupado de Boom Burger desligado'), findsOneWidget);
  });

  testWidgets('falha ao desligar: avisa e a loja continua na lista', (t) async {
    final api = _ApiAdmin(PainelOcupados(ligado: true, lojas: [
      loja('r1', 'Boom Burger', 20, DateTime.utc(2026, 10, 29, 15, 50)),
    ]))
      ..desligarOk = false;
    await montar(t, api);

    await t.tap(find.byKey(const Key('btn_desligar_r1')));
    await t.pump();
    await t.pump();

    expect(find.textContaining('Não deu para desligar'), findsOneWidget);
    expect(find.text('Boom Burger'), findsOneWidget);
  });

  testWidgets('o interruptor geral mostra o estado e liga', (t) async {
    final api = _ApiAdmin(const PainelOcupados(ligado: false, lojas: []));
    await montar(t, api);

    final sw = find.byKey(const Key('switch_modo_ocupado'));
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
    expect(find.textContaining('Desligado: nada muda'), findsOneWidget);

    await t.tap(sw);
    await t.pump();
    await t.pump();
    await t.pump();

    expect(api.chamadas, containsAllInOrder(['interruptor:true', 'listar']));
    expect(t.widget<SwitchListTile>(sw).value, isTrue);
    expect(find.textContaining('Ligado: os parceiros online'), findsOneWidget);
  });

  testWidgets('interruptor desligado mas com lojas: avisa que não se aplica',
      (t) async {
    await montar(
        t,
        _ApiAdmin(PainelOcupados(ligado: false, lojas: [
          loja('r1', 'Boom Burger', 20, DateTime.utc(2026, 10, 29, 15, 50)),
        ])));
    expect(find.byKey(const Key('ocupados_aviso_desligado')), findsOneWidget);
  });

  testWidgets('servidor sem as funções novas: mensagem e "Tentar de novo"',
      (t) async {
    final api = _ApiAdmin(const PainelOcupados(ligado: false, lojas: []))..painel = null;
    await montar(t, api);
    expect(find.byKey(const Key('ocupados_erro')), findsOneWidget);

    api.painel = const PainelOcupados(ligado: true, lojas: []);
    await t.tap(find.text('Tentar de novo'));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('ocupados_erro')), findsNothing);
    expect(find.text('Lojas ocupadas agora (0)'), findsOneWidget);
  });
}
