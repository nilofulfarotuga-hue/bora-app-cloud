import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../utils/hora_lisboa.dart';

/// Painel admin (PT-BR) — Gorjetas (missão 03/10 · bloco 3; taxa da Stripe
/// na missão gorjetas-taxa 30/10/2026).
///
/// Todas as gorjetas: quem deu, a quem, quanto, quando, como foi paga, a taxa
/// da Stripe, quem pagou essa taxa, o líquido para o prestador e o estado.
/// Ligar/desligar (`tips_enabled`), gorjeta do carrinho junto com a compra
/// (`tips_checkout_junto_pagamento`), exportar CSV e reembolsar (Edge Function
/// `charge-tip`, ação `refund`, idempotente).
///
/// Regra do Danilo (30/10/2026): gorjeta dada no carrinho com cartão/MB Way vai
/// no mesmo pagamento da compra, inteira para o prestador. Gorjeta paga depois
/// (avaliação) com cartão/MB Way: o prestador recebe a gorjeta menos a taxa
/// exata da Stripe desse pagamento. Em dinheiro: inteira. A Bora não ganha nada
/// com gorjetas; pedido cancelado → a gorjeta volta inteira ao cliente.
class AdminGorjetasScreen extends StatefulWidget {
  const AdminGorjetasScreen({super.key});

  @override
  State<AdminGorjetasScreen> createState() => _AdminGorjetasScreenState();
}

/// Interruptor da gorjeta do carrinho cobrada junto com a compra (criado pelo
/// servidor na missão de 30/10; começa desligado).
const String kChaveGorjetaJunto = 'tips_checkout_junto_pagamento';

/// Explicação curta (PT-BR) do interruptor, igual aqui e nas Configurações.
const String kExplicacaoGorjetaJunto =
    'Ligado = a gorjeta dada no carrinho com cartão ou MB Way é cobrada junto '
    'com a compra, num pagamento só, e vai inteira para o prestador. '
    'Desligado = é cobrada à parte, como antes (a taxa da Stripe dessa cobrança '
    'à parte fica com a Bora).';

/// Como a gorjeta foi paga: `dinheiro`, `junto_da_compra`,
/// `a_parte_no_carrinho` ou `depois`. Usa a coluna do servidor
/// (`como_foi_paga`); se a função ainda for a antiga, calcula igual.
String comoFoiPagaGorjeta(Map<String, dynamic> l) {
  final s = l['como_foi_paga'];
  if (s is String && s.isNotEmpty) return s;
  if (l['metodo'] == 'cash') return 'dinheiro';
  if (l['cobrada_junto'] == true) return 'junto_da_compra';
  if (l['momento'] == 'checkout') return 'a_parte_no_carrinho';
  return 'depois';
}

/// Quem pagou a taxa da Stripe: `prestador` (paga depois com cartão/MB Way:
/// desconta-se da gorjeta), `bora` (cobrada à parte no carrinho) ou `nenhuma`
/// (junto da compra ou em dinheiro: não há taxa à parte).
String quemPagouTaxaGorjeta(Map<String, dynamic> l) {
  final s = l['quem_pagou_taxa'];
  if (s is String && s.isNotEmpty) return s;
  return switch (comoFoiPagaGorjeta(l)) {
    'depois' => 'prestador',
    'a_parte_no_carrinho' => 'bora',
    _ => 'nenhuma',
  };
}

/// Estimativa da taxa enquanto a Stripe ainda não a deu — a mesma da coluna
/// gerada `tips.liquido_prestador_cents`: 25 cêntimos + 1,5 % (para cima).
int taxaEstimadaGorjetaCents(int valorCents) =>
    25 + (valorCents * 15 + 999) ~/ 1000;

/// O que o prestador recebe, em cêntimos (coluna do servidor; se faltar,
/// calcula igual).
int liquidoGorjetaCents(Map<String, dynamic> l) {
  final v = l['liquido_prestador_cents'];
  if (v is num) return v.toInt();
  final valor = (l['valor_cents'] as num?)?.toInt() ?? 0;
  if (quemPagouTaxaGorjeta(l) != 'prestador') return valor;
  final taxa = (l['taxa_stripe_cents'] as num?)?.toInt() ??
      taxaEstimadaGorjetaCents(valor);
  return valor - taxa < 0 ? 0 : valor - taxa;
}

