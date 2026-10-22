import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/admin/confirmar_dinheiro.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../utils/hora_lisboa_ext.dart';
import 'tvde_conformidade/_comum.dart' show tvdeCsv, tvdeGuardarCsvPadrao;

/// Bora Motorista (TVDE) — Histórico de cancelamentos (PT-BR).
///
/// Espelha o histórico de cancelamentos do DELIVERY
/// (`admin_cancellations_screen.dart`), mas para corridas de passageiros.
///
/// Lê a RPC `admin_tvde_cancellations(p_limit)` (read-only, aditiva). Construído
/// defensivamente: se a migration ainda não foi aplicada e a RPC não existir em
/// runtime, o FutureBuilder trata o erro e mostra um aviso amigável — nunca
/// tela branca nem crash.
///
/// 17/10/2026 (cancelamento tardio, "autorizo" do Danilo às 13:50): se o
/// cliente cancela mais de 3 min depois de o motorista aceitar, paga a corrida
/// inteira e o motorista recebe 3,75 € de compensação. Este ecrã passou a:
/// juntar as compensações (`admin_tvde_cancel_comps`, numa segunda chamada que
/// NUNCA estraga a primeira), mostrar o resumo no topo, deixar o admin
/// compensar à mão (`admin_tvde_cancel_comp_grant`) e exportar CSV. O texto
/// antigo "corridas em dinheiro, sem reembolso" saiu: já há corridas pagas
/// online; o método e o estado do pagamento aparecem só onde há dados.
class AdminTvdeCancellationsScreen extends StatefulWidget {
  const AdminTvdeCancellationsScreen({super.key});

  @override
  State<AdminTvdeCancellationsScreen> createState() =>
      _AdminTvdeCancellationsScreenState();
}

