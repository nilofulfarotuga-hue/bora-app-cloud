// Missão cadeia-gratis-2026-08-19 — Painel admin: modelos Gemini dos robôs.
// Lê/escreve support_settings (id=1): gemini_model (suporte) e gemini_model_robot_b (Robot B).
// Motivo: o Robot B corria de hora a hora num modelo *preview*; o Danilo passa a poder
// trocar o modelo sem depender de ninguém.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAiModelsScreen extends StatefulWidget {
  const AdminAiModelsScreen({super.key});

  @override
  State<AdminAiModelsScreen> createState() => _AdminAiModelsScreenState();
}

class _AdminAiModelsScreenState extends State<AdminAiModelsScreen> {
  final _supabase = Supabase.instance.client;

  // Modelos estáveis (GA). Mantidos aqui como atalho — o campo aceita qualquer texto,
  // para não travar o Danilo quando o Google lançar um modelo novo.
  static const _sugestoes = <String>[
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-3-flash-preview',
  ];

  final _suporteCtrl = TextEditingController();
  final _robotBCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _atualizadoEm;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _suporteCtrl.dispose();
    _robotBCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await _supabase
          .from('support_settings')
          .select('gemini_model, gemini_model_robot_b, updated_at')
          .eq('id', 1)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _suporteCtrl.text = (row?['gemini_model'] as String?) ?? '';
        _robotBCtrl.text = (row?['gemini_model_robot_b'] as String?) ?? '';
        _atualizadoEm = row?['updated_at'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  Future<void> _salvar() async {
    final suporte = _suporteCtrl.text.trim();
    final robotB = _robotBCtrl.text.trim();
    if (suporte.isEmpty || robotB.isEmpty) {
      setState(() => _error = 'Os dois campos são obrigatórios.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _supabase.from('support_settings').update({
        'gemini_model': suporte,
        'gemini_model_robot_b': robotB,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 1);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modelos salvos. Vale na próxima execução do robô.'),
          backgroundColor: AppColors.success,
        ),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao salvar: $e';
        _saving = false;
      });
    }
  }

  bool get _temPreview =>
      _suporteCtrl.text.contains('preview') ||
      _robotBCtrl.text.contains('preview');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Modelos de IA'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                const Text(
                  'Qual modelo Gemini cada robô usa. Vale na próxima execução — '
                  'o Robot B roda de hora em hora, no minuto 7.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _campo(
                  rotulo: 'Robot B (roda de hora em hora)',
                  ctrl: _robotBCtrl,
                  dica: 'Ex.: gemini-3.6-flash',
                ),
                const SizedBox(height: 20),
                _campo(
                  rotulo: 'Suporte / chatbot (volume)',
                  ctrl: _suporteCtrl,
                  dica: 'Ex.: gemini-3.5-flash-lite',
                ),
                if (_temPreview) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Atenção: um dos modelos é "preview". Modelos preview podem sair '
                      'do ar sem aviso. Prefira os estáveis.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Salvar'),
                  ),
                ),
                if (_atualizadoEm != null) ...[
                  const SizedBox(height: 16),
                  Text('Última alteração: $_atualizadoEm',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
    );
  }

  Widget _campo({
    required String rotulo,
    required TextEditingController ctrl,
    required String dica,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: dica,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider)),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _sugestoes
              .map((m) => ActionChip(
                    label: Text(m, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      ctrl.text = m;
                      setState(() {});
                    },
                  ))
              .toList(),
        ),
      ],
    );
  }
}
