// "Repetir todos os meses" (missão farmacias-2026-11-11).
// Só avisa no dia escolhido; nunca faz o pedido nem cobra sozinho.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/prescricao_service.dart';
import '../bora/bora_bottom_action_bar.dart';
import '../bora/bora_primary_button.dart';

class LembreteMensalSheet extends StatefulWidget {
  const LembreteMensalSheet({
    super.key,
    required this.restaurantId,
    required this.farmaciaNome,
    this.prescricaoId,
    this.service,
  });

  final String restaurantId;
  final String farmaciaNome;
  final String? prescricaoId;
  final PrescricaoService? service;

  static Future<void> abrir(BuildContext context,
      {required String restaurantId, required String farmaciaNome, String? prescricaoId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LembreteMensalSheet(
        restaurantId: restaurantId,
        farmaciaNome: farmaciaNome,
        prescricaoId: prescricaoId,
      ),
    );
  }

  @override
  State<LembreteMensalSheet> createState() => _LembreteMensalSheetState();
}

class _LembreteMensalSheetState extends State<LembreteMensalSheet> {
  late final PrescricaoService _svc = widget.service ?? PrescricaoService();
  late int _dia = DateTime.now().day.clamp(1, 28);
  bool _aGravar = false;
  List<Map<String, dynamic>> _ativos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final l = await _svc.meusLembretes();
      if (mounted) setState(() => _ativos = l.where((x) => x['restaurant_id'] == widget.restaurantId).toList());
    } catch (_) {}
  }

  Future<void> _ligar() async {
    if (_aGravar) return;
    setState(() => _aGravar = true);
    try {
      await _svc.lembreteDefinir(restaurantId: widget.restaurantId, prescricaoId: widget.prescricaoId, diaDoMes: _dia);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Combinado: avisamos todos os meses no dia $_dia.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _aGravar = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
      }
    }
  }

  Future<void> _desligar(String id) async {
    try {
      await _svc.lembreteDesligar(id);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, BoraBottomActionBar.folgaInferior(context, base: 16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 16),
        const Text('Repetir todos os meses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'No dia que escolher, avisamos para pedir outra vez na ${widget.farmaciaNome}. '
          'Só avisamos: nunca fazemos o pedido nem cobramos sozinhos.',
          style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Text('Dia do mês: $_dia', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Slider(
          value: _dia.toDouble(),
          min: 1,
          max: 28,
          divisions: 27,
          label: '$_dia',
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _dia = v.round()),
        ),
        const SizedBox(height: 8),
        BoraPrimaryButton(label: 'Ligar o lembrete', icon: Icons.notifications_active_outlined, loading: _aGravar, onPressed: _aGravar ? null : _ligar),
        if (_ativos.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Lembretes ligados', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final l in _ativos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat, color: AppColors.primary),
              title: Text('Todos os meses no dia ${l['dia_do_mes']}'),
              trailing: TextButton(onPressed: () => _desligar(l['id'].toString()), child: const Text('Desligar')),
            ),
        ],
      ]),
    );
  }
}
