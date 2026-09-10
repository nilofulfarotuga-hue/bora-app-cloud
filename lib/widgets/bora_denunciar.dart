import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../screens/support_chat_screen.dart';
import '../services/bloqueio_service.dart';

/// DENUNCIAR CONTEUDO (2026-09-08, missao `ios-lancamento`).
///
/// A directriz 1.2 da App Store exige que uma app com conteudo de utilizadores
/// tenha "a mechanism to report offensive content and timely responses to
/// concerns". A Bora tem chat entre cliente e estafeta e avaliacoes com texto:
/// a moderacao ja existia, mas **so do lado do admin** — nao havia forma de
/// quem usa a app dizer que alguma coisa esta mal.
///
/// Isto nao inventa um canal novo. Abre o **chat de suporte que ja existe**,
/// com a denuncia ja escrita, para a pessoa so ter de enviar. O suporte ja
/// tem visor no painel de admin (`admin_chat_viewer_screen.dart`), por isso a
/// denuncia cai onde alguem a le, em vez de cair numa tabela que ninguem abre.
class BotaoDenunciar extends StatelessWidget {
  const BotaoDenunciar({
    super.key,
    this.orderId,
    this.sobreQuem,
    this.refDoOutro,
    this.onMudou,
  });

  /// Pedido a que a conversa pertence, para o suporte saber do que se trata.
  final String? orderId;

  /// Quem esta a ser denunciado, tal como aparece no ecra ("o estafeta",
  /// "a loja"). Vai no texto, nao serve para bloquear ninguem.
  final String? sobreQuem;

  /// Identificador da pessoa do outro lado. Quando existe, alem de denunciar
  /// pode-se BLOQUEAR — que a directriz 1.2 exige e a Apple nomeou ao recusar
  /// a primeira submissao a 2026-09-10.
  final String? refDoOutro;

  /// Chamado depois de bloquear ou desbloquear, para o ecra se redesenhar.
  final VoidCallback? onMudou;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      tooltip: 'Denunciar ou bloquear'.tr,
      onPressed: () => mostrarFolhaDenuncia(
        context,
        orderId: orderId,
        sobreQuem: sobreQuem,
        refDoOutro: refDoOutro,
        onMudou: onMudou,
      ),
    );
  }
}

/// Motivos oferecidos. Curtos de proposito: quem denuncia esta chateado e nao
/// quer preencher um formulario.
const List<String> _motivos = [
  'Linguagem ofensiva ou insultos',
  'Ameaças ou assédio',
  'Conteúdo sexual ou impróprio',
  'Fraude ou burla',
  'Outro motivo',
];

Future<void> mostrarFolhaDenuncia(
  BuildContext context, {
  String? orderId,
  String? sobreQuem,
  String? refDoOutro,
  VoidCallback? onMudou,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (folha) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Denunciar'.tr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Diga o que se passou. A denúncia vai para o suporte do Bora, que a analisa e responde.'
                    .tr,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Divider(height: 1),
            for (final motivo in _motivos)
              ListTile(
                title: Text(motivo.tr),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.of(folha).pop();
                  final alvo = sobreQuem == null ? '' : ' sobre $sobreQuem';
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupportChatScreen(
                        orderId: orderId,
                        initialMessage:
                            '${'Denúncia'.tr}$alvo: ${motivo.tr}\n\n',
                      ),
                    ),
                  );
                },
              ),
            // BLOQUEAR — a outra metade do que a directriz 1.2 exige.
            if (refDoOutro != null && refDoOutro.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  BloqueioService.estaBloqueado(refDoOutro)
                      ? Icons.lock_open
                      : Icons.block,
                  color: BloqueioService.estaBloqueado(refDoOutro)
                      ? AppColors.textSecondary
                      : Colors.red,
                ),
                title: Text(
                  BloqueioService.estaBloqueado(refDoOutro)
                      ? 'Desbloquear esta pessoa'.tr
                      : 'Bloquear esta pessoa'.tr,
                  style: TextStyle(
                    color: BloqueioService.estaBloqueado(refDoOutro)
                        ? AppColors.textPrimary
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  BloqueioService.estaBloqueado(refDoOutro)
                      ? 'Voltas a ver as mensagens desta pessoa.'.tr
                      : 'Deixas de ver as mensagens desta pessoa.'.tr,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () async {
                  final jaEstava = BloqueioService.estaBloqueado(refDoOutro);
                  final ok = jaEstava
                      ? await BloqueioService.desbloquear(refDoOutro)
                      : await BloqueioService.bloquear(refDoOutro,
                          etiqueta: sobreQuem);
                  if (folha.mounted) Navigator.of(folha).pop();
                  onMudou?.call();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        !ok
                            ? 'Não foi possível concluir. Tenta outra vez.'.tr
                            : jaEstava
                                ? 'Pessoa desbloqueada.'.tr
                                : 'Pessoa bloqueada.'.tr,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Barra que substitui a caixa de escrita quando se bloqueou a pessoa do outro
/// lado. E' a mesma peca nas conversas de TVDE, limpeza e lavagem, para nao
/// haver tres versoes da mesma frase a divergirem com o tempo.
class BarraBloqueado extends StatelessWidget {
  const BarraBloqueado({super.key, required this.refDoOutro, this.onMudou});

  final String refDoOutro;
  final VoidCallback? onMudou;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.block, size: 18, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bloqueaste esta pessoa. Não vês as mensagens dela nem lhe podes escrever.'
                  .tr,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await BloqueioService.desbloquear(refDoOutro);
              onMudou?.call();
            },
            child: Text('Desbloquear'.tr),
          ),
        ],
      ),
    );
  }
}
