import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_acertos_semana_screen.dart';
import 'admin_appointments_screen.dart';
import 'admin_carwash_screen.dart';
import 'admin_cleaning_bookings_screen.dart';
import 'admin_marcacoes_confirmacao_screen.dart';
import 'admin_menu_accordion.dart';
import 'admin_menu_registry.dart';
import 'admin_notification_failures_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reservations_screen.dart';
import 'admin_tvde_rides_screen.dart';

/// Corpo do Painel Admin (PT-BR): alertas, uma linha por vertical, dinheiro
/// em três cartões, gráfico, menu por secções e o interruptor de demo.
///
/// É um widget PURO: recebe o JSON de `admin_dashboard_metrics_v2` já
/// carregado e não fala com o servidor. Assim fotografa-se num teste golden
/// (as capturas do relatório de 14/09 vêm daqui) e testa-se sem Supabase.
/// Quem carrega os números e navega é o `AdminDashboardScreen`.
class AdminDashboardContent extends StatelessWidget {
  const AdminDashboardContent({
    super.key,
    required this.metrics,
    required this.favoritos,
    required this.onToggleFavorito,
    required this.onOpen,
    this.pendingSuggestionsCount = 0,
    this.demoBusy = false,
    this.onSetDemoVisivel,
    this.onOpenMenuItem,
  });

  final Map<String, dynamic> metrics;
  final List<String> favoritos;
  final void Function(String id) onToggleFavorito;

  /// Abre um ecrã (o screen faz `Navigator.push`).
  final void Function(Widget screen) onOpen;
  final int pendingSuggestionsCount;
  final bool demoBusy;
  final ValueChanged<bool>? onSetDemoVisivel;

