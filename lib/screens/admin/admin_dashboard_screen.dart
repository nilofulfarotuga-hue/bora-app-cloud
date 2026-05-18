import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart' show routeObserver;
import '../../config/app_colors.dart';
import '../../services/admin_push_service.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/admin_realtime_metrics_card.dart';
import 'admin_advanced_kpis_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_cancellation_requests_screen.dart';
import 'admin_catalog_screen.dart';
import 'admin_clients_screen.dart';
import 'admin_complaints_screen.dart';
import 'admin_crosstalk_screen.dart';
import 'admin_driver_approval_screen.dart';
import 'admin_driver_payments_screen.dart';
import 'admin_cashbacks_screen.dart';
import 'admin_category_mapping_screen.dart';
import 'admin_drivers_screen.dart';
import 'admin_edge_functions_screen.dart';
import 'admin_live_orders_map_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_global_search_screen.dart';
import 'admin_partner_payouts_screen.dart';
import 'admin_partner_settlements_screen.dart';
import 'admin_referrals_screen.dart';
import 'admin_search_kpi_screen.dart';
import 'admin_send_notification_screen.dart';
import 'admin_settlements_screen.dart';
import 'admin_support_stats_screen.dart';
import 'admin_knowledge_screen.dart';
import 'admin_pending_actions_screen.dart';
import 'admin_skill_suggestions_screen.dart';
import '../../widgets/admin_closed_partners_card.dart';
import '../../widgets/admin_reservations_today_card.dart';
import 'admin_partners_pending_screen.dart';
import 'admin_partners_screen.dart';
import 'admin_dispatch_settings_screen.dart';
import 'admin_platform_settings_screen.dart';
import 'admin_promo_codes_screen.dart';
import 'admin_ratings_screen.dart';
import 'admin_reservations_metrics_screen.dart';
import 'admin_reservations_screen.dart';
import 'admin_tokens_screen.dart';
import 'admin_wallets_screen.dart';