/// Há taxa à parte mas a Stripe ainda não a deu (o líquido usa a estimativa).
bool taxaPorLerGorjeta(Map<String, dynamic> l) {
  final v = l['taxa_por_ler'];
  if (v is bool) return v;
  return quemPagouTaxaGorjeta(l) != 'nenhuma' && l['taxa_stripe_cents'] == null;
}

/// Rótulos PT-BR de "como foi paga".
const Map<String, String> rotulosComoFoiPaga = {
  'dinheiro': 'em dinheiro',
  'junto_da_compra': 'junto da compra (um pagamento só)',
  'a_parte_no_carrinho': 'à parte no carrinho',
  'depois': 'depois (na avaliação)',
};

/// Rótulos PT-BR de "quem pagou a taxa da Stripe".
const Map<String, String> rotulosQuemPagouTaxa = {
  'prestador': 'paga pelo prestador',
  'bora': 'paga pela Bora',
  'nenhuma': 'sem taxa à parte',
};

String rotuloMetodoGorjeta(Object? m) => switch (m) {
      'card' => 'cartão',
      'mbway' => 'MB Way',
      'cash' => 'dinheiro',
      _ => '${m ?? '-'}',
    };

String rotuloEstadoGorjeta(Object? s) => switch (s) {
      'succeeded' => 'paga',
      'cash_due' => 'em dinheiro (a entregar)',
      'cash_collected' => 'em dinheiro (entregue)',
      'requires_action' => 'à espera do cliente',
      'pending' => 'pendente',
      'failed' => 'falhou',
      'refunded' => 'reembolsada',
      'cancelled' => 'cancelada',
      _ => '${s ?? '-'}',
    };

String eurGorjeta(Object? cents) =>
    '€ ${(((cents as num?) ?? 0) / 100).toStringAsFixed(2)}';

/// Gorjeta que conta nos totais: paga por cartão/MB Way ou entregue em dinheiro.
bool gorjetaPaga(Map<String, dynamic> l) =>
    l['estado'] == 'succeeded' || l['estado'] == 'cash_collected';

typedef TotaisGorjetas = ({
  int pagas,
  int valor,
  int liquido,
  int taxasPrestadores,
  int taxasBora,
  int taxasPorLer,
});

/// Totais do período, só das gorjetas pagas: valor, líquido para os
/// prestadores, taxas da Stripe descontadas aos prestadores (pagas depois) e
/// taxas da Stripe pagas pela Bora (à parte no carrinho; só as já lidas).
TotaisGorjetas totaisGorjetas(List<Map<String, dynamic>> linhas) {
  var pagas = 0, valor = 0, liquido = 0, prest = 0, bora = 0, porLer = 0;
  for (final l in linhas) {
    if (!gorjetaPaga(l)) continue;
    final v = (l['valor_cents'] as num?)?.toInt() ?? 0;
    final liq = liquidoGorjetaCents(l);
    pagas++;
    valor += v;
    liquido += liq;
    switch (quemPagouTaxaGorjeta(l)) {
      case 'prestador':
        prest += v - liq;
      case 'bora':
        bora += (l['taxa_stripe_cents'] as num?)?.toInt() ?? 0;
    }
    if (taxaPorLerGorjeta(l)) porLer++;
  }
  return (
    pagas: pagas,
    valor: valor,
    liquido: liquido,
    taxasPrestadores: prest,
    taxasBora: bora,
    taxasPorLer: porLer,
  );
}

/// Linha da taxa num cartão de gorjeta (PT-BR).
String linhaTaxaGorjeta(Map<String, dynamic> l) {
  final liq = 'líquido para o prestador ${eurGorjeta(liquidoGorjetaCents(l))}';
  final porLer = taxaPorLerGorjeta(l);
  switch (quemPagouTaxaGorjeta(l)) {
    case 'prestador':
      final valor = (l['valor_cents'] as num?)?.toInt() ?? 0;
      final taxa = valor - liquidoGorjetaCents(l);
      return 'Taxa da Stripe ${eurGorjeta(taxa)}'
          '${porLer ? ' (estimada, ainda não lida da Stripe)' : ''}'
          ', ${rotulosQuemPagouTaxa['prestador']} · $liq';
    case 'bora':
      return 'Taxa da Stripe '
          '${porLer ? 'ainda não lida' : eurGorjeta(l['taxa_stripe_cents'])}'
          ', ${rotulosQuemPagouTaxa['bora']} · $liq';
    default:
      return 'Sem taxa à parte · $liq (inteira)';
  }
}

