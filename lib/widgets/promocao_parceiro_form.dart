import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/promocao.dart';
import '../services/partner_price_rules.dart';
import '../services/promocoes_service.dart';

/// Promoção de um produto, no ecrã de editar produto do parceiro
/// (adendo 5 · item 4, 29/10/2026).
///
/// O parceiro escreve o preço promocional no mesmo sentido do preço normal: numa
/// loja parceira é o balcão ("o que recebes") e a app mostra quanto o cliente
/// vai ver; numa loja não parceira é o preço de catálogo. Escolhe o início
/// (por defeito, agora) e, se quiser, o fim. A app do cliente risca o preço
/// antigo e mostra a linha dos 30 dias sozinha.
///
/// Só aparece com o interruptor `promotions_enabled` ligado no painel admin.
/// Tem os seus próprios botões (Guardar / Terminar), independentes do "Guardar
/// produto" do ecrã.
class PromocaoParceiroForm extends StatefulWidget {
  const PromocaoParceiroForm({
    super.key,
    required this.product,
    required this.lojaParceira,
    this.regras,
    this.api,
    this.aoGuardar,
  });

  final PartnerProduct product;
  final bool lojaParceira;

  /// Percentagens da plataforma (só interessam a lojas parceiras).
  final PartnerPriceRules? regras;

  /// Só para testes: troca o servidor por uma porta de mentira.
  final PromocoesApi? api;

  final VoidCallback? aoGuardar;

  @override
  State<PromocaoParceiroForm> createState() => _PromocaoParceiroFormState();
}

class _PromocaoParceiroFormState extends State<PromocaoParceiroForm> {
  late final PromocoesApi _api = widget.api ?? PromocoesApiSupabase();
  final _preco = TextEditingController();
  bool _ligado = false;
  bool _ocupado = false;
  PromocaoDefinida? _atual;
  DateTime? _inicio;
  DateTime? _fim;
  String? _erro;
  String? _ok;

