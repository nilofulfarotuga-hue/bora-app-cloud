import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

/// Admin · Configurações de Despacho (PT-BR).
///
/// Tela dedicada para editar os 5 parâmetros que controlam o ciclo de
/// dispatch (REGRAS 2, 3, 4, 5). Lê e grava em `platform_settings` via
/// RPCs `admin_list_settings` / `admin_update_setting`.
///
/// IMPORTANTE: alterações propagam-se em tempo real para o backend
/// (dispatch-engine + bora_dispatch_maintenance). Use com critério.
class AdminDispatchSettingsScreen extends StatefulWidget {
  const AdminDispatchSettingsScreen({super.key});

  @override
  State<AdminDispatchSettingsScreen> createState() =>
      _AdminDispatchSettingsScreenState();
}

class _AdminDispatchSettingsScreenState
    extends State<AdminDispatchSettingsScreen> {
  bool _loading = true;
  String? _error;
  final Map<String, num> _values = {};

  /// Definições dos 5 settings com label PT-BR amigável + explicação técnica.
  /// A ordem aqui é a ordem de exibição.
  static const List<_DispatchSettingSpec> _specs = [
    _DispatchSettingSpec(
      key: 'dispatch_offer_timeout_seconds',
      label: 'Timeout da oferta',
      unit: 'segundos',
      description:
          'Quanto tempo o estafeta tem para aceitar/recusar a oferta antes '
          'de o sistema marcar como tentativa expirada e ofertar ao próximo.',
      minValue: 10,
      maxValue: 120,
      defaultValue: 40,
      icon: Icons.timer_outlined,
    ),
    _DispatchSettingSpec(
      key: 'dispatch_retry_no_driver_seconds',
      label: 'Retry sem novo estafeta',
      unit: 'segundos',
      description:
          'Tempo entre tentativas quando não há estafetas disponíveis '
          '(todos rejeitaram ou único estafeta online — REGRAS 2 e 3).',
      minValue: 5,
      maxValue: 60,
      defaultValue: 10,
      icon: Icons.replay_outlined,
    ),
    _DispatchSettingSpec(
      key: 'dispatch_max_total_seconds_with_drivers_online',
      label: 'Limite com estafetas online',
      unit: 'segundos',
      description:
          'Tempo total acumulado com estafetas online antes do modal aparecer '
          'ao parceiro pedindo decisão. Conta APENAS o tempo com drivers '
          'online (REGRA 4). 1200s = 20 minutos.',
      minValue: 300,
      maxValue: 3600,
      defaultValue: 1200,
      icon: Icons.hourglass_top,
    ),
    _DispatchSettingSpec(
      key: 'dispatch_partner_confirm_extension_seconds',
      label: 'Extensão após "Continuar"',
      unit: 'segundos',
      description:
          'Tempo extra que o parceiro adiciona ao escolher "Continuar +10 min" '
          'no modal. 600s = 10 minutos.',
      minValue: 60,
      maxValue: 1800,
      defaultValue: 600,
      icon: Icons.add_circle_outline,
    ),
    _DispatchSettingSpec(
      key: 'dispatch_auto_cancel_safety_seconds',
      label: 'Safety auto-cancel',
      unit: 'segundos',
      description:
          'Tempo absoluto para auto-cancelar pedido mesmo se houver drivers '
          'online (último recurso de segurança). 1800s = 30 minutos. '
          'REGRA 1: nunca cancelar com drivers ainda no sistema antes deste limite.',
      minValue: 600,
      maxValue: 7200,
      defaultValue: 1800,
      icon: Icons.warning_amber_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_settings', params: {'p_category': null});
      final list = (res as List).cast<Map<String, dynamic>>();
      _values.clear();
      for (final row in list) {
        final key = row['key']?.toString();
        if (key == null) continue;
        if (!_specs.any((s) => s.key == key)) continue;
        final v = row['value'];
        final num? parsed = v is num ? v : num.tryParse(v?.toString() ?? '');
        if (parsed != null) _values[key] = parsed;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editSetting(_DispatchSettingSpec spec) async {
    final current = _values[spec.key] ?? spec.defaultValue;
    final ctrl = TextEditingController(text: current.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(spec.icon, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(spec.label)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: false, signed: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Valor (${spec.unit})',
                helperText:
                    'Min: ${spec.minValue} · Max: ${spec.maxValue} · '
                    'Padrão: ${spec.defaultValue}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Esta alteração propaga-se em tempo real para o backend.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final parsed = int.tryParse(ctrl.text.trim());
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valor inválido — insira apenas números inteiros.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (parsed < spec.minValue || parsed > spec.maxValue) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fora do intervalo permitido (${spec.minValue}..${spec.maxValue}).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': spec.key, 'p_value': parsed});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${spec.label}: atualizado para $parsed ${spec.unit}.'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações de Despacho'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const _HeaderBanner(),
                      const SizedBox(height: 16),
                      ..._specs.map((spec) {
                        final current =
                            _values[spec.key] ?? spec.defaultValue;
                        final isDefault = current == spec.defaultValue;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () => _editSetting(spec),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(spec.icon,
                                        color: AppColors.primary, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          spec.label,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          spec.description,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$current',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: isDefault
                                              ? Colors.black87
                                              : AppColors.warning,
                                        ),
                                      ),
                                      Text(
                                        spec.unit,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54),
                                      ),
                                      if (!isDefault) ...[
                                        const SizedBox(height: 2),
                                        const Text(
                                          'custom',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.warning,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class _DispatchSettingSpec {
  final String key;
  final String label;
  final String unit;
  final String description;
  final int minValue;
  final int maxValue;
  final int defaultValue;
  final IconData icon;

  const _DispatchSettingSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.description,
    required this.minValue,
    required this.maxValue,
    required this.defaultValue,
    required this.icon,
  });
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controle do ciclo de despacho',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estes 5 parâmetros regem como o sistema escolhe estafetas, '
                  'quando re-tenta, e quando pede decisão ao parceiro. '
                  'Mudanças aplicam-se em tempo real.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.amber.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