/// Texto do diálogo de reembolso (PT-BR).
String textoReembolsoGorjeta(Map<String, dynamic> l) {
  final base = '${eurGorjeta(l['valor_cents'])} de ${l['cliente_nome']} para '
      '${l['prestador_nome']}. Volta inteira para o cliente.';
  if (comoFoiPagaGorjeta(l) != 'junto_da_compra') return base;
  return '$base\nEsta gorjeta foi cobrada junto da compra: é devolvida em parte '
      'do pagamento do pedido (reembolso parcial — só o valor da gorjeta; o '
      'resto do pedido não muda).';
}

/// Cartão com os totais do período.
class CartaoTotaisGorjetas extends StatelessWidget {
  const CartaoTotaisGorjetas({super.key, required this.totais});

  final TotaisGorjetas totais;

  @override
  Widget build(BuildContext context) {
    const fraco = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${totais.pagas} gorjetas pagas · ${eurGorjeta(totais.valor)} '
              '(últimos 90 dias)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Líquido para os prestadores: ${eurGorjeta(totais.liquido)}'),
            Text('Taxas da Stripe descontadas aos prestadores (gorjetas pagas '
                'depois): ${eurGorjeta(totais.taxasPrestadores)}'),
            Text('Taxas da Stripe pagas pela Bora (gorjetas à parte no '
                'carrinho): ${eurGorjeta(totais.taxasBora)}'),
            if (totais.taxasPorLer > 0)
              Text(
                '${totais.taxasPorLer} com a taxa ainda por ler da Stripe '
                '(conta a estimativa de 25 cêntimos + 1,5 %).',
                style: fraco,
              ),
            const SizedBox(height: 4),
            const Text(
              'A Bora não ganha nada com gorjetas. Taxa da Stripe = tarifa que '
              'a Stripe (empresa dos pagamentos) cobra por cada pagamento.',
              style: fraco,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de uma gorjeta.
class LinhaGorjetaAdmin extends StatelessWidget {
  const LinhaGorjetaAdmin({
    super.key,
    required this.linha,
    this.onReembolsar,
    this.aReembolsar = false,
  });

  final Map<String, dynamic> linha;

  /// null = botão desligado (outro reembolso em curso).
  final VoidCallback? onReembolsar;
  final bool aReembolsar;

  @override
  Widget build(BuildContext context) {
    final l = linha;
    final como = comoFoiPagaGorjeta(l);
    return Card(
      child: ListTile(
        title: Text('${eurGorjeta(l['valor_cents'])} · ${l['cliente_nome']} → '
            '${l['prestador_nome']}'),
        subtitle: Text(
            '${l['alvo'] == 'tvde' ? 'Corrida' : 'Pedido'} '
            '${(l['pedido'] ?? l['corrida'] ?? '').toString().split('-').first}'
            ' · ${rotuloMetodoGorjeta(l['metodo'])}'
            // em dinheiro o método e o estado já o dizem: não repetir
            '${como == 'dinheiro' ? '' : ' · ${rotulosComoFoiPaga[como] ?? como}'}'
            ' · ${rotuloEstadoGorjeta(l['estado'])}'
            '\n${linhaTaxaGorjeta(l)}'
            '\n${dataHoraLisboa(l['criada_em'])}'),
        isThreeLine: true,
        trailing: l['estado'] == 'succeeded'
            ? TextButton(
                onPressed: onReembolsar,
                child: aReembolsar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reembolsar',
                        style: TextStyle(color: AppColors.error)),
              )
            : null,
      ),
    );
  }
}

class _AdminGorjetasScreenState extends State<AdminGorjetasScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = const [];
  bool? _ligada;
  bool? _junto;
  bool _aMudar = false;
  String? _aReembolsar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_listar_gorjetas');
      final flag = await _sb.rpc('get_setting', params: {'p_key': 'tips_enabled'});
      // null = a chave ainda não existe no servidor.
      final junto =
          await _sb.rpc('get_setting', params: {'p_key': kChaveGorjetaJunto});
      if (!mounted) return;
      setState(() {
        _linhas = List<Map<String, dynamic>>.from(res as List);
        _ligada = flag?.toString() == 'true';
        _junto = junto == null ? null : junto.toString() == 'true';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _mudarLigada(bool v) =>
      _gravarInterruptor('tips_enabled', v, (f) => _ligada = f);

  Future<void> _mudarJunto(bool v) =>
      _gravarInterruptor(kChaveGorjetaJunto, v, (f) => _junto = f);

  Future<void> _gravarInterruptor(
      String chave, bool v, void Function(bool) aplicar) async {
    if (_aMudar) return;
    setState(() => _aMudar = true);
    try {
      // 26/10 (melhorias-paridade, item 18): antes era um UPDATE direto à
      // tabela, que só tem política de leitura — mudava 0 linhas e o ecrã
      // dizia que tinha gravado. Agora vai pela função de admin (auditada) e
      // relê-se do servidor: o interruptor mostra o que ficou gravado.
      await _sb.rpc('admin_update_setting',
          params: {'p_key': chave, 'p_value': v});
      final gravado = await _sb.rpc('get_setting', params: {'p_key': chave});
      final ficou = gravado?.toString() == 'true';
      if (mounted) setState(() => aplicar(ficou));
      if (ficou != v) {
        throw StateError('o servidor ficou com ${ficou ? 'ligado' : 'desligado'}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu para mudar: $e')));
      }
    } finally {
      if (mounted) setState(() => _aMudar = false);
    }
  }

