import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// MULTI-PAPEL (admin, PT-BR) — ver, adicionar e remover papéis de um usuário.
///
/// Lê/escreve via RPCs com guarda de admin no servidor:
/// `admin_list_user_roles` / `admin_add_user_role` / `admin_remove_user_role`.
/// Toda alteração fica registrada em `admin_audit_log`.
///
/// O servidor recusa tirar o ÚLTIMO papel — o usuário nunca fica sem nenhum.
const Map<String, String> kRoleLabelsPtBr = {
  'client': 'Cliente',
  'driver': 'Entregador',
  'partner': 'Parceiro',
  'cleaner': 'Faxineira/o',
  'admin': 'Admin',
};

Future<void> showAdminUserRolesSheet({
  required BuildContext context,
  required String userId,
  required String userLabel,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AdminUserRolesSheet(userId: userId, userLabel: userLabel),
  );
}

class _AdminUserRolesSheet extends StatefulWidget {
  const _AdminUserRolesSheet({required this.userId, required this.userLabel});

  final String userId;
  final String userLabel;

  @override
  State<_AdminUserRolesSheet> createState() => _AdminUserRolesSheetState();
}

class _AdminUserRolesSheetState extends State<_AdminUserRolesSheet> {
  bool _loading = true;
  String? _erro;
  String? _primary;
  List<String> _roles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_user_roles', params: {'p_user_id': widget.userId});
      final map = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _primary = map['primary_role'] as String?;
        _roles = ((map['roles'] as List?) ?? const [])
            .map((e) => (e as Map)['role'] as String)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _mutate(String rpc, String role, String okMsg) async {
    try {
      await Supabase.instance.client.rpc(
        rpc,
        params: {'p_user_id': widget.userId, 'p_role': role},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(okMsg), backgroundColor: AppColors.success),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final disponiveis = kRoleLabelsPtBr.keys
        .where((r) => !_roles.contains(r))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Papéis de ${widget.userLabel}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.sm),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(Spacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Text('Erro: $_erro',
                  style: const TextStyle(color: AppColors.error))
            else ...[
              Text(
                'Papel principal (users.role): ${kRoleLabelsPtBr[_primary] ?? _primary ?? '—'}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  for (final r in _roles)
                    Chip(
                      label: Text(kRoleLabelsPtBr[r] ?? r),
                      onDeleted: _roles.length <= 1
                          ? null
                          : () => _mutate('admin_remove_user_role', r,
                              'Papel removido.'),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    ),
                ],
              ),
              if (_roles.length <= 1)
                const Padding(
                  padding: EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    'Não dá para tirar o último papel do usuário.',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ),
              if (disponiveis.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                const Text('Adicionar papel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final r in disponiveis)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(kRoleLabelsPtBr[r] ?? r),
                        onPressed: () => _mutate(
                            'admin_add_user_role', r, 'Papel adicionado.'),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: Spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
