// FAVORES (errand) — Fase 3 UI Cliente
// Wizard 3 passos com rodapé sticky live (quote_order_pricing).
// UX 1–7: cards Normal/Expresso com tempos, paragem 1 linha, placeholder
// "Ex.: Vai à Farmácia Holon…", mensagem amigável forçar >€40, breakdown
// "ver detalhe", disclaimer receita-positiva (G1), resumo final com "~".
// Meta: a avó consegue pedir sem ajuda.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../services/payment_service.dart';
import '../stores/cart_store.dart';
import 'payment_method_screen.dart';

enum _ErrandStep { what, where, when }

/// Dados para pré-preenchimento (N3 "Pedir de novo" no histórico).
class ErrandPrefill {
  const ErrandPrefill({
    required this.description,
    required this.location,
    this.hasPurchase = false,
    this.estimatedCents = 0,
    this.speed = 'normal',
    this.homeStop = false,
    this.homeStopReason,
  });

  final String description;
  final String location;
  final bool hasPurchase;
  final int estimatedCents;
  final String speed;
  final bool homeStop;
  final String? homeStopReason;
}

class ErrandFormScreen extends StatefulWidget {
  const ErrandFormScreen({super.key, this.prefill});

  /// N3 — pré-preenche o wizard a partir de um pedido anterior.
  final ErrandPrefill? prefill;

  @override
  State<ErrandFormScreen> createState() => _ErrandFormScreenState();
}

class _ErrandFormScreenState extends State<ErrandFormScreen> {
  _ErrandStep _step = _ErrandStep.what;
  final _descCtrl = TextEditingController();
  final _estimateCtrl = TextEditingController();
  final _errandLocationCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();

