import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/driver_documentos.dart';
import '../../services/robo_documentos.dart';
import '../../widgets/admin_documentos.dart';
import '../../widgets/admin_robo_documentos.dart';
import '../../widgets/admin_ficha_tvde.dart';
import '../../widgets/admin_other_role_badge.dart';
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

  // 22/10/2026 (Danilo: "o que pede lá tem que aparecer aqui pra mim"): tudo o
  // que o cadastro pede — nome legal, nascimento, DSA, consentimento, modo de
  // trabalho, cor/modelo do veículo — e não só documento/NIF/veículo/IBAN.
  static const _columns =
      'id, user_id, name, legal_name, phone, email, birth_date, address, '
      'vehicle_type, license_plate, vehicle_color, vehicle_make_model, '
      'photo_url, document_type, document_number, document_photo_url, '
      'vehicle_photo_url, vehicle_doc_url, registration_selfie_url, nif, '
      'iban, mbway_phone, payment_method, work_mode, dsa_self_certified_at, '
      'dsa_self_cert_version, consent_accepted_at, consent_version, '
      'approval_status, rejection_reason, submitted_at, reviewed_at, created_at, '
      // TVDE (motorista de passageiros) — 22/10, documentos de todos os papéis.
      'tvde_cert_foto_path, tvde_contrato_operador_path, carta_b_emitida_em, '
      'fala_portugues, tvde_curso_atualizacao_em, tvde_operator_id';

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
      // 22/10/2026: contas encerradas pelo titular (delete-account anonimiza e
      // marca deleted_at) não são candidaturas — saíam em "Pendentes" como
      // "Conta eliminada" com tudo em falta.
      final all = await supabase
          .from('drivers')
          .select(_columns)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(all);
      await juntarAtividadeAdmin(supabase, list);
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
    // Adendo 3: o servidor só aprova depois do comprovativo aprovado. Avisa já, com
    // mensagem clara, em vez de deixar a chamada falhar com 400.
    if (!await avisarSeAtividadePorAprovar(context, driver)) return;
    final avisosRobo = avisosParaAprovar(driver);

    bool force = false;
    String? justification;

    if (missing.isEmpty) {
      final ok = await _confirmSimple(
        title: 'Aprovar entregador?',
        body: 'Vais aprovar ${driver['name'] ?? 'este estafeta'}.'
            '${_textoAvisoRobo(avisosRobo)}',
        confirmLabel: avisosRobo.isEmpty ? 'Aprovar' : 'Aprovar mesmo assim',
        confirmColor: avisosRobo.isEmpty ? AppColors.success : AppColors.error,
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

  /// O que o robô viu de errado, para o diálogo de aprovar (vazio se não viu nada).
  String _textoAvisoRobo(List<String> avisos) {
    if (avisos.isEmpty) return '';
    final linhas = avisos.map((a) => '• $a').join('\n');
    return '\n\nATENÇÃO — o robô diz que há documento errado:\n$linhas';
  }

  /// Mesma regra que o estafeta vê no ecrã "Conta em análise".
  List<String> _missingDocs(Map<String, dynamic> driver) =>
      _faltaDoCandidato(driver).map((f) => f.rotulo).toList();

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
                    RoboAvisoAprovar(linha: driver),
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
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (sheetCtx, scrollController) => _DriverDetailSheet(
          driver: driver,
          scrollController: scrollController,
          onPedirDocumentos: (itens) =>
              _pedirDocumentos(sheetCtx, driver, itens),
          onAprovarComprovativo: () => _aprovarComprovativo(sheetCtx, driver),
        ),
      ),
    );
  }

  /// "Pedir documentos em falta" — peça comum a todos os papéis.
  Future<void> _pedirDocumentos(BuildContext ctx,
      Map<String, dynamic> driver, List<String> itens) async {
    final userId = driver['user_id']?.toString();
    if (userId == null) return;
    await pedirDocumentosEmFalta(ctx,
        userId: userId,
        tipoDestino: 'driver',
        quem: 'estafeta',
        itens: itens,
        telefone: driver['phone'] as String?,
        refId: driver['id']?.toString());
  }

  /// Aprova o comprovativo de atividade aqui mesmo (o servidor só deixa
  /// aprovar a conta depois disto, nas candidaturas novas).
  Future<void> _aprovarComprovativo(
      BuildContext ctx, Map<String, dynamic> driver) async {
    final at = driver['_atividade'];
    final userId = driver['user_id']?.toString();
    if (at is! Map || userId == null) return;
    final ok = await aprovarComprovativoAtividade(ctx,
        userId: userId,
        nome: driver['name']?.toString() ?? 'este estafeta',
        nif: (at['nif'] ?? driver['nif'])?.toString());
    if (!ok) return;
    if (ctx.mounted) Navigator.of(ctx).maybePop();
    if (mounted) await _load();
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
                  // 22/10: aprovados também têm de ter tudo — a ficha com os
                  // documentos (e o TVDE) abre por este botão.
                  actions: (d) => IconButton(
                    icon: const Icon(Icons.badge_outlined,
                        color: AppColors.primary),
                    tooltip: 'Documentos',
                    onPressed: () => _showDetail(d),
                  ),
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
        // Pendentes: a selfie ainda está em registration_selfie_url (bucket
        // privado — o avatar volta a assinar o endereço).
        final photoUrl = docTexto(d['photo_url']) ??
            docTexto(d['registration_selfie_url']);
        final falta = _faltaDoCandidato(d);
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
                  photoUrl != null
                      ? PrivateBucketCircleAvatar(urlOrPath: photoUrl, radius: 26)
                      : const CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.surface,
                          child: Icon(Icons.person,
                              color: AppColors.textSecondary),
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
                        if (falta.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Falta: ${juntarComE(falta.map((f) => f.rotulo.toLowerCase()).toList())}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        RoboResumoLinha(linha: d),
                        _DriverWarningChips(driver: d),
                        // MULTI-PAPEL: sinaliza se já é profissional de limpeza.
                        AdminOtherRoleBadge(
                          userId: d['user_id'] as String?,
                          show: OtherRole.cleaner,
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

// ── Regra do que falta (mesma do ecrã "Conta em análise") ───────────────────

List<DocEmFalta> _faltaDoCandidato(Map<String, dynamic> d) =>
    documentosEmFaltaEstafeta(d, atividadeEmFalta: atividadeEmFaltaDe(d));

// ── Driver detail bottom sheet ────────────────────────────────────────────────

/// Tudo o que o cadastro do estafeta pede, pela mesma ordem, com cada foto em
/// miniatura (toca para abrir em ecrã inteiro com zoom) e cada obrigatório em
/// falta a vermelho. Painel em PT-BR.
class _DriverDetailSheet extends StatelessWidget {
  const _DriverDetailSheet({
    required this.driver,
    required this.scrollController,
    required this.onPedirDocumentos,
    required this.onAprovarComprovativo,
  });

  final Map<String, dynamic> driver;
  final ScrollController scrollController;
  final void Function(List<String> itens) onPedirDocumentos;
  final VoidCallback onAprovarComprovativo;

  @override
  Widget build(BuildContext context) {
    final d = driver;
    final falta = _faltaDoCandidato(d);
    final chavesEmFalta = falta.map((f) => f.chave).toSet();
    bool faltaItem(String chave) => chavesEmFalta.contains(chave);

    // O "trabalhar noutro papel" grava caminho solto no balde (sem
    // `driver-documents/`) — sem o prefixo a foto saía partida.
    final selfieBruta =
        docTexto(d['registration_selfie_url']) ?? docTexto(d['photo_url']);
    final selfie = selfieBruta == null
        ? null
        : withPrivateBucketPrefix('driver-documents', selfieBruta);
    final semMatricula = (d['vehicle_type'] ?? '') == 'bicycle';
    final nascimento = DateTime.tryParse(d['birth_date']?.toString() ?? '');
    final idade = idadeEmAnos(nascimento, DateTime.now());
    final rejectionReason = docTexto(d['rejection_reason']);
    final fiscal = d['_fiscal'];
    final atividadeAberta =
        fiscal is Map ? fiscal['atividade_aberta'] as bool? : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ListView(
        controller: scrollController,
        children: [
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

          // Selfie — toca para ampliar.
          Center(
            child: selfie != null
                ? SizedBox(
                    width: 110,
                    height: 110,
                    child: PrivateBucketImage(
                      urlOrPath: selfie,
                      width: 110,
                      height: 110,
                      borderRadius: BorderRadius.circular(55),
                      tituloAmpliada: 'Foto pessoal (selfie)',
                    ),
                  )
                : Container(
                    width: 110,
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Text('Falta:\nselfie',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              docTexto(d['name']) ?? '—',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: _ContactButtons(phone: d['phone'] as String?)),
          if (vereditoDe(d, 'drivers.registration_selfie_url', ficheiro: selfieBruta) != null)
            RoboVereditoChip(
              veredito: vereditoDe(d, 'drivers.registration_selfie_url', ficheiro: selfieBruta)!,
              onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
            ),

          if (falta.isNotEmpty) ...[
            const SizedBox(height: 14),
            DocFaltaCaixa(
              falta: falta.map((f) => f.rotulo).toList(),
              onPedir: () => onPedirDocumentos(
                  falta.map((f) => f.rotulo.toLowerCase()).toList()),
            ),
          ],

          if (rejectionReason != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Motivo de rejeição: $rejectionReason',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],

          if (d['_robo'] != null) RoboResumoLinha(linha: d),
          if (avisosParaAprovar(d).isNotEmpty) RoboAvisoAprovar(linha: d),

          const DocSeccao('Dados pessoais'),
          DocCampo('Nome que aparece', d['name']),
          DocCampo('Nome legal', d['legal_name']),
          DocCampo('Telefone', d['phone']),
          DocCampo('E-mail', d['email']),
          DocCampo(
            'Data de nascimento',
            nascimento == null
                ? null
                : '${docData(d['birth_date'])}${idade == null ? '' : ' ($idade anos)'}',
          ),
          DocCampo('Morada', d['address']),

          const DocSeccao('Documento de identificação'),
          DocCampo('Tipo', d['document_type']),
          DocCampo('Número', d['document_number'],
              falta: faltaItem('document_number')),
          DocFoto(
            titulo: 'Foto do documento',
            urlOrPath: docTexto(d['document_photo_url']),
            obrigatoria: true,
            balde: 'driver-documents',
            veredito: vereditoDe(d, 'drivers.document_photo_url',
                ficheiro: docTexto(d['document_photo_url'])),
            onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
          ),

          const DocSeccao('Fiscal'),
          DocCampo('NIF', d['nif']),
          DocCampo(
            'Atividade aberta',
            atividadeAberta == null ? null : (atividadeAberta ? 'Sim' : 'Não'),
          ),
          DocComprovativoAtividade(
            atividade: d['_atividade'] is Map
                ? Map<String, dynamic>.from(d['_atividade'] as Map)
                : null,
            falta: faltaItem('atividade'),
            onAprovar: onAprovarComprovativo,
            veredito: vereditoDe(d, 'provider_atividade.documento_path',
                ficheiro: docTexto((d['_atividade'] as Map?)?['documento_path'])),
            onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
          ),

          const DocSeccao('Veículo'),
          DocCampo('Tipo', veiculoEmPortugues(d['vehicle_type']?.toString())),
          if (!semMatricula)
            DocCampo('Matrícula', d['license_plate'],
                falta: faltaItem('license_plate')),
          DocCampo('Marca e modelo', d['vehicle_make_model']),
          DocCampo('Cor', d['vehicle_color']),
          DocFoto(
            titulo: 'Foto do veículo',
            urlOrPath: docTexto(d['vehicle_photo_url']),
            obrigatoria: !semMatricula,
            balde: 'driver-documents',
            veredito: vereditoDe(d, 'drivers.vehicle_photo_url',
                ficheiro: docTexto(d['vehicle_photo_url'])),
            onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
          ),
          DocFoto(
            titulo: 'Documento do veículo (carta ou livrete)',
            urlOrPath: docTexto(d['vehicle_doc_url']),
            obrigatoria: false,
            balde: 'driver-documents',
            veredito: vereditoDe(d, 'drivers.vehicle_doc_url',
                ficheiro: docTexto(d['vehicle_doc_url'])),
            onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
          ),

          if (eMotoristaTvde(d)) FichaTvdeSecao(driver: d),

          const DocSeccao('Pagamento'),
          DocCampo('IBAN', d['iban'], falta: faltaItem('iban')),
          DocCampo('MB Way', d['mbway_phone']),
          DocCampo('Forma de receber', switch (d['payment_method']) {
            'mbway' => 'MB Way',
            'iban' || 'transfer' || 'bank_transfer' => 'Transferência (IBAN)',
            final v => docTexto(v),
          }),

          const DocSeccao('Trabalho e termos'),
          DocCampo('Modo de trabalho',
              modoDeTrabalhoEmPortugues(d['work_mode']?.toString())),
          DocCampo(
            'Autocertificação DSA',
            docTexto(d['dsa_self_certified_at']) == null
                ? null
                : '${docData(d['dsa_self_certified_at'], hora: true)}'
                    '${docTexto(d['dsa_self_cert_version']) == null ? '' : ' · v${d['dsa_self_cert_version']}'}',
          ),
          DocCampo(
            'Consentimento (termos)',
            docTexto(d['consent_accepted_at']) == null
                ? null
                : '${docData(d['consent_accepted_at'], hora: true)}'
                    '${docTexto(d['consent_version']) == null ? '' : ' · ${d['consent_version']}'}',
          ),
          DocCampo('Candidatura enviada', docData(d['submitted_at'], hora: true)),
          const SizedBox(height: 24),
        ],
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
