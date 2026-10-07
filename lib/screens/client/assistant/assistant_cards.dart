// BORA ASSISTENTE (07/10/2026) — os cartões que o assistente desenha na
// conversa: proposta de carrinho por loja, divisão em 2 lojas, favores,
// lista extraída de uma foto e chips de acção.
//
// Só desenham o que o servidor devolveu: nenhum valor é calculado aqui.
// Um laranja por cartão: o botão "Encher o carrinho" (acção principal).

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/maior_18.dart';

String _eur(double v) => '€${v.toStringAsFixed(2)}';
String _eurCents(int c) => '€${(c / 100).toStringAsFixed(2)}';

/// Cartão de uma proposta de carrinho (uma loja).
class AssistantProposalCard extends StatelessWidget {
  const AssistantProposalCard({
    super.key,
    required this.proposta,
    required this.onEncher,
    this.aEncher = false,
    this.compacto = false,
  });

  final AssistantProposal proposta;
  final VoidCallback? onEncher;
  final bool aEncher;

  /// Dentro do cartão de divisão: sem sombra, sem poupança própria.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final p = proposta;
    final badgeCor = p.isPartner ? AppColors.primary : AppColors.info;
    final badgeTxt = p.isPartner ? 'Parceiro'.tr : 'Mercado'.tr;
    return Container(
      margin: EdgeInsets.only(top: compacto ? 8 : 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.rank == 1 && !compacto
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
        boxShadow: compacto
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  p.restaurantName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Badge(texto: badgeTxt, cor: badgeCor),
            ],
          ),
          if (!p.open)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: AppColors.error),
                  const SizedBox(width: 6),
                  Text(
                    'Fechada agora'.tr,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          if (p.coveragePct < 100)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tem {0}% da tua lista'.trArgs([p.coveragePct.round()]),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 10),
          for (final it in p.items) _ItemLinha(item: it),
          for (final m in p.missingItems) _FaltaLinha(item: m),
          const Divider(height: 20),
          _Parcela(rotulo: 'Subtotal'.tr, valor: p.subtotal),
          _Parcela(rotulo: 'Entrega'.tr, valor: p.deliveryFee),
          _Parcela(rotulo: 'Taxa de serviço'.tr, valor: p.serviceFee),
          if (p.smallOrderFee > 0)
            _Parcela(rotulo: 'Taxa de pedido pequeno'.tr, valor: p.smallOrderFee),
          if (p.bagFee > 0) _Parcela(rotulo: 'Sacos'.tr, valor: p.bagFee),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total'.tr,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                _eur(p.customerTotal),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          if (p.savingsCents > 0 && !compacto)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Poupas {0} face à loja mais cara'
                          .trArgs([_eurCents(p.savingsCents)]),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (p.hasMaior18)
            Maior18Aviso(
              margin: const EdgeInsets.only(top: 10),
              texto: '+18: o estafeta pede documento na entrega.'.tr,
            ),
          const SizedBox(height: 12),
          BoraAccentButton(
            label: 'Encher o carrinho'.tr,
            icon: Icons.shopping_cart_outlined,
            loading: aEncher,
            onPressed: onEncher,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.texto, required this.cor});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor),
      ),
    );
  }
}

class _ItemLinha extends StatelessWidget {
  const _ItemLinha({required this.item});
  final AssistantItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Foto(url: item.photoUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                Row(
                  children: [
                    Text(
                      '{0}× {1}'.trArgs([item.quantity, _eur(item.unitPrice)]),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (item.maior18) ...[
                      const SizedBox(width: 6),
                      const Maior18Badge(small: true),
                    ],
                  ],
                ),
                if (item.parecido)
                  Text(
                    'Parecido — confirma'.tr,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _eur(item.lineTotal),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  const _Foto({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget vazio = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.shopping_basket_outlined,
          size: 18, color: AppColors.textSubtle),
    );
    if (u == null || u.isEmpty) return vazio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        u,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => vazio,
      ),
    );
  }
}

class _FaltaLinha extends StatelessWidget {
  const _FaltaLinha({required this.item});
  final AssistantMissingItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.remove_shopping_cart_outlined,
                size: 18, color: AppColors.textSubtle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sem {0} ({1}×) nesta loja'.trArgs([item.query, item.quantity]),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSubtle,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Parcela extends StatelessWidget {
  const _Parcela({required this.rotulo, required this.valor});
  final String rotulo;
  final double valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Text(_eur(valor),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Cartão "Dividir em 2 lojas".
class AssistantDivisaoCard extends StatelessWidget {
  const AssistantDivisaoCard({
    super.key,
    required this.divisao,
    required this.onEncher,
    this.aEncherId,
  });

  final AssistantDivisao divisao;
  final void Function(AssistantProposal parte) onEncher;
  final String? aEncherId;

  @override
  Widget build(BuildContext context) {
    final d = divisao;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dividir em 2 lojas'.tr,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              Text(
                _eur(d.customerTotal),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          if (d.savingsVsBestSingleCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Poupas {0} face à melhor loja sozinha (2 entregas)'
                    .trArgs([_eurCents(d.savingsVsBestSingleCents)]),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          for (final parte in d.parts)
            AssistantProposalCard(
              proposta: parte,
              compacto: true,
              aEncher: aEncherId == parte.proposalId,
              onEncher: () => onEncher(parte),
            ),
        ],
      ),
    );
  }
}

