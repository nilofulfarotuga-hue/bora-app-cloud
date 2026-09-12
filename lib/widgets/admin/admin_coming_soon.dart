import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_audit_service.dart';

/// Painel admin (PT-BR) — controle do estado "Em breve" (`coming_soon`).
///
/// A loja/parceiro continua no catálogo e navegável pelo cliente, mas não
/// aceita pedidos/marcações. O bloqueio real é no servidor
/// (triggers + Edge Functions, erro `STORE_COMING_SOON`).

/// Texto sugerido quando o admin liga o "Em breve" sem escrever nada.
const String kAdminComingSoonDefaultText = 'Em breve';

/// Selo laranja para a listagem do admin.
class AdminComingSoonBadge extends StatelessWidget {
  const AdminComingSoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: Spacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF97316),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: const Text(
        'Em breve',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Abre o diálogo de "Em breve" para uma linha de [table] (`restaurants` ou
/// `service_providers`) e grava a alteração + registro em `admin_audit_log`.
///
/// Devolve `true` quando algo foi gravado (o chamador recarrega a lista).
Future<bool> showAdminComingSoonDialog({
  required BuildContext context,
  required String table,
  required String id,
  required String name,
  required bool currentValue,
  required String? currentText,
}) async {
  var enabled = currentValue;
  final textCtrl = TextEditingController(
    text: (currentText == null || currentText.trim().isEmpty)
        ? kAdminComingSoonDefaultText
        : currentText,
  );

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Em breve'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              title: const Text('Marcar como "Em breve"'),
              subtitle: const Text(
                'A loja continua visível e navegável, mas não aceita '
                'pedidos nem marcações.',
                style: TextStyle(fontSize: 12),
              ),
              onChanged: (v) => setLocal(() => enabled = v),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: textCtrl,
              enabled: enabled,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Texto do banner (visto pelo cliente)',
                hintText: kAdminComingSoonDefaultText,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );

  final newText = textCtrl.text.trim();
  textCtrl.dispose();

  if (confirmed != true) return false;

  final effectiveText =
      newText.isEmpty ? kAdminComingSoonDefaultText : newText;

  try {
    await Supabase.instance.client.from(table).update({
      'coming_soon': enabled,
      'coming_soon_text': enabled ? effectiveText : null,
    }).eq('id', id);

    // Auditoria best-effort — nunca bloqueia a UX. entity_id fica null porque
    // restaurants.id / service_providers.id são TEXT, não UUID; o id textual
    // viaja em details (mesmo padrão de partner_toggle).
    unawaited(AdminAuditService.logAction(
      action: 'coming_soon_toggle',
      entityType: table == 'restaurants' ? 'restaurant' : 'service_provider',
      details: {
        'id': id,
        'name': name,
        'de': {
          'coming_soon': currentValue,
          'coming_soon_text': currentText,
        },
        'para': {
          'coming_soon': enabled,
          'coming_soon_text': enabled ? effectiveText : null,
        },
      },
    ));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(enabled
            ? '$name marcado como "Em breve".'
            : '$name voltou a aceitar pedidos.'),
        backgroundColor: enabled ? AppColors.warning : AppColors.success,
        duration: const Duration(seconds: 2),
      ));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Falha ao salvar "Em breve": $e'),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ));
    }
    return false;
  }
}

/// Barra do filtro rápido "Só em breve" para as listagens do admin.
class AdminComingSoonFilterBar extends StatelessWidget {
  const AdminComingSoonFilterBar({
    super.key,
    required this.onlyComingSoon,
    required this.onChanged,
    required this.total,
  });

  final bool onlyComingSoon;
  final ValueChanged<bool> onChanged;

  /// Quantos itens estão em "Em breve" na lista carregada.
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          FilterChip(
            label: Text('Só em breve ($total)'),
            selected: onlyComingSoon,
            onSelected: onChanged,
            selectedColor: const Color(0xFFF97316).withValues(alpha: 0.20),
            checkmarkColor: const Color(0xFFF97316),
          ),
        ],
      ),
    );
  }
}
