// Missão farmacias-loja-2026-11-14, Bloco 5 — painel admin das farmácias, testes sem rede.
import 'package:bora_app/screens/admin/admin_farmacia_ficha.dart';
import 'package:bora_app/screens/admin/admin_farmacias_extrato_aba.dart';
import 'package:bora_app/screens/admin/admin_farmacias_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/services/admin_farmacias_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Linha como vem de admin_farmacias_listar (c1), hoje: tudo por preencher, e-mail de demonstração.
Map<String, dynamic> _farmacia({
  bool demo = true,
  List<String> falta = const ['nome', 'nif', 'iban', 'data_nascimento', 'autocertificacao'],
  String? certidao,
  bool escondida = true,
}) =>
    {
      'id': 'farmacia-se-guarda',
      'name': 'Farmácia da Sé',
      'is_partner': true,
      'so_lista_permissao': escondida,
      'pharmacy_prescription_mode': 'so_lista',
      'partner_extra_commission_pct': 0.10,
      'partner_extra_commission_starts_at': null,
      'aberta_ao_publico_em': null,
      'dono_user_id': '9b218f1a-3b54-4168-ba8f-d1b218f6ec94',
      'dono_email': demo ? 'demo.farmacia.se@bora.app' : 'geral@farmaciadase.pt',
      'email': demo ? 'demo.farmacia.se@bora.app' : 'geral@farmaciadase.pt',
      'email_demonstracao': demo,
      'dono_ultimo_login': '2026-11-11T19:55:07Z',
      'dono_link_senha_em': null,
      'legal_name': null,
      'business_registration_number': certidao,
      'dsa_self_certified_at': null,
      'em_falta': falta,
      'produtos': 120,
      'produtos_provisorios': 3,
      'lista': ['dono@exemplo.pt'],
      'pedidos_receita': 4,
    };

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: filho)));

