import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/driver_documentos.dart';
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
      'approval_status, rejection_reason, submitted_at, reviewed_at, created_at';

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
      await _juntarAtividade(supabase, list);
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

  /// Comprovativo de atividade (bucket privado `provider-atividade`) e o
  /// "tenho atividade aberta" (`driver_fiscal_status`) de cada candidato,
  /// pendurados na linha como `_atividade` / `_fiscal`. Falha aberta: sem estas
  /// tabelas o ecrã continua a funcionar com o resto.
  Future<void> _juntarAtividade(
      SupabaseClient supabase, List<Map<String, dynamic>> list) async {
    final ids = list
        .map((d) => d['user_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final at = await supabase
          .from('provider_atividade')
          .select('user_id, nif, documento_path, documento_tipo, '
              'atividade_status, obrigatoria, enviado_em, decidido_em, motivo')
          .inFilter('user_id', ids);
      final porUser = {
        for (final r in List<Map<String, dynamic>>.from(at))
          r['user_id'].toString(): r
      };
      final fs = await supabase
          .from('driver_fiscal_status')
          .select('user_id, atividade_aberta, confirmado_em')
          .inFilter('user_id', ids);
      final fiscal = {
        for (final r in List<Map<String, dynamic>>.from(fs))
          r['user_id'].toString(): r
      };
      for (final d in list) {
        final uid = d['user_id']?.toString();
        d['_atividade'] = porUser[uid];
        d['_fiscal'] = fiscal[uid];
      }
    } catch (e) {
      debugPrint('[admin_driver_approval] atividade: $e');
    }
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

  /// Frase que o estafeta recebe (PT-PT — é a app dele, não o painel).
  static String _textoPedido(List<String> itens) =>
      'Para aprovarmos a tua conta de estafeta falta: ${juntarComE(itens)}. '
      'Abre a app Bora e envia no ecrã "Conta em análise".';

  /// "Pedir documentos em falta": aviso na app + push ao estafeta com a lista
  /// exata (RPC `admin_send_push_notification`, a porta única de mensagens do
  /// painel, que já grava no log de ações do admin) e uma linha no e2e_log.
  /// SMS automático não existe; depois do envio o painel oferece abrir o SMS
  /// já escrito no telemóvel do admin.
  Future<void> _pedirDocumentos(BuildContext ctx,
      Map<String, dynamic> driver, List<String> itens) async {
    final userId = driver['user_id']?.toString();
    if (userId == null || itens.isEmpty) return;
    final texto = _textoPedido(itens);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Pedir documentos em falta'),
        content: Text('O estafeta vai receber:\n\n$texto'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final sb = Supabase.instance.client;
    bool temAparelho = false;
    try {
      final r = await sb.rpc('admin_send_push_notification', params: {
        'p_recipient_type': 'driver',
        'p_recipient_id': userId,
        'p_title': 'Faltam documentos na tua candidatura',
        'p_body': texto,
        'p_data': {'tipo': 'documentos_em_falta'},
      });
      temAparelho = r is Map && r['fcm_token_found'] == true;
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    try {
      final id = driver['id']?.toString() ?? '';
      await sb.from('e2e_log').insert({
        'fluxo': 'cadastro-estafeta-fotos',
        'passo': 'pedir-documentos',
        'estado': 'ok',
        'detalhe': 'driver=${id.length > 8 ? id.substring(0, 8) : id} '
            'itens=${itens.join(', ')} aparelho=$temAparelho',
        'device': 'painel-admin',
      });
    } catch (e) {
      debugPrint('[admin_driver_approval] e2e_log: $e');
    }
    if (!ctx.mounted) return;
    final phone = (driver['phone'] as String?)?.replaceAll(' ', '');
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(temAparelho
          ? 'Pedido enviado (aviso na app + notificação).'
          : 'Aviso gravado na app, mas este estafeta não tem notificações '
              'ligadas. Manda também por SMS.'),
      action: (phone == null || phone.isEmpty)
          ? null
          : SnackBarAction(
              label: 'SMS',
              // `query` à mão: queryParameters troca os espaços por '+',
              // que a app de SMS mostra tal e qual.
              onPressed: () => launchUrl(Uri(
                scheme: 'sms',
                path: phone,
                query: 'body=${Uri.encodeComponent(texto)}',
              )),
            ),
    ));
  }

  /// Aprova o comprovativo de atividade aqui mesmo (o servidor só deixa
  /// aprovar a conta depois disto, nas candidaturas novas).
  Future<void> _aprovarComprovativo(
      BuildContext ctx, Map<String, dynamic> driver) async {
    final at = driver['_atividade'];
    final userId = driver['user_id']?.toString();
    if (at is! Map || userId == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Aprovar comprovativo?'),
        content: Text('Confirmas que viste o comprovativo de '
            '${driver['name'] ?? 'este estafeta'} e que a atividade está aberta '
            'com o NIF ${at['nif'] ?? driver['nif'] ?? '—'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .rpc('admin_provider_atividade_decidir', params: {
        'p_user_id': userId,
        'p_acao': 'aprovar',
        'p_motivo': null,
        'p_avisar': true,
      });
      if (ctx.mounted) Navigator.of(ctx).maybePop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Comprovativo aprovado (a pessoa foi avisada).'),
        backgroundColor: AppColors.success,
      ));
      await _load();
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(e.toString().contains('sem_documento')
            ? 'Ainda não há comprovativo para aprovar.'
            : humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
      ));
    }
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
        // Pendentes: a selfie ainda está em registration_selfie_url (bucket
        // privado — o avatar volta a assinar o endereço).
        final photoUrl = _texto(d['photo_url']) ??
            _texto(d['registration_selfie_url']);
        final falta = d['approval_status'] == 'approved'
            ? const <DocEmFalta>[]
            : _faltaDoCandidato(d);
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

