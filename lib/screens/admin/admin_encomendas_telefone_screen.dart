import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../utils/hora_lisboa_ext.dart';

/// Painel admin (PT-BR) — Encomendas por telefone (missão 03/10 · bloco 6).
///
/// Lojas não-parceiras que não usam a app (Pôr do Sol, Fuku, Jyosmi, Tiago's,
/// DaVinci, Amaya): quando entra um pedido, a Bora liga à loja. Aqui aparece o
/// mesmo cartão do alerta (resumo com preço de BALCÃO), o botão "Ligar para a
/// loja" e "Encomendado à loja" (grava quem ligou e a que horas). O estafeta só
/// é chamado `dispatch_delay_minutes` depois. Em baixo: ligar/desligar por loja,
/// número e minutos.
class AdminEncomendasTelefoneScreen extends StatefulWidget {
  const AdminEncomendasTelefoneScreen({super.key});

  @override
  State<AdminEncomendasTelefoneScreen> createState() =>
      _AdminEncomendasTelefoneScreenState();
}

class _AdminEncomendasTelefoneScreenState
    extends State<AdminEncomendasTelefoneScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _pedidos = const [];
  List<Map<String, dynamic>> _lojas = const [];
  String? _aGravar;

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
      final p = await _sb.rpc('admin_listar_encomendas_telefone', params: {'p_dias': 7});
      final l = await _sb
          .from('restaurants')
          .select('id, name, phone, order_by_phone, phone_order_number, dispatch_delay_minutes, phone_prep_minutes')
          .eq('is_partner', false)
          .order('order_by_phone', ascending: false)
          .order('name');
      if (!mounted) return;
      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(p as List);
        _lojas = List<Map<String, dynamic>>.from(l as List);
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

  Future<void> _ligar(String? numero) async {
    if (numero == null || numero.isEmpty) return;
    await launchUrl(Uri.parse('tel:${numero.replaceAll(' ', '')}'));
  }

  Future<void> _encomendado(String orderId) async {
    if (_aGravar != null) return;
    setState(() => _aGravar = orderId);
    try {
      final r = await _sb.rpc('admin_encomendado_a_loja', params: {'p_order_id': orderId});
      final m = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(m['ok'] == true
              ? 'Registrado. O entregador é chamado às ${m['estafeta_chamado_as']}.'
              : 'Já estava encomendado (ou o pedido saiu da fila).')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
  }

  Future<void> _editarLoja(Map<String, dynamic> l) async {
    var ligado = l['order_by_phone'] == true;
    final numero = TextEditingController(
        text: (l['phone_order_number'] ?? l['phone'] ?? '').toString());
    final atraso = TextEditingController(
        text: '${l['dispatch_delay_minutes'] ?? 15}');
    final prep =
        TextEditingController(text: '${l['phone_prep_minutes'] ?? 20}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(l['name']?.toString() ?? ''),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: ligado,
                onChanged: (v) => set(() => ligado = v),
                title: const Text('Encomenda por telefone'),
                contentPadding: EdgeInsets.zero,
              ),
              TextField(
                  controller: numero,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Número para ligar')),
              TextField(
                  controller: atraso,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Minutos até chamar o entregador')),
              TextField(
                  controller: prep,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Minutos de preparo (o cliente vê a hora)')),
            ],
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
    if (ok != true) return;
    try {
      await _sb.rpc('admin_definir_loja_telefone', params: {
        'p_restaurant_id': l['id'],
        'p_ligado': ligado,
        'p_numero': numero.text.trim(),
        'p_atraso': int.tryParse(atraso.text) ?? 15,
        'p_prep': int.tryParse(prep.text) ?? 20,
      });
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  String _hora(dynamic iso) {
    if (iso == null) return '—';
    final t = DateTime.tryParse(iso.toString())?.toLisboa();
    if (t == null) return '—';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _cartao(Map<String, dynamic> p) {
    final aberto = p['libertado_em'] == null && p['cancelado_em'] == null;
    final encomendado = p['encomendado_em'] != null;
    return Card(
      color: aberto && !encomendado ? const Color(0xFFFFF7ED) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p['loja']} · ${_hora(p['criado_em'])}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(p['resumo']?.toString() ?? ''),
            const SizedBox(height: 6),
            Text(
              encomendado
                  ? 'Encomendado por ${p['encomendado_por_nome'] ?? '?'} às ${_hora(p['encomendado_em'])}'
                  : 'Ainda não encomendado · ${p['alertas']} aviso(s)',
              style: TextStyle(
                  color: encomendado ? AppColors.primary : AppColors.warning,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              p['libertado_em'] != null
                  ? 'Entregador chamado às ${_hora(p['libertado_em'])}'
                  : p['cancelado_em'] != null
                      ? 'Pedido ${p['estado_pedido']}'
                      : 'Entregador será chamado às ${_hora(p['chama_estafeta_as'])}',
              style: const TextStyle(fontSize: 12),
            ),
            if (aberto) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _ligar(p['telefone']?.toString()),
                    icon: const Icon(Icons.call),
                    label: Text('Ligar para a loja (${p['telefone'] ?? '?'})'),
                  ),
                  if (!encomendado)
                    FilledButton.icon(
                      onPressed: _aGravar != null
                          ? null
                          : () => _encomendado(p['order_id'] as String),
                      icon: const Icon(Icons.check),
                      label: const Text('Encomendado à loja'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Encomendas por telefone',
        actions: [
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
                      const Text('Pedidos (últimos 7 dias)',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      if (_pedidos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Nenhum pedido de loja por telefone.'),
                        ),
                      for (final p in _pedidos) _cartao(p),
                      const SizedBox(height: 24),
                      const Text('Lojas não parceiras',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      for (final l in _lojas)
                        ListTile(
                          title: Text(l['name']?.toString() ?? ''),
                          subtitle: Text(l['order_by_phone'] == true
                              ? 'Por telefone · ${l['phone_order_number'] ?? l['phone'] ?? 'sem número'}'
                                  ' · entregador após ${l['dispatch_delay_minutes']} min'
                                  ' · preparo ${l['phone_prep_minutes']} min'
                              : 'Fluxo normal (sem ligação)'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editarLoja(l),
                        ),
                    ],
                  ),
                ),
    );
  }
}
