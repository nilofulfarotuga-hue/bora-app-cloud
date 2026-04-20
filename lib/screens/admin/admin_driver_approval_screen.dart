import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminDriverApprovalScreen extends StatefulWidget {
  const AdminDriverApprovalScreen({super.key});

  @override
  State<AdminDriverApprovalScreen> createState() =>
      _AdminDriverApprovalScreenState();
}

class _AdminDriverApprovalScreenState extends State<AdminDriverApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loading = true;

  static const _columns =
      'id, name, phone, email, vehicle_type, photo_url, document_type, '
      'document_number, document_photo_url, vehicle_photo_url, iban, '
      'approval_status, rejection_reason, created_at';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final all = await supabase
          .from('drivers')
          .select(_columns)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(all);
      if (mounted) {
        setState(() {
          _pending =
              list.where((d) => d['approval_status'] == 'pending').toList();
          _approved =
              list.where((d) => d['approval_status'] == 'approved').toList();
          _rejected =
              list.where((d) => d['approval_status'] == 'rejected').toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _approve(String driverId) async {
    // Validate required fields before approval
    final driver = _pending.firstWhere(
      (d) => d['id'] == driverId,
      orElse: () => <String, dynamic>{},
    );
    final missing = <String>[];
    if (driver['photo_url'] == null ||
        (driver['photo_url'] as String).isEmpty) {
      missing.add('Foto pessoal');
    }
    if (driver['document_photo_url'] == null ||
        (driver['document_photo_url'] as String).isEmpty) {
      missing.add('Foto do documento');
    }
    if (driver['document_number'] == null ||
        (driver['document_number'] as String).isEmpty) {
      missing.add('Número do documento');
    }
    final vehicleType = driver['vehicle_type'] as String? ?? '';
    if (vehicleType != 'bicycle' &&
        (driver['vehicle_photo_url'] == null ||
            (driver['vehicle_photo_url'] as String).isEmpty)) {
      missing.add('Foto do veículo');
    }
    if (missing.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Falta: ${missing.join(', ')}'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    try {
      await Supabase.instance.client.from('drivers').update({
        'approval_status': 'approved',
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'approved_by': Supabase.instance.client.auth.currentUser?.id,
      }).eq('id', driverId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao aprovar: $e')));
      }
    }
  }

  Future<void> _reject(String driverId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar candidatura'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Motivo de rejeição',
            hintText: 'Ex: Documento ilegível',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('drivers').update({
        'approval_status': 'rejected',
        'rejection_reason': reasonController.text.trim(),
      }).eq('id', driverId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao rejeitar: $e')));
      }
    }
  }

  void _showDetail(Map<String, dynamic> driver) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => _DriverDetailSheet(
            driver: driver, scrollController: scrollController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprovações de Estafetas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Pendentes (${_pending.length})'),
            Tab(text: 'Aprovados (${_approved.length})'),
            Tab(text: 'Rejeitados (${_rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _DriverList(
                  drivers: _pending,
                  emptyMessage: 'Nenhuma candidatura pendente.',
                  onTap: _showDetail,
                  actions: (d) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle,
                            color: AppColors.primary),
                        tooltip: 'Aprovar',
                        onPressed: () => _approve(d['id'] as String),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        tooltip: 'Rejeitar',
                        onPressed: () => _reject(d['id'] as String),
                      ),
                    ],
                  ),
                ),
                _DriverList(
                  drivers: _approved,
                  emptyMessage: 'Nenhum estafeta aprovado.',
                  onTap: _showDetail,
                ),
                _DriverList(
                  drivers: _rejected,
                  emptyMessage: 'Nenhuma candidatura rejeitada.',
                  onTap: _showDetail,
                ),
              ],
            ),
    );
  }
}

// ── Driver list ───────────────────────────────────────────────────────────────

class _DriverList extends StatelessWidget {
  const _DriverList({
    required this.drivers,
    required this.emptyMessage,
    required this.onTap,
    this.actions,
  });

  final List<Map<String, dynamic>> drivers;
  final String emptyMessage;
  final void Function(Map<String, dynamic>) onTap;
  final Widget Function(Map<String, dynamic>)? actions;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = drivers[i];
        final photoUrl = d['photo_url'] as String?;
        final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(d),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person,
                            color: AppColors.textSecondary)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['name'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          d['phone'] as String? ?? '—',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                        if (createdAt != null)
                          Text(
                            '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  if (actions != null) actions!(d),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Driver detail bottom sheet ────────────────────────────────────────────────

class _DriverDetailSheet extends StatelessWidget {
  const _DriverDetailSheet(
      {required this.driver, required this.scrollController});

  final Map<String, dynamic> driver;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final photoUrl = driver['photo_url'] as String?;
    final docPhotoUrl = driver['document_photo_url'] as String?;
    final vehiclePhotoUrl = driver['vehicle_photo_url'] as String?;
    final rejectionReason = driver['rejection_reason'] as String?;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: scrollController,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Selfie
          if (photoUrl != null)
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage(photoUrl),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              driver['name'] as String? ?? '—',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              driver['email'] as String? ?? '—',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Center(
            child: Text(
              driver['phone'] as String? ?? '—',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // Documento
          _InfoRow(
              label: 'Tipo de doc.', value: driver['document_type'] as String?),
          _InfoRow(
              label: 'Nº documento',
              value: driver['document_number'] as String?),
          _InfoRow(label: 'Veículo', value: driver['vehicle_type'] as String?),
          _InfoRow(label: 'IBAN', value: driver['iban'] as String?),
          if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Motivo de rejeição: $rejectionReason',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Foto documento
          if (docPhotoUrl != null) ...[
            const Text('Foto do documento',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, docPhotoUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(docPhotoUrl,
                    height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Foto veículo
          if (vehiclePhotoUrl != null) ...[
            const Text('Foto do veículo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, vehiclePhotoUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(vehiclePhotoUrl,
                    height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showFullscreen(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value!,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
