import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../models/client_restaurant_profile.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — guest book partner-side.
///
/// Layout inspirado em SevenRooms guest book + OpenTable guest profiles.
/// 3 tabs (Todos / VIP / Bloqueados) + search por name/phone client-side.
class PartnerClientProfilesScreen extends StatefulWidget {
  const PartnerClientProfilesScreen({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

  @override
  State<PartnerClientProfilesScreen> createState() =>
      _PartnerClientProfilesScreenState();
}

class _PartnerClientProfilesScreenState
    extends State<PartnerClientProfilesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<ClientRestaurantProfile>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = context
          .read<PartnerReservasStore>()
          .fetchClientProfiles(widget.restaurantId);
    });
  }

  Future<void> _openEditor(ClientRestaurantProfile p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProfileEditorSheet(
        profile: p,
        onChanged: _refresh,
      ),
    );
  }

  String _relativeLastVisit(DateTime? lastVisit) {
    if (lastVisit == null) return 'Nunca visitou';
    final diff = DateTime.now().difference(lastVisit);
    if (diff.inDays == 0) return 'Hoje';
    if (diff.inDays == 1) return 'Ontem';
    if (diff.inDays < 7) return 'Há ${diff.inDays} dias';
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return 'Há $w ${w == 1 ? "semana" : "semanas"}';
    }
    if (diff.inDays < 365) {
      final m = (diff.inDays / 30).floor();
      return 'Há $m ${m == 1 ? "mês" : "meses"}';
    }
    final y = (diff.inDays / 365).floor();
    return 'Há $y ${y == 1 ? "ano" : "anos"}';
  }

  List<ClientRestaurantProfile> _filter(
      List<ClientRestaurantProfile> list, int tabIndex) {
    Iterable<ClientRestaurantProfile> base = list;
    switch (tabIndex) {
      case 1:
        base = base.where((p) => p.isVip);
        break;
      case 2:
        base = base.where((p) => p.isBlocked);
        break;
      default:
        break;
    }
    if (_query.isEmpty) return base.toList();
    final q = _query.toLowerCase();
    return base.where((p) {
      final name = (p.clientName ?? '').toLowerCase();
      final phone = (p.clientPhone ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text(
          'Clientes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tab,
          onTap: (_) => setState(() {}),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'VIP'),
            Tab(text: 'Bloqueados'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Procurar por nome ou telefone',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ClientRestaurantProfile>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            snap.error
                                .toString()
                                .replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refresh,
                            child: const Text('Tentar de novo'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final all = snap.data ?? const [];
                final list = _filter(all, _tab.index);
                if (list.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Sem perfis para mostrar.',
                              style:
                                  TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          onTap: () => _openEditor(p),
                          leading: CircleAvatar(
                            backgroundColor: p.isVip
                                ? const Color(0xFFD4AF37)
                                : AppColors.primary
                                    .withValues(alpha: 0.1),
                            child: Icon(
                              p.isBlocked
                                  ? Icons.block
                                  : (p.isVip ? Icons.star : Icons.person),
                              color:
                                  p.isVip ? Colors.white : AppColors.primary,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.clientName ?? 'Cliente',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (p.isVip)
                                const _SmallBadge(
                                  label: 'VIP',
                                  color: Color(0xFFD4AF37),
                                ),
                              if (p.isBlocked)
                                const _SmallBadge(
                                  label: 'Bloqueado',
                                  color: Colors.red,
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((p.clientPhone ?? '').isNotEmpty)
                                Text(
                                  p.clientPhone!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Text(
                                '${p.totalVisits} visitas • '
                                '${p.totalNoShows} no-shows • '
                                '${p.totalLateCancels} cancels',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                _relativeLastVisit(p.lastVisitAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _ProfileEditorSheet extends StatefulWidget {
  const _ProfileEditorSheet({
    required this.profile,
    required this.onChanged,
  });

  final ClientRestaurantProfile profile;
  final VoidCallback onChanged;

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late bool _isVip;
  late bool _isBlocked;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _isVip = widget.profile.isVip;
    _isBlocked = widget.profile.isBlocked;
    _notesCtrl = TextEditingController(text: widget.profile.partnerNotes ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleVip(bool v) async {
    setState(() => _isVip = v);
    try {
      await context
          .read<PartnerReservasStore>()
          .toggleVip(widget.profile.id, v);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVip = !v);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _toggleBlock(bool v) async {
    String? reason;
    if (v) {
      final ctrl = TextEditingController();
      final got = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Motivo do bloqueio'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Bloquear'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (got == null) {
        return;
      }
      reason = got.isEmpty ? null : got;
    }
    setState(() => _isBlocked = v);
    try {
      await context.read<PartnerReservasStore>().toggleBlock(
            profileId: widget.profile.id,
            isBlocked: v,
            reason: reason,
          );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBlocked = !v);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _saveNotes() async {
    final notes = _notesCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<PartnerReservasStore>().updatePartnerNotes(
            widget.profile.id,
            notes.isEmpty ? null : notes,
          );
      widget.onChanged();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Notas guardadas.')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.clientName ?? 'Cliente',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if ((p.clientPhone ?? '').isNotEmpty)
              Text(
                p.clientPhone!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VIP'),
              subtitle: const Text('Cliente preferencial'),
              value: _isVip,
              activeThumbColor: const Color(0xFFD4AF37),
              onChanged: _toggleVip,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bloqueado'),
              subtitle: Text(
                p.isBlocked && (p.blockedReason ?? '').isNotEmpty
                    ? 'Motivo: ${p.blockedReason}'
                    : 'Não pode fazer reservas',
              ),
              value: _isBlocked,
              activeThumbColor: Colors.red,
              onChanged: _toggleBlock,
            ),
            const SizedBox(height: 8),
            const Text(
              'Notas privadas',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Preferências, dietas, alergias...',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveNotes,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save),
                label: const Text('Guardar notas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
