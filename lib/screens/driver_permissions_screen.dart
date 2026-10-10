import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // [10/10/2026] Toque das ofertas (volume do alarme, canal, "Não
  // incomodar"). null = não é Android ou a leitura falhou — não se mostra.
  EstadoDoToque? _toque;
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
    final toque = await PermissionGateService.estadoDoToque();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _toque = toque;
    });
  }

  bool _aTestar = false;

  /// [10/10/2026] Pede ao servidor (Edge `testar-toque`) um aviso igual ao de
  /// uma oferta para os aparelhos desta conta. Prova o toque de ponta a ponta:
  /// push só de dados → app → canal v4 do alarme.
  Future<void> _testarToque() async {
    setState(() => _aTestar = true);
    String msg;
    try {
      final res = await Supabase.instance.client.functions.invoke('testar-toque');
      final d = res.data;
      final enviados = d is Map ? (d['enviados'] ?? 0) : 0;
      msg = (enviados is num && enviados > 0)
          ? 'Enviado. Deve tocar daqui a uns segundos, durante 30 segundos — '
              'experimenta com o telemóvel em Vibrar e o ecrã apagado.'
          : 'Não encontrámos nenhum aparelho registado nesta conta.';
    } catch (e) {
      debugPrint('[BORA-TOQUE] testar-toque falhou: $e');
      msg = 'Não foi possível enviar o teste. Tenta outra vez.';
    }
    if (!mounted) return;
    setState(() => _aTestar = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    final toque = _toque;
    // "Tudo pronto" só se a oferta também tocar (o "Não incomodar" é aviso,
    // não conta).
    final tudoOk =
        snap != null && snap.allOk && toque?.temProblemaGrave != true;
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
                            tudoOk
                                ? Icons.verified_outlined
                                : Icons.warning_amber_rounded,
                            color: tudoOk
                                ? AppColors.success
                                : AppColors.error,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tudoOk
                                  ? 'Tudo pronto — vais receber a chamada '
                                      'de pedido mesmo com o ecrã bloqueado.'
                                  : 'Falta pelo menos uma coisa. Sem '
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
                  // [10/10/2026] As ofertas só vibraram a 09/10 e 10/10
                  // (Samsung A36 em Vibrar). Agora tocam pelo volume do
                  // ALARME — estas três linhas dizem o que as pode calar.
                  if (toque != null) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        'As ofertas tocam como um alarme, mesmo com o '
                        'telemóvel em Vibrar.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _PermissionTile(
                      title: 'Volume do alarme',
                      subtitle: toque.volumeAlarme == null
                          ? 'Tem de estar acima de zero.'
                          : 'Tem de estar acima de zero. Agora: '
                              '${toque.volumeAlarme} de '
                              '${toque.volumeAlarmeMax ?? '?'}.',
                      granted: toque.volumeAlarme == null
                          ? null
                          : toque.volumeAlarme! > 0,
                      busy: _busy,
                      acao: 'Abrir',
                      onFix: () => _fix(() async {
                        await PermissionGateService.abrirDefinicoesSom();
                      }),
                    ),
                    _PermissionTile(
                      title: 'Canal das ofertas',
                      subtitle: 'Tem de estar com som e importância alta '
                          '(aparece no ecrã).',
                      granted: toque.canalOk,
                      busy: _busy,
                      acao: 'Abrir',
                      onFix: () => _fix(() async {
                        await PermissionGateService.abrirCanalOfertas();
                      }),
                    ),
                    _PermissionTile(
                      title: 'Acesso ao Não incomodar',
                      subtitle: 'Ajuda a oferta a tocar de noite, com o '
                          '"Não incomodar" ligado.',
                      granted: toque.acessoNaoIncomodar,
                      aviso: true,
                      busy: _busy,
                      onFix: () => _fix(() async {
                        await PermissionGateService.abrirAcessoNaoIncomodar();
                      }),
                    ),
                    const SizedBox(height: 8),
                    // [10/10/2026] Um passo só: o servidor manda a este
                    // telemóvel um aviso igual ao de uma oferta (30 s).
                    OutlinedButton.icon(
                      onPressed: _aTestar ? null : _testarToque,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: Text(_aTestar
                          ? 'A enviar…'
                          : 'Testar o toque (30 segundos)'),
                    ),
                  ],
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
    this.acao = 'Activar',
    this.aviso = false,
  });

  final String title;
  final String subtitle;

  /// true = concedida · false = em falta · null = indeterminado.
  final bool? granted;
  final bool busy;
  final VoidCallback onFix;

  /// Texto do botão de correcção.
  final String acao;

  /// Em falta é só aviso (laranja), não erro (vermelho).
  final bool aviso;

  @override
  Widget build(BuildContext context) {
    final ok = granted == true;
    final corFalta = aviso ? AppColors.accent : AppColors.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          ok
              ? Icons.check_circle
              : granted == false
                  ? (aviso ? Icons.error_outline : Icons.cancel)
                  : Icons.help_outline,
          color: ok
              ? AppColors.success
              : granted == false
                  ? corFalta
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
                child: Text(acao),
              ),
      ),
    );
  }
}
