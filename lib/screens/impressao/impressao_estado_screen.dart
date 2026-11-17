// Estado de um pedido de impressão ou de personalizado, em tempo real (missão a3-guarda-16-11, parte 2).
// Personalizado com preço da loja ("orcamentado"): o cliente escolhe o pagamento e confirma aqui.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_impressao.dart';
import '../../services/impressao_service.dart';
import '../../widgets/bora/bora_bottom_action_bar.dart';
import '../../widgets/bora/bora_primary_button.dart';

class ImpressaoEstadoScreen extends StatefulWidget {
  const ImpressaoEstadoScreen({super.key, required this.pedidoId, required this.lojaNome, this.service});
  final String pedidoId;
  final String lojaNome;
  final ImpressaoService? service;

  @override
  State<ImpressaoEstadoScreen> createState() => _ImpressaoEstadoScreenState();
}

class _ImpressaoEstadoScreenState extends State<ImpressaoEstadoScreen> {
  late final ImpressaoService _svc = widget.service ?? ImpressaoService();
  String _metodo = 'cash';
  bool _ocupado = false;

  Future<void> _correr(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
    } on ImpressaoErro catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _passos(PedidoImpressao p) {
    final ordem = p.personalizado
        ? const [ImpressaoEstado.enviado, ImpressaoEstado.orcamentado, ImpressaoEstado.aceite, ImpressaoEstado.pronto, ImpressaoEstado.entregue]
        : const [ImpressaoEstado.enviado, ImpressaoEstado.aceite, ImpressaoEstado.pronto, ImpressaoEstado.entregue];
    final i = ordem.indexOf(p.estado);
    return Column(children: [
      for (var k = 0; k < ordem.length; k++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(k <= i ? Icons.check_circle : Icons.radio_button_unchecked,
                color: k <= i ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(impressaoEstadoTexto(ordem[k], personalizado: p.personalizado),
                style: TextStyle(fontWeight: k == i ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PedidoImpressao?>(
      stream: _svc.acompanhar(widget.pedidoId),
      builder: (context, snap) {
        final p = snap.data;
        final terminado = p != null &&
            (p.estado == ImpressaoEstado.recusado || p.estado == ImpressaoEstado.cancelado || p.estado == ImpressaoEstado.expirado);
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(widget.lojaNome)),
          body: p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (p.isDemo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Text('Pedido de teste: nada é cobrado.', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  Text(impressaoEstadoTexto(p.estado, personalizado: p.personalizado),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(p.resumo, style: const TextStyle(color: AppColors.textSecondary)),
                  if (p.personalizado)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('A loja envia-lhe uma prova antes de produzir.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  if (p.estado == ImpressaoEstado.recusado && p.motivoRecusa != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text('Motivo: ${p.motivoRecusa}')),
                  const SizedBox(height: 16),
                  if (!terminado) _passos(p),
                  if (!p.entrega && p.codigoLevantamento != null && !terminado) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        const Text('Código para levantar na loja'),
                        const SizedBox(height: 4),
                        SelectableText(p.codigoLevantamento!,
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (p.totalCents != null || p.artigoCents != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (p.artigoCents != null) _linha(p.personalizado ? 'Personalizado' : 'Impressão', p.artigoCents),
                        if (p.taxaServicoCents != null) _linha('Taxa de serviço', p.taxaServicoCents),
                        if (p.entrega && p.taxaEntregaCents != null) _linha('Entrega', p.taxaEntregaCents),
                        if (p.totalCents != null) ...[const Divider(), _linha('Total', p.totalCents, forte: true)],
                        if (p.metodoPagamento != null)
                          Text('Pagamento: ${_metodoTexto(p.metodoPagamento!)}', style: const TextStyle(color: AppColors.textSecondary)),
                      ]),
                    ),
                  if (p.estado == ImpressaoEstado.orcamentado) ...[
                    const SizedBox(height: 16),
                    const Text('Como quer pagar?', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final m in const [('card', 'Cartão'), ('mbway', 'MB Way'), ('cash', 'Dinheiro')])
                        ChoiceChip(label: Text(m.$2), selected: _metodo == m.$1, onSelected: (_) => setState(() => _metodo = m.$1)),
                    ]),
                  ],
                ]),
          bottomNavigationBar: p == null ? null : _barra(p),
        );
      },
    );
  }

  Widget? _barra(PedidoImpressao p) {
    if (p.estado == ImpressaoEstado.orcamentado) {
      return BoraBottomActionBar(children: [
        BoraPrimaryButton(
          label: 'Aceitar o preço',
          icon: Icons.check,
          loading: _ocupado,
          onPressed: () => _correr(() => _svc.confirmarOrcamento(p.id, _metodo)),
        ),
        TextButton(onPressed: _ocupado ? null : () => _correr(() => _svc.cancelar(p.id)), child: const Text('Não quero')),
      ]);
    }
    if (p.estado == ImpressaoEstado.enviado) {
      return BoraBottomActionBar(children: [
        TextButton(onPressed: _ocupado ? null : () => _correr(() => _svc.cancelar(p.id)), child: const Text('Cancelar pedido')),
      ]);
    }
    return null;
  }

  Widget _linha(String t, int? c, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w500))),
          Text(euros(c), style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  static String _metodoTexto(String m) => m == 'card' ? 'cartão' : (m == 'mbway' ? 'MB Way' : 'dinheiro');
}
