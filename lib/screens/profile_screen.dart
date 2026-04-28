import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/app_theme.dart';
import '../models/driver_model.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import 'orders_screen.dart';
import 'support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _imagePicker = ImagePicker();

  String? _photoUrl;
  XFile? _localPreview;
  bool _isUploading = false;
  bool _photoLoaded = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadPhotoUrl();
  }

  Future<void> _loadPhotoUrl() async {
    // Priority: local account (survives session cache staleness) → Supabase
    // metadata → server refresh via getUser().
    final authStore = context.read<AuthStore>();
    final localUrl = authStore.currentPhotoUrl;
    if (localUrl.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _photoUrl = localUrl;
        _photoLoaded = true;
      });
      return;
    }

    final client = Supabase.instance.client;
    var user = client.auth.currentUser;
    var metaUrl = user?.userMetadata?['bora_photo_url'] as String?;

    // Local restored session can have stale metadata — ask the server.
    if ((metaUrl == null || metaUrl.isEmpty) && user != null) {
      try {
        final fresh = await client.auth.getUser();
        metaUrl = fresh.user?.userMetadata?['bora_photo_url'] as String?;
      } catch (_) {}
    }

    if (!mounted) return;
    if (metaUrl != null && metaUrl.isNotEmpty) {
      // Mirror back into AuthStore so subsequent reads are instant.
      unawaited(authStore.updateCurrentUserPhoto(metaUrl));
    }
    setState(() {
      _photoUrl = (metaUrl != null && metaUrl.isNotEmpty) ? metaUrl : null;
      _photoLoaded = true;
    });
  }

  /// Decodes the picked image, center-crops it to a square and resizes to
  /// 500x500 px. Returns null if decoding fails.
  Future<Uint8List?> _squareResize(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final x = (decoded.width - side) ~/ 2;
    final y = (decoded.height - side) ~/ 2;
    final cropped =
        img.copyCrop(decoded, x: x, y: y, width: side, height: side);
    final resized = img.copyResize(
      cropped,
      width: 500,
      height: 500,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isUploading) return;

    final supabase = Supabase.instance.client;
    var userId = supabase.auth.currentUser?.id;

    // If the AuthStore considers us logged-in as a client but the Supabase
    // session is missing (null) or still attached to the guest session,
    // try a silent re-auth using the cached client credentials so the
    // upload path ({uid}/avatar.jpg) matches the client's own RLS folder.
    final authStore = context.read<AuthStore>();
    final client = authStore.currentClient;
    final currentEmail = supabase.auth.currentUser?.email;
    final sessionIsGuest = currentEmail == 'guest@bora.com';

    if ((userId == null || sessionIsGuest) &&
        client != null &&
        client.email.isNotEmpty &&
        client.password.isNotEmpty &&
        client.email != 'cliente@bora.app') {
      try {
        await supabase.auth.signInWithPassword(
          email: client.email,
          password: client.password,
        );
        userId = supabase.auth.currentUser?.id;
      } catch (_) {
        // silent — fall through to the guard below
      }
    }

    if (userId == null) {
      if (!mounted) return;
      final isDemo = client?.email == 'cliente@bora.app';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDemo
                ? 'Demo accounts não podem fazer upload de foto. Cria uma conta real.'
                : 'Sessão expirada. Faz logout e login novamente.',
          ),
        ),
      );
      return;
    }

    final chosen = await _chooseImageSource();
    if (chosen == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(
        source: chosen,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao seleccionar imagem: $e')),
      );
      return;
    }

    if (picked == null || !mounted) return;

    setState(() {
      _localPreview = picked;
      _isUploading = true;
    });

    try {
      final rawBytes = await picked.readAsBytes();
      // Centre-crop square + resize to 500px (smaller upload, consistent UI).
      final processed = await _squareResize(rawBytes) ?? rawBytes;

      final path = '$userId/avatar.jpg';
      final storage = Supabase.instance.client.storage;

      await storage.from('avatars').uploadBinary(
            path,
            processed,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final publicUrl = storage.from('avatars').getPublicUrl(path);
      // Cache-bust version suffix — stored in metadata so every device
      // sees the new image without waiting for Flutter's network cache.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final versionedUrl = '$publicUrl?v=$bust';

      // Single source of truth — AuthStore persists locally + to Supabase.
      // `authStore` is captured above (before async gaps).
      await authStore.updateCurrentUserPhoto(versionedUrl);

      if (!mounted) return;
      setState(() {
        _photoUrl = versionedUrl;
        _localPreview = null;
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localPreview = null;
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar foto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authStore = context.watch<AuthStore>();
    final driverStore = context.watch<DriverStore>();

    if (!authStore.isLogged) {
      return const Center(child: Text('Sessão terminada.'));
    }

    final role = authStore.role;
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = authStore.displayName ?? 'Utilizador';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Perfil',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Spacing.xxxl),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration:
                  const BoxDecoration(gradient: AppColors.headerGradient),
              padding: const EdgeInsets.fromLTRB(
                  Spacing.xxl, 0, Spacing.xxl, Spacing.xxxl),
              child: Column(
                children: [
                  _buildAvatar(initial: initial),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role == AuthRole.driver
                        ? 'Estafeta'
                        : role == AuthRole.partner
                            ? 'Parceiro'
                            : 'Cliente',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Info card ──────────────────────────────────────────────────
            _SectionCard(
              children: [
                if (role == AuthRole.client) ...[
                  _InfoTile(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: authStore.currentClient?.email ?? '-',
                  ),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Telemóvel',
                    value: authStore.currentClient?.phone ?? '-',
                  ),
                ] else if (role == AuthRole.driver) ...[
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Telemóvel',
                    value: authStore.currentDriver?.phone ?? '-',
                  ),
                  _InfoTile(
                    icon: Icons.directions_car_outlined,
                    label: 'Veículo',
                    value: driverStore.currentVehicleType.label,
                  ),
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    label: 'Matrícula',
                    value: authStore.currentDriver?.licensePlate ?? '-',
                  ),
                ] else if (role == AuthRole.partner) ...[
                  _InfoTile(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: authStore.currentPartner?.email ?? '-',
                  ),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Telefone',
                    value: authStore.currentPartner?.phone ?? '-',
                  ),
                  _InfoTile(
                    icon: Icons.location_on_outlined,
                    label: 'Endereço',
                    value: authStore.currentPartner?.address ?? '-',
                  ),
                  _InfoTile(
                    icon: Icons.restaurant_outlined,
                    label: 'Tipo de cozinha',
                    value: authStore.currentPartner?.cuisineType ?? '-',
                  ),
                ],
              ],
            ),

            // ── Token balance ──────────────────────────────────────────────
            if (role == AuthRole.client || role == AuthRole.driver) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TokenBalanceRow(),
              ),
              const SizedBox(height: 12),
            ],

            // ── Driver capabilities ────────────────────────────────────────
            if (role == AuthRole.driver) ...[
              _SectionCard(
                header: 'Serviços disponíveis',
                children: _vehicleCapabilities(driverStore.currentVehicleType)
                    .map(
                      (cap) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 20),
                        title: Text(cap, style: const TextStyle(fontSize: 14)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: Spacing.lg),
                      ),
                    )
                    .toList(),
              ),
            ],

            // ── Quick links ────────────────────────────────────────────────
            if (role == AuthRole.client)
              _SectionCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined,
                        color: AppTheme.primary),
                    title: const Text('Histórico de pedidos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersScreen()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined,
                        color: AppTheme.primary),
                    title: const Text('Suporte'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
                    ),
                  ),
                ],
              ),

            // ── Admin panel ────────────────────────────────────────────────
            if (user?.email == 'nilofulfarotuga@gmail.com' ||
                user?.email == 'nilofulfaro@gmail.com')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/admin'),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Painel Admin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md + 2),
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: Spacing.md),

            // ── Apagar conta (GDPR — BR §20.2) ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isDeletingAccount ? null : _confirmDeleteAccount,
                  icon: _isDeletingAccount
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.error),
                        )
                      : const Icon(Icons.delete_forever,
                          color: AppColors.error),
                  label: const Text(
                    'Apagar conta',
                    style: TextStyle(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md + 2),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: Spacing.md),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    authStore.logout();
                    await context.read<SessionStore>().clearRole();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.logout, color: AppColors.error),
                  label: const Text(
                    'Terminar sessão',
                    style: TextStyle(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md + 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({required String initial}) {
    ImageProvider? bgImage;
    if (_localPreview != null) {
      bgImage = FileImage(File(_localPreview!.path));
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      // ValueKey on the CircleAvatar forces rebuild when URL changes (bust).
      bgImage = NetworkImage(_photoUrl!);
    }

    final avatar = CircleAvatar(
      key: ValueKey(_photoUrl ?? _localPreview?.path ?? 'none'),
      radius: 44,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      backgroundImage: bgImage,
      child: bgImage == null
          ? Text(
              initial,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : null,
    );

    // All 3 roles can upload a profile photo.
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _isUploading ? null : _pickAndUploadAvatar,
          onLongPress: (_isUploading || _photoUrl == null || _photoUrl!.isEmpty)
              ? null
              : _confirmRemovePhoto,
          child: avatar,
        ),
        if (_isUploading)
          // Dim overlay + centred spinner, Uber-style.
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        if (!_isUploading && _photoLoaded)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 16,
                color: AppTheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmRemovePhoto() async {
    final authStore = context.read<AuthStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover foto de perfil?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        try {
          await supabase.storage.from('avatars').remove(['$uid/avatar.jpg']);
        } catch (_) {}
      }
      await authStore.updateCurrentUserPhoto('');
      if (!mounted) return;
      setState(() {
        _photoUrl = null;
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto removida.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover foto: $e')),
      );
    }
  }

  static List<String> _vehicleCapabilities(VehicleType type) {
    if (type == VehicleType.motorcycle) {
      return const [
        'Restaurantes parceiros e não parceiros',
        'Pequenas compras em loja',
      ];
    }
    return const [
      'Restaurantes',
      'Compras em loja',
      'Entregar compras',
      'Enviar pacotes e caixas',
    ];
  }

  // ── GDPR account deletion (BR §20.2) ────────────────────────────────────
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar conta'),
        content: const SingleChildScrollView(
          child: Text(
            'Os teus dados pessoais serão apagados imediatamente.\n\n'
            'Por obrigação legal, os dados fiscais (faturas) são '
            'guardados por 10 anos.\n\nConfirmar?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke('delete-account');

      if (!mounted) return;

      if (response.status >= 400) {
        setState(() => _isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Não foi possível apagar a conta. Tenta novamente mais tarde.'),
          ),
        );
        return;
      }

      // Local cleanup — match the existing logout flow.
      context.read<AuthStore>().logout();
      await context.read<SessionStore>().clearRole();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta apagada.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao apagar conta: $e')),
      );
    }
  }
}

// ─── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children, this.header});

  final List<Widget> children;
  final String? header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  header!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Info tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 22),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      subtitle: Text(
        value.isEmpty ? '-' : value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ─── Token balance row ────────────────────────────────────────────────────────
// Fetches the active token balance via get_user_tokens() RPC and displays it.
// Works for both client and driver — uses the currently authenticated user ID.

class _TokenBalanceRow extends StatelessWidget {
  _TokenBalanceRow();

  final _client = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: _client.rpc('get_user_tokens',
          params: {'p_user_id': userId}).then((v) => (v as int?) ?? 0),
      builder: (context, snapshot) {
        final balance = snapshot.data ?? 0;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bora Tokens',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.amber,
                          ),
                        )
                      : Text(
                          '$balance tokens',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