class _AdminTvdeCancellationsScreenState
    extends State<AdminTvdeCancellationsScreen> {
  late Future<DadosCancelamentos> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DadosCancelamentos> _load() async {
    final sb = Supabase.instance.client;
    final res =
        await sb.rpc('admin_tvde_cancellations', params: {'p_limit': 100});
    final cancelamentos = _mapas(res);

    // ── Extras de 17/10: cada um falha sozinho e o ecrã fica como antes. ──
    var compensacoes = <Map<String, dynamic>>[];
    var compensacoesOk = false;
    try {
      compensacoes = _mapas(await sb
          .rpc('admin_tvde_cancel_comps', params: {'p_limit': 200}));
      compensacoesOk = true;
    } catch (e) {
      debugPrint('admin_tvde_cancel_comps falhou: $e');
    }

    final ids = cancelamentos
        .map((r) => r['id']?.toString())
        .whereType<String>()
        .toList();
    final pagamentos = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      try {
        final p = await sb
            .from('tvde_rides')
            .select('id, payment_method, payment_status')
            .inFilter('id', ids);
        for (final m in _mapas(p)) {
          pagamentos[m['id'].toString()] = m;
        }
      } catch (e) {
        debugPrint('pagamentos das corridas canceladas: $e');
      }
    }

    final motoristas = <String, String>{};
    final driverIds = cancelamentos
        .map((r) => r['driver_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (driverIds.isNotEmpty) {
      try {
        final d = await sb
            .from('drivers')
            .select('user_id, name')
            .inFilter('user_id', driverIds);
        for (final m in _mapas(d)) {
          final nome = (m['name'] as String?)?.trim();
          if (nome != null && nome.isNotEmpty) {
            motoristas[m['user_id'].toString()] = nome;
          }
        }
      } catch (e) {
        debugPrint('nomes dos motoristas: $e');
      }
    }

    RegraCancelamento? regra;
    try {
      regra = await _lerRegra(sb);
    } catch (e) {
      debugPrint('definições de cancelamento: $e');
    }

    final linhas = [
      for (final r in juntarCancelamentosECompensacoes(
          cancelamentos, compensacoes))
        {
          ...r,
          if (pagamentos[r['id']?.toString()] case final p?) ...{
            '_pag_metodo': p['payment_method'],
            '_pag_estado': p['payment_status'],
          },
          if (motoristas[r['driver_id']?.toString()] case final n?)
            '_motorista': n,
        },
    ];
    return DadosCancelamentos(
      linhas: linhas,
      compensacoes: compensacoes,
      compensacoesOk: compensacoesOk,
      regra: regra,
    );
  }

  Future<RegraCancelamento> _lerRegra(SupabaseClient sb) async {
    Future<String?> v(String k) async {
      final r = await sb.rpc('get_setting', params: {'p_key': k});
      return r?.toString();
    }

    final valores = await Future.wait([
      v('tvde_cancel_full_after_grace'),
      v('cancel_grace_seconds'),
      v('tvde_cancel_driver_fee_cents'),
      v('tvde_cancel_fee_cents'),
    ]);
    int n(String? s, int f) => num.tryParse(s ?? '')?.round() ?? f;
    return RegraCancelamento(
      ligada: valores[0] == 'true',
      graceSeconds: n(valores[1], 180),
      driverFeeCents: n(valores[2], 375),
      fixedFeeCents: n(valores[3], 250),
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return; // o admin saiu do ecrã enquanto a RPC corria
    setState(() => _future = _load());
    await _future.catchError((_) => const DadosCancelamentos(linhas: []));
  }

  Future<void> _exportar(List<Map<String, dynamic>> linhas) async {
    if (linhas.isEmpty) return;
    final dia = DateTime.now().toIso8601String().substring(0, 10);
    try {
      await tvdeGuardarCsvPadrao(
          'cancelamentos_tvde_$dia.csv', csvCancelamentos(linhas));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível exportar: $e')));
    }
  }

  /// Compensação manual: valor + motivo → confirmação com nome e valor →
  /// `admin_tvde_cancel_comp_grant`. Não cobra nada ao cliente.
  Future<void> _compensar(
      Map<String, dynamic> linha, RegraCancelamento? regra) async {
    final rideId = linha['id']?.toString();
    if (rideId == null) return;
    final idMotorista = linha['driver_id']?.toString() ?? '';
    final nome = (linha['_motorista'] as String?) ??
        'Motorista ${idMotorista.length > 8 ? idMotorista.substring(0, 8) : idMotorista}';
    final valorCtrl = TextEditingController(
        text: eurosBr(regra?.driverFeeCents ?? 375).replaceAll(' €', ''));
    final motivoCtrl = TextEditingController();
    final pedido = await showDialog<({int cents, String motivo})>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) {
          final cents = centsDoTexto(valorCtrl.text);
          final motivoOk = motivoCtrl.text.trim().length >= 3;
          return AlertDialog(
            title: const Text('Compensar motorista'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor (€)',
                      helperText: 'Entre 0,01 € e 50,00 €',
                      errorText: cents == null ? 'Valor inválido' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: motivoCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Motivo (obrigatório, mínimo 3 letras)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Vai para o acerto semanal do motorista. Não cobra nada ao cliente.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: cents == null || !motivoOk
                    ? null
                    : () => Navigator.pop(
                        ctx, (cents: cents, motivo: motivoCtrl.text.trim())),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );
    valorCtrl.dispose();
    motivoCtrl.dispose();
    if (pedido == null || !mounted) return;
    final confirmou = await confirmarDinheiro(
      context,
      titulo: 'Confirmar compensação',
      nome: nome,
      valor: eurosBr(pedido.cents),
      detalhe: 'Vai para o acerto semanal do motorista. Não cobra nada ao '
          'cliente.\nMotivo: ${pedido.motivo}',
      botao: 'Compensar',
    );
    if (!confirmou || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client
          .rpc('admin_tvde_cancel_comp_grant', params: {
        'p_ride_id': rideId,
        'p_driver_cents': pedido.cents,
        'p_reason': pedido.motivo,
      });
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Compensação registrada: ${eurosBr(pedido.cents)} para $nome.')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: AppColors.error,
          content: Text(erroDaCompensacao(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Cancelamentos — Bora Motorista'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<DadosCancelamentos>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _errorView('${snap.error}');
            }
            final dados = snap.data ?? const DadosCancelamentos(linhas: []);
            final rows = dados.linhas;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (dados.compensacoesOk)
                  _ResumoCompensacoes(
                    resumo: resumirCompensacoes(dados.compensacoes),
                    regra: dados.regra,
                  ),
                if (rows.isEmpty) ...const [
                  SizedBox(height: 90),
                  Icon(Icons.check_circle_outline,
                      size: 44, color: AppColors.primary),
                  SizedBox(height: 12),
                  Center(child: Text('Sem cancelamentos de corridas.')),
                ] else ...[
                  _headerNote(rows),
                  const SizedBox(height: 10),
                  ...rows.map((r) => _CancelCard(
                        data: r,
                        onCompensar: podeCompensar(r,
                                compensacoesOk: dados.compensacoesOk)
                            ? () => _compensar(r, dados.regra)
                            : null,
                      )),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _headerNote(List<Map<String, dynamic>> rows) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.08),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${rows.length} cancelamento(s) · pagamento em dinheiro ou '
                'online: o método e o que ficou retido aparecem em cada '
                'cartão quando há dados.',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => _exportar(rows),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('CSV'),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback amigável — cobre também o caso da RPC ainda não existir em runtime
  /// (migration nova ainda por aplicar). Nunca crasha; oferece "Tentar de novo".
  Widget _errorView(String error) {
    final missingRpc = error.contains('admin_tvde_cancellations') ||
        error.contains('PGRST202') ||
        error.contains('42883') ||
        error.contains('Could not find the function') ||
        error.contains('does not exist');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(missingRpc ? Icons.hourglass_empty : Icons.error_outline,
            size: 44,
            color: missingRpc ? AppColors.warning : AppColors.error),
        const SizedBox(height: 12),
        Text(
          missingRpc
              ? 'Histórico ainda não disponível.\n'
                  'A base de dados desta funcionalidade ainda não foi aplicada '
                  '(migration pendente). Assim que for aplicada, os '
                  'cancelamentos aparecem aqui.'
              : 'Erro ao carregar:\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ),
      ],
    );
  }
}

/// Cartão do topo: compensações ao motorista (cancelamento tardio) e a regra
/// em vigor, com os valores lidos das definições.
class _ResumoCompensacoes extends StatelessWidget {
  const _ResumoCompensacoes({required this.resumo, required this.regra});
  final ResumoCompensacoes resumo;
  final RegraCancelamento? regra;

  @override
  Widget build(BuildContext context) {
    Widget linha(String k, String v, {Color? cor}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary))),
              Text(v,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: cor ?? AppColors.textPrimary)),
            ],
          ),
        );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: const BorderSide(color: AppColors.divider)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Compensações ao motorista (cancelamento tardio)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            linha('Compensações', '${resumo.n}'),
            linha('Cobrado aos clientes', eurosBr(resumo.cobradoCents)),
            linha('Pago aos motoristas', eurosBr(resumo.motoristasCents)),
            linha('Fica para a Bora (cobrado − pago)', eurosBr(resumo.boraCents),
                cor: resumo.boraCents < 0 ? AppColors.error : AppColors.primary),
            if (resumo.naoCobradas > 0)
              linha('NÃO COBRADO (carteira no limite)', '${resumo.naoCobradas}',
                  cor: AppColors.error),
            if (regra != null) ...[
              const SizedBox(height: 8),
              Text(fraseDaRegra(regra!),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CancelCard extends StatelessWidget {
  const _CancelCard({required this.data, this.onCompensar});
  final Map<String, dynamic> data;

  /// Só nos cancelamentos do cliente / no-show com motorista e sem compensação.
  final VoidCallback? onCompensar;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final (statusLabel, statusColor) = _statusStyle(status);
    final reason = (data['cancel_reason'] as String?)?.trim();
    final feeCents = (data['cancel_fee_cents'] as num?)?.toInt() ?? 0;
    final fareCents = (data['est_fare_cents'] as num?)?.toInt() ?? 0;
    final elapsed = _elapsed(data['created_at'], data['updated_at']);
    final comp = (data['_comp'] as Map?)?.cast<String, dynamic>();
    final pagamento = rotuloPagamento(
      (data['_pag_metodo'] ?? comp?['payment_method']) as String?,
      (data['_pag_estado'] ?? comp?['payment_status']) as String?,
    );
    final nomeDaComp = (comp?['driver_name'] as String?)?.trim();
    final motorista = (data['_motorista'] as String?) ?? nomeDaComp;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado + taxa cobrada
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Text(
                  feeCents > 0 ? 'Taxa ${_eur(feeCents)}' : 'Grátis',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color:
                        feeCents > 0 ? AppColors.textPrimary : AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Motivo
            if (reason != null && reason.isNotEmpty)
              _kv(Icons.chat_bubble_outline, 'Motivo', reason),
            if (motorista != null && motorista.isNotEmpty)
              _kv(Icons.directions_car_outlined, 'Motorista', motorista),
            // Valor da corrida
            _kv(Icons.route, 'Valor da corrida', _eur(fareCents)),
            // Tempo até cancelar. [17/10] Sem a etiqueta da janela de cortesia:
            // a janela conta desde o motorista ACEITAR, não desde o pedido —
            // este tempo não diz se havia graça ou não.
            if (elapsed != null)
              _kv(Icons.timer_outlined, 'Tempo até cancelar',
                  'cancelada $elapsed após o pedido'),
            // Pagamento: só quando há dados (dinheiro, cartão, MB Way).
            if (pagamento != null)
              _kv(Icons.payments_outlined, 'Pagamento', pagamento),
            // [17/10] Compensação ao motorista (cancelamento tardio ou manual).
            if (comp != null) ...[
              _kv(
                  Icons.euro,
                  'Compensação ao motorista',
                  nomeDaComp == null || nomeDaComp.isEmpty
                      ? eurosBr(_int(comp['driver_cents']))
                      : '${eurosBr(_int(comp['driver_cents']))} ($nomeDaComp)',
                  valueColor: AppColors.primary),
              _kv(
                  Icons.account_balance_wallet_outlined,
                  'Cobrado ao cliente',
                  '${eurosBr(cobradoDaCompensacao(comp))} — '
                      '${rotuloCobranca(comp['collected_via'] as String?)}',
                  valueColor: comp['collected_via'] == 'nao_cobrado'
                      ? AppColors.error
                      : null),
              _kv(Icons.rule, 'Regra',
                  comp['origem'] == 'admin' ? 'admin' : 'automática'),
              _kv(Icons.event_note_outlined, 'Acerto da semana',
                  rotuloSemana(comp['week_status'] as String?)),
            ],
            if (onCompensar != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: onCompensar,
                  icon: const Icon(Icons.euro, size: 16),
                  label: const Text('Compensar motorista'),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            const SizedBox(height: 6),
            Text(_fmtDateTime(data['created_at']),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle)),
          ],
        ),
      ),
    );
  }

  Widget _kv(IconData icon, String key, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSubtle),
          const SizedBox(width: 6),
          Text('$key: ',
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textSubtle)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight:
                    valueColor != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dados e funções puras (testes em test/admin_tvde_cancelamentos_test.dart) ──