/// Cartão de Favores (o que só um estafeta consegue ir buscar).
class AssistantFavoresCard extends StatelessWidget {
  const AssistantFavoresCard({
    super.key,
    required this.favores,
    required this.preco,
    required this.onPedir,
  });

  final List<AssistantFavor> favores;
  final AssistantFavorPreco? preco;
  final VoidCallback onPedir;

  @override
  Widget build(BuildContext context) {
    final p = preco;
    final temMaior18 = favores.any((f) => f.maior18);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Pedir como Favor'.tr,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Isto não está em nenhuma loja da app — um estafeta vai buscar por ti.'
                .tr,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final f in favores)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('{0}× {1}'.trArgs([f.quantity, f.query]),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  if (f.maior18) const Maior18Badge(small: true),
                ],
              ),
            ),
          if (p != null && p.available) ...[
            const SizedBox(height: 8),
            _Parcela(rotulo: 'Normal · até {0} min'.trArgs([p.normalSlaMinutes]), valor: p.normalFee),
            _Parcela(rotulo: 'Expresso · até {0} min'.trArgs([p.expressSlaMinutes]), valor: p.expressFee),
            if (p.maxAdvanceCents > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'O estafeta adianta até {0}; acertas pelo talão.'
                      .trArgs([_eurCents(p.maxAdvanceCents)]),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSubtle),
                ),
              ),
          ],
          if (p != null && !p.available)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Favores indisponíveis de momento.'.tr,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
            ),
          if (temMaior18)
            Maior18Aviso(
              margin: const EdgeInsets.only(top: 10),
              texto: '+18: o estafeta pede documento na entrega.'.tr,
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: (p == null || p.available) ? onPedir : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.directions_run),
            label: Text('Pedir como Favor'.tr),
          ),
        ],
      ),
    );
  }
}

/// Lista extraída de uma foto: chips para confirmar/editar e reenviar.
class AssistantListaExtraidaCard extends StatefulWidget {
  const AssistantListaExtraidaCard({
    super.key,
    required this.itens,
    required this.onConfirmar,
  });

  final List<AssistantMissingItem> itens;
  final void Function(String mensagem) onConfirmar;

  @override
  State<AssistantListaExtraidaCard> createState() =>
      _AssistantListaExtraidaCardState();
}

class _AssistantListaExtraidaCardState
    extends State<AssistantListaExtraidaCard> {
  late List<AssistantMissingItem> _itens;

  @override
  void initState() {
    super.initState();
    _itens = List.of(widget.itens);
  }

  String get _mensagem => _itens
      .map((i) => i.quantity > 1 ? '${i.quantity}× ${i.query}' : i.query)
      .join(', ');

  Future<void> _editar(int i) async {
    final ctrl = TextEditingController(text: _itens[i].query);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Corrigir artigo'.tr),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('Guardar'.tr)),
        ],
      ),
    );
    if (novo == null || novo.isEmpty || !mounted) return;
    setState(() {
      _itens[i] = AssistantMissingItem(query: novo, quantity: _itens[i].quantity);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Li isto na tua lista — confirma ou corrige:'.tr,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _itens.length; i++)
                InputChip(
                  label: Text(_itens[i].quantity > 1
                      ? '${_itens[i].quantity}× ${_itens[i].query}'
                      : _itens[i].query),
                  onPressed: () => _editar(i),
                  onDeleted: () => setState(() => _itens.removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed:
                _itens.isEmpty ? null : () => widget.onConfirmar(_mensagem),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.check),
            label: Text('Confirmar lista'.tr),
          ),
        ],
      ),
    );
  }
}

/// Chips de acção sugeridos pelo assistente.
class AssistantAcoesChips extends StatelessWidget {
  const AssistantAcoesChips({
    super.key,
    required this.acoes,
    required this.onTap,
  });

  final List<AssistantAcao> acoes;
  final void Function(AssistantAcao acao) onTap;

  static IconData icone(String tipo) {
    switch (tipo) {
      case 'abrir_pedido':
        return Icons.receipt_long_outlined;
      case 'abrir_carteira':
        return Icons.account_balance_wallet_outlined;
      case 'abrir_favores':
        return Icons.directions_run;
      case 'abrir_tvde':
        return Icons.local_taxi_outlined;
      case 'suporte_humano':
        return Icons.support_agent;
      case 'confirmar_lista':
        return Icons.checklist;
      case 'abrir_loja':
        return Icons.storefront_outlined;
    }
    return Icons.arrow_forward;
  }

  @override
  Widget build(BuildContext context) {
    if (acoes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in acoes)
            ActionChip(
              avatar: Icon(icone(a.tipo), size: 16, color: AppColors.primaryDark),
              label: Text(a.rotulo),
              onPressed: () => onTap(a),
              side: const BorderSide(color: AppColors.primaryLight),
              backgroundColor: AppColors.primaryWash,
            ),
        ],
      ),
    );
  }
}

/// Estado vazio do chat: 3 sugestões clicáveis.
class AssistantEmptyState extends StatelessWidget {
  const AssistantEmptyState({super.key, required this.onSugestao});

  final void Function(String texto) onSugestao;

  static const List<String> sugestoes = [
    'arroz, leite, ovos, azeite',
    'quero um cheeseburger',
    'o de sempre',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 36, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 16),
            Text(
              'Diz-me o que precisas'.tr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Escreve a lista, dita por voz ou manda uma foto. Eu procuro nas lojas da Guarda e mostro-te onde fica mais barato.'
                  .tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            for (final s in sugestoes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onSugestao(s),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(s),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
