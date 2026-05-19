import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'client_login_screen.dart';

class RegisterClientScreen extends StatefulWidget {
  const RegisterClientScreen({super.key});

  @override
  State<RegisterClientScreen> createState() => _RegisterClientScreenState();
}

class _RegisterClientScreenState extends State<RegisterClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  String _avatarLetter = '';

  final _imagePicker = ImagePicker();
  XFile? _avatarFile;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final letter = _nameController.text.trim().isEmpty
          ? ''
          : _nameController.text.trim()[0].toUpperCase();
      if (letter != _avatarLetter) setState(() => _avatarLetter = letter);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text('Criar conta'),
      ),
      body: SafeArea(
        child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.xxl,
            Spacing.sm,
            Spacing.xxl,
            Spacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Logo ────────────────────────────────────────────────────
              Text(
                'BORA',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'A tua app de entregas',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              // ── Avatar ──────────────────────────────────────────────────
              GestureDetector(
                onTap: _isSubmitting ? null : _showPhotoOptions,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor:
                          AppColors.accent.withValues(alpha: 0.12),
                      backgroundImage: _avatarFile != null
                          ? FileImage(File(_avatarFile!.path))
                          : null,
                      child: _avatarFile != null
                          ? null
                          : (_avatarLetter.isEmpty
                              ? Icon(Icons.person_outline,
                                  size: 44, color: Colors.grey.shade400)
                              : Text(
                                  _avatarLetter,
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE65100),
                                  ),
                                )),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE65100),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Foto de perfil (opcional)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o seu nome.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Informe o seu email.';
                  }
                  if (!v.contains('@')) return 'Email inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telemóvel',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o seu telemóvel.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmar palavra-passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'As palavras-passe não coincidem.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _referralCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Código de convite (opcional)',
                  hintText: 'Ex: BORA-ABC-1234',
                  prefixIcon: Icon(Icons.card_giftcard_outlined),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: _isSubmitting
                    ? null
                    : (v) => setState(() => _acceptedTerms = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: const TermsLinkText(),
              ),
              const SizedBox(height: 16),
              BoraPrimaryButton(
                label: 'Criar conta',
                loading: _isSubmitting,
                color: AppColors.primary,
                onPressed: _acceptedTerms ? _submit : null,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Já tenho conta?',
                      style: TextStyle(color: Colors.grey.shade600)),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const ClientLoginScreen()),
                    ),
                    child: const Text(
                      'Iniciar sessão',
                      style: TextStyle(
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _avatarFile = picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao seleccionar imagem: $e')),
        );
      }
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tirar foto'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    // ── FIX: Call registerClientAsync which does Supabase signUp FIRST,
    // then creates the local account only after Supabase confirms.
    // The old code had an empty try block and called the sync
    // registerClient() which fired signUp as fire-and-forget.
    final error = await authStore.registerClientAsync(
      name: name,
      email: email,
      phone: phone,
      password: password,
      consentAcceptedAt: DateTime.now().toUtc(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _isSubmitting = false);
      final msg = error.contains('already registered')
          ? 'Este email já está registado.'
          : error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    // ── Upload avatar foto (se escolhida) — não bloqueia em caso de falha ──
    if (_avatarFile != null) {
      try {
        final supabase = Supabase.instance.client;
        // T1 FIX: refresh session before upload (stale JWT → 403).
        try { await supabase.auth.refreshSession(); } catch (_) {}
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final bytes = await _avatarFile!.readAsBytes();
          final path = '$uid/avatar.jpg';
          await supabase.storage.from('avatars').uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(
                  upsert: true,
                  contentType: 'image/jpeg',
                ),
              );
          final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);
          await supabase.auth.updateUser(
            UserAttributes(data: {'bora_photo_url': publicUrl}),
          );
          // UPSERT em public.users — sem trigger automático auth→public,
          // a row pode não existir ainda. Cria com id+photo_url.
          await supabase
              .from('users')
              .upsert({'id': uid, 'photo_url': publicUrl});
        }
      } catch (e) {
        debugPrint('RegisterClientScreen: avatar upload failed => $e');
      }
    }

    // ── Código de convite (opcional) ───────────────────────────────────────
    // Se o utilizador colou um código no formulário, regista-o via RPC.
    // Falhas não bloqueiam o registo — o utilizador já tem conta válida.
    final referralCode = _referralCodeController.text.trim().toUpperCase();
    if (referralCode.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'client_register_with_referral',
          params: {'p_referral_code': referralCode},
        );
      } catch (e) {
        debugPrint('[Referral] Erro ao registar código "$referralCode": $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Código de convite inválido ou expirado — conta criada à mesma.'),
            ),
          );
        }
      }
    }

    await sessionStore.setRole(UserRole.client);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conta criada com sucesso!')),
    );

    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