String? _texto(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// O comprovativo de atividade conta para esta candidatura e ainda não chegou
/// (ou foi recusado). Para quem já trabalhava antes da data de corte
/// (`obrigatoria = false`) nunca falta.
bool _atividadeEmFaltaDoCandidato(Map<String, dynamic> d) {
  final a = d['_atividade'];
  if (a is! Map || a['obrigatoria'] != true) return false;
  return _texto(a['documento_path']) == null ||
      a['atividade_status'] == 'recusada';
}

List<DocEmFalta> _faltaDoCandidato(Map<String, dynamic> d) =>
    documentosEmFaltaEstafeta(d,
        atividadeEmFalta: _atividadeEmFaltaDoCandidato(d));

String _data(Object? v, {bool hora = false}) {
  final t = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  if (t == null) return '—';
  String dd(int n) => n.toString().padLeft(2, '0');
  final d = '${dd(t.day)}/${dd(t.month)}/${t.year}';
  return hora ? '$d ${dd(t.hour)}:${dd(t.minute)}' : d;
}

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
    final aprovado = d['approval_status'] == 'approved';
    final falta = aprovado ? const <DocEmFalta>[] : _faltaDoCandidato(d);
    final chavesEmFalta = falta.map((f) => f.chave).toSet();
    bool faltaItem(String chave) => chavesEmFalta.contains(chave);

    final selfie = _texto(d['registration_selfie_url']) ?? _texto(d['photo_url']);
    final semMatricula = (d['vehicle_type'] ?? '') == 'bicycle';
    final nascimento = DateTime.tryParse(d['birth_date']?.toString() ?? '');
    final idade = idadeEmAnos(nascimento, DateTime.now());
    final rejectionReason = _texto(d['rejection_reason']);
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
              _texto(d['name']) ?? '—',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: _ContactButtons(phone: d['phone'] as String?)),

          if (falta.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in falta)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'Falta: ${f.rotulo.toLowerCase()}',
                        style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error),
                      onPressed: () => onPedirDocumentos(
                          falta.map((f) => f.rotulo.toLowerCase()).toList()),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Pedir documentos em falta'),
                    ),
                  ),
                ],
              ),
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

          const _Seccao('Dados pessoais'),
          _Campo('Nome que aparece', d['name']),
          _Campo('Nome legal', d['legal_name']),
          _Campo('Telefone', d['phone']),
          _Campo('E-mail', d['email']),
          _Campo(
            'Data de nascimento',
            nascimento == null
                ? null
                : '${_data(d['birth_date'])}${idade == null ? '' : ' ($idade anos)'}',
          ),
          _Campo('Morada', d['address']),

          const _Seccao('Documento de identificação'),
          _Campo('Tipo', d['document_type']),
          _Campo('Número', d['document_number'],
              falta: faltaItem('document_number')),
          _FotoDoc(
            titulo: 'Foto do documento',
            urlOrPath: _texto(d['document_photo_url']),
            obrigatoria: true,
          ),

          const _Seccao('Fiscal'),
          _Campo('NIF', d['nif']),
          _Campo(
            'Atividade aberta',
            atividadeAberta == null ? null : (atividadeAberta ? 'Sim' : 'Não'),
          ),
          _ComprovativoAtividade(
            atividade: d['_atividade'] is Map
                ? Map<String, dynamic>.from(d['_atividade'] as Map)
                : null,
            falta: faltaItem('atividade'),
            onAprovar: onAprovarComprovativo,
          ),

          const _Seccao('Veículo'),
          _Campo('Tipo', veiculoEmPortugues(d['vehicle_type']?.toString())),
          if (!semMatricula)
            _Campo('Matrícula', d['license_plate'],
                falta: faltaItem('license_plate')),
          _Campo('Marca e modelo', d['vehicle_make_model']),
          _Campo('Cor', d['vehicle_color']),
          _FotoDoc(
            titulo: 'Foto do veículo',
            urlOrPath: _texto(d['vehicle_photo_url']),
            obrigatoria: !semMatricula,
          ),
          _FotoDoc(
            titulo: 'Documento do veículo (carta ou livrete)',
            urlOrPath: _texto(d['vehicle_doc_url']),
            obrigatoria: false,
          ),

          const _Seccao('Pagamento'),
          _Campo('IBAN', d['iban'], falta: faltaItem('iban')),
          _Campo('MB Way', d['mbway_phone']),
          _Campo('Forma de receber', switch (d['payment_method']) {
            'mbway' => 'MB Way',
            'iban' || 'transfer' || 'bank_transfer' => 'Transferência (IBAN)',
            final v => _texto(v),
          }),

          const _Seccao('Trabalho e termos'),
          _Campo('Modo de trabalho',
              modoDeTrabalhoEmPortugues(d['work_mode']?.toString())),
          _Campo(
            'Autocertificação DSA',
            _texto(d['dsa_self_certified_at']) == null
                ? null
                : '${_data(d['dsa_self_certified_at'], hora: true)}'
                    '${_texto(d['dsa_self_cert_version']) == null ? '' : ' · v${d['dsa_self_cert_version']}'}',
          ),
          _Campo(
            'Consentimento (termos)',
            _texto(d['consent_accepted_at']) == null
                ? null
                : '${_data(d['consent_accepted_at'], hora: true)}'
                    '${_texto(d['consent_version']) == null ? '' : ' · ${d['consent_version']}'}',
          ),
          _Campo('Candidatura enviada', _data(d['submitted_at'], hora: true)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Seccao extends StatelessWidget {
  const _Seccao(this.titulo);
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        titulo.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Uma linha "rótulo: valor". Vazio → "—"; vazio e obrigatório → "Falta" a
/// vermelho.
class _Campo extends StatelessWidget {
  const _Campo(this.label, this.value, {this.falta = false});
  final String label;
  final Object? value;
  final bool falta;

  @override
  Widget build(BuildContext context) {
    final v = _texto(value);
    final vazio = v == null || v == '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              vazio ? (falta ? 'Falta' : '—') : v,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: vazio && falta ? AppColors.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura de uma foto do bucket privado (toca para ampliar com zoom) ou,
/// sem foto, "Falta: …" a vermelho (obrigatória) / "Não enviada" (opcional).
class _FotoDoc extends StatelessWidget {
  const _FotoDoc({
    required this.titulo,
    required this.urlOrPath,
    required this.obrigatoria,
  });
  final String titulo;
  final String? urlOrPath;
  final bool obrigatoria;

  @override
  Widget build(BuildContext context) {
    final url = urlOrPath;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (url != null)
            PrivateBucketImage(
              urlOrPath: url,
              height: 170,
              width: double.infinity,
              borderRadius: BorderRadius.circular(10),
              tituloAmpliada: titulo,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: obrigatoria ? Colors.red.shade50 : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: obrigatoria
                        ? Colors.red.shade300
                        : AppColors.divider),
              ),
              child: Text(
                obrigatoria
                    ? 'Falta: ${titulo.toLowerCase()}'
                    : 'Não enviada (opcional)',
                style: TextStyle(
                  color: obrigatoria ? AppColors.error : AppColors.textSecondary,
                  fontWeight: obrigatoria ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Comprovativo de atividade (bucket privado `provider-atividade`): estado,
/// miniatura (foto) ou botão para abrir o PDF, e "Aprovar comprovativo" quando
/// está em análise.
class _ComprovativoAtividade extends StatelessWidget {
  const _ComprovativoAtividade({
    required this.atividade,
    required this.falta,
    required this.onAprovar,
  });
  final Map<String, dynamic>? atividade;
  final bool falta;
  final VoidCallback onAprovar;

  Future<void> _abrirPdf(BuildContext context, String path) async {
    try {
      final url = await Supabase.instance.client.storage
          .from('provider-atividade')
          .createSignedUrl(path, 120);
      final ok =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir o PDF neste aparelho.')));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = atividade;
    final path = _texto(a?['documento_path']);
    final status = a?['atividade_status']?.toString();
    final rotuloEstado = switch (status) {
      'aprovada' => 'Aprovado',
      'recusada' =>
        'Recusado${_texto(a?['motivo']) == null ? '' : ': ${a!['motivo']}'}',
      'em_analise' => path == null ? 'Falta enviar' : 'Em análise',
      _ => a == null ? 'Sem registo' : 'Por enviar',
    };
    final pdf = (a?['documento_tipo']?.toString() ?? '') == 'pdf';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comprovativo de atividade',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Estado: $rotuloEstado'
            '${_texto(a?['enviado_em']) == null ? '' : ' · enviado ${_data(a!['enviado_em'], hora: true)}'}',
            style: TextStyle(
              fontSize: 13,
              color: status == 'aprovada'
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (path != null && !pdf)
            PrivateBucketImage(
              urlOrPath: withPrivateBucketPrefix('provider-atividade', path),
              height: 170,
              width: double.infinity,
              borderRadius: BorderRadius.circular(10),
              tituloAmpliada: 'Comprovativo de atividade',
            )
          else if (path != null && pdf)
            OutlinedButton.icon(
              onPressed: () => _abrirPdf(context, path),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Abrir comprovativo (PDF)'),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: falta ? Colors.red.shade50 : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: falta ? Colors.red.shade300 : AppColors.divider),
              ),
              child: Text(
                falta
                    ? 'Falta: comprovativo de atividade'
                    : 'Não enviado (não obrigatório para esta conta)',
                style: TextStyle(
                  color: falta ? AppColors.error : AppColors.textSecondary,
                  fontWeight: falta ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          if (path != null && status == 'em_analise') ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: onAprovar,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Aprovar comprovativo'),
            ),
          ],
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
