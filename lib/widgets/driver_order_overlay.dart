// Sessão 2026-05-21 — flutter_overlay_window: card de oferta de novo pedido
// por cima de qualquer outra app (estilo Uber/Glovo).
//
// Como funciona:
//   1. FCM data-only message chega com type=new_order_offer
//   2. _firebaseMessagingBackgroundHandler em notification_service.dart
//      mostra a local notification (som/vibração) E tenta showOverlay()
//   3. O Android arranca um isolate separado e chama overlayMain()
//   4. Este ficheiro define a UI desse isolate
//   5. Main app envia os dados via FlutterOverlayWindow.shareData()
//   6. Quando o estafeta toca em ACEITAR/REJEITAR, o overlay envia o action
//      de volta via shareData e fecha
//
// LIMITAÇÕES (overlay isolate):
//   • Sem acesso a Supabase / Provider / OrderStore — apenas Flutter base
//   • Sem som próprio (a local notification trata disso)
//   • Sem vibração própria (idem)
//
// O som contínuo + vibração são geridos pela notificação local com
// FLAG_INSISTENT + bora_alert RawResource (ver notification_service.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const _kOfferTimeoutSeconds = 40; // matches dispatch_engine TTL backend

const _kBoraGreen = Color(0xFF2E7D32);
const _kBoraGreenDark = Color(0xFF1B5E20);
const _kBoraOrange = Color(0xFFE65100);

/// Entry point invocado pelo plugin flutter_overlay_window quando
/// `FlutterOverlayWindow.showOverlay()` arranca o isolate.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _DriverOrderOverlayApp());
}

class _DriverOrderOverlayApp extends StatelessWidget {
  const _DriverOrderOverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: _DriverOrderOverlay(),
      ),
    );
  }
}

class _DriverOrderOverlay extends StatefulWidget {
  const _DriverOrderOverlay();

  @override
  State<_DriverOrderOverlay> createState() => _DriverOrderOverlayState();
}

class _DriverOrderOverlayState extends State<_DriverOrderOverlay> {
  String? _orderId;
  String _vendorName = 'Novo pedido';
  double _total = 0;
  String _distanceKm = '0';
  double _driverEarnings = 0;

  int _remaining = _kOfferTimeoutSeconds;
  Timer? _timer;
  StreamSubscription<dynamic>? _sub;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen(_onData);
    // NÃO iniciar countdown aqui — aguardar dados via shareData.
    // O overlay arranca em standby (invisível, click-through) quando
    // o driver vai Online; o countdown começa quando chega um orderId.
  }

  void _onData(dynamic data) {
    if (data is! Map) return;
    final newOrderId = data['orderId']?.toString();
    final action = data['action']?.toString();

    // Comando explícito de fecho (driver foi Offline).
    if (action == 'close') {
      _timer?.cancel();
      FlutterOverlayWindow.closeOverlay().ignore();
      return;
    }

    if (newOrderId != null && newOrderId.isNotEmpty) {
      _timer?.cancel();
      setState(() {
        _orderId = newOrderId;
        _vendorName = (data['vendorName']?.toString() ?? _vendorName).isEmpty
            ? _vendorName
            : data['vendorName'].toString();
        _total = double.tryParse(data['total']?.toString() ?? '') ?? _total;
        _distanceKm = data['distanceKm']?.toString() ?? _distanceKm;
        _driverEarnings =
            double.tryParse(data['driverEarnings']?.toString() ?? '') ??
                _driverEarnings;
        _remaining = _kOfferTimeoutSeconds;
        _decided = false;
      });
      // Mudar flag para defaultFlag para capturar toques em Aceitar/Rejeitar.
      FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag).ignore();
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        _decide('expired');
        return;
      }
      setState(() => _remaining--);
    });
  }

  Future<void> _decide(String action) async {
    if (_decided) return;
    _decided = true;
    _timer?.cancel();
    try {
      await FlutterOverlayWindow.shareData({
        'action': action,
        'orderId': _orderId,
      });
    } catch (_) {}
    // Voltar para standby (invisível, click-through) em vez de fechar.
    // Assim o overlay está pronto para a próxima oferta sem showOverlay().
    setState(() {
      _orderId = null;
      _decided = false;
      _remaining = _kOfferTimeoutSeconds;
    });
    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.clickThrough);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Standby: overlay activo mas invisível (click-through configurado pelo
    // initDriverStandbyOverlay). Quando orderId chega via shareData(), o flag
    // muda para defaultFlag e o card é mostrado.
    if (_orderId == null) return const SizedBox.shrink();
    final progress = _remaining / _kOfferTimeoutSeconds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: _kBoraGreenDark, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(remaining: _remaining, progress: progress),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vendorName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _kBoraGreenDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Chip(
                          icon: Icons.euro_rounded,
                          label: '€${_total.toStringAsFixed(2)}',
                          color: _kBoraGreen,
                        ),
                        const SizedBox(width: 8),
                        _Chip(
                          icon: Icons.directions_bike_rounded,
                          label: '${_distanceKm}km',
                          color: _kBoraOrange,
                        ),
                        if (_driverEarnings > 0) ...[
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.payments_rounded,
                            label:
                                'Ganhas €${_driverEarnings.toStringAsFixed(2)}',
                            color: _kBoraGreenDark,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Rejeitar',
                        icon: Icons.close_rounded,
                        color: Colors.red.shade700,
                        onTap: () => _decide('reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _ActionButton(
                        label: 'Aceitar',
                        icon: Icons.check_rounded,
                        color: _kBoraGreen,
                        onTap: () => _decide('accept'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.remaining, required this.progress});
  final int remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBoraGreenDark, _kBoraGreen],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: Colors.white, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Novo pedido!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              '$remaining',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
