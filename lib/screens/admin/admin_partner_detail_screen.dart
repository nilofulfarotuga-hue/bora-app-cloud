// T3 — Admin partner detail with tabs: Dados / Horários / Estado / Datas Especiais.
// Requires partner_hours_system migration (T4 of sessão nocturna 2026-04-29).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/restaurant_model.dart';
import '../../stores/restaurant_store.dart';
import '_admin_partner_edit_dialog.dart';

class AdminPartnerDetailScreen extends StatefulWidget {
  const AdminPartnerDetailScreen({
    super.key,
    required this.restaurantId,
    required this.initialName,
  });

  final String restaurantId;
  final String initialName;

  @override
  State<AdminPartnerDetailScreen> createState() =>
      _AdminPartnerDetailScreenState();
}

class _AdminPartnerDetailScreenState extends State<AdminPartnerDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  Map<String, dynamic>? _restaurant;
  Map<String, dynamic>? _openStatus; // result of is_partner_open()
  BusinessHours _hours = const BusinessHours();
  bool _savingHours = false;
  String? _heroImageUrl;
  bool _uploadingHero = false;
  String? _logoImageUrl;
  bool _uploadingLogo = false;

  static const _days = <({int weekday, String label, String key})>[
    (weekday: DateTime.monday,    label: 'Segunda-feira', key: 'mon'),
    (weekday: DateTime.tuesday,   label: 'Terça-feira',   key: 'tue'),
    (weekday: DateTime.wednesday, label: 'Quarta-feira',  key: 'wed'),
    (weekday: DateTime.thursday,  label: 'Quinta-feira',  key: 'thu'),
    (weekday: DateTime.friday,    label: 'Sexta-feira',   key: 'fri'),
    (weekday: DateTime.saturday,  label: 'Sábado',        key: 'sat'),
    (weekday: DateTime.sunday,    label: 'Domingo',       key: 'sun'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final restaurantData = await Supabase.instance.client
          .from('restaurants')
          .select(
              'id, name, category, address, phone, email, is_partner, is_online, is_active_admin, business_hours, '
              'takeaway_enabled, curbside_enabled, takeaway_default_prep_minutes, hero_image_url, photo_url')
          .eq('id', widget.restaurantId)
          .single();
      final openData = await Supabase.instance.client.rpc('is_partner_open', params: {
        'p_restaurant_id': widget.restaurantId,
        'p_at': DateTime.now().toUtc().toIso8601String(),
      });
      final results = [restaurantData, openData];
      if (mounted) {
        final r = Map<String, dynamic>.from(results[0] as Map);
        final bh = BusinessHours.fromJson(r['business_hours']);
        setState(() {
          _restaurant = r;
          _hours = bh;
          _heroImageUrl = r['hero_image_url'] as String?;
          _logoImageUrl = r['photo_url'] as String?;
          _openStatus = results[1] is Map
              ? Map<String, dynamic>.from(results[1] as Map)
              : {'is_open': results[1]};
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    }
  }

  // ─── Hero image upload (PT-BR) ────────────────────────────────────────────

  Future<void> _uploadHero() async {
    // Escolha da fonte: câmara ou galeria (PT-BR — admin).
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem muito grande (máx 10 MB).')),
      );
      return;
    }
    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formato inválido. Use JPEG, PNG ou WebP.')),
      );
      return;
    }
    setState(() => _uploadingHero = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final path = '$userId/hero/${widget.restaurantId}.$ext';
      await Supabase.instance.client.storage
          .from('restaurant-assets')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(
                  upsert: true, contentType: 'image/$ext'));
      final publicUrl = Supabase.instance.client.storage
          .from('restaurant-assets')
          .getPublicUrl(path);
      await Supabase.instance.client
          .from('restaurants')
          .update({'hero_image_url': publicUrl})
          .eq('id', widget.restaurantId);
      if (mounted) {
        setState(() => _heroImageUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem do banner enviada com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: $e')));
    } finally {
      if (mounted) setState(() => _uploadingHero = false);
    }
  }

  Future<void> _removeHero() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover banner?'),
        content: const Text('O banner do mercado será removido. Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'hero_image_url': null})
          .eq('id', widget.restaurantId);
      if (mounted) {
        setState(() => _heroImageUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem removida.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  // ─── Logo upload ──────────────────────────────────────────────────────────

  Future<void> _uploadLogo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem muito grande (máx 10 MB).')),
      );
      return;
    }
    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formato inválido. Use JPEG, PNG ou WebP.')),
      );
      return;
    }
    setState(() => _uploadingLogo = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final path = '$userId/logo/${widget.restaurantId}.$ext';
      await Supabase.instance.client.storage
          .from('restaurant-assets')
          .uploadBinary(path, bytes,
              fileOptions:
                  FileOptions(upsert: true, contentType: 'image/$ext'));
      final publicUrl = Supabase.instance.client.storage
          .from('restaurant-assets')
          .getPublicUrl(path);
      await Supabase.instance.client
          .from('restaurants')
          .update({'photo_url': publicUrl})
          .eq('id', widget.restaurantId);
      if (mounted) {
        setState(() => _logoImageUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo enviado com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar logo: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover logo?'),
        content: const Text('O logo do parceiro será removido. Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'photo_url': null})
          .eq('id', widget.restaurantId);
      if (mounted) {
        setState(() => _logoImageUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo removido.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
      }
    }
  }

  // ─── TAB 1 — DADOS ────────────────────────────────────────────────────────

  Widget _buildDadosTab() {
    if (_loading || _restaurant == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _restaurant!;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _infoRow(Icons.store, 'Nome', r['name'] as String? ?? '—'),
          _infoRow(Icons.category, 'Categoria', r['category'] as String? ?? '—'),
          _infoRow(Icons.location_on, 'Endereço', r['address'] as String? ?? '—'),
          _infoRow(Icons.phone, 'Telefone', r['phone'] as String? ?? '—'),
          _infoRow(Icons.email, 'Email', r['email'] as String? ?? '—'),
          _infoRow(Icons.handshake,
              r['is_partner'] == true ? 'Parceiro' : 'Não-parceiro', ''),
          _infoRow(Icons.toggle_on,
              r['is_active_admin'] != false ? 'Activo no admin' : 'DESACTIVADO', ''),
          const SizedBox(height: 24),
          // ── Banner do mercado (hero) ────────────────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.image_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Imagem do banner do mercado (hero)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Aparece no topo do mercado (estilo Glovo). JPEG, PNG ou WebP, máx 10 MB.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (_heroImageUrl != null && _heroImageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _heroImageUrl!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(height: 120,
                                child: Center(child: Icon(Icons.broken_image))),
                      ),
                    )
                  else
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Center(
                          child: Text('Sem banner configurado',
                              style: TextStyle(color: Colors.grey))),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploadingHero ? null : _uploadHero,
                        icon: _uploadingHero
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload),
                        label: Text(_heroImageUrl != null ? 'Trocar imagem' : 'Enviar imagem'),
                      ),
                    ),
                    if (_heroImageUrl != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _uploadingHero ? null : _removeHero,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Remover',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── Logo do parceiro (photo_url) ────────────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.store_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Logo do parceiro',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Aparece na listagem de restaurantes. JPEG, PNG ou WebP, máx 10 MB.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (_logoImageUrl != null && _logoImageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _logoImageUrl!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            height: 120,
                            child: Center(child: Icon(Icons.broken_image))),
                      ),
                    )
                  else
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Center(
                          child: Text('Sem logo configurado',
                              style: TextStyle(color: Colors.grey))),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _uploadLogo,
                        icon: _uploadingLogo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.upload),
                        label: Text(_logoImageUrl != null
                            ? 'Trocar logo'
                            : 'Enviar logo'),
                      ),
                    ),
                    if (_logoImageUrl != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _removeLogo,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        label: const Text('Remover',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final res = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => AdminPartnerEditDialog(
                  restaurantId: widget.restaurantId,
                  initialName: r['name'] as String? ?? '',
                  initialAddress: r['address'] as String? ?? '',
                  initialCategory: r['category'] as String? ?? 'restaurant',
                  initialPhone: r['phone'] as String? ?? '',
                ),
              );
              if (res != null && res['success'] == true) _loadAll();
            },
            icon: const Icon(Icons.edit),
            label: const Text('Editar dados'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (value.isNotEmpty)
              Text(value, style: const TextStyle(fontSize: 15)),
          ]),
        ),
      ]),
    );
  }

  // ─── TAB 2 — HORÁRIOS ─────────────────────────────────────────────────────

  void _updateDay(int weekday, DayHours day) {
    setState(() => _hours = _hours.copyWithDay(weekday, day));
  }

  Future<void> _pickTime(int weekday, bool isOpen) async {
    final current = _hours.dayFor(weekday);
    final raw = isOpen ? current.open : current.close;
    final parts = raw.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    final formatted = '$h:$m';
    _updateDay(weekday,
        isOpen ? current.copyWith(open: formatted) : current.copyWith(close: formatted));
  }

  Future<void> _saveHours() async {
    setState(() => _savingHours = true);
    try {
      final store = context.read<RestaurantStore>();
      await store.adminUpdatePartnerHours(
        restaurantId: widget.restaurantId,
        hours: _hours,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horário guardado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingHours = false);
    }
  }

  Widget _buildHorariosTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._days.map((d) {
          final dh = _hours.dayFor(d.weekday);
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(d.label,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
                  Switch(
                    value: !dh.closed,
                    onChanged: (v) =>
                        _updateDay(d.weekday, dh.copyWith(closed: !v)),
                  ),
                  Text(dh.closed ? 'Fechado' : 'Aberto',
                      style: TextStyle(
                          color: dh.closed ? Colors.grey : AppColors.primary,
                          fontSize: 13)),
                ]),
                if (!dh.closed)
                  Row(children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text('Abre: ${dh.open}'),
                        onPressed: () => _pickTime(d.weekday, true),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.access_time_filled, size: 18),
                        label: Text('Fecha: ${dh.close}'),
                        onPressed: () => _pickTime(d.weekday, false),
                      ),
                    ),
                  ]),
              ]),
            ),
          );
        }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _savingHours ? null : _saveHours,
          icon: _savingHours
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Salvar horários'),
        ),
      ],
    );
  }

  // ─── TAB 3 — ESTADO ───────────────────────────────────────────────────────

  Widget _buildEstadoTab() {
    if (_openStatus == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isOpen = _openStatus!['is_open'] == true;
    final overrideActive = _openStatus!['override_active'] == true;
    final overrideReason = _openStatus!['override_reason'] as String?;
    final overrideEndsAt = _openStatus!['override_ends_at'] as String?;

    Color badgeColor;
    String badgeLabel;
    IconData badgeIcon;

    if (overrideActive) {
      badgeColor = isOpen ? Colors.green.shade700 : Colors.red.shade700;
      badgeLabel = isOpen ? 'ABERTO (forçado)' : 'FECHADO (forçado)';
      badgeIcon = Icons.admin_panel_settings;
    } else {
      badgeColor = isOpen ? Colors.green : Colors.orange;
      badgeLabel = isOpen ? 'ABERTO (horário)' : 'FECHADO (horário)';
      badgeIcon = isOpen ? Icons.check_circle : Icons.cancel;
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(badgeIcon, color: badgeColor, size: 60),
                const SizedBox(height: 12),
                Text(badgeLabel,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: badgeColor)),
                if (overrideReason != null) ...[
                  const SizedBox(height: 8),
                  Text('Motivo: $overrideReason',
                      style: const TextStyle(color: Colors.grey)),
                ],
                if (overrideEndsAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Até: ${overrideEndsAt.substring(0, 16)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (overrideActive)
            OutlinedButton.icon(
              onPressed: _clearOverride,
              icon: const Icon(Icons.clear, color: Colors.orange),
              label: const Text('Limpar override → voltar a horário regular'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            )
          else ...[
            FilledButton.icon(
              onPressed: () => _setOverride('closed'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.lock),
              label: const Text('Forçar FECHAR'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _setOverride('open'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.lock_open),
              label: const Text('Forçar ABRIR'),
            ),
          ],
          const SizedBox(height: 24),
          _AdminTakeawayConfigCard(
            takeawayEnabled:
                _restaurant?['takeaway_enabled'] as bool? ?? false,
            curbsideEnabled:
                _restaurant?['curbside_enabled'] as bool? ?? false,
            prepMinutes:
                (_restaurant?['takeaway_default_prep_minutes'] as num?)
                        ?.toInt() ??
                    15,
            onToggleTakeaway: (v) => _setAdminTakeawayEnabled(v),
            onToggleCurbside: (v) => _setAdminCurbsideEnabled(v),
            onPrepMinutesChanged: (m) => _setAdminPrepMinutes(m),
          ),
        ],
      ),
    );
  }

  // ─── Takeaway admin actions (PROMPT C, PT-BR) ───────────────────────────
  Future<void> _setAdminTakeawayEnabled(bool enabled) async {
    try {
      final updates = <String, dynamic>{'takeaway_enabled': enabled};
      // Desabilitar curbside automaticamente quando takeaway é desabilitado
      // (estado consistente — mesmo comportamento do painel do parceiro).
      if (!enabled) updates['curbside_enabled'] = false;
      await Supabase.instance.client
          .from('restaurants')
          .update(updates)
          .eq('id', widget.restaurantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(enabled
              ? 'Takeaway habilitado'
              : 'Takeaway desabilitado'),
        ));
      }
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _setAdminCurbsideEnabled(bool enabled) async {
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'curbside_enabled': enabled}).eq(
              'id', widget.restaurantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(enabled
              ? 'Curbside habilitado'
              : 'Curbside desabilitado'),
        ));
      }
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _setAdminPrepMinutes(int minutes) async {
    final clamped = minutes.clamp(3, 60);
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'takeaway_default_prep_minutes': clamped}).eq(
              'id', widget.restaurantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Preparo padrão: $clamped min'),
        ));
      }
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _setOverride(String state) async {
    final reasonCtrl = TextEditingController();
    DateTime? endsAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(state == 'closed' ? 'Forçar fechar' : 'Forçar abrir'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: reasonCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Motivo (mín 3)')),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(endsAt == null
                  ? 'Sem limite (permanente)'
                  : 'Até ${endsAt.toString().substring(0, 10)}'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().add(const Duration(minutes: 5)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: DateTime.now().add(const Duration(hours: 2)),
                );
                if (picked != null) setSt(() => endsAt = picked);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      final store = context.read<RestaurantStore>();
      await store.adminSetPartnerOverride(
        restaurantId: widget.restaurantId,
        state: state,
        reason: reasonCtrl.text.trim(),
        endsAt: endsAt,
      );
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _clearOverride() async {
    try {
      final store = context.read<RestaurantStore>();
      await store.adminClearPartnerOverride(widget.restaurantId);
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // ─── TAB 4 — DATAS ESPECIAIS ──────────────────────────────────────────────

  List<Map<String, dynamic>> _getSpecialDates() {
    if (_restaurant == null) return [];
    final bh = _restaurant!['business_hours'];
    if (bh is! Map) return [];
    final sd = bh['special_dates'];
    if (sd is! List) return [];
    return sd.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Widget _buildDatasEspeciaisTab() {
    final dates = _getSpecialDates();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Expanded(child: Text('Datas especiais (feriados/eventos)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppColors.primary),
              onPressed: _addSpecialDate,
              tooltip: 'Adicionar data',
            ),
          ]),
          const Divider(),
          if (dates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma data especial configurada.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...dates.map((d) {
              final closed = d['closed'] == true;
              return Card(
                child: ListTile(
                  leading: Icon(closed ? Icons.event_busy : Icons.event_available,
                      color: closed ? Colors.red : Colors.green),
                  title: Text(d['date'] as String? ?? '—'),
                  subtitle: Text(closed
                      ? 'Fechado — ${d['reason'] ?? ''}'
                      : '${d['open'] ?? '?'} – ${d['close'] ?? '?'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeSpecialDate(d['date'] as String),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _addSpecialDate() async {
    DateTime? date;
    bool closed = true;
    final openCtrl = TextEditingController(text: '09:00');
    final closeCtrl = TextEditingController(text: '13:00');
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Adicionar data especial'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(date == null
                    ? 'Seleccionar data'
                    : date.toString().substring(0, 10)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                    initialDate: DateTime.now(),
                  );
                  if (picked != null) setSt(() => date = picked);
                },
              ),
              SwitchListTile(
                title: const Text('Fechado neste dia'),
                value: closed,
                onChanged: (v) => setSt(() => closed = v),
              ),
              if (!closed) ...[
                TextField(controller: openCtrl,
                    decoration: const InputDecoration(labelText: 'Abre (HH:MM)')),
                TextField(controller: closeCtrl,
                    decoration: const InputDecoration(labelText: 'Fecha (HH:MM)')),
              ],
              TextField(controller: reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Motivo (ex: Natal, Feriado)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || date == null || !mounted) return;
    try {
      final dayHours = closed
          ? {'closed': true, 'reason': reasonCtrl.text}
          : {'closed': false, 'open': openCtrl.text, 'close': closeCtrl.text,
             'reason': reasonCtrl.text};
      final store = context.read<RestaurantStore>();
      await store.adminSetPartnerSpecialDate(
        restaurantId: widget.restaurantId,
        date: date!,
        dayHours: dayHours,
      );
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _removeSpecialDate(String dateStr) async {
    // Remove by setting closed=false with no hours (effectively a no-op date)
    // or just update business_hours without that date.
    try {
      final bh = Map<String, dynamic>.from(_restaurant?['business_hours'] as Map? ?? {});
      final sd = (bh['special_dates'] as List? ?? [])
          .where((e) => (e as Map)['date'] != dateStr)
          .toList();
      bh['special_dates'] = sd;
      await Supabase.instance.client
          .from('restaurants')
          .update({'business_hours': bh})
          .eq('id', widget.restaurantId);
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _restaurant?['name'] as String? ?? widget.initialName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Dados'),
            Tab(icon: Icon(Icons.schedule), text: 'Horários'),
            Tab(icon: Icon(Icons.toggle_on), text: 'Estado'),
            Tab(icon: Icon(Icons.date_range), text: 'Datas'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Vendas'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Catálogo'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildDadosTab(),
                _buildHorariosTab(),
                _buildEstadoTab(),
                _buildDatasEspeciaisTab(),
                _PartnerSalesTab(partnerId: widget.restaurantId),
                _PartnerCatalogTab(partnerId: widget.restaurantId),
              ],
            ),
    );
  }
}

// ─── TAB 5 — VENDAS (B2) ────────────────────────────────────────────────────

class _PartnerSalesTab extends StatefulWidget {
  const _PartnerSalesTab({required this.partnerId});
  final String partnerId;
  @override
  State<_PartnerSalesTab> createState() => _PartnerSalesTabState();
}

class _PartnerSalesTabState extends State<_PartnerSalesTab> {
  int _periodDays = 30;
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;

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
      final from = DateTime.now()
          .subtract(Duration(days: _periodDays))
          .toUtc()
          .toIso8601String();
      final to = DateTime.now().toUtc().toIso8601String();
      final res = await Supabase.instance.client.rpc(
        'admin_partner_sales_summary',
        params: {
          'p_partner_id': widget.partnerId,
          'p_from': from,
          'p_to': to,
        },
      );
      if (!mounted) return;
      setState(() {
        _data = (res as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 dias')),
              ButtonSegment(value: 30, label: Text('30 dias')),
              ButtonSegment(value: 90, label: Text('90 dias')),
            ],
            selected: {_periodDays},
            onSelectionChanged: (s) {
              setState(() => _periodDays = s.first);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
              ),
            )
          else if (_data != null) ..._buildSummary(_data!),
        ],
      ),
    );
  }

  List<Widget> _buildSummary(Map<String, dynamic> d) {
    final totalOrders = (d['total_orders'] as num?)?.toInt() ?? 0;
    final gross = (d['gross_revenue'] as num?)?.toDouble() ?? 0;
    final visible = (d['commission_visible_10'] as num?)?.toDouble() ?? 0;
    final hidden = (d['commission_markup_hidden_5'] as num?)?.toDouble() ?? 0;
    final service = (d['commission_service_fee_5'] as num?)?.toDouble() ?? 0;
    final commTotal = (d['commission_total_20'] as num?)?.toDouble() ?? 0;
    final partnerNet = (d['partner_net'] as num?)?.toDouble() ?? 0;
    final orders = (d['orders'] as List?) ?? const [];

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resumo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _row('Pedidos entregues', '$totalOrders'),
              _row('Total faturado', '€${gross.toStringAsFixed(2)}'),
              const Divider(),
              _row('Comissão Bora 10%', '€${visible.toStringAsFixed(2)}'),
              _row('Markup oculto 5%', '€${hidden.toStringAsFixed(2)}'),
              _row('Taxa serviço cliente 5%',
                  '€${service.toStringAsFixed(2)}'),
              const Divider(),
              _row('Total comissão (20%)',
                  '€${commTotal.toStringAsFixed(2)}', bold: true),
              _row('Líquido parceiro',
                  '€${partnerNet.toStringAsFixed(2)}',
                  bold: true, color: Colors.green),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Pedidos recentes',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      if (orders.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sem pedidos no período.',
              style: TextStyle(color: Colors.black54)),
        ),
      ...orders.map((e) {
        final o = (e as Map).cast<String, dynamic>();
        final created = DateTime.tryParse((o['created_at'] ?? '') as String);
        final dateStr = created != null
            ? '${created.year}-${created.month.toString().padLeft(2, '0')}-'
                '${created.day.toString().padLeft(2, '0')}'
            : '—';
        return Card(
          child: ListTile(
            dense: true,
            title: Text('#${(o['id'] as String).substring(0, 6)} · '
                '${o['customer_name'] ?? '—'}'),
            subtitle: Text('$dateStr · ${o['service_type']}'),
            trailing: Text(
                '€${((o['price'] as num?) ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      }),
    ];
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ─── TAB 6 — CATÁLOGO (B2) ──────────────────────────────────────────────────

class _PartnerCatalogTab extends StatefulWidget {
  const _PartnerCatalogTab({required this.partnerId});
  final String partnerId;
  @override
  State<_PartnerCatalogTab> createState() => _PartnerCatalogTabState();
}

class _PartnerCatalogTabState extends State<_PartnerCatalogTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = const [];

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
      final res = await Supabase.instance.client.rpc(
        'admin_list_products_by_partner',
        params: {
          'p_restaurant_id': widget.partnerId,
          'p_limit': 200,
          'p_offset': 0,
        },
      );
      if (!mounted) return;
      setState(() {
        _products = (res as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleAvailability(
      String productId, bool currentlyAvailable) async {
    try {
      await Supabase.instance.client.rpc('admin_set_product_availability',
          params: {
            'p_product_id': productId,
            'p_available': !currentlyAvailable,
          });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alternar disponibilidade: $e')));
    }
  }

  Future<void> _togglePopular(String productId, bool currentlyPopular) async {
    try {
      await Supabase.instance.client
          .from('products')
          .update({'is_popular': !currentlyPopular})
          .eq('id', productId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!currentlyPopular
              ? 'Marcado como popular'
              : 'Removido dos populares'),
          duration: const Duration(milliseconds: 1200),
        ));
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _editPrice(String productId, double current) async {
    final controller =
        TextEditingController(text: current.toStringAsFixed(2));
    final newPrice = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar preço'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '€ '),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(
                  controller.text.replaceAll(',', '.'));
              if (v != null && v >= 0) Navigator.pop(ctx, v);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (newPrice == null) return;
    try {
      await Supabase.instance.client.rpc('admin_update_product_price',
          params: {
            'p_product_id': productId,
            'p_new_price': newPrice,
          });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao salvar preço: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Erro: $_error',
                          style:
                              const TextStyle(color: Colors.red)),
                    ),
                  ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: _products.length,
                  itemBuilder: (_, i) {
                    final p = _products[i];
                    final id = p['id'] as String;
                    final available =
                        (p['is_available'] as bool?) ?? true;
                    final price =
                        ((p['price'] as num?) ?? 0).toDouble();
                    final popular =
                        (p['is_popular'] as bool?) ?? false;
                    return Card(
                      child: ListTile(
                        title: Text(p['name'] as String? ?? '—'),
                        subtitle: Text(
                            'Categoria: ${p['category'] ?? '—'}'),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _editPrice(id, price),
                                  child: Text(
                                      '€${price.toStringAsFixed(2)}'),
                                ),
                                Switch(
                                  value: available,
                                  onChanged: (_) =>
                                      _toggleAvailability(id, available),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Popular',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey)),
                                Switch(
                                  value: popular,
                                  activeThumbColor: const Color(0xFFFFB300),
                                  onChanged: (_) =>
                                      _togglePopular(id, popular),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// PROMPT C (2026-05-14) — Card de configurações Takeaway para o admin.
/// PT-BR (regra 21). 3 controles: switch master, switch curbside (so
/// editavel se master ON), input numerico preparo padrão (3-60 min).
class _AdminTakeawayConfigCard extends StatefulWidget {
  const _AdminTakeawayConfigCard({
    required this.takeawayEnabled,
    required this.curbsideEnabled,
    required this.prepMinutes,
    required this.onToggleTakeaway,
    required this.onToggleCurbside,
    required this.onPrepMinutesChanged,
  });

  final bool takeawayEnabled;
  final bool curbsideEnabled;
  final int prepMinutes;
  final ValueChanged<bool> onToggleTakeaway;
  final ValueChanged<bool> onToggleCurbside;
  final ValueChanged<int> onPrepMinutesChanged;

  @override
  State<_AdminTakeawayConfigCard> createState() =>
      _AdminTakeawayConfigCardState();
}

class _AdminTakeawayConfigCardState extends State<_AdminTakeawayConfigCard> {
  late TextEditingController _prepController;

  @override
  void initState() {
    super.initState();
    _prepController =
        TextEditingController(text: widget.prepMinutes.toString());
  }

  @override
  void didUpdateWidget(covariant _AdminTakeawayConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.prepMinutes.toString();
    if (_prepController.text != newText) {
      _prepController.text = newText;
    }
  }

  @override
  void dispose() {
    _prepController.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_prepController.text.trim());
    if (parsed == null) {
      _prepController.text = widget.prepMinutes.toString();
      return;
    }
    final clamped = parsed.clamp(3, 60);
    widget.onPrepMinutesChanged(clamped);
    if (clamped != parsed) _prepController.text = clamped.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(Icons.shopping_bag_outlined),
                SizedBox(width: 8),
                Text(
                  'Configurações de Takeaway',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SwitchListTile.adaptive(
            value: widget.takeawayEnabled,
            onChanged: widget.onToggleTakeaway,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: const Text(
              'Takeaway habilitado',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Permite pedidos para levantamento (cliente vê botão "Ir buscar").',
              style: TextStyle(fontSize: 12),
            ),
            activeColor: const Color(0xFF1B5E20),
          ),
          if (widget.takeawayEnabled) ...[
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: widget.curbsideEnabled,
              onChanged: widget.onToggleCurbside,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text(
                'Curbside habilitado',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Atendimento no carro (cliente informa matrícula).',
                style: TextStyle(fontSize: 12),
              ),
              activeColor: const Color(0xFFE65100),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tempo de preparo padrão (minutos)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '3-60 min. Aparece pré-selecionado ao parceiro aceitar.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 76,
                    child: TextField(
                      controller: _prepController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _commit(),
                      onEditingComplete: _commit,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        suffixText: 'min',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
