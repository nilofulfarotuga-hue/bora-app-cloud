// Agendar pedidos (item 5 do adendo 5, 29/10/2026): o ecrã do painel admin
// (PT-BR) — interruptor com a tranca do revisor, ajustes e lista — e o item no
// menu. Servidor de mentira, sem rede.
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_pedidos_agendados_screen.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

DateTime utc(int dia, int h, [int m = 0]) => DateTime.utc(2026, 11, dia, h, m);

class AdminApiFalsa implements AgendarPedidoAdminApi {
  AdminApiFalsa({
    this.cfg = const ConfigAgendarAdmin(),
    this.lista = const [],
    this.falhaLeitura = false,
    this.erroAoDefinir,
  });

  ConfigAgendarAdmin cfg;
  List<PedidoAgendado> lista;
  final bool falhaLeitura;
  final Object? erroAoDefinir;
  final List<String> chamadas = [];

  @override
  Future<ConfigAgendarAdmin> config() async {
    if (falhaLeitura) throw Exception('sem rede');
    return cfg;
  }

  @override
  Future<ConfigAgendarAdmin> definir(String chave, Object valor) async {
    chamadas.add('$chave=$valor');
    if (erroAoDefinir != null) throw erroAoDefinir!;
    cfg = ConfigAgendarAdmin(
      ligado: chave == 'scheduled_orders_enabled' ? valor as bool : cfg.ligado,
      maxDias: chave == 'scheduled_orders_max_days' ? valor as int : cfg.maxDias,
      antecedenciaMin:
          chave == 'scheduled_orders_min_lead_minutes' ? valor as int : cfg.antecedenciaMin,
      revisorOk: cfg.revisorOk,
      total: cfg.total,
      proximas24h: cfg.proximas24h,
    );
    return cfg;
  }

  @override
  Future<List<PedidoAgendado>> pedidos() async => lista;
}

