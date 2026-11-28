import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException, FailureCode;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../l10n/tr.dart';
import '../../../models/cleaning_models.dart';
import '../../../models/cleaning_plan_models.dart';
import '../../../services/payment_service.dart';
import '../../../services/place_autocomplete_service.dart';
import '../../../stores/cart_store.dart';
import '../../../stores/cleaning_plan_store.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../complete_profile_screen.dart' show garantirContactoDoCliente;
import 'cleaning_plan_screen.dart';

/// PLANO DE LIMPEZA — criar (missão limpeza-planos-empresas-2026-11-28, Blocos C e D).
///
/// [segment] 'casa': frequência (De 15 em 15 dias / Semanal [Popular] / Mais de uma vez por
/// semana), horas por visita, barra "Preço por hora" a descer, preço por visita e "≈ por mês".
/// [segment] 'empresa' (Bora Empresas): tipo de espaço, m², tarefas, mínimo 1 h, produtos
/// incluídos, hora À ESCOLHA da empresa, nome, NIF, email de faturação e instruções de acesso.
///
/// Só com cartão. O preço vem SEMPRE do servidor (cleaning_plan_quote). Nada se cobra aqui:
/// "Começar plano" cria o plano e guarda o cartão (SetupIntent); cada limpeza cobra-se 24 h
/// antes, e só com a profissional confirmada.
class CleaningPlanWizardScreen extends StatefulWidget {
  const CleaningPlanWizardScreen({super.key, this.segment = 'casa', this.storeOverride, this.garantirContacto});

  final String segment;

  @visibleForTesting
  final CleaningPlanStore? storeOverride;

  /// Porta do telemóvel antes de criar o plano (28/11/2026). Só os testes a trocam;
  /// em produção é sempre [garantirContactoDoCliente].
  @visibleForTesting
  final Future<bool> Function(BuildContext context)? garantirContacto;

  @override
  State<CleaningPlanWizardScreen> createState() => _CleaningPlanWizardScreenState();
}

class _CleaningPlanWizardScreenState extends State<CleaningPlanWizardScreen> {
  late final CleaningPlanStore _store = widget.storeOverride ?? CleaningPlanStore();
  bool get _empresa => widget.segment == 'empresa';

  // serviço
  late String _frequency = _empresa ? 'weekly_1' : 'weekly';
  String _homeSize = 't2';
  int _hours = 4;
  int _teamSize = 1;
  String _productsBy = 'client';
  String _billingMode = 'per_visit';
  Map<String, int> _duracoes = const {'t0_t1': 180, 't2': 240, 't3': 300, 't4plus': 360};

  // quando
  final Set<int> _days = {};
  late TimeOfDay _time = _empresa ? const TimeOfDay(hour: 20, minute: 0) : const TimeOfDay(hour: 10, minute: 0);
  late DateTime _startDate = DateTime.now().add(const Duration(days: 2));

  // onde
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  ll.LatLng? _coords;
  late final PlaceAutocompleteService _places = createPlaceAutocompleteService(googleApiKey);

  // Bora Empresas
  final _companyCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _accessCtrl = TextEditingController();
  String _spaceType = 'loja';
  final Set<String> _tasks = {'varrer_aspirar', 'po', 'casa_de_banho', 'lixo'};

  CleaningPlanQuote? _quote;
  bool _quoteLoading = false;
  int _quoteSeq = 0;
  Timer? _debounce;
  bool _busy = false;

  int get _minHours => _empresa ? 1 : 2;

