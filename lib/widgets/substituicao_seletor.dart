import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/order_service_type.dart';
import '../services/substituicao_service.dart';

/// "Se faltar um produto" — a pergunta do ecrã de pagamento (adendo 5, item 7).
///
/// Só aparece em mercados que não são parceiros e em Favores com compra, e só
/// com o interruptor `substitution_choice_enabled` ligado. Desligado, ou
/// noutro tipo de pedido, não desenha nada (nem espaço).
///
/// A escolha fica em [SubstituicaoService.pendente]; quem cria o pedido chama
/// `gravarPendenteEmSegundoPlano(orderId)` quando o pedido tem id real. Nunca
/// bloqueia o pagamento: sem escolha, o pedido segue como sempre.
class SubstituicaoSeletor extends StatefulWidget {
  const SubstituicaoSeletor({
    super.key,
    required this.serviceType,
    required this.lojaParceira,
    this.favorComLista = false,
    this.servico,
  });

  final OrderServiceType serviceType;
  final bool lojaParceira;

  /// Favor com compra (o cliente escreveu o que o estafeta tem de comprar).
  final bool favorComLista;

  /// Só para testes.
  final SubstituicaoService? servico;

  @override
  State<SubstituicaoSeletor> createState() => _SubstituicaoSeletorState();
}

class _SubstituicaoSeletorState extends State<SubstituicaoSeletor> {
  bool _visivel = false;
  bool _mexeu = false;
  SubstituicaoEscolha? _escolha;

  SubstituicaoService get _servico =>
      widget.servico ?? SubstituicaoService.instance;

  bool get _aplica => substituicaoAplica(
        serviceType: widget.serviceType,
        lojaParceira: widget.lojaParceira,
        favorComLista: widget.favorComLista,
      );

  @override
  void initState() {
    super.initState();
    if (_aplica) unawaited(_carregar());
  }

  Future<void> _carregar() async {
    final servico = _servico;
    final ligada = await servico.ligada();
    if (!ligada || !mounted) return;
    final guardada = await servico.escolhaGuardada();
    if (!mounted) return;
    setState(() {
      _visivel = true;
      // A última escolha pré-marca; nunca desfaz uma escolha já feita.
      if (!_mexeu) _escolha = guardada;
    });
    servico.definirPendente(this, _escolha);
  }

  void _escolher(SubstituicaoEscolha e) {
    setState(() {
      _mexeu = true;
      _escolha = e;
    });
    _servico.definirPendente(this, e);
  }

  @override
  void dispose() {
    _servico.largarPendente(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visivel || !_aplica) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: SubstituicaoCard(escolha: _escolha, onChanged: _escolher),
    );
  }
}

/// O cartão com as três opções (sem estado próprio: quem o usa guarda a escolha).
class SubstituicaoCard extends StatelessWidget {
  const SubstituicaoCard({
    super.key,
    required this.escolha,
    required this.onChanged,
  });

  final SubstituicaoEscolha? escolha;
  final ValueChanged<SubstituicaoEscolha> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('substituicao_cartao'),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Se faltar um produto'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            'Escolhe agora. Guardamos a tua escolha para a próxima vez.'.tr,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.sm),
          for (final e in SubstituicaoEscolha.values)
            _Opcao(
              chave: Key('substituicao_opcao_${e.codigo}'),
              escolha: e,
              marcada: e == escolha,
              onTap: () => onChanged(e),
            ),
        ],
      ),
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({
    required this.chave,
    required this.escolha,
    required this.marcada,
    required this.onTap,
  });

  final Key chave;
  final SubstituicaoEscolha escolha;
  final bool marcada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: marcada,
      button: true,
      label: escolha.titulo,
      child: InkWell(
        key: chave,
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                marcada
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: marcada ? AppColors.primary : AppColors.textSubtle,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      escolha.titulo,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      escolha.explicacao,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A linha do estafeta, no topo da lista de compras (laranja). Sem escolha do
/// cliente não desenha nada, por isso pedidos antigos ficam exatamente como
/// estavam.
class SubstituicaoLinhaEstafeta extends StatelessWidget {
  const SubstituicaoLinhaEstafeta({super.key, required this.preferencia});

  /// `orders.substitution_preference` (`trocar`, `tirar_devolver`, `ligar`).
  final String? preferencia;

  @override
  Widget build(BuildContext context) {
    final escolha = SubstituicaoEscolha.deCodigo(preferencia);
    if (escolha == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Container(
        key: const Key('substituicao_linha_estafeta'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.swap_horiz, size: 18, color: AppColors.accentDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                escolha.fraseEstafeta,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
