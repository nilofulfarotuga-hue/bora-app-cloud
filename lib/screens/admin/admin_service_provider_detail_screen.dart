// Admin — Detalhe / gestão TOTAL do prestador de serviços (vertical Serviços /
// Beleza). Espelha `admin_partner_detail_screen.dart` (restaurantes) mas para a
// tabela `service_providers` + `provider_services`. PT-BR.
//
// Abas: Dados (editar + logo + capa) · Horários · Serviços & Preços · Equipe
// (staff com foto) · Estado.
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
import '../../utils/io_compat.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/staff_member_model.dart';
// Prefixo `wh`: `DayHours` também existe em restaurant_model.dart (horários de
// restaurante). Aqui é o horário da vertical Serviços (staff_availability).
import '../../models/weekly_hours.dart' as wh;
import '../../utils/safe_image_picker.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/services/staff_avatar.dart';
import '../../widgets/services/weekly_hours_editor.dart';

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

  // Sobre (about_text)
  final _aboutCtrl = TextEditingController();
  bool _savingAbout = false;

  // Redes sociais
  final _instagramCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  bool _savingSocial = false;

  // Galeria (gallery_urls)
  List<String> _galleryUrls = const [];
  bool _uploadingGallery = false;

  // Horários — BLOCO C (2026-07-28).
  // FONTE DA VERDADE: `staff_availability` (por profissional × day_of_week),
  // que é o que a RPC `get_available_slots` lê. Até aqui esta aba escrevia só
  // em `service_providers.business_hours` — vitrine da ficha, ZERO efeito nos
  // horários que o cliente consegue marcar.
  Map<int, wh.DayHours> _week = wh.defaultWeek();
  String? _hoursStaffId;
  bool _hoursApplyToAll = true;
  bool _savingHours = false;

  // Modo de cobrança + política de cancelamento (BLOCO B / BLOCO E).
  String _paymentMode = 'deposit';
  String _cancellationPolicy = 'refund';
  bool _savingPolicy = false;

  // Serviços
  List<Map<String, dynamic>> _services = const [];
  bool _servicesLoading = true;

  // Equipe (staff_members)
  List<Map<String, dynamic>> _staff = const [];
  bool _staffLoading = true;

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _aboutCtrl.dispose();
    _instagramCtrl.dispose();
    _facebookCtrl.dispose();
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
        _aboutCtrl.text = r['about_text'] as String? ?? '';
        _instagramCtrl.text = r['social_instagram'] as String? ?? '';
        _facebookCtrl.text = r['social_facebook'] as String? ?? '';
        _galleryUrls = r['gallery_urls'] is List
            ? (r['gallery_urls'] as List).map((e) => e.toString()).toList()
            : const [];
        _paymentMode = (r['booking_payment_mode'] as String?) ?? 'deposit';
        _cancellationPolicy =
            (r['booking_cancellation_policy'] as String?) ?? 'refund';
        _loading = false;
      });
      await _loadServices();
      await _loadStaff();
      await _loadWeeklyHours();
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

  Future<void> _loadStaff() async {
    setState(() => _staffLoading = true);
    try {
      // Admin vê TODA a equipa (activos e inactivos).
      final res = await _supabase
          .from('staff_members')
          .select()
          .eq('provider_id', widget.providerId)
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _staff = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _staffLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _staffLoading = false);
      _toast('Erro ao carregar equipe: $e');
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
          const SizedBox(height: Spacing.md),
          _sectionCard(
            icon: Icons.menu_book_outlined,
            title: 'Sobre (história do prestador)',
            children: [
              TextField(
                controller: _aboutCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Texto "Sobre"',
                  helperText:
                      'Aparece no perfil do cliente (aba/secção "Sobre"). Deixe vazio para não mostrar a secção.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Guardar "Sobre"',
                icon: Icons.save,
                loading: _savingAbout,
                onPressed: _savingAbout ? null : _saveAbout,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _galleryCard(),
          const SizedBox(height: Spacing.md),
          _sectionCard(
            icon: Icons.share_outlined,
            title: 'Redes sociais',
            children: [
              TextField(
                controller: _instagramCtrl,
                decoration: const InputDecoration(
                  labelText: 'Instagram',
                  helperText: 'Handle (@nome) ou URL completo. Opcional.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _facebookCtrl,
                decoration: const InputDecoration(
                  labelText: 'Facebook',
                  helperText: 'Handle ou URL completo. Opcional.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Guardar redes sociais',
                icon: Icons.save,
                loading: _savingSocial,
                onPressed: _savingSocial ? null : _saveSocial,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _galleryCard() {
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
              const Icon(Icons.photo_library_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              const Text('Galeria',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Fotos do espaço/trabalhos. Aparece no perfil do cliente. Use as setas para reordenar.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: Spacing.md),
            if (_galleryUrls.isEmpty)
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Center(
                    child: Text('Sem fotos na galeria',
                        style: TextStyle(color: Colors.grey))),
              )
            else
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (var i = 0; i < _galleryUrls.length; i++)
                    _galleryThumb(i),
                ],
              ),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: _uploadingGallery ? null : _addGalleryPhoto,
              icon: _uploadingGallery
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Adicionar foto'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _galleryThumb(int index) {
    final url = _galleryUrls[index];
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () => _removeGalleryPhoto(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed:
                    index == 0 ? null : () => _moveGalleryPhoto(index, -1),
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: index == _galleryUrls.length - 1
                    ? null
                    : () => _moveGalleryPhoto(index, 1),
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
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

  // ─── SOBRE (about_text) ─────────────────────────────────────────────────────

  Future<void> _saveAbout() async {
    setState(() => _savingAbout = true);
    try {
      final text = _aboutCtrl.text.trim();
      await _supabase
          .from('service_providers')
          .update({'about_text': text.isEmpty ? null : text}).eq(
              'id', widget.providerId);
      _toast('Texto "Sobre" guardado.');
    } catch (e) {
      _toast('Erro ao guardar: $e');
    } finally {
      if (mounted) setState(() => _savingAbout = false);
    }
  }

  // ─── REDES SOCIAIS ──────────────────────────────────────────────────────────

  Future<void> _saveSocial() async {
    setState(() => _savingSocial = true);
    try {
      final ig = _instagramCtrl.text.trim();
      final fb = _facebookCtrl.text.trim();
      await _supabase.from('service_providers').update({
        'social_instagram': ig.isEmpty ? null : ig,
        'social_facebook': fb.isEmpty ? null : fb,
      }).eq('id', widget.providerId);
      _toast('Redes sociais guardadas.');
    } catch (e) {
      _toast('Erro ao guardar: $e');
    } finally {
      if (mounted) setState(() => _savingSocial = false);
    }
  }

  // ─── GALERIA (gallery_urls) via Edge Function upload-restaurant-asset ───────

  Future<void> _saveGalleryUrls(List<String> urls) async {
    await _supabase
        .from('service_providers')
        .update({'gallery_urls': urls}).eq('id', widget.providerId);
  }

  Future<void> _addGalleryPhoto() async {
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
    setState(() => _uploadingGallery = true);
    try {
      // Pasta `{providerId}/gallery/...` — a Edge Function concatena
      // `{restaurantId}/{kind}-{timestamp}.{ext}`, por isso `kind` inclui a
      // subpasta 'gallery/photo'.
      final response = await _supabase.functions.invoke(
        'upload-restaurant-asset',
        body: {
          'restaurantId': widget.providerId,
          'kind': 'gallery/photo',
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
      final updated = [..._galleryUrls, publicUrl];
      await _saveGalleryUrls(updated);
      if (!mounted) return;
      setState(() => _galleryUrls = updated);
      _toast('Foto adicionada à galeria.');
    } catch (e) {
      _toast('Erro ao enviar foto: $e');
    } finally {
      if (mounted) setState(() => _uploadingGallery = false);
    }
  }

  Future<void> _removeGalleryPhoto(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover foto?'),
        content: const Text('Esta foto será removida da galeria. Continuar?'),
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
    final updated = [..._galleryUrls]..removeAt(index);
    try {
      await _saveGalleryUrls(updated);
      if (!mounted) return;
      setState(() => _galleryUrls = updated);
      _toast('Foto removida.');
    } catch (e) {
      _toast('Erro ao remover: $e');
    }
  }

  Future<void> _moveGalleryPhoto(int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= _galleryUrls.length) return;
    final updated = [..._galleryUrls];
    final item = updated.removeAt(index);
    updated.insert(target, item);
    final previous = _galleryUrls;
    setState(() => _galleryUrls = updated);
    try {
      await _saveGalleryUrls(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _galleryUrls = previous);
      _toast('Erro ao reordenar: $e');
    }
  }

  // ─── HORÁRIOS ───────────────────────────────────────────────────────────────

  /// Lê o horário real (staff_availability) do profissional seleccionado.
  Future<void> _loadWeeklyHours({String? staffId}) async {
    final id = staffId ??
        _hoursStaffId ??
        (_staff.isNotEmpty ? _staff.first['id'] as String? : null);
    if (id == null) return;
    try {
      final res = await _supabase
          .from('staff_availability')
          .select()
          .eq('staff_id', id);
      final week = wh.defaultWeek();
      for (final r in (res as List)) {
        final row = Map<String, dynamic>.from(r as Map);
        final dow = (row['day_of_week'] as num?)?.toInt();
        if (dow == null || dow < 0 || dow > 6) continue;
        week[dow] = wh.DayHours.fromAvailabilityRow(row);
      }
      if (!mounted) return;
      setState(() {
        _hoursStaffId = id;
        _week = week;
      });
    } catch (e) {
      _toast('Erro ao carregar horário: $e');
    }
  }

  /// Grava nos DOIS sítios: `staff_availability` (motor de slots) e
  /// `business_hours` (vitrine). RLS `sa_write`/`sp_update` já permitem admin.
  Future<void> _saveWeeklyHours() async {
    if (_hoursStaffId == null) return;
    for (final entry in _week.entries) {
      final err = entry.value.validate(ptBr: true);
      if (err != null) {
        _toast('${wh.kWeekdayNamesPt[entry.key]}: $err');
        return;
      }
    }
    setState(() => _savingHours = true);
    try {
      final targets = _hoursApplyToAll
          ? _staff.map((s) => s['id'] as String).toList()
          : [_hoursStaffId!];
      final rows = <Map<String, dynamic>>[
        for (final staffId in targets)
          for (final entry in _week.entries)
            entry.value.toAvailabilityRow(staffId, entry.key),
      ];
      await _supabase
          .from('staff_availability')
          .upsert(rows, onConflict: 'staff_id,day_of_week');
      await _supabase.from('service_providers').update({
        'business_hours': {
          for (final entry in _week.entries)
            wh.kBusinessHoursKeys[entry.key]: entry.value.toBusinessHoursEntry(),
        },
      }).eq('id', widget.providerId);
      _toast('Horário salvo. Já vale para as próximas marcações.');
    } catch (e) {
      _toast('Erro ao salvar horário: $e');
    } finally {
      if (mounted) setState(() => _savingHours = false);
    }
  }

  /// BLOCO B + E — alterna o modo de cobrança e a política de cancelamento.
  /// NÃO toca em `platform_settings` (o sinal de €3 e o split continuam a
  /// valer para todos os parceiros em modo `deposit`).
  Future<void> _savePolicy({String? paymentMode, String? cancellation}) async {
    setState(() => _savingPolicy = true);
    try {
      await _supabase.from('service_providers').update({
        if (paymentMode != null) 'booking_payment_mode': paymentMode,
        if (cancellation != null) 'booking_cancellation_policy': cancellation,
      }).eq('id', widget.providerId);
      if (!mounted) return;
      setState(() {
        if (paymentMode != null) _paymentMode = paymentMode;
        if (cancellation != null) _cancellationPolicy = cancellation;
      });
      _toast('Configuração salva.');
    } catch (e) {
      _toast('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _savingPolicy = false);
    }
  }

  Widget _buildHorariosTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_staff.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: Text(
            'Cadastre primeiro um profissional na aba Equipe.\n'
            'O horário é definido por profissional (staff_availability).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        const Card(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Text(
              'Este é o horário REAL — é dele que saem os horários que o '
              'cliente consegue marcar (staff_availability → '
              'get_available_slots). A vitrine da ficha (business_hours) é '
              'atualizada em espelho ao salvar. Nenhuma marcação pode começar '
              'nem terminar dentro da pausa.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_staff.length > 1) ...[
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              for (final s in _staff)
                ChoiceChip(
                  label: Text(s['name'] as String? ?? '—'),
                  selected: s['id'] == _hoursStaffId,
                  onSelected: (_) =>
                      _loadWeeklyHours(staffId: s['id'] as String),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hoursApplyToAll,
            onChanged: (v) => setState(() => _hoursApplyToAll = v),
            title: const Text('Aplicar a toda a equipe'),
            subtitle: const Text('Salva este horário para todos os profissionais.'),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        WeeklyHoursEditor(
          week: _week,
          ptBr: true,
          enabled: !_savingHours,
          onChanged: (w) => setState(() => _week = w),
        ),
        const SizedBox(height: Spacing.md),
        BoraPrimaryButton(
          label: 'Salvar horários',
          icon: Icons.save,
          loading: _savingHours,
          onPressed: _savingHours ? null : _saveWeeklyHours,
        ),
        const SizedBox(height: Spacing.xl),
        _buildPolicyCard(),
      ],
    );
  }

  /// BLOCO B + BLOCO E — controlos por parceiro, com o efeito de cada opção
  /// escrito por extenso (PT-BR, painel do Danilo).
  Widget _buildPolicyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cobrança e cancelamento',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: Spacing.md),
            const Text('Modo de cobrança da marcação',
                style: TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'deposit',
              groupValue: _paymentMode,
              onChanged: _savingPolicy
                  ? null
                  : (v) => _savePolicy(paymentMode: v),
              title: const Text('Sinal (padrão)'),
              subtitle: const Text(
                'Cobra os €3,00 de sinal (platform_settings). O resto o '
                'cliente paga na loja.',
              ),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'full',
              groupValue: _paymentMode,
              onChanged: _savingPolicy
                  ? null
                  : (v) => _savePolicy(paymentMode: v),
              title: const Text('Valor cheio'),
              subtitle: const Text(
                'Cobra o preço TOTAL do serviço na hora de marcar. O dinheiro '
                'entra 100% na Bora; o acerto com o parceiro é fora do app.',
              ),
            ),
            const Divider(height: Spacing.xl),
            const Text('Política de cancelamento',
                style: TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'refund',
              groupValue: _cancellationPolicy,
              onChanged: _savingPolicy
                  ? null
                  : (v) => _savePolicy(cancellation: v),
              title: const Text('Cancelamento com reembolso (padrão)'),
              subtitle: const Text(
                'O cliente pode cancelar. Dentro da janela de 24h recebe o '
                'valor de volta; fora dela, fica retido.',
              ),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'reschedule_only',
              groupValue: _cancellationPolicy,
              onChanged: _savingPolicy
                  ? null
                  : (v) => _savePolicy(cancellation: v),
              title: const Text('Somente reagendamento'),
              subtitle: const Text(
                'O cliente NÃO cancela uma marcação já paga — só reagenda '
                '(mesma cobrança, sem reembolso). Se não reagendar e não '
                'aparecer, perde o valor (no-show).',
              ),
            ),
            if (_savingPolicy)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.sm),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
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

  // ─── EQUIPE (staff_members — CRUD directo, RLS is_admin) ────────────────────

  /// Escolhe (câmara/galeria) e sobe uma foto de profissional via a Edge
  /// Function `upload-restaurant-asset` (kind='staff_photo' → bucket público).
  /// Devolve o public_url ou lança em erro.
  Future<String?> _uploadStaffPhoto() async {
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
    if (source == null) return null;
    final file = await SafeImagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1000,
    );
    if (file == null) return null;
    final bytes = await File(file.path).readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _toast('Imagem muito grande (máx 10 MB).');
      return null;
    }
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
    final response = await _supabase.functions.invoke(
      'upload-restaurant-asset',
      body: {
        'restaurantId': widget.providerId,
        'kind': 'staff_photo',
        'fileBase64': base64Encode(bytes),
        'contentType': 'image/${safeExt == 'jpg' ? 'jpeg' : safeExt}',
      },
    );
    if (response.status != 200 || response.data is! Map) {
      throw Exception('upload-restaurant-asset HTTP ${response.status}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true || data['public_url'] == null) {
      throw Exception(data['error']?.toString() ?? 'upload falhou');
    }
    return data['public_url'] as String;
  }

  Future<void> _staffDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final bioCtrl =
        TextEditingController(text: existing?['bio'] as String? ?? '');
    final specialtiesCtrl = TextEditingController(
        text: ((existing?['specialties'] as List?)
                ?.map((e) => e.toString())
                .join(', ')) ??
            '');
    String? photoUrl = existing?['photo_url'] as String?;
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    bool uploading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(
              existing == null ? 'Adicionar profissional' : 'Editar profissional'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: uploading
                          ? null
                          : () async {
                              setSt(() => uploading = true);
                              try {
                                final url = await _uploadStaffPhoto();
                                if (url != null) setSt(() => photoUrl = url);
                              } catch (e) {
                                _toast('Erro ao enviar foto: $e');
                              } finally {
                                setSt(() => uploading = false);
                              }
                            },
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.primaryLight,
                            backgroundImage:
                                (photoUrl != null && photoUrl!.isNotEmpty)
                                    ? NetworkImage(photoUrl!)
                                    : null,
                            child: uploading
                                ? const CircularProgressIndicator()
                                : ((photoUrl == null || photoUrl!.isEmpty)
                                    ? const Icon(Icons.person,
                                        size: 36, color: AppColors.primary)
                                    : null),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Obrigatório'
                        : null,
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: bioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Função / Bio (ex.: Cabeleireira)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: specialtiesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Especialidades (separadas por vírgula)',
                      border: OutlineInputBorder(),
                    ),
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
              onPressed: (saving || uploading)
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setSt(() => saving = true);
                      final specialties = specialtiesCtrl.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      try {
                        if (existing == null) {
                          final nextOrder = _staff.isEmpty
                              ? 0
                              : ((_staff.last['sort_order'] as num?)?.toInt() ??
                                      _staff.length - 1) +
                                  1;
                          await _supabase.from('staff_members').insert({
                            'provider_id': widget.providerId,
                            'name': nameCtrl.text.trim(),
                            'bio': bioCtrl.text.trim(),
                            'photo_url': photoUrl,
                            'specialties': specialties,
                            'is_active': true,
                            'sort_order': nextOrder,
                          });
                        } else {
                          await _supabase.from('staff_members').update({
                            'name': nameCtrl.text.trim(),
                            'bio': bioCtrl.text.trim(),
                            'photo_url': photoUrl,
                            'specialties': specialties,
                          }).eq('id', existing['id']);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _toast(existing == null
                            ? 'Profissional adicionado.'
                            : 'Profissional actualizado.');
                        await _loadStaff();
                      } catch (e) {
                        setSt(() => saving = false);
                        _toast('Erro ao guardar profissional: $e');
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
    bioCtrl.dispose();
    specialtiesCtrl.dispose();
  }

  Future<void> _toggleStaffActive(Map<String, dynamic> s) async {
    final current = (s['is_active'] as bool?) ?? true;
    try {
      await _supabase
          .from('staff_members')
          .update({'is_active': !current}).eq('id', s['id']);
      _toast(!current ? 'Profissional activado.' : 'Profissional desactivado.');
      await _loadStaff();
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _deleteStaff(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar profissional'),
        content: Text(
            'Apagar "${s['name']}"? Esta ação não pode ser desfeita.'),
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
      // `appointments.staff_id` → staff_members: se houver marcações, o DELETE
      // falha. Verificamos antes e, nesse caso, desactivamos (mantém histórico).
      final linked = await _supabase
          .from('appointments')
          .select('id')
          .eq('staff_id', s['id'])
          .limit(1);
      if ((linked as List).isNotEmpty) {
        await _supabase
            .from('staff_members')
            .update({'is_active': false}).eq('id', s['id']);
        _toast(
            'Profissional tem marcações no histórico — foi DESACTIVADO em vez de apagado.');
        await _loadStaff();
        return;
      }
      await _supabase.from('staff_members').delete().eq('id', s['id']);
      _toast('Profissional apagado.');
      await _loadStaff();
    } catch (e) {
      _toast('Erro ao apagar profissional: $e');
    }
  }

  Future<void> _moveStaff(int index, int delta) async {
    final j = index + delta;
    if (j < 0 || j >= _staff.length) return;
    final list = [..._staff];
    final tmp = list[index];
    list[index] = list[j];
    list[j] = tmp;
    setState(() => _staff = list);
    try {
      for (var i = 0; i < list.length; i++) {
        await _supabase
            .from('staff_members')
            .update({'sort_order': i}).eq('id', list[i]['id']);
      }
      await _loadStaff();
    } catch (e) {
      _toast('Erro ao reordenar: $e');
      await _loadStaff();
    }
  }

  Widget _buildEquipeTab() {
    if (_staffLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadStaff,
            child: _staff.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(Spacing.xxxl),
                        child: Center(
                            child: Text('Nenhum profissional cadastrado.',
                                style:
                                    TextStyle(color: AppColors.textSecondary))),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: _staff.length,
                    itemBuilder: (ctx, i) => _staffRow(_staff[i], i),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: BoraPrimaryButton(
              label: 'Adicionar profissional',
              icon: Icons.add,
              onPressed: () => _staffDialog(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _staffRow(Map<String, dynamic> s, int index) {
    final active = (s['is_active'] as bool?) ?? true;
    final specialties = (s['specialties'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final model = StaffMemberModel.fromSupabase(s);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StaffAvatar(staff: model, radius: 24),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s['name'] as String? ?? '(sem nome)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: active ? null : AppColors.textSecondary,
                          decoration:
                              active ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if ((s['bio'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 2),
                        Text(s['bio'] as String,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                      if (!active) ...[
                        const SizedBox(height: 2),
                        const Text('inactivo',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (specialties.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final sp in specialties) _adminChip(sp)],
              ),
            ],
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Subir',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: index == 0 ? null : () => _moveStaff(index, -1),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Descer',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: index == _staff.length - 1
                      ? null
                      : () => _moveStaff(index, 1),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: Icon(
                      active ? Icons.toggle_on : Icons.toggle_off_outlined,
                      size: 18),
                  label: Text(active ? 'Desactivar' : 'Activar'),
                  style: TextButton.styleFrom(
                      foregroundColor:
                          active ? AppColors.warning : AppColors.success),
                  onPressed: () => _toggleStaffActive(s),
                ),
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit, size: 18, color: AppColors.info),
                  onPressed: () => _staffDialog(existing: s),
                ),
                IconButton(
                  tooltip: 'Apagar',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.error),
                  onPressed: () => _deleteStaff(s),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
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
            Tab(icon: Icon(Icons.groups_outlined), text: 'Equipe'),
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
                _buildEquipeTab(),
                _buildEstadoTab(),
              ],
            ),
    );
  }
}
