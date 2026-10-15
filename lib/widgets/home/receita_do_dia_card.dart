// lib/widgets/home/receita_do_dia_card.dart
//
// Cartão "Receita do dia" da home do cliente (Bora Todo Dia, 15/10/2026).
// Mostra o título e o resumo da receita de hoje; um toque abre a receita com
// os ingredientes, o modo de preparação e o botão "Pôr no carrinho".
// Tudo vem do servidor (`ReceitaService`): desligada, sem função ou sem rede,
// o cartão não aparece. Sem laranja: a home já tem o seu elemento laranja.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../screens/client/receita_do_dia_screen.dart';
import '../../services/receita_service.dart';

class ReceitaDoDiaCard extends StatefulWidget {
  const ReceitaDoDiaCard({super.key, this.carregar});

  /// Lê a receita de hoje. Por omissão, `ReceitaService.instance.hoje`.
  final Future<ReceitaHoje?> Function()? carregar;

  @override
  State<ReceitaDoDiaCard> createState() => _ReceitaDoDiaCardState();
}

class _ReceitaDoDiaCardState extends State<ReceitaDoDiaCard>
    with WidgetsBindingObserver {
  ReceitaHoje? _hoje;
  int _versao = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A app pode ficar aberta de um dia para o outro: ao voltar, relê-se.
    if (state == AppLifecycleState.resumed) unawaited(_carregar());
  }

  Future<void> _carregar() async {
    final minha = ++_versao;
    final h = await (widget.carregar ?? ReceitaService.instance.hoje)();
    if (!mounted || minha != _versao) return;
    setState(() => _hoje = h);
  }

  Future<void> _abrir() async {
    final h = _hoje;
    if (h == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReceitaDoDiaScreen(hoje: h)),
    );
    // O aviso pode ter mudado lá dentro: relê-se.
    if (mounted) unawaited(_carregar());
  }

  @override
  Widget build(BuildContext context) {
    final h = _hoje;
    if (h == null) return const SizedBox.shrink();
    final r = h.receita;
    final meta = [
      if (r.tempoMin != null) '{0} min'.trArgs([r.tempoMin!]),
      '{0} ingredientes'.trArgs([r.ingredientes.length]),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Material(
        key: const Key('receita_do_dia_card'),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _abrir,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppColors.shadowCard,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: r.fotoUrl == null
                        ? const ColoredBox(
                            color: AppColors.primaryWash,
                            child: Icon(Icons.restaurant_menu,
                                color: AppColors.primary, size: 30),
                          )
                        : CachedNetworkImage(
                            imageUrl: r.fotoUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 192,
                            errorWidget: (_, __, ___) => const ColoredBox(
                              color: AppColors.primaryWash,
                              child: Icon(Icons.restaurant_menu,
                                  color: AppColors.primary, size: 30),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receita do dia'.tr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSubtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
