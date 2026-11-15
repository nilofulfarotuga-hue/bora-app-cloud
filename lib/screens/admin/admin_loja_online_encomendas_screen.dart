// lib/screens/admin/admin_loja_online_encomendas_screen.dart
//
// Painel (PT-BR) — Loja Online: encomendas a fazer ao fornecedor (checkup-geral-15-11, B3.7).
// Lista por estado (pagas primeiro), endereço de envio, custo e preço, e os passos de logística
// (encomendada no fornecedor → enviada com rastreio → entregue / cancelada), sempre com motivo
// e auditoria (admin_loja_online_encomenda_estado). "Ver pagamento" pergunta à Stripe pela Edge.
// Cancelar NÃO devolve dinheiro: o reembolso é da zona do dinheiro e fica com o Danilo.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/loja_online_produto.dart';
import '../../services/loja_online_pagamento_service.dart';
import '../../services/loja_online_service.dart';

/// Nome do estado para o painel.
String adminEstadoEncomenda(String estado) {
  switch (estado) {
    case 'aguarda_pagamento':
      return 'Aguardando pagamento';
    case 'paga':
      return 'PAGA — encomendar no fornecedor';
    case 'encomendada_fornecedor':
      return 'Encomendada no fornecedor';
    case 'enviada':
      return 'Enviada (com rastreio)';
    case 'entregue':
      return 'Entregue';
    case 'cancelada':
      return 'Cancelada';
    case 'falhou_pagamento':
      return 'Pagamento falhou';
    default:
      return estado;
  }
}

/// O próximo passo de logística permitido a partir de um estado (null = nenhum).
String? adminProximoPasso(String estado) {
  switch (estado) {
    case 'paga':
      return 'encomendada_fornecedor';
    case 'encomendada_fornecedor':
      return 'enviada';
    case 'enviada':
      return 'entregue';
    default:
      return null;
  }
}

class AdminLojaOnlineEncomendasScreen extends StatefulWidget {
  const AdminLojaOnlineEncomendasScreen({super.key, this.listar, this.mudar});

  /// Injetáveis para os testes.
  final Future<List<Map<String, dynamic>>> Function(String? estado)? listar;
  final Future<void> Function(Map<String, dynamic> params)? mudar;

  @override
  State<AdminLojaOnlineEncomendasScreen> createState() =>
      _AdminLojaOnlineEncomendasScreenState();
}

