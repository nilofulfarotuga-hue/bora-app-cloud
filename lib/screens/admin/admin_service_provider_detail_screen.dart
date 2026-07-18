// Admin — Detalhe / gestão TOTAL do prestador de serviços (vertical Serviços /
// Beleza). Espelha `admin_partner_detail_screen.dart` (restaurantes) mas para a
// tabela `service_providers` + `provider_services`. PT-BR.
//
// Abas: Dados (editar + logo + capa) · Horários · Serviços & Preços · Estado.
//
// Reutiliza:
//  - `BusinessHours`/`DayHours` (models/restaurant_model.dart) para os horários.
//  - Edge Function `upload-restaurant-asset` (não é exclusiva de restaurantes —
//    só usa o id como prefixo da pasta) para logo (kind='logo' → photo_url) e
//    capa (kind='hero' → hero_image_url).
//  - `SafeImagePicker` para escolher a imagem.
//
// RLS confirmada (2026-07-18): sp_update/sp_delete/sp_insert e ps_write
// permitem is_admin() → UPDATE/DELETE directo funciona para o admin.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/restaurant_model.dart' show BusinessHours, DayHours;
import '../../utils/safe_image_picker.dart';
import '../../widgets/bora/bora_primary_button.dart';

class AdminServiceProviderDetailScreen extends StatefulWidget {
  const AdminServiceProviderDetailScreen({
    super.key,
    required this.providerId,
    required this.initialName,
  });

  final String providerId;
  final String initialName;

  @override
  State<AdminServiceProviderDetailScreen> createState() =>
      _AdminServiceProviderDetailScreenState();
}

