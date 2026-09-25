import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista (TVDE) — Pagamentos das corridas. Idioma: PT-BR.
///
/// ## Por que esta tela existe (22/09/2026)
///
/// Em 21 e 22/09 sete corridas morreram por causa do pagamento e o Danilo só
/// ficou sabendo das duas que lhe contaram. Os clientes ficaram sem corrida,
/// ninguém ligou para eles, e não havia lugar nenhum no painel onde isso
/// aparecesse. A aba "Não conseguiram pagar" é essa lista — com nome e
/// telefone, para ligar.
///
/// Lê `admin_tvde_pagamentos_list(scope, limite)` — RPC somente leitura.
/// O estorno chama a ação `refund` da Edge `tvde-payment`, que já existia.
class AdminTvdePagamentosScreen extends StatefulWidget {
  const AdminTvdePagamentosScreen({super.key});

  @override
  State<AdminTvdePagamentosScreen> createState() =>
      _AdminTvdePagamentosScreenState();
}

class _AdminTvdePagamentosScreenState extends State<AdminTvdePagamentosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _abas = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _pagos = const [];
  List<Map<String, dynamic>> _falhados = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _abas.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pagos = await _lista('pagos');
      final falhados = await _lista('falhados');
      if (!mounted) return;
      setState(() {
        _pagos = pagos;
        _falhados = falhados;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _lista(String escopo) async {
    final res = await Supabase.instance.client.rpc(
      'admin_tvde_pagamentos_list',
      params: {'p_scope': escopo, 'p_limit': 200},
    );
    if (res is! List) return const [];
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  // ── Estorno ───────────────────────────────────────────────────────────────

  /// Chama a ação `refund` da Edge `tvde-payment` (a que já existe — nenhuma
  /// nova foi inventada). Ela devolve `valor pago menos taxa de cancelamento`
  /// e é idempotente: chamar duas vezes não estorna duas vezes.
  Future<void> _estornar(Map<String, dynamic> corrida) async {
    final valor = ((corrida['final_fare_cents'] ?? corrida['est_fare_cents'])
            as num?) ??
        0;
    final taxa = (corrida['cancel_fee_cents'] as num?) ?? 0;
    final devolve = (valor - taxa).clamp(0, valor) / 100;

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Estornar esta corrida?'),
        content: Text(
          'Vai devolver € ${devolve.toStringAsFixed(2)} ao cliente '
          '(pago € ${(valor / 100).toStringAsFixed(2)}'
          '${taxa > 0 ? ', menos € ${(taxa / 100).toStringAsFixed(2)} de taxa de cancelamento' : ''}).\n\n'
          'Isto mexe em dinheiro de verdade na Stripe e não tem desfazer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Estornar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'tvde-payment',
        body: {'action': 'refund', 'ride_id': corrida['id']},
      );
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      if (body['error'] != null) {
        _aviso('Não deu certo: ${body['error']}', erro: true);
        return;
      }
      if (body['already'] == true) {
        _aviso('Esta corrida já tinha sido estornada antes.');
      } else if (body['noop'] == true) {
        _aviso('Não havia cobrança para estornar nesta corrida.');
      } else {
        final c = ((body['refundCents'] as num?) ?? 0) / 100;
        _aviso('Estornado € ${c.toStringAsFixed(2)}. '
            'Novo estado: ${body['paymentStatus']}');
      }
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _aviso('Não deu certo: $e', erro: true);
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pagamentos das corridas',
        bottom: TabBar(
          controller: _abas,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSubtle,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Pagos'),
            Tab(text: 'Não conseguiram pagar (${_falhados.length})'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _carregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _Falha(erro: _erro!, aoTentar: _carregar)
              : TabBarView(
                  controller: _abas,
                  children: [
                    _Lista(
                      linhas: _pagos,
                      vazio: 'Nenhuma corrida paga por cartão ou MB Way ainda.',
                      construir: (c) => _CartaoPago(
                        corrida: c,
                        aoEstornar: () => _estornar(c),
                      ),
                    ),
                    _Lista(
                      linhas: _falhados,
                      vazio:
                          'Ninguém ficou sem conseguir pagar. É assim que tem '
                          'que ser.',
                      cabecalho: 'Estes clientes tentaram pagar e a corrida '
                          'morreu. Ninguém foi cobrado. Vale a pena ligar.',
                      construir: (c) => _CartaoFalhado(corrida: c),
                    ),
                  ],
                ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.linhas,
    required this.vazio,
    required this.construir,
    this.cabecalho,
  });

  final List<Map<String, dynamic>> linhas;
  final String vazio;
  final String? cabecalho;
  final Widget Function(Map<String, dynamic>) construir;

  @override
  Widget build(BuildContext context) {
    if (linhas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(vazio,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSubtle)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: linhas.length + (cabecalho == null ? 0 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) {
        if (cabecalho != null && i == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(cabecalho!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          );
        }
        return construir(linhas[i - (cabecalho == null ? 0 : 1)]);
      },
    );
  }
}

String _quando(Map<String, dynamic> c) {
  final t = DateTime.tryParse((c['created_at'] as String?) ?? '')?.toLocal();
  if (t == null) return '';
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(t.day)}/${dd(t.month)} ${dd(t.hour)}:${dd(t.minute)}';
}

String _euros(num? cents) => '€ ${((cents ?? 0) / 100).toStringAsFixed(2)}';

/// PT-BR com o termo técnico entre parênteses, como o Danilo pediu.
String _estadoEmPortugues(String? estado) => switch (estado) {
      'succeeded' => 'Pago',
      'processing' => 'Processando (a Stripe ainda está confirmando)',
      'refunded' => 'Estornado por inteiro',
      'partial_refund' => 'Estornado em parte',
      'kept_cancel_fee' => 'Ficou só a taxa de cancelamento',
      'requires_payment_method' => 'Cliente não chegou a pôr o cartão',
      'requires_action' => 'Banco pediu confirmação e ela não veio (3-D Secure)',
      _ => estado ?? '—',
    };

String _motivoEmPortugues(String? motivo) => switch (motivo) {
      'payment_failed' => 'Pagamento não concluído',
      'payment_abandoned' => 'Cliente fechou a tela de pagamento',
      'payment_timeout' => 'Expirou (limpeza automática do sistema)',
      _ => motivo ?? '—',
    };

class _CartaoPago extends StatelessWidget {
  const _CartaoPago({required this.corrida, required this.aoEstornar});

  final Map<String, dynamic> corrida;
  final VoidCallback aoEstornar;

  @override
  Widget build(BuildContext context) {
    final estado = corrida['payment_status'] as String?;
    final jaEstornado = estado == 'refunded' ||
        estado == 'partial_refund' ||
        estado == 'kept_cancel_fee';
    final pi = corrida['payment_intent_id'] as String?;

    return _Caixa(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${corrida['client_name']?.toString().isNotEmpty == true ? corrida['client_name'] : 'Sem nome'} · ${_quando(corrida)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ),
            Text(
                _euros((corrida['final_fare_cents'] ??
                    corrida['est_fare_cents']) as num?),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${corrida['payment_method'] == 'card' ? 'Cartão' : 'MB Way'} · ${_estadoEmPortugues(estado)}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        Text('${corrida['origin_label'] ?? '?'} → ${corrida['dest_label'] ?? '?'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        if (pi != null && pi.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pi));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Código da cobrança copiado.')));
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.copy, size: 12, color: AppColors.textSubtle),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('cobrança (PaymentIntent) $pi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSubtle)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: jaEstornado ? null : aoEstornar,
            icon: const Icon(Icons.undo, size: 16),
            label: Text(jaEstornado ? 'Já estornado' : 'Estornar'),
          ),
        ),
      ],
    );
  }
}