  Future<void> _reembolsar(Map<String, dynamic> l) async {
    final id = l['id'] as String;
    if (_aReembolsar != null) return;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reembolsar gorjeta?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(textoReembolsoGorjeta(l)),
            TextField(
              controller: motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reembolsar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aReembolsar = id);
    try {
      final r = await _sb.functions.invoke('charge-tip', body: {
        'action': 'refund',
        'tipId': id,
        'reason': motivo.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((r.data as Map)['ok'] == true
              ? 'Gorjeta reembolsada.'
              : 'Não reembolsou: ${r.data}')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro no reembolso: $e')));
      }
    } finally {
      if (mounted) setState(() => _aReembolsar = null);
    }
  }

  Future<void> _exportar() async {
    if (_linhas.isEmpty) return;
    const cols = [
      'id', 'criada_em', 'paga_em', 'alvo', 'pedido', 'corrida', 'cliente_nome',
      'prestador_nome', 'valor_cents', 'metodo', 'momento', 'estado', 'stripe_pi',
      'taxa_stripe_cents', 'reembolsada_em', 'motivo_reembolso',
    ];
    const extra = [
      'como_foi_paga', 'quem_pagou_taxa', 'liquido_prestador_cents',
      'taxa_por_ler',
    ];
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_gorjetas_$stamp.csv',
      headers: [...cols, ...extra],
      rows: _linhas
          .map((l) => [
                ...cols.map((c) => l[c] ?? ''),
                comoFoiPagaGorjeta(l),
                quemPagouTaxaGorjeta(l),
                liquidoGorjetaCents(l),
                taxaPorLerGorjeta(l),
              ])
          .toList(),
      subject: 'Bora — Gorjetas $stamp',
    );
  }

  @override
  Widget build(BuildContext context) {
    final totais = totaisGorjetas(_linhas);
    final juntoExiste = _junto != null;
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Gorjetas',
        actions: [
          IconButton(
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download),
              onPressed: _exportar),
          IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _carregar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro ao carregar: $_erro')))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SwitchListTile(
                        value: _ligada ?? false,
                        onChanged: _aMudar ? null : _mudarLigada,
                        title: const Text('Gorjetas ligadas na app'),
                        subtitle: const Text(
                            'Checkout, avaliação da entrega e fim da corrida TVDE. '
                            'Desligado = o cliente não vê a opção.'),
                      ),
                      SwitchListTile(
                        value: _junto ?? false,
                        onChanged:
                            (_aMudar || !juntoExiste) ? null : _mudarJunto,
                        title: const Text(
                            'Gorjeta do carrinho junto com a compra'),
                        subtitle: Text(juntoExiste
                            ? kExplicacaoGorjetaJunto
                            : '$kExplicacaoGorjetaJunto\nAinda não existe no '
                                'servidor ($kChaveGorjetaJunto): falta aplicar a '
                                'migração do servidor.'),
                      ),
                      CartaoTotaisGorjetas(totais: totais),
                      if (_linhas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma gorjeta nos últimos 90 dias.'),
                        ),
                      for (final l in _linhas)
                        LinhaGorjetaAdmin(
                          linha: l,
                          aReembolsar: _aReembolsar == l['id'],
                          onReembolsar: _aReembolsar != null
                              ? null
                              : () => _reembolsar(l),
                        ),
                    ],
                  ),
                ),
    );
  }
}