class _AdminLojaOnlineEncomendasScreenState
    extends State<AdminLojaOnlineEncomendasScreen> {
  List<Map<String, dynamic>> _lista = const [];
  bool _carregando = true;
  String? _erro;
  String? _filtro = 'paga';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  static Future<List<Map<String, dynamic>>> _listarNoSupabase(
      String? estado) async {
    final r = await Supabase.instance.client
        .rpc(kLojaOnlineRpcEncomendas, params: {'p_estado': estado});
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<void> _mudarNoSupabase(Map<String, dynamic> params) async {
    await Supabase.instance.client
        .rpc(kLojaOnlineRpcEncomendaEstado, params: params);
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await (widget.listar ?? _listarNoSupabase)(_filtro);
      if (mounted) setState(() => _lista = l);
    } catch (e) {
      if (mounted) {
        setState(() => _erro = lojaOnlineServidorEmFalta(e)
            ? kLojaOnlineNaoInstalada
            : 'Não deu para carregar: $e');
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _passo(Map<String, dynamic> e, String novo) async {
    final ref = TextEditingController(text: '${e['fornecedor_ref'] ?? ''}');
    final rastreio = TextEditingController(text: '${e['tracking'] ?? ''}');
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mudar para: ${adminEstadoEncomenda(novo)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (novo == 'cancelada')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                      'Cancelar aqui NÃO devolve o dinheiro ao cliente. O '
                      'reembolso é feito à parte, com autorização do Danilo.',
                      style: TextStyle(color: AppColors.error)),
                ),
              TextField(
                controller: ref,
                decoration: const InputDecoration(
                    labelText: 'Nº da encomenda no fornecedor (CJ/Shopify)'),
              ),
              TextField(
                controller: rastreio,
                decoration:
                    const InputDecoration(labelText: 'Código de rastreio'),
              ),
              TextField(
                key: const Key('loja_online_encomenda_motivo'),
                controller: motivo,
                decoration: const InputDecoration(
                    labelText: 'Motivo (fica no registro, mínimo 3 letras)'),
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
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    if (motivo.text.trim().length < 3) {
      _aviso('Escreva o motivo (mínimo 3 letras).');
      return;
    }
    try {
      await (widget.mudar ?? _mudarNoSupabase)({
        'p_id': e['id'],
        'p_estado': novo,
        'p_fornecedor_ref': ref.text.trim(),
        'p_tracking': rastreio.text.trim(),
        'p_motivo': motivo.text.trim(),
      });
      _aviso('Feito.');
      await _carregar();
    } catch (err) {
      _aviso('Não deu: $err');
    }
  }

  Future<void> _verPagamento(Map<String, dynamic> e) async {
    try {
      final estado =
          await LojaOnlinePagamentoService().confirmar('${e['id']}');
      _aviso('Stripe: ${adminEstadoEncomenda(estado)}');
      await _carregar();
    } catch (err) {
      _aviso('Não deu para ver o pagamento: $err');
    }
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Widget _cartao(Map<String, dynamic> e) {
    final estado = '${e['estado'] ?? ''}';
    final proximo = adminProximoPasso(estado);
    final custo = _int(e['custo_unit_cents']) * _int(e['quantidade']);
    final morada =
        '${e['nome']}\n${e['morada']}\n${e['codigo_postal']} ${e['localidade']}\n${e['telefone']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e['titulo']} × ${_int(e['quantidade'])}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(adminEstadoEncomenda(estado),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: estado == 'paga'
                        ? AppColors.accent
                        : AppColors.primary)),
            Text('Cliente pagou ${formatarEurosCents(_int(e['total_cents']))} '
                '(${e['metodo'] == 'mbway' ? 'MB WAY' : 'cartão'}, conta ${e['stripe_account']}) · '
                'custo fornecedor ${formatarEurosCents(custo)}'),
            Text('Criada: ${e['criado_em'] ?? ''}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SelectableText(morada),
            if ('${e['fornecedor_ref'] ?? ''}'.isNotEmpty)
              Text('Fornecedor: ${e['fornecedor_ref']}'),
            if ('${e['tracking'] ?? ''}'.isNotEmpty)
              Text('Rastreio: ${e['tracking']}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: morada)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar endereço'),
                ),
                if (estado == 'aguarda_pagamento')
                  TextButton(
                      onPressed: () => _verPagamento(e),
                      child: const Text('Ver pagamento')),
                if (proximo != null)
                  FilledButton(
                      onPressed: () => _passo(e, proximo),
                      child: Text(adminEstadoEncomenda(proximo))),
                if (estado == 'paga' || estado == 'encomendada_fornecedor')
                  TextButton(
                      onPressed: () => _passo(e, 'cancelada'),
                      child: const Text('Cancelar encomenda')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const filtros = <String?, String>{
      'paga': 'A encomendar',
      'encomendada_fornecedor': 'No fornecedor',
      'enviada': 'Enviadas',
      null: 'Todas',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Loja Online — encomendas')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (final f in filtros.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.value),
                      selected: _filtro == f.key,
                      onSelected: (_) {
                        setState(() => _filtro = f.key);
                        _carregar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Center(child: Text(_erro!))
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: _lista.isEmpty
                            ? ListView(children: const [
                                Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('Nenhuma encomenda aqui.',
                                      textAlign: TextAlign.center),
                                ),
                              ])
                            : ListView(
                                padding: const EdgeInsets.all(12),
                                children: [for (final e in _lista) _cartao(e)],
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