class _AdminServiceProviderDetailScreenState
    extends State<AdminServiceProviderDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  late final TabController _tab;
  bool _loading = true;
  Map<String, dynamic>? _provider;

  // Dados (editáveis)
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'barbershop';
  bool _savingDados = false;

  // Imagens
  String? _logoUrl;
  String? _heroUrl;
  bool _uploadingLogo = false;
  bool _uploadingHero = false;

  // Horários
  BusinessHours _hours = const BusinessHours();
  bool _savingHours = false;

  // Serviços
  List<Map<String, dynamic>> _services = const [];
  bool _servicesLoading = true;

  // Estado
  bool _deleting = false;

  /// Rótulos PT-BR das categorias da vertical Serviços/Beleza. Só `barbershop`
  /// tem efeito de terminologia (Barbeiro vs Profissional); as restantes são
  /// puramente descritivas.
  static const _categoryLabels = <String, String>{
    'barbershop': 'Barbearia',
    'beauty': 'Salão de Beleza',
    'hair': 'Cabeleireiro',
    'nails': 'Manicure / Unhas',
    'esthetics': 'Estética',
    'spa': 'Spa / Bem-estar',
    'tattoo': 'Tatuagem / Piercing',
    'other': 'Outro',
  };

  static const _days = <({int weekday, String label, String key})>[
    (weekday: DateTime.monday, label: 'Segunda-feira', key: 'mon'),
    (weekday: DateTime.tuesday, label: 'Terça-feira', key: 'tue'),
    (weekday: DateTime.wednesday, label: 'Quarta-feira', key: 'wed'),
    (weekday: DateTime.thursday, label: 'Quinta-feira', key: 'thu'),
    (weekday: DateTime.friday, label: 'Sexta-feira', key: 'fri'),
    (weekday: DateTime.saturday, label: 'Sábado', key: 'sat'),
    (weekday: DateTime.sunday, label: 'Domingo', key: 'sun'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ─── LOAD ───────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final row = await _supabase
          .from('service_providers')
          .select()
          .eq('id', widget.providerId)
          .single();
      final r = Map<String, dynamic>.from(row as Map);
      if (!mounted) return;
      setState(() {
        _provider = r;
        _nameCtrl.text = r['name'] as String? ?? '';
        _addressCtrl.text = r['address'] as String? ?? '';
        _phoneCtrl.text = r['phone'] as String? ?? '';
        _descCtrl.text = r['description'] as String? ?? '';
        _category = (r['category'] as String?)?.trim().isNotEmpty == true
            ? r['category'] as String
            : 'barbershop';
        _logoUrl = r['photo_url'] as String?;
        _heroUrl = r['hero_image_url'] as String?;
        _hours = BusinessHours.fromJson(r['business_hours']);
        _loading = false;
      });
      await _loadServices();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Erro ao carregar: $e');
    }
  }

  Future<void> _loadServices() async {
    setState(() => _servicesLoading = true);
    try {
      // Admin vê TODOS os serviços (activos e inactivos).
      final res = await _supabase
          .from('provider_services')
          .select()
          .eq('provider_id', widget.providerId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _services = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _servicesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _servicesLoading = false);
      _toast('Erro ao carregar serviços: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── DADOS ──────────────────────────────────────────────────────────────────

  Future<void> _saveDados() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('O nome não pode ficar vazio.');
      return;
    }
    setState(() => _savingDados = true);
    try {
      await _supabase.from('service_providers').update({
        'name': name,
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
      }).eq('id', widget.providerId);
      _toast('Dados guardados.');
      await _loadAll();
    } catch (e) {
      _toast('Erro ao guardar: $e');
    } finally {
      if (mounted) setState(() => _savingDados = false);
    }
  }

  List<DropdownMenuItem<String>> _categoryItems() {
    final keys = <String>{..._categoryLabels.keys};
    if (_category.trim().isNotEmpty) keys.add(_category);
    return keys
        .map((c) => DropdownMenuItem(
              value: c,
              child: Text(_categoryLabels[c] ?? c),
            ))
        .toList();
  }

  Widget _buildDadosTab() {
    if (_loading || _provider == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          _sectionCard(
            icon: Icons.badge_outlined,
            title: 'Dados do prestador',
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Endereço (morada)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  border: OutlineInputBorder(),
                ),
                items: _categoryItems(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Guardar dados',
                icon: Icons.save,
                loading: _savingDados,
                onPressed: _savingDados ? null : _saveDados,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _imageCard(
            title: 'Logo do prestador',
            subtitle:
                'Aparece na listagem de prestadores. JPEG, PNG ou WebP, máx 10 MB.',
            url: _logoUrl,
            uploading: _uploadingLogo,
            onUpload: () => _pickAndUpload('logo'),
            onRemove: () => _removeImage('logo'),
          ),
          const SizedBox(height: Spacing.md),
          _imageCard(
            title: 'Capa (banner)',
            subtitle:
                'Aparece no topo do perfil do prestador. JPEG, PNG ou WebP, máx 10 MB.',
            url: _heroUrl,
            uploading: _uploadingHero,
            onUpload: () => _pickAndUpload('hero'),
            onRemove: () => _removeImage('hero'),
          ),
        ],
      ),
    );
  }

  // ─── IMAGENS (logo / capa) via Edge Function upload-restaurant-asset ─────────

  Future<void> _pickAndUpload(String kind) async {
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
    final file = await SafeImagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _toast('Imagem muito grande (máx 10 MB).');
      return;
    }
    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      _toast('Formato inválido. Use JPEG, PNG ou WebP.');
      return;
    }
    final isLogo = kind == 'logo';
    setState(() {
      if (isLogo) {
        _uploadingLogo = true;
      } else {
        _uploadingHero = true;
      }
    });
    try {
      // A Edge Function usa `restaurantId` apenas como prefixo da pasta no
      // bucket público `restaurant-assets` — reutilizada tal como está para
      // prestadores de serviços (passamos o id do prestador).
      final response = await _supabase.functions.invoke(
        'upload-restaurant-asset',
        body: {
          'restaurantId': widget.providerId,
          'kind': kind,
          'fileBase64': base64Encode(bytes),
          'contentType': 'image/$ext',
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw Exception(
            'upload-restaurant-asset HTTP ${response.status}: ${response.data}');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) {
        throw Exception('Upload falhou: ${data['error'] ?? 'desconhecido'}');
      }
      final publicUrl = data['public_url'] as String;
      final column = isLogo ? 'photo_url' : 'hero_image_url';
      await _supabase
          .from('service_providers')
          .update({column: publicUrl}).eq('id', widget.providerId);
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          _logoUrl = publicUrl;
        } else {
          _heroUrl = publicUrl;
        }
      });
      _toast(isLogo ? 'Logo enviado com sucesso.' : 'Capa enviada com sucesso.');
    } catch (e) {
      _toast('Erro ao enviar imagem: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isLogo) {
            _uploadingLogo = false;
          } else {
            _uploadingHero = false;
          }
        });
      }
    }
  }

  Future<void> _removeImage(String kind) async {
    final isLogo = kind == 'logo';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isLogo ? 'Remover logo?' : 'Remover capa?'),
        content: Text(isLogo
            ? 'O logo do prestador será removido. Continuar?'
            : 'A capa do prestador será removida. Continuar?'),
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
      final column = isLogo ? 'photo_url' : 'hero_image_url';
      await _supabase
          .from('service_providers')
          .update({column: null}).eq('id', widget.providerId);
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          _logoUrl = null;
        } else {
          _heroUrl = null;
        }
      });
      _toast(isLogo ? 'Logo removido.' : 'Capa removida.');
    } catch (e) {
      _toast('Erro ao remover: $e');
    }
  }

  // ─── HORÁRIOS ───────────────────────────────────────────────────────────────

  void _updateDay(int weekday, DayHours day) {
    setState(() => _hours = _hours.copyWithDay(weekday, day));
  }

  Future<void> _pickTime(int weekday, bool isOpen) async {
    final current = _hours.dayFor(weekday);
    final raw = isOpen ? current.open : current.close;
    final parts = raw.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0)
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
    _updateDay(
      weekday,
      isOpen
          ? current.copyWith(open: formatted)
          : current.copyWith(close: formatted),
    );
  }

  Future<void> _saveHours() async {
    setState(() => _savingHours = true);
    try {
      await _supabase
          .from('service_providers')
          .update({'business_hours': _hours.toJson()}).eq(
              'id', widget.providerId);
      _toast('Horário guardado.');
    } catch (e) {
      _toast('Erro ao guardar horário: $e');
    } finally {
      if (mounted) setState(() => _savingHours = false);
    }
  }

  Widget _buildHorariosTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        ..._days.map((d) {
          final dh = _hours.dayFor(d.weekday);
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.xs),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text(d.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
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
        const SizedBox(height: Spacing.md),
        BoraPrimaryButton(
          label: 'Salvar horários',
          icon: Icons.save,
          loading: _savingHours,
          onPressed: _savingHours ? null : _saveHours,
        ),
      ],
    );
  }

  // ─── SERVIÇOS & PREÇOS ──────────────────────────────────────────────────────

  Future<void> _serviceDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] as String? ?? '');
    final durationCtrl = TextEditingController(
        text: ((existing?['duration_minutes'] as num?)?.toInt() ?? 30)
            .toString());
    final priceCtrl = TextEditingController(
        text: existing != null
            ? (((existing['price_cents'] as num?) ?? 0) / 100)
                .toStringAsFixed(2)
            : '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Adicionar serviço' : 'Editar serviço'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome do serviço',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Obrigatório'
                        : null,
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duração (minutos)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'Minutos > 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Preço (€)',
                      hintText: 'Ex: 12.50',
                      prefixText: '€ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final p =
                          double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                      if (p == null || p <= 0) return 'Preço > 0';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setSt(() => saving = true);
                      final priceCents = (double.parse(
                                  priceCtrl.text.trim().replaceAll(',', '.')) *
                              100)
                          .round();
                      final durationMinutes =
                          int.parse(durationCtrl.text.trim());
                      try {
                        if (existing == null) {
                          // sort_order = fim da lista.
                          final nextOrder = _services.isEmpty
                              ? 0
                              : ((_services.last['sort_order'] as num?)
                                          ?.toInt() ??
                                      _services.length - 1) +
                                  1;
                          await _supabase.from('provider_services').insert({
                            'provider_id': widget.providerId,
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'duration_minutes': durationMinutes,
                            'price_cents': priceCents,
                            'is_active': true,
                            'sort_order': nextOrder,
                          });
                        } else {
                          await _supabase.from('provider_services').update({
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'duration_minutes': durationMinutes,
                            'price_cents': priceCents,
                          }).eq('id', existing['id']);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _toast(existing == null
                            ? 'Serviço adicionado.'
                            : 'Serviço actualizado.');
                        await _loadServices();
                      } catch (e) {
                        setSt(() => saving = false);
                        _toast('Erro ao guardar serviço: $e');
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
    durationCtrl.dispose();
    priceCtrl.dispose();
  }

  Future<void> _toggleServiceActive(Map<String, dynamic> s) async {
    final current = (s['is_active'] as bool?) ?? true;
    try {
      await _supabase
          .from('provider_services')
          .update({'is_active': !current}).eq('id', s['id']);
      _toast(!current ? 'Serviço activado.' : 'Serviço desactivado.');
      await _loadServices();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _deleteService(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar serviço'),
        content: Text('Apagar "${s['name']}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // `appointments.service_id` → provider_services (NO ACTION): se houver
      // marcações associadas, o DELETE falha. Verificamos antes e, nesse caso,
      // desactivamos (mantém o histórico) em vez de apagar.
      final linked = await _supabase
          .from('appointments')
          .select('id')
          .eq('service_id', s['id'])
          .limit(1);
      if ((linked as List).isNotEmpty) {
        await _supabase
            .from('provider_services')
            .update({'is_active': false}).eq('id', s['id']);
        _toast(
            'Serviço tem marcações no histórico — foi DESACTIVADO em vez de apagado.');
        await _loadServices();
        return;
      }
      await _supabase.from('provider_services').delete().eq('id', s['id']);
      _toast('Serviço apagado.');
      await _loadServices();
    } catch (e) {
      _toast('Erro ao apagar serviço: $e');
    }
  }

  Future<void> _moveService(int index, int delta) async {
    final j = index + delta;
    if (j < 0 || j >= _services.length) return;
    final list = [..._services];
    final tmp = list[index];
    list[index] = list[j];
    list[j] = tmp;
    setState(() => _services = list);
    try {
      // Reatribui sort_order sequencial (robusto mesmo se todos estavam a 0).
      for (var i = 0; i < list.length; i++) {
        await _supabase
            .from('provider_services')
            .update({'sort_order': i}).eq('id', list[i]['id']);
      }
      await _loadServices();
    } catch (e) {
      _toast('Erro ao reordenar: $e');
      await _loadServices();
    }
  }

  Widget _buildServicosTab() {
    if (_servicesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadServices,
            child: _services.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(Spacing.xxxl),
                        child: Center(
                            child: Text('Nenhum serviço cadastrado.',
                                style:
                                    TextStyle(color: AppColors.textSecondary))),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: _services.length,
                    itemBuilder: (ctx, i) => _serviceRow(_services[i], i),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: BoraPrimaryButton(
              label: 'Adicionar serviço',
              icon: Icons.add,
              onPressed: () => _serviceDialog(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _serviceRow(Map<String, dynamic> s, int index) {
    final active = (s['is_active'] as bool?) ?? true;
    final priceEur = ((s['price_cents'] as num?) ?? 0) / 100;
    final duration = (s['duration_minutes'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s['name'] as String? ?? '(sem nome)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: active ? null : AppColors.textSecondary,
                      decoration:
                          active ? null : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                Text('€${priceEur.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 2),
            Text('$duration min${active ? '' : ' · inactivo'}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            if ((s['description'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(s['description'] as String,
                  style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Subir',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: index == 0 ? null : () => _moveService(index, -1),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Descer',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: index == _services.length - 1
                      ? null
                      : () => _moveService(index, 1),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: Icon(active ? Icons.toggle_on : Icons.toggle_off_outlined,
                      size: 18),
                  label: Text(active ? 'Desactivar' : 'Activar'),
                  style: TextButton.styleFrom(
                      foregroundColor:
                          active ? AppColors.warning : AppColors.success),
                  onPressed: () => _toggleServiceActive(s),
                ),
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit, size: 18, color: AppColors.info),
                  onPressed: () => _serviceDialog(existing: s),
                ),
                IconButton(
                  tooltip: 'Apagar',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.error),
                  onPressed: () => _deleteService(s),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── ESTADO / AÇÕES ─────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar prestador'),
        content: const Text(
            'O prestador ficará visível aos clientes (se estiver online). Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supabase.rpc('admin_appointment_provider_approve',
          params: {'p_provider_id': widget.providerId});
      _toast('Prestador aprovado.');
      await _loadAll();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rejeitar prestador'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatório)',
              hintText: 'Ex.: dados incompletos, licença em falta…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                final txt = ctrl.text.trim();
                if (txt.isEmpty) return;
                Navigator.pop(ctx, txt);
              },
              child: const Text('Rejeitar'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (reason == null || reason.isEmpty) return;
    try {
      await _supabase.rpc('admin_appointment_provider_reject',
          params: {'p_provider_id': widget.providerId, 'p_reason': reason});
      _toast('Prestador rejeitado.');
      await _loadAll();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _setActiveAdmin(bool value) async {
    try {
      await _supabase
          .from('service_providers')
          .update({'is_active_admin': value}).eq('id', widget.providerId);
      _toast(value ? 'Prestador activado.' : 'Prestador desactivado.');
      await _loadAll();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _setOnline(bool value) async {
    try {
      await _supabase
          .from('service_providers')
          .update({'is_online': value}).eq('id', widget.providerId);
      _toast(value ? 'Colocado Online.' : 'Colocado Offline.');
      await _loadAll();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _deleteProvider() async {
    // Confirmação dupla (destrutivo).
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar prestador'),
        content: Text(
            'Apagar "${_provider?['name'] ?? ''}"? Isto remove também todos os serviços e a equipa. Esta ação é irreversível.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tens a certeza?'),
        content: const Text(
            'Confirma que queres APAGAR definitivamente este prestador.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar definitivamente'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      // FKs NO ACTION: appointments.provider_id e appointment_payouts.provider_id
      // impedem o DELETE se houver histórico. Nesse caso, DESACTIVAMOS em vez de
      // apagar (preserva histórico financeiro/agendamentos) e avisamos.
      final appts = await _supabase
          .from('appointments')
          .select('id')
          .eq('provider_id', widget.providerId)
          .limit(1);
      final payouts = await _supabase
          .from('appointment_payouts')
          .select('id')
          .eq('provider_id', widget.providerId)
          .limit(1);
      if ((appts as List).isNotEmpty || (payouts as List).isNotEmpty) {
        await _supabase
            .from('service_providers')
            .update({'is_active_admin': false, 'is_online': false}).eq(
                'id', widget.providerId);
        if (!mounted) return;
        setState(() => _deleting = false);
        _toast(
            'Prestador tem histórico (agendamentos/pagamentos) — foi DESACTIVADO em vez de apagado.');
        await _loadAll();
        return;
      }
      // Sem histórico: DELETE (CASCADE remove provider_services + staff_members).
      await _supabase
          .from('service_providers')
          .delete()
          .eq('id', widget.providerId);
      if (!mounted) return;
      _toast('Prestador apagado.');
      Navigator.pop(context, true); // devolve `true` → a lista recarrega.
    } catch (e) {
      if (mounted) setState(() => _deleting = false);
      _toast('Erro ao apagar: $e');
    }
  }

  Widget _buildEstadoTab() {
    if (_loading || _provider == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _provider!;
    final status = r['approval_status'] as String?;
    final isActive = (r['is_active_admin'] as bool?) ?? true;
    final isOnline = (r['is_online'] as bool?) ?? false;
    final rejReason = r['rejection_reason'] as String?;

    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(children: [
                const Text('Estado da aprovação',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: Spacing.xs),
                Text((status ?? '—').toUpperCase(),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
                if (rejReason != null && rejReason.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text('Motivo: $rejReason',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Card(
            child: SwitchListTile.adaptive(
              value: isOnline,
              onChanged: _setOnline,
              title: const Text('Online / Offline',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(isOnline
                  ? 'Visível e disponível para clientes (se aprovado).'
                  : 'Indisponível para clientes.'),
              activeThumbColor: AppColors.success,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Card(
            child: SwitchListTile.adaptive(
              value: isActive,
              onChanged: _setActiveAdmin,
              title: const Text('Activo no admin',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(isActive
                  ? 'Prestador activo na plataforma.'
                  : 'Prestador DESACTIVADO pelo admin.'),
              activeThumbColor: AppColors.success,
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (status != 'approved')
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.success),
                icon: const Icon(Icons.check_circle),
                label: const Text('Aprovar'),
                onPressed: _approve,
              ),
            ),
          if (status != 'rejected')
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Rejeitar'),
                onPressed: _reject,
              ),
            ),
          const Divider(height: Spacing.xxl),
          const Text('Zona de perigo',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error)),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_forever),
            label: const Text('Apagar prestador'),
            onPressed: _deleting ? null : _deleteProvider,
          ),
        ],
      ),
    );
  }

  // ─── HELPERS de UI ──────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: Spacing.md),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _imageCard({
    required String title,
    required String subtitle,
    required String? url,
    required bool uploading,
    required VoidCallback onUpload,
    required VoidCallback onRemove,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.image_outlined, size: 20),
              const SizedBox(width: Spacing.sm),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: Spacing.sm),
            if (url != null && url.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
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
                    child: Text('Sem imagem configurada',
                        style: TextStyle(color: Colors.grey))),
              ),
            const SizedBox(height: Spacing.sm),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: uploading ? null : onUpload,
                  icon: uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload),
                  label: Text(url != null && url.isNotEmpty
                      ? 'Trocar imagem'
                      : 'Enviar imagem'),
                ),
              ),
              if (url != null && url.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: uploading ? null : onRemove,
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  label: const Text('Remover',
                      style: TextStyle(color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error)),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _provider?['name'] as String? ?? widget.initialName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Dados'),
            Tab(icon: Icon(Icons.schedule), text: 'Horários'),
            Tab(icon: Icon(Icons.content_cut), text: 'Serviços'),
            Tab(icon: Icon(Icons.toggle_on), text: 'Estado'),
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
                _buildServicosTab(),
                _buildEstadoTab(),
              ],
            ),
    );
  }
}
