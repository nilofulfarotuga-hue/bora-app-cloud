// PAINEL ADMIN (PT-BR) — Produto em destaque da loja ("Hambúrguer do mês").
// 02/11/2026, missão boom-hamburguer-mes, bloco C. Ver, trocar e remover o
// destaque de qualquer loja (RPC admin_definir_destaque, com auditoria). O
// parceiro faz o mesmo na loja dele pelo ecrã de produtos.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/destaque_loja_service.dart';
import '../../widgets/editor_destaque_loja.dart';

class AdminDestaqueLojaCard extends StatefulWidget {
  const AdminDestaqueLojaCard({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<AdminDestaqueLojaCard> createState() => _AdminDestaqueLojaCardState();
}

class _AdminDestaqueLojaCardState extends State<AdminDestaqueLojaCard> {
  List<ProdutoEscolhivel> _produtos = const [];
  DestaqueLoja? _destaque;
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    var produtos = const <ProdutoEscolhivel>[];
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id, name')
          .eq('restaurant_id', widget.restaurantId)
          .order('sort_order', ascending: true)
          .limit(500);
      produtos = [
        for (final r in (rows as List).whereType<Map>())
          ProdutoEscolhivel((r['id'] ?? '').toString(), (r['name'] ?? '').toString()),
      ];
    } catch (_) {
      // sem produtos lidos: o editor mostra só "Sem destaque"
    }
    final d = await DestaqueLojaService.instance.daLoja(widget.restaurantId);
    if (!mounted) return;
    setState(() {
      _produtos = produtos;
      _destaque = d;
      _carregado = true;
    });
  }

  Future<void> _salvar(String? produtoId, String? rotulo) async {
    await DestaqueLojaService.instance
        .definirComoAdmin(widget.restaurantId, produtoId, rotulo);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado) return const SizedBox.shrink();
    return EditorDestaqueLoja(
      key: ValueKey('${_destaque?.produtoId}|${_destaque?.rotulo}'),
      produtos: _produtos,
      inicial: _destaque,
      onGuardar: _salvar,
      textos: EditorDestaqueTextos.admin,
    );
  }
}
