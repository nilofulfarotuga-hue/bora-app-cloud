// Painel admin — Farmácias, aba "Extrato semanal" (missão farmacias-loja-2026-11-14, Bloco 5). PT-BR.
// Só leitura: para cada farmácia parceira chama compute_partner_weekly_settlement com
// p_persist = false (calcula agora, não grava nada). Marcar como pago continua no ecrã
// "Acertos semanais" (AdminSettlementsScreen), que é o dono dos fechos.
// As chaves comissao_extra e comissao_extra_receitas só aparecem quando o servidor as manda.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/admin_farmacias_service.dart';
import '../../services/prescricao_service.dart';
import '../../utils/euros.dart';
import '../../widgets/admin/admin_csv_button.dart';
import 'admin_farmacia_ficha.dart' show dataLisboa;
import 'admin_settlements_screen.dart';

/// Valor numérico de uma chave do extrato (aceita número, texto ou {total|valor}).
num? numeroDoExtrato(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is Map) return numeroDoExtrato(v['total'] ?? v['valor'] ?? v['amount']);
  return num.tryParse(v.toString());
}

/// Quem paga a quem no fim da semana.
String direcaoDoExtrato(Object? d) => switch ('$d') {
      'bora_pays_partner' => 'Bora paga à farmácia',
      'partner_pays_bora' => 'Farmácia paga à Bora',
      _ => 'Sem saldo',
    };

/// (chave, rótulo, mostrarSempre). As que não são "sempre" só aparecem quando vêm no extrato
/// (e os depósitos só quando são diferentes de zero).
const kLinhasExtrato = <(String, String, bool)>[
  ('gross_sales', 'Vendas na app (bruto)', true),
  ('commission_total', 'Comissão Bora', true),
  ('partner_share', 'Parte da farmácia', true),
  ('cash_kept_by_partner', 'Recebido em mão pela farmácia (dinheiro)', true),
  ('deposit_volta_total', 'Depósitos Volta (100% da farmácia)', false),
  ('comissao_extra', 'Comissão extra (10% das vendas na app depois da data de início)', false),
  ('comissao_extra_receitas', 'Comissão extra das receitas (10% dos medicamentos com receita)', false),
];

String _csvNum(Object? v) {
  final n = numeroDoExtrato(v);
  return n == null ? '' : n.toStringAsFixed(2).replaceAll('.', ',');
}

/// Uma linha do CSV (separador ';', vírgula decimal — o que o Excel em português lê).
Map<String, dynamic> linhaCsvExtrato(String farmacia, Map<String, dynamic> e) => {
      'semana_inicio': dataLisboa(e['week_start']),
      'semana_fim': dataLisboa(e['week_end']),
      'farmacia': farmacia,
      'pedidos': '${e['total_orders'] ?? 0}',
      'vendas': _csvNum(e['gross_sales']),
      'comissao': _csvNum(e['commission_total']),
      'parte_farmacia': _csvNum(e['partner_share']),
      'dinheiro_em_mao': _csvNum(e['cash_kept_by_partner']),
      'pago_na_recolha': _csvNum(e['pago_em_mao_na_recolha']),
      'depositos_volta': _csvNum(e['deposit_volta_total']),
      'comissao_extra': _csvNum(e['comissao_extra']),
      'comissao_extra_receitas': _csvNum(e['comissao_extra_receitas']),
      'saldo': _csvNum(e['net_balance']),
      'direcao': direcaoDoExtrato(e['direction']),
    };

const kColunasCsvExtrato = <(String, String)>[
  ('semana_inicio', 'Semana (início)'),
  ('semana_fim', 'Semana (fim)'),
  ('farmacia', 'Farmácia'),
  ('pedidos', 'Pedidos entregues'),
  ('vendas', 'Vendas na app (€)'),
  ('comissao', 'Comissão Bora (€)'),
  ('parte_farmacia', 'Parte da farmácia (€)'),
  ('dinheiro_em_mao', 'Recebido em mão (€)'),
  ('pago_na_recolha', 'Pago pelo entregador na recolha (€)'),
  ('depositos_volta', 'Depósitos Volta (€)'),
  ('comissao_extra', 'Comissão extra 10% (€)'),
  ('comissao_extra_receitas', 'Comissão extra receitas 10% (€)'),
  ('saldo', 'Saldo da semana (€)'),
  ('direcao', 'Quem paga'),
];

class _Linha {
  _Linha(this.id, this.nome, this.extrato, this.erro);
  final String id;
  final String nome;
  final Map<String, dynamic>? extrato;
  final String? erro;
}

class AdminFarmaciasExtratoAba extends StatefulWidget {
  const AdminFarmaciasExtratoAba({super.key});
  @override
  State<AdminFarmaciasExtratoAba> createState() => _AdminFarmaciasExtratoAbaState();
}

