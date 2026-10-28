// lib/screens/admin/admin_alergenos_screen.dart
//
// ALERGÊNICOS NO PAINEL (melhorias-paridade 26/10, item 17).
//
// Obrigação legal (Regulamento UE 1169/2011, Anexo II: 14 alergênicos de
// declaração obrigatória). A coluna `products.allergens` (text[]) já existia e
// o app do cliente já mostra os alergênicos na ficha do produto, mas só o
// parceiro conseguia preenchê-los — e a 26/10 apenas 1 de 58 227 produtos os
// tinha. Aqui o admin vê, por loja, quais produtos têm a informação e corrige.
//
// Grava direto em `products.allergens` (a RLS de products deixa o admin
// editar — provado a 26/10 numa transação desfeita) e registra em
// log_admin_action.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/allergens.dart';
import '../../config/app_colors.dart';
import '../../services/admin_audit_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAlergenosScreen extends StatefulWidget {
  const AdminAlergenosScreen({super.key});

  @override
  State<AdminAlergenosScreen> createState() => _AdminAlergenosScreenState();
}

class _AdminAlergenosScreenState extends State<AdminAlergenosScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _lojas = const [];
  String? _lojaId;
  List<Map<String, dynamic>> _produtos = const [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregarLojas();
  }

  Future<void> _carregarLojas() async {
    try {
      final res = await _sb
          .from('restaurants')
          .select('id, name, category')
          .order('name');
      if (!mounted) return;
      setState(() {
        _lojas = List<Map<String, dynamic>>.from(res as List);
        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = '$e';
          _carregando = false;
        });
      }
    }
  }

  Future<void> _carregarProdutos(String lojaId) async {
    setState(() {
      _lojaId = lojaId;
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _sb
          .from('products')
          .select('id, name, category, allergens')
          .eq('restaurant_id', lojaId)
          .order('name')
          .limit(1000);
      // Escolheu outra loja entretanto: esta resposta já não interessa.
      if (!mounted || lojaId != _lojaId) return;
      setState(() {
        _produtos = List<Map<String, dynamic>>.from(res as List);
        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = '$e';
          _carregando = false;
        });
      }
    }
  }

  static List<String> _alergenos(Map<String, dynamic> p) =>
      ((p['allergens'] as List?) ?? const []).map((e) => '$e').toList();

  Future<void> _editar(Map<String, dynamic> p) async {
    final escolhidos = _alergenos(p).toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(p['name']?.toString() ?? 'Produto'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in kAllergenLabels.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: escolhidos.contains(e.key),
                    onSelected: (v) => setD(() =>
                        v ? escolhidos.add(e.key) : escolhidos.remove(e.key)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final antes = _alergenos(p);
    // Códigos antigos fora dos 14 (outra grafia) ficam — não se apagam calados.
    final depois = [
      ...antes.where((a) => !kAllergenLabels.containsKey(a)),
      ...kAllergenLabels.keys.where(escolhidos.contains),
    ];
    try {
      final linhas = await _sb
          .from('products')
          .update({'allergens': depois})
          .eq('id', p['id'] as String)
          .select('id');
      if ((linhas as List).isEmpty) {
        throw StateError('nenhuma linha gravada (sem permissão?)');
      }
      await AdminAuditService.logAction(
        action: 'product_allergens_updated',
        entityType: 'product',
        entityId: p['id'] as String,
        details: {'antes': antes, 'depois': depois},
      );
      if (!mounted) return;
      setState(() => p['allergens'] = depois);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alergênicos salvos.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _produtos
        .where((p) => (p['name']?.toString() ?? '')
            .toLowerCase()
            .contains(_busca.toLowerCase()))
        .toList();
    final comInfo = _produtos.where((p) => _alergenos(p).isNotEmpty).length;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Alergênicos dos produtos'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Os 14 alergênicos de declaração obrigatória na UE (Regulamento '
              '1169/2011). O cliente vê-os na ficha do produto.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _lojaId,
              hint: const Text('Escolha a loja'),
              items: [
                for (final l in _lojas)
                  DropdownMenuItem(
                    value: l['id'] as String,
                    child: Text(l['name']?.toString() ?? '—'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _carregarProdutos(v);
              },
            ),
          ),
          if (_lojaId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar produto',
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          if (_lojaId != null && !_carregando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                _produtos.length >= 1000
                    ? '$comInfo dos primeiros 1000 produtos com alergênicos informados (use a busca)'
                    : '$comInfo de ${_produtos.length} produtos com alergênicos informados',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erro: $_erro',
                  style: const TextStyle(color: AppColors.error)),
            ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: visiveis.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = visiveis[i];
                      final a = _alergenos(p);
                      return ListTile(
                        title: Text(p['name']?.toString() ?? '—'),
                        subtitle: Text(
                          a.isEmpty
                              ? 'Sem alergênicos informados'
                              : a.map((s) => kAllergenLabels[s] ?? s).join(', '),
                          style: TextStyle(
                            color: a.isEmpty
                                ? AppColors.warning
                                : AppColors.textSecondary,
                          ),
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editar(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