  bool _hasPurchase = false;
  bool _homeStop = false;
  String _homeStopReason = 'cartao'; // receita | cartao | dinheiro | outro
  String _speed = 'normal'; // normal | express

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _descCtrl.text = p.description;
      _errandLocationCtrl.text = p.location;
      _hasPurchase = p.hasPurchase;
      if (p.estimatedCents > 0) {
        _estimateCtrl.text = (p.estimatedCents / 100).toStringAsFixed(2);
      }
      _speed = p.speed;
      _homeStop = p.homeStop;
      if (p.homeStopReason != null) _homeStopReason = p.homeStopReason!;
    }
  }

  // Coordenadas (preenchidas via autocomplete — placeholders por agora).
  LatLng? _errandLocation;
  LatLng? _dropoff;
  LatLng? _home;

  Map<String, dynamic>? _quote;
  bool _quoting = false;

  final _payment = PaymentService();

  static const _maxAdvanceCents = 4000; // €40 — força paragem-casa
  static const _maxCashCents = 4000; // limite cash global

  @override
  void dispose() {
    _descCtrl.dispose();
    _estimateCtrl.dispose();
    _errandLocationCtrl.dispose();
    _dropoffCtrl.dispose();
    super.dispose();
  }

  int get _estimatedCents {
    final raw = _estimateCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw) ?? 0;
    return (v * 100).round();
  }

  bool get _forcedHomeStopByEstimate =>
      _hasPurchase && _estimatedCents > _maxAdvanceCents;

  Future<void> _refreshQuote() async {
    if (_errandLocation == null || _dropoff == null) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _quoting = true);

    // Distância: aqui assumimos que o caller injeta um valor inicial via
    // DirectionsService (Fase 2/UI maps); como placeholder usamos 1 km para
    // que o backend ainda assim devolva um quote. A integração real do
    // multi-waypoint é feita pelo CartStore.refreshMultiSegmentDistance.
    final input = <String, dynamic>{
      'service_type': 'errand',
      'distance_km': 1.0,
      'errand_speed': _speed,
      'errand_home_stop': _homeStop || _forcedHomeStopByEstimate,
      'errand_home_stop_reason': (_homeStop || _forcedHomeStopByEstimate)
          ? _homeStopReason
          : null,
      'errand_has_purchase': _hasPurchase,
      'errand_estimated_purchase_cents': _estimatedCents,
      'errand_location_lat': _errandLocation!.latitude,
      'errand_location_lng': _errandLocation!.longitude,
      'dropoff_lat': _dropoff!.latitude,
      'dropoff_lng': _dropoff!.longitude,
      if (_home != null) ...{
        'pickup_lat': _home!.latitude,
        'pickup_lng': _home!.longitude,
      },
    };
    final q = await _payment.quoteOrder(input);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _quoting = false;
    });
  }

  void _onChange() {
    if (_forcedHomeStopByEstimate && !_homeStop) {
      _homeStop = true;
      _homeStopReason = 'dinheiro';
    }
    _refreshQuote();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pedir um favor'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepHeader(current: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _stepBody(),
              ),
            ),
            _PriceFooter(
              quote: _quote,
              loading: _quoting,
              estimateApprox: _hasPurchase,
              onNext: _canProceed() ? _next : null,
              onBack: _step == _ErrandStep.what ? null : _back,
              nextLabel: _step == _ErrandStep.when ? 'Continuar para pagamento' : 'Próximo',
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case _ErrandStep.what:
        return _descCtrl.text.trim().isNotEmpty &&
            (!_hasPurchase || _estimatedCents > 0);
      case _ErrandStep.where:
        return _errandLocation != null && _dropoff != null;
      case _ErrandStep.when:
        return _quote != null && !_quoting;
    }
  }

  void _next() {
    if (_step == _ErrandStep.what) {
      setState(() => _step = _ErrandStep.where);
    } else if (_step == _ErrandStep.where) {
      _refreshQuote();
      setState(() => _step = _ErrandStep.when);
    } else {
      _goToCheckout();
    }
  }

  void _back() {
    if (_step == _ErrandStep.where) {
      setState(() => _step = _ErrandStep.what);
    } else if (_step == _ErrandStep.when) {
      setState(() => _step = _ErrandStep.where);
    }
  }

  Future<void> _goToCheckout() async {
    final quote = _quote;
    if (quote == null) return;
    // D4: cash > €40 com compra adiantada sem paragem-dinheiro = forçar paragem.
    final customerCents =
        ((quote['customer_total'] as num?)?.toDouble() ?? 0) * 100;
    if (_hasPurchase &&
        !(_homeStop && _homeStopReason == 'dinheiro') &&
        customerCents > _maxCashCents) {
      _showFriendlyCashDialog();
      return;
    }
    final cart = context.read<CartStore>();
    cart.configureErrandSession(
      description: _descCtrl.text.trim(),
      location: _errandLocationCtrl.text.trim(),
      locationCoords: _errandLocation!,
      dropoff: _dropoff!,
      home: _homeStop ? _home : null,
      homeStopReason: _homeStop ? _homeStopReason : null,
      speed: _speed,
      hasPurchase: _hasPurchase,
      estimatedCents: _estimatedCents,
      quote: quote,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentMethodScreen()),
    );
  }

  void _showFriendlyCashDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compra acima de €40'),
        content: const Text(
            'Como a compra é mais de €40, eu passo primeiro em tua casa para levantar o dinheiro. Fica mais seguro para os dois 🙂\n\nVais pagar mais €2 pela paragem.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar a escolher'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _homeStop = true;
                _homeStopReason = 'dinheiro';
              });
              Navigator.pop(context);
              _refreshQuote();
            },
            child: const Text('Ativar paragem em casa'),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case _ErrandStep.what:
        return _StepWhat(
          descCtrl: _descCtrl,
          estimateCtrl: _estimateCtrl,
          hasPurchase: _hasPurchase,
          onHasPurchaseChanged: (v) {
            setState(() => _hasPurchase = v);
            _onChange();
          },
          onChanged: _onChange,
        );
      case _ErrandStep.where:
        return _StepWhere(
          errandLocationCtrl: _errandLocationCtrl,
          dropoffCtrl: _dropoffCtrl,
          homeStop: _homeStop || _forcedHomeStopByEstimate,
          forced: _forcedHomeStopByEstimate,
          homeStopReason: _homeStopReason,
          onHomeStopChanged: (v) {
            if (_forcedHomeStopByEstimate) return;
            setState(() => _homeStop = v);
            _onChange();
          },
          onReasonChanged: (r) {
            setState(() => _homeStopReason = r);
            _onChange();
          },
          // Placeholders: integração real do autocomplete vem de
          // PlaceAutocompleteService + map_screen. Aqui o user digita e
          // assumimos lat/lng provisórias (centro Guarda) para o quote.
          onErrandLocationPicked: () {
            setState(() =>
                _errandLocation = const LatLng(40.5374, -7.2667));
            _onChange();
          },
          onDropoffPicked: () {
            setState(() => _dropoff = const LatLng(40.5395, -7.2700));
            _onChange();
          },
          onHomePicked: () {
            setState(() => _home = const LatLng(40.5395, -7.2700));
            _onChange();
          },
        );
      case _ErrandStep.when:
        return _StepWhen(
          speed: _speed,
          quote: _quote,
          hasPurchase: _hasPurchase,
          homeStop: _homeStop || _forcedHomeStopByEstimate,
          estimateCents: _estimatedCents,
          onSpeedChanged: (s) {
            setState(() => _speed = s);
            _refreshQuote();
          },
        );
    }
  }
}