class _CartaoFalhado extends StatelessWidget {
  const _CartaoFalhado({required this.corrida});

  final Map<String, dynamic> corrida;

  @override
  Widget build(BuildContext context) {
    final telefone = (corrida['client_phone'] as String?) ?? '';

    return _Caixa(
      borda: AppColors.warning,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${corrida['client_name']?.toString().isNotEmpty == true ? corrida['client_name'] : 'Sem nome'} · ${_quando(corrida)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ),
            Text(_euros(corrida['est_fare_cents'] as num?),
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${corrida['payment_method'] == 'card' ? 'Cartão' : 'MB Way'} · ${_motivoEmPortugues(corrida['cancel_reason'] as String?)}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        Text(_estadoEmPortugues(corrida['payment_status'] as String?),
            style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        Text('${corrida['origin_label'] ?? '?'} → ${corrida['dest_label'] ?? '?'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        if (telefone.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              const Icon(Icons.phone, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(telefone,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: telefone));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Telefone copiado.')));
                },
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copiar'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({required this.children, this.borda});

  final List<Widget> children;
  final Color? borda;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: borda ?? AppColors.divider),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Falha extends StatelessWidget {
  const _Falha({required this.erro, required this.aoTentar});

  final String erro;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: AppColors.error),
              const SizedBox(height: Spacing.md),
              Text('Não deu para carregar.\n$erro',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.md),
              FilledButton(
                  onPressed: aoTentar, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
}
