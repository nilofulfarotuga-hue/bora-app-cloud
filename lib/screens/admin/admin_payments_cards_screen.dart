import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/saved_card.dart';
import '../../services/admin/admin_payments_service.dart';
import '../../services/admin_audit_service.dart';
import '../../services/admin_export_service.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Admin — Pagamentos/Cartões (Carteira Única, Parte 6/6). Painel em PT-BR.
///
/// Três abas:
///   • Cobranças — histórico de todas as verticais (RPC admin_list_payments),
///     com filtro, busca, exportação CSV e estorno.
///   • Travados  — PaymentIntents parados em 3DS. Esse estado é transitório e
///     não fica gravado no banco, então vem direto da Stripe.
///   • Cartões   — cartões guardados de um cliente. Só marca e últimos 4
///     dígitos: o número completo nunca sai da Stripe, nem para o admin.
class AdminPaymentsCardsScreen extends StatefulWidget {
  const AdminPaymentsCardsScreen({super.key, this.service});

  /// Injetável para testes.
  final AdminPaymentsService? service;

  @override
  State<AdminPaymentsCardsScreen> createState() =>
      _AdminPaymentsCardsScreenState();
}

class _AdminPaymentsCardsScreenState extends State<AdminPaymentsCardsScreen>
    with SingleTickerProviderStateMixin {
  AdminPaymentsService get _svc => widget.service ?? AdminPaymentsService.instance;

  late final TabController _tabs = TabController(length: 3, vsync: this);

  // Aba Cobranças
  List<AdminPaymentRow> _pagamentos = const [];
  bool _carregando = true;
  String? _erro;
  String? _vertical;
  final _buscaCtrl = TextEditingController();

  // Aba Travados
  List<AdminStuckIntent> _travados = const [];
  bool _travadosCarregados = false;
  String? _erroTravados;

  // Aba Cartões
  final _userIdCtrl = TextEditingController();
  List<SavedCard> _cartoes = const [];
  bool _buscandoCartoes = false;
  String? _erroCartoes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscaCtrl.dispose();
    _userIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await _svc.listarPagamentos(
        vertical: _vertical,
        busca: _buscaCtrl.text.trim().isEmpty ? null : _buscaCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _pagamentos = lista;
        _carregando = false;
      });
    } on AdminPaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    }
  }

  Future<void> _carregarTravados() async {
    setState(() {
      _travadosCarregados = true;
      _erroTravados = null;
    });
    try {
      final lista = await _svc.intentsTravados();
      if (!mounted) return;
      setState(() => _travados = lista);
    } on AdminPaymentsException catch (e) {
      if (!mounted) return;
      setState(() => _erroTravados = e.mensagem);
    }
  }

  Future<void> _buscarCartoes() async {
    final id = _userIdCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _buscandoCartoes = true;
      _erroCartoes = null;
      _cartoes = const [];
    });
    try {
      final lista = await _svc.cartoesDoUsuario(id);
      if (!mounted) return;
      setState(() {
        _cartoes = lista;
        _buscandoCartoes = false;
      });
      AdminAuditService.logAction(
        action: 'admin_viewed_saved_cards',
        entityType: 'user',
        entityId: id,
        details: {'quantidade': lista.length},
      );
    } on AdminPaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _erroCartoes = e.mensagem;
        _buscandoCartoes = false;
      });
    }
  }

  Future<void> _exportarCsv() async {
    if (_pagamentos.isEmpty) {
      _aviso('Nada para exportar.');
      return;
    }
    await AdminExportService.instance.exportCsv(
      filename: 'bora_pagamentos.csv',
      headers: const [
        'Vertical', 'ID', 'Cliente', 'PaymentIntent',
        'Valor (EUR)', 'Status', 'Método', 'Data',
      ],
      rows: _pagamentos
          .map((p) => <dynamic>[
                p.verticalRotulo,
                p.entityId,
                p.userId ?? '',
                p.paymentIntentId ?? '',
                (p.amountCents / 100).toStringAsFixed(2),
                p.status ?? '',
                p.paymentMethod ?? '',
                p.createdAt?.toIso8601String() ?? '',
              ])
          .toList(),
      subject: 'Pagamentos Bora',
    );
    AdminAuditService.logAction(
      action: 'admin_exported_payments_csv',
      entityType: 'payments',
      details: {'linhas': _pagamentos.length, 'vertical': _vertical ?? 'todas'},
    );
  }

  Future<void> _confirmarEstorno(AdminPaymentRow p) async {
    final motivoCtrl = TextEditingController();
    final valorCtrl =
        TextEditingController(text: (p.amountCents / 100).toStringAsFixed(2));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar pagamento?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.verticalRotulo} · ${p.entityId}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(p.paymentIntentId ?? '',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor a estornar (EUR)',
                helperText: 'Não pode passar do valor capturado.',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo (fica na auditoria)',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const Text(
              'Isso devolve dinheiro de verdade ao cliente e não tem desfazer.',
              style: TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final euros = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
    if (euros <= 0) {
      _aviso('Valor inválido.');
      return;
    }
    try {
      final refundId = await _svc.estornar(
        paymentIntentId: p.paymentIntentId!,
        amountCents: (euros * 100).round(),
        userId: p.userId,
        entityId: p.entityId,
        vertical: p.vertical,
        motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
      );
      if (!mounted) return;
      _aviso('Estorno feito${refundId != null ? ' ($refundId)' : ''}.');
      await _carregar();
    } on AdminPaymentsException catch (e) {
      if (!mounted) return;
      _aviso(e.mensagem, erro: true);
    }
  }

  void _aviso(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthAdminService.isAdmin()) {
      return const Scaffold(
        appBar: BoraScreenAppBar(title: 'Pagamentos/Cartões'),
        body: Center(child: Text('Acesso restrito a administradores.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pagamentos/Cartões',
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.download),
            onPressed: _exportarCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: AppColors.primary,
            child: TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              onTap: (i) {
                if (i == 1 && !_travadosCarregados) _carregarTravados();
              },
              tabs: const [
                Tab(text: 'Cobranças'),
                Tab(text: 'Travados'),
                Tab(text: 'Cartões'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_abaCobrancas(), _abaTravados(), _abaCartoes()],
            ),
          ),
        ],
      ),
    );
  }

  // ── aba 1: cobranças ──────────────────────────────────────────────────────
  Widget _abaCobrancas() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscaCtrl,
                  onSubmitted: (_) => _carregar(),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ID, PaymentIntent ou usuário',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              DropdownButton<String?>(
                value: _vertical,
                hint: const Text('Todas'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...AdminPaymentRow.rotulosVertical.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _vertical = v);
                  _carregar();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? _mensagemErro(_erro!, _carregar)
                  : _pagamentos.isEmpty
                      ? const Center(child: Text('Nenhuma cobrança encontrada.'))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(Spacing.md),
                            itemCount: _pagamentos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: Spacing.sm),
                            itemBuilder: (_, i) => _cardPagamento(_pagamentos[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _cardPagamento(AdminPaymentRow p) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.md),
        boxShadow: AppColors.shadowCard,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.verticalRotulo} · ${p.valorFormatado}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: Spacing.xxs),
                Text(
                  '${p.status ?? 'sem status'} · ${p.paymentMethod ?? '—'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  p.paymentIntentId ?? 'sem PaymentIntent',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSubtle),
                ),
              ],
            ),
          ),
          if (p.podeEstornar)
            TextButton(
              onPressed: () => _confirmarEstorno(p),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Estornar'),
            ),
        ],
      ),
    );
  }

  // ── aba 2: travados ───────────────────────────────────────────────────────
  Widget _abaTravados() {
    if (_erroTravados != null) {
      return _mensagemErro(_erroTravados!, _carregarTravados);
    }
    if (!_travadosCarregados) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_travados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xxl),
          child: Text(
            'Nenhum pagamento parado em autenticação (3DS).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregarTravados,
      child: ListView.separated(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: _travados.length,
        separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
        itemBuilder: (_, i) {
          final t = _travados[i];
          return Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(Radii.md),
              boxShadow: AppColors.shadowCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('€${(t.amountCents / 100).toStringAsFixed(2)} · ${t.status}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(t.id,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
                if (t.metadata.isNotEmpty)
                  Text(
                    t.metadata.entries
                        .map((e) => '${e.key}=${e.value}')
                        .join(' · '),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── aba 3: cartões ────────────────────────────────────────────────────────
  Widget _abaCartoes() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _userIdCtrl,
                onSubmitted: (_) => _buscarCartoes(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'ID do usuário (UUID)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              onPressed: _buscandoCartoes ? null : _buscarCartoes,
              child: const Text('Buscar'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (_buscandoCartoes)
          const Center(child: CircularProgressIndicator())
        else if (_erroCartoes != null)
          Text(_erroCartoes!, style: const TextStyle(color: AppColors.error))
        else
          ..._cartoes.map(
            (c) => ListTile(
              leading: const Icon(Icons.credit_card, color: AppColors.primary),
              title: Text('${c.prettyBrand} •••• ${c.last4}'),
              subtitle: Text('Validade ${c.prettyExpiry}'
                  '${c.isDefault ? ' · principal' : ''}'),
            ),
          ),
        const SizedBox(height: Spacing.lg),
        const Text(
          'Guardamos apenas marca e os 4 últimos dígitos. O número completo '
          'fica na Stripe e não é acessível nem pelo painel.',
          style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
        ),
      ],
    );
  }

  Widget _mensagemErro(String msg, Future<void> Function() tentarDeNovo) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: Spacing.md),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            OutlinedButton(
              onPressed: () => tentarDeNovo(),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
