// PAINEL ADMIN (PT-BR) — Ajustes de peso (missão fecho-pendentes 31/10/2026).
//
// Produtos ao quilo dos mercados NÃO-parceiros (`products.variable_weight`):
// o preço da app é uma estimativa; o estafeta escreve o valor da etiqueta da
// balança (`estafeta_ajustar_peso`) e o cliente paga o valor final, com a
// mesma margem do produto. Cada ajuste fica numa linha de
// `order_weight_adjustments` (um por produto e pedido).
//
// Este ecrã só MOSTRA: lê a RPC `admin_list_weight_adjustments(p_dias, p_limit)`
// e exporta CSV. Não cobra, não devolve, não mexe em dinheiro.
//
// Não confundir: `sold_by_weight` (porções de 200 g dos parceiros, "Ao peso"
// no Catálogo) ≠ `variable_weight` (peso variável dos mercados).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_empty_placeholder.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import 'admin_order_detail_screen.dart';

/// Cêntimos → "1,40 €" (vírgula decimal). Com [comSinal], "+0,17 €" / "-0,20 €".
String eurosAjustePeso(Object? centimos, {bool comSinal = false}) {
  final c = _inteiro(centimos);
  if (c == null) return '—';
  final abs = (c.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
  final sinal = c < 0 ? '-' : (comSinal && c > 0 ? '+' : '');
  return '$sinal$abs €';
}

/// Cêntimos → "1,40" (para o CSV: número com vírgula, sem o símbolo).
String eurosCsvAjustePeso(Object? centimos) {
  final c = _inteiro(centimos);
  if (c == null) return '';
  return (c / 100).toStringAsFixed(2).replaceAll('.', ',');
}

/// Como foi acertada a diferença (`order_weight_adjustments.settled_via`).
const Map<String, String> kAcertosAjustePeso = {
  'dinheiro': 'Dinheiro (acertado em mão com o estafeta)',
  'carteira': 'Carteira Bora do cliente (saldo)',
  'cartao_pendente': 'Cartão — cobrança da diferença pendente',
  'cartao_cobrado': 'Cartão — diferença cobrada',
  'bora_assume': 'A Bora assume a diferença',
  'sem_diferenca': 'Sem diferença',
  'ignorado_nao_ha': 'Ignorado (produto marcado "Não há")',
};

/// Resumo das cobranças da diferença no CARTÃO (02/11/2026, zerar B3), por
/// pedido: "Cartão: 2 pedido(s) cobrado(s) 3,10 € · 1 a cobrar 0,90 € · Bora
/// assumiu 1,20 € (1)". Soma só o que subiu (`delta_client_cents` > 0).
String resumoCobrancasCartaoPeso(Iterable<Map<String, dynamic>> linhas) {
  final porPedido = <String, Map<String, int>>{};
  for (final r in linhas) {
    final via = r['settled_via']?.toString() ?? '';
    if (via != 'cartao_cobrado' && via != 'cartao_pendente' && via != 'bora_assume') {
      continue;
    }
    final d = _inteiro(r['delta_client_cents']) ?? 0;
    final pedido = porPedido.putIfAbsent(via, () => <String, int>{});
    final id = r['order_id']?.toString() ?? '';
    pedido[id] = (pedido[id] ?? 0) + d;
  }
  (int, String) parte(String via) {
    final p = porPedido[via] ?? const <String, int>{};
    final soma = p.values.fold<int>(0, (s, v) => s + (v > 0 ? v : 0));
    return (p.length, eurosAjustePeso(soma));
  }

  final (nCobrado, cobrado) = parte('cartao_cobrado');
  final (nPendente, pendente) = parte('cartao_pendente');
  final (nAssume, assume) = parte('bora_assume');
  return 'Cartão: $nCobrado pedido(s) cobrado(s) $cobrado · '
      '$nPendente a cobrar $pendente · Bora assumiu $assume ($nAssume)';
}

/// `settled_via` em PT-BR; `null` = o pedido ainda não fechou a compra.
String textoAcertoPeso(Object? settledVia) {
  final v = settledVia?.toString() ?? '';
  if (v.isEmpty) return 'Ainda não fechado';
  return kAcertosAjustePeso[v] ?? v;
}

/// Meio de pagamento do pedido em PT-BR.
String textoMeioPagamentoPeso(Object? metodo) {
  final v = metodo?.toString() ?? '';
  switch (v) {
    case '':
      return '—';
    case 'cash':
      return 'Dinheiro';
    case 'mbway':
      return 'MB Way';
    case 'card':
      return 'Cartão';
    case 'wallet':
      return 'Carteira Bora';
    default:
      return v;
  }
}

/// "#a1b2c3d4" — os 8 primeiros caracteres do id do pedido.
String idCurtoPedidoPeso(Object? id) {
  final s = id?.toString() ?? '';
  return s.length > 8 ? s.substring(0, 8) : s;
}

int? _inteiro(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Cor da diferença: a mais para o cliente = azul, a menos = verde, zero = cinza.
Color _corDiferenca(int? delta) {
  if (delta == null || delta == 0) return AppColors.textSecondary;
  return delta > 0 ? AppColors.info : AppColors.success;
}

String _sufixoDiferenca(int? delta) {
  if (delta == null || delta == 0) return '';
  return delta > 0 ? ' (a mais)' : ' (a menos)';
}

class AdminAjustesPesoScreen extends StatefulWidget {
  const AdminAjustesPesoScreen({super.key});

  @override
  State<AdminAjustesPesoScreen> createState() => _AdminAjustesPesoScreenState();
}

class _AdminAjustesPesoScreenState extends State<AdminAjustesPesoScreen> {
  static const _opcoesDias = <int>[7, 30, 90];

  int _dias = 30;
  List<Map<String, dynamic>> _linhas = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_weight_adjustments',
        params: {'p_dias': _dias, 'p_limit': 1000},
      );
      final lista = res is List ? res : const [];
      if (!mounted) return;
      setState(() {
        _linhas = [
          for (final r in lista)
            if (r is Map) Map<String, dynamic>.from(r),
        ];
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  void _abrirPedido(String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminOrderDetailScreen(orderId: orderId)),
    ).then((_) {
      if (mounted) _carregar();
    });
  }

  /// As linhas visíveis, já com os euros e os textos em PT-BR, para o CSV.
  List<Map<String, dynamic>> _linhasCsv() => [
        for (final r in _linhas)
          {
            ...r,
            'est_base_eur': eurosCsvAjustePeso(r['est_base_cents']),
            'real_base_eur': eurosCsvAjustePeso(r['real_base_cents']),
            'est_client_eur': eurosCsvAjustePeso(r['est_client_cents']),
            'new_client_eur': eurosCsvAjustePeso(r['new_client_cents']),
            'delta_client_eur': eurosCsvAjustePeso(r['delta_client_cents']),
            'pagamento': textoMeioPagamentoPeso(r['payment_method']),
            'acerto': textoAcertoPeso(r['settled_via']),
          },
      ];

  static const _colunasCsv = <(String, String)>[
    ('created_at', 'Quando'),
    ('order_id', 'Pedido'),
    ('loja', 'Loja'),
    ('cliente_nome', 'Cliente'),
    ('item_name', 'Produto'),
    ('product_id', 'ID do produto'),
    ('qty', 'Quantidade'),
    ('est_base_eur', 'Caixa previsto (€)'),
    ('real_base_eur', 'Caixa real (€)'),
    ('est_client_eur', 'Cliente previsto (€)'),
    ('new_client_eur', 'Cliente final (€)'),
    ('delta_client_eur', 'Diferença para o cliente (€)'),
    ('pagamento', 'Meio de pagamento'),
    ('acerto', 'Como foi acertado'),
    ('settled_at', 'Acertado em'),
    ('notified_at', 'Cliente avisado em'),
    ('estafeta_nome', 'Estafeta'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Ajustes de peso',
        actions: [
          AdminCsvButton(
            nome: 'ajustes_peso_${_dias}d',
            colunas: _colunasCsv,
            linhas: _linhasCsv,
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  _cartaoExplicacao(),
                  const SizedBox(height: Spacing.sm),
                  _filtroDias(),
                  const SizedBox(height: Spacing.sm),
                  if (_erro != null)
                    _cartaoErro()
                  else if (_linhas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xxl),
                      child: BoraEmptyPlaceholder(
                        icon: Icons.scale_outlined,
                        title: 'Nenhum ajuste de peso',
                        message: 'Nos últimos $_dias dias nenhum estafeta '
                            'escreveu o valor da balança em um produto de peso variável.',
                      ),
                    )
                  else ...[
                    _resumo(),
                    const SizedBox(height: Spacing.sm),
                    for (final r in _linhas) _cartao(r),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _cartaoExplicacao() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Text(
          'Produtos ao quilo dos mercados não-parceiros (peso variável): o '
          'preço da app é uma estimativa; o estafeta escreve o valor da '
          'etiqueta da balança e o cliente paga o valor final, com a mesma '
          'margem do produto. Caixa = o que o estafeta paga na loja; '
          'Cliente = o que o cliente paga. Toque em uma linha para abrir o pedido.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _filtroDias() {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Período:', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final d in _opcoesDias)
          ChoiceChip(
            label: Text('$d dias'),
            selected: _dias == d,
            onSelected: (_) {
              if (_dias == d) return;
              setState(() => _dias = d);
              _carregar();
            },
          ),
      ],
    );
  }

  Widget _cartaoErro() {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xl),
      child: Column(
        children: [
          Text(_erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _carregar,
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }

  Widget _resumo() {
    var aMais = 0;
    var aMenos = 0;
    var porFechar = 0;
    for (final r in _linhas) {
      final d = _inteiro(r['delta_client_cents']) ?? 0;
      if (d > 0) aMais += d;
      if (d < 0) aMenos += d;
      if ((r['settled_via']?.toString() ?? '').isEmpty) porFechar++;
    }
    final cartao = resumoCobrancasCartaoPeso(_linhas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_linhas.length} ajuste(s) · cliente pagou ${eurosAjustePeso(aMais)} a mais '
          'e ${eurosAjustePeso(-aMenos)} a menos · $porFechar ainda não fechado(s)',
          key: const Key('admin_ajustes_peso_resumo'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        // 02/11/2026 (zerar B3): as cobranças da diferença no cartão.
        Text(
          cartao,
          key: const Key('admin_ajustes_peso_cartao'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _linhaValores(String rotulo, Object? previsto, Object? real) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$rotulo: ${eurosAjustePeso(previsto)} previsto → ${eurosAjustePeso(real)} real',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> r) {
    final orderId = r['order_id']?.toString() ?? '';
    final delta = _inteiro(r['delta_client_cents']);
    final acertadoEm = r['settled_at'] == null
        ? ''
        : ' · ${dataHoraLisboa(r['settled_at'])}';
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: orderId.isEmpty ? null : () => _abrirPedido(orderId),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pedido #${idCurtoPedidoPeso(orderId)} · ${r['loja'] ?? '—'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(dataHoraLisboa(r['created_at']), style: pequeno),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${r['qty'] ?? 1}× ${r['item_name'] ?? r['product_id'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Cliente: ${r['cliente_nome'] ?? '—'} · Estafeta: ${r['estafeta_nome'] ?? '—'}',
                style: pequeno,
              ),
              const SizedBox(height: Spacing.xs),
              _linhaValores('Caixa (preço na loja)', r['est_base_cents'], r['real_base_cents']),
              _linhaValores('Cliente paga', r['est_client_cents'], r['new_client_cents']),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Diferença para o cliente: '
                  '${eurosAjustePeso(delta, comSinal: true)}${_sufixoDiferenca(delta)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _corDiferenca(delta),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Pagamento: ${textoMeioPagamentoPeso(r['payment_method'])} · '
                'Acerto: ${textoAcertoPeso(r['settled_via'])}$acertadoEm',
                style: pequeno,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secção "Ajustes de peso" do detalhe do pedido admin: as linhas de
/// `order_weight_adjustments` deste pedido (leitura direta; o admin lê pela
/// política `owa_admin_ve`). Sem linhas — ou se a leitura falhar — não desenha
/// nada: nunca estraga o detalhe.
class AdminAjustesPesoSection extends StatefulWidget {
  const AdminAjustesPesoSection({
    super.key,
    required this.orderId,
    this.carregar,
  });

  final String orderId;

  /// Só para testes: substitui a leitura ao servidor.
  final Future<List<Map<String, dynamic>>> Function()? carregar;

  @override
  State<AdminAjustesPesoSection> createState() => _AdminAjustesPesoSectionState();
}

class _AdminAjustesPesoSectionState extends State<AdminAjustesPesoSection> {
  List<Map<String, dynamic>> _linhas = const [];

  @override
  void initState() {
    super.initState();
    _ler();
  }

  @override
  void didUpdateWidget(covariant AdminAjustesPesoSection old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId) _ler();
  }

  Future<List<Map<String, dynamic>>> _doServidor() async {
    final rows = await Supabase.instance.client
        .from('order_weight_adjustments')
        .select('id, product_id, item_name, qty, est_base_cents, '
            'real_base_cents, est_client_cents, new_client_cents, '
            'delta_client_cents, payment_method, settled_via, settled_at, '
            'notified_at, created_at')
        .eq('order_id', widget.orderId)
        .order('created_at', ascending: true);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<void> _ler() async {
    try {
      final l = await (widget.carregar ?? _doServidor)();
      if (!mounted) return;
      setState(() => _linhas = l);
    } catch (e) {
      debugPrint('[AdminAjustesPeso] leitura do pedido falhou: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_linhas.isEmpty) return const SizedBox.shrink();
    var total = 0;
    for (final r in _linhas) {
      total += _inteiro(r['delta_client_cents']) ?? 0;
    }
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Card(
        key: const Key('admin_ajustes_peso_cartao'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ajustes de peso',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: Spacing.xs),
              const Text(
                'O estafeta escreveu o valor da balança nestes produtos de peso '
                'variável. Caixa = preço na loja; Cliente = o que o cliente paga.',
                style: pequeno,
              ),
              for (final r in _linhas) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  '${r['qty'] ?? 1}× ${r['item_name'] ?? r['product_id'] ?? '—'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Caixa: ${eurosAjustePeso(r['est_base_cents'])} → '
                  '${eurosAjustePeso(r['real_base_cents'])} · Cliente: '
                  '${eurosAjustePeso(r['est_client_cents'])} → '
                  '${eurosAjustePeso(r['new_client_cents'])} '
                  '(${eurosAjustePeso(r['delta_client_cents'], comSinal: true)})',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Pagamento: ${textoMeioPagamentoPeso(r['payment_method'])} · '
                  'Acerto: ${textoAcertoPeso(r['settled_via'])}'
                  '${r['settled_at'] == null ? '' : ' · ${dataHoraLisboa(r['settled_at'])}'}',
                  style: pequeno,
                ),
              ],
              const SizedBox(height: Spacing.sm),
              Text(
                'Diferença total para o cliente: '
                '${eurosAjustePeso(total, comSinal: true)}${_sufixoDiferenca(total)}',
                key: const Key('admin_ajustes_peso_total'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _corDiferenca(total),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