  @override
  void initState() {
    super.initState();
    _days.add(_startDate.weekday);
    if (_empresa) {
      _hours = 1;
      _productsBy = 'cleaner';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cart = context.read<CartStore>();
      if (cart.dropoffStreet.isNotEmpty) {
        _streetCtrl.text = cart.dropoffStreet;
        _cityCtrl.text = cart.dropoffCity;
        _postalCtrl.text = cart.dropoffPostalCode;
        _coords = cart.deliveryLocation;
      }
      if (!_empresa) {
        final d = await _store.duracoesPorTipologia();
        if (!mounted) return;
        setState(() {
          _duracoes = d;
          _hours = CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize);
        });
      }
      _refreshQuote();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_streetCtrl, _cityCtrl, _postalCtrl, _notesCtrl, _companyCtrl, _nifCtrl, _emailCtrl, _areaCtrl, _accessCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  (int, int) get _regraDias => CleaningPlanLabels.diasPorSemana(_frequency);

  void _ajustarDias() {
    final (min, max) = _regraDias;
    final ordenados = _days.toList()..sort();
    while (ordenados.length > max) {
      ordenados.removeLast();
    }
    var d = 1;
    while (ordenados.length < min && d <= 7) {
      if (!ordenados.contains(d)) ordenados.add(d);
      d++;
    }
    _days
      ..clear()
      ..addAll(ordenados);
  }

  void _mudou() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refreshQuote);
  }

  Future<void> _refreshQuote() async {
    final seq = ++_quoteSeq;
    setState(() => _quoteLoading = true);
    final q = await _store.quote(
      segment: widget.segment,
      frequency: _frequency,
      hours: _hours,
      daysPerWeek: _days.isEmpty ? 1 : _days.length,
      teamSize: _teamSize,
      productsBy: _empresa ? 'cleaner' : _productsBy,
      lat: _coords?.latitude,
      lng: _coords?.longitude,
    );
    if (!mounted || seq != _quoteSeq) return;
    setState(() {
      _quote = q;
      _quoteLoading = false;
    });
  }

  String get _moradaEscrita => [_streetCtrl.text, _postalCtrl.text, _cityCtrl.text]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(', ');

  Future<void> _resolverMorada() async {
    if (_coords != null || _moradaEscrita.isEmpty) return;
    try {
      final achada = await _places.procurarMoradaEscrita(_moradaEscrita);
      if (achada != null && mounted) setState(() => _coords = achada.coords);
    } catch (_) {/* segue sem coordenadas: o servidor recusa e o ecrã diz */}
  }

  String get _horaTexto => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _comecar() async {
    if (_busy) return;
    if (kIsWeb) {
      _snack('Os planos com cartão fazem-se na app do telemóvel.'.tr);
      return;
    }
    final (min, max) = _regraDias;
    if (_days.length < min || _days.length > max) {
      _snack(min == max ? 'Escolhe {0} dia(s) da semana.'.trArgs([min]) : 'Escolhe entre {0} e {1} dias da semana.'.trArgs([min, max]));
      return;
    }
    if (_empresa) {
      if (_companyCtrl.text.trim().isEmpty) return _snack('Falta o nome da empresa.'.tr);
      if (_nifCtrl.text.replaceAll(RegExp(r'\D'), '').length != 9) return _snack('O NIF tem de ter 9 algarismos.'.tr);
      if (!_emailCtrl.text.contains('@')) return _snack('Falta o email de faturação.'.tr);
    }
    // 28/11/2026 (Danilo): sem telemóvel não há pedido. As visitas do plano são reservas de
    // limpeza, e o servidor recusa-as sem o telemóvel do cliente (SEM_TELEFONE) quando o cartão
    // fica guardado e o plano gera as limpezas. Por isso pede-se ANTES de criar o plano.
    final contactoOk = await (widget.garantirContacto?.call(context) ??
        garantirContactoDoCliente(context, categoria: 'limpeza'));
    if (!contactoOk || !mounted) return;
    setState(() => _busy = true);
    try {
      await _resolverMorada();
      final c = _coords;
      if (c == null) {
        _snack('Escolhe a morada numa das sugestões, para sabermos onde é.'.tr);
        return;
      }
      final planId = await _store.createPlan(
        segment: widget.segment,
        frequency: _frequency,
        hours: _hours,
        days: (_days.toList()..sort()),
        time: _horaTexto,
        startDate: _startDate,
        teamSize: _teamSize,
        productsBy: _empresa ? 'cleaner' : _productsBy,
        homeSize: _empresa ? null : _homeSize,
        billingMode: _frequency == 'once' ? 'per_visit' : _billingMode,
        street: _streetCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        postal: _postalCtrl.text.trim(),
        lat: c.latitude,
        lng: c.longitude,
        notes: _notesCtrl.text.trim(),
        companyName: _empresa ? _companyCtrl.text.trim() : null,
        billingNif: _empresa ? _nifCtrl.text.trim() : null,
        billingEmail: _empresa ? _emailCtrl.text.trim() : null,
        spaceType: _empresa ? _spaceType : null,
        areaM2: _empresa ? int.tryParse(_areaCtrl.text.trim()) : null,
        tasks: _empresa ? _tasks.toList() : const [],
        accessInstructions: _empresa ? _accessCtrl.text.trim() : null,
      );
      if (!mounted) return;
      if (planId == null) {
        _snack(_store.erro ?? 'Não foi possível criar o plano.'.tr);
        return;
      }
      final ok = await guardarCartaoDoPlano(context, _store, planId);
      if (!mounted) return;
      if (!ok) {
        _snack('O plano ficou guardado sem cartão e sem cobrança. Junta o cartão em "O meu plano".'.tr);
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CleaningPlanScreen()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      appBar: BoraScreenAppBar(title: _empresa ? 'Limpeza para empresas'.tr : 'Plano de limpeza'.tr),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          if (_empresa) ..._blocoEmpresa() else ..._blocoCasa(),
          const SizedBox(height: Spacing.lg),
          _Titulo('Com que frequência?'.tr),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final e in (_empresa ? CleaningPlanLabels.empresaFrequencias : CleaningPlanLabels.casaFrequencias).entries)
                ChoiceChip(
                  key: Key('plano-freq-${e.key}'),
                  label: Text(e.key == 'weekly' ? '${e.value.tr} · ${'Popular'.tr}' : e.value.tr),
                  selected: _frequency == e.key,
                  selectedColor: AppColors.primaryLight,
                  onSelected: (_) => setState(() {
                    _frequency = e.key;
                    _ajustarDias();
                    _mudou();
                  }),
                ),
            ],
          ),
          if (q != null && q.ladder.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _BarraPrecoHora(ladder: q.ladder, escolhida: _frequency),
          ],
          const SizedBox(height: Spacing.lg),
          _Titulo(_empresa ? 'Horas por visita (mínimo 1 h)'.tr : 'Horas por limpeza'.tr),
          _Passo(
            valor: '$_hours h',
            menos: _hours > _minHours ? () => setState(() { _hours--; _mudou(); }) : null,
            mais: _hours < 10 ? () => setState(() { _hours++; _mudou(); }) : null,
          ),
          if (!_empresa && CleaningPlanLabels.sugereEquipa(_homeSize)) ...[
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              key: const Key('plano-equipa'),
              contentPadding: EdgeInsets.zero,
              value: _teamSize >= 2,
              activeThumbColor: AppColors.primary,
              title: Text('Vêm 2 profissionais e acabam em metade do tempo'.tr),
              subtitle: Text('O preço por hora é o mesmo; cada uma recebe a sua parte.'.tr),
              onChanged: (v) => setState(() {
                _teamSize = v ? 2 : 1;
                _hours = CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize);
                _mudou();
              }),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          _Titulo(_regraDias.$1 == _regraDias.$2 && _regraDias.$1 == 1 ? 'Que dia da semana?'.tr : 'Que dias da semana?'.tr),
          Wrap(
            spacing: Spacing.xs,
            children: [
              for (final d in CleaningPlanLabels.diasCurtos.entries)
                FilterChip(
                  key: Key('plano-dia-${d.key}'),
                  label: Text(d.value.tr),
                  selected: _days.contains(d.key),
                  selectedColor: AppColors.primaryLight,
                  onSelected: (sel) => setState(() {
                    final (_, max) = _regraDias;
                    if (sel) {
                      if (max == 1) _days.clear();
                      if (_days.length < max) _days.add(d.key);
                    } else {
                      _days.remove(d.key);
                    }
                    _mudou();
                  }),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('plano-hora'),
                  icon: const Icon(Icons.schedule),
                  label: Text('Hora: {0}'.trArgs([_horaTexto])),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('plano-inicio'),
                  icon: const Icon(Icons.event),
                  label: Text('Começa: {0}'.trArgs(['${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}'])),
                  onPressed: () async {
                    final agora = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: agora.add(const Duration(days: 2)),
                      lastDate: agora.add(const Duration(days: 90)),
                    );
                    if (d != null) setState(() => _startDate = d);
                  },
                ),
              ),
            ],
          ),
          if (_empresa)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text('A hora que a empresa quiser: antes de abrir, durante ou depois de fechar.'.tr,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          const SizedBox(height: Spacing.lg),
          _Titulo(_empresa ? 'Onde é a empresa?'.tr : 'Onde é a casa?'.tr),
          AddressAutocompleteField(
            controller: _streetCtrl,
            labelText: 'Rua e número'.tr,
            prefixIcon: const Icon(Icons.place),
            confirmarAoSair: false,
            onSelected: (morada, coords) {
              setState(() => _coords = coords);
              _mudou();
            },
            onChanged: (_) => _coords = null,
          ),
          const SizedBox(height: Spacing.sm),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: _cityCtrl, decoration: InputDecoration(labelText: 'Localidade'.tr), onChanged: (_) => _coords = null)),
            const SizedBox(width: Spacing.sm),
            Expanded(flex: 2, child: TextField(controller: _postalCtrl, decoration: InputDecoration(labelText: 'Código postal'.tr), onChanged: (_) => _coords = null)),
          ]),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'Notas para a profissional (opcional)'.tr),
          ),
          if (_frequency != 'once') ...[
            const SizedBox(height: Spacing.lg),
            _Titulo('Como queres pagar?'.tr),
            RadioGroup<String>(
              groupValue: _billingMode,
              onChanged: (v) => setState(() => _billingMode = v ?? 'per_visit'),
              child: Column(children: [
                RadioListTile<String>(
                  key: const Key('plano-cobranca-visita'),
                  contentPadding: EdgeInsets.zero,
                  value: 'per_visit',
                  title: Text('A cada limpeza'.tr),
                  subtitle: Text('Cobramos 24 h antes de cada limpeza, e só com a profissional confirmada.'.tr),
                ),
                RadioListTile<String>(
                  key: const Key('plano-cobranca-mes'),
                  contentPadding: EdgeInsets.zero,
                  value: 'monthly',
                  title: Text('O mês de uma vez'.tr),
                  subtitle: Text('No início de cada mês cobramos as limpezas desse mês já confirmadas. Até lá, cobramos cada limpeza 24 h antes.'.tr),
                ),
              ]),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          _ResumoPreco(quote: q, loading: _quoteLoading, empresa: _empresa, erro: q == null ? _store.erro : null),
          const SizedBox(height: Spacing.md),
          const _LinhaCartao(),
          const SizedBox(height: Spacing.md),
          Text(
            'Cancelas quando quiseres, sem taxa, em Limpeza → O meu plano. Saltar uma limpeza é grátis até 24 h antes.'.tr,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
          child: BoraPrimaryButton(
            key: const Key('plano-comecar'),
            label: 'Começar plano'.tr,
            loading: _busy,
            onPressed: (q == null || _quoteLoading) ? null : _comecar,
          ),
        ),
      ),
    );
  }

  List<Widget> _blocoCasa() => [
        _Titulo('Que tamanho tem a casa?'.tr),
        Wrap(
          spacing: Spacing.sm,
          children: [
            for (final s in CleaningLabels.sizes.entries)
              ChoiceChip(
                key: Key('plano-tamanho-${s.key}'),
                label: Text(s.value),
                selected: _homeSize == s.key,
                selectedColor: AppColors.primaryLight,
                onSelected: (_) => setState(() {
                  _homeSize = s.key;
                  if (!CleaningPlanLabels.sugereEquipa(_homeSize)) _teamSize = 1;
                  _hours = CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize);
                  _mudou();
                }),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text('Sugerimos {0} h para esta casa. Podes mudar.'.trArgs([CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize)]),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: Spacing.lg),
        _Titulo('Produtos de limpeza'.tr),
        Wrap(spacing: Spacing.sm, children: [
          ChoiceChip(
            label: Text('Tenho em casa'.tr),
            selected: _productsBy == 'client',
            selectedColor: AppColors.primaryLight,
            onSelected: (_) => setState(() { _productsBy = 'client'; _mudou(); }),
          ),
          ChoiceChip(
            label: Text('A profissional leva (+3 €)'.tr),
            selected: _productsBy == 'cleaner',
            selectedColor: AppColors.primaryLight,
            onSelected: (_) => setState(() { _productsBy = 'cleaner'; _mudou(); }),
          ),
        ]),
      ];

  List<Widget> _blocoEmpresa() => [
        _Titulo('Que espaço é?'.tr),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final e in CleaningPlanLabels.espacos.entries)
              ChoiceChip(
                key: Key('plano-espaco-${e.key}'),
                label: Text(e.value.tr),
                selected: _spaceType == e.key,
                selectedColor: AppColors.primaryLight,
                onSelected: (_) => setState(() => _spaceType = e.key),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _areaCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Área aproximada (m²)'.tr),
        ),
        const SizedBox(height: Spacing.lg),
        _Titulo('O que precisa?'.tr),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final t in CleaningPlanLabels.tarefas.entries)
              FilterChip(
                label: Text(t.value.tr),
                selected: _tasks.contains(t.key),
                selectedColor: AppColors.primaryLight,
                onSelected: (sel) => setState(() => sel ? _tasks.add(t.key) : _tasks.remove(t.key)),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text('Os produtos estão incluídos: a profissional leva-os.'.tr,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: Spacing.lg),
        _Titulo('Dados da empresa'.tr),
        TextField(controller: _companyCtrl, decoration: InputDecoration(labelText: 'Nome da empresa'.tr)),
        const SizedBox(height: Spacing.sm),
        TextField(controller: _nifCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'NIF'.tr)),
        const SizedBox(height: Spacing.sm),
        TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email de faturação'.tr)),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _accessCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Como entrar (chave, código) — opcional'.tr,
            helperText: 'Só a profissional vê, e só no dia da limpeza.'.tr,
          ),
        ),
      ];
}

