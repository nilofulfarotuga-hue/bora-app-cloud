// lib/screens/client/checkin_premios_screen.dart
//
// "Os meus prémios" (Bloco D, 21/10/2026): os vales dos marcos do check-in.
// Por usar → "Usar" (produto: abre a loja certa com o prémio no carrinho) ou
// "Escolher" (30 dias: limpeza de 2 h ou lavagem exterior). Guardado (tecto do
// mês) e "Falta 1 pedido" dizem o que falta. Usados/expirados ficam por baixo.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../utils/premio_checkin_fluxo.dart';
import '../../widgets/checkin/checkin_mes_sheet.dart';
import 'checkin_premio_servico_screen.dart';

class CheckinPremiosScreen extends StatefulWidget {
  const CheckinPremiosScreen({super.key, this.carregar, this.usarProduto, this.escolherServico});

  final Future<CheckinPremiosEstado?> Function()? carregar;
  final Future<void> Function(BuildContext context, CheckinVale vale)? usarProduto;
  final Future<void> Function(BuildContext context, CheckinVale vale)? escolherServico;

  @override
  State<CheckinPremiosScreen> createState() => _CheckinPremiosScreenState();
}

class _CheckinPremiosScreenState extends State<CheckinPremiosScreen> {
  CheckinPremiosEstado? _estado;
  bool _aCarregar = true;
  String? _aUsar;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final e = await (widget.carregar ?? CheckinPremiosService.instance.estado)();
    if (!mounted) return;
    setState(() {
      _estado = e;
      _aCarregar = false;
    });
    if (e != null && e.novos.isNotEmpty) {
      await CheckinPremiosService.instance.marcarVistos(e.novos);
    }
  }

  Future<void> _usar(CheckinVale v) async {
    if (_aUsar != null) return;
    setState(() => _aUsar = v.id);
    try {
      if (v.ehProduto) {
        await (widget.usarProduto ?? usarPremioProduto)(context, v);
      } else {
        await (widget.escolherServico ??
            (ctx, vale) => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => CheckinPremioServicoScreen(vale: vale),
                )))(context, v);
      }
    } finally {
      if (mounted) setState(() => _aUsar = null);
      await _ler();
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Os meus prémios'.tr)),
      body: _aCarregar
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _ler,
              child: ListView(
                key: const Key('lista_premios'),
                padding: const EdgeInsets.all(16),
                children: [
                  if (e == null)
                    _vazio('Não foi possível ver os teus prémios. Puxa para tentar de novo.'.tr)
                  else ...[
                    if (e.marcos.isNotEmpty)
                      OutlinedButton.icon(
                        key: const Key('btn_ver_marcos'),
                        onPressed: () => mostrarCheckinMes(context, e),
                        icon: const Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text(e.diasSeguidos > 0
                            ? 'Os marcos do check-in · dia {0}'.trArgs([e.diaMarco])
                            : 'Os marcos do check-in'.tr),
                      ),
                    const SizedBox(height: 12),
                    if (e.porUsar.isEmpty && e.historico.isEmpty)
                      _vazio('Ainda não tens prémios. Faz o check-in todos os dias: aos 10 dias seguidos ganhas o primeiro.'.tr),
                    if (e.porUsar.isNotEmpty) ...[
                      _titulo('Por usar'.tr),
                      for (final v in e.porUsar) _ValeCartao(vale: v, aUsar: _aUsar == v.id, onUsar: () => _usar(v)),
                    ],
                    if (e.historico.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _titulo('Usados e expirados'.tr),
                      for (final v in e.historico) _ValeCartao(vale: v, aUsar: false, onUsar: null),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _vazio(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

String _data(DateTime? d) {
  if (d == null) return '';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}';
}

class _ValeCartao extends StatelessWidget {
  const _ValeCartao({required this.vale, required this.aUsar, required this.onUsar});

  final CheckinVale vale;
  final bool aUsar;
  final VoidCallback? onUsar;

  String _subtitulo() {
    final v = vale;
    switch (v.estado) {
      case 'por_usar':
      case 'reservado':
        final onde = v.ehProduto && (v.lojaNome ?? '').isNotEmpty ? '${v.lojaNome} · ' : '';
        return '$onde${'Vale até {0}'.trArgs([_data(v.validoAte)])}';
      case 'guardado':
        return 'Este mês já não há mais prémios de {0} dias. Fica disponível a {1}.'
            .trArgs([v.marco, _data(v.ativarEm)]);
      case 'a_espera_pedido':
        return 'Falta 1 pedido para desbloquear o prémio. Tens até {0}.'.trArgs([_data(v.esperarAte)]);
      case 'usado':
        return 'Usado a {0}'.trArgs([_data(v.usadoEm)]);
      case 'expirado':
        return 'Expirou a {0}'.trArgs([_data(v.validoAte ?? v.esperarAte)]);
      default:
        return textoEstadoVale(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = vale;
    final podeUsar = onUsar != null && v.usavel;
    return Card(
      key: Key('vale_${v.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: podeUsar ? AppColors.primary : const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: podeUsar ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${v.marco}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.titulo.tr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_subtitulo(), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
                ],
              ),
            ),
            if (podeUsar) ...[
              const SizedBox(width: 8),
              FilledButton(
                key: Key('btn_usar_${v.id}'),
                onPressed: aUsar ? null : onUsar,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(aUsar ? '…' : (v.ehProduto ? 'Usar'.tr : 'Escolher'.tr)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
