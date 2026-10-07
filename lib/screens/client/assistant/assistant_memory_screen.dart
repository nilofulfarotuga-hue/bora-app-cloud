// BORA ASSISTENTE (07/10/2026) — "A minha memória": o que o assistente
// guardou sobre o cliente (o de sempre, marcas, restrições…) e a poupança
// acumulada. O cliente apaga linha a linha ou tudo (RLS: só o dono).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../widgets/bora/bora_empty_placeholder.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

class AssistantMemoryScreen extends StatefulWidget {
  const AssistantMemoryScreen({super.key});

  @override
  State<AssistantMemoryScreen> createState() => _AssistantMemoryScreenState();
}

class _AssistantMemoryScreenState extends State<AssistantMemoryScreen> {
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _memoria = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final s = await AssistantService.stats();
      final m = await AssistantService.memoria();
      if (!mounted) return;
      setState(() {
        _stats = s;
        _memoria = m;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar. Tenta outra vez.'.tr;
        _carregando = false;
      });
    }
  }

  static String rotuloKind(String kind) {
    switch (kind) {
      case 'o_de_sempre':
        return 'O de sempre'.tr;
      case 'marca_preferida':
        return 'Marca preferida'.tr;
      case 'nunca_substituir':
        return 'Nunca substituir'.tr;
      case 'substituir_por':
        return 'Substituir por'.tr;
      case 'restricao_alimentar':
        return 'Restrição alimentar'.tr;
      case 'orcamento_habitual':
        return 'Orçamento habitual'.tr;
      case 'nota':
        return 'Nota'.tr;
    }
    return kind;
  }

  static String valorLegivel(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    if (v is List) return v.map(valorLegivel).where((s) => s.isNotEmpty).join(', ');
    if (v is Map) {
      return v.entries
          .map((e) => '${e.key}: ${valorLegivel(e.value)}')
          .join(' · ');
    }
    return v.toString();
  }

  Future<void> _apagar(Map<String, dynamic> linha) async {
    final id = linha['id']?.toString();
    if (id == null) return;
    try {
      await AssistantService.apagarMemoria(id);
      if (!mounted) return;
      setState(() => _memoria = _memoria.where((m) => m['id'] != id).toList());
    } catch (e) {
      if (mounted) _snack('Não consegui apagar. Tenta outra vez.'.tr);
    }
  }

  Future<void> _apagarTudo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar tudo?'.tr),
        content: Text(
            'O assistente esquece o que sabe sobre ti. Os teus pedidos ficam.'
                .tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text('Apagar tudo'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AssistantService.apagarMemoriaToda();
      if (!mounted) return;
      setState(() => _memoria = const []);
    } catch (e) {
      if (mounted) _snack('Não consegui apagar. Tenta outra vez.'.tr);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final mostrados = ((s?['savings_shown_cents'] as num?) ?? 0) / 100;
    final reais = ((s?['savings_realized_cents'] as num?) ?? 0) / 100;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Bora Assistente'.tr,
        actions: [
          if (_memoria.isNotEmpty)
            IconButton(
              tooltip: 'Apagar tudo'.tr,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _apagarTudo,
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_erro!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _carregar,
                          child: Text('Tentar outra vez'.tr)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryWash,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primaryLight),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.savings_outlined,
                                size: 32, color: AppColors.primaryDark),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Já poupaste {0}'.trArgs(
                                        ['€${reais.toStringAsFixed(2)}']),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    'Poupança proposta: {0} · pedidos pelo assistente: {1}'
                                        .trArgs([
                                      '€${mostrados.toStringAsFixed(2)}',
                                      (s?['orders_count'] as num?)?.toInt() ?? 0,
                                    ]),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'A minha memória'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'O que o assistente aprendeu contigo. Podes apagar o que quiseres.'
                            .tr,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      if (_memoria.isEmpty)
                        BoraEmptyPlaceholder(
                          icon: Icons.psychology_outlined,
                          title: 'Ainda não guardei nada'.tr,
                          message:
                              'Quando pedires "o de sempre" ou uma marca, fica aqui.'
                                  .tr,
                        )
                      else
                        for (final m in _memoria)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                [
                                  rotuloKind(m['kind']?.toString() ?? ''),
                                  if ((m['key']?.toString() ?? '').isNotEmpty)
                                    m['key'].toString(),
                                ].join(' · '),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(valorLegivel(m['value'])),
                              trailing: IconButton(
                                tooltip: 'Apagar'.tr,
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.error),
                                onPressed: () => _apagar(m),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}