/// Guarda o cartão de um plano: SetupIntent na Edge cleaning-plan → folha do cartão → grava.
/// Serve para o cartão novo e para "Trocar cartão". Devolve true quando ficou guardado.
Future<bool> guardarCartaoDoPlano(BuildContext context, CleaningPlanStore store, String planId) async {
  final setup = await store.startCardSetup(planId);
  if (setup == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.erro ?? 'Não foi possível abrir o cartão.'.tr)));
    }
    return false;
  }
  try {
    await PaymentService().saveCardWithSetupIntent(
      setupIntentClientSecret: setup['setupIntentClientSecret'] as String,
      customerId: setup['customerId'] as String?,
      ephemeralKey: setup['ephemeralKey'] as String?,
      publishableKey: setup['publishable_key'] as String?,
      referenciaId: planId,
    );
  } on StripeException catch (e) {
    if (e.error.code != FailureCode.Canceled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.error.localizedMessage ?? 'O cartão não foi guardado.'.tr)));
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return false;
  }
  return store.confirmCardSetup(planId, setup['setupIntentId'] as String);
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      );
}

class _Passo extends StatelessWidget {
  const _Passo({required this.valor, required this.menos, required this.mais});
  final String valor;
  final VoidCallback? menos;
  final VoidCallback? mais;
  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.outlined(key: const Key('plano-horas-menos'), onPressed: menos, icon: const Icon(Icons.remove)),
        SizedBox(
          width: 72,
          child: Text(valor, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        IconButton.outlined(key: const Key('plano-horas-mais'), onPressed: mais, icon: const Icon(Icons.add)),
      ]);
}