void _tamanho(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

AdminFarmaciaCartao _cartao(Map<String, dynamic> f, {VoidCallback? aoAbrir, VoidCallback? aoLink}) => AdminFarmaciaCartao(
      farmacia: f,
      aoMudarModo: (_) {},
      aoEditarLista: () {},
      aoEditarComissao: () {},
      aoAbrir: aoAbrir ?? () {},
      formatarData: dataLisboa,
      aoTrocarEmail: () {},
      aoEnviarLinkSenha: aoLink ?? () {},
      aoAbrirHorario: () {},
      aoAbrirPrecos: () {},
    );

void main() {
  group('o que falta antes de abrir ao público', () {
    test('hoje (demonstração e sem dados) não pode abrir', () {
      final itens = itensParaAbrir(_farmacia());
      expect(podeAbrirAoPublico(itens), isFalse);
      final faltam = itens.where((i) => i.obrigatorio && !i.ok).map((i) => i.rotulo).join(' | ');
      expect(faltam, contains('E-mail de login verdadeiro'));
      expect(faltam, contains('NIF (número de contribuinte)'));
      expect(faltam, contains('IBAN (número da conta bancária)'));
      expect(faltam, contains('Termos aceitos'));
      expect(faltam, contains('Data de nascimento'));
    });

    test('com e-mail real e dados completos pode abrir; a certidão é só recomendada', () {
      final itens = itensParaAbrir(_farmacia(demo: false, falta: const []));
      expect(podeAbrirAoPublico(itens), isTrue);
      final cert = itens.firstWhere((i) => i.rotulo.contains('certidão'));
      expect(cert.obrigatorio, isFalse);
      expect(cert.ok, isFalse);
    });

    test('sem conta de dono não conta como e-mail real', () {
      final f = _farmacia(demo: false, falta: const [])..['dono_user_id'] = null;
      expect(podeAbrirAoPublico(itensParaAbrir(f)), isFalse);
    });

    test('erros do servidor ao abrir viram frase em português', () {
      expect(mensagemErroAbrirFarmacia(Exception('email_demonstracao: a conta ...')), contains('e-mail de demonstração'));
      expect(mensagemErroAbrirFarmacia(Exception('conformidade_incompleta: faltam nif, iban')),
          'Não dá para abrir: faltam NIF, IBAN.');
    });
  });

  group('cartão da farmácia', () {
    testWidgets('demonstração: aviso, link de senha desligado e "Abrir" desligado com a lista', (t) async {
      _tamanho(t);
      var abriu = false;
      var link = false;
      await t.pumpWidget(_app(_cartao(_farmacia(), aoAbrir: () => abriu = true, aoLink: () => link = true)));
      expect(find.text('e-mail de demonstração'), findsOneWidget);
      expect(find.text('E-mail de login (conta do dono): demo.farmacia.se@bora.app'), findsOneWidget);
      expect(find.text('Antes de abrir ao público'), findsOneWidget);
      expect(find.text('Abrir ao público (complete o que falta acima)'), findsOneWidget);
      await t.tap(find.text('Abrir ao público (complete o que falta acima)'));
      await t.tap(find.text('Mandar link de senha'));
      await t.pump();
      expect(abriu, isFalse);
      expect(link, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('tudo pronto: "Abrir ao público" acende e chama a ação', (t) async {
      _tamanho(t);
      var abriu = false;
      await t.pumpWidget(_app(_cartao(_farmacia(demo: false, falta: const [], certidao: '1234-5678-9012'),
          aoAbrir: () => abriu = true)));
      expect(find.text('e-mail de demonstração'), findsNothing);
      await t.tap(find.text('Abrir ao público'));
      await t.pump();
      expect(abriu, isTrue);
    });

    testWidgets('aberta ao público mostra a data e não a lista', (t) async {
      _tamanho(t);
      final f = _farmacia(demo: false, falta: const [], escondida: false)..['aberta_ao_publico_em'] = '2026-11-20T10:00:00Z';
      await t.pumpWidget(_app(_cartao(f)));
      expect(find.text('Antes de abrir ao público'), findsNothing);
      expect(find.text('Aberta ao público em 20/11/2026'), findsOneWidget);
    });

    testWidgets('interruptor das receitas reais: desligado diz o que é e só muda por callback', (t) async {
      bool? pedido;
      await t.pumpWidget(_app(AdminReceitasReaisCartao(ligado: false, aoMudar: (v) => pedido = v)));
      expect(find.textContaining('DESLIGADO'), findsOneWidget);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(pedido, isTrue); // o ecrã pede a confirmação forte antes de gravar
    });
  });

  group('extrato semanal', () {
    final base = <String, dynamic>{
      'week_start': '2026-11-09T00:00:00Z',
      'week_end': '2026-11-15T23:59:59Z',
      'total_orders': 3,
      'gross_sales': 42.5,
      'commission_total': 4.25,
      'partner_share': 38.25,
      'cash_kept_by_partner': 10,
      'pago_em_mao_na_recolha': 0,
      'net_balance': 28.25,
      'deposit_volta_total': 0,
      'direction': 'bora_pays_partner',
    };

    testWidgets('sem as chaves novas não mostra a comissão extra', (t) async {
      await t.pumpWidget(_app(AdminFarmaciaExtratoCartao(nome: 'Farmácia da Sé', extrato: base)));
      expect(find.text('Vendas na app (bruto)'), findsOneWidget);
      expect(find.text('42,50 €'), findsOneWidget);
      expect(find.textContaining('Comissão extra'), findsNothing);
      expect(find.textContaining('Depósitos Volta'), findsNothing);
      expect(find.text('Saldo da semana — Bora paga à farmácia'), findsOneWidget);
    });

    testWidgets('com comissao_extra e comissao_extra_receitas mostra as duas', (t) async {
      final e = {...base, 'comissao_extra': 4.25, 'comissao_extra_receitas': 1.2};
      await t.pumpWidget(_app(AdminFarmaciaExtratoCartao(nome: 'Farmácia da Sé', extrato: e)));
      expect(find.textContaining('Comissão extra (10% das vendas'), findsOneWidget);
      expect(find.textContaining('Comissão extra das receitas'), findsOneWidget);
      expect(find.text('1,20 €'), findsOneWidget);
    });

    test('linha do CSV com vírgula decimal e datas de Lisboa', () {
      final l = linhaCsvExtrato('Farmácia da Sé', {...base, 'comissao_extra': 4.25});
      expect(l['semana_inicio'], '09/11/2026');
      expect(l['vendas'], '42,50');
      expect(l['comissao_extra'], '4,25');
      expect(l['comissao_extra_receitas'], '');
      expect(l['direcao'], 'Bora paga à farmácia');
      expect(kColunasCsvExtrato.map((c) => c.$1), containsAll(l.keys));
    });

    test('valores em texto ou em mapa também se leem', () {
      expect(numeroDoExtrato('3.5'), 3.5);
      expect(numeroDoExtrato({'total': 2}), 2);
      expect(numeroDoExtrato(null), isNull);
    });
  });

  test('erros da troca de e-mail em português', () {
    expect(AdminFarmaciasService.mensagemErroEmail('email_em_uso'), contains('já é usado por outra conta'));
    expect(AdminFarmaciasService.mensagemErroEmail('dono_e_admin'), contains('administrador'));
    expect(AdminFarmaciasService.mensagemErroEmail(403), 'Sem permissão de admin para esta ação.');
  });

  test('o extrato das farmácias está na busca do painel', () {
    final todos = adminMenuAllItems();
    expect(todos.where((i) => i.matches('extrato')).map((i) => i.id), contains('farmacias_extrato'));
    expect(todos.where((i) => i.matches('certidao')).map((i) => i.id), contains('farmacias'));
  });
}