class _AdminFarmaciasExtratoAbaState extends State<AdminFarmaciasExtratoAba> {
  final _svc = AdminFarmaciasService();
  final _prescricao = PrescricaoService();

  /// 0 = semana atual, -1 = anterior, ...
  int _semana = 0;
  late Future<List<_Linha>> _f = _carregar();

  Future<List<_Linha>> _carregar() async {
    final dia = DateTime.now().add(Duration(days: 7 * _semana));
    final farmacias = (await _prescricao.adminFarmacias())
        .where((f) => f['is_partner'] != false) // não-parceiras não têm acerto semanal
        .toList();
    return Future.wait(farmacias.map((f) async {
      final id = '${f['id']}';
      final nome = '${f['name'] ?? id}';
      try {
        return _Linha(id, nome, await _svc.extratoSemana(id, dia), null);
      } catch (e) {
        return _Linha(id, nome, null, PrescricaoService.mensagemDe(e));
      }
    }));
  }

  void _mudarSemana(int delta) => setState(() {
        _semana += delta;
        _f = _carregar();
      });

  String _rotuloSemana(List<_Linha> l) {
    final e = l.map((x) => x.extrato).whereType<Map<String, dynamic>>().firstOrNull;
    final base = _semana == 0
        ? 'Esta semana'
        : _semana == -1
            ? 'Semana passada'
            : 'Há ${-_semana} semanas';
    if (e == null) return base;
    return '$base · ${dataLisboa(e['week_start'])} a ${dataLisboa(e['week_end'])}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Linha>>(
      future: _f,
      builder: (context, s) {
        final pronto = s.connectionState == ConnectionState.done;
        // Enquanto calcula outra semana não se mostra (nem se exporta) a anterior.
        final linhas = pronto ? (s.data ?? const <_Linha>[]) : const <_Linha>[];
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'Semana anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _mudarSemana(-1),
              ),
              Expanded(
                child: Text(
                  pronto && s.hasData ? _rotuloSemana(linhas) : 'A calcular…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Semana seguinte',
                icon: const Icon(Icons.chevron_right),
                onPressed: _semana >= 0 ? null : () => _mudarSemana(1),
              ),
              AdminCsvButton(
                nome: 'extrato_farmacias',
                colunas: kColunasCsvExtrato,
                linhas: () => [
                  for (final l in linhas)
                    if (l.extrato != null) linhaCsvExtrato(l.nome, l.extrato!),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Expanded(
                child: Text(
                  'Só leitura: calculado agora, não grava nada. Para marcar como pago use "Acertos semanais".',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AdminSettlementsScreen())),
                child: const Text('Acertos semanais'),
              ),
            ]),
          ),
          Expanded(
            child: !pronto
                ? const Center(child: CircularProgressIndicator())
                : s.hasError
                    ? Center(child: Text(PrescricaoService.mensagemDe(s.error!)))
                    : linhas.isEmpty
                        ? const Center(child: Text('Nenhuma farmácia parceira.'))
                        : RefreshIndicator(
                            onRefresh: () async => _mudarSemana(0),
                            child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: [for (final l in linhas) AdminFarmaciaExtratoCartao(nome: l.nome, extrato: l.extrato, erro: l.erro)],
                            ),
                          ),
          ),
        ]);
      },
    );
  }
}

/// Cartão do extrato de uma farmácia (testável sem rede).
class AdminFarmaciaExtratoCartao extends StatelessWidget {
  const AdminFarmaciaExtratoCartao({super.key, required this.nome, required this.extrato, this.erro});
  final String nome;
  final Map<String, dynamic>? extrato;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    final e = extrato;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (e == null)
            Text(erro ?? 'Sem dados.', style: const TextStyle(color: AppColors.error))
          else ...[
            _linha('Pedidos entregues', '${e['total_orders'] ?? 0}'),
            for (final (chave, rotulo, sempre) in kLinhasExtrato)
              if (sempre ||
                  (e.containsKey(chave) &&
                      (chave != 'deposit_volta_total' || (numeroDoExtrato(e[chave]) ?? 0) != 0)))
                _linha(rotulo, _eur(e[chave])),
            const Divider(height: 18),
            _linha('Saldo da semana — ${direcaoDoExtrato(e['direction'])}', _eur(e['net_balance']), forte: true),
          ],
        ]),
      ),
    );
  }

  static String _eur(Object? v) {
    final n = numeroDoExtrato(v);
    return n == null ? '—' : eur(n);
  }

  Widget _linha(String rotulo, String valor, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(rotulo, style: TextStyle(fontWeight: forte ? FontWeight.w700 : FontWeight.w400))),
          const SizedBox(width: 12),
          Text(valor, style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}
