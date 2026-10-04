import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/order_photo_upload_service.dart';
import '../utils/hora_lisboa.dart';
import '../utils/io_compat.dart';
import '../utils/safe_image_picker.dart';

/// "Reportar um problema" no pedido (padrão Uber Eats, 04/10/2026).
///
/// Grava pela RPC existente `file_complaint` (categoria `order_issue`, ligada
/// ao pedido). A foto, se houver, vai para o mesmo armazenamento das fotos de
/// encomenda e o endereço fica no texto da queixa. O cliente vê aqui o estado
/// da queixa (a tabela `complaints` só lhe mostra as suas — RLS).
class ReportarProblemaPedido extends StatefulWidget {
  const ReportarProblemaPedido({super.key, required this.order});

  final OrderModel order;

  /// Motivos (texto que o cliente vê e que fica no assunto da queixa).
  static const List<String> motivos = [
    'Faltou um produto',
    'Produto errado',
    'Chegou frio ou danificado',
    'O pedido nunca chegou',
    'Outro problema',
  ];

  /// Estado da queixa em palavras do cliente.
  static String estadoLegivel(String? status) {
    switch (status) {
      case 'in_progress':
        return 'Em análise'.tr;
      case 'resolved':
        return 'Resolvido'.tr;
      case 'dismissed':
        return 'Fechado'.tr;
      case 'open':
      default:
        return 'Recebido — vamos analisar'.tr;
    }
  }

  @override
  State<ReportarProblemaPedido> createState() => _ReportarProblemaPedidoState();
}

class _ReportarProblemaPedidoState extends State<ReportarProblemaPedido> {
  List<Map<String, dynamic>> _queixas = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final rows = await Supabase.instance.client
          .from('complaints')
          .select('id, subject, status, created_at')
          .eq('related_order_id', widget.order.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _queixas = (rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('[ReportarProblema] carregar: $e');
    }
  }

  Future<void> _abrir() async {
    final enviado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FolhaReportar(order: widget.order),
    );
    if (!mounted) return;
    if (enviado == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Recebemos o teu relato. Vamos analisar e responder-te.'.tr),
      ));
      await _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.report_gmailerrorred_outlined,
                    color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Algum problema com o pedido?'.tr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            for (final q in _queixas) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '{0} · {1}\nEstado: {2}'.trArgs([
                    (q['subject'] as String?) ?? '',
                    dataHoraLisboa(q['created_at']),
                    ReportarProblemaPedido.estadoLegivel(
                        q['status'] as String?),
                  ]),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _abrir,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text('Reportar um problema'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolhaReportar extends StatefulWidget {
  const _FolhaReportar({required this.order});
  final OrderModel order;

  @override
  State<_FolhaReportar> createState() => _FolhaReportarState();
}

class _FolhaReportarState extends State<_FolhaReportar> {
  String? _motivo;
  final _detalhes = TextEditingController();
  File? _foto;
  bool _aEnviar = false;
  String? _erro;

  @override
  void dispose() {
    _detalhes.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    final x = await SafeImagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 1200);
    if (x == null || !mounted) return;
    setState(() => _foto = File(x.path));
  }

  Future<void> _enviar() async {
    if (_aEnviar) return; // trava de toque duplo
    final motivo = _motivo;
    if (motivo == null) {
      setState(() => _erro = 'Escolhe o que aconteceu.'.tr);
      return;
    }
    setState(() {
      _aEnviar = true;
      _erro = null;
    });
    try {
      String? urlFoto;
      final foto = _foto;
      if (foto != null) {
        urlFoto = await OrderPhotoUploadService.uploadOrderPhoto(
          photoFile: foto,
          pathPrefix: 'queixa_${widget.order.id}',
        );
      }
      final detalhes = _detalhes.text.trim();
      // O texto da queixa fica em português para quem a lê no painel.
      final corpo = StringBuffer('Motivo: $motivo');
      if (detalhes.isNotEmpty) corpo.write('\nDetalhes: $detalhes');
      if (urlFoto != null) corpo.write('\nFoto: $urlFoto');
      await Supabase.instance.client.rpc('file_complaint', params: {
        'p_role': 'client',
        'p_category': 'order_issue',
        'p_subject': motivo,
        'p_body': corpo.toString(),
        'p_related_order_id': widget.order.id,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[ReportarProblema] enviar: $e');
      if (!mounted) return;
      setState(() {
        _aEnviar = false;
        _erro = 'Não foi possível enviar. Tenta outra vez.'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'O que aconteceu?'.tr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final m in ReportarProblemaPedido.motivos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  _motivo == m
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _motivo == m
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                title: Text(m.tr),
                onTap: _aEnviar ? null : () => setState(() => _motivo = m),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _detalhes,
              enabled: !_aEnviar,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Conta-nos mais (opcional)'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _aEnviar ? null : _escolherFoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(_foto == null
                      ? 'Juntar uma foto (opcional)'.tr
                      : 'Foto escolhida — trocar'.tr),
                ),
                if (_foto != null)
                  IconButton(
                    tooltip: 'Tirar a foto'.tr,
                    onPressed:
                        _aEnviar ? null : () => setState(() => _foto = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            if (_erro != null) ...[
              const SizedBox(height: 4),
              Text(_erro!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _aEnviar ? null : _enviar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _aEnviar
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Enviar'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
