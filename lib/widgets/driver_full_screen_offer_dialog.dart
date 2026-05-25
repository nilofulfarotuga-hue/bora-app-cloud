// Sessão 2026-05-24 (exec3 PIVOT FULL-SCREEN) — Estilo Uber/Glovo:
// quando chega uma oferta, este widget ocupa o ecrã inteiro com o cartão do
// pedido + ACEITAR/REJEITAR. Substitui o overlay-por-cima-das-apps (que era
// bloqueado pelo Android 14+/16 quando MainActivity invisível).
//
// Quem mostra:
//   1. order_store.dart no realtime UPDATE quando current_driver_offer_id == myDriverId
//   2. driver_store.dart no broadcast `driver-offer:{driverId}` (caminho rápido)
//   3. notification_service.dart `_onForegroundTaskData` (ponte FCM→FGS→main)
//
// Som: NÃO toca aqui. A notificação local (canal bora_orders_urgent_v3 com
// setSound bora_alert) é a ÚNICA fonte de som — evita duplicação. Quando o
// utilizador toca em Aceitar/Rejeitar, a notif é cancelada e o som pára.
//
// fullScreenIntent: a notif tem fullScreenIntent:true, o que acorda o ecrã +
// lança MainActivity (com showWhenLocked+turnScreenOn no manifest) mesmo se a
// app estiver em background/morta/bloqueada. Ao subir, o realtime já entregou
// o offer ao OrderStore → este dialog aparece em < 500ms.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/offer_presentation_gate.dart';
import '../services/sound_service.dart';

const Color _kBoraGreen = Color(0xFF2E7D32);
const Color _kBoraOrange = Color(0xFFE65100);
const Color _kBoraGreenDark = Color(0xFF1B5E20);
const int _kOfferTimeoutSeconds = 40; // alinhado com TTL dispatch-engine v56

class DriverFullScreenOfferDialog extends StatefulWidget {
  const DriverFullScreenOfferDialog({
    super.key,
    required this.orderId,
    required this.vendorName,
    required this.total,
    required this.distanceKm,
    required this.driverEarnings,
    this.dropoffAddress = '',
  });

  final String orderId;
  final String vendorName;
  final String total;
  final String distanceKm;
  final String driverEarnings;
  final String dropoffAddress;

  @override
  State<DriverFullScreenOfferDialog> createState() =>
      _DriverFullScreenOfferDialogState();
}

class _DriverFullScreenOfferDialogState
    extends State<DriverFullScreenOfferDialog> {
  Timer? _timer;
  int _remaining = _kOfferTimeoutSeconds;
  bool _busy = false;
  bool _closed = false;
  // Exec6.5 (2026-05-25) — som persistente até accept/reject/expire.
  // BG-unlocked não tem CallKit ringtone, precisa de fonte própria.
  final SoundService _sound = SoundService();

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('[BORA-OFFER] DriverFullScreenOfferDialog initState order=${widget.orderId} vendor=${widget.vendorName}');
    unawaited(_sound.playLoop());
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        _expire();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sound.stop();
    _sound.dispose();
    super.dispose();
  }

  void _closeDialog() {
    if (_closed) return;
    _closed = true;
    // cancelDriverOfferNotification é top-level (não método de instância) —
    // cancela a notif persistente + limpa pending_offer + fecha CallKit +
    // fecha overlay (idempotente em tudo).
    cancelDriverOfferNotification(widget.orderId).ignore();
    // Exec6 GATE (2026-05-25) — liberta o gate para o próximo pedido.
    OfferPresentationGate.markActionCompleted(widget.orderId);
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _accept() async {
    if (_busy || _closed) return;
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client
          .rpc('driver_accept_offer', params: {'p_order_id': widget.orderId});
      if (res is Map && res['ok'] == false) {
        final err = res['error']?.toString() ?? 'unknown';
        _closeDialog();
        _showSnack(
          err == 'offer_expired_or_taken'
              ? 'Oferta expirada — já foi atribuída a outro estafeta.'
              : 'Não foi possível aceitar ($err).',
        );
        return;
      }
      _closeDialog();
      _showSnack('✓ Pedido aceite');
    } catch (e) {
      _closeDialog();
      _showSnack('Erro de rede ao aceitar — tenta de novo.');
    }
  }

  Future<void> _reject() async {
    if (_busy || _closed) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .rpc('driver_reject_offer', params: {'p_order_id': widget.orderId});
    } catch (_) {
      // Mesmo se falhar, fechamos — o backend reoferece via watchdog 40s.
    }
    _closeDialog();
    // Exec6.5 (2026-05-25) — rejeitar a bonita devolve o controlo ao
    // sistema (home / app anterior do dono). Sem isto, a MainActivity
    // ficaria visível por trás a mostrar a tela laranja, o que é errado:
    // o dono estava noutra app e queremos respeitar isso.
    _minimizeApp();
  }

  void _expire() {
    _closeDialog();
    _minimizeApp();
  }

  void _minimizeApp() {
    try {
      const ch = MethodChannel('pt.boraapp.bora/native');
      ch.invokeMethod<bool>('moveTaskToBack').ignore();
    } catch (_) {}
  }

  void _showSnack(String msg) {
    final nav = NotificationService.navigatorKey.currentState;
    final ctx = nav?.context;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PopScope: o estafeta NÃO pode dispensar com back — só com ACEITAR/REJEITAR
    // ou expirar. Padrão Uber/Glovo.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(remaining: _remaining),
                const SizedBox(height: 24),
                Expanded(
                  child: _OfferCard(
                    vendorName: widget.vendorName,
                    total: widget.total,
                    distanceKm: widget.distanceKm,
                    driverEarnings: widget.driverEarnings,
                    dropoffAddress: widget.dropoffAddress,
                  ),
                ),
                const SizedBox(height: 20),
                _ActionButtons(
                  busy: _busy,
                  onAccept: _accept,
                  onReject: _reject,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.remaining});
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final ratio = remaining / _kOfferTimeoutSeconds;
    return Row(
      children: [
        const Text('🛵',
            style: TextStyle(fontSize: 32, color: Colors.white)),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'NOVO PEDIDO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 5,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ratio > 0.3 ? _kBoraGreen : _kBoraOrange,
                  ),
                ),
              ),
              Text(
                '${remaining}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.vendorName,
    required this.total,
    required this.distanceKm,
    required this.driverEarnings,
    required this.dropoffAddress,
  });

  final String vendorName;
  final String total;
  final String distanceKm;
  final String driverEarnings;
  final String dropoffAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vendorName,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: _kBoraGreenDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (dropoffAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: _kBoraOrange, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dropoffAddress,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const Spacer(),
          _StatRow(icon: Icons.payments, label: 'Total cliente', value: '€$total'),
          const SizedBox(height: 12),
          _StatRow(
              icon: Icons.straighten,
              label: 'Distância',
              value: '$distanceKm km'),
          const SizedBox(height: 12),
          _StatRow(
            icon: Icons.savings,
            label: 'Ganhos',
            value: '€$driverEarnings',
            highlight: true,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            color: highlight ? _kBoraGreen : Colors.black54, size: 22),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.black54)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 22 : 18,
            fontWeight: FontWeight.bold,
            color: highlight ? _kBoraGreen : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 64,
            child: OutlinedButton(
              onPressed: busy ? null : onReject,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'REJEITAR',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 64,
            child: ElevatedButton(
              onPressed: busy ? null : onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBoraGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 6,
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'ACEITAR',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
