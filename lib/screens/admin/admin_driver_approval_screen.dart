import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/private_bucket_image.dart';
import '_admin_rpc_errors.dart';
import 'admin_driver_detail_screen.dart';

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

  // Bulk select
  final Set<String> _selectedIds = {};
  bool get _isMultiSelectMode => _selectedIds.isNotEmpty;

  static const _columns =
      'id, name, phone, email, vehicle_type, license_plate, photo_url, '
      'document_type, document_number, document_photo_url, vehicle_photo_url, '
      'vehicle_doc_url, registration_selfie_url, nif, '
      'iban, mbway_phone, address, approval_status, rejection_reason, '
      'submitted_at, reviewed_at, created_at';

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

  /// Approve a driver. Calls `admin_approve_driver` RPC (SECURITY DEFINER,
  /// bypasses the drivers_update_own RLS that silently blocked this for
  /// the entire history of the project — see Fase 2 BUG 1 reports).
  ///
  /// Two paths:
  /// - All required docs present → simple confirm dialog → RPC with force=false.
  /// - Some docs missing → "Aprovar mesmo assim" dialog with mandatory
  ///   justification + checkbox → RPC with force=true.
  Future<void> _approve(String driverId) async {
    final driver = _pending.firstWhere(
      (d) => d['id'] == driverId,
      orElse: () => <String, dynamic>{},
    );
    final missing = _missingDocs(driver);

    bool force = false;
    String? justification;

    if (missing.isEmpty) {
      final ok = await _confirmSimple(
        title: 'Aprovar entregador?',
        body: 'Vais aprovar ${driver['name'] ?? 'este estafeta'}.',
        confirmLabel: 'Aprovar',
        confirmColor: AppColors.success,
      );
      if (ok != true) return;
    } else {
      final result = await _confirmForceApprove(
        driver: driver,
        missing: missing,
      );
      if (result == null) return;
      force = true;
      justification = result;
    }

    try {
      final res = await Supabase.instance.client.rpc(
        'admin_approve_driver',
        params: {
          'p_driver_id': driverId,
          'p_force': force,
          'p_justification': justification,
        },
      );
      if (!mounted) return;
      final wasForced =
          res is Map && res['was_forced'] == true; // ignore: avoid_dynamic_calls
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(wasForced
            ? 'Entregador aprovado (override admin).'
            : 'Entregador aprovado.'),
        backgroundColor:
            wasForced ? AppColors.warning : AppColors.success,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  List<String> _missingDocs(Map<String, dynamic> driver) {
    final missing = <String>[];
    // Aceita photo_url OU registration_selfie_url (novo fluxo: foto fica em
    // registration_selfie_url até aprovação; só copia para photo_url ao aprovar).
    final photo = (driver['photo_url'] as String?) ??
        (driver['registration_selfie_url'] as String?);
    if (photo == null || photo.isEmpty) missing.add('Foto pessoal');
    final docPhoto = driver['document_photo_url'] as String?;
    if (docPhoto == null || docPhoto.isEmpty) {
      missing.add('Foto do documento');
    }
    final docNum = driver['document_number'] as String?;
    if (docNum == null || docNum.isEmpty) missing.add('Número do documento');
    final vt = driver['vehicle_type'] as String? ?? '';
    final vPhoto = driver['vehicle_photo_url'] as String?;
    if (vt != 'bicycle' && (vPhoto == null || vPhoto.isEmpty)) {
      missing.add('Foto do veículo');
    }
    if (vt != 'bicycle') {
      final plate = driver['license_plate'] as String?;
      if (plate == null || plate.isEmpty) missing.add('Matrícula');
    }
    final iban = driver['iban'] as String?;
    if (iban == null || iban.isEmpty) missing.add('IBAN');
    return missing;
  }

  Future<bool?> _confirmSimple({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Returns the entered justification on confirm, or null on cancel.
  Future<String?> _confirmForceApprove({
    required Map<String, dynamic> driver,
    required List<String> missing,
  }) async {
    final controller = TextEditingController();
    bool acknowledged = false;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final justOk = controller.text.trim().length >= 3;
          return AlertDialog(
            title: const Text('Faltam documentos'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vais aprovar ${driver['name'] ?? 'este estafeta'} '
                      'mesmo sem:',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...missing.map((m) => Padding(
                          padding: const EdgeInsets.only(
                              left: 8, top: 2, bottom: 2),
                          child: Text(
                            '• $m',
                            style: const TextStyle(color: AppColors.error),
                          ),
                        )),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      onChanged: (_) => setLocal(() {}),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText:
                            'Justificação (obrigatória, mín. 3 caracteres)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: acknowledged,
                      onChanged: (v) =>
                          setLocal(() => acknowledged = v ?? false),
                      title: const Text(
                        'Compreendo o risco e quero aprovar mesmo assim.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning),
                onPressed: (acknowledged && justOk)
                    ? () => Navigator.pop(ctx, controller.text.trim())
                    : null,
                child: const Text('Aprovar mesmo assim'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Reject a driver. Calls `admin_reject_driver` RPC (SECURITY DEFINER,
  /// bypasses RLS). Reason >= 3 chars required server-side AND client-side.
  Future<void> _reject(String driverId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final ok = controller.text.trim().length >= 3;
          return AlertDialog(
            title: const Text('Rejeitar candidatura'),
            content: TextField(
              controller: controller,
              onChanged: (_) => setLocal(() {}),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (mín. 3 caracteres)',
                hintText: 'Ex: Documento ilegível',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: ok
                    ? () => Navigator.pop(ctx, controller.text.trim())
                    : null,
                child: const Text('Rejeitar'),
              ),
            ],
          );
        },
      ),
    );
    if (reason == null) return;

    try {
      await Supabase.instance.client.rpc(
        'admin_reject_driver',
        params: {'p_driver_id': driverId, 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Candidatura rejeitada.'),
        backgroundColor: AppColors.error,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  Future<void> _bulkApprove() async {
    final ids = _selectedIds.toList();
    int approved = 0;
    int skipped = 0;
    for (final id in ids) {
      final driver = _pending.firstWhere(
        (d) => d['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      final missing = _missingDocs(driver);
      if (missing.isNotEmpty) {
        skipped++;
        continue;
      }
      try {
        await Supabase.instance.client.rpc(
          'admin_approve_driver',
          params: {
            'p_driver_id': id,
            'p_force': false,
            'p_justification': 'bulk_approval',
          },
        );
        approved++;
      } catch (_) {
        skipped++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$approved aprovados, $skipped ignorados (docs incompletos)'),
      backgroundColor: AppColors.success,
    ));
    await _load();
    setState(() => _selectedIds.clear());
  }

  Future<void> _bulkReject() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final ok = controller.text.trim().length >= 3;
          return AlertDialog(
            title: Text('Rejeitar ${_selectedIds.length} candidatos'),
            content: TextField(
              controller: controller,
              onChanged: (_) => setLocal(() {}),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (mín. 3 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: ok ? () => Navigator.pop(ctx, controller.text.trim()) : null,
                child: const Text('Rejeitar todos'),
              ),
            ],
          );
        },
      ),
    );
    if (reason == null) return;
    final ids = _selectedIds.toList();
    int rejected = 0;
    for (final id in ids) {
      try {
        await Supabase.instance.client.rpc(
          'admin_reject_driver',
          params: {'p_driver_id': id, 'p_reason': reason},
        );
        rejected++;
      } catch (e, st) {
        debugPrint('[admin_driver_approval] reject driver $id failed: $e\n$st');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$rejected rejeitados'),
      backgroundColor: AppColors.error,
    ));
    await _load();
    setState(() => _selectedIds.clear());
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        title: _isMultiSelectMode
            ? Text('${_selectedIds.length} seleccionados')
            : const Text('Aprovações de Entregadores'),
        actions: _isMultiSelectMode
            ? [
                TextButton(
                  onPressed: _bulkApprove,
                  child: const Text('Aprovar todos',
                      style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: _bulkReject,
                  child: const Text('Rejeitar todos',
                      style: TextStyle(color: Colors.white70)),
                ),
              ]
            : [
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
      floatingActionButton: _isMultiSelectMode
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.success,
              onPressed: _bulkApprove,
              icon: const Icon(Icons.check_circle),
              label: Text('Aprovar (${_selectedIds.length})'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _DriverList(
                  drivers: _pending,
                  emptyMessage: 'Nenhuma candidatura pendente.',
                  onTap: (d) {
                    if (_isMultiSelectMode) {
                      final id = d['id'] as String;
                      setState(() {
                        if (_selectedIds.contains(id)) {
                          _selectedIds.remove(id);
                        } else {
                          _selectedIds.add(id);
                        }
                      });
                    } else {
                      _showDetail(d);
                    }
                  },
                  onLongPress: (d) {
                    final id = d['id'] as String;
                    setState(() => _selectedIds.add(id));
                  },
                  selectedIds: _selectedIds,
                  actions: (d) {
                    if (_isMultiSelectMode) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: AppColors.success),
                          tooltip: 'Aprovar',
                          onPressed: () => _approve(d['id'] as String),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: AppColors.error),
                          tooltip: 'Rejeitar',
                          onPressed: () => _reject(d['id'] as String),
                        ),
                      ],
                    );
                  },
                ),
                _DriverList(
                  drivers: _approved,
                  emptyMessage: 'Nenhum entregador aprovado.',
                  onTap: (d) {
                    final id = d['id'] as String?;
                    if (id == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminDriverDetailScreen(driverId: id),
                      ),
                    );
                  },
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
    this.onLongPress,
    this.selectedIds,
    this.actions,
  });

  final List<Map<String, dynamic>> drivers;
  final String emptyMessage;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onLongPress;
  final Set<String>? selectedIds;
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
        final id = d['id'] as String? ?? '';
        final isSelected = selectedIds?.contains(id) ?? false;
        return Card(
          color: isSelected ? AppColors.primaryWash : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            side: isSelected
                ? const BorderSide(color: AppColors.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.lg),
            onTap: () => onTap(d),
            onLongPress: onLongPress != null ? () => onLongPress!(d) : null,
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
                        _DriverWarningChips(driver: d),
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
    // Pending: foto ainda está em registration_selfie_url. Aprovados: photo_url.
    final photoUrl = (driver['photo_url'] as String?) ??
        (driver['registration_selfie_url'] as String?);
    final selfieUrl = driver['registration_selfie_url'] as String?;
    final docPhotoUrl = driver['document_photo_url'] as String?;
    final vehiclePhotoUrl = driver['vehicle_photo_url'] as String?;
    final vehicleDocUrl = driver['vehicle_doc_url'] as String?;
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

          // Selfie — re-sign quando vier de bucket privado (driver-documents).
          if (photoUrl != null)
            Center(
              child: PrivateBucketCircleAvatar(
                urlOrPath: photoUrl,
                radius: 50,
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
          const SizedBox(height: 12),
          Center(child: _ContactButtons(phone: driver['phone'] as String?)),
          const SizedBox(height: 8),

          // Documento
          _InfoRow(
              label: 'Tipo de doc.', value: driver['document_type'] as String?),
          _InfoRow(
              label: 'Nº documento',
              value: driver['document_number'] as String?),
          _InfoRow(label: 'NIF', value: driver['nif'] as String?),
          _InfoRow(label: 'Veículo', value: driver['vehicle_type'] as String?),
          _InfoRow(
              label: 'Matrícula',
              value: (driver['license_plate'] as String?)?.isEmpty == false
                  ? driver['license_plate'] as String
                  : null),
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

          // Foto documento — bucket privado driver-documents.
          if (docPhotoUrl != null) ...[
            const Text('Foto do documento',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, docPhotoUrl),
              child: PrivateBucketImage(
                urlOrPath: docPhotoUrl,
                height: 160,
                width: double.infinity,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Foto veículo — bucket privado driver-documents.
          if (vehiclePhotoUrl != null) ...[
            const Text('Foto do veículo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, vehiclePhotoUrl),
              child: PrivateBucketImage(
                urlOrPath: vehiclePhotoUrl,
                height: 160,
                width: double.infinity,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Documento do veículo (livrete) — bucket privado driver-documents.
          // Adicionado 2026-06-02 (auditoria fotos admin): admin precisa ver
          // o livrete já durante a aprovação, não só no detail.
          if (vehicleDocUrl != null) ...[
            const Text('Documento do veículo (livrete)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, vehicleDocUrl),
              child: PrivateBucketImage(
                urlOrPath: vehicleDocUrl,
                height: 160,
                width: double.infinity,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Selfie de registo — guardada em registration_selfie_url.
          if (selfieUrl != null) ...[
            const Text('Selfie de registo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullscreen(context, selfieUrl),
              child: PrivateBucketImage(
                urlOrPath: selfieUrl,
                height: 160,
                width: double.infinity,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showFullscreen(BuildContext context, String url) async {
    final resolved = await resolveSignedUrlIfPrivate(url) ?? url;
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(resolved),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Warning chips — invalid email/phone format ────────────────────────────────

class _DriverWarningChips extends StatelessWidget {
  const _DriverWarningChips({required this.driver});
  final Map<String, dynamic> driver;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[];
    final email = driver['email'] as String? ?? '';
    final phone = driver['phone'] as String? ?? '';
    final iban = driver['iban'] as String? ?? '';
    if (email.isNotEmpty && !email.contains('@')) warnings.add('⚠️ email');
    if (phone.isNotEmpty && phone.replaceAll(RegExp(r'\D'), '').length < 9) {
      warnings.add('⚠️ telefone');
    }
    if (iban.isNotEmpty && iban.replaceAll(' ', '').length != 25) {
      warnings.add('⚠️ IBAN');
    }
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      children: warnings
          .map((w) => Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(w,
                    style: TextStyle(
                        fontSize: 10, color: Colors.orange.shade900)),
              ))
          .toList(),
    );
  }
}

// ── Contact buttons ───────────────────────────────────────────────────────────

class _ContactButtons extends StatelessWidget {
  const _ContactButtons({required this.phone});
  final String? phone;

  Future<void> _launch(String scheme) async {
    if (phone == null || phone!.isEmpty) return;
    final uri = Uri.parse('$scheme:${phone!.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => _launch('tel'),
          icon: const Icon(Icons.phone, size: 16),
          label: const Text('Ligar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _launch('sms'),
          icon: const Icon(Icons.sms, size: 16),
          label: const Text('SMS'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ],
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
