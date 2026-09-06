import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Item 100 (paridade-admin-360): GDPR — export de dados (art. 15/20) e
/// anonimização / direito ao esquecimento (art. 17) por utilizador.
/// Export copia JSON para o clipboard; anonimização exige escrever
/// "APAGAR DADOS" + razão (guard na RPC admin_gdpr_anonymize).
class AdminGdprScreen extends StatefulWidget {
  const AdminGdprScreen({super.key});
  @override
  State<AdminGdprScreen> createState() => _AdminGdprScreenState();
}

class _AdminGdprScreenState extends State<AdminGdprScreen> {
  final _searchCtrl = TextEditingController();
  List<_ClientRow> _rows = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_clients', params: {'p_search': q, 'p_limit': 20});
      final list = (res as List)
          .map((e) => _ClientRow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(_ClientRow c) async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_gdpr_export', params: {'p_user_id': c.userId});
      final pretty = const JsonEncoder.withIndent('  ').convert(res);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Dados de ${c.name}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(pretty,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar JSON'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pretty));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('Erro no export: $e', error: true);
    }
  }

  Future<void> _anonymize(_ClientRow c) async {
    final confirmCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Anonimizar utilizador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Isto remove PERMANENTEMENTE os dados pessoais de '
                '${c.name} (${c.email}). Os pedidos ficam (obrigação fiscal) '
                'mas sem moradas nem nome. Não dá para desfazer.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Razão (pedido do titular, nº do ticket…)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Escreve: APAGAR DADOS',
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anonimizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_gdpr_anonymize', params: {
        'p_user_id': c.userId,
        'p_confirm': confirmCtrl.text.trim(),
        'p_reason': reasonCtrl.text.trim(),
      });
      _snack('Utilizador anonimizado. Desativa também a conta Auth '
          'no dashboard Supabase.');
      _search();
    } catch (e) {
      _snack('Erro: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.primary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Privacidade (RGPD)'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Email, nome ou telefone do cliente',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  onPressed: _search,
                  child: const Text('Procurar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.error)))
                    : _rows.isEmpty
                        ? const Center(
                            child: Text(
                                'Procura um cliente para exportar ou\n'
                                'anonimizar os dados dele (RGPD).',
                                textAlign: TextAlign.center))
                        : ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (_, i) {
                              final c = _rows[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                child: ListTile(
                                  title: Text(c.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      '${c.email}\n${c.totalOrders} pedidos'),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Exportar dados (JSON)',
                                        icon: const Icon(Icons.download,
                                            color: AppColors.primary),
                                        onPressed: () => _export(c),
                                      ),
                                      IconButton(
                                        tooltip: 'Anonimizar (esquecimento)',
                                        icon: const Icon(
                                            Icons.person_off_outlined,
                                            color: AppColors.error),
                                        onPressed: () => _anonymize(c),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ClientRow {
  final String userId;
  final String name;
  final String email;
  final int totalOrders;

  _ClientRow({
    required this.userId,
    required this.name,
    required this.email,
    required this.totalOrders,
  });

  factory _ClientRow.fromJson(Map<String, dynamic> j) => _ClientRow(
        userId: j['user_id'] as String,
        name: (j['bora_name'] as String?) ?? '—',
        email: (j['email'] as String?) ?? '—',
        totalOrders: (j['total_orders'] as num?)?.toInt() ?? 0,
      );
}
