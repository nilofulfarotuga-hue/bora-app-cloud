import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;

import '../config/app_colors.dart';
import '../services/permission_gate_service.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Sessão 2026-06-11 — Estado visível (✅/❌) das 4 permissões críticas do
/// estafeta, com correcção individual. Razão de existir: no Android 14+ a
/// Play Store revoga USE_FULL_SCREEN_INTENT na instalação e a chamada de
/// pedido deixa de acordar o ecrã bloqueado — sem nenhum sítio onde o
/// estafeta veja que falta a permissão. Acessível via Perfil.
///
/// Re-verifica os estados quando a app volta de Settings (observer resumed).
class DriverPermissionsScreen extends StatefulWidget {
  const DriverPermissionsScreen({super.key});

  @override
  State<DriverPermissionsScreen> createState() =>
      _DriverPermissionsScreenState();
}

class _DriverPermissionsScreenState extends State<DriverPermissionsScreen>
    with WidgetsBindingObserver {
  DriverPermissionsSnapshot? _snap;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Regresso das Definições do Android → re-ler estados reais.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final snap = await PermissionGateService.snapshot();
    if (!mounted) return;
    setState(() => _snap = snap);
  }

  Future<void> _fix(Future<void> Function() request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await request();
    } catch (e) {
      debugPrint('[BORA-FSI] permissions screen fix error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Permissões de pedidos'),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            snap.allOk
                                ? Icons.verified_outlined
                                : Icons.warning_amber_rounded,
                            color: snap.allOk
                                ? AppColors.success
                                : AppColors.error,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              snap.allOk
                                  ? 'Tudo pronto — vais receber a chamada '
                                      'de pedido mesmo com o ecrã bloqueado.'
                                  : 'Falta pelo menos uma permissão. Sem '
                                      'todas, podes perder pedidos com o '
                                      'telemóvel bloqueado ou noutra app.',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PermissionTile(
                    title: 'Ecrã inteiro (telemóvel bloqueado)',
                    subtitle:
                        'Acorda o ecrã e mostra a chamada de pedido por cima '
                        'do bloqueio — como a Uber. A Play Store desliga isto '
                        'na instalação (Android 14+).',
                    granted: snap.fullScreenIntent,
                    busy: _busy,
                    onFix: () => _fix(() async {
                      // Abre Settings → acesso especial "Ecrã inteiro";
                      // devolve no regresso (plugin 17.2.4 verificado).
                      final androidImpl = FlutterLocalNotificationsPlugin()
                          .resolvePlatformSpecificImplementation<
                              AndroidFlutterLocalNotificationsPlugin>();
                      await androidImpl?.requestFullScreenIntentPermission();
                    }),
                  ),
                  _PermissionTile(
                    title: 'Notificações',
                    subtitle:
                        'Aviso sonoro de novos pedidos e serviço activo em '
                        'segundo plano.',
                    granted: snap.notifications,
                    busy: _busy,
                    onFix: () => _fix(() async {
                      await FlutterForegroundTask
                          .requestNotificationPermission();
                    }),
                  ),
                  _PermissionTile(
                    title: 'Mostrar sobre outras apps',
                    subtitle:
                        'Card do pedido por cima da app que estiveres a usar.',
                    granted: snap.overlay,
                    busy: _busy,
                    onFix: () => _fix(() async {
                      await fow.FlutterOverlayWindow.requestPermission();
                    }),
                  ),
                  _PermissionTile(
                    title: 'Bateria sem optimização',
                    subtitle:
                        'Impede o Android de matar a Bora em segundo plano '
                        'durante turnos longos.',
                    granted: snap.battery,
                    busy: _busy,
                    onFix: () => _fix(() async {
                      await FlutterForegroundTask
                          .requestIgnoreBatteryOptimization();
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Depois de activares uma permissão nas Definições, volta '
                    'à Bora — o estado actualiza automaticamente.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.busy,
    required this.onFix,
  });

  final String title;
  final String subtitle;

  /// true = concedida · false = em falta · null = indeterminado.
  final bool? granted;
  final bool busy;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final ok = granted == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          ok
              ? Icons.check_circle
              : granted == false
                  ? Icons.cancel
                  : Icons.help_outline,
          color: ok
              ? AppColors.success
              : granted == false
                  ? AppColors.error
                  : AppColors.textSecondary,
          size: 28,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: const TextStyle(fontSize: 12)),
        ),
        trailing: ok
            ? null
            : TextButton(
                onPressed: busy ? null : onFix,
                child: const Text('Activar'),
              ),
      ),
    );
  }
}
