// Adendo3 (2026-08-16) — AVISO DE ATUALIZAÇÃO DO APP (padrão Glovo/Uber).
//
// O app publica direto para produção; quem fica em versão velha congela sem
// saber que há update. Este gate compara o versionCode INSTALADO (injetado
// pelo CI via --dart-define=BORA_VERSION_CODE; build local = 0 ⇒ silêncio)
// com as settings criadas pela Claude.ai (category app_update):
//   app_latest_version_code        — 0 = desligado
//   app_min_supported_version_code — 0 = sem bloqueio
//   app_update_notes_pt            — frase curta editável
//
// Regras: atrasado → diálogo simpático dispensável ("Agora não" = volta no
// próximo arranque); abaixo do mínimo → ecrã de bloqueio suave (só atualizar);
// última versão → nunca incomoda; erro de rede → silêncio absoluto.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  AppUpdateService._();

  /// versionCode do build instalado — o CI injeta; local fica 0 (dev).
  static const int installedVersionCode =
      int.fromEnvironment('BORA_VERSION_CODE');

  /// Só um aviso dispensável por sessão (volta no próximo arranque).
  static bool _softPromptShown = false;
  static bool _checking = false;

  static Future<int?> _settingInt(String key) async {
    final v = await Supabase.instance.client
        .rpc('get_setting', params: {'p_key': key});
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.replaceAll('"', ''));
  }

  static Future<String?> _settingText(String key) async {
    final v = await Supabase.instance.client
        .rpc('get_setting', params: {'p_key': key});
    if (v == null) return null;
    final s = '$v'.replaceAll('"', '').trim();
    return s.isEmpty ? null : s;
  }

  static Future<void> _openStore() async {
    const market = 'market://details?id=pt.boraapp.bora';
    const web = 'https://play.google.com/store/apps/details?id=pt.boraapp.bora';
    try {
      final ok = await launchUrl(Uri.parse(market),
          mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {/* cai para o fallback web */}
    try {
      await launchUrl(Uri.parse(web), mode: LaunchMode.externalApplication);
    } catch (_) {/* silêncio */}
  }

  /// Verifica e mostra o aviso/bloqueio quando aplicável. Silêncio total em
  /// qualquer falha — NUNCA bloquear por erro de rede.
  static Future<void> checkAndPrompt(BuildContext context) async {
    if (installedVersionCode <= 0) return; // build local/dev
    if (_checking) return;
    _checking = true;
    try {
      final latest = await _settingInt('app_latest_version_code') ?? 0;
      if (latest <= 0 || installedVersionCode >= latest) return;
      final minSupported =
          await _settingInt('app_min_supported_version_code') ?? 0;
      final notes = await _settingText('app_update_notes_pt') ??
          'Correções e melhorias para uma app mais rápida e estável.';
      if (!context.mounted) return;

      if (minSupported > 0 && installedVersionCode < minSupported) {
        // Bloqueio suave: só dá para atualizar.
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Atualização necessária'),
              content: Text(
                  'Esta versão da app já não é suportada.\n\n$notes'),
              actions: [
                FilledButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.system_update),
                  label: const Text('Atualizar agora'),
                ),
              ],
            ),
          ),
        );
        return;
      }

      if (_softPromptShown) return;
      _softPromptShown = true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nova versão disponível 🎉'),
          content: Text(notes),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Agora não'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openStore();
              },
              icon: const Icon(Icons.system_update),
              label: const Text('Atualizar'),
            ),
          ],
        ),
      );
    } catch (_) {
      // silêncio: falha de rede/settings nunca incomoda nem bloqueia
    } finally {
      _checking = false;
    }
  }
}

/// Gate global: corre o check no arranque e ao voltar ao foreground.
/// Envolve a árvore inteira (os 3 papéis + admin embutido).
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppUpdateService.checkAndPrompt(context));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(AppUpdateService.checkAndPrompt(context));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
