// BORA ASSISTENTE (07/10/2026) — "A minha memória": o que o assistente
// guardou sobre o cliente (o de sempre, marcas, restrições…) e a poupança
// acumulada. O cliente apaga linha a linha ou tudo (RLS: só o dono).
//
// AMIGO BORA (08/11/2026, missão m4): passa a ser "O que o Amigo Bora sabe de
// mim" — junta o resumo do perfil (hábitos, lojas favoritas, o que repete,
// restrições), o interruptor "Deixar o Amigo lembrar-se de mim" e "Esquecer
// tudo" (RGPD: apaga as preferências e o resumo; o Amigo só volta a aprender
// com o que acontecer depois). Nunca mostra valores.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../widgets/bora/bora_empty_placeholder.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../utils/euros.dart';

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
  Map<String, dynamic>? _perfil;
  bool _lembrar = true;

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
      final p = await AssistantService.perfilAmigo();
      if (!mounted) return;
      setState(() {
        _stats = s;
        _memoria = m;
        final perfil = p?['perfil'];
        _perfil = perfil is Map ? Map<String, dynamic>.from(perfil) : null;
        _lembrar = p?['lembrar'] != false;
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
        title: Text('Esquecer tudo?'.tr),
        content: Text(
            'O Amigo Bora esquece o que sabe sobre ti e só volta a aprender com o que fizeres daqui para a frente. Os teus pedidos ficam.'
                .tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text('Esquecer tudo'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AssistantService.esquecerTudo();
      if (!mounted) return;
      setState(() {
        _memoria = const [];
        _perfil = null;
      });
      _snack('Pronto: esqueci tudo.'.tr);
    } catch (e) {
      if (mounted) _snack('Não consegui apagar. Tenta outra vez.'.tr);
    }
  }

  Future<void> _mudarLembrar(bool v) async {
    setState(() => _lembrar = v);
    final ok = await AssistantService.lembrar(v);
    if (!ok && mounted) {
      setState(() => _lembrar = !v);
      _snack('Não consegui mudar agora. Tenta outra vez.'.tr);
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
        title: 'O que o Amigo Bora sabe de mim'.tr,
        actions: [
          if (_memoria.isNotEmpty || (_perfil?.isNotEmpty ?? false))
            IconButton(
              tooltip: 'Esquecer tudo'.tr,
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
                                        [eur(reais)]),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    'Poupança proposta: {0} · pedidos pelo assistente: {1}'
                                        .trArgs([
                                      eur(mostrados),
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
                      // Amigo Bora: o resumo em frases (sem valores).
                      Text(
                        'O que sei de ti'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...() {
                        final frases = frasesDoPerfilAmigo(_perfil);
                        if (frases.isEmpty) {
                          return [
                            Text(
                              'Ainda não sei nada de ti. Vou aprendendo com os teus pedidos e com o que me disseres.'
                                  .tr,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ];
                        }
                        return [
                          for (final f in frases)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(Icons.check_circle_outline,
                                        size: 16, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(f,
                                          style:
                                              const TextStyle(fontSize: 14))),
                                ],
                              ),
                            ),
                        ];
                      }(),
                      SwitchListTile(
                        key: const Key('amigo-lembrar'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('Deixar o Amigo lembrar-se de mim'.tr),
                        subtitle: Text(
                            'Desligado, o Amigo não usa nem guarda o que sabe de ti.'
                                .tr),
                        value: _lembrar,
                        onChanged: _mudarLembrar,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('amigo-esquecer-tudo'),
                          onPressed: _apagarTudo,
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.error),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text('Esquecer tudo'.tr),
                        ),
                      ),
                      const SizedBox(height: 12),
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