/// Barra "Preço por hora": desce com a frequência, a escolhida em destaque.
class _BarraPrecoHora extends StatelessWidget {
  const _BarraPrecoHora({required this.ladder, required this.escolhida});
  final List<CleaningPlanLadderStep> ladder;
  final String escolhida;

  @override
  Widget build(BuildContext context) {
    final maior = ladder.map((s) => s.clientCentsPerHour).fold<int>(1, (a, b) => b > a ? b : a);
    return Container(
      key: const Key('plano-barra-preco-hora'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preço por hora'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Spacing.sm),
          for (final s in ladder)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 140, child: Text(s.label.tr, style: TextStyle(fontWeight: s.frequency == escolhida ? FontWeight.w700 : FontWeight.w400, fontSize: 13))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: s.clientCentsPerHour / maior,
                      minHeight: 10,
                      backgroundColor: Colors.white,
                      color: s.frequency == escolhida ? AppColors.primary : AppColors.primaryLight,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(CleaningPlanLabels.euroHora(s.clientCentsPerHour),
                    style: TextStyle(fontWeight: s.frequency == escolhida ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _ResumoPreco extends StatelessWidget {
  const _ResumoPreco({required this.quote, required this.loading, required this.empresa, this.erro});
  final CleaningPlanQuote? quote;
  final bool loading;
  final bool empresa;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    if (q == null) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Text(erro ?? 'Sem preço — verifica a ligação.'.tr, style: const TextStyle(color: AppColors.error)),
      );
    }
    final linha = TextStyle(color: AppColors.textSecondary.withValues(alpha: loading ? 0.5 : 1));
    return Container(
      key: const Key('plano-resumo-preco'),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('{0} por limpeza'.trArgs([CleaningLabels.euro(q.totalPerVisitCents)]),
              key: const Key('plano-preco-visita'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
          if (q.frequency != 'once')
            Text('≈ {0} por mês'.trArgs([CleaningLabels.euro(q.approxMonthCents)]),
                key: const Key('plano-preco-mes'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: Spacing.sm),
          Text('{0} × {1} h{2}'.trArgs([
            CleaningPlanLabels.euroHora(q.clientCentsPerHour),
            q.hours.round(),
            q.teamSize > 1 ? ' × ${q.teamSize} ${'profissionais'.tr}' : '',
          ]), style: linha),
          if (q.productsCents > 0) Text('Produtos levados pela profissional: {0}'.trArgs([CleaningLabels.euro(q.productsCents)]), style: linha),
          if (empresa) Text('Produtos incluídos.'.tr, style: linha),
          if (q.travelFeeCents > 0)
            Text('Taxa de deslocação: {0}'.trArgs([CleaningLabels.euro(q.travelFeeCents)]), style: linha),
          if (q.frequency != 'once')
            Text('Conta feita com {0} limpezas por mês, em média.'.trArgs([q.visitsPerMonth.toStringAsFixed(1).replaceAll('.', ',')]),
                style: linha.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Regra de 22/09: o cartão vê-se antes de confirmar. No plano é só cartão.
class _LinhaCartao extends StatelessWidget {
  const _LinhaCartao();
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('plano-linha-cartao'),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.credit_card, color: AppColors.primary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Pagamento: cartão (os planos são só com cartão). A seguir escolhes ou juntas o cartão — não cobramos nada agora.'.tr,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ]),
      );
}