void ecraAlto(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget tela(AdminApiFalsa api) => MaterialApp(
      home: AdminPedidosAgendadosScreen(api: api, relogio: () => utc(3, 12)),
    );

bool interruptorLigado(WidgetTester t) =>
    t.widget<SwitchListTile>(find.byKey(const Key('agendados-interruptor'))).value;

bool interruptorAtivo(WidgetTester t) =>
    t.widget<SwitchListTile>(find.byKey(const Key('agendados-interruptor'))).onChanged != null;

void main() {
  group('AdminPedidosAgendadosScreen', () {
    testWidgets('nasce desligado e sem o SIM do revisor não deixa ligar', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa();
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();

      expect(find.text('Pedidos agendados'), findsOneWidget);
      expect(interruptorLigado(t), isFalse);
      expect(interruptorAtivo(t), isFalse);
      expect(find.byKey(const Key('agendados-sem-revisor')), findsOneWidget);
      expect(find.textContaining('DESLIGADO'), findsOneWidget);
      expect(find.byKey(const Key('agendados-admin-vazio')), findsOneWidget);
      expect(api.chamadas, isEmpty);
    });

    testWidgets('com o SIM do revisor: pede confirmação e só então liga', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa(cfg: const ConfigAgendarAdmin(revisorOk: true));
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();
      expect(interruptorAtivo(t), isTrue);
      expect(find.byKey(const Key('agendados-sem-revisor')), findsNothing);

      // Cancelar no diálogo: nada muda.
      await t.tap(find.byKey(const Key('agendados-interruptor')));
      await t.pumpAndSettle();
      expect(find.text('Ligar os pedidos agendados?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(api.chamadas, isEmpty);
      expect(interruptorLigado(t), isFalse);

      // Confirmar: liga.
      await t.tap(find.byKey(const Key('agendados-interruptor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ligar'));
      await t.pumpAndSettle();
      expect(api.chamadas, ['scheduled_orders_enabled=true']);
      expect(interruptorLigado(t), isTrue);
      expect(find.textContaining('LIGADO'), findsOneWidget);
    });

    testWidgets('ligado, desligar é sempre possível (sem confirmação)', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa(cfg: const ConfigAgendarAdmin(ligado: true));
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();
      expect(interruptorAtivo(t), isTrue);
      await t.tap(find.byKey(const Key('agendados-interruptor')));
      await t.pumpAndSettle();
      expect(api.chamadas, ['scheduled_orders_enabled=false']);
      expect(interruptorLigado(t), isFalse);
    });

    testWidgets('o servidor recusa ligar (revisor_em_falta): mostra o motivo', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa(
        cfg: const ConfigAgendarAdmin(revisorOk: true),
        erroAoDefinir: const PostgrestException(message: 'revisor_em_falta'),
      );
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agendados-interruptor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ligar'));
      await t.pumpAndSettle();
      expect(find.text('O revisor independente ainda não disse SIM. Sem isso não dá para ligar.'),
          findsOneWidget);
      expect(interruptorLigado(t), isFalse);
    });

    testWidgets('muda o máximo de dias e a antecedência mínima', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa(cfg: const ConfigAgendarAdmin(revisorOk: true));
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('agendados-dias')));
      await t.pumpAndSettle();
      await t.tap(find.text('10 dias').last);
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('agendados-antecedencia')));
      await t.pumpAndSettle();
      await t.tap(find.text('120 min').last);
      await t.pumpAndSettle();

      expect(api.chamadas, [
        'scheduled_orders_max_days=10',
        'scheduled_orders_min_lead_minutes=120',
      ]);
    });

    testWidgets('lista os pedidos agendados de todas as lojas e a contagem', (t) async {
      ecraAlto(t);
      final api = AdminApiFalsa(
        cfg: const ConfigAgendarAdmin(ligado: true, revisorOk: true, total: 2, proximas24h: 1),
        lista: [
          PedidoAgendado(
            id: 'ped-aaaa1111',
            estado: 'created',
            quando: utc(3, 19, 30),
            lojaNome: 'Boom! Burger',
            clienteNome: 'Ana',
            totalEur: 12.5,
            metodo: 'cash',
          ),
          PedidoAgendado(
            id: 'ped-bbbb2222',
            estado: 'preparing',
            quando: utc(7, 13),
            lojaNome: 'Casa do Zé',
            clienteNome: 'Rui',
            totalEur: 8,
            metodo: 'card',
            pagamento: 'paid',
          ),
        ],
      );
      await t.pumpWidget(tela(api));
      await t.pumpAndSettle();

      expect(find.text('Agendados à frente: 2 · nas próximas 24 h: 1'), findsOneWidget);
      expect(find.text('Boom! Burger · ter 03/11 19:30–20:00'), findsOneWidget);
      expect(find.text('Casa do Zé · sáb 07/11 13:00–13:30'), findsOneWidget);
      expect(find.textContaining('faltam 7 h 30 min · Aguardando a loja aceitar'), findsOneWidget);
      expect(find.textContaining('Ana · 12,50 € · Dinheiro · #1111'), findsOneWidget);
      expect(find.textContaining('Rui · 8,00 € · Cartão · pago · #2222'), findsOneWidget);
      expect(find.textContaining('Aceito, em preparo'), findsOneWidget);
    });

    testWidgets('erro a carregar: mostra a mensagem e deixa tentar de novo', (t) async {
      ecraAlto(t);
      await t.pumpWidget(tela(AdminApiFalsa(falhaLeitura: true)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendados-admin-erro')), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('menu do painel', () {
    test('o item "Pedidos agendados" existe uma vez, na secção Sistema', () {
      final todos = adminMenuAllItems().where((i) => i.id == 'sistema_pedidos_agendados').toList();
      expect(todos.length, 1);
      expect(todos.single.title, 'Pedidos agendados');
      expect(todos.single.builder(), isA<AdminPedidosAgendadosScreen>());
    });

    test('os ids do menu continuam todos únicos', () {
      final ids = adminMenuAllItems().map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
