import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../widgets/private_bucket_image.dart';

/// Item 80 (paridade-admin-360): revisão de documentos TVDE (IMT / DL 45/2018).
/// Lista documentos por estado, mostra preview assinado (bucket privado
/// driver-documents) e aprova/rejeita via admin_review_tvde_document.
class AdminTvdeDocsReviewScreen extends StatefulWidget {
  const AdminTvdeDocsReviewScreen({super.key});
  @override
  State<AdminTvdeDocsReviewScreen> createState() =>
      _AdminTvdeDocsReviewScreenState();
}

class _AdminTvdeDocsReviewScreenState extends State<AdminTvdeDocsReviewScreen> {
  String _status = 'pending';
  List<_TvdeDoc> _docs = const [];
  bool _loading = true;
  String? _error;

  static const _docTypeLabels = <String, String>{
    'carta_conducao': 'Carta de condução',
    'certificado_tvde_imt': 'Certificado TVDE (IMT)',
    'dut': 'Documento do veículo (DUT)',
    'seguro': 'Seguro',
    'inspecao': 'Inspeção periódica',
    'registo_criminal': 'Registo criminal',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_tvde_documents', params: {
        'p_status': _status == 'todos' ? null : _status,
        'p_limit': 200,
      });
      final list = (res as List)
          .map((e) => _TvdeDoc.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() => _docs = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(_TvdeDoc doc, String decision) async {
    String? note;
    if (decision == 'rejected') {
      note = await _askNote();
      if (note == null || note.trim().length < 5) return; // cancelado
    }
    try {
      await Supabase.instance.client.rpc('admin_review_tvde_document', params: {
        'p_doc_id': doc.id,
        'p_decision': decision,
        'p_note': note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approved'
            ? 'Documento aprovado.'
            : 'Documento rejeitado.'),
        backgroundColor:
            decision == 'approved' ? AppColors.primary : AppColors.error,
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<String?> _askNote() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo da rejeição'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Explica o que está errado (mín. 5 caracteres)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Documentos TVDE'),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                for (final s in const [
                  ('pending', 'Pendentes'),
                  ('approved', 'Aprovados'),
                  ('rejected', 'Rejeitados'),
                  ('todos', 'Todos'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.$2),
                      selected: _status == s.$1,
                      onSelected: (_) {
                        setState(() => _status = s.$1);
                        _load();
                      },
                    ),
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
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _docs.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 60),
                                Center(
                                    child: Text(
                                        'Sem documentos neste estado.\n'
                                        'Nota: o upload de docs na app do motorista '
                                        'é o próximo passo desta vertical.',
                                        textAlign: TextAlign.center)),
                              ])
                            : ListView.builder(
                                itemCount: _docs.length,
                                itemBuilder: (_, i) => _card(_docs[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(_TvdeDoc d) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _docTypeLabels[d.docType] ?? d.docType,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                _statusChip(d.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('${d.driverName} · ${d.driverPhone}',
                style: const TextStyle(color: AppColors.textSecondary)),
            Text('Enviado: ${_fmt(d.uploadedAt)}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PrivateBucketImage(
                urlOrPath: d.filePath,
                height: 220,
                width: double.infinity,
              ),
            ),
            if (d.reviewNote != null && d.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Nota: ${d.reviewNote}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            if (d.status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: AppColors.error),
                      label: const Text('Rejeitar',
                          style: TextStyle(color: AppColors.error)),
                      onPressed: () => _review(d, 'rejected'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprovar'),
                      onPressed: () => _review(d, 'approved'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String s) {
    final (color, label) = switch (s) {
      'approved' => (AppColors.primary, 'Aprovado'),
      'rejected' => (AppColors.error, 'Rejeitado'),
      _ => (AppColors.accent, 'Pendente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _TvdeDoc {
  final String id;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String docType;
  final String filePath;
  final String status;
  final String? reviewNote;
  final DateTime uploadedAt;

  _TvdeDoc({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.docType,
    required this.filePath,
    required this.status,
    required this.reviewNote,
    required this.uploadedAt,
  });

  factory _TvdeDoc.fromJson(Map<String, dynamic> j) => _TvdeDoc(
        id: j['id'] as String,
        driverId: j['driver_id'] as String,
        driverName: (j['driver_name'] as String?) ?? '—',
        driverPhone: (j['driver_phone'] as String?) ?? '—',
        docType: j['doc_type'] as String,
        filePath: j['file_path'] as String,
        status: j['status'] as String,
        reviewNote: j['review_note'] as String?,
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
      );
}
