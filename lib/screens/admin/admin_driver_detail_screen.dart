import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin/admin_driver_service.dart';
import '../../services/prestador_suspensao_service.dart';
import '../../utils/gps_parado.dart';
import '../../utils/sinal_motorista.dart';
import '../../widgets/admin/ligado_sem_sinal.dart';
import '../../widgets/admin/escolher_estafeta_sheet.dart'
    show plataformaLabel, haQuantoTempo;
import '../../widgets/bora/bora_bottom_action_bar.dart';
import '../../services/robo_documentos.dart';
import '../../services/robo_documentos_service.dart';
import '../../widgets/admin_robo_documentos.dart';
import '../../widgets/private_bucket_image.dart';
import '_admin_password_reset_dialog.dart';
import '_admin_rpc_errors.dart';
import 'admin_papeis_screen.dart';
import 'admin_area_estafeta_screen.dart';
import 'admin_suspensao_comum.dart';
import '../../utils/hora_lisboa_ext.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/periodo_entregas.dart';

/// Full-screen admin detail for an approved driver. Pushed from
/// `admin_drivers_screen` and from the "Aprovados" tab of
/// `admin_driver_approval_screen` (FASE 3 BUG 2).
///
/// Tabs:
///   1. Visão geral — info, badges, action buttons (5)
///   2. Pedidos    — orders history (read-only)
///   3. Transações — driver_balances + driver_transactions (read-only)
///   4. Histórico  — admin_audit_log rows for this driver
///
/// [15/11/2026] Pedidos, Transações, saldo e Histórico procuram pelos DOIS
/// ids do entregador (user_id e drivers.id) — ver
/// [AdminDriverService.idsDoEntregador].
///
/// Action buttons (tab 1):
///   • Editar              — bottom sheet with whitelisted form (IBAN/NIF flagged)
///   • Banir               — modal: reason_code dropdown + reason + optional date picker
///   • Reativar            — visible only if banned/suspended/deleted
///   • Forçar logout       — single confirmation
///   • Remover             — checks orders in progress, then type driver name to confirm
class AdminDriverDetailScreen extends StatefulWidget {
  const AdminDriverDetailScreen({super.key, required this.driverId});

  final String driverId;

  @override
  State<AdminDriverDetailScreen> createState() =>
      _AdminDriverDetailScreenState();
}

class _AdminDriverDetailScreenState extends State<AdminDriverDetailScreen>
    with SingleTickerProviderStateMixin {
  final AdminDriverService _svc = AdminDriverService();
  late final TabController _tab;

  Map<String, dynamic>? _driver;
  String _effectiveStatus = 'active';
  Map<String, dynamic>? _balance;
  bool _loading = true;
  String? _error;

  // Last admin action (header strip).
  Map<String, dynamic>? _lastAction;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  static const _baseDriverCols =
      'id, user_id, name, phone, email, vehicle_type, license_plate, iban, nif, '
      'photo_url, is_online, is_banned, banned_at, banned_by, banned_until, '
      'ban_reason, ban_reason_code, deleted_at, deleted_by, deletion_reason, '
      'last_forced_logout_at, last_forced_logout_by, approval_status, created_at';

  // [15/11/2026] vehicle_color e vehicle_make_model: o "Editar dados" abre
  // com a cor e a marca/modelo (TVDE) preenchidas.
  static const _extendedDriverCols = '$_baseDriverCols, '
      'document_type, document_number, document_photo_url, vehicle_photo_url, '
      'vehicle_doc_url, registration_selfie_url, address, submitted_at, reviewed_at, '
      'mbway_phone, rejection_reason, last_heartbeat_at, rating, total_deliveries, '
      'vehicle_color, vehicle_make_model';

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;

      Map<String, dynamic>? driver;
      try {
        driver = await client
            .from('drivers')
            .select(_extendedDriverCols)
            .eq('id', widget.driverId)
            .maybeSingle();
      } catch (_) {
        // Fallback if any extended column does not exist yet.
        driver = await client
            .from('drivers')
            .select(_baseDriverCols)
            .eq('id', widget.driverId)
            .maybeSingle();
      }

      if (driver == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Entregador não encontrado.';
          });
        }
        return;
      }

      // Adendo 3: o veredito do robô junto a cada documento (`_robo`). Falha aberta.
      await juntarVereditosRobo(client, [driver]);

      final status = await client
          .rpc('driver_effective_status', params: {'p_driver_id': widget.driverId});

      // [15/11/2026] O saldo está no user_id (conta de login); a ficha antiga
      // pode tê-lo no drivers.id. Procura pelos dois e mostra o do user_id.
      final ids = AdminDriverService.idsDoEntregador(driver);
      final saldos = await client
          .from('driver_balances')
          .select('driver_id, balance, updated_at')
          .inFilter('driver_id', ids);
      final balance = AdminDriverService.saldoDoEntregador(
          List<Map<String, dynamic>>.from(saldos),
          AdminDriverService.authIdDoEntregador(driver));

      // A mesma procura do separador Histórico (os dois ids).
      final lastAction = await client
          .from('admin_audit_log')
          .select('action, admin_email, created_at, details')
          .or(AdminDriverService.filtroHistoricoDoEntregador(ids))
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _driver = Map<String, dynamic>.from(driver!);
        _effectiveStatus = (status as String?) ?? 'active';
        _balance = balance == null ? null : Map<String, dynamic>.from(balance);
        _lastAction = lastAction == null ? null : Map<String, dynamic>.from(lastAction);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erro ao carregar: ${humanizeAdminRpcError(e)}';
        });
      }
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : null,
      // Mensagem comprida (ex.: o que o "Forçar logout" faz hoje) fica mais
      // tempo, para dar para ler.
      duration: Duration(seconds: msg.length > 90 ? 8 : 4),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // [15/11/2026] user_id e drivers.id: os separadores procuram pelos dois.
    final ids = _driver == null
        ? <String>[widget.driverId]
        : AdminDriverService.idsDoEntregador(_driver!);
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
        title: Text(_driver?['name'] as String? ?? 'Entregador',
            style: const TextStyle(color: Colors.white)),
        actions: [
          // OS PAPEIS DESTA PESSOA (2026-08-29). Uma conta tem varios perfis;
          // a ficha dela tem de deixar ver e mexer em todos, nao so no de
          // estafeta.
          IconButton(
            icon: const Icon(Icons.badge_outlined),
            tooltip: 'Papéis desta pessoa',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminPapeisScreen(
                  buscaInicial: (_driver?['email'] as String?)?.trim().isNotEmpty == true
                      ? _driver!['email'] as String
                      : _driver?['name'] as String?,
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Visão geral'),
            Tab(text: 'Pedidos'),
            Tab(text: 'Transações'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _OverviewTab(
                      driver: _driver!,
                      effectiveStatus: _effectiveStatus,
                      balance: (_balance?['balance'] as num?)?.toDouble() ?? 0.0,
                      lastAction: _lastAction,
                      onAction: (action) async {
                        await action(_svc, _driver!, _toast);
                        if (mounted) _refresh();
                      },
                    ),
                    _OrdersTab(driverIds: ids),
                    _TransactionsTab(driverIds: ids, balance: _balance),
                    _AuditTab(driverIds: ids),
                  ],
                ),
    );
  }
}

