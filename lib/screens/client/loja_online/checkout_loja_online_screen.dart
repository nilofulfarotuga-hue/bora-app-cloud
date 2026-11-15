// lib/screens/client/loja_online/checkout_loja_online_screen.dart
//
// Loja Online — pagar uma encomenda (checkup-geral-15-11, B3.7). Morada de envio, quantidade
// (1 a 5), cartão ou MB WAY (NUNCA dinheiro: vai pelo correio). O total mostrado é preço × quantidade;
// o servidor volta a ler o preço da base e é esse que cobra.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/loja_online_produto.dart';
import '../../../models/client_address.dart';
import '../../../services/loja_online_pagamento_service.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

class CheckoutLojaOnlineScreen extends StatefulWidget {
  const CheckoutLojaOnlineScreen({
    super.key,
    required this.produto,
    this.servico,
    this.perfil,
  });

  final LojaOnlineProduto produto;

  /// Injetável para os testes.
  final LojaOnlinePagamentoService? servico;

  /// loja-nichos-15-11 (C): o que a app já sabe do cliente (nome, telemóvel,
  /// moradas guardadas). Por defeito: a conta da app e as moradas guardadas.
  final Future<LojaOnlinePerfil> Function()? perfil;

  @override
  State<CheckoutLojaOnlineScreen> createState() =>
      _CheckoutLojaOnlineScreenState();
}

class _CheckoutLojaOnlineScreenState extends State<CheckoutLojaOnlineScreen> {
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _morada = TextEditingController();
  final _codigoPostal = TextEditingController();
  final _localidade = TextEditingController(text: 'Guarda');
  int _quantidade = 1;
  LojaOnlineMetodo _metodo = LojaOnlineMetodo.mbway;
  bool _aPagar = false;
  String? _aviso;
  List<ClientAddress> _moradas = const [];
  String? _moradaEscolhida;

  @override
  void initState() {
    super.initState();
    _preencher();
  }