  /// O preço normal no mesmo sentido do que o parceiro escreve.
  double get _normal => widget.lojaParceira
      ? (widget.product.partnerShelfPrice ?? widget.product.price)
      : widget.product.price;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _preco.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    bool ligado;
    try {
      ligado = await _api.ligado();
    } catch (_) {
      ligado = false;
    }
    PromocaoDefinida? atual;
    if (ligado) {
      try {
        atual = await _api.doProduto(widget.product.id);
      } catch (_) {
        atual = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _ligado = ligado;
      _atual = atual;
      if (atual != null && atual.existe) {
        _inicio = atual.inicio;
        _fim = atual.fim;
        _preco.clear();
        _preencherPreco();
      }
    });
  }

  /// Põe no campo o preço da promoção que já existe, no sentido que o parceiro
  /// escreve (balcão numa loja parceira). Espera pelas percentagens se faltarem.
  void _preencherPreco() {
    final a = _atual;
    if (a == null || !a.existe || _preco.text.isNotEmpty) return;
    if (widget.lojaParceira && widget.regras == null) return;
    final cliente = a.precoPromocional!;
    final escrito = widget.lojaParceira
        ? widget.regras!.shelfFromAppPrice(cliente)
        : cliente;
    _preco.text = escrito.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void didUpdateWidget(covariant PromocaoParceiroForm old) {
    super.didUpdateWidget(old);
    if (old.regras == null && widget.regras != null) {
      setState(_preencherPreco);
    }
  }

  static double? _ler(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.').replaceAll('€', '').trim());

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _escolher({required bool inicio}) async {
    final hoje = DateTime.now();
    final base = (inicio ? _inicio : _fim) ?? hoje;
    final r = await showDatePicker(
      context: context,
      initialDate: base.isBefore(hoje) ? hoje : base,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (r == null || !mounted) return;
    setState(() {
      // Início à meia-noite do dia; fim no último segundo do dia.
      if (inicio) {
        _inicio = DateTime(r.year, r.month, r.day);
      } else {
        _fim = DateTime(r.year, r.month, r.day, 23, 59, 59);
      }
    });
  }

  Future<void> _guardar() async {
    if (_ocupado) return;
    setState(() {
      _erro = null;
      _ok = null;
    });
    final x = _ler(_preco.text);
    if (x == null || x <= 0 || x >= _normal) {
      setState(() => _erro =
          'O preço promocional tem de ser maior que zero e menor que o preço normal (${_eur(_normal)}).');
      return;
    }
    double catalogo = x;
    if (widget.lojaParceira) {
      final regras = widget.regras;
      if (regras == null) {
        setState(() => _erro =
            'Não foi possível ler as percentagens da plataforma. Verifica a ligação e tenta outra vez.');
        return;
      }
      catalogo = regras.appPriceFromShelf(x);
    }
    if (catalogo >= widget.product.price) {
      setState(() => _erro =
          'O preço promocional tem de ficar abaixo do preço que o cliente vê hoje.');
      return;
    }
    if (_inicio != null && _fim != null && !_fim!.isAfter(_inicio!)) {
      setState(() => _erro = 'O fim tem de ser depois do início.');
      return;
    }
    setState(() => _ocupado = true);
    try {
      await _api.definir(
        productId: widget.product.id,
        precoPromocional: catalogo,
        inicio: _inicio,
        fim: _fim,
      );
      if (!mounted) return;
      setState(() => _ok = 'Promoção guardada.');
      await _carregar();
      widget.aoGuardar?.call();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErroPromocao(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _terminar() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erro = null;
      _ok = null;
    });
    try {
      await _api.definir(productId: widget.product.id, precoPromocional: null);
      if (!mounted) return;
      _preco.clear();
      setState(() {
        _atual = null;
        _inicio = null;
        _fim = null;
        _ok = 'Promoção terminada.';
      });
      widget.aoGuardar?.call();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErroPromocao(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  static String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  String? _estadoTexto() {
    final a = _atual;
    if (a == null || !a.existe) return null;
    final estado = estadoDaPromocao(
      preco: widget.product.price,
      precoPromocional: a.precoPromocional,
      ativada: a.ativada,
      inicio: a.inicio,
      fim: a.fim,
      agora: DateTime.now(),
    );
    switch (estado) {
      case EstadoPromocao.ativa:
        return 'Promoção ativa agora.';
      case EstadoPromocao.agendada:
        return 'Promoção agendada: ainda não começou.';
      case EstadoPromocao.expirada:
        return 'Esta promoção já terminou.';
      case EstadoPromocao.desligada:
        return 'Promoção desligada pela Bora. Fala com o suporte se for engano.';
      case EstadoPromocao.semDatas:
        return 'Guarda com um início para a promoção começar.';
      case EstadoPromocao.invalida:
        return 'O preço promocional já não é menor que o preço normal.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final x = _ler(_preco.text);
    String? vistaCliente;
    if (widget.lojaParceira && widget.regras != null && x != null && x > 0) {
      vistaCliente =
          'O cliente vê ${_eur(widget.regras!.appPriceFromShelf(x))} em vez de ${_eur(widget.product.price)}.';
    }
    final estado = _estadoTexto();
    return Container(
      key: const Key('promocao_parceiro'),
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.local_offer_outlined, size: 20, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Promoção',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Text(
            'O cliente vê o preço normal riscado e este preço novo. A app mostra '
            'também, sozinha, o preço mais baixo dos últimos 30 dias, como a lei pede.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
          ),
          if (estado != null) ...[
            const SizedBox(height: 8),
            Text(estado,
                key: const Key('promo_estado'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const Key('promo_preco'),
            controller: _preco,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.lojaParceira
                  ? 'Preço promocional que recebes (€)'
                  : 'Preço promocional (€)',
              helperText: vistaCliente ?? 'Preço normal: ${_eur(_normal)}',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const Key('promo_inicio'),
                onPressed: _ocupado ? null : () => _escolher(inicio: true),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(_inicio == null ? 'Início: agora' : 'Início: ${_data(_inicio!)}'),
              ),
              OutlinedButton.icon(
                key: const Key('promo_fim'),
                onPressed: _ocupado ? null : () => _escolher(inicio: false),
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: Text(_fim == null ? 'Fim: sem fim' : 'Fim: ${_data(_fim!)}'),
              ),
              if (_fim != null || _inicio != null)
                TextButton(
                  onPressed: _ocupado
                      ? null
                      : () => setState(() {
                            _inicio = null;
                            _fim = null;
                          }),
                  child: const Text('Limpar datas'),
                ),
            ],
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!,
                key: const Key('promo_erro'),
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          if (_ok != null) ...[
            const SizedBox(height: 8),
            Text(_ok!,
                key: const Key('promo_ok'),
                style: const TextStyle(color: AppColors.primary, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const Key('promo_guardar'),
                onPressed: _ocupado ? null : _guardar,
                child: Text(_ocupado ? 'A guardar…' : 'Guardar promoção'),
              ),
            ),
            if (_atual?.existe ?? false) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const Key('promo_terminar'),
                onPressed: _ocupado ? null : _terminar,
                child: const Text('Terminar promoção'),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