// ── TAB 1 — Overview ────────────────────────────────────────────────────────

typedef _OverviewActionRunner = Future<void> Function(
  AdminDriverService svc,
  Map<String, dynamic> driver,
  void Function(String, {bool isError}) toast,
);

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.driver,
    required this.effectiveStatus,
    required this.balance,
    required this.lastAction,
    required this.onAction,
  });

  final Map<String, dynamic> driver;
  final String effectiveStatus;
  final double balance;
  final Map<String, dynamic>? lastAction;
  final void Function(_OverviewActionRunner) onAction;

  @override
  Widget build(BuildContext context) {
    final isBanned = effectiveStatus == 'banned' || effectiveStatus == 'suspended';
    final isDeleted = effectiveStatus == 'deleted';
    final showReactivate = isBanned || isDeleted;

    return RefreshIndicator(
      onRefresh: () async => onAction((_, __, ___) async {}),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(driver: driver, status: effectiveStatus, balance: balance),
          if (lastAction != null) ...[
            const SizedBox(height: 12),
            _LastActionStrip(entry: lastAction!),
          ],
          const SizedBox(height: 16),
          // [Escolher estafeta 16/09] Ligado? sinal? notificações? como usa a
          // Bora? + quem lhe passou pedidos (painel ou qual agente).
          _PresencaEHistoricoCard(
              driverId: (driver['user_id'] ?? driver['id']).toString()),
          const SizedBox(height: 16),
          _InfoCard(driver: driver),
          const SizedBox(height: 16),
          _DocumentsCard(driver: driver),
          const SizedBox(height: 16),
          _PerformanceCard(driver: driver, walletBalance: balance),
          const SizedBox(height: 16),
          _StatusDetailsCard(driver: driver, effectiveStatus: effectiveStatus),
          const SizedBox(height: 24),
          Text('Ações', style: Theme.of(context).textTheme.titleMedium),
          const _ParaQueServe(
              'O que a equipe pode fazer com esta conta. Tudo fica registrado '
              'no Histórico.'),
          const SizedBox(height: 4),
          // [15/11/2026 painel] Área do estafeta: o admin faz por ele o que ele
          // faz na app (pedidos, ganhos, conta, documentos), tudo auditado.
          _ActionButton(
            icon: Icons.badge_outlined,
            label: 'Área do estafeta (agir por ele)',
            // Sem conta de login ligada (user_id vazio) os ganhos, a conta e os
            // documentos não têm de onde vir: o botão fica desligado e diz porquê.
            subtitle: driver['user_id'] == null
                ? 'Este entregador não tem conta de login ligada: a área dele '
                    'não tem dados para mostrar.'
                : 'Ver o que ele vê agora e fazer por ele: pedidos, ganhos, '
                    'conta e documentos. Tudo fica registrado.',
            enabled: driver['user_id'] != null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AdminAreaEstafetaScreen(
                  driverId: driver['id'].toString(),
                  userId: (driver['user_id'] ?? driver['id']).toString(),
                  nome: driver['name']?.toString(),
                ),
              ),
            ),
          ),
          _ActionButton(
            icon: Icons.edit,
            label: 'Editar dados',
            onTap: () => onAction(_runEdit),
          ),
          _ActionButton(
            icon: Icons.block,
            label: 'Banir / suspender',
            subtitle: "Prefira 'Suspender com motivo': ele guarda o registro "
                'legal e avisa se o entregador tem pedido em andamento.',
            color: AppColors.error,
            enabled: !isDeleted && !isBanned,
            onTap: () => onAction(_runBan),
          ),
          // [01/11/2026 · B8] Registo legal completo (Diretiva 2024/2831):
          // temporária, sem data, encerramento ou restrição, com motivo.
          _ActionButton(
            icon: Icons.gavel,
            label: 'Suspender com motivo',
            color: AppColors.error,
            enabled: !isDeleted && !isBanned,
            onTap: () => onAction(_runSuspenderComMotivo),
          ),
          if (showReactivate)
            _ActionButton(
              icon: Icons.refresh,
              label: 'Reativar',
              color: AppColors.success,
              onTap: () => onAction(_runReactivate),
            ),
          _ActionButton(
            icon: Icons.logout,
            label: 'Forçar logout',
            color: AppColors.warning,
            onTap: () => onAction(_runForceLogout),
          ),
          // O link vai para a conta de login (auth.users.id), que é o
          // drivers.user_id. drivers.id NÃO é o auth.users.id: em 17 de 22
          // entregadores é outro número (15/11/2026). Só a ficha antiga sem
          // user_id usa drivers.id.
          if ((driver['email'] as String?)?.isNotEmpty ?? false)
            _ActionButton(
              icon: Icons.lock_reset,
              label: 'Enviar link de redefinição de senha',
              onTap: () => showAdminPasswordResetDialog(
                context,
                userId: AdminDriverService.authIdDoEntregador(driver),
                email: driver['email'].toString(),
                displayName: (driver['name'] ?? '').toString(),
              ),
            ),
          _ActionButton(
            icon: Icons.delete_forever,
            label: 'Remover (fica arquivado)',
            color: AppColors.error,
            enabled: !isDeleted,
            onTap: () => onAction(_runSoftDelete),
          ),
        ],
      ),
    );
  }

  // ── Action handlers ──────────────────────────────────────────────────────

  Future<void> _runEdit(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    final result = await showModalBottomSheet<_EditResult>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _EditDriverSheet(driver: driver),
    );
    if (result == null) return;
    try {
      final r = await svc.updateDriver(
        driverId: driver['id'] as String,
        reason: result.reason,
        name: result.name,
        phone: result.phone,
        vehicleType: result.vehicleType,
        licensePlate: result.licensePlate,
        iban: result.iban,
        nif: result.nif,
        vehicleColor: result.vehicleColor,
        vehicleMakeModel: result.vehicleMakeModel,
      );
      final changed = (r['fields_changed'] as List?)?.join(', ') ?? '';
      toast('Atualizado: $changed');
    } catch (e) {
      toast(_erroParaAdmin(e), isError: true);
    }
  }

  Future<void> _runBan(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    final result = await showDialog<_BanResult>(
      context: ctx,
      builder: (_) => const _BanDialog(),
    );
    if (result == null) return;
    try {
      await svc.banDriver(
        driverId: driver['id'] as String,
        reasonCode: result.reasonCode,
        reason: result.reason,
        bannedUntil: result.bannedUntil,
      );
      toast(result.bannedUntil == null
          ? 'Entregador banido permanentemente.'
          : 'Entregador suspenso até ${_fmtDate(result.bannedUntil!)}.');
    } catch (e) {
      toast(_erroParaAdmin(e), isError: true);
    }
  }

  Future<void> _runSuspenderComMotivo(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    await suspenderComMotivo(
      ctx,
      tabela: 'drivers',
      entidadeId: driver['id'].toString(),
      nome: driver['name'] as String?,
      // 02/11/2026: com a temporária (a manutenção levanta o bloqueio no
      // fim da data — ver kTiposSuspensaoEstafeta).
      tipos: kTiposSuspensaoEstafeta,
    );
  }

  Future<void> _runReactivate(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Reativar entregador?'),
        content: Text('Isso desfaz o banimento, a suspensão e/ou a remoção de '
            '"${driver['name']}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reativar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await svc.reactivateDriver(
        driverId: driver['id'] as String,
        note: 'Reativado pela ficha do entregador no painel',
      );
      // [01/11/2026 · B8] Fecha também o registo legal da suspensão (senão
      // fica "ativa" no histórico e na fila de revisões).
      await PrestadorSuspensaoService.fecharRegistoAberto('drivers',
          driver['id'].toString(), 'Reativado no painel (ficha do entregador)');
      final cleared = (r['cleared_states'] as List?)?.join(', ') ?? '';
      toast('Reativado (desfeito: $cleared).');
    } catch (e) {
      toast(_erroParaAdmin(e), isError: true);
    }
  }

  Future<void> _runForceLogout(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    // [15/11/2026] Dizer o que acontece HOJE: o servidor ainda não consegue
    // encerrar a sessão no celular (correção no servidor proposta).
    final reason = await showDialog<String>(
      context: ctx,
      builder: (_) => const _ReasonDialog(
        title: 'Forçar logout?',
        body: 'Ele fica offline e o aparelho principal deixa de receber avisos '
            'de pedidos. Hoje a sessão no celular dele pode continuar aberta '
            'até ele sair do app.',
        confirmLabel: 'Forçar logout',
      ),
    );
    if (reason == null) return;
    try {
      final r = await svc.forceLogout(
        driverId: driver['id'] as String,
        reason: reason,
      );
      final revoked = r['sessions_revoked'] == true;
      toast(revoked
          ? 'Feito: sessões encerradas, avisos do aparelho principal '
              'desligados e entregador offline.'
          : 'Feito: avisos do aparelho principal desligados e entregador '
              'offline. A sessão no celular dele pode continuar aberta até ele '
              'sair do app (correção no servidor proposta).');
    } catch (e) {
      toast(_erroParaAdmin(e), isError: true);
    }
  }

  Future<void> _runSoftDelete(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    final ctx = _AdminDriverDetailScreenContext.of();
    if (ctx == null) return;
    // [15/11/2026] O servidor, ao remover, só procura pedidos pelo drivers.id,
    // e os pedidos do app estão no user_id. O painel confere antes de abrir a
    // confirmação e de novo logo antes de chamar o servidor.
    if (await _temPedidoEmAndamento(svc, driver, toast)) return;
    if (!ctx.mounted) return;
    final result = await showDialog<String>(
      context: ctx,
      builder: (_) => _SoftDeleteDialog(expectedName: driver['name'] as String? ?? ''),
    );
    if (result == null) return;
    if (await _temPedidoEmAndamento(svc, driver, toast)) return;
    try {
      await svc.softDeleteDriver(
        driverId: driver['id'] as String,
        reason: result,
      );
      toast('Entregador removido (fica arquivado).');
    } catch (e) {
      toast(_erroParaAdmin(e), isError: true);
    }
  }

  /// `true` = travar o "Remover" (o admin já foi avisado): há pedido em
  /// andamento, ou não deu para conferir.
  Future<bool> _temPedidoEmAndamento(
    AdminDriverService svc,
    Map<String, dynamic> driver,
    void Function(String, {bool isError}) toast,
  ) async {
    try {
      final n = await svc.pedidosEmCurso(
          driverAuthId: AdminDriverService.authIdDoEntregador(driver));
      final bloqueio = AdminDriverService.bloqueioParaRemover(n);
      if (bloqueio == null) return false;
      toast(bloqueio, isError: true);
    } on AdminDriverException catch (e) {
      toast('${e.message} Nada foi removido.', isError: true);
    } catch (e) {
      toast(
          'Não foi possível conferir os pedidos em andamento '
          '(${humanizeAdminRpcError(e)}). Nada foi removido.',
          isError: true);
    }
    return true;
  }
}

