import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// MULTI-PAPEL (admin, PT-BR) — mostra se o candidato já tem o OUTRO papel.
/// Numa candidatura de limpeza, mostra o estado de entregador/motorista;
/// numa candidatura de entregador, mostra o estado de profissional de limpeza.
/// Lê `admin_user_role_flags(user_id)` (guarda de admin no servidor).
enum OtherRole { driver, cleaner }

class AdminOtherRoleBadge extends StatefulWidget {
  const AdminOtherRoleBadge({
    super.key,
    required this.userId,
    required this.show,
  });

  final String? userId;

  /// Qual papel mostrar (o OUTRO, diferente da tela atual).
  final OtherRole show;

  @override
  State<AdminOtherRoleBadge> createState() => _AdminOtherRoleBadgeState();
}

class _AdminOtherRoleBadgeState extends State<AdminOtherRoleBadge> {
  String? _status;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.userId;
    if (uid == null || uid.isEmpty) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .rpc('admin_user_role_flags', params: {'p_user_id': uid});
      final map = (res as Map?)?.cast<String, dynamic>();
      final key = widget.show == OtherRole.driver
          ? 'driver_status'
          : 'cleaner_status';
      if (mounted) {
        setState(() {
          _status = map?[key] as String?;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  static const _statusPt = {
    'approved': 'aprovado',
    'pending': 'em análise',
    'rejected': 'recusado',
    'suspended': 'suspenso',
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _status == null) return const SizedBox.shrink();
    final roleLabel = widget.show == OtherRole.driver
        ? 'Também é entregador/motorista'
        : 'Também é profissional de limpeza';
    final statusPt = _statusPt[_status] ?? _status!;
    final approved = _status == 'approved';
    final color = approved ? AppColors.primary : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(approved ? Icons.verified_user : Icons.badge_outlined,
              size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$roleLabel · $statusPt',
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
