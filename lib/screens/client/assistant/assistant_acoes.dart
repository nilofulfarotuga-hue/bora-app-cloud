// AÇÕES DO ASSISTENTE / AMIGO (09/11/2026, missão m11-amigo-rosto).
//
// O que acontece quando o cliente toca num cartão ou num botão de uma
// resposta (encher o carrinho, pedir um Favor, abrir a carteira, a deixa...).
// Era código do ecrã de conversa (assistant_chat_screen.dart); passou para
// aqui, sem mudar o comportamento, para o ecrã do rosto do Amigo
// (amigo_screen.dart) fazer exatamente o mesmo.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../services/tvde_visibilidade.dart';
import '../../../utils/home_destino.dart';
import '../../../widgets/bora_support_sheet.dart';
import '../../errand_form_screen.dart';
import '../../orders_screen.dart';
import '../../wallet_history_screen.dart';
import '../cleaning/cleaning_wizard_screen.dart';
import '../tvde/tvde_entrada_screen.dart';
import 'assistant_cards.dart';
import 'assistant_encher_carrinho.dart';

mixin AssistantAcoesMixin<T extends StatefulWidget> on State<T> {
  /// A proposta a ser posta no carrinho agora (mostra o "a carregar").
  String? aEncherId;

  /// As respostas já mostradas nesta conversa (para "Sim, repete").
  Iterable<AssistantReply> get respostasMostradas;

  /// Envia um texto ao assistente (confirmar a lista lida, botões genéricos).
  Future<void> enviarAoAssistente(String texto);

  void snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// A proposta com este id numa resposta já mostrada (para "Sim, repete").
  AssistantProposal? propostaNaConversa(String id) {
    for (final r in respostasMostradas.toList().reversed) {
      for (final p in r.propostas) {
        if (p.proposalId == id) return p;
      }
    }
    return null;
  }

  Future<void> encher(AssistantProposal p) async {
    if (aEncherId != null) return;
    setState(() => aEncherId = p.proposalId);
    try {
      await encherCarrinhoDaProposta(context, p);
    } finally {
      if (mounted) setState(() => aEncherId = null);
    }
  }

  void pedirFavor(List<AssistantFavor> favores) {
    final desc = favores
        .map((f) => f.quantity > 1 ? '${f.quantity}× ${f.query}' : f.query)
        .join(', ');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ErrandFormScreen(
          prefill: ErrandPrefill(
            description: 'Comprar: {0}'.trArgs([desc]),
            location: '',
            hasPurchase: true,
          ),
        ),
      ),
    );
  }

  Future<void> tocarDeixa(AssistantDeixa d) async {
    unawaited(AssistantService.deixaClicada(d.id));
    final destino = d.acaoDestino?.trim() ?? '';
    switch (d.acaoTipo) {
      case 'abrir_loja':
        if (destino.isNotEmpty) await abrirLojaPorId(context, destino);
      case 'abrir_carteira':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WalletHistoryScreen()));
      case 'abrir_checkin':
        // O check-in vive no topo da página inicial.
        Navigator.of(context).popUntil((r) => r.isFirst);
      case 'abrir_faixa':
        try {
          final m = jsonDecode(destino);
          if (m is Map) {
            await abrirDestino(context,
                tipo: (m['tipo_destino'] ?? '').toString(),
                destino: (m['destino'] ?? '').toString());
          }
        } catch (_) {}
    }
  }

  Future<void> acao(AssistantAcao a) async {
    final d = a.destino?.trim() ?? '';
    switch (a.tipo) {
      case 'abrir_pedido':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OrdersScreen()));
      case 'abrir_carteira':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WalletHistoryScreen()));
      case 'abrir_favores':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ErrandFormScreen(
              prefill: d.isEmpty
                  ? null
                  : ErrandPrefill(description: d, location: '', hasPurchase: true),
            ),
          ),
        );
      case 'abrir_tvde':
        // 04/11/2026: Bora Motorista fechado → não abre nada.
        if (!TvdeVisibilidade.aberto) return;
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TvdeEntradaScreen()));
      // Amigo Bora (08/11/2026): a compra acaba numa ação, com uma confirmação.
      case 'repetir_habitual':
        final p = propostaNaConversa(d);
        if (p != null) {
          await encher(p);
        } else {
          snack('Esta proposta já não está disponível.'.tr);
        }
      case 'pedir_favor':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ErrandFormScreen(
              prefill: ErrandPrefill(
                  description: d, location: '', hasPurchase: true),
            ),
          ),
        );
      case 'marcar_limpeza':
        if (d.isNotEmpty) snack('Na marcação escolhe: {0}'.trArgs([d]));
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CleaningWizardScreen()));
      case 'suporte_humano':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const BoraSupportSheet(showAgentCard: false),
        );
      case 'confirmar_lista':
        if (d.isNotEmpty) await enviarAoAssistente(d);
      case 'abrir_loja':
        if (d.isNotEmpty) await abrirLojaPorId(context, d);
      default:
        if (d.isNotEmpty) await enviarAoAssistente(d);
    }
  }
}

/// Os cartões de uma resposta (sem o texto): comparação, lista lida,
/// propostas, divisão, Favores, botões e a deixa. O ecrã de conversa põe o
/// texto num balão por cima; o ecrã do rosto põe-no na legenda.
class AssistantCartoesDaResposta extends StatelessWidget {
  const AssistantCartoesDaResposta({
    super.key,
    required this.reply,
    required this.aEncherId,
    required this.onEncher,
    required this.onFavor,
    required this.onAcao,
    required this.onConfirmarLista,
    required this.onDeixa,
    this.mostrarDeixa = true,
  });

  /// O ecrã do rosto mostra a deixa num cartão próprio, por baixo da legenda.
  final bool mostrarDeixa;
  final AssistantReply reply;
  final String? aEncherId;
  final void Function(AssistantProposal) onEncher;
  final void Function(List<AssistantFavor>) onFavor;
  final void Function(AssistantAcao) onAcao;
  final void Function(String) onConfirmarLista;
  final void Function(AssistantDeixa) onDeixa;

  @override
  Widget build(BuildContext context) {
    final r = reply;
    final lista = r.listaExtraida;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.comparacao != null) AssistantComparacaoCard(comparacao: r.comparacao!),
        if (lista != null && lista.isNotEmpty)
          AssistantListaExtraidaCard(itens: lista, onConfirmar: onConfirmarLista),
        for (final p in r.propostas)
          AssistantProposalCard(
            proposta: p,
            aEncher: aEncherId == p.proposalId,
            onEncher: () => onEncher(p),
          ),
        if (r.divisao != null)
          AssistantDivisaoCard(
            divisao: r.divisao!,
            aEncherId: aEncherId,
            onEncher: onEncher,
          ),
        if (r.favores.isNotEmpty)
          AssistantFavoresCard(
            favores: r.favores,
            preco: r.favorPreco,
            onPedir: () => onFavor(r.favores),
          ),
        AssistantAcoesChips(acoes: r.acoes, onTap: onAcao),
        if (mostrarDeixa && r.deixa != null) AmigoDeixaLinha(deixa: r.deixa!, onTap: () => onDeixa(r.deixa!)),
      ],
    );
  }
}

