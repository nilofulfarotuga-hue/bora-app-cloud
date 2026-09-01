import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/roles_service.dart';
import '../widgets/bora/bora.dart';
import 'cleaner/cleaner_apply_screen.dart';
import 'driver_signup_screen.dart';
import 'login_screen.dart';
import 'washer/washer_apply_screen.dart';

import '../l10n/tr.dart';

/// A PORTA — "Quero trabalhar no Bora".
///
/// Até 2026-08-29 as candidaturas estavam escondidas. A da Limpeza só se
/// alcançava a partir do painel de quem JÁ era faxineiro — quatro níveis de
/// profundidade, e portanto inútil para quem ainda não era nada. A da Lavagem
/// não existia de todo. É a cicatriz do PADRAO_BORA §1.7.
///
/// Este ecrã é a entrada única: mostra as quatro actividades, o estado real de
/// cada uma para esta pessoa, e leva à candidatura certa com os dados que já
/// conhecemos dela pré-preenchidos.
class TrabalharNoBoraScreen extends StatefulWidget {
  const TrabalharNoBoraScreen({super.key});

  @override
  State<TrabalharNoBoraScreen> createState() => _TrabalharNoBoraScreenState();
}

class _TrabalharNoBoraScreenState extends State<TrabalharNoBoraScreen> {
  RolesSummary _roles = RolesSummary.empty();
  bool _loading = true;

  bool get _temSessao => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    // Sem sessão, `my_roles_summary` recusa — e é o comportamento certo. Aqui
    // isso lê-se como "ainda não és nada", que é verdade.
    final r = _temSessao ? await RolesService.mySummary() : RolesSummary.empty();
    if (!mounted) return;
    setState(() {
      _roles = r;
      _loading = false;
    });
  }

  Future<void> _abrir(AtividadeDeTrabalho a) async {
    // Corridas e entregas partilham a mesma candidatura: quem já é estafeta
    // não se recandidata para passar a fazer corridas — liga o interruptor.
    if (a.jaFaz) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(a.papel == 'driver' || a.papel == 'delivery'
            ? 'Já és estafeta. Liga ou desliga "{0}" na caixa "O que queres aceitar?" do teu ecrã de trabalho.'.trArgs([a.titulo])
            : 'Já fazes ${a.titulo.toLowerCase()}.'),
        duration: const Duration(seconds: 5),
      ));
      return;
    }
    if (a.emAnalise) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('A tua candidatura está em análise. Avisamos-te assim que estiver decidida.'.tr),
      ));
      return;
    }

    // A limpeza e a lavagem candidatam-se com a conta já autenticada (a função
    // da base recusa sem sessão). O estafeta tem fluxo próprio que cria conta.
    final precisaDeConta = a.papel == 'cleaner' || a.papel == 'washer';
    if (precisaDeConta && !_temSessao) {
      final entrar = await _perguntarSeEntra();
      if (entrar != true || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      await _carregar();
      if (!mounted || !_temSessao) return;
    }

    final prefill = _roles.dadosJaConhecidos;
    final destino = switch (a.papel) {
      'cleaner' => CleanerApplyScreen(prefill: prefill),
      'washer' => WasherApplyScreen(prefill: prefill),
      _ => const DriverSignupScreen(),
    };
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => destino));
    if (mounted) await _carregar();
  }

  Future<bool?> _perguntarSeEntra() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Precisas de conta Bora'.tr),
          content: Text(
            'Para te candidatares, entra com a tua conta Bora ou cria uma. Se já és cliente, é a mesma conta — não repetes os dados.'.tr,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Agora não'.tr),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Entrar'.tr),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final atividades = atividadesDisponiveis(_roles);
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Trabalhar no Bora'.tr),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text(
                  'Escolhe o que queres fazer. Podes fazer mais do que uma coisa — é a mesma conta, e os teus dados só se preenchem uma vez.'.tr,
                  style:
                      const TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: Spacing.lg),
                for (final a in atividades) ...[
                  _CartaoAtividade(atividade: a, onTap: () => _abrir(a)),
                  const SizedBox(height: Spacing.md),
                ],
                const SizedBox(height: Spacing.sm),
                Text(
                  'Tens um restaurante, uma loja ou um salão? Isso é uma parceria e faz-se pelo registo de parceiro.'.tr,
                  style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
                ),
              ],
            ),
    );
  }
}

class _CartaoAtividade extends StatelessWidget {
  const _CartaoAtividade({required this.atividade, required this.onTap});
  final AtividadeDeTrabalho atividade;
  final VoidCallback onTap;

  IconData get _icone => switch (atividade.papel) {
        'delivery' => Icons.pedal_bike_outlined,
        'driver' => Icons.local_taxi_outlined,
        'cleaner' => Icons.cleaning_services_outlined,
        'washer' => Icons.local_car_wash_outlined,
        _ => Icons.work_outline,
      };

  Color get _corDoEstado => switch (atividade.estado) {
        CrossRoleCardState.active => AppColors.primary,
        CrossRoleCardState.pending => AppColors.warning,
        CrossRoleCardState.invite => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: atividade.jaFaz ? AppColors.primary : AppColors.divider,
            width: atividade.jaFaz ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primaryWash,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(_icone, color: AppColors.primary),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    atividade.titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    atividade.descricao,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.3),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    atividade.rotuloDeEstado,
                    style: TextStyle(
                        color: _corDoEstado,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