// ── PASSO 1: O QUÊ ────────────────────────────────────────────────────────
class _StepWhat extends StatelessWidget {
  const _StepWhat({
    required this.descCtrl,
    required this.estimateCtrl,
    required this.hasPurchase,
    required this.onHasPurchaseChanged,
    required this.onChanged,
  });

  final TextEditingController descCtrl;
  final TextEditingController estimateCtrl;
  final bool hasPurchase;
  final ValueChanged<bool> onHasPurchaseChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('O que precisas?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: descCtrl,
          maxLines: 4,
          maxLength: 500,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText:
                'Ex.: Vai à Farmácia Holon na Sé e compra Ben-u-ron 1g',
            labelText: 'Descreve o favor',
          ),
        ),
        const SizedBox(height: 16),
        // G5 — disclaimer + receita positiva (G1)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryWash,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Text(
            'Não é permitido pedir itens ilegais ou armas.\n'
            'Para medicamentos com receita, ativa a paragem em tua casa no próximo passo '
            'para o estafeta recolher a receita.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Este favor inclui uma compra?'),
          subtitle: const Text('Ex.: comprar algo na loja'),
          value: hasPurchase,
          onChanged: onHasPurchaseChanged,
        ),
        if (hasPurchase) ...[
          const SizedBox(height: 8),
          TextField(
            controller: estimateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Valor estimado da compra',
              hintText: 'Ex.: 15',
              prefixText: '€ ',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'É só uma estimativa — pagas o valor exato do talão.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ── PASSO 2: ONDE ─────────────────────────────────────────────────────────
class _StepWhere extends StatelessWidget {
  const _StepWhere({
    required this.errandLocationCtrl,
    required this.dropoffCtrl,
    required this.homeStop,
    required this.forced,
    required this.homeStopReason,
    required this.onHomeStopChanged,
    required this.onReasonChanged,
    required this.onErrandLocationPicked,
    required this.onDropoffPicked,
    required this.onHomePicked,
  });

  final TextEditingController errandLocationCtrl;
  final TextEditingController dropoffCtrl;
  final bool homeStop;
  final bool forced;
  final String homeStopReason;
  final ValueChanged<bool> onHomeStopChanged;
  final ValueChanged<String> onReasonChanged;
  final VoidCallback onErrandLocationPicked;
  final VoidCallback onDropoffPicked;
  final VoidCallback onHomePicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Onde é o favor?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: errandLocationCtrl,
          onChanged: (_) => onErrandLocationPicked(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Local do favor',
            hintText: 'Ex.: Farmácia Holon, Guarda',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: dropoffCtrl,
          onChanged: (_) => onDropoffPicked(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Onde entregar',
            hintText: 'Morada de entrega',
            prefixIcon: Icon(Icons.home_outlined),
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(forced
              ? 'Paragem em tua casa (obrigatória)'
              : 'Precisas que eu passe primeiro em tua casa?'),
          subtitle: Text(forced
              ? 'Como a compra é mais de €40, passo em tua casa para levantar o dinheiro. +€2.'
              : '(buscar receita, cartão ou dinheiro) — +€2'),
          value: homeStop,
          onChanged: forced ? null : onHomeStopChanged,
        ),
        if (homeStop) ...[
          const SizedBox(height: 8),
          Text('Motivo:', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: const ['receita', 'cartao', 'dinheiro', 'outro']
                .map((r) => ChoiceChip(
                      label: Text(_reasonLabel(r)),
                      selected: homeStopReason == r,
                      onSelected: (_) => onReasonChanged(r),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onHomePicked,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Confirmar morada da paragem em casa'),
          ),
        ],
      ],
    );
  }

  static String _reasonLabel(String r) {
    switch (r) {
      case 'receita':
        return 'Receita médica';
      case 'cartao':
        return 'Cartão';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return 'Outro';
    }
  }
}

// ── PASSO 3: QUANDO + PAGAR ───────────────────────────────────────────────
class _StepWhen extends StatelessWidget {
  const _StepWhen({
    required this.speed,
    required this.quote,
    required this.hasPurchase,
    required this.homeStop,
    required this.estimateCents,
    required this.onSpeedChanged,
  });

  final String speed;
  final Map<String, dynamic>? quote;
  final bool hasPurchase;
  final bool homeStop;
  final int estimateCents;
  final ValueChanged<String> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Quando precisas?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _SpeedCard(
          title: '🕐  Normal',
          subtitle: 'Até 3 horas',
          price: '€6',
          tagline: 'Escolhe Normal se não tens pressa.',
          selected: speed == 'normal',
          onTap: () => onSpeedChanged('normal'),
        ),
        const SizedBox(height: 10),
        _SpeedCard(
          title: '⚡  Expresso',
          subtitle: '45 a 60 minutos',
          price: '€10',
          tagline: 'Vai logo. Custa um pouco mais.',
          selected: speed == 'express',
          onTap: () => onSpeedChanged('express'),
        ),
        const SizedBox(height: 24),
        if (q != null) _Breakdown(quote: q, hasPurchase: hasPurchase),
      ],
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.tagline,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String price;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryWash : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(tagline,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Text(price,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.quote, required this.hasPurchase});
  final Map<String, dynamic> quote;
  final bool hasPurchase;

  @override
  Widget build(BuildContext context) {
    final base = (quote['base_fee'] as num?)?.toDouble() ?? 0;
    final home = (quote['home_stop_fee'] as num?)?.toDouble() ?? 0;
    final km = (quote['km_extra_fee'] as num?)?.toDouble() ?? 0;
    final purchase = (quote['purchase_estimate'] as num?)?.toDouble() ?? 0;
    final total = (quote['customer_total'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _Row(label: 'Favor', value: base),
          if (home > 0) _Row(label: 'Paragem em casa', value: home),
          if (km > 0) _Row(label: 'Km extra', value: km),
          if (hasPurchase) _Row(label: 'Compra (estimada)', value: purchase),
          const Divider(),
          _Row(
            label: hasPurchase ? 'Total ~' : 'Total',
            value: total,
            strong: true,
          ),
          if (hasPurchase) ...[
            const SizedBox(height: 4),
            Text(
              'O valor da compra ajusta-se ao talão real.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false});
  final String label;
  final double value;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: strong ? 16 : 14,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

// ── Cabeçalho de progresso ────────────────────────────────────────────────
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});
  final _ErrandStep current;
  @override
  Widget build(BuildContext context) {
    final idx = _ErrandStep.values.indexOf(current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= idx;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Rodapé sticky com preço live ──────────────────────────────────────────
class _PriceFooter extends StatelessWidget {
  const _PriceFooter({
    required this.quote,
    required this.loading,
    required this.estimateApprox,
    required this.onNext,
    required this.onBack,
    required this.nextLabel,
  });

  final Map<String, dynamic>? quote;
  final bool loading;
  final bool estimateApprox;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final total = (quote?['customer_total'] as num?)?.toDouble();
    final priceLabel = total == null
        ? 'desde €6'
        : '${estimateApprox ? "~" : ""}€${total.toStringAsFixed(2)}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.shadowNav,
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total', style: TextStyle(color: AppColors.textSecondary)),
              Row(children: [
                Text(priceLabel,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                if (loading) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ]),
            ],
          ),
          const Spacer(),
          if (onBack != null) ...[
            TextButton(onPressed: onBack, child: const Text('Voltar')),
            const SizedBox(width: 8),
          ],
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            child: Text(nextLabel),
          ),
        ],
      ),
    );
  }
}
