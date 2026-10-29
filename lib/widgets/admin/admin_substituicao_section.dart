import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/substituicao_service.dart';
import '../../utils/hora_lisboa.dart';

/// Um produto que saiu do pedido por falta (PT-BR no painel).
class ItemTirado {
  const ItemTirado({
    required this.nome,
    required this.quantidade,
    required this.centimos,
  });

  final String nome;
  final int quantidade;

  /// Valor da linha (preço × quantidade), em cêntimos.
  final int centimos;
}

/// Um crédito ao cliente por produto em falta (`wallet_transactions`).
class CreditoPorFalta {
  const CreditoPorFalta({required this.centimos, this.quando});

  final int centimos;
  final String? quando;
}

/// O que o painel mostra de um pedido: a escolha do cliente e o que já saiu.
class DadosSubstituicao {
  const DadosSubstituicao({
    this.preferencia,
    this.itensTirados = const [],
    this.creditos = const [],
  });

  /// `orders.substitution_preference` (ou `null` se o cliente não escolheu).
  final String? preferencia;
  final List<ItemTirado> itensTirados;
  final List<CreditoPorFalta> creditos;

  bool get vazio =>
      preferencia == null && itensTirados.isEmpty && creditos.isEmpty;
}

/// PAINEL ADMIN (PT-BR) — "Se faltar produto" no detalhe do pedido
/// (adendo 5, item 7). Só mostra: a escolha que o cliente fez antes de pagar,
/// os produtos que saíram do pedido por falta e as devoluções já feitas
/// (crédito no saldo registado e o reembolso do pedido, se houver).
///
/// Quem liga e desliga a função é o interruptor `substitution_choice_enabled`
/// (Configurações da plataforma). Pedidos sem escolha e sem produto em falta
/// não mostram nada. Se a leitura falhar, também não: nunca estraga o detalhe.
class AdminSubstituicaoSection extends StatefulWidget {
  const AdminSubstituicaoSection({
    super.key,
    required this.order,
    this.carregar,
  });

  /// O pedido já carregado pelo detalhe (`id`, `items`, `refund_*`).
  final Map<String, dynamic> order;

  /// Só para testes: substitui as leituras ao servidor.
  final Future<DadosSubstituicao> Function()? carregar;

  /// Os produtos marcados "não há" na lista `items` do pedido (cópia local,
  /// usada quando ainda não há linhas do talão).
  static List<ItemTirado> itensTiradosDaLista(Object? items) {
    if (items is! List) return const [];
    final out = <ItemTirado>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final status = raw['purchaseStatus'] ?? raw['purchase_status'];
      if (status != 'unavailable') continue;
      final qtd = (raw['quantity'] ?? raw['qty'] ?? 1);
      final q = qtd is num ? qtd.toInt() : 1;
      final preco = raw['price'];
      final cent = preco is num ? (preco * 100).round() * q : 0;
      out.add(ItemTirado(
        nome: (raw['name'] ?? raw['title'] ?? '—').toString(),
        quantidade: q,
        centimos: cent,
      ));
    }
    return out;
  }

  /// "1,98" → texto de euros com vírgula (PT-BR e PT usam vírgula).
  static String euros(int centimos) =>
      '€${(centimos / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  State<AdminSubstituicaoSection> createState() =>
      _AdminSubstituicaoSectionState();
}

class _AdminSubstituicaoSectionState extends State<AdminSubstituicaoSection> {
  DadosSubstituicao? _dados;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  @override
  void didUpdateWidget(covariant AdminSubstituicaoSection old) {
    super.didUpdateWidget(old);
    if (old.order['id'] != widget.order['id']) _ler();
  }

