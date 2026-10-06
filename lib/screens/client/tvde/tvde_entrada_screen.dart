import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';
import 'tvde_request_ride_screen.dart';

/// Porta única do Bora Motorista no lado do cliente (2026-10-06, caso Beatriz).
///
/// Regra do Danilo (30/09, reforçada a 06/10): quem já tinha cadastro fica com
/// a categoria; os NOVOS cadastros não a veem. Em vez dela aparece uma
/// "Nova categoria" por descobrir — a pessoa deixa nome e telefone, pede, e o
/// Danilo aprova no painel (Pedidos de acesso TVDE). Só depois de aprovado é
/// que entra no ecrã de pedir corrida.
///
/// Todas as entradas (ladrilho da home, faixas, pesquisa) passam por aqui. O
/// servidor também recusa (`no_tvde_access`) — este ecrã é só para a pessoa
/// nunca dar com um erro.
class TvdeEntradaScreen extends StatefulWidget {
  const TvdeEntradaScreen({super.key});

  @override
  State<TvdeEntradaScreen> createState() => _TvdeEntradaScreenState();
}

class _TvdeEntradaScreenState extends State<TvdeEntradaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TvdeStore>().refreshAccess();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    if (store.tvdeAccess) return const TvdeRequestRideScreen();
    if (!store.accessLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const TvdeDescobrirCategoriaScreen();
  }
}

/// Ecrã da categoria por descobrir. Não diz qual é — é surpresa até o Danilo
/// aprovar.
class TvdeDescobrirCategoriaScreen extends StatefulWidget {
  const TvdeDescobrirCategoriaScreen({super.key});

  @override
  State<TvdeDescobrirCategoriaScreen> createState() =>
      _TvdeDescobrirCategoriaScreenState();
}

class _TvdeDescobrirCategoriaScreenState
    extends State<TvdeDescobrirCategoriaScreen> {
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    _preencher();
  }

  /// Pré-preenche com o que o cliente já deu no cadastro.
  Future<void> _preencher() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final u = await sb
          .from('users')
          .select('name, phone')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || u == null) return;
      if (_nome.text.isEmpty) _nome.text = (u['name'] as String?) ?? '';
      if (_telefone.text.isEmpty) _telefone.text = (u['phone'] as String?) ?? '';
    } catch (_) {/* campos ficam vazios, a pessoa escreve */}
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    super.dispose();
  }

  Future<void> _pedir() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<TvdeStore>().requestAccess(
            nome: _nome.text.trim(),
            telefone: _telefone.text.trim(),
          );
      if (!mounted) return;
      await context.read<TvdeStore>().refreshAccess();
    } catch (e) {
      if (!mounted) return;
      final s = '$e';
      if (s.contains('already_has_access')) {
        await context.read<TvdeStore>().refreshAccess();
        return;
      }
      messenger.showSnackBar(SnackBar(
          content: Text('Não consegui enviar o pedido. Tenta de novo.'.tr)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<TvdeStore>().accessRequestStatus;
    final pendente = estado == 'pendente';
    final recusado = estado == 'recusado';

    return Scaffold(
      appBar: AppBar(title: Text('Nova categoria'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.xl),
          children: [
            const SizedBox(height: Spacing.lg),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 48, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              pendente
                  ? 'Pedido enviado!'.tr
                  : 'Há uma categoria nova à tua espera'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              pendente
                  ? 'Estamos a analisar o teu pedido. Assim que for aprovado, a categoria aparece na tua página inicial.'
                      .tr
                  : recusado
                      ? 'Desta vez o teu pedido não foi aprovado. Podes voltar a pedir quando quiseres.'
                          .tr
                      : 'É exclusiva e o acesso é dado um a um. Deixa o teu nome e telefone e pede para a descobrir.'
                          .tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: Spacing.xxl),
            if (!pendente)
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nome,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Nome'.tr,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Escreve o teu nome.'.tr
                          : null,
                    ),
                    const SizedBox(height: Spacing.md),
                    TextFormField(
                      controller: _telefone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Telefone'.tr,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').replaceAll(RegExp(r'\D'), '').length < 9
                              ? 'Escreve um telefone válido.'.tr
                              : null,
                    ),
                    const SizedBox(height: Spacing.xl),
                    BoraPrimaryButton(
                      label: 'Pedir para descobrir'.tr,
                      icon: Icons.lock_open,
                      loading: _aEnviar,
                      onPressed: _aEnviar ? null : _pedir,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