/// Erro para mostrar ao admin. O que o serviço já traduziu vai como está; o
/// resto (erro do servidor que o serviço não conhece, erro inesperado) passa
/// pela tradução comum do painel, [humanizeAdminRpcError].
String _erroParaAdmin(Object e) {
  if (e is AdminDriverException) {
    final semTraducao = e.code == 'server_error' || e.code == 'unexpected';
    final causa = e.cause;
    return semTraducao && causa != null ? humanizeAdminRpcError(causa) : e.message;
  }
  return humanizeAdminRpcError(e);
}

/// Tiny lookup helper so action handlers above can find the parent
/// BuildContext without threading it through the typedef. Set lazily in build.
class _AdminDriverDetailScreenContext {
  static BuildContext? _ctx;
  static BuildContext? of() => _ctx;
  static void set(BuildContext c) => _ctx = c;
}

class _Header extends StatelessWidget {
  const _Header({required this.driver, required this.status, required this.balance});
  final Map<String, dynamic> driver;
  final String status;
  final double balance;

  @override
  Widget build(BuildContext context) {
    _AdminDriverDetailScreenContext.set(context);
    final photo = driver['photo_url'] as String?;
    final isOnline = driver['is_online'] == true;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundImage: (photo != null && photo.isNotEmpty)
                      ? NetworkImage(photo)
                      : null,
                  child: (photo == null || photo.isEmpty)
                      ? const Icon(Icons.person, size: 32, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver['name'] as String? ?? '—',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        _StatusBadge(status: status),
                        // [24/10/2026] Botão ligado sem sinal há >10 min não é "Online".
                        if (isOnline &&
                            driver.containsKey('last_heartbeat_at') &&
                            ligadoSemSinal(
                                ligado: true,
                                ultimoSinal: DateTime.tryParse(
                                    driver['last_heartbeat_at']?.toString() ?? '')))
                          _Pill(label: 'Ligado sem sinal', color: AppColors.error)
                        else if (isOnline)
                          _Pill(label: 'Online', color: AppColors.success),
                        _Pill(label: 'Saldo €${balance.toStringAsFixed(2)}',
                            color: AppColors.info),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active'    => ('Ativo', AppColors.success),
      'suspended' => ('Suspenso', AppColors.warning),
      'banned'    => ('Banido', AppColors.error),
      'deleted'   => ('Removido', AppColors.textSecondary),
      'pending'   => ('Pendente', AppColors.info),
      'rejected'  => ('Rejeitado', AppColors.error),
      _           => (status, AppColors.textSecondary),
    };
    return _Pill(label: label, color: color);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _LastActionStrip extends StatelessWidget {
  const _LastActionStrip({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final action = (entry['action'] as String?) ?? '—';
    final email = (entry['admin_email'] as String?) ?? '—';
    final at = DateTime.tryParse((entry['created_at'] as String?) ?? '');
    final ago = at == null ? '—' : _ago(at);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.history, size: 16, color: AppColors.info),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Última ação: $action por $email há $ago',
              style: const TextStyle(fontSize: 12, color: AppColors.info)),
        ),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.driver});
  final Map<String, dynamic> driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          _row(Icons.phone, 'Telefone', driver['phone']),
          _row(Icons.email_outlined, 'Email', driver['email']),
          _row(Icons.two_wheeler, 'Veículo',
              '${driver['vehicle_type'] ?? '—'}'
              '${driver['license_plate'] != null && (driver['license_plate'] as String).isNotEmpty ? " · ${driver['license_plate']}" : ""}'),
          _row(Icons.location_on_outlined, 'Endereço', driver['address'] ?? '—'),
          _row(Icons.account_balance, 'IBAN', driver['iban'] ?? '—'),
          _row(Icons.phone_android, 'MBWay', driver['mbway_phone'] ?? '—'),
          _row(Icons.badge_outlined, 'NIF', driver['nif'] ?? '—'),
          if (driver['submitted_at'] != null)
            _row(Icons.send, 'Enviado', _formatTs(driver['submitted_at'])),
          if (driver['reviewed_at'] != null)
            _row(Icons.check_circle_outline, 'Revisado', _formatTs(driver['reviewed_at'])),
        ]),
      ),
    );
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    final dt = DateTime.tryParse(ts.toString());
    if (dt == null) return ts.toString();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _row(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
        Expanded(child: Text(value?.toString() ?? '—')),
      ]),
    );
  }
}

