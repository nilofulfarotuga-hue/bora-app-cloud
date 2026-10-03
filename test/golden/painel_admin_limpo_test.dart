import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/admin/admin_dashboard_content.dart';
import 'package:bora_app/screens/admin/admin_menu_accordion.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';

import 'fabrica_de_fotos.dart';

/// [painel-admin-limpo · 14/09/2026] Fotografias do painel novo, com os
/// NÚMEROS REAIS que o RPC `admin_dashboard_metrics_v2` devolveu em produção
/// às 00:53 de Lisboa de 14/09 (JWT de admin simulado, ver relatório):
/// hoje 14/09 com zero pedidos (o demo de 13/09 já não conta), semana fechada
/// 07/09 a 13/09 com 40,34 € a pagar = estafetas 7,04 + Goola 21,80 +
/// barbeiro 11,50, e o gráfico dos 7 dias sem demo.
///
/// Servem de "depois" para o relatório e de rede: se alguém partir o layout
/// (overflow), o teste falha aqui.
const metricsReais = <String, dynamic>{
  'versao': 2,
  'tz': 'Europe/Lisbon',
  'generated_at': '2026-09-13T23:53:25.698491+00:00',
  'demo_visivel': false,
  'hoje': {'label': '14/09'},
  'semana': {'label': '14/09 a 20/09'},
  'entregas': {
    'hoje': 0, 'entregues_hoje': 0, 'cancelados_hoje': 0, 'em_curso': 0,
    'atrasados': 0, 'presos_sem_estafeta': 0, 'semana': 0, 'entregues_semana': 0,
  },
  'tvde': {
    'hoje': 0, 'finalizadas_hoje': 0, 'em_curso': 0, 'agendadas': 0,
    'sem_motorista_hoje': 0, 'semana': 0,
  },
  'servicos': {
    'hoje': 0, 'por_concluir': 0, 'por_confirmar': 0, 'retido_falta_n': 0,
    'retido_falta_cents': 0, 'semana': 0,
  },
  'limpeza': {'hoje': 0, 'em_curso': 0, 'por_atribuir': 0, 'semana': 0},
  'lavagem': {'hoje': 0, 'em_curso': 0, 'por_atribuir': 0, 'semana': 0},
  'reservas': {'hoje': 0, 'por_confirmar': 0, 'semana': 0},
  'dinheiro': {
    'receita_hoje': {
      'total_cents': 0, 'entregas_cents': 0, 'tvde_cents': 0, 'servicos_cents': 0,
      'limpeza_cents': 0, 'lavagem_cents': 0, 'reservas_cents': 0,
    },
    'receita_semana': {
      'total_cents': 0, 'entregas_cents': 0, 'tvde_cents': 0, 'servicos_cents': 0,
      'limpeza_cents': 0, 'lavagem_cents': 0, 'reservas_cents': 0,
    },
    'acerto_semana_fechada': {
      'label': '07/09 a 13/09',
      'week_param': '2026-09-07',
      'a_pagar_cents': 4034,
      'a_receber_cents': 0,
      'a_pagar_pendente_cents': 4034,
      'a_receber_pendente_cents': 0,
      'pendentes': 4,
      'por_tipo': {
        'driver': {'a_pagar_cents': 704, 'a_receber_cents': 0, 'pendentes': 2, 'linhas': 2},
        'partner': {'a_pagar_cents': 2180, 'a_receber_cents': 0, 'pendentes': 1, 'linhas': 1},
        'provider': {'a_pagar_cents': 1150, 'a_receber_cents': 0, 'pendentes': 1, 'linhas': 1},
      },
    },
  },
  'alertas': {
    'avisos_por_ler': 235,
    'acertos_pendentes': '4',
    'pedidos_atrasados': '0',
    'avisos_falhados_24h': 0,
    'lavagens_por_atribuir': '0',
    'limpezas_por_atribuir': '0',
    'marcacoes_por_concluir': '0',
    'reservas_por_confirmar': '0',
    'dinheiro_retido_falta_n': '0',
    'marcacoes_por_confirmar': '0',
    'tvde_sem_motorista_hoje': '0',
    'dinheiro_retido_falta_cents': '0',
    'pedidos_presos_sem_estafeta': '0',
  },
  'daily_orders': [
    {'date': '2026-09-08', 'count': 0},
    {'date': '2026-09-09', 'count': 1},
    {'date': '2026-09-10', 'count': 2},
    {'date': '2026-09-11', 'count': 1},
    {'date': '2026-09-12', 'count': 1},
    {'date': '2026-09-13', 'count': 0},
    {'date': '2026-09-14', 'count': 0},
  ],
};

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  Widget corpo({List<String> favoritos = const []}) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AdminDashboardContent(
            metrics: metricsReais,
            favoritos: favoritos,
            onToggleFavorito: (_) {},
            onOpen: (_) {},
            onOpenMenuItem: (_, __) {},
            onSetDemoVisivel: (_) {},
          ),
        ),
      );

  testWidgets('dashboard novo — cartões de cima, por área, dinheiro, gráfico e menu fechado',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'painel_admin_dashboard_2026_09_14',
      tamanho: ('telemovel_alto', const Size(390, 2100)),
      tela: corpo(favoritos: const [
        'dinheiro_dinheiro_e_acertos',
        'operacao_pedidos_ao_vivo',
        'servicos_marcacoes_por_confirmar_e_faltas',
      ]),
    );
    // Uma linha por vertical, com o nome à frente; zero aparece como zero.
    for (final v in ['Entregas', 'Bora Motorista', 'Barbearias', 'Limpeza', 'Lavagem', 'Reservas']) {
      expect(find.text(v), findsWidgets, reason: 'falta a linha $v');
    }
    expect(find.textContaining('Hoje 14/09'), findsOneWidget);
    expect(find.textContaining('a pagar 40,34 €'), findsOneWidget);
    expect(find.textContaining('4 acertos por pagar/receber'), findsOneWidget);
    // Secções do menu fechadas: nenhum ecrã à vista, só os cabeçalhos.
    expect(find.text('Operação do dia'), findsOneWidget);
    // (o favorito 'Pedidos ao Vivo' aparece como ficha em cima; a linha do menu, não)
    expect(find.widgetWithText(ListTile, 'Pedidos ao Vivo'), findsNothing);
    expect(find.text('Arquivado'), findsNothing);
  });

  testWidgets('menu arrumado — secção de dinheiro aberta e busca', (tester) async {
    await fotografaTela(
      tester,
      nome: 'painel_admin_menu_dinheiro_aberto',
      tamanho: ('telemovel_alto', const Size(390, 1700)),
      tela: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AdminMenuAccordion(
            sections: adminMenuSections(),
            favoritos: const ['dinheiro_dinheiro_e_acertos'],
            onToggleFavorito: (_) {},
            onOpen: (_, __) {},
            badges: const {'acertos': 4},
          ),
        ),
      ),
      interagir: (t) async {
        await t.tap(find.widgetWithText(ExpansionTile, 'Dinheiro e acertos'));
        await t.pumpAndSettle();
      },
    );
    expect(find.text('Pagamentos/Cartões'), findsOneWidget);
    expect(find.text('Tokens'), findsOneWidget);
    // Os sete antigos não estão na secção viva.
    expect(find.text('Fechamento Semanal — Estafetas'), findsNothing);
  });

  testWidgets('menu arrumado — arquivado à vista, com o motivo', (tester) async {
    await fotografaTela(
      tester,
      nome: 'painel_admin_menu_arquivado',
      tamanho: ('telemovel_alto', const Size(390, 1900)),
      tela: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AdminMenuAccordion(
            sections: adminMenuSections(),
            favoritos: const [],
            onToggleFavorito: (_) {},
            onOpen: (_, __) {},
          ),
        ),
      ),
      interagir: (t) async {
        await t.tap(find.byKey(const ValueKey('btn_arquivado')));
        await t.pumpAndSettle();
        await t.tap(find.text('Arquivado'));
        await t.pumpAndSettle();
      },
    );
    expect(find.textContaining('duplica o hub Dinheiro e acertos'), findsWidgets);
  });
}
