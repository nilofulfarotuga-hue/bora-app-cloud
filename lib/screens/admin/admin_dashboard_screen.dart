import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../main.dart' show routeObserver;
import '../../services/admin_push_service.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/admin_closed_partners_card.dart';
import '../../widgets/admin_realtime_metrics_card.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_dashboard_content.dart';
import 'admin_global_search_screen.dart';
import 'admin_menu_accordion.dart';
import 'admin_menu_registry.dart';
import 'admin_notifications_inbox_screen.dart';

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
///    e "Arquivado" no fim. O desenho vive em `admin_dashboard_content.dart`
///    (widget puro, fotografável em teste); este ficheiro só carrega e navega.
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
              // Sem números não se fica sem menu: o painel continua a servir
              // para chegar a qualquer ecrã.
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 40),
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
                  Text('Gestão',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  AdminMenuAccordion(
                    sections: adminMenuSections(),
                    favoritos: _favoritos,
                    onToggleFavorito: _toggleFavorito,
                    badges: {'skills': _pendingSuggestionsCount},
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const AdminRealtimeMetricsCard(),
                const AdminClosedPartnersCard(),
                const SizedBox(height: 8),
                AdminDashboardContent(
                  metrics: snapshot.data ?? const <String, dynamic>{},
                  favoritos: _favoritos,
                  onToggleFavorito: _toggleFavorito,
                  onOpen: _abrir,
                  pendingSuggestionsCount: _pendingSuggestionsCount,
                  demoBusy: _demoBusy,
                  onSetDemoVisivel: _setDemoVisivel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
