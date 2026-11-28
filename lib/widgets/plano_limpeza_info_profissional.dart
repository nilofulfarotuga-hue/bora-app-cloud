import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/cleaning_models.dart';
import '../models/cleaning_plan_models.dart';

/// Para a PROFISSIONAL, numa visita de plano (missão limpeza-planos-empresas-2026-11-28, Bloco D):
/// tipo de espaço, área, tarefas e — só no dia, e só para quem aceitou — como entrar
/// (chave/código). Lê tudo do servidor (cleaning_plan_visit_info), que esconde o acesso fora do dia.
class PlanoLimpezaInfoProfissional extends StatefulWidget {
  const PlanoLimpezaInfoProfissional({super.key, required this.booking});
  final CleaningBooking booking;

  @override
  State<PlanoLimpezaInfoProfissional> createState() => _PlanoLimpezaInfoProfissionalState();
}

class _PlanoLimpezaInfoProfissionalState extends State<PlanoLimpezaInfoProfissional> {
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    if (widget.booking.isPlanVisit) _ler();
  }

  Future<void> _ler() async {
    try {
      final res = await Supabase.instance.client
          .rpc('cleaning_plan_visit_info', params: {'p_booking_id': widget.booking.id})
          .timeout(const Duration(seconds: 12));
      if (mounted && res is Map) setState(() => _info = Map<String, dynamic>.from(res));
    } catch (e) {
      debugPrint('PlanoLimpezaInfoProfissional: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    if (!widget.booking.isPlanVisit || i == null) return const SizedBox.shrink();
    final empresa = i['segment'] == 'empresa';
    final tarefas = [
      for (final t in (i['tasks'] as List? ?? const [])) CleaningPlanLabels.tarefas['$t'] ?? '$t',
    ];
    final acesso = i['access_instructions'] as String?;
    return Container(
      key: const Key('plano-info-profissional'),
      margin: const EdgeInsets.only(top: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          empresa
              ? '${'Bora Empresas'.tr}: ${i['company_name'] ?? ''} · ${CleaningPlanLabels.espacos['${i['space_type']}'] ?? ''}'
                  '${i['area_m2'] != null ? ' · ${i['area_m2']} m²' : ''}'
              : 'Cliente de plano (limpeza fixa)'.tr,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (tarefas.isNotEmpty) Text('${'Tarefas'.tr}: ${tarefas.join(', ')}'),
        if (empresa) Text('Leva os produtos (estão incluídos).'.tr),
        if (acesso != null && acesso.isNotEmpty)
          Text('${'Como entrar'.tr}: $acesso', style: const TextStyle(fontWeight: FontWeight.w600))
        else if (i['access_available_on_the_day'] == true)
          Text('Como entrar: aparece aqui no dia da limpeza.'.tr,
              style: const TextStyle(color: AppColors.textSecondary)),
      ]),
    );
  }
}
