import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../main.dart' show routeObserver;
import '../../services/admin_push_service.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/admin_closed_partners_card.dart';
import '../../widgets/admin_realtime_metrics_card.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_acertos_semana_screen.dart';
import 'admin_appointments_screen.dart';
import 'admin_carwash_screen.dart';
import 'admin_cleaning_bookings_screen.dart';
import 'admin_global_search_screen.dart';
import 'admin_marcacoes_confirmacao_screen.dart';
import 'admin_menu_accordion.dart';
import 'admin_menu_registry.dart';
import 'admin_notification_failures_screen.dart';
import 'admin_notifications_inbox_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reservations_screen.dart';
import 'admin_tvde_rides_screen.dart';

/// Painel Admin (PT-BR, só o Danilo usa) — o que ele vê ao abrir.
///
/// 2026-09-14 (missão painel-admin-limpo). O que mudou e porquê:
///  · Os números de cima vêm do RPC `admin_dashboard_metrics_v2`: hora de
///    Lisboa em tudo (às 00:18 o painel mostrava "Pedidos hoje 1" — era um
///    pedido de demonstração e ainda era "ontem" em UTC), nada de demo nas
///    contas (interruptor `admin_show_demo_data` para quando ele quer testar),
///    uma linha por vertical (entregas, Bora Motorista, serviços, limpeza,
///    lavagem, reservas — zero é zero e aparece), dinheiro em três cartões
///    lidos das tabelas de acerto, e alertas que abrem o ecrã certo.
///  · O menu deixou de ser uma lista de 90 cartões: vive em
///    `admin_menu_registry.dart`, por secções fechadas, com busca, favoritos
///    e "Arquivado" no fim. Este ficheiro passou de 1745 para ~600 linhas.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with RouteAware {
  static const _kFavoritos = 'bora_admin.favoritos';

  /// Favoritos com que o painel nasce; ele muda pelo alfinete de cada linha.
  static const _favoritosIniciais = [
    'dinheiro_dinheiro_e_acertos',
    'operacao_pedidos_ao_vivo',
    'servicos_marcacoes_por_confirmar_e_faltas',
  ];

  late Future<Map<String, dynamic>> _metricsFuture;
  int _pendingSuggestionsCount = 0;
  int _unreadNotificationsCount = 0;
  List<String> _favoritos = const [];
  bool _demoBusy = false;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
    _loadPendingSuggestionsCount();
    _loadUnreadNotificationsCount();
    _loadFavoritos();
    // 5F-β — registar FCM token admin + ouvir taps em pushes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AdminPushService.registerForAdmin();
      AdminPushService.setupDeepLinks(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Refresh sempre que o admin volta para o dashboard.
  @override
  void didPopNext() {
    _refresh();
  }

  Future<Map<String, dynamic>> _loadMetrics() async {
    final response =
        await Supabase.instance.client.rpc('admin_dashboard_metrics_v2');
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Unexpected RPC response type: ${response.runtimeType}');
  }

  Future<void> _loadPendingSuggestionsCount() async {
    try {
      final response = await Supabase.instance.client
          .rpc('admin_skill_suggestions_stats');
      if (!mounted) return;
      final stats = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      setState(() {
        _pendingSuggestionsCount = (stats['pending'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {/* silent */}
  }

  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('admin_notifications')
          .select('id')
          .isFilter('read_at', null)
          .isFilter('archived_at', null)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _unreadNotificationsCount = (rows as List).length;
      });
    } catch (_) {/* silent */}
  }

  Future<void> _loadFavoritos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getStringList(_kFavoritos);
      if (!mounted) return;
      setState(() => _favoritos = v ?? List.of(_favoritosIniciais));
    } catch (_) {
      if (mounted) setState(() => _favoritos = List.of(_favoritosIniciais));
    }
  }

  Future<void> _toggleFavorito(String id) async {
    final next = List.of(_favoritos);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favoritos = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kFavoritos, next);
    } catch (_) {/* fica só em memória */}
  }

  Future<void> _refresh() async {
    setState(() {
      _metricsFuture = _loadMetrics();
    });
    try {
      await _metricsFuture;
    } catch (_) {/* o FutureBuilder mostra o erro */}
    await _loadPendingSuggestionsCount();
    await _loadUnreadNotificationsCount();
  }

  /// Interruptor "mostrar dados de demonstração" (platform_settings
  /// `admin_show_demo_data`). Por defeito desligado: demo fora das contas.
  Future<void> _setDemoVisivel(bool v) async {
    if (_demoBusy) return;
    setState(() => _demoBusy = true);
    try {
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': 'admin_show_demo_data', 'p_value': v});
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu: $e')));
      }
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  bool get _isAuthorized => AuthAdminService.isAdmin();

  void _abrir(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Painel Admin'),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Acesso negado.\nO seu email não está na lista de admins.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Painel Admin',
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (clientes, entregadores, parceiros, pedidos)',
            onPressed: () => _abrir(const AdminGlobalSearchScreen()),
          ),
          Badge(
            isLabelVisible: _unreadNotificationsCount > 0,
            label: Text(_unreadNotificationsCount > 9
                ? '9+'
                : '$_unreadNotificationsCount'),
            backgroundColor: AppColors.error,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notificações ($_unreadNotificationsCount não lidas)',
              onPressed: () => _abrir(const AdminNotificationsInboxScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _metricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.error_outline,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar métricas:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: BoraPrimaryButton(
                      onPressed: _refresh,
                      icon: Icons.refresh,
                      label: 'Tentar de novo',
                      expanded: false,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _menu(),
                ],
              );
            }

            final m = snapshot.data ?? const <String, dynamic>{};
            final alertas = _map(m['alertas']);
            final dinheiro = _map(m['dinheiro']);
            final acerto = _map(dinheiro['acerto_semana_fechada']);
            final demoVisivel = m['demo_visivel'] == true;
            final hojeLabel = _map(m['hoje'])['label']?.toString() ?? '';
            final semanaLabel = _map(m['semana'])['label']?.toString() ?? '';
            final generatedAt = m['generated_at']?.toString() ?? '—';
            final dailyOrders = _parseDailyOrders(m['daily_orders']);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (demoVisivel) _avisoDemo(),
                _alertas(alertas, acerto),
                const AdminRealtimeMetricsCard(),
                const AdminClosedPartnersCard(),
                const SizedBox(height: 8),
                _cabecalhoDia(hojeLabel, semanaLabel),
                const SizedBox(height: 8),
                _verticais(m),
                const SizedBox(height: 12),
                _dinheiro(dinheiro, acerto, hojeLabel, semanaLabel),
                const SizedBox(height: 12),
                _buildChart(dailyOrders),
                _menu(acertosPendentes: _toInt(alertas['acertos_pendentes'])),
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
              ],
            );
          },
        ),
      ),
    );
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

  Widget _alertas(Map<String, dynamic> a, Map<String, dynamic> acerto) {
    final chips = <Widget>[];
    void add(String key, String label, IconData icon, Color cor, Widget screen,
        {String? sufixo}) {
      final n = _toInt(a[key]);
      if (n <= 0) return;
      chips.add(ActionChip(
        avatar: Icon(icon, size: 16, color: cor),
        label: Text('$n $label${sufixo ?? ''}',
            style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
        side: BorderSide(color: cor.withValues(alpha: 0.5)),
        onPressed: () => _abrir(screen),
      ));
    }

    add('pedidos_presos_sem_estafeta', 'pedidos presos sem estafeta',
        Icons.warning_amber_rounded, AppColors.error,
        const AdminOrdersScreen());
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
            _abrir(const AdminMarcacoesConfirmacaoScreen(abaInicial: 1)),
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
        onPressed: () => _abrir(AdminAcertosSemanaScreen(
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
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ]);

  // --------------------------------------------------------------- verticais
  Widget _verticais(Map<String, dynamic> m) {
    final e = _map(m['entregas']);
    final t = _map(m['tvde']);
    final s = _map(m['servicos']);
    final l = _map(m['limpeza']);
    final w = _map(m['lavagem']);
    final r = _map(m['reservas']);

    Widget linha(String nome, IconData icon, Color cor, List<(String, int)> nums,
        Widget screen) {
      return InkWell(
        onTap: () => _abrir(screen),
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
      _MetricCard(
        icon: Icons.today,
        iconColor: AppColors.primary,
        title: 'Receita da Bora hoje ($hoje)',
        value: _eur(_toInt(rh['total_cents'])),
        nota: detalhe(rh),
      ),
      _MetricCard(
        icon: Icons.date_range,
        iconColor: AppColors.primary,
        title: 'Receita da semana em curso ($semana)',
        value: _eur(_toInt(rs['total_cents'])),
        nota: '${detalhe(rs)} · a semana reinicia à segunda-feira, 00:00 de Lisboa',
      ),
      _MetricCard(
        icon: Icons.account_balance_wallet,
        iconColor: AppColors.accent,
        title: 'Acerto da semana fechada ($label)',
        value: 'a pagar ${_eur(aPagar)} · a receber ${_eur(aReceber)}',
        nota: aPagarPend == 0 && aReceberPend == 0
            ? 'tudo marcado como pago/recebido'
            : 'ainda por pagar ${_eur(aPagarPend)} · ainda por receber ${_eur(aReceberPend)} · toque para abrir',
        onTap: () => _abrir(AdminAcertosSemanaScreen(
            semanaInicial: acerto['week_param']?.toString())),
      ),
    ]);
  }

  // -------------------------------------------------------------------- menu
  Widget _menu({int acertosPendentes = 0}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Gestão', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        AdminMenuAccordion(
          sections: adminMenuSections(),
          favoritos: _favoritos,
          onToggleFavorito: _toggleFavorito,
          badges: {
            'skills': _pendingSuggestionsCount,
            'acertos': acertosPendentes,
          },
        ),
      ]);

  Widget _ferramentasDoPainel(bool demoVisivel) => Card(
        child: SwitchListTile(
          secondary: const Icon(Icons.science_outlined),
          title: const Text('Mostrar dados de demonstração'),
          subtitle: const Text(
              'Contas e pedidos de teste entram nos números só enquanto isto estiver ligado.'),
          value: demoVisivel,
          onChanged: _demoBusy ? null : _setDemoVisivel,
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

  Widget _buildChart(List<_DayCount> data) {
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
                        getTitlesWidget: (value, meta) {
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