  /// Enche o que estiver vazio com o perfil e a morada predefinida. Nunca
  /// apaga o que o cliente já escreveu.
  Future<void> _preencher() async {
    LojaOnlinePerfil p;
    try {
      p = await (widget.perfil ?? _perfilDaApp)();
    } catch (e) {
      debugPrint('[LojaOnline] perfil: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_nome.text.trim().isEmpty && p.nome.trim().isNotEmpty) {
        _nome.text = p.nome.trim();
      }
      if (_telefone.text.trim().isEmpty && p.telefone.trim().isNotEmpty) {
        _telefone.text = p.telefone.trim();
      }
      _moradas = p.moradas;
      if (_morada.text.trim().isEmpty && p.moradas.isNotEmpty) {
        _usarMorada(p.moradas.first);
      }
    });
  }

  Future<LojaOnlinePerfil> _perfilDaApp() async {
    String nome = '', telefone = '';
    try {
      final c = Provider.of<AuthStore>(context, listen: false).currentClient;
      nome = c?.name ?? '';
      telefone = c?.phone ?? '';
    } catch (_) {
      // Sem AuthStore por cima (ex.: testes): fica só o que se escrever.
    }
    return LojaOnlinePerfil(
      nome: nome,
      telefone: telefone,
      moradas: await lojaOnlineMoradasGuardadas(),
    );
  }

  void _usarMorada(ClientAddress a) {
    _moradaEscolhida = a.id;
    final rua = [
      (a.street ?? '').trim().isNotEmpty ? a.street!.trim() : a.address.trim(),
      if ((a.details ?? '').trim().isNotEmpty) a.details!.trim(),
    ].join(', ');
    _morada.text = rua;
    final partes = lojaOnlinePartesDaMorada(a.address);
    final cp = (a.postalCode ?? '').trim().isNotEmpty
        ? a.postalCode!.trim()
        : partes.codigoPostal;
    if (cp != null) _codigoPostal.text = lojaOnlineCodigoPostal(cp) ?? cp;
    final loc = (a.city ?? '').trim().isNotEmpty ? a.city!.trim() : partes.localidade;
    if (loc != null && loc.isNotEmpty) _localidade.text = loc;
  }

  void _moradaDasSugestoes(String morada) {
    final partes = lojaOnlinePartesDaMorada(morada);
    setState(() {
      _moradaEscolhida = null;
      if (partes.codigoPostal != null) _codigoPostal.text = partes.codigoPostal!;
      if (partes.localidade != null) _localidade.text = partes.localidade!;
      // Na rua fica só a parte antes do código postal.
      final i = morada.indexOf(RegExp(r'[0-9]{4}-?[0-9]{3}'));
      if (i > 0) {
        _morada.text = morada.substring(0, i).replaceAll(RegExp(r'[,\s]+$'), '');
      }
    });
  }

  LojaOnlinePagamentoService get _servico =>
      widget.servico ?? LojaOnlinePagamentoService();

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _morada.dispose();
    _codigoPostal.dispose();
    _localidade.dispose();
    super.dispose();
  }

  int get _totalCents => widget.produto.precoBoraCents * _quantidade;

  Future<void> _pagar() async {
    final faltas = lojaOnlineFaltas(
      nome: _nome.text,
      telefone: _telefone.text,
      morada: _morada.text,
      codigoPostal: _codigoPostal.text,
      localidade: _localidade.text,
    );
    if (faltas.isNotEmpty) {
      setState(() => _aviso = faltas.first.tr);
      return;
    }
    setState(() {
      _aPagar = true;
      _aviso = _metodo == LojaOnlineMetodo.mbway
          ? 'Aceita o pagamento na app MB WAY do teu telemóvel.'.tr
          : null;
    });
    try {
      final criado = await _servico.criar(LojaOnlinePedidoPagamento(
        produtoId: widget.produto.id,
        quantidade: _quantidade,
        metodo: _metodo,
        nome: _nome.text,
        telefone: _telefone.text,
        morada: _morada.text,
        codigoPostal: _codigoPostal.text,
        localidade: _localidade.text,
      ));
      final id = criado['encomenda_id'] as String;
      if (_metodo == LojaOnlineMetodo.cartao) {
        await _servico.pagarComCartao(criado);
      }
      final estado = await _servico.esperarPagamento(
        id,
        limite: _metodo == LojaOnlineMetodo.cartao
            ? const Duration(seconds: 40)
            : const Duration(minutes: 5),
      );
      if (!mounted) return;
      if (kEncomendaEstadosFinais.contains(estado)) {
        await _mostrarSucesso();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _aviso = estado == 'aguarda_pagamento'
          ? 'Ainda não recebemos a confirmação do pagamento. Vê em "As minhas encomendas" daqui a pouco.'
              .tr
          : 'O pagamento não foi concluído. Não te foi cobrado nada.'.tr);
    } on StateError catch (e) {
      if (mounted) setState(() => _aviso = e.message.tr);
    } catch (e) {
      debugPrint('[LojaOnline] pagar: $e');
      if (mounted) {
        setState(() =>
            _aviso = 'O pagamento não foi concluído. Não te foi cobrado nada.'.tr);
      }
    } finally {
      if (mounted) setState(() => _aPagar = false);
    }
  }

  Future<void> _mostrarSucesso() {
    final prazo = widget.produto.prazoTexto;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Encomenda feita!'.tr),
        content: Text(prazo.isEmpty
            ? 'Vais receber a encomenda pelo correio.'.tr
            : prazo),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Fechar'.tr),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String rotulo,
      {TextInputType? teclado, Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: TextField(
        key: key,
        controller: c,
        keyboardType: teclado,
        enabled: !_aPagar,
        decoration: InputDecoration(
          labelText: rotulo,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.produto;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Encomendar'.tr),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text(p.titulo,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if (p.prazoTexto.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Text(p.prazoTexto,
                key: const Key('loja_online_checkout_prazo'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ],
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              Expanded(
                child: Text('Quantidade'.tr,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textPrimary)),
              ),
              IconButton(
                key: const Key('loja_online_menos'),
                onPressed: _aPagar || _quantidade <= 1
                    ? null
                    : () => setState(() => _quantidade--),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_quantidade',
                  key: const Key('loja_online_quantidade'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(
                key: const Key('loja_online_mais'),
                onPressed: _aPagar || _quantidade >= 5
                    ? null
                    : () => setState(() => _quantidade++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text('Morada de envio'.tr,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          _campo(_nome, 'Nome completo'.tr,
              key: const Key('loja_online_nome')),
          _campo(_telefone, 'Telemóvel'.tr,
              teclado: TextInputType.phone,
              key: const Key('loja_online_telefone')),
          if (_moradas.isNotEmpty) ...[
            Text('As tuas moradas'.tr,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.sm,
              children: [
                for (final a in _moradas)
                  ChoiceChip(
                    key: Key('loja_online_morada_guardada_${a.id}'),
                    label: Text(a.label),
                    selected: _moradaEscolhida == a.id,
                    onSelected: _aPagar ? null : (_) => setState(() => _usarMorada(a)),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          // A MESMA caixa de moradas com sugestões dos pedidos (Google Places).
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: AddressAutocompleteField(
              key: const Key('loja_online_morada'),
              controller: _morada,
              labelText: 'Rua, número e andar'.tr,
              prefixIcon: const Icon(Icons.home_outlined),
              onSelected: (morada, _) => _moradaDasSugestoes(morada),
              onChanged: (_) => setState(() => _moradaEscolhida = null),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _campo(_codigoPostal, 'Código postal'.tr,
                    key: const Key('loja_online_cp')),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _campo(_localidade, 'Localidade'.tr,
                    key: const Key('loja_online_localidade')),
              ),
            ],
          ),
          Text('Como queres pagar?'.tr,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          RadioListTile<LojaOnlineMetodo>(
            key: const Key('loja_online_mbway'),
            value: LojaOnlineMetodo.mbway,
            groupValue: _metodo,
            onChanged: _aPagar ? null : (v) => setState(() => _metodo = v!),
            title: const Text('MB WAY'),
          ),
          RadioListTile<LojaOnlineMetodo>(
            key: const Key('loja_online_cartao'),
            value: LojaOnlineMetodo.cartao,
            groupValue: _metodo,
            onChanged: _aPagar ? null : (v) => setState(() => _metodo = v!),
            title: Text('Cartão'.tr),
          ),
          Text(
            'Esta loja envia pelo correio: não há pagamento em dinheiro.'.tr,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (_aviso != null) ...[
            const SizedBox(height: Spacing.md),
            Text(_aviso!,
                key: const Key('loja_online_aviso'),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('loja_online_pagar'),
              onPressed: _aPagar ? null : _pagar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _aPagar
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(
                      'Pagar {0}'.trArgs([formatarEurosCents(_totalCents)]),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
