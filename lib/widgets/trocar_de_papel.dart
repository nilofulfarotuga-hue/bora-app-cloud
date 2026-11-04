import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../screens/cleaner/cleaner_home_screen.dart';
import '../screens/handyman/handyman_home_screen.dart';
import '../screens/trabalhar_no_bora_screen.dart';
import '../screens/washer/washer_home_screen.dart';
import '../services/papeis_de_trabalho.dart';
import '../services/roles_service.dart';
import '../services/tvde_visibilidade.dart';

/// SALTAR ENTRE PAPÉIS — sem sair e voltar a entrar.
///
/// Pedido do Danilo a 2026-08-29: quem faz mais do que uma coisa tinha de sair
/// da app e voltar para passar de motorista a lavador. A caixa "O que queres
/// aceitar?" diz o que a pessoa ACEITA receber; isto é outra coisa — é ir para
/// o ecrã de trabalho de outro papel agora.
///
/// Só aparece a quem tem mais do que um papel, e **nunca** enquanto houver
/// trabalho a decorrer: a meio de uma lavagem, o que se quer é voltar a ela,
/// não trocar de ofício. Essa regra vive em quem chama, com [temTrabalho].
Future<void> abrirTrocaDePapel(BuildContext context) async {
  final resumo = await RolesService.mySummary();
  if (!context.mounted) return;

  final destinos = <_Destino>[
    if (resumo.cleanerApproved)
      const _Destino('cleaner', 'Limpeza', Icons.cleaning_services_outlined),
    if (resumo.washerApproved)
      const _Destino('washer', 'Lavagem de carros', Icons.local_car_wash_outlined),
    if (resumo.handymanApproved)
      const _Destino('handyman', 'Casa e manutenção', Icons.handyman_outlined),
  ];

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Spacing.md),
          const Text('Ir trabalhar em',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.xs),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text(
              'Isto muda o ecrã em que estás. O que aceitas receber muda-se na '
              'caixa "O que queres aceitar?".',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          const Divider(height: 1),
          if (destinos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                // 04/11/2026 (fechar-bora-motorista): sem corridas com o
                // Bora Motorista fechado.
                '${TvdeVisibilidade.aberto ? 'Por agora só fazes entregas e corridas.' : 'Por agora só fazes entregas.'}'
                ' Podes juntar limpeza, '
                'lavagem de carros ou Casa e manutenção à mesma conta.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final d in destinos)
            ListTile(
              leading: Icon(d.icone, color: AppColors.primary),
              title: Text(d.titulo),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Regra 1.18: um caso por papel, sem "o resto é limpeza".
                    builder: (_) => switch (d.papel) {
                      'washer' => const WasherHomeScreen(),
                      'handyman' => const HandymanHomeScreen(),
                      _ => const CleanerHomeScreen(),
                    },
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline,
                color: AppColors.textSecondary),
            title: const Text('Juntar outra actividade'),
            subtitle: Text(TvdeVisibilidade.aberto
                ? 'Entregas, corridas, limpeza, lavagem ou Casa'
                : 'Entregas, limpeza, lavagem ou Casa'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TrabalharNoBoraScreen()),
              );
            },
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    ),
  );
}

/// Quantos papéis de trabalho a pessoa tem — decide se o botão sequer aparece.
/// Quem só faz uma coisa não precisa de um botão para saltar para lado nenhum.
int quantosPapeisDeTrabalho(RolesSummary r) =>
    [r.hasDriver, r.cleanerApproved, r.washerApproved, r.handymanApproved]
        .where((x) => x)
        .length;

class _Destino {
  const _Destino(this.papel, this.titulo, this.icone);
  final String papel;
  final String titulo;
  final IconData icone;
}

/// Guarda de coerência: os papéis que este botão sabe abrir têm de ser papéis
/// reais. Se alguém acrescentar um papel novo em `PapelDeTrabalho.conhecidos`
/// sem lhe dar destino aqui, o teste rebenta em vez de o Danilo descobrir no
/// telemóvel que o botão não o leva a lado nenhum.
const papeisComEcraDeTrabalho = <String>{'cleaner', 'washer', 'handyman'};

bool todosOsPapeisComEcraSaoConhecidos() =>
    papeisComEcraDeTrabalho.every(PapelDeTrabalho.conhecidos.contains);
