// Botões no topo da loja da farmácia (missão farmacias-2026-11-11):
// "Tenho receita", "Não encontra o produto? Peça aqui" e "Repetir todos os meses".
// Só aparecem se o servidor disser que sim (categoria farmácia + modo da receita + lista de permissão).
// Sem resposta do servidor = não aparece nada.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../screens/farmacia/farmacia_pedidos_screen.dart';
import '../../screens/farmacia/prescricao_enviar_screen.dart';
import '../../services/prescricao_service.dart';
import 'lembrete_mensal_sheet.dart';

class FarmaciaBotoesTopo extends StatefulWidget {
  const FarmaciaBotoesTopo({
    super.key,
    required this.restaurantId,
    required this.storeName,
    this.service,
    this.visivelParaTeste,
    this.onVisivel,
    this.chaveBotaoReceita,
  });

  final String restaurantId;
  final String storeName;
  final PrescricaoService? service;

  /// Só para testes: força o resultado de `farmacia_botoes_visiveis`.
  final bool? visivelParaTeste;

  /// 14/11/2026 (loja da farmácia): avisa o ecrã quando o servidor responde,
  /// para a barra fina mostrar o chip "Tenho receita" (ver [FarmaciaReceitaChip]).
  final ValueChanged<bool>? onVisivel;

  /// 14/11/2026: chave do botão grande "Tenho receita" — o ecrã da loja mede
  /// quando ele sai do ecrã para pôr o chip na barra fina no lugar dele.
  final Key? chaveBotaoReceita;

  @override
  State<FarmaciaBotoesTopo> createState() => _FarmaciaBotoesTopoState();
}

class _FarmaciaBotoesTopoState extends State<FarmaciaBotoesTopo> {
  late final PrescricaoService _svc = widget.service ?? PrescricaoService();
  bool _visivel = false;
  int _pedidos = 0;

  @override
  void initState() {
    super.initState();
    if (widget.visivelParaTeste != null) {
      _visivel = widget.visivelParaTeste!;
      if (widget.onVisivel != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onVisivel?.call(_visivel);
        });
      }
    } else {
      _verificar();
    }
  }

  Future<void> _verificar() async {
    final v = await _svc.botoesVisiveis(widget.restaurantId);
    if (!mounted) return;
    setState(() => _visivel = v);
    widget.onVisivel?.call(v);
    if (v) {
      try {
        final l = await _svc.meus(restaurantId: widget.restaurantId, limite: 30);
        if (mounted) setState(() => _pedidos = l.length);
      } catch (_) {}
    }
  }

  void _abrir(Widget ecra) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecra));
    if (mounted && widget.visivelParaTeste == null) _verificar();
  }

  Future<void> _repetir() async {
    List<PedidoPrescricao> l = const [];
    try {
      l = await _svc.meus(restaurantId: widget.restaurantId);
    } catch (_) {}
    if (!mounted) return;
    final feitos = l.where((p) => p.estado == PrescricaoEstado.confirmado || p.estado == PrescricaoEstado.entregue).toList();
    if (feitos.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Repetir todos os meses'),
          content: const Text(
              'Primeiro faça um pedido nesta farmácia. Depois de confirmado, pode pedir para o avisarmos todos os meses.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Percebi'))],
        ),
      );
      return;
    }
    LembreteMensalSheet.abrir(context,
        restaurantId: widget.restaurantId, farmaciaNome: widget.storeName, prescricaoId: feitos.first.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visivel) return const SizedBox.shrink();
    final secundario = OutlinedButton.styleFrom(
      foregroundColor: AppColors.primaryDark,
      side: const BorderSide(color: AppColors.primary),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          key: widget.chaveBotaoReceita,
          height: 54,
          child: ElevatedButton.icon(
            key: const ValueKey('farmacia_tenho_receita'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            onPressed: () => _abrir(PrescricaoEnviarScreen(restaurantId: widget.restaurantId, farmaciaNome: widget.storeName)),
            icon: const Icon(Icons.receipt_long, size: 24),
            label: const Text('Tenho receita'),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: secundario,
              onPressed: () => _abrir(PedidoLivreScreen(restaurantId: widget.restaurantId, farmaciaNome: widget.storeName)),
              child: const Text('Não encontra o produto? Peça aqui', textAlign: TextAlign.center, maxLines: 2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: secundario,
              onPressed: _repetir,
              child: const Text('Repetir todos os meses', textAlign: TextAlign.center, maxLines: 2),
            ),
          ),
        ]),
        if (_pedidos > 0)
          TextButton.icon(
            onPressed: () => _abrir(FarmaciaPedidosScreen(restaurantId: widget.restaurantId, farmaciaNome: widget.storeName)),
            icon: const Icon(Icons.history, size: 18),
            label: Text('Os meus pedidos à farmácia ($_pedidos)'),
          ),
      ]),
    );
  }
}

/// 14/11/2026 (loja da farmácia): "Tenho receita" em pequeno, preso na barra
/// fina da loja quando o botão grande já saiu do ecrã (e durante a pesquisa).
/// Só o ecrã da loja o mostra, e só depois de [FarmaciaBotoesTopo] confirmar
/// com o servidor que a farmácia recebe receitas.
class FarmaciaReceitaChip extends StatelessWidget {
  const FarmaciaReceitaChip({
    super.key,
    required this.restaurantId,
    required this.storeName,
  });

  final String restaurantId;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      key: const ValueKey('farmacia_tenho_receita_chip'),
      avatar: const Icon(Icons.receipt_long, size: 18, color: Colors.white),
      label: const Text('Tenho receita'),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
      backgroundColor: AppColors.primary,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PrescricaoEnviarScreen(
          restaurantId: restaurantId,
          farmaciaNome: storeName,
        ),
      )),
    );
  }
}