/// O que o ecrã carrega: os cancelamentos (já com a compensação, o pagamento e
/// o nome do motorista quando os há), as compensações e a regra em vigor.
class DadosCancelamentos {
  const DadosCancelamentos({
    required this.linhas,
    this.compensacoes = const [],
    this.compensacoesOk = false,
    this.regra,
  });
  final List<Map<String, dynamic>> linhas;
  final List<Map<String, dynamic>> compensacoes;

  /// A segunda chamada (`admin_tvde_cancel_comps`) correu bem.
  final bool compensacoesOk;
  final RegraCancelamento? regra;
}

/// Os valores das definições que fazem a regra (lidos com `get_setting`).
class RegraCancelamento {
  const RegraCancelamento({
    required this.ligada,
    required this.graceSeconds,
    required this.driverFeeCents,
    required this.fixedFeeCents,
  });
  final bool ligada;
  final int graceSeconds;
  final int driverFeeCents;
  final int fixedFeeCents;
}

class ResumoCompensacoes {
  const ResumoCompensacoes({
    required this.n,
    required this.cobradoCents,
    required this.motoristasCents,
    required this.boraCents,
    required this.naoCobradas,
  });
  final int n;

  /// O que entrou mesmo (pagamento retido ou carteira debitada).
  final int cobradoCents;
  final int motoristasCents;

