import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../widgets/bora_support_fab.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import '../widgets/chat_bubble_button.dart';
import 'chat_screen.dart';
import '../stores/order_store.dart';
import '../stores/partner_product_store.dart';
import '../stores/restaurant_store.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell.dart';
import '../services/sound_service.dart';
import '../services/incoming_job_alert.dart';
import '../stores/session_store.dart';
import '../widgets/address_text.dart';
import '../widgets/biometric_login_tile.dart';
import '../widgets/partner_weekly_closeout_card.dart';
import 'partner/reservations/partner_reservations_home_screen.dart';
import 'partner/services/partner_services_hub_screen.dart';
import 'partner_call_driver_screen.dart';
import 'partner_earnings_screen.dart';
import 'partner_hours_screen.dart';
import 'partner_products_screen.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  final Set<String> _knownCreatedOrderIds = <String>{};
  final SoundService _soundService = SoundService();
  Timer? _vibrationTimer;
  // BUG-PT-006 (2026-05-14) — fallback de segurança. Se a condição de
  // paragem do som não disparar (latência realtime, bug logic, etc.),
  // o som auto-para após 60s para evitar loop infinito no parceiro.
  Timer? _soundTimeoutTimer;
  int _pendingReservationsCount = 0;
  final Set<String> _seenPendingReservationIds = <String>{};
  RealtimeChannel? _reservationsChannel;

  // Vertical Serviços / Barbearias — só mostra o atalho "Agenda de Marcações"
  // quando esta conta tem um service_provider associado (user_id = auth.uid()).
  bool _hasServiceProvider = false;

  // REGRA 5 — modal "Continuar +10 min / Cancelar" aparece quando
  // dispatch_online_attempt_seconds >= dispatch_max_total_seconds_with_drivers_online
  // (1200s = 20 min de tentativas reais com drivers online, conta apenas
  // tempo COM drivers online — REGRA 4). Anti-spam: cada order_id só dispara
  // o modal UMA vez por sessão da app (após decisão, backend reseta o gate
  // via dispatch_partner_decision_at + dispatch_extended_until; nova janela
  // dispara nova entrada no Set quando o ID volta a ficar elegível — mas
  // dentro da mesma sessão guardamos para evitar re-mostrar).
  RealtimeChannel? _dispatchDecisionChannel;
  final Set<String> _shownDispatchModalForOrderIds = <String>{};
  bool _isShowingDispatchModal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PartnerProductStore>().selectRestaurant(widget.restaurant);
      context.read<OrderStore>().loadOrders();
      unawaited(_loadPendingReservationsCount());
      _subscribeReservationsRealtime();
      _subscribeDispatchDecisionRealtime();
      // Verificar imediatamente se já há pedidos elegíveis (load inicial
      // pode trazer rows que já passaram o limite enquanto a app estava
      // fechada).
      unawaited(_checkPendingDispatchDecisions());
      // Defensive FCM token re-register on every dashboard boot.
      // Garante registo mesmo se partner_login_screen.saveTokenForPartner
      // falhou (token ainda não disponível na altura do login).
      NotificationService.instance
          .saveTokenForPartner(widget.restaurant.id)
          .ignore();
      unawaited(_checkServiceProvider());
    });
  }

  /// Vertical Serviços — descobre se esta conta também é dona de um
  /// service_provider (barbearia/serviços). Só nesse caso o atalho aparece.
  /// Mudança aditiva e reversível — não afecta o fluxo do restaurante.
  Future<void> _checkServiceProvider() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await Supabase.instance.client
          .from('service_providers')
          .select('id')
          .eq('user_id', uid)
          .limit(1);
      if (!mounted) return;
      final has = (rows as List).isNotEmpty;
      if (has != _hasServiceProvider) {
        setState(() => _hasServiceProvider = has);
      }
    } catch (e) {
      debugPrint('[PartnerDashboard] _checkServiceProvider error: $e');
    }
  }

  Future<void> _loadPendingReservationsCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('reservations')
          .select('id')
          .eq('restaurant_id', widget.restaurant.id)
          .eq('status', 'pending');
      if (!mounted) return;
      final list = (rows as List).cast<Map<String, dynamic>>();
      _seenPendingReservationIds
        ..clear()
        ..addAll(list.map((r) => r['id'].toString()));
      final count = list.length;
      if (count != _pendingReservationsCount) {
        setState(() => _pendingReservationsCount = count);
      }
    } catch (e) {
      debugPrint(
          '[PartnerDashboard] _loadPendingReservationsCount error: $e');
    }
  }

  void _subscribeReservationsRealtime() {
    if (_reservationsChannel != null) return;
    final channelName = 'partner_reservations_${widget.restaurant.id}';
    _reservationsChannel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'reservations',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if (rec['restaurant_id'] != widget.restaurant.id) return;
            if (rec['status'] != 'pending') return;
            final id = rec['id']?.toString();
            if (id == null || _seenPendingReservationIds.contains(id)) return;
            _seenPendingReservationIds.add(id);
            setState(() => _pendingReservationsCount += 1);
            // BUG 5 (2026-05-15) — som persistente para nova reserva pendente.
            // Mesmo padrão usado para pedidos novos (created). Idempotente.
            unawaited(_startSoundAndVibration());
            final clientName =
                (rec['client_name'] as String?)?.trim().isNotEmpty == true
                    ? rec['client_name'] as String
                    : 'cliente';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Nova reserva de $clientName'),
                backgroundColor: AppColors.warning,
                duration: const Duration(seconds: 4),
              ),
            );
            debugPrint(
                '[PartnerDashboard] realtime new pending reservation $id');
          },
        )
        .onPostgresChanges(
          // BUG A — escutar UPDATE para decrementar quando status sai de
          // 'pending' (aceitar/rejeitar/sentar/etc) e re-incrementar se
          // voltar para pending.
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reservations',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if (rec['restaurant_id'] != widget.restaurant.id) return;
            final id = rec['id']?.toString();
            if (id == null) return;
            final newStatus = rec['status'];
            final wasInSet = _seenPendingReservationIds.contains(id);
            if (newStatus != 'pending' && wasInSet) {
              _seenPendingReservationIds.remove(id);
              if (_pendingReservationsCount > 0) {
                setState(() => _pendingReservationsCount -= 1);
              }
              // BUG 5 (2026-05-15) — parar som quando deixar de haver
              // reservas pendentes. _stopSoundAndVibration() é idempotente.
              if (_pendingReservationsCount == 0) {
                _stopSoundAndVibration();
              }
              debugPrint(
                  '[PartnerDashboard] realtime pending→$newStatus reservation $id');
            } else if (newStatus == 'pending' && !wasInSet) {
              _seenPendingReservationIds.add(id);
              setState(() => _pendingReservationsCount += 1);
              debugPrint(
                  '[PartnerDashboard] realtime →pending reservation $id');
            }
          },
        )
      ..subscribe();
  }

  @override
  void dispose() {
    _reservationsChannel?.unsubscribe();
    _reservationsChannel = null;
    _dispatchDecisionChannel?.unsubscribe();
    _dispatchDecisionChannel = null;
    _vibrationTimer?.cancel();
    _soundTimeoutTimer?.cancel();
    _soundService.dispose();
    super.dispose();
  }

  // ── REGRA 5: Dispatch decision modal ─────────────────────────────────────
  // Quando o pedido está em callingDriver há ≥20 min de tentativas reais
  // (com drivers online — REGRA 4 já cuidou da contabilização no backend),
  // o parceiro precisa de decidir: continuar +10 min ou cancelar.
  void _subscribeDispatchDecisionRealtime() {
    if (_dispatchDecisionChannel != null) return;
    final channelName =
        'partner_dispatch_decision_${widget.restaurant.id}';
    _dispatchDecisionChannel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if (rec['restaurant_id'] != widget.restaurant.id) return;
            _maybeShowDispatchModalFromRow(rec);
          },
        )
      ..subscribe();
  }

  Future<void> _checkPendingDispatchDecisions() async {
    try {
      final rows = await Supabase.instance.client
          .from('orders')
          .select(
            'id, status, dispatch_online_attempt_seconds, '
            'dispatch_partner_decision_at, dispatch_extended_until, '
            'vendor_name, estimated_total, price',
          )
          .eq('restaurant_id', widget.restaurant.id)
          .eq('status', OrderStatus.callingDriver.name)
          .filter('dispatch_partner_decision_at', 'is', null);
      if (!mounted) return;
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        _maybeShowDispatchModalFromRow(row);
      }
    } catch (e) {
      debugPrint(
          '[PartnerDashboard] _checkPendingDispatchDecisions error: $e');
    }
  }

  void _maybeShowDispatchModalFromRow(Map<String, dynamic> rec) {
    if (!mounted) return;
    if (_isShowingDispatchModal) return;
    final id = rec['id']?.toString();
    if (id == null) return;
    if (_shownDispatchModalForOrderIds.contains(id)) return;
    if (rec['status'] != OrderStatus.callingDriver.name) return;
    if (rec['dispatch_partner_decision_at'] != null) return;
    final attemptRaw = rec['dispatch_online_attempt_seconds'];
    final attempts = attemptRaw is num ? attemptRaw.toInt() : 0;
    // Hardcoded threshold = default da setting dispatch_max_total_seconds_with_drivers_online.
    // Backend é a fonte de verdade; aqui só decidimos quando mostrar o modal.
    // Se admin reduzir a setting para 600s, o backend ainda dispara via realtime
    // quando attempts ≥ 600 — vamos mostrar nesse caso também (>= 600).
    // Para evitar mostrar prematuramente em ambientes onde a setting é maior,
    // usamos 1200s como gate mínimo aqui (≈20 min).
    if (attempts < 1200) return;
    _shownDispatchModalForOrderIds.add(id);
    final vendorName = rec['vendor_name'] as String? ?? 'Pedido';
    final totalRaw = rec['estimated_total'] ?? rec['price'];
    final total = totalRaw is num ? totalRaw.toDouble() : 0.0;
    unawaited(_showDispatchDecisionModal(
      orderId: id,
      vendorName: vendorName,
      total: total,
      attemptSeconds: attempts,
    ));
  }

  Future<void> _showDispatchDecisionModal({
    required String orderId,
    required String vendorName,
    required double total,
    required int attemptSeconds,
  }) async {
    if (!mounted) return;
    _isShowingDispatchModal = true;
    final minutes = (attemptSeconds / 60).floor();
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.local_shipping_outlined,
            size: 36, color: AppColors.warning),
        title: const Text('Sem estafetas disponíveis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Já tentámos atribuir um estafeta ao pedido de "$vendorName" '
              'durante $minutes minutos sem sucesso.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            const Text(
              'O que pretende fazer?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: €${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar pedido'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'continue_10min'),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Continuar +10 min'),
          ),
        ],
      ),
    );

    _isShowingDispatchModal = false;
    if (action == null || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'partner_dispatch_decision',
        params: {'p_order_id': orderId, 'p_action': action},
      );
      if (!mounted) return;
      final msg = action == 'continue_10min'
          ? 'Continuamos a procurar estafeta…'
          : 'Pedido cancelado.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: action == 'continue_10min'
              ? AppColors.success
              : AppColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
      debugPrint(
          '[PartnerDashboard] dispatch decision $action OK order=$orderId');
    } catch (e) {
      debugPrint(
          '[PartnerDashboard] partner_dispatch_decision error: $e');
      if (!mounted) return;
      // Permite re-tentar se RPC falhou.
      _shownDispatchModalForOrderIds.remove(orderId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro a registar decisão: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _startVibrationLoop() async {
    if (_vibrationTimer != null) return;
    if (!(await Vibration.hasVibrator())) return;
    Vibration.vibrate(duration: 400);
    _vibrationTimer =
        Timer.periodic(const Duration(milliseconds: 2500), (_) {
      Vibration.vibrate(duration: 400);
    });
  }

  void _stopVibrationLoop() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  // BUG-PT-006 (2026-05-14) — helpers centralizados que combinam som +
  // vibração + timeout de segurança. Tudo passa por aqui para garantir
  // que os 3 ciclos param em sincronia.
  Future<void> _startSoundAndVibration() async {
    unawaited(_soundService.playLoop());
    unawaited(_startVibrationLoop());
    // Fallback: máximo 60s. Se a condição lógica de paragem não disparar
    // (takeaway com latência realtime, status nunca muda, etc.), o
    // parceiro NÃO fica com som infinito.
    _soundTimeoutTimer?.cancel();
    _soundTimeoutTimer = Timer(const Duration(seconds: 60), () {
      debugPrint('[BUG-PT-006] Som auto-parado após timeout 60s');
      _stopSoundAndVibration();
    });
  }

  void _stopSoundAndVibration() {
    unawaited(_soundService.stop());
    _stopVibrationLoop();
    _soundTimeoutTimer?.cancel();
    _soundTimeoutTimer = null;
  }

  Future<void> _handleTestMode() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    // L3 — troca de modo, não "Sair": preserva biometria.
    authStore.logout(wipeBiometrics: false);
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleNewOrders(List<OrderModel> orders) async {
    final createdIds = orders
        .where((order) =>
            order.status == OrderStatus.created &&
            !(order.paymentMethod == PaymentMethod.mbway &&
              order.paymentStatus == PaymentStatus.pending))
        .map((order) => order.id)
        .toSet();

    if (createdIds.isNotEmpty) {
      // Só (re)inicia se houver pedidos created que ainda não tinham
      // sido vistos — evita reset do timeout 60s a cada rebuild.
      final hasNewOrders =
          createdIds.any((id) => !_knownCreatedOrderIds.contains(id));
      if (hasNewOrders) {
        unawaited(_startSoundAndVibration());
        // Parte 1 (rodada 2) — alerta insistente full-screen (canal urgente) por
        // cada pedido NOVO; tocar abre a app (type 'new_order' já roteado pelo
        // handler de tap). Complementa o som in-app com heads-up do sistema.
        for (final order in orders) {
          if (order.status != OrderStatus.created) continue;
          if (_knownCreatedOrderIds.contains(order.id)) continue;
          IncomingJobAlert.show(
            id: order.id,
            type: 'new_order',
            title: '🔔 Novo pedido!',
            body: 'Toca para abrir e aceitar o pedido.',
            extraPayload: {'orderId': order.id},
          );
        }
      }
    } else {
      _stopSoundAndVibration();
    }

    // Pedidos que saíram de 'created' (aceites/expirados) → dispensa o alerta.
    for (final id in _knownCreatedOrderIds) {
      if (!createdIds.contains(id)) IncomingJobAlert.dismiss(id);
    }
    _knownCreatedOrderIds
      ..clear()
      ..addAll(createdIds);
  }

  String _ordersLabel(int count) {
    return count == 1 ? '1 pedido' : '$count pedidos';
  }

  double _sumEarningsSince(List<OrderModel> orders, DateTime threshold) {
    var total = 0.0;
    for (final order in orders) {
      if (order.createdAt.isBefore(threshold)) continue;
      total += _partnerRevenue(order);
    }
    return total;
  }

  double _partnerRevenue(OrderModel order) {
    final commission = order.platformCommissionAmount;
    final itemsValue = order.subtotal > 0
        ? order.subtotal
        : (order.total - order.deliveryFee - order.serviceFee);
    final revenue = itemsValue - commission;
    return revenue > 0 ? revenue : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerStore = context.watch<PartnerProductStore>();
    final orderStore = context.watch<OrderStore>();
    final restaurantStore = context.watch<RestaurantStore>();
    final currentRestaurant = restaurantStore.restaurants.firstWhere(
      (r) => r.id == widget.restaurant.id,
      orElse: () => widget.restaurant,
    );
    final products = partnerStore.productsForRestaurant(widget.restaurant.id);
    final availableProducts =
        products.where((product) => product.isAvailable).length;

    final partnerOrders =
        orderStore.partnerOrdersForRestaurant(widget.restaurant.name);

    // BUG-UI-04 (2026-05-20) — split active vs. history so the dashboard
    // doesn't accumulate every delivered/cancelled/rejected order forever.
    //
    // Decisão Danilo (2026-05-20): `rejected` é estado terminal (parceiro
    // recusou) e DEVE aparecer no histórico junto com delivered/cancelled —
    // NÃO ficar preso na lista activa. Os 3 estados terminais (delivered,
    // cancelled, rejected) saem do active e entram no historical bottom sheet.
    final activePartnerOrders = partnerOrders
        .where((o) =>
            o.status != OrderStatus.delivered &&
            o.status != OrderStatus.cancelled &&
            o.status != OrderStatus.rejected)
        .toList();
    final historicalPartnerOrders = partnerOrders
        .where((o) =>
            o.status == OrderStatus.delivered ||
            o.status == OrderStatus.cancelled ||
            o.status == OrderStatus.rejected)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleNewOrders(activePartnerOrders);
    });

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(const Duration(days: 6));
    final todayCount = partnerOrders
        .where((order) => !order.createdAt.isBefore(startOfToday))
        .length;
    final weekCount = partnerOrders
        .where((order) => !order.createdAt.isBefore(startOfWeek))
        .length;
    final totalCount = partnerOrders.length;

    final todayEarnings = _sumEarningsSince(partnerOrders, startOfToday);
    final weekEarnings = _sumEarningsSince(partnerOrders, startOfWeek);
    final totalEarnings = _sumEarningsSince(
      partnerOrders,
      DateTime.fromMillisecondsSinceEpoch(0),
    );

    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final subtitleColor = appBarForeground.withValues(alpha: 0.7);

    NotificationService.setupBroadcastDeepLink(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.restaurant.name,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.restaurant.cuisineType,
              style: theme.textTheme.bodySmall?.copyWith(
                color: subtitleColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          const NotificationBell(),
          TextButton.icon(
            onPressed: () => restaurantStore.toggleRestaurantOnline(
                widget.restaurant.id, !currentRestaurant.isOnline),
            style: TextButton.styleFrom(
              foregroundColor: currentRestaurant.isOnline
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
            icon: Icon(currentRestaurant.isOnline
                ? Icons.circle
                : Icons.circle_outlined),
            label: Text(currentRestaurant.isOnline ? 'ONLINE' : 'OFFLINE'),
          ),
          TextButton.icon(
            onPressed: _handleTestMode,
            style: TextButton.styleFrom(foregroundColor: appBarForeground),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Teste'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentRestaurant.reservationsEnabled &&
                    _pendingReservationsCount > 0) ...[
                  _PendingReservationsBadge(
                    count: _pendingReservationsCount,
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => PartnerReservationsHomeScreen(
                              restaurantId: currentRestaurant.id,
                              restaurantName: currentRestaurant.name,
                            ),
                          ),
                        )
                        // BUG A — refresh ao voltar de Reservas Pro.
                        .then((_) {
                      if (mounted) _loadPendingReservationsCount();
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                _EarningsSummary(
                  todayAmount: todayEarnings,
                  weekAmount: weekEarnings,
                  totalAmount: totalEarnings,
                  todayLabel: _ordersLabel(todayCount),
                  weekLabel: _ordersLabel(weekCount),
                  totalLabel: _ordersLabel(totalCount),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerEarningsScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Ver detalhe de ganhos'),
                  ),
                ),
                const SizedBox(height: 8),
                // M2 (2026-06-12) — fecho semanal read-only (transparência).
                PartnerWeeklyCloseoutCard(restaurantId: widget.restaurant.id),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerHoursScreen(
                          restaurant: currentRestaurant,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Horários de funcionamento'),
                  ),
                ),
                const SizedBox(height: 24),
                _OverviewCard(
                  totalProducts: products.length,
                  availableProducts: availableProducts,
                ),
                const SizedBox(height: 16),
                _ReservationsToggleCard(
                  enabled: currentRestaurant.reservationsEnabled,
                  onChanged: (value) => restaurantStore
                      .toggleReservationsEnabled(currentRestaurant.id, value),
                ),
                const SizedBox(height: 8),
                _TakeawayToggleCard(
                  restaurant: currentRestaurant,
                  onToggleTakeaway: (value) => restaurantStore
                      .toggleTakeawayEnabled(currentRestaurant.id, value),
                  onToggleCurbside: (value) => restaurantStore
                      .toggleCurbsideEnabled(currentRestaurant.id, value),
                  onPrepMinutesChanged: (minutes) =>
                      restaurantStore.setTakeawayDefaultPrepMinutes(
                          currentRestaurant.id, minutes),
                ),
                const SizedBox(height: 8),
                // L3 — login com biometria (esconde-se sem biometria).
                const BiometricLoginTile(
                  role: 'partner',
                  margin: EdgeInsets.zero,
                ),
                if (currentRestaurant.reservationsEnabled) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => PartnerReservationsHomeScreen(
                                restaurantId: currentRestaurant.id,
                                restaurantName: currentRestaurant.name,
                              ),
                            ),
                          )
                          // BUG A — refresh ao voltar de Reservas Pro.
                          .then((_) {
                        if (mounted) _loadPendingReservationsCount();
                      }),
                      icon: const Icon(Icons.event_seat),
                      label: const Text('Reservas Pro'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (historicalPartnerOrders.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showHistorySheet(
                          context, historicalPartnerOrders),
                      icon: const Icon(Icons.history, size: 18),
                      label: Text(
                          'Ver Histórico (${historicalPartnerOrders.length})'),
                    ),
                  ),
                _OrdersSection(
                  orders: activePartnerOrders,
                  onAccept: (order) async {
                    final accepted =
                        await orderStore.restaurantAcceptOrder(order);
                    cancelPartnerOrderNotification(order.id);
                    if (!context.mounted) return;
                    // BUG F (2026-05-13) — incluir ultimos 4 chars do order id
                    // para o parceiro identificar QUAL pedido em situacoes
                    // com varios pedidos simultaneos.
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = accepted
                        ? 'Pedido aceite — #$shortId. Prepare os itens.'
                        : 'Não foi possível aceitar o pedido — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                  onReject: (order) async {
                    final rejected =
                        await orderStore.restaurantRejectOrder(order);
                    cancelPartnerOrderNotification(order.id);
                    if (!context.mounted) return;
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = rejected
                        ? 'Pedido rejeitado — #$shortId.'
                        : 'Não foi possível rejeitar o pedido — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                  onCallDriver: (order) async {
                    final ready = await orderStore.restaurantMarkReady(order);
                    if (!context.mounted) return;
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = ready
                        ? 'Estafeta a caminho — #$shortId'
                        : 'Não foi possível chamar o estafeta — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Ações rápidas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Gerir produtos',
                  description:
                      'Atualize o catálogo, ajuste disponibilidade e mantenha os itens organizados.',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerProductsScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.local_shipping_outlined,
                  label: 'Chamar estafeta',
                  description:
                      'Criar um pedido de entrega com os produtos disponíveis para envio imediato.',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerCallDriverScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    );
                  },
                ),
                // Vertical Serviços / Barbearias — atalho aditivo, só visível
                // quando esta conta tem um service_provider associado.
                if (_hasServiceProvider) ...[
                  const SizedBox(height: 12),
                  _ActionButton(
                    icon: Icons.calendar_month,
                    label: 'Agenda de Marcações',
                    description:
                        'Gerir marcações, serviços, profissionais e financeiro do teu negócio de serviços.',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PartnerServicesHubScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// BUG-UI-04 (2026-05-20) — Bottom sheet com pedidos finalizados
  /// (delivered / cancelled / rejected). Lista vem já ordenada
  /// desc por createdAt do `build()`.
  Future<void> _showHistorySheet(
    BuildContext context,
    List<OrderModel> history,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 8),
                      Text(
                        'Histórico (${history.length})',
                        style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = history[i];
                      final shortId = o.id.length >= 6
                          ? o.id.substring(0, 6).toUpperCase()
                          : o.id.toUpperCase();
                      final statusColor = o.status == OrderStatus.delivered
                          ? Colors.green.shade700
                          : Colors.red.shade700;
                      final statusLabel = o.status == OrderStatus.delivered
                          ? 'Entregue'
                          : o.status == OrderStatus.cancelled
                              ? 'Cancelado'
                              : 'Rejeitado';
                      final when = _formatHistoryDate(o.createdAt);
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '#$shortId',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    '€${o.total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Builder(
                                builder: (_) {
                                  final name =
                                      (o.customerName ?? '').trim();
                                  final phone = (o.clientPhone ?? '').trim();
                                  final label = name.isNotEmpty
                                      ? (phone.isNotEmpty
                                          ? '$name · $phone'
                                          : name)
                                      : (phone.isNotEmpty
                                          ? 'Cliente · $phone'
                                          : 'Cliente');
                                  return Text(
                                    label,
                                    style: TextStyle(
                                        color: Colors.grey.shade700),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    when,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatHistoryDate(DateTime dt) {
    final now = DateTime.now();
    final sameDay = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Hoje · $hh:$mm';
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo · $hh:$mm';
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.orders,
    required this.onAccept,
    required this.onReject,
    required this.onCallDriver,
  });

  final List<OrderModel> orders;
  final Future<void> Function(OrderModel) onAccept;
  final Future<void> Function(OrderModel) onReject;
  final Future<void> Function(OrderModel) onCallDriver;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.event_available,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nenhum pedido pendente no momento.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: orders
          .map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PartnerOrderCard(
                order: order,
                onAccept: onAccept,
                onReject: onReject,
                onCallDriver: onCallDriver,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PartnerOrderCard extends StatefulWidget {
  const _PartnerOrderCard({
    required this.order,
    required this.onAccept,
    required this.onReject,
    required this.onCallDriver,
  });

  final OrderModel order;
  final Future<void> Function(OrderModel) onAccept;
  final Future<void> Function(OrderModel) onReject;
  final Future<void> Function(OrderModel) onCallDriver;

  @override
  State<_PartnerOrderCard> createState() => _PartnerOrderCardState();
}

class _PartnerOrderCardState extends State<_PartnerOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;

  /// Anti double-tap durante a chamada `restaurantMarkReady`. Map por orderId
  /// para coexistir com o pattern usado no resto do dashboard parceiro.
  final Map<String, bool> _chamandobusy = {};

  bool get _isNew => widget.order.status == OrderStatus.created;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updateFlashing();
  }

  @override
  void didUpdateWidget(covariant _PartnerOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.status != widget.order.status) {
      _updateFlashing();
    }
  }

  void _updateFlashing() {
    if (_isNew) {
      _flashController.repeat(reverse: true);
    } else {
      _flashController.stop();
      _flashController.value = 0;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _flashController,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildContent(theme),
      ),
      builder: (context, child) {
        final highlight = theme.colorScheme.secondary.withValues(alpha: 0.22);
        final background = _isNew
            ? Color.lerp(Colors.white, highlight, _flashController.value)!
            : Colors.white;
        final elevation = _isNew ? 2.0 + (_flashController.value * 4) : 1.0;
        final borderSide = _isNew
            ? BorderSide(
                color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                width: 1.2,
              )
            : BorderSide.none;
        return Card(
          color: background,
          elevation: elevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: borderSide,
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildContent(ThemeData theme) {
    final order = widget.order;
    final isNew = _isNew;
    final shortId = order.id.length >= 6
        ? order.id.substring(0, 6).toUpperCase()
        : order.id.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#$shortId',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    isNew ? 'Novo pedido' : order.status.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isNew ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '€${order.total.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Cliente ──────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cliente',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    order.customerName ?? 'Cliente BORA',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if ((order.clientPhone ?? '').isNotEmpty)
              IconButton(
                icon: const Icon(Icons.phone, size: 20),
                tooltip: 'Ligar cliente',
                onPressed: () async {
                  final uri = Uri(scheme: 'tel', path: order.clientPhone!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            // Chat — sempre visível (não precisa de telefone). M11: badge.
            ChatBubbleButton(
              order: order,
              senderType: ChatSenderType.partner,
              chatTarget: ChatTarget.client,
              label: 'Chat cliente',
              compact: true,
            ),
          ],
        ),
        // ── Estafeta (aparece após aceitação) ────────────────────────────
        if (order.assignedDriverId != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estafeta',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      (order.driverPhone ?? '').isNotEmpty
                          ? order.driverPhone!
                          : 'Em trânsito',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if ((order.driverPhone ?? '').isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.phone, size: 20),
                  tooltip: 'Ligar estafeta',
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: order.driverPhone!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              // Chat — sempre visível (não precisa de telefone). M11: badge.
              ChatBubbleButton(
                order: order,
                senderType: ChatSenderType.partner,
                chatTarget: ChatTarget.driver,
                label: 'Chat estafeta',
                compact: true,
              ),
            ],
          ),
        ],
        if ((order.dropoffAddress ?? '').isNotEmpty ||
            order.destination != null)
          _InfoRow(
            label: 'Entrega',
            value: '',
            valueWidget: AddressText(
              rawAddress: order.dropoffAddress,
              coords: order.destination,
            ),
          ),
        // PROMPT C — Takeaway badges (banner discreto no topo + alerta curbside).
        if (order.isTakeaway) ...[
          const SizedBox(height: 8),
          _TakeawayBadge(order: order),
          const SizedBox(height: 6),
          _TakeawayPaymentIndicator(order: order),
        ],
        if (order.isTakeaway && order.takeawayIsCurbside) ...[
          const SizedBox(height: 8),
          _CurbsideAlert(info: order.takeawayCurbsideInfo),
        ],
        const SizedBox(height: 12),
        Text(
          'Itens',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (order.items.isEmpty)
          Text(
            order.customerNotes?.isNotEmpty == true
                ? order.customerNotes!
                : 'Detalhes indisponíveis.',
          )
        else
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${item.quantity} × ${item.name} — €${(item.price * item.quantity).toStringAsFixed(2)}',
                  ),
                  // Opções escolhidas pelo cliente (acompanhamentos, extras,
                  // toppings...) — o parceiro precisa de as ver para preparar.
                  // T1: displayOptions inclui o preço cobrado por extra.
                  if (item.displayOptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 14, top: 1),
                      child: Text(
                        item.displayOptions
                            .map((o) => '${o.group}: ${o.items.join(', ')}')
                            .join('\n'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            // PROMPT C — Takeaway: aceitar com ETA picker (8 opções) em vez de
            // accept directo. Restantes status takeaway tratam-se em
            // _buildTakeawayActionButton.
            if (order.isTakeaway &&
                order.status == OrderStatus.created) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showTakeawayEtaPicker(order),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Aceitar com ETA'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onReject(order),
                  icon: const Icon(Icons.close),
                  label: const Text('Rejeitar'),
                ),
              ),
            ] else if (order.status == OrderStatus.created) ...[
              Expanded(
                child: Semantics(
                  identifier: 'btn_aceitar_pedido',
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onAccept(order);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Aceitar pedido'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  identifier: 'btn_rejeitar_pedido',
                  child: OutlinedButton.icon(
                    onPressed: () {
                      widget.onReject(order);
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Rejeitar'),
                  ),
                ),
              ),
            ] else if (order.isTakeaway) ...[
              Expanded(child: _buildTakeawayActionButton(order)),
            ] else ...[
              Expanded(child: _buildBotaoEstafeta(order)),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _chamarEstafeta(OrderModel order) async {
    final orderId = order.id;
    if (_chamandobusy[orderId] == true) return;

    setState(() => _chamandobusy[orderId] = true);
    try {
      await widget.onCallDriver(order);
    } finally {
      if (mounted) {
        setState(() => _chamandobusy.remove(orderId));
      }
    }
  }

  // ─── Takeaway actions (PROMPT C) ─────────────────────────────────────────

  /// Opções de ETA mostradas no bottom sheet (BR §14.9c).
  static const List<int> _kTakeawayEtaOptions = [3, 5, 10, 15, 20, 30, 45, 60];

  /// Abre bottom sheet com 8 opções de ETA. Default destacado = restaurante
  /// `takeawayDefaultPrepMinutes` (fallback 15). Ao confirmar, chama RPC
  /// `partner_takeaway_accept(p_order_id, p_prep_minutes)`.
  Future<void> _showTakeawayEtaPicker(OrderModel order) async {
    final orderId = order.id;
    if (_chamandobusy[orderId] == true) return;

    final restaurantStore = context.read<RestaurantStore>();
    int defaultMinutes = 15;
    final vendor = order.vendorName;
    if (vendor != null) {
      final matches = restaurantStore.restaurants.where((r) => r.name == vendor);
      if (matches.isNotEmpty) {
        defaultMinutes = matches.first.takeawayDefaultPrepMinutes;
      }
    }

    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: false,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Aceitar pedido — tempo de preparação',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'O cliente será notificado com este tempo.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              ..._kTakeawayEtaOptions.map((mins) {
                final isDefault = mins == defaultMinutes;
                return ListTile(
                  leading: Icon(
                    Icons.timer_outlined,
                    color: isDefault ? AppColors.success : null,
                  ),
                  title: Text(
                    '$mins minutos',
                    style: TextStyle(
                      fontWeight:
                          isDefault ? FontWeight.w700 : FontWeight.w500,
                      color: isDefault ? AppColors.success : null,
                    ),
                  ),
                  trailing: isDefault
                      ? const Text(
                          'Padrão',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(mins),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (chosen == null || !mounted) return;

    // BUG-PT-006 (2026-05-14) — parar som/vibração IMEDIATAMENTE quando o
    // parceiro confirma a ETA, sem esperar pelo round-trip do realtime
    // a propagar status=preparing. Takeaway não passa por callingDriver,
    // logo a condição lógica de paragem chega tarde — UX inaceitável.
    //
    // O dashboard parent é onde vive o SoundService. Procurar pelo state
    // ancestor e chamar o helper centralizado.
    _PartnerDashboardScreenState? dashState =
        context.findAncestorStateOfType<_PartnerDashboardScreenState>();
    dashState?._stopSoundAndVibration();

    setState(() => _chamandobusy[orderId] = true);
    try {
      await Supabase.instance.client.rpc(
        'partner_takeaway_accept',
        params: {
          'p_order_id': orderId,
          'p_prep_minutes': chosen,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido aceite — pronto em $chosen min'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aceitar pedido: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _chamandobusy.remove(orderId));
    }
  }

  /// Chama RPC `partner_takeaway_mark_ready(p_order_id)`. Servidor muda status
  /// para readyForPickup e dispara push ao cliente (notify-client).
  Future<void> _markTakeawayReady(OrderModel order) async {
    final orderId = order.id;
    if (_chamandobusy[orderId] == true) return;

    setState(() => _chamandobusy[orderId] = true);
    try {
      await Supabase.instance.client.rpc(
        'partner_takeaway_mark_ready',
        params: {'p_order_id': orderId},
      );
      if (mounted) {
        final code = order.takeawayPickupCode ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(code.isEmpty
                ? 'Cliente notificado'
                : 'Cliente notificado — código de levantamento: $code'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _chamandobusy.remove(orderId));
    }
  }

  /// Chama RPC `partner_takeaway_mark_picked_up(p_order_id)`. Servidor muda
  /// status para delivered (takeaway não tem estafeta).
  Future<void> _markTakeawayPickedUp(OrderModel order) async {
    final orderId = order.id;
    if (_chamandobusy[orderId] == true) return;

    setState(() => _chamandobusy[orderId] = true);
    try {
      await Supabase.instance.client.rpc(
        'partner_takeaway_mark_picked_up',
        params: {'p_order_id': orderId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Levantamento confirmado — bom dia!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _chamandobusy.remove(orderId));
    }
  }

  /// Botão CTA específico para pedidos takeaway, consoante o status actual.
  /// Substitui o `_buildBotaoEstafeta` (que é só para delivery).
  Widget _buildTakeawayActionButton(OrderModel order) {
    final busy = _chamandobusy[order.id] == true;
    switch (order.status) {
      case OrderStatus.preparing:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: busy ? null : () => _markTakeawayReady(order),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.notifications_active),
            label: Text(busy ? 'A marcar...' : 'Marcar como Pronto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );
      case OrderStatus.readyForPickup:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: busy ? null : () => _markTakeawayPickedUp(order),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(busy
                ? 'A confirmar...'
                : 'Cliente apareceu — Confirmar levantamento'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );
      case OrderStatus.delivered:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Levantado ✓'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: AppColors.primary,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(order.status.label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.grey,
            ),
          ),
        );
      case OrderStatus.created:
      case OrderStatus.callingDriver:
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        // Estados não esperados em takeaway — defensivo.
        return const SizedBox.shrink();
    }
  }

  Widget _buildBotaoEstafeta(OrderModel order) {
    final busy = _chamandobusy[order.id] == true;

    switch (order.status) {
      case OrderStatus.preparing:
        return SizedBox(
          width: double.infinity,
          child: Semantics(
            identifier: 'btn_chamar_estafeta',
            child: ElevatedButton.icon(
              onPressed: busy ? null : () => _chamarEstafeta(order),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delivery_dining),
              label: Text(busy ? 'A chamar...' : 'Chamar estafeta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        );

      case OrderStatus.callingDriver:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            label: const Text('Aguardando estafeta...'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.grey.shade400,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.directions_bike),
            label: const Text('Estafeta a caminho'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.grey.shade400,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.delivered:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Entregue ✓'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: AppColors.primary,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(order.status.label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.grey,
            ),
          ),
        );

      // PROMPT C (2026-05-14) — pedidos takeaway são roteados via
      // _buildTakeawayActionButton (chamado do Row em _buildContent). Este
      // ramo cobre o caso defensivo de delivery alcançar readyForPickup
      // (não deveria acontecer; servidor é authoritative).
      case OrderStatus.readyForPickup:
        return const SizedBox.shrink();

      case OrderStatus.created:
        return const SizedBox.shrink();
    }
  }
}

/// PROMPT C — Badge discreto no card de pedido takeaway. Distingue
/// visualmente da lista de delivery e mostra ETA quando preparing.
class _TakeawayBadge extends StatelessWidget {
  const _TakeawayBadge({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final code = order.takeawayPickupCode;
    final readyAt = order.takeawayReadyAt;
    final prep = order.takeawayPrepMinutes;

    String detail;
    if (order.status == OrderStatus.readyForPickup && code != null) {
      detail = 'Código: $code';
    } else if (order.status == OrderStatus.preparing && readyAt != null) {
      final hh = readyAt.hour.toString().padLeft(2, '0');
      final mm = readyAt.minute.toString().padLeft(2, '0');
      detail = 'Pronto às $hh:$mm';
    } else if (order.status == OrderStatus.preparing && prep != null) {
      detail = '~$prep min';
    } else {
      detail = 'Cliente vai levantar';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_bag_outlined,
              size: 16, color: AppColors.success),
          const SizedBox(width: 6),
          Text(
            'Takeaway · $detail',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de pagamento para pedidos takeaway. Mostra ao parceiro se
/// tem de cobrar dinheiro na loja ou se o pedido já está pago online.
/// Laranja = receber cash, verde = pago online.
class _TakeawayPaymentIndicator extends StatelessWidget {
  const _TakeawayPaymentIndicator({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isCash = order.paymentMethod == PaymentMethod.cash;
    final isPaid = order.paymentStatus == PaymentStatus.paid;

    final Color color;
    final IconData icon;
    final String label;
    if (isCash) {
      color = Colors.orange.shade800;
      icon = Icons.payments_outlined;
      label = 'Receber €${order.total.toStringAsFixed(2)} na loja';
    } else if (isPaid) {
      color = AppColors.success;
      icon = Icons.check_circle_outline;
      label = 'Pago online';
    } else {
      color = Colors.grey.shade700;
      icon = Icons.hourglass_empty;
      label = 'Pagamento online pendente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// PROMPT C — Alerta visual destacado quando o cliente escolheu curbside
/// (esperar no carro). O parceiro precisa de identificar a viatura antes
/// de levar o pedido cá fora.
class _CurbsideAlert extends StatelessWidget {
  const _CurbsideAlert({required this.info});

  final String? info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade400, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURBSIDE — cliente espera no carro',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
                if (info != null && info!.isNotEmpty)
                  Text(
                    info!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade900,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueWidget});

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: valueWidget ?? Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }
}

class _EarningsSummary extends StatelessWidget {
  const _EarningsSummary({
    required this.todayAmount,
    required this.weekAmount,
    required this.totalAmount,
    required this.todayLabel,
    required this.weekLabel,
    required this.totalLabel,
  });

  final double todayAmount;
  final double weekAmount;
  final double totalAmount;
  final String todayLabel;
  final String weekLabel;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final cards = <Widget>[
          _EarningCard(
            title: 'Ganhos hoje',
            subtitle: todayLabel,
            amount: todayAmount,
            icon: Icons.today_outlined,
          ),
          _EarningCard(
            title: 'Ganhos semana',
            subtitle: weekLabel,
            amount: weekAmount,
            icon: Icons.date_range_outlined,
          ),
          _EarningCard(
            title: 'Ganhos totais',
            subtitle: totalLabel,
            amount: totalAmount,
            icon: Icons.savings_outlined,
          ),
        ];

        if (isCompact) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final formattedAmount = '€${amount.toStringAsFixed(2)}';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: primary.withValues(alpha: 0.1),
              child: Icon(icon, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedAmount,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.totalProducts,
    required this.availableProducts,
  });

  final int totalProducts;
  final int availableProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = totalProducts - availableProducts;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo do catálogo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _OverviewStat(
                  label: 'Total',
                  value: '$totalProducts',
                  icon: Icons.layers_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                _OverviewStat(
                  label: 'Disponíveis',
                  value: '$availableProducts',
                  icon: Icons.check_circle_outline,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 16),
                _OverviewStat(
                  label: 'Indisponíveis',
                  value: '$unavailable',
                  icon: Icons.pause_circle_outline,
                  color: Colors.orange.shade600,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// BR §14.10 — opt-in do parceiro para mostrar o botão "Reservar mesa" ao cliente.
class _ReservationsToggleCard extends StatelessWidget {
  const _ReservationsToggleCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SwitchListTile.adaptive(
        value: enabled,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: const Text(
          'Aceitar reservas de mesa',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          enabled
              ? 'O botão "Reservar mesa" aparece aos clientes.'
              : 'Desligado — reservas ocultas aos clientes. (BR §14.10)',
          style: const TextStyle(fontSize: 12),
        ),
        activeColor: AppColors.primary,
      ),
    );
  }
}

/// PROMPT C — Cartão com 3 controlos takeaway: switch master, switch
/// curbside (disabled se master off), input de minutos default. Padrão
/// visual segue [_ReservationsToggleCard].
class _TakeawayToggleCard extends StatefulWidget {
  const _TakeawayToggleCard({
    required this.restaurant,
    required this.onToggleTakeaway,
    required this.onToggleCurbside,
    required this.onPrepMinutesChanged,
  });

  final RestaurantModel restaurant;
  final ValueChanged<bool> onToggleTakeaway;
  final ValueChanged<bool> onToggleCurbside;
  final ValueChanged<int> onPrepMinutesChanged;

  @override
  State<_TakeawayToggleCard> createState() => _TakeawayToggleCardState();
}

class _TakeawayToggleCardState extends State<_TakeawayToggleCard> {
  late TextEditingController _prepController;

  @override
  void initState() {
    super.initState();
    _prepController = TextEditingController(
      text: widget.restaurant.takeawayDefaultPrepMinutes.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _TakeawayToggleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText =
        widget.restaurant.takeawayDefaultPrepMinutes.toString();
    if (_prepController.text != newText) {
      _prepController.text = newText;
    }
  }

  @override
  void dispose() {
    _prepController.dispose();
    super.dispose();
  }

  void _commitPrepMinutes() {
    final parsed = int.tryParse(_prepController.text.trim());
    if (parsed == null) {
      // Repor texto válido visível no input.
      _prepController.text =
          widget.restaurant.takeawayDefaultPrepMinutes.toString();
      return;
    }
    final clamped = parsed.clamp(3, 60);
    widget.onPrepMinutesChanged(clamped);
    if (clamped != parsed) {
      _prepController.text = clamped.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final takeawayEnabled = widget.restaurant.takeawayEnabled;
    final curbsideEnabled = widget.restaurant.curbsideEnabled;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: takeawayEnabled,
            onChanged: widget.onToggleTakeaway,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: const Text(
              'Aceitar pedidos para levantamento (Takeaway)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              takeawayEnabled
                  ? 'O botão "Ir buscar" aparece aos clientes.'
                  : 'Desligado — só entrega. (BR §14.9)',
              style: const TextStyle(fontSize: 12),
            ),
            activeColor: AppColors.primary,
          ),
          if (takeawayEnabled) ...[
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: curbsideEnabled,
              onChanged: widget.onToggleCurbside,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text(
                'Permitir levantamento no carro (Curbside)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                curbsideEnabled
                    ? 'Cliente pode informar matrícula e esperar no carro.'
                    : 'Apenas levantamento ao balcão.',
                style: const TextStyle(fontSize: 12),
              ),
              activeColor: AppColors.accent,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tempo de preparação padrão',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Em minutos (3-60). Aparece pré-seleccionado ao aceitar.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 76,
                    child: TextField(
                      controller: _prepController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _commitPrepMinutes(),
                      onEditingComplete: _commitPrepMinutes,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        suffixText: 'min',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _PendingReservationsBadge extends StatelessWidget {
  const _PendingReservationsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? '1 reserva pendente'
        : '$count reservas pendentes';
    return Material(
      color: AppColors.warning,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.event_seat, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toca para abrir Reservas Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