// ── Documents card (FASE 5 — extended detail) ───────────────────────────────
//
// Shows document type/number and the two photos (document + vehicle) with
// click-to-zoom. Falls back gracefully when columns/photos are missing.
class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.driver});
  final Map<String, dynamic> driver;

  @override
  Widget build(BuildContext context) {
    final docType = driver['document_type'] as String?;
    final docNumber = driver['document_number'] as String?;
    final docPhoto = driver['document_photo_url'] as String?;
    final vehicleDocPhoto = driver['vehicle_doc_url'] as String?;
    final vehiclePhoto = driver['vehicle_photo_url'] as String?;
    final selfiePhoto = driver['registration_selfie_url'] as String?;

    final hasAny = (docType != null && docType.isNotEmpty) ||
        (docNumber != null && docNumber.isNotEmpty) ||
        (docPhoto != null && docPhoto.isNotEmpty) ||
        (vehicleDocPhoto != null && vehicleDocPhoto.isNotEmpty) ||
        (vehiclePhoto != null && vehiclePhoto.isNotEmpty) ||
        (selfiePhoto != null && selfiePhoto.isNotEmpty);
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Documentos',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const _ParaQueServe(
                'Documentos e fotos enviados no cadastro, com a análise do robô '
                'quando houver.'),
            if (docType != null && docType.isNotEmpty)
              _kv('Tipo', docType),
            if (docNumber != null && docNumber.isNotEmpty)
              _kv('Nº', docNumber),
            if (docPhoto != null && docPhoto.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Foto do documento',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _ZoomableImage(url: docPhoto),
              if (vereditoDe(driver, 'drivers.document_photo_url', ficheiro: docPhoto) != null)
                RoboVereditoChip(
                  veredito: vereditoDe(driver, 'drivers.document_photo_url', ficheiro: docPhoto)!,
                  onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
                ),
            ],
            if (vehicleDocPhoto != null && vehicleDocPhoto.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Documento do veículo',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _ZoomableImage(url: vehicleDocPhoto),
              if (vereditoDe(driver, 'drivers.vehicle_doc_url', ficheiro: vehicleDocPhoto) != null)
                RoboVereditoChip(
                  veredito: vereditoDe(driver, 'drivers.vehicle_doc_url', ficheiro: vehicleDocPhoto)!,
                  onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
                ),
            ],
            if (vehiclePhoto != null && vehiclePhoto.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Foto do veículo',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _ZoomableImage(url: vehiclePhoto),
              if (vereditoDe(driver, 'drivers.vehicle_photo_url', ficheiro: vehiclePhoto) != null)
                RoboVereditoChip(
                  veredito: vereditoDe(driver, 'drivers.vehicle_photo_url', ficheiro: vehiclePhoto)!,
                  onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
                ),
            ],
            if (selfiePhoto != null && selfiePhoto.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Selfie de verificação',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _ZoomableImage(url: selfiePhoto),
              if (vereditoDe(driver, 'drivers.registration_selfie_url', ficheiro: selfiePhoto) != null)
                RoboVereditoChip(
                  veredito: vereditoDe(driver, 'drivers.registration_selfie_url', ficheiro: selfiePhoto)!,
                  onDesfazer: (v) => desfazerDecisaoDoRobo(context, v),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

class _ZoomableImage extends StatelessWidget {
  const _ZoomableImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    // O toque abre a foto inteira (BoraFotoEcraInteiro) pelo próprio
    // PrivateBucketImage — não há ecrã inteiro próprio aqui (08/10/2026).
    return PrivateBucketImage(
      urlOrPath: url,
      height: 160,
      width: double.infinity,
      borderRadius: BorderRadius.circular(10),
    );
  }
}

// ── Performance card ────────────────────────────────────────────────────────
//
// Rating, deliveries, wallet balance and last heartbeat. All fields are
// optional; the card renders only the rows it has data for.
class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.driver, required this.walletBalance});
  final Map<String, dynamic> driver;
  final double walletBalance;

  @override
  Widget build(BuildContext context) {
    final rating = (driver['rating'] as num?)?.toDouble();
    final deliveries = (driver['total_deliveries'] as num?)?.toInt();
    final isOnline = driver['is_online'] == true;
    final heartbeatRaw = driver['last_heartbeat_at'] as String?;
    final heartbeat =
        heartbeatRaw == null ? null : DateTime.tryParse(heartbeatRaw);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Desempenho',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const _ParaQueServe(
                'Avaliação, entregas feitas, saldo e último sinal do app dele.'),
            _row(
              Icons.star_outline,
              'Avaliação',
              rating == null
                  ? '—'
                  : '${rating.toStringAsFixed(2)}'
                      '${deliveries == null ? '' : ' · $deliveries entregas'}',
            ),
            _row(Icons.account_balance_wallet_outlined, 'Saldo',
                '€${walletBalance.toStringAsFixed(2)}'),
            // [24/10/2026] Botão ligado mas sem sinal: diz desde quando e
            // deixa mandar o aviso ao telemóvel dele já.
            if (driver.containsKey('last_heartbeat_at') &&
                ligadoSemSinal(ligado: isOnline, ultimoSinal: heartbeat))
              LigadoSemSinalLinha(
                userId: driver['user_id']?.toString(),
                ultimoSinal: heartbeat,
                nome: driver['name'] as String?,
              )
            else
              _row(
                isOnline ? Icons.circle : Icons.circle_outlined,
                'Estado',
                isOnline ? 'Online' : 'Offline',
                color: isOnline ? AppColors.success : AppColors.textSecondary,
              ),
            _row(
              Icons.favorite_border,
              'Heartbeat',
              heartbeat == null ? '—' : _ago(heartbeat),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: color ?? AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

// ── Status details card ─────────────────────────────────────────────────────
//
// Surfaces rejection_reason (rejected) and ban_reason (banned/suspended).
// Hidden when none apply, so the card never shows empty.
/// [Escolher estafeta 16/09] Estado de presença (ligado agora, último sinal,
/// GPS, notificações, como usa a Bora, pedidos em curso) + histórico de quem
/// lhe passou pedidos. Lê as RPCs admin_driver_presence e
/// admin_driver_assignment_history; nunca escreve.
///
/// [A10 23/09] `online_agora` exige heartbeat vivo E GPS fresco
/// (`dispatch_gps_fresh_seconds`, 180 s). A linha "GPS" mostra a idade da
/// última posição (`gps_age_s`) e fica vermelha "parado há X min" quando
/// `gps_fresco` é falso — o caso da app morta com o heartbeat a bater.
class _PresencaEHistoricoCard extends StatefulWidget {
  const _PresencaEHistoricoCard({required this.driverId});
  final String driverId;

  @override
  State<_PresencaEHistoricoCard> createState() => _PresencaEHistoricoCardState();
}

class _PresencaEHistoricoCardState extends State<_PresencaEHistoricoCard> {
  Map<String, dynamic>? _p;
  List<Map<String, dynamic>> _hist = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final p = await client.rpc('admin_driver_presence', params: {'p_driver': widget.driverId});
      final h = await client.rpc('admin_driver_assignment_history',
          params: {'p_driver': widget.driverId, 'p_limit': 20});
      if (!mounted) return;
      setState(() {
        _p = (p is List && p.isNotEmpty && p.first is Map)
            ? Map<String, dynamic>.from(p.first as Map)
            : (p is Map ? Map<String, dynamic>.from(p) : null);
        _hist = (h is List)
            ? h.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [];
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminDriverDetail] presença: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _acao(String a) {
    switch (a) {
      case 'order_reassigned':
        return 'Pedido atribuído (painel)';
      case 'order_preassigned':
        return 'Pedido reservado (painel)';
      case 'order_reassigned_by_agent':
        return 'Pedido passado por agente';
      case 'order_driver_released':
        return 'Pedido devolvido a todos (painel)';
      case 'order_driver_released_by_agent':
        return 'Pedido devolvido a todos (agente)';
      case 'preassign_released':
        return 'Reserva liberada pelo sistema';
      default:
        return a;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final ligadoAgora = p?['online_agora'] == true;
    final hb = DateTime.tryParse(p?['last_heartbeat_at']?.toString() ?? '');
    final hbFresco =
        hb != null &&
        DateTime.now().toUtc().difference(hb.toUtc()).inSeconds <= 90;
    final gpsAge = (p?['gps_age_s'] as num?)?.toInt();
    // Sem a coluna (RPC antiga) não se inventa alarme.
    final gpsFresco = p?['gps_fresco'] != false;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Presença agora',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const _ParaQueServe(
                'Se ele pode receber pedidos agora e quem já passou pedidos '
                'para ele.'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (p == null)
              const Text('Sem dados de presença.',
                  style: TextStyle(color: AppColors.textSecondary))
            else ...[
              _row(
                ligadoAgora ? Icons.check_circle : Icons.cancel,
                'Ligado agora',
                ligadoAgora
                    ? 'Sim'
                    : (p['is_online'] == true
                          ? (hbFresco && !gpsFresco
                                ? 'Marcado ligado, mas GPS parado'
                                : 'Marcado ligado, mas sem sinal')
                          : 'Não'),
              ),
              _row(
                Icons.wifi_tethering,
                'Último sinal',
                hb == null
                    ? 'nunca'
                    : '${haQuantoTempo(hb)} (${hb.toLisboa().toString().substring(0, 16)})',
              ),
              _row(
                gpsFresco ? Icons.gps_fixed : Icons.gps_off,
                'GPS',
                gpsFresco
                    ? gpsIdadeTexto(gpsAge)
                    : '${gpsParadoHaTexto(gpsAge)} — não recebe pedidos',
                cor: gpsFresco ? null : const Color(0xFFB91C1C),
              ),
              _row(
                p['tem_notificacoes'] == true
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                'Notificações',
                p['tem_notificacoes'] == true
                    ? 'Sim (${p['tokens_ativos'] ?? 1} aparelho(s))'
                    : 'NÃO — não vai receber pedidos',
              ),
              _row(Icons.devices, 'Como usa a Bora', plataformaLabel(p['last_platform']?.toString())),
              _row(Icons.delivery_dining, 'Pedidos em andamento', '${p['pedidos_em_curso'] ?? 0}'),
            ],
            const SizedBox(height: 10),
            const Text('Quem passou pedidos para ele',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            if (!_loading && _hist.isEmpty)
              const Text('Nenhum registro.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            for (final h in _hist)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.history, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${dataHoraLisboa(h['created_at'])} · '
                        '${_acao((h['action'] ?? '').toString())} · '
                        'por ${h['quem'] ?? 'sistema'} · pedido '
                        '${(h['order_id'] ?? '').toString().replaceAll('-', '').substring(0, 6).toUpperCase()}'
                        '${(h['details'] is Map && (h['details'] as Map)['motivo'] != null) ? ' · ${(h['details'] as Map)['motivo']}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Color? cor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cor ?? AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDetailsCard extends StatelessWidget {
  const _StatusDetailsCard(
      {required this.driver, required this.effectiveStatus});
  final Map<String, dynamic> driver;
  final String effectiveStatus;

  @override
  Widget build(BuildContext context) {
    final approvalStatus =
        (driver['approval_status'] as String?) ?? 'pending';
    final rejectionReason = driver['rejection_reason'] as String?;
    final banReason = driver['ban_reason'] as String?;
    final banReasonCode = driver['ban_reason_code'] as String?;
    final bannedUntilRaw = driver['banned_until'] as String?;
    final bannedUntil =
        bannedUntilRaw == null ? null : DateTime.tryParse(bannedUntilRaw);

    final isRejected = approvalStatus == 'rejected';
    final isBanned = effectiveStatus == 'banned' ||
        effectiveStatus == 'suspended';

    if (!isRejected && !isBanned) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estado',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const _ParaQueServe('Por que ele foi recusado ou bloqueado.'),
            if (isRejected && rejectionReason != null && rejectionReason.isNotEmpty)
              _block(
                icon: Icons.cancel_outlined,
                label: 'Motivo de rejeição',
                value: rejectionReason,
              ),
            if (isBanned) ...[
              _block(
                icon: Icons.block,
                label: 'Motivo do banimento',
                value: [
                  if (banReasonCode != null && banReasonCode.isNotEmpty)
                    '[$banReasonCode]',
                  if (banReason != null && banReason.isNotEmpty) banReason,
                ].join(' '),
              ),
              if (bannedUntil != null)
                _block(
                  icon: Icons.event_busy,
                  label: 'Suspenso até',
                  value: _fmtDate(bannedUntil),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _block({
    required IconData icon,
    required String label,
    required String value,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.error),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Uma frase curta a dizer para que serve a aba ou o bloco (painel em PT-BR).
class _ParaQueServe extends StatelessWidget {
  const _ParaQueServe(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(texto,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: enabled ? (color ?? AppColors.primary) : AppColors.textSubtle),
        title: Text(label,
            style: TextStyle(
                color: enabled ? AppColors.textPrimary : AppColors.textSubtle,
                fontWeight: FontWeight.w600)),
        subtitle: sub == null
            ? null
            : Text(sub,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }
}

// ── Edit driver sheet ──────────────────────────────────────────────────────

class _EditResult {
  const _EditResult({
    required this.reason,
    this.name,
    this.phone,
    this.vehicleType,
    this.licensePlate,
    this.iban,
    this.nif,
    this.vehicleColor,
    this.vehicleMakeModel,
  });
  final String reason;
  final String? name, phone, vehicleType, licensePlate, iban, nif;
  // TVDE — cor + marca/modelo do carro.
  final String? vehicleColor, vehicleMakeModel;
}

class _EditDriverSheet extends StatefulWidget {
  const _EditDriverSheet({required this.driver});
  final Map<String, dynamic> driver;
  @override
  State<_EditDriverSheet> createState() => _EditDriverSheetState();
}

class _EditDriverSheetState extends State<_EditDriverSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _plate;
  late final TextEditingController _color;
  late final TextEditingController _makeModel;
  late final TextEditingController _iban;
  late final TextEditingController _nif;
  late final TextEditingController _reason;
  String _vt = 'motorcycle';
  bool _confirmIbanNif = false;

  @override
  void initState() {
    super.initState();
    _name  = TextEditingController(text: widget.driver['name'] as String? ?? '');
    _phone = TextEditingController(text: widget.driver['phone'] as String? ?? '');
    _plate = TextEditingController(text: widget.driver['license_plate'] as String? ?? '');
    _color = TextEditingController(text: widget.driver['vehicle_color'] as String? ?? '');
    _makeModel = TextEditingController(text: widget.driver['vehicle_make_model'] as String? ?? '');
    _iban  = TextEditingController(text: widget.driver['iban'] as String? ?? '');
    _nif   = TextEditingController(text: widget.driver['nif'] as String? ?? '');
    _reason = TextEditingController();
    _vt = (widget.driver['vehicle_type'] as String?) ?? 'motorcycle';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _plate, _color, _makeModel, _iban, _nif, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Returns the new value if changed; null if unchanged.
  /// Anomalia #3: campo cleared (vazio após trim) → null em vez de '' →
  /// RPC interpreta NULL como "não alterar". Empty string semântica é
  /// preservada apenas se o valor original já era vazio (resulta em null
  /// = "no change") — clear explícito de IBAN/NIF não suportado por
  /// design (admin tem que usar acção dedicada se precisar).
  String? _diff(TextEditingController c, String? original) {
    final v = c.text.trim();
    final o = (original ?? '').trim();
    if (v == o) return null;
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    // Comparação simétrica trimada (anomalia #3: trailing spaces no DB
    // não devem desencadear sensitiveChanged falso-positivo).
    final origIban = ((widget.driver['iban'] as String?) ?? '').trim();
    final origNif  = ((widget.driver['nif']  as String?) ?? '').trim();
    final ibanChanged = _iban.text.trim() != origIban;
    final nifChanged  = _nif.text.trim()  != origNif;
    final sensitiveChanged = ibanChanged || nifChanged;

    // Anomalia #2: auto-desticka checkbox quando admin reverte a edição
    // (sensitiveChanged passa de true→false). Schedule para próxima frame
    // para evitar setState-during-build.
    if (!sensitiveChanged && _confirmIbanNif) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _confirmIbanNif = false);
      });
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: BoraBottomActionBar.folgaInferior(context),
        left: 16, right: 16, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Editar dados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Telefone')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _vt,
              decoration: const InputDecoration(labelText: 'Veículo'),
              // [15/11/2026] 'carro_passageiros' (TVDE, 5 motoristas): sem
              // ele o formulário destes motoristas abria com o veículo vazio.
              items: const [
                DropdownMenuItem(value: 'motorcycle', child: Text('Moto')),
                DropdownMenuItem(value: 'car',        child: Text('Carro')),
                DropdownMenuItem(value: 'bicycle',    child: Text('Bicicleta')),
                DropdownMenuItem(
                    value: 'carro_passageiros',
                    child: Text('Carro de passageiros (TVDE)')),
              ],
              onChanged: (v) => setState(() => _vt = v ?? 'motorcycle'),
            ),
            TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Placa')),
            // TVDE — carro visível ao passageiro no cartão.
            TextField(controller: _makeModel, decoration: const InputDecoration(labelText: 'Marca e modelo (TVDE)')),
            TextField(controller: _color, decoration: const InputDecoration(labelText: 'Cor do carro (TVDE)')),
            const SizedBox(height: 12),
            const Text('Dados sensíveis (o valor fica oculto no histórico)', style: TextStyle(color: AppColors.warning, fontSize: 12)),
            // BUG 1 fix: onChanged trigger setState para que sensitiveChanged
            // se actualize dinamicamente quando admin tipa nestes campos.
            // Sem isto o build só re-corre quando _reason muda, deixando o
            // banner/checkbox em estado stale.
            TextField(
              controller: _iban,
              decoration: const InputDecoration(labelText: 'IBAN'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _nif,
              decoration: const InputDecoration(labelText: 'NIF'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Motivo (obrigatório, mínimo 3 letras)'),
              minLines: 1, maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            if (sensitiveChanged) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você vai alterar ${ibanChanged && nifChanged ? "IBAN e NIF" : ibanChanged ? "IBAN" : "NIF"} '
                      '(dados financeiros/fiscais).',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
              CheckboxListTile(
                value: _confirmIbanNif,
                onChanged: (v) => setState(() => _confirmIbanNif = v ?? false),
                title: const Text('Confirmo a alteração de dados sensíveis',
                    style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                onPressed: (_reason.text.trim().length < 3 ||
                            (sensitiveChanged && !_confirmIbanNif))
                    ? null
                    : () {
                        Navigator.pop(context, _EditResult(
                          reason: _reason.text.trim(),
                          name:         _diff(_name, widget.driver['name'] as String?),
                          phone:        _diff(_phone, widget.driver['phone'] as String?),
                          vehicleType:  _vt != (widget.driver['vehicle_type'] as String?) ? _vt : null,
                          licensePlate: _diff(_plate, widget.driver['license_plate'] as String?),
                          vehicleColor: _diff(_color, widget.driver['vehicle_color'] as String?),
                          vehicleMakeModel: _diff(_makeModel, widget.driver['vehicle_make_model'] as String?),
                          iban:         _diff(_iban, widget.driver['iban'] as String?),
                          nif:          _diff(_nif, widget.driver['nif'] as String?),
                        ));
                      },
                child: const Text('Salvar'),
              )),
            ]),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Ban dialog ─────────────────────────────────────────────────────────────

class _BanResult {
  const _BanResult({required this.reasonCode, required this.reason, this.bannedUntil});
  final String reasonCode;
  final String reason;
  final DateTime? bannedUntil;
}

class _BanDialog extends StatefulWidget {
  const _BanDialog();
  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  String _code = 'misconduct';
  final TextEditingController _reason = TextEditingController();
  DateTime? _until;

  static const _codes = <(String, String)>[
    ('fraud',             'Fraude'),
    ('misconduct',        'Conduta imprópria'),
    ('documents_invalid', 'Documentos inválidos'),
    ('inactivity',        'Inatividade'),
    ('safety',            'Segurança'),
    ('other',             'Outro'),
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now.add(const Duration(hours: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _until = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Banir / suspender entregador'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _code,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: _codes
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _code = v ?? 'misconduct'),
            ),
            const SizedBox(height: 12),
            // [01/11/2026 · B8] O gatilho do servidor exige 10 letras: o
            // entregador recebe o motivo por escrito (Diretiva 2024/2831).
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Motivo (mín. $kMinLetrasMotivoSuspensao letras — '
                    'o entregador recebe por escrito)',
              ),
              minLines: 2, maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                  _until == null
                      ? 'Permanente'
                      : 'Suspenso até ${_fmtDate(_until!)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_until == null ? 'Definir data' : 'Alterar'),
                onPressed: _pickUntil,
              ),
              if (_until != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Tornar permanente',
                  onPressed: () => setState(() => _until = null),
                ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _reason.text.trim().length < kMinLetrasMotivoSuspensao
              ? null
              : () => Navigator.pop(
                    context,
                    _BanResult(
                      reasonCode: _code,
                      reason: _reason.text.trim(),
                      bannedUntil: _until,
                    ),
                  ),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Banir'),
        ),
      ],
    );
  }
}

// ── Reason dialog (used by force-logout) ───────────────────────────────────

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.body, required this.confirmLabel});
  final String title;
  final String body;
  final String confirmLabel;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _c = TextEditingController();
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.body),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          decoration: const InputDecoration(labelText: 'Motivo (mínimo 3 letras)'),
          minLines: 1, maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _c.text.trim().length < 3
              ? null
              : () => Navigator.pop(context, _c.text.trim()),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ── Soft-delete dialog (type-name confirmation) ────────────────────────────

class _SoftDeleteDialog extends StatefulWidget {
  const _SoftDeleteDialog({required this.expectedName});
  final String expectedName;
  @override
  State<_SoftDeleteDialog> createState() => _SoftDeleteDialogState();
}

class _SoftDeleteDialogState extends State<_SoftDeleteDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  @override void dispose() { _name.dispose(); _reason.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final nameOk = _name.text.trim() == widget.expectedName.trim();
    // [01/11/2026 · B8] Remover = encerrar a conta: 10 letras (servidor).
    final reasonOk = _reason.text.trim().length >= kMinLetrasMotivoSuspensao;
    return AlertDialog(
      // Texto mais comprido (aviso do dinheiro): rola em tela pequena.
      scrollable: true,
      title: const Text('Remover entregador'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'A conta fica arquivada: o registro é guardado para não perder '
          'pedidos, transações e histórico, mas o entregador deixa de trabalhar.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        // [15/11/2026] O servidor confere o saldo e os acertos pelo
        // drivers.id, mas o dinheiro está no user_id (correção proposta).
        const Text(
          'Atenção: o painel ainda não consegue conferir se há dinheiro '
          'pendente com este entregador (saldo ou acertos); a correção no '
          'servidor está proposta. Confira antes de remover.',
          style: TextStyle(fontSize: 12, color: AppColors.warning),
        ),
        const SizedBox(height: 12),
        Text('Para confirmar, digite o nome exato: "${widget.expectedName}"',
            style: const TextStyle(fontSize: 12, color: AppColors.error)),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nome do entregador'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
              labelText: 'Motivo (mín. $kMinLetrasMotivoSuspensao letras — '
                  'o entregador recebe por escrito)'),
          minLines: 1, maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: (nameOk && reasonOk) ? () => Navigator.pop(context, _reason.text.trim()) : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Remover'),
        ),
      ],
    );
  }
}

// ── TAB 2 — Orders ──────────────────────────────────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.driverIds});

  /// user_id e drivers.id: o pedido guarda o entregador pelo user_id (os
  /// antigos, às vezes, pelo drivers.id).
  final List<String> driverIds;
  @override State<_OrdersTab> createState() => _OrdersTabState();
}

/// app-15-11 (paridade admin do separador Pedidos do estafeta): o mesmo
/// seletor de período (hoje, esta semana, semana passada, este mês), com o
/// total que o entregador ganhou e o número de entregas feitas no período.
/// A conta do período é a mesma função do app ([entregaNoPeriodo]).
class _OrdersTabState extends State<_OrdersTab> {
  /// `null` = "Últimos 50", de qualquer data (o que o separador já mostrava).
  PeriodoEntregas? _periodo = PeriodoEntregas.estaSemana;

  /// O servidor devolveu o máximo (500): pode haver mais no período.
  bool _chegouAoLimite = false;
  late Future<List<Map<String, dynamic>>> _f;
  @override void initState() { super.initState(); _f = _load(); }

  Future<List<Map<String, dynamic>>> _load() async {
    final periodo = _periodo;
    final client = Supabase.instance.client;
    const colunas = 'id, status, payment_method, final_total, driver_earnings, '
        'created_at, delivered_at, restaurant_id, restaurants(id, name)';
    if (periodo == null) {
      _chegouAoLimite = false;
      final res = await client
          .from('orders')
          .select(colunas)
          .inFilter('assigned_driver_id', widget.driverIds)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(res);
    }
    final agora = DateTime.now();
    // instanteDeLisboa só lê ano/mês/dia do dia (data UTC): o fuso do
    // navegador não entra na conta.
    final de = instanteDeLisboa(inicioDoPeriodo(periodo, agora));
    final ate = instanteDeLisboa(periodo == PeriodoEntregas.semanaPassada
        ? inicioDoPeriodo(PeriodoEntregas.estaSemana, agora)
        : diaLisboa(agora).add(const Duration(days: 1)));
    // app-15-11 (Juiz): entregue no período (pela hora da entrega) OU, sem
    // entrega, feito no período — apanha também o pedido marcado feito dias
    // antes e entregue agora. O filtro fino (dias de Lisboa) é o de baixo.
    final deIso = de.toIso8601String();
    final ateIso = ate.toIso8601String();
    final res = await client
        .from('orders')
        .select(colunas)
        .inFilter('assigned_driver_id', widget.driverIds)
        .or('and(delivered_at.gte.$deIso,delivered_at.lt.$ateIso),'
            'and(delivered_at.is.null,created_at.gte.$deIso,created_at.lt.$ateIso)')
        .order('created_at', ascending: false)
        .limit(500);
    _chegouAoLimite = (res as List).length >= 500;
    return List<Map<String, dynamic>>.from(res)
        .where((o) {
          // Como no app: conta a hora da entrega; sem ela, a do pedido.
          final at = DateTime.tryParse(
              (o['delivered_at'] ?? o['created_at'])?.toString() ?? '');
          return at != null && entregaNoPeriodo(at, periodo, agora);
        })
        .toList();
  }

  void _escolher(PeriodoEntregas? p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _f = _load();
    });
  }

  Widget _seletor() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final p in PeriodoEntregas.values) ...[
            ChoiceChip(
              key: ValueKey('admin_estafeta_periodo_${p.name}'),
              label: Text(p.rotulo),
              selected: p == _periodo,
              onSelected: (_) => _escolher(p),
            ),
            const SizedBox(width: 8),
          ],
          ChoiceChip(
            key: const ValueKey('admin_estafeta_periodo_todos'),
            label: const Text('Últimos 50'),
            selected: _periodo == null,
            onSelected: (_) => _escolher(null),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: _ParaQueServe('Pedidos atribuídos a este entregador e quanto '
              'ele ganhou no período escolhido.'),
        ),
        _seletor(),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Erro: ${humanizeAdminRpcError(snap.error!)}'));
              }
              final orders = snap.data ?? const [];
              final entregues =
                  orders.where((o) => o['status'] == 'delivered').toList();
              final ganho = entregues.fold<double>(
                  0, (s, o) => s + ((o['driver_earnings'] as num?) ?? 0));
              final n = entregues.length;
              return RefreshIndicator(
                onRefresh: () async => setState(() => _f = _load()),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return ListTile(
                        key: const Key('admin_estafeta_total_periodo'),
                        title: Text(
                          'Ganhou €${ganho.toStringAsFixed(2)} — ${_periodo?.rotulo.toLowerCase() ?? 'últimos 50 pedidos'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '$n ${n == 1 ? 'entrega feita' : 'entregas feitas'}'
                          ' · ${orders.length} pedidos atribuídos no período'
                          '${_chegouAoLimite ? ' (mostrando os 500 mais recentes)' : ''}',
                        ),
                      );
                    }
                    final o = orders[i - 1];
                    final at = DateTime.tryParse((o['created_at'] as String?) ?? '');
                    final restaurantName =
                        (o['restaurants'] as Map?)?['name'] as String?;
                    final ganhoPedido = (o['driver_earnings'] as num?) ?? 0;
                    return ListTile(
                      title: Text(restaurantName ?? 'Sem origem'),
                      subtitle: Text('${o['status']} · ${o['payment_method'] ?? '—'} · '
                          '€${((o['final_total'] as num?) ?? 0).toStringAsFixed(2)}'
                          ' · ganho €${ganhoPedido.toStringAsFixed(2)}'),
                      trailing: Text(at == null ? '—' : _fmtDate(at),
                          style: const TextStyle(fontSize: 11)),
                      dense: true,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── TAB 3 — Transactions ───────────────────────────────────────────────────

class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab({required this.driverIds, required this.balance});

  /// user_id e drivers.id: as transações usam driver_id = user_id.
  final List<String> driverIds;
  final Map<String, dynamic>? balance;
  @override State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  late Future<List<Map<String, dynamic>>> _f;
  @override void initState() { super.initState(); _f = _load(); }
  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .from('driver_transactions')
        .select('id, amount, type, status, created_at, notes, order_id')
        .inFilter('driver_id', widget.driverIds)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Widget build(BuildContext context) {
    final balance = (widget.balance?['balance'] as num?)?.toDouble() ?? 0.0;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Text('Erro: ${humanizeAdminRpcError(snap.error!)}'));
        }
        final txs = snap.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const _ParaQueServe(
                  'Movimentos de saldo do entregador: ganhos, acertos e ajustes.'),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  boxShadow: AppColors.shadowCard,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.account_balance_wallet, color: AppColors.info),
                    const SizedBox(width: 12),
                    Text('Saldo atual em dinheiro: €${balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (txs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Sem transações.')),
                )
              else
                ...txs.map((t) {
                  final at = DateTime.tryParse((t['created_at'] as String?) ?? '');
                  final amount = ((t['amount'] as num?) ?? 0).toDouble();
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      boxShadow: AppColors.shadowCard,
                    ),
                    child: ListTile(
                      title: Text('€${amount.toStringAsFixed(2)} · ${t['type']}'),
                      subtitle: Text('${t['status']}'
                          '${t['notes'] != null ? "\n${t['notes']}" : ""}'),
                      trailing: Text(at == null ? '—' : _fmtDate(at),
                          style: const TextStyle(fontSize: 11)),
                      isThreeLine: t['notes'] != null,
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// ── TAB 4 — Histórico (admin_audit_log) ────────────────────────────────────

class _AuditTab extends StatefulWidget {
  const _AuditTab({required this.driverIds});

  /// user_id e drivers.id: as entradas do histórico usam um ou outro, na
  /// coluna uuid (entity_id) ou na de texto (entity_id_text).
  final List<String> driverIds;
  @override State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  late Future<List<Map<String, dynamic>>> _f;
  @override void initState() { super.initState(); _f = _load(); }
  Future<List<Map<String, dynamic>>> _load() async {
    // [15/11/2026] Tudo o que a equipe registrou sobre esta pessoa, pelos
    // dois ids (aprovações, acertos, papéis, acesso TVDE…), não só as
    // entradas do tipo 'driver' gravadas com o drivers.id.
    final res = await Supabase.instance.client
        .from('admin_audit_log')
        .select('id, action, admin_email, details, created_at')
        .or(AdminDriverService.filtroHistoricoDoEntregador(widget.driverIds))
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(res);
  }

  static const _explicacao = _ParaQueServe(
      'Tudo o que a equipe registrou sobre esta conta, do mais recente para o '
      'mais antigo.');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Text('Erro: ${humanizeAdminRpcError(snap.error!)}'));
        }
        final entries = snap.data ?? const [];
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _explicacao,
                Expanded(
                    child: Center(child: Text('Nenhum registro no histórico.'))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length + 1,
            separatorBuilder: (_, i) => i == 0
                ? const SizedBox.shrink()
                : const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (_, i) {
              if (i == 0) return _explicacao;
              final e = entries[i - 1];
              final at = DateTime.tryParse((e['created_at'] as String?) ?? '');
              // Entradas de outros tipos podem trazer details que não é mapa.
              final raw = e['details'];
              final details =
                  raw is Map ? Map<String, dynamic>.from(raw) : null;
              final summary = details == null ? '' : _summariseDetails(details);
              return ListTile(
                leading: Icon(_iconFor(e['action'] as String?), color: AppColors.primary, size: 20),
                title: Text(e['action'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${e['admin_email'] ?? '—'}${summary.isEmpty ? '' : '\n$summary'}',
                    style: const TextStyle(fontSize: 12)),
                trailing: Text(at == null ? '—' : _fmtDate(at),
                    style: const TextStyle(fontSize: 11)),
                isThreeLine: summary.isNotEmpty,
              );
            },
          ),
        );
      },
    );
  }

  IconData _iconFor(String? action) {
    if (action == null) return Icons.history;
    if (action.startsWith('driver_ban') || action == 'driver_suspend') return Icons.block;
    if (action == 'driver_reactivate') return Icons.refresh;
    if (action.startsWith('driver_update')) return Icons.edit;
    if (action == 'driver_soft_delete') return Icons.delete_forever;
    if (action == 'driver_force_logout') return Icons.logout;
    if (action.startsWith('driver_approve') || action.startsWith('driver_force_approve')) return Icons.check_circle;
    if (action == 'driver_reject') return Icons.cancel;
    return Icons.history;
  }

  String _summariseDetails(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['reason'] != null) parts.add('"${d['reason']}"');
    if (d['reason_code'] != null) parts.add('cat=${d['reason_code']}');
    if (d['banned_until'] != null) parts.add('até ${d['banned_until']}');
    if (d['cleared_states'] != null) parts.add('limpos=${d['cleared_states']}');
    if (d['fields_changed'] != null) parts.add('campos=${d['fields_changed']}');
    if (d['field'] != null) {
      final old = d['is_sensitive'] == true ? '[REDACTED]' : d['old_value'];
      final neu = d['is_sensitive'] == true ? '[REDACTED]' : d['new_value'];
      parts.add('${d['field']}: $old → $neu');
    }
    if (d['sessions_revoked'] != null) parts.add('sessões=${d['sessions_revoked']}');
    return parts.join(' · ');
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _fmtDate(DateTime d) {
  final l = d.toLisboa();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
         '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _ago(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}min';
  if (diff.inHours < 24)   return '${diff.inHours}h';
  if (diff.inDays < 30)    return '${diff.inDays}d';
  return '${(diff.inDays / 30).floor()}m';
}