  Future<DadosSubstituicao> _doServidor() async {
    final sb = Supabase.instance.client;
    final id = widget.order['id'];

    // A escolha do cliente: leitura à parte, para o detalhe do pedido continuar
    // a abrir mesmo antes de a coluna existir no servidor.
    String? pref;
    try {
      final r = await sb
          .from('orders')
          .select('substitution_preference')
          .eq('id', id)
          .maybeSingle();
      pref = r?['substitution_preference'] as String?;
    } catch (e) {
      debugPrint('[AdminSubstituicao] escolha não lida: $e');
    }

    var itens = <ItemTirado>[];
    try {
      final linhas = await sb
          .from('order_purchase_items_v2')
          .select('original_name, original_price_cents, original_qty')
          .eq('order_id', id)
          .eq('status', 'unavailable');
      itens = [
        for (final l in (linhas as List))
          ItemTirado(
            nome: (l['original_name'] ?? '—').toString(),
            quantidade: (l['original_qty'] as num?)?.toInt() ?? 1,
            centimos: ((l['original_price_cents'] as num?)?.toInt() ?? 0) *
                ((l['original_qty'] as num?)?.toInt() ?? 1),
          ),
      ];
    } catch (e) {
      debugPrint('[AdminSubstituicao] itens do talão não lidos: $e');
    }
    if (itens.isEmpty) {
      itens =
          AdminSubstituicaoSection.itensTiradosDaLista(widget.order['items']);
    }

    var creditos = <CreditoPorFalta>[];
    try {
      final linhas = await sb
          .from('wallet_transactions')
          .select('amount_cents, created_at')
          .eq('related_order_id', id)
          .eq('reason', 'storeshopping_v2_unavailable_items');
      creditos = [
        for (final l in (linhas as List))
          CreditoPorFalta(
            centimos: (l['amount_cents'] as num?)?.toInt() ?? 0,
            quando: l['created_at']?.toString(),
          ),
      ];
    } catch (e) {
      debugPrint('[AdminSubstituicao] créditos não lidos: $e');
    }

    return DadosSubstituicao(
        preferencia: pref, itensTirados: itens, creditos: creditos);
  }

  Future<void> _ler() async {
    try {
      final d = await (widget.carregar ?? _doServidor)();
      if (!mounted) return;
      setState(() => _dados = d);
    } catch (e) {
      debugPrint('[AdminSubstituicao] leitura falhou: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    // Sem escolha e sem produto em falta não há nada a mostrar (um reembolso de
    // cancelamento sozinho não é desta secção).
    if (d == null || d.vazio) return const SizedBox.shrink();
    // Reembolso do pedido (colunas que o detalhe já traz): só mostrar.
    final reembolso =
        ((widget.order['refund_amount'] as num?)?.toDouble() ?? 0);

    final escolha = SubstituicaoEscolha.deCodigo(d.preferencia);
    final totalTirado = d.itensTirados.fold<int>(0, (s, i) => s + i.centimos);
    final totalCredito = d.creditos.fold<int>(0, (s, c) => s + c.centimos);
    final refundStatus = widget.order['refund_status'] as String?;
    final refundMethod = widget.order['refund_method'] as String?;
    final refundedAt = widget.order['refunded_at'];

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Card(
        key: const Key('admin_substituicao_cartao'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Se faltar produto',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: Spacing.sm),
              Text(
                'Preferência se faltar produto: '
                '${escolha?.textoAdmin ?? 'o cliente não escolheu'}',
                key: const Key('admin_substituicao_preferencia'),
                style: const TextStyle(fontSize: 13),
              ),
              if (d.itensTirados.isNotEmpty) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  'Produtos tirados do pedido '
                  '(${AdminSubstituicaoSection.euros(totalTirado)}):',
                  key: const Key('admin_substituicao_tirados'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                for (final i in d.itensTirados)
                  Padding(
                    padding: const EdgeInsets.only(left: Spacing.md, top: 2),
                    child: Text(
                      '${i.quantidade}× ${i.nome}'
                      '${i.centimos > 0 ? ' · ${AdminSubstituicaoSection.euros(i.centimos)}' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
              ],
              if (d.creditos.isNotEmpty || reembolso > 0) ...[
                const SizedBox(height: Spacing.sm),
                const Text('Devoluções feitas:',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              if (d.creditos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.md, top: 2),
                  child: Text(
                    'Crédito no saldo Bora por produto em falta: '
                    '${AdminSubstituicaoSection.euros(totalCredito)}'
                    '${d.creditos.first.quando != null ? ' · ${dataHoraLisboa(d.creditos.first.quando)}' : ''}',
                    key: const Key('admin_substituicao_credito'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              if (reembolso > 0)
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.md, top: 2),
                  child: Text(
                    'Reembolso do pedido: '
                    '${AdminSubstituicaoSection.euros((reembolso * 100).round())}'
                    '${refundStatus != null ? ' · $refundStatus' : ''}'
                    '${refundMethod != null ? ' · $refundMethod' : ''}'
                    '${refundedAt != null ? ' · ${dataHoraLisboa(refundedAt)}' : ''}',
                    key: const Key('admin_substituicao_reembolso'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