/// In-app admin dashboard.
///
/// Reads aggregated metrics from `admin_dashboard_metrics()` (server-side
/// SECURITY DEFINER RPC). The function only ever returns aggregates — never
/// row-level data — so even if this screen is reached by a non-admin the
/// blast radius is limited to four totals.
///
/// Access gating (Phase-2-B): `app_metadata.role == 'admin'` (canonical)
/// with fallback to `user_metadata.bora_role == 'admin'` and finally a
/// deprecated email allow-list. See [AuthAdminService.isAdmin].
/// Server-side `_admin_op_guard()` enforces strictly on
/// `app_metadata.role` — the Dart fallback chain exists only to keep
/// the UI usable across legacy sessions; any *action* still has to
/// pass the strict server gate.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with RouteAware {
  late Future<Map<String, dynamic>> _metricsFuture;
  int _pendingSuggestionsCount = 0;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
    _loadPendingSuggestionsCount();
    // 5F-β — registar FCM token admin + ouvir taps em pushes crosstalk_critical.
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

  // 5G — refresh do badge sempre que admin volta para o dashboard.
  @override
  void didPopNext() {
    _loadPendingSuggestionsCount();
  }

  Future<Map<String, dynamic>> _loadMetrics() async {
    final response =
        await Supabase.instance.client.rpc('admin_dashboard_metrics');
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

  Future<void> _refresh() async {
    setState(() {
      _metricsFuture = _loadMetrics();
    });
    await _metricsFuture;
    await _loadPendingSuggestionsCount();
  }

  bool get _isAuthorized => AuthAdminService.isAdmin();

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel Admin')),
        body: const Center(
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
      appBar: AppBar(
        title: const Text('Painel Admin'),
        actions: [
          // BLOCO C (2026-05-18) — Pesquisa global cross-entity.
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (clientes, entregadores, parceiros, pedidos)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminGlobalSearchScreen(),
              ),
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
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar métricas:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar de novo'),
                    ),
                  ),
                ],
              );
            }

            final m = snapshot.data ?? const <String, dynamic>{};
            final platformRevenue = _toDouble(m['platform_revenue']);
            final ordersToday = _toInt(m['orders_today']);
            final driversPayable = _toDouble(m['drivers_payable']);
            final restaurantsPayable = _toDouble(m['restaurants_payable']);
            final generatedAt = m['generated_at']?.toString() ?? '—';
            final dailyOrders = _parseDailyOrders(m['daily_orders']);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const AdminRealtimeMetricsCard(),
                const AdminClosedPartnersCard(),
                const AdminReservationsTodayCard(),
                const SizedBox(height: 8),
                _buildChart(dailyOrders),
                _MetricCard(
                  icon: Icons.account_balance_wallet,
                  iconColor: AppColors.primary,
                  title: 'Faturamento total (plataforma)',
                  value: '€${platformRevenue.toStringAsFixed(2)}',
                ),
                _MetricCard(
                  icon: Icons.receipt_long,
                  iconColor: AppColors.accent,
                  title: 'Pedidos hoje',
                  value: ordersToday.toString(),
                ),
                _MetricCard(
                  icon: Icons.local_shipping,
                  iconColor: Colors.blue,
                  title: 'A pagar — drivers',
                  value: '€${driversPayable.toStringAsFixed(2)}',
                ),
                _MetricCard(
                  icon: Icons.restaurant,
                  iconColor: Colors.purple,
                  title: 'A pagar — restaurantes',
                  value: '€${restaurantsPayable.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 20),
                Text(
                  'Gestão',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _NavCard(
                  icon: Icons.receipt_long,
                  title: 'Pedidos',
                  subtitle: 'Ver, filtrar e cancelar pedidos',
                  color: AppColors.accent,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminOrdersScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.delivery_dining,
                  title: 'Estafetas',
                  subtitle: 'Lista e estado de todos os estafetas',
                  color: Colors.blue,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminDriversScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.how_to_reg,
                  title: 'Aprovações',
                  subtitle: 'Candidaturas pendentes, aprovadas e rejeitadas',
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminDriverApprovalScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.payments,
                  title: 'Pagamentos',
                  subtitle: 'Saques e ganhos semanais dos estafetas',
                  color: AppColors.primary,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminDriverPaymentsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.account_balance,
                  title: 'Settlements semanais',
                  subtitle: 'Fecho semanal driver + processar MBWay',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminSettlementsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.event_seat,
                  title: 'Acerto reservas parceiros',
                  subtitle:
                      'Créditos €2 usados pelos clientes — pagar ao restaurante',
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminPartnerSettlementsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  // Q1 (2026-05-17) — Repasses a parceiros (admin_partner_payouts trio).
                  icon: Icons.payments_outlined,
                  title: 'Repasses parceiros',
                  subtitle:
                      'Marcar pagamentos a parceiros · summary por período · CSV',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminPartnerPayoutsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.storefront,
                  title: 'Parceiros',
                  subtitle: 'Activar e desactivar restaurantes/lojas',
                  color: Colors.purple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminPartnersScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.how_to_reg,
                  title: 'Aprovação de parceiros',
                  subtitle: 'Pendentes, aprovados, rejeitados',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminPartnersPendingScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.event_seat,
                  title: 'Reservas',
                  subtitle: 'Reservas de mesa em todos os restaurantes',
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminReservationsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.bar_chart,
                  title: 'Métricas Reservas Pro',
                  subtitle: 'KPIs de reservas (7/30/90 dias)',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminReservationsMetricsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.star_outline,
                  title: 'Avaliações',
                  subtitle: 'Casos problemáticos e denúncias',
                  color: Colors.amber,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminRatingsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.people_outline,
                  title: 'Clientes',
                  subtitle: 'Listar, banir, suspender, ver histórico',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminClientsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.account_balance_wallet,
                  title: 'Tokens',
                  subtitle: 'Saldo, atribuir, revogar (clientes + estafetas)',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminTokensScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Catálogo',
                  subtitle: 'Produtos por parceiro: activar/desactivar, preço',
                  color: Colors.brown,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminCatalogScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.report_problem_outlined,
                  title: 'Reclamações',
                  subtitle: 'Inbox de reclamações e suporte',
                  color: Colors.redAccent,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminComplaintsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.insights,
                  title: 'KPIs Avançado',
                  subtitle: 'Zonas quentes, ticket médio, conversão',
                  color: Colors.cyan,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminAdvancedKpisScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.wallet,
                  title: 'Wallets',
                  subtitle: 'Saldos livres + tokens dos clientes',
                  color: Colors.green,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminWalletsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.map,
                  title: 'Pedidos ao Vivo',
                  subtitle: 'Mapa em tempo real · pickups, dropoffs, drivers',
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminLiveOrdersMapScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.cancel_schedule_send,
                  title: 'Pedidos de Cancelamento',
                  subtitle: 'Aprovar / rejeitar pedidos driver/parceiro',
                  color: Colors.deepOrange,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminCancellationRequestsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.local_offer,
                  title: 'Promo Codes',
                  subtitle: 'Criar e desactivar códigos promocionais',
                  color: Colors.pinkAccent,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminPromoCodesScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.history,
                  title: 'Histórico de Acções',
                  subtitle: 'Audit log de todas as acções admin',
                  color: Colors.blueGrey,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminAuditLogScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.settings,
                  title: 'Configurações',
                  subtitle: 'Pricing, fees, wallet split, cashback %',
                  color: Colors.grey,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminPlatformSettingsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Configurações de Despacho',
                  subtitle:
                      'Timeouts, retry, limite parceiro (REGRAS 2-5)',
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminDispatchSettingsScreen())),
                ),
                const SizedBox(height: 10),
                // T5.1
                _NavCard(
                  icon: Icons.card_giftcard,
                  title: 'Referrals',
                  subtitle: 'Convites, conversão, top referrers',
                  color: Colors.purple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminReferralsScreen())),
                ),
                const SizedBox(height: 10),
                // T5.2
                _NavCard(
                  icon: Icons.celebration,
                  title: 'Cashbacks',
                  subtitle: 'Histórico cashback + total mês',
                  color: Colors.green,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminCashbacksScreen())),
                ),
                const SizedBox(height: 10),
                // T2.2
                _NavCard(
                  icon: Icons.search,
                  title: 'Personalização',
                  subtitle: 'Top buscas + parceiros mais favoritados',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminSearchKpiScreen())),
                ),
                const SizedBox(height: 10),
                // T2.3
                _NavCard(
                  icon: Icons.campaign,
                  title: 'Enviar notificação',
                  subtitle: 'Manual a 1 cliente ou broadcast',
                  color: Colors.amber,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminSendNotificationScreen())),
                ),
                const SizedBox(height: 10),
                // T5.5
                _NavCard(
                  icon: Icons.cloud_outlined,
                  title: 'Edge Functions',
                  subtitle: 'Lista + erros recentes (mbway, geral)',
                  color: Colors.cyan,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminEdgeFunctionsScreen())),
                ),
                const SizedBox(height: 10),
                // Sessão 6 B3 — Estatísticas robô IA
                _NavCard(
                  icon: Icons.smart_toy_outlined,
                  title: 'Estatísticas Suporte IA',
                  subtitle: 'Sessões, resolução, tokens, custo Gemini',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminSupportStatsScreen())),
                ),
                const SizedBox(height: 10),
                // Sessão 5C-α — Knowledge Base (RAG)
                _NavCard(
                  icon: Icons.menu_book_outlined,
                  title: 'Knowledge Base',
                  subtitle: 'RAG embeddings · Obsidian + knowledge + rules',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminKnowledgeScreen())),
                ),
                const SizedBox(height: 10),
                // Sessão 5B-α — Propostas IA (write_shadow)
                _NavCard(
                  icon: Icons.fact_check_outlined,
                  title: 'Propostas IA',
                  subtitle: 'Aprovar/rejeitar acções WRITE do robô',
                  color: const Color(0xFFE65100),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminPendingActionsScreen())),
                ),
                const SizedBox(height: 10),
                // Sessão 5D — Sugestões de skills novas (auto-suggest)
                // 5G — badge contador propostas pendentes
                _NavCard(
                  icon: Icons.auto_awesome,
                  title: 'Sugestões Skills IA',
                  subtitle: 'Skills novas propostas pelo cron semanal',
                  color: const Color(0xFFFF8F00),
                  badgeCount: _pendingSuggestionsCount,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminSkillSuggestionsScreen())),
                ),
                const SizedBox(height: 10),
                // Sessão 5F — Comunicação Robô A ↔ Robô B (crosstalk)
                _NavCard(
                  icon: Icons.forum_outlined,
                  title: 'Comunicação A↔B',
                  subtitle: 'Perguntas do robô A ao robô B + respostas RAG',
                  color: const Color(0xFF1B5E20),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminCrosstalkScreen())),
                ),
                const SizedBox(height: 10),
                // T1: Category mapping
                _NavCard(
                  icon: Icons.account_tree,
                  title: 'Mapeamento de categorias',
                  subtitle: '281 roots → 23 secções · revisão admin',
                  color: Colors.brown,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AdminCategoryMappingScreen())),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Atualizado: $generatedAt',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pedidos por dia',
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
                          // Format: dd/MM from yyyy-MM-dd
                          String label;
                          if (d.length >= 10) {
                            label =
                                '${d.substring(8, 10)}/${d.substring(5, 7)}';
                          } else {
                            label = d;
                          }
                          return Text(label,
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.grey));
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

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: iconColor.withValues(alpha: 0.15),
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
                          color: Colors.grey.shade700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
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

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            if (badgeCount > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Text(
                    badgeCount > 99 ? '99+' : badgeCount.toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Icon(Icons.chevron_right, color: color),
      ),
    );
  }
}