  /// Só para testes: intercepta a abertura de itens do menu.
  final void Function(BuildContext, AdminMenuItem)? onOpenMenuItem;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final alertas = _map(m['alertas']);
    final dinheiro = _map(m['dinheiro']);
    final acerto = _map(dinheiro['acerto_semana_fechada']);
    final demoVisivel = m['demo_visivel'] == true;
    final hojeLabel = _map(m['hoje'])['label']?.toString() ?? '';
    final semanaLabel = _map(m['semana'])['label']?.toString() ?? '';
    final generatedAt = m['generated_at']?.toString() ?? '—';
    final dailyOrders = _parseDailyOrders(m['daily_orders']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (demoVisivel) _avisoDemo(),
      _alertas(context, alertas, acerto),
      _cabecalhoDia(hojeLabel, semanaLabel),
      const SizedBox(height: 8),
      _verticais(context, m),
      const SizedBox(height: 12),
      _dinheiro(dinheiro, acerto, hojeLabel, semanaLabel),
      const SizedBox(height: 12),
      _buildChart(context, dailyOrders),
      Text('Gestão', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      AdminMenuAccordion(
        sections: adminMenuSections(),
        favoritos: favoritos,
        onToggleFavorito: onToggleFavorito,
        onOpen: onOpenMenuItem,
        badges: {
          'skills': pendingSuggestionsCount,
          'acertos': _toInt(alertas['acertos_pendentes']),
        },
      ),
      const SizedBox(height: 12),
      _ferramentasDoPainel(demoVisivel),
      const SizedBox(height: 16),
      Center(
        child: Text(
          'Atualizado: $generatedAt · hora de Lisboa · '
          '${demoVisivel ? 'COM dados de demonstração' : 'sem dados de demonstração'}',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSubtle),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- alertas
  Widget _avisoDemo() => Card(
        color: AppColors.warning.withValues(alpha: 0.12),
        margin: const EdgeInsets.only(bottom: 10),
        child: const ListTile(
          leading: Icon(Icons.science_outlined, color: AppColors.warning),
          title: Text('Dados de demonstração LIGADOS',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              'Os números abaixo incluem contas e pedidos de teste. Desligue lá em baixo quando acabar de testar.'),
        ),
      );

  Widget _alertas(BuildContext context, Map<String, dynamic> a,
      Map<String, dynamic> acerto) {
    final chips = <Widget>[];
    void add(String key, String label, IconData icon, Color cor, Widget screen) {
      final n = _toInt(a[key]);
      if (n <= 0) return;
      chips.add(ActionChip(
        avatar: Icon(icon, size: 16, color: cor),
        label: Text('$n $label',
            style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
        side: BorderSide(color: cor.withValues(alpha: 0.5)),
        onPressed: () => onOpen(screen),
      ));
    }

    add('pedidos_presos_sem_estafeta', 'pedidos presos sem estafeta',
        Icons.warning_amber_rounded, AppColors.error, const AdminOrdersScreen());
    add('pedidos_atrasados', 'pedidos atrasados', Icons.timer_off_outlined,
        AppColors.warning, const AdminOrdersScreen());
    add('tvde_sem_motorista_hoje', 'corridas sem motorista hoje',
        Icons.local_taxi, AppColors.warning, const AdminTvdeRidesScreen());
    add('marcacoes_por_confirmar', 'marcações por confirmar', Icons.rule,
        AppColors.warning, const AdminMarcacoesConfirmacaoScreen());
    add('marcacoes_por_concluir', 'marcações por concluir',
        Icons.hourglass_bottom, AppColors.info,
        const AdminMarcacoesConfirmacaoScreen());
    final retidoN = _toInt(a['dinheiro_retido_falta_n']);
    if (retidoN > 0) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.money_off, size: 16, color: AppColors.error),
        label: Text(
            '${_eur(_toInt(a['dinheiro_retido_falta_cents']))} retidos por falta ($retidoN)',
            style: const TextStyle(
                color: AppColors.error, fontWeight: FontWeight.w600)),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
        onPressed: () =>
            onOpen(const AdminMarcacoesConfirmacaoScreen(abaInicial: 1)),
      ));
    }
    add('limpezas_por_atribuir', 'limpezas sem profissional',
        Icons.cleaning_services_outlined, AppColors.warning,
        const AdminCleaningBookingsScreen());
    add('lavagens_por_atribuir', 'lavagens sem lavador',
        Icons.local_car_wash_outlined, AppColors.warning,
        const AdminCarwashScreen());
    add('reservas_por_confirmar', 'reservas por confirmar',
        Icons.table_restaurant_outlined, AppColors.info,
        const AdminReservationsScreen());
    add('avisos_falhados_24h', 'avisos que falharam (24h)',
        Icons.notifications_off_outlined, AppColors.error,
        const AdminNotificationFailuresScreen());
    final pend = _toInt(a['acertos_pendentes']);
    if (pend > 0) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.account_balance_wallet_outlined,
            size: 16, color: AppColors.primary),
        label: Text('$pend acertos por pagar/receber',
            style: const TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w600)),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
        onPressed: () => onOpen(AdminAcertosSemanaScreen(
            semanaInicial: acerto['week_param']?.toString())),
      ));
    }

    if (chips.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: AppColors.success.withValues(alpha: 0.08),
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.check_circle_outline, color: AppColors.success),
          title: Text('Nada preso, nada por confirmar, nada retido.'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  // --------------------------------------------------------------- cabeçalho
  Widget _cabecalhoDia(String hoje, String semana) => Row(children: [
        const Icon(Icons.today, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Hoje $hoje · semana $semana (hora de Lisboa; a semana reinicia à segunda)',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ]);

  // --------------------------------------------------------------- verticais
  Widget _verticais(BuildContext context, Map<String, dynamic> m) {
    final e = _map(m['entregas']);
    final t = _map(m['tvde']);
    final s = _map(m['servicos']);
    final l = _map(m['limpeza']);
    final w = _map(m['lavagem']);
    final r = _map(m['reservas']);

    Widget linha(String nome, IconData icon, Color cor,
        List<(String, int)> nums, Widget screen) {
      return InkWell(
        onTap: () => onOpen(screen),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 20, color: cor),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: Text(nome,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 2,
                children: nums
                    .map((n) => RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style,
                            children: [
                              TextSpan(
                                  text: '${n.$2}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: n.$2 > 0
                                          ? AppColors.textPrimary
                                          : AppColors.textSubtle)),
                              TextSpan(
                                  text: ' ${n.$1}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ]),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Por área — hoje',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          linha('Entregas', Icons.delivery_dining, Colors.blue, [
            ('pedidos hoje', _toInt(e['hoje'])),
            ('em curso', _toInt(e['em_curso'])),
            ('atrasados', _toInt(e['atrasados'])),
            ('entregues', _toInt(e['entregues_hoje'])),
          ], const AdminOrdersScreen()),
          const Divider(height: 1),
          linha('Bora Motorista', Icons.local_taxi, const Color(0xFF0EA5E9), [
            ('corridas hoje', _toInt(t['hoje'])),
            ('em curso', _toInt(t['em_curso'])),
            ('agendadas', _toInt(t['agendadas'])),
          ], const AdminTvdeRidesScreen()),
          const Divider(height: 1),
          linha('Barbearias', Icons.content_cut, const Color(0xFF8B5CF6), [
            ('marcações hoje', _toInt(s['hoje'])),
            ('por concluir', _toInt(s['por_concluir'])),
            ('por confirmar', _toInt(s['por_confirmar'])),
          ], const AdminAppointmentsScreen()),
          const Divider(height: 1),
          linha('Limpeza', Icons.cleaning_services_outlined,
              const Color(0xFF14B8A6), [
            ('hoje', _toInt(l['hoje'])),
            ('em curso', _toInt(l['em_curso'])),
            ('sem profissional', _toInt(l['por_atribuir'])),
          ], const AdminCleaningBookingsScreen()),
          const Divider(height: 1),
          linha('Lavagem', Icons.local_car_wash_outlined, Colors.cyan, [
            ('hoje', _toInt(w['hoje'])),
            ('em curso', _toInt(w['em_curso'])),
            ('sem lavador', _toInt(w['por_atribuir'])),
          ], const AdminCarwashScreen()),
          const Divider(height: 1),
          linha('Reservas', Icons.table_restaurant_outlined, Colors.deepOrange,
              [
                ('mesas hoje', _toInt(r['hoje'])),
                ('por confirmar', _toInt(r['por_confirmar'])),
              ],
              const AdminReservationsScreen()),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- dinheiro
  Widget _dinheiro(Map<String, dynamic> d, Map<String, dynamic> acerto,
      String hoje, String semana) {
    final rh = _map(d['receita_hoje']);
    final rs = _map(d['receita_semana']);
    String detalhe(Map<String, dynamic> r) {
      final partes = <String>[];
      void p(String k, String nome) {
        final c = _toInt(r[k]);
        if (c > 0) partes.add('$nome ${_eur(c)}');
      }

      p('entregas_cents', 'entregas');
      p('tvde_cents', 'Bora Motorista');
      p('servicos_cents', 'barbearias');
      p('limpeza_cents', 'limpeza');
      p('lavagem_cents', 'lavagem');
      p('reservas_cents', 'reservas');
      return partes.isEmpty ? 'nada ainda' : partes.join(' · ');
    }

    final aPagar = _toInt(acerto['a_pagar_cents']);
    final aReceber = _toInt(acerto['a_receber_cents']);
    final aPagarPend = _toInt(acerto['a_pagar_pendente_cents']);
    final aReceberPend = _toInt(acerto['a_receber_pendente_cents']);
    final label = acerto['label']?.toString() ?? '';

    return Column(children: [
      AdminMetricCard(
        icon: Icons.today,
        iconColor: AppColors.primary,
        title: 'Receita da Bora hoje ($hoje)',
        value: _eur(_toInt(rh['total_cents'])),
        nota: detalhe(rh),
      ),
      AdminMetricCard(
        icon: Icons.date_range,
        iconColor: AppColors.primary,
        title: 'Receita da semana em curso ($semana)',
        value: _eur(_toInt(rs['total_cents'])),
        nota:
            '${detalhe(rs)} · a semana reinicia à segunda-feira, 00:00 de Lisboa',
      ),
      AdminMetricCard(
        icon: Icons.account_balance_wallet,
        iconColor: AppColors.accent,
        title: 'Acerto da semana fechada ($label)',
        value: 'a pagar ${_eur(aPagar)} · a receber ${_eur(aReceber)}',
        nota: aPagarPend == 0 && aReceberPend == 0
            ? 'tudo marcado como pago/recebido'
            : 'ainda por pagar ${_eur(aPagarPend)} · ainda por receber ${_eur(aReceberPend)} · toque para abrir',
        onTap: () => onOpen(AdminAcertosSemanaScreen(
            semanaInicial: acerto['week_param']?.toString())),
      ),
    ]);
  }

  Widget _ferramentasDoPainel(bool demoVisivel) => Card(
        child: SwitchListTile(
          secondary: const Icon(Icons.science_outlined),
          title: const Text('Mostrar dados de demonstração'),
          subtitle: const Text(
              'Contas e pedidos de teste entram nos números só enquanto isto estiver ligado.'),
          value: demoVisivel,
          onChanged: demoBusy ? null : onSetDemoVisivel,
        ),
      );

  // ------------------------------------------------------------------ gráfico
  static List<_DayCount> _parseDailyOrders(dynamic raw) {
    if (raw is! List) return const [];
    final result = <_DayCount>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final date = item['date']?.toString() ?? '';
      final count = _toInt(item['count']);
      if (date.isNotEmpty) result.add(_DayCount(date, count));
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  Widget _buildChart(BuildContext context, List<_DayCount> data) {
    if (data.isEmpty) return const SizedBox();
    final maxY =
        data.map((d) => d.count).reduce((a, b) => a > b ? a : b).toDouble();
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].count.toDouble()),
    );
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pedidos de entrega por dia (7 dias, sem demo)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                '${s.y.toInt()} pedidos',
                                const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ))
                          .toList(),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        // Um rótulo por dia; sem isto o fl_chart repetia cada
                        // data duas vezes (herdado do gráfico antigo).
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value != value.roundToDouble()) {
                            return const SizedBox();
                          }
                          final i = value.toInt();
                          if (i < 0 || i >= data.length) {
                            return const SizedBox();
                          }
                          final d = data[i].date;
                          String label;
                          if (d.length >= 10) {
                            label =
                                '${d.substring(8, 10)}/${d.substring(5, 7)}';
                          } else {
                            label = d;
                          }
                          return Text(label,
                              style: const TextStyle(
                                  fontSize: 9, color: AppColors.textSubtle));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.4,
                      preventCurveOverShooting: true,
                      color: AppColors.primary,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- helpers
  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  static String _eur(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  /// O servidor devolve alguns contadores como texto (vêm de `->>`); aqui
  /// aceita-se número ou texto, e nulo é zero.
  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Cartão de número grande com nota em letra pequena (os 3 cartões de dinheiro).
class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.nota,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String? nota;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (nota != null) ...[
                      const SizedBox(height: 4),
                      Text(nota!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSubtle)),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: AppColors.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCount {
  const _DayCount(this.date, this.count);
  final String date;
  final int count;
}
