import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/saved_card.dart';
import '../services/card_wallet_service.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Meus Cartões — carteira de cartões guardados do cliente (Carteira Única).
///
/// Mostra só marca + últimos 4 dígitos (nunca o número completo — nem o app
/// nem o servidor lhe têm acesso: o Stripe só devolve `last4`).
///
/// Não há "adicionar cartão" aqui de propósito: os cartões entram guardados
/// pelo próprio checkout, quando o cliente paga com cartão.
class MyCardsScreen extends StatefulWidget {
  const MyCardsScreen({super.key, this.service});

  /// Injectável para testes; em produção usa o singleton.
  final CardWalletService? service;

  @override
  State<MyCardsScreen> createState() => _MyCardsScreenState();
}

class _MyCardsScreenState extends State<MyCardsScreen> {
  CardWalletService get _wallet => widget.service ?? CardWalletService.instance;

  List<SavedCard> _cards = const [];
  bool _loading = true;
  String? _busyCardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cards = await _wallet.listCards();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  Future<void> _setDefault(SavedCard card) async {
    if (card.isDefault) return;
    setState(() => _busyCardId = card.id);
    await _wallet.setDefaultCard(card.id);
    if (!mounted) return;
    setState(() => _busyCardId = null);
    _snack('${card.prettyBrand} •••• ${card.last4} é agora o cartão principal.');
    await _load();
  }

  Future<void> _confirmRemove(SavedCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover cartão?'),
        content: Text(
          'O cartão ${card.prettyBrand} •••• ${card.last4} deixa de estar '
          'guardado. Podes voltar a guardá-lo no próximo pagamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyCardId = card.id);
    try {
      await _wallet.removeCard(card.id);
      if (!mounted) return;
      _snack('Cartão removido.');
    } on CardWalletException catch (e) {
      if (!mounted) return;
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyCardId = null);
    }
    if (mounted) await _load();
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Meus Cartões'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _cards.isEmpty ? _emptyState() : _cardList(),
            ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.xxl),
      children: const [
        SizedBox(height: Spacing.huge),
        Icon(Icons.credit_card_off_outlined,
            size: 56, color: AppColors.textSubtle),
        SizedBox(height: Spacing.lg),
        Text(
          'Ainda não tens cartões guardados',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: Spacing.sm),
        Text(
          'Quando pagares com cartão, guardamo-lo aqui para o pagamento '
          'seguinte ser só um toque.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _cardList() {
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _cards.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.md),
      itemBuilder: (context, i) {
        if (i == _cards.length) return _footerNote();
        return _cardTile(_cards[i]);
      },
    );
  }

  Widget _cardTile(SavedCard card) {
    final busy = _busyCardId == card.id;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
        border: card.isDefault
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.md),
      child: Row(
        children: [
          const Icon(Icons.credit_card, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${card.prettyBrand} •••• ${card.last4}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (card.isDefault) ...[
                      const SizedBox(width: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm, vertical: Spacing.xxs),
                        decoration: BoxDecoration(
                          color: AppColors.primaryWash,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: const Text(
                          'Principal',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  'Validade ${card.prettyExpiry}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Opções do cartão',
              onSelected: (v) {
                if (v == 'default') _setDefault(card);
                if (v == 'remove') _confirmRemove(card);
              },
              itemBuilder: (_) => [
                if (!card.isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Tornar principal'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remover cartão',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _footerNote() {
    return const Padding(
      padding: EdgeInsets.only(top: Spacing.sm, left: Spacing.xs, right: Spacing.xs),
      child: Text(
        'Guardamos apenas a marca e os últimos 4 dígitos. O número completo '
        'fica no Stripe, nunca no Bora.',
        style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
      ),
    );
  }
}
