import 'package:bora_app/screens/admin/admin_agentes_hermes_tab.dart';
import 'package:bora_app/stores/agentes_hermes_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [hermes-diretor B10] Aba "Agentes" e previsão do crédito do Claude. Fontes falsas: sem rede.
class _Fonte implements AgentesFonte {
  _Fonte({this.linhas = const [], this.semColunasNovas = false, this.falha});

  final List<Map<String, dynamic>> linhas;
  final bool semColunasNovas;
  final Object? falha;
  final gravacoes = <String>[];

  @override
  Future<List<Map<String, dynamic>>> agentes({required bool comColunasNovas}) async {
    if (falha != null) throw falha!;
    if (comColunasNovas && semColunasNovas) {
      throw Exception('42703: column agentes_estado.arquivado does not exist');
    }
    return linhas;
  }

  @override
  Future<List<Map<String, dynamic>>> auditoria24h() async => [
        {'para': 'crescimento', 'terminadas': 14, 'precisavam': 13, 'auditadas_ok': 11, 'devolvidas': 2, 'percentagem': 84.6},
      ];

  @override
  Future<Object?> auditoriaResumo() async =>
      {'terminadas': 20, 'precisavam': 20, 'auditadas_ok': 18, 'devolvidas': 2, 'percentagem': 90};

  @override
  Future<double> gastoMesHermesUsd() async => 4.5;

  @override
  Future<void> gravarEstado(String agente, Map<String, dynamic> campos, {required Map<String, dynamic> auditoria}) async {
    gravacoes.add('$agente:${campos['ligado']}/${campos['horario_ligado']}/${campos['arquivado']}');
  }
}

Map<String, dynamic> _agente(String nome, {bool ligado = true, bool horario = false, bool arquivado = false}) => {
      'agente': nome,
      'ligado': ligado,
      'horario_ligado': horario,
      'arquivado': arquivado,
      'departamento': 'crescimento',
      'papel': 'Faz coisas',
      'cadencia_min': 60,
      'teto_dia_eur': 2.0,
    };

class _FontePrevisao implements PrevisaoClaudeFonte {
  _FontePrevisao(this.resposta, {this.falha});

  final Object? resposta;
  final Object? falha;

  @override
  Future<Object?> previsao() async {
    if (falha != null) throw falha!;
    return resposta;
  }
}

Future<void> _abrir(WidgetTester t, Widget corpo) async {
  t.view.physicalSize = const Size(1200, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: corpo)));
  await t.pumpAndSettle();
}

void main() {
  group('aba Agentes', () {
    testWidgets('lista vazia', (t) async {
      await _abrir(t, AdminAgentesTab(store: AgentesHermesStore(fonte: _Fonte())));
      expect(find.text('Nenhum agente registado.'), findsOneWidget);
    });

    testWidgets('com dados: estados em palavras, auditoria, gasto do Hermes e mudar estado com confirmação', (t) async {
      final f = _Fonte(linhas: [
        _agente('crescimento', horario: true),
        _agente('atendimento'),
        _agente('trader', arquivado: true, ligado: false),
      ]);
      await _abrir(t, AdminAgentesTab(store: AgentesHermesStore(fonte: f)));
      expect(find.text('Ligado ao relógio'), findsOneWidget);
      expect(find.text('A pedido'), findsWidgets);
      expect(find.text('Arquivado'), findsWidgets);
      expect(find.text('85 % (11 de 13)'), findsOneWidget);
      expect(find.text('US\$ 4,50'), findsOneWidget);

      // Pôr "crescimento" a pedido: pede confirmação e só depois grava.
      final botao = find.descendant(of: find.byKey(const ValueKey('agente-crescimento')), matching: find.text('Pôr a pedido'));
      await t.tap(botao);
      await t.pumpAndSettle();
      expect(f.gravacoes, isEmpty);
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(f.gravacoes, ['crescimento:true/false/false']);
    });

    testWidgets('colunas novas em falta: lê na mesma e avisa que arquivar ainda não está ligado', (t) async {
      final f = _Fonte(linhas: [_agente('crescimento', horario: true)], semColunasNovas: true);
      await _abrir(t, AdminAgentesTab(store: AgentesHermesStore(fonte: f)));
      expect(find.text('crescimento'), findsOneWidget);
      expect(find.textContaining('Arquivar ainda não está ligado'), findsOneWidget);
      expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
    });

    testWidgets('ainda não ligado no servidor: faixa calma', (t) async {
      final f = _Fonte(falha: Exception('PGRST205: Could not find the table public.agentes_estado'));
      await _abrir(t, AdminAgentesTab(store: AgentesHermesStore(fonte: f)));
      expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
      expect(find.textContaining('Não foi possível carregar'), findsNothing);
    });
  });

  group('cartão da previsão do crédito', () {
    testWidgets('com dados: gasto, previsão, quanto falta e quem gasta mais', (t) async {
      final r = {
        'mes': '2026-11',
        'gasto_usd': 3.5,
        'credito_usd': 20,
        'previsao_usd': 11.7,
        'falta_usd': 8.3,
        'percentagem': 17.5,
        'dia_do_mes': 22,
        'dias_no_mes': 30,
        'estado': 'claude',
        'top': [
          {'robo': 'edge-suporte', 'perfil': 'claude-cliente', 'usd': 2.1, 'chamadas': 141},
        ],
      };
      await _abrir(t, CartaoPrevisaoClaude(store: PrevisaoClaudeStore(fonte: _FontePrevisao(r))));
      expect(find.text('US\$ 3,50'), findsOneWidget);
      expect(find.text('US\$ 11,70'), findsOneWidget);
      expect(find.text('US\$ 8,30'), findsOneWidget);
      expect(find.textContaining('edge-suporte (claude-cliente): US\$ 2,10 · 141 chamadas'), findsOneWidget);
    });

    testWidgets('ainda não ligado no servidor: faixa calma', (t) async {
      final s = PrevisaoClaudeStore(
          fonte: _FontePrevisao(null, falha: Exception('PGRST202: Could not find the function public.admin_credito_claude_previsao')));
      await _abrir(t, CartaoPrevisaoClaude(store: s));
      expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
    });
  });
}