  /// Cobrado − pago aos motoristas. Pode ser negativo (corrida mais barata que
  /// a compensação, cobrança falhada ou compensação manual).
  final int boraCents;
  final int naoCobradas;
}

int _int(Object? v) =>
    v is num ? v.toInt() : (num.tryParse('$v')?.toInt() ?? 0);

List<Map<String, dynamic>> _mapas(Object? res) => ((res as List?) ?? const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

/// Junta a cada cancelamento a SUA compensação (pelo id da corrida), na chave
/// `_comp`. Sem compensações, devolve a lista igual.
List<Map<String, dynamic>> juntarCancelamentosECompensacoes(
  List<Map<String, dynamic>> cancelamentos,
  List<Map<String, dynamic>> compensacoes,
) {
  if (compensacoes.isEmpty) return cancelamentos;
  final porCorrida = <String, Map<String, dynamic>>{
    for (final c in compensacoes)
      if (c['ride_id'] != null) c['ride_id'].toString(): c,
  };
  return [
    for (final r in cancelamentos)
      if (porCorrida[r['id']?.toString()] case final c?)
        {...r, '_comp': c}
      else
        r,
  ];
}

/// O que foi mesmo cobrado ao cliente nesta compensação.
int cobradoDaCompensacao(Map<String, dynamic> c) {
  final via = c['collected_via'];
  return (via == 'pagamento_retido' || via == 'carteira')
      ? _int(c['fee_cents'])
      : 0;
}

ResumoCompensacoes resumirCompensacoes(List<Map<String, dynamic>> comps) {
  var cobrado = 0, motoristas = 0, naoCobradas = 0;
  for (final c in comps) {
    cobrado += cobradoDaCompensacao(c);
    motoristas += _int(c['driver_cents']);
    if (c['collected_via'] == 'nao_cobrado') naoCobradas++;
  }
  return ResumoCompensacoes(
    n: comps.length,
    cobradoCents: cobrado,
    motoristasCents: motoristas,
    boraCents: cobrado - motoristas,
    naoCobradas: naoCobradas,
  );
}

/// "3,75 €" / "−3,25 €".
String eurosBr(int cents) {
  final txt = (cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
  return cents < 0 ? '−$txt €' : '$txt €';
}

String rotuloCobranca(String? via) => switch (via) {
      'pagamento_retido' => 'Pagamento online retido',
      'carteira' => 'Debitado na carteira',
      'nao_cobrado' => 'NÃO COBRADO (carteira no limite)',
      'admin' => 'Compensação manual do admin',
      null => '—',
      _ => via,
    };

/// Estado do acerto semanal do motorista (`driver_weekly_settlements.status`).
String rotuloSemana(String? s) => switch (s) {
      null || '' => 'ainda aberta (entra no acerto desta semana)',
      'paid' => 'paga ao motorista',
      'received' => 'recebida pela Bora (o motorista pagou)',
      'pending' => 'pendente (por acertar)',
      _ => s,
    };

/// Método e estado do pagamento em PT-BR; null quando não há dados.
String? rotuloPagamento(String? metodo, String? estado) {
  final m = switch (metodo) {
    null => null,
    'cash' => 'Dinheiro',
    'card' => 'Cartão',
    'mbway' => 'MB Way',
    _ => metodo,
  };
  final e = switch (estado) {
    null => null,
    'succeeded' => 'pago (online)',
    'kept_cancel_fee' => 'valor retido (taxa de cancelamento)',
    'refunded' => 'devolvido ao cliente (reembolso total)',
    'partial_refund' => 'devolvido em parte (ficou a taxa)',
    'canceled' => 'pagamento anulado (nada cobrado)',
    'requires_payment_method' ||
    'requires_confirmation' ||
    'requires_action' ||
    'processing' =>
      'não chegou a ser pago',
    _ => estado,
  };
  if (m == null && e == null) return null;
  if (e == null) return m;
  if (m == null) return e;
  return '$m · $e';
}

/// A regra em vigor, com os valores das definições.
String fraseDaRegra(RegraCancelamento r) {
  if (!r.ligada) {
    return 'Regra atual: DESLIGADA (tvde_cancel_full_after_grace) — o cliente '
        'não paga nada por cancelar e o motorista não recebe compensação '
        'automática.';
  }
  final janela = r.graceSeconds % 60 == 0
      ? '${r.graceSeconds ~/ 60} min'
      : '${r.graceSeconds} s';
  return 'Regra atual: se o cliente cancelar mais de $janela depois de o '
      'motorista aceitar (e antes da recolha), paga a corrida inteira e o '
      'motorista recebe ${eurosBr(r.driverFeeCents)} de compensação. '
      'Corridas de plano, pacote, marcadas, balcão, em fila ou com preço '
      'combinado pagam a taxa fixa de ${eurosBr(r.fixedFeeCents)}.';
}

/// O botão "Compensar motorista" só aparece onde o servidor o aceita:
/// cancelada pelo cliente ou no-show, com motorista e sem compensação — e só
/// se as compensações carregaram (senão não se sabe se já existe).
bool podeCompensar(Map<String, dynamic> r, {required bool compensacoesOk}) {
  if (!compensacoesOk) return false;
  final st = r['status'];
  if (st != 'cancelada_cliente' && st != 'no_show') return false;
  final drv = r['driver_id']?.toString();
  if (drv == null || drv.isEmpty) return false;
  return r['_comp'] == null;
}

/// Valor em euros escrito pelo admin → cêntimos (1..5000), ou null.
int? centsDoTexto(String texto) {
  final t = texto.replaceAll('€', '').replaceAll(',', '.').trim();
  final v = double.tryParse(t);
  if (v == null) return null;
  final c = (v * 100).round();
  return (c < 1 || c > 5000) ? null : c;
}

/// Erros de `admin_tvde_cancel_comp_grant` em PT-BR.
String erroDaCompensacao(Object e) {
  final s = e is PostgrestException ? '${e.message} ${e.code ?? ''}' : '$e';
  if (s.contains('reason_required')) {
    return 'Escreva o motivo (mínimo 3 letras).';
  }
  if (s.contains('invalid_value')) {
    return 'Valor inválido: tem de ser entre 0,01 € e 50,00 €.';
  }
  if (s.contains('ride_not_found')) return 'Corrida não encontrada.';
  if (s.contains('ride_without_driver')) {
    return 'Esta corrida não tem motorista — não há a quem compensar.';
  }
  if (s.contains('ride_not_cancelled_by_client')) {
    final m = RegExp(r'ride_not_cancelled_by_client:\s*(\w+)').firstMatch(s);
    return 'Só se compensa corrida cancelada pelo cliente ou no-show '
        '(estado desta: ${m?.group(1) ?? 'outro'}).';
  }
  if (s.contains('compensation_already_exists')) {
    return 'Esta corrida já tem compensação registrada (uma por corrida).';
  }
  if (s.contains('admin_required') || s.contains('42501')) {
    return 'Só um admin pode compensar (a sessão não tem papel de admin).';
  }
  return 'Não foi possível registrar a compensação: $s';
}

String _eurCsv(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

/// CSV (separador ";") dos cancelamentos listados, com a compensação.
String csvCancelamentos(List<Map<String, dynamic>> linhas) => tvdeCsv(
      const [
        'Corrida',
        'Data',
        'Estado',
        'Motivo',
        'Valor da corrida (€)',
        'Taxa cobrada (€)',
        'Pagamento',
        'Compensação ao motorista (€)',
        'Motorista',
        'Cobrado ao cliente',
        'Fica para a Bora (€)',
        'Origem da compensação',
        'Acerto da semana',
      ],
      [for (final r in linhas) _linhaCsv(r)],
    );

List<dynamic> _linhaCsv(Map<String, dynamic> r) {
  final c = (r['_comp'] as Map?)?.cast<String, dynamic>();
  return <dynamic>[
    r['id'],
    _fmtDateTime(r['created_at']),
    _statusStyle(r['status'] as String?).$1,
    (r['cancel_reason'] as String?)?.trim() ?? '',
    _eurCsv(_int(r['est_fare_cents'])),
    _eurCsv(_int(r['cancel_fee_cents'])),
    rotuloPagamento((r['_pag_metodo'] ?? c?['payment_method']) as String?,
            (r['_pag_estado'] ?? c?['payment_status']) as String?) ??
        '',
    c == null ? '' : _eurCsv(_int(c['driver_cents'])),
    (r['_motorista'] as String?) ?? c?['driver_name'] ?? '',
    c == null ? '' : rotuloCobranca(c['collected_via'] as String?),
    c == null ? '' : _eurCsv(cobradoDaCompensacao(c) - _int(c['driver_cents'])),
    c == null ? '' : (c['origem'] == 'admin' ? 'admin' : 'automática'),
    c == null ? '' : rotuloSemana(c['week_status'] as String?),
  ];
}

// ── Helpers ──

(String, Color) _statusStyle(String? s) => switch (s) {
      'cancelada_cliente' =>
        ('Cancelada pelo cliente', AppColors.error),
      'cancelada_motorista' =>
        ('Cancelada pelo motorista', AppColors.error),
      'no_show' => ('Não compareceu (no-show)', Colors.deepOrange),
      _ => (s ?? '—', AppColors.textSecondary),
    };

String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';

/// Diferença entre `updated_at` (momento do cancelamento) e `created_at`
/// (momento do pedido), em texto.
String? _elapsed(dynamic created, dynamic updated) {
  final c = DateTime.tryParse('${created ?? ''}');
  final u = DateTime.tryParse('${updated ?? ''}');
  if (c == null || u == null) return null;
  var secs = u.difference(c).inSeconds;
  if (secs < 0) secs = 0;
  if (secs < 60) return '$secs s';
  if (secs < 3600) return '${secs ~/ 60} min';
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  return m > 0 ? '$h h $m min' : '$h h';
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLisboa();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
