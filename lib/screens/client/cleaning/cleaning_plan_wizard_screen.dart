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
/// 28/11/2026 (redesenho didático, pedido do Danilo): uma pergunta por ecrã, com "Passo X de N",
/// botão grande Continuar e Voltar. A opção escolhida fica verde cheio com um visto.
///   casa (5):    a casa e as horas → frequência → dia, hora e início → morada → resumo e cartão
///   empresa (6): espaço e tarefas → frequência e horas → dias e hora → morada → fatura → resumo
///
/// Só com cartão. O preço vem SEMPRE do servidor (cleaning_plan_quote). Nada se cobra aqui:
/// "Começar plano" cria o plano e guarda o cartão (SetupIntent); cada limpeza cobra-se na véspera,
/// e só com a profissional confirmada. Só a apresentação mudou: as chamadas e as regras são as mesmas.
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

/// Os passos de cada assistente, pela ordem.
enum _Passo { casa, espaco, frequencia, quando, morada, fatura, resumo }

class _CleaningPlanWizardScreenState extends State<CleaningPlanWizardScreen> {
  late final CleaningPlanStore _store = widget.storeOverride ?? CleaningPlanStore();
  bool get _empresa => widget.segment == 'empresa';

  late final List<_Passo> _passos = _empresa
      ? const [_Passo.espaco, _Passo.frequencia, _Passo.quando, _Passo.morada, _Passo.fatura, _Passo.resumo]
      : const [_Passo.casa, _Passo.frequencia, _Passo.quando, _Passo.morada, _Passo.resumo];
  int _i = 0;
  _Passo get _passo => _passos[_i];
  bool get _ultimo => _i == _passos.length - 1;

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
  String get _dataTexto => '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}';

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ── navegação ─────────────────────────────────────────────────────────────

  /// O que falta neste passo (null = pode continuar).
  String? _faltaNestePasso() {
    switch (_passo) {
      case _Passo.quando:
        final (min, max) = _regraDias;
        if (_days.length < min || _days.length > max) {
          return min == max ? 'Escolhe {0} dia(s) da semana.'.trArgs([min]) : 'Escolhe entre {0} e {1} dias da semana.'.trArgs([min, max]);
        }
        return null;
      case _Passo.morada:
        return _streetCtrl.text.trim().isEmpty ? 'Falta a rua e o número.'.tr : null;
      case _Passo.fatura:
        if (_companyCtrl.text.trim().isEmpty) return 'Falta o nome da empresa.'.tr;
        if (_nifCtrl.text.replaceAll(RegExp(r'\D'), '').length != 9) return 'O NIF tem de ter 9 algarismos.'.tr;
        if (!_emailCtrl.text.contains('@')) return 'Falta o email de faturação.'.tr;
        return null;
      default:
        return null;
    }
  }

  void _continuar() {
    final falta = _faltaNestePasso();
    if (falta != null) {
      _snack(falta);
      return;
    }
    if (_ultimo) {
      _comecar();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _i++);
  }

  void _voltar() {
    if (_i == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _i--);
  }

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

  // ── ecrã ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _voltar();
      },
      child: Scaffold(
        appBar: BoraScreenAppBar(title: _empresa ? 'Limpeza para empresas'.tr : 'Plano de limpeza'.tr),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Progresso(passo: _i + 1, total: _passos.length),
            Expanded(
              child: ListView(
                key: ValueKey('plano-passo-${_passo.name}'),
                padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxl),
                children: _conteudo(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
            child: Row(children: [
              if (_i > 0) ...[
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const Key('plano-voltar'),
                    onPressed: _busy ? null : _voltar,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.dividerStrong, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md + 2)),
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    ),
                    child: Text('Voltar'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: BoraPrimaryButton(
                  key: Key(_ultimo ? 'plano-comecar' : 'plano-continuar'),
                  label: _ultimo ? 'Começar plano'.tr : 'Continuar'.tr,
                  loading: _busy,
                  onPressed: _ultimo && (_quote == null || _quoteLoading) ? null : _continuar,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _conteudo() => switch (_passo) {
        _Passo.casa => _passoCasa(),
        _Passo.espaco => _passoEspaco(),
        _Passo.frequencia => _passoFrequencia(),
        _Passo.quando => _passoQuando(),
        _Passo.morada => _passoMorada(),
        _Passo.fatura => _passoFatura(),
        _Passo.resumo => _passoResumo(),
      };

  Widget _passoHoras({required String titulo, String? sugestao}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pergunta(titulo),
          if (sugestao != null) _Ajuda(sugestao),
          _Passador(
            valor: '$_hours h',
            menos: _hours > _minHours ? () => setState(() { _hours--; _mudou(); }) : null,
            mais: _hours < 10 ? () => setState(() { _hours++; _mudou(); }) : null,
          ),
        ],
      );

  List<Widget> _passoCasa() => [
        _Titulo('Como é a tua casa?'.tr),
        _Pergunta('Tamanho'.tr),
        Row(children: [
          for (final (i, s) in CleaningLabels.sizes.entries.indexed) ...[
            if (i > 0) const SizedBox(width: Spacing.sm),
            Expanded(
              child: _Opcao(
                key: Key('plano-tamanho-${s.key}'),
                titulo: s.value,
                centrado: true,
                escolhida: _homeSize == s.key,
                onTap: () => setState(() {
                  _homeSize = s.key;
                  if (!CleaningPlanLabels.sugereEquipa(_homeSize)) _teamSize = 1;
                  _hours = CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize);
                  _mudou();
                }),
              ),
            ),
          ],
        ]),
        const SizedBox(height: Spacing.xxl),
        _passoHoras(
          titulo: 'Horas por limpeza'.tr,
          sugestao: 'Sugerimos {0} h para esta casa. Podes mudar.'.trArgs([CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize)]),
        ),
        if (CleaningPlanLabels.sugereEquipa(_homeSize)) ...[
          const SizedBox(height: Spacing.md),
          _Opcao(
            key: const Key('plano-equipa'),
            titulo: 'Vêm 2 profissionais'.tr,
            subtitulo: 'Acabam em metade do tempo. O preço por hora é o mesmo.'.tr,
            escolhida: _teamSize >= 2,
            marcavel: true,
            onTap: () => setState(() {
              _teamSize = _teamSize >= 2 ? 1 : 2;
              _hours = CleaningPlanLabels.horasSugeridas(_duracoes, _homeSize, _teamSize);
              _mudou();
            }),
          ),
        ],
        const SizedBox(height: Spacing.xxl),
        _Pergunta('Produtos de limpeza'.tr),
        _Opcao(
          key: const Key('plano-produtos-cliente'),
          titulo: 'Tenho em casa'.tr,
          escolhida: _productsBy == 'client',
          onTap: () => setState(() { _productsBy = 'client'; _mudou(); }),
        ),
        const SizedBox(height: Spacing.sm),
        _Opcao(
          key: const Key('plano-produtos-profissional'),
          titulo: 'A profissional leva (+3 €)'.tr,
          escolhida: _productsBy == 'cleaner',
          onTap: () => setState(() { _productsBy = 'cleaner'; _mudou(); }),
        ),
      ];

  List<Widget> _passoEspaco() => [
        _Titulo('Que espaço é?'.tr),
        _Grelha(children: [
          for (final e in CleaningPlanLabels.espacos.entries)
            _Opcao(
              key: Key('plano-espaco-${e.key}'),
              titulo: e.value.tr,
              grelha: true,
              escolhida: _spaceType == e.key,
              onTap: () => setState(() => _spaceType = e.key),
            ),
        ]),
        const SizedBox(height: Spacing.lg),
        TextField(
          controller: _areaCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(labelText: 'Área aproximada (m²)'.tr),
        ),
        const SizedBox(height: Spacing.xxl),
        _Pergunta('O que precisa?'.tr),
        _Ajuda('Toca em tudo o que queres. Os produtos estão incluídos.'.tr),
        _Grelha(children: [
          for (final t in CleaningPlanLabels.tarefas.entries)
            _Opcao(
              key: Key('plano-tarefa-${t.key}'),
              titulo: t.value.tr,
              grelha: true,
              escolhida: _tasks.contains(t.key),
              marcavel: true,
              onTap: () => setState(() => _tasks.contains(t.key) ? _tasks.remove(t.key) : _tasks.add(t.key)),
            ),
        ]),
      ];

  List<Widget> _passoFrequencia() {
    final q = _quote;
    final opcoes = _empresa ? CleaningPlanLabels.empresaFrequencias : CleaningPlanLabels.casaFrequencias;
    final porHora = {for (final s in q?.ladder ?? const <CleaningPlanLadderStep>[]) s.frequency: s.clientCentsPerHour};
    final umaVez = porHora['once'];
    return [
      _Titulo('Com que frequência?'.tr),
      _Ajuda('Quanto mais vezes, mais barato fica cada hora.'.tr),
      for (final e in opcoes.entries) ...[
        _Opcao(
          key: Key('plano-freq-${e.key}'),
          titulo: e.value.tr,
          subtitulo: _poupanca(umaVez, porHora[e.key]),
          valor: porHora[e.key] == null ? null : CleaningPlanLabels.euroHora(porHora[e.key]!),
          selo: e.key == 'weekly' ? 'Popular'.tr : null,
          escolhida: _frequency == e.key,
          onTap: () => setState(() {
            _frequency = e.key;
            _ajustarDias();
            _mudou();
          }),
        ),
        const SizedBox(height: Spacing.sm),
      ],
      if (q == null && _quoteLoading)
        const Padding(padding: EdgeInsets.all(Spacing.lg), child: Center(child: CircularProgressIndicator())),
      if (_empresa) ...[
        const SizedBox(height: Spacing.lg),
        _passoHoras(titulo: 'Horas por visita'.tr, sugestao: 'No mínimo 1 h.'.tr),
      ],
    ];
  }

  /// "Poupas 6,00 € por limpeza" face a "Uma vez" (só o preço por hora: deslocação e produtos são iguais).
  String? _poupanca(int? umaVez, int? esta) {
    if (umaVez == null || esta == null || esta >= umaVez) return null;
    final cents = (umaVez - esta) * _hours * _teamSize;
    return 'Poupas {0} por limpeza'.trArgs([CleaningLabels.euro(cents)]);
  }

  List<Widget> _passoQuando() {
    final (min, max) = _regraDias;
    return [
      _Titulo(min == 1 && max == 1 ? 'Que dia da semana?'.tr : 'Que dias da semana?'.tr),
      if (max > 1) _Ajuda(min == max ? 'Escolhe {0} dias.'.trArgs([min]) : 'Escolhe {0} ou mais dias.'.trArgs([min])),
      Row(children: [
        for (final (i, d) in CleaningPlanLabels.diasCurtos.entries.indexed) ...[
          if (i > 0) const SizedBox(width: Spacing.xs),
          Expanded(
            child: _Opcao(
              key: Key('plano-dia-${d.key}'),
              titulo: d.value.tr,
              centrado: true,
              compacto: true,
              escolhida: _days.contains(d.key),
              onTap: () => setState(() {
                if (_days.contains(d.key)) {
                  _days.remove(d.key);
                } else {
                  if (max == 1) _days.clear();
                  if (_days.length < max) _days.add(d.key);
                }
                _mudou();
              }),
            ),
          ),
        ],
      ]),
      const SizedBox(height: Spacing.xxl),
      _Pergunta('A que horas?'.tr),
      if (_empresa) _Ajuda('A que quiseres: antes de abrir, durante ou depois de fechar.'.tr),
      _BotaoGrande(
        key: const Key('plano-hora'),
        icone: Icons.schedule,
        texto: _horaTexto,
        onTap: () async {
          final t = await showTimePicker(context: context, initialTime: _time);
          if (t != null) setState(() => _time = t);
        },
      ),
      const SizedBox(height: Spacing.xxl),
      _Pergunta('Quando começa?'.tr),
      _BotaoGrande(
        key: const Key('plano-inicio'),
        icone: Icons.event,
        texto: _dataTexto,
        onTap: () async {
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
    ];
  }

  List<Widget> _passoMorada() => [
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
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _cityCtrl,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(labelText: 'Localidade'.tr),
          onChanged: (_) => _coords = null,
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _postalCtrl,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(labelText: 'Código postal'.tr),
          onChanged: (_) => _coords = null,
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(labelText: 'Notas para a profissional (opcional)'.tr),
        ),
      ];

  List<Widget> _passoFatura() => [
        _Titulo('Dados para a fatura'.tr),
        TextField(controller: _companyCtrl, style: const TextStyle(fontSize: 16), decoration: InputDecoration(labelText: 'Nome da empresa'.tr)),
        const SizedBox(height: Spacing.md),
        TextField(controller: _nifCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 16), decoration: InputDecoration(labelText: 'NIF'.tr)),
        const SizedBox(height: Spacing.md),
        TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(fontSize: 16), decoration: InputDecoration(labelText: 'Email de faturação'.tr)),
        const SizedBox(height: Spacing.xxl),
        _Pergunta('Como se entra?'.tr),
        _Ajuda('Chave, código da porta… Só a profissional vê, e só no dia.'.tr),
        TextField(
          controller: _accessCtrl,
          maxLines: 2,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(labelText: 'Como entrar (opcional)'.tr),
        ),
      ];

  List<Widget> _passoResumo() {
    final q = _quote;
    final dias = CleaningPlanLabels.dias((_days.toList()..sort()));
    final freq = (_empresa ? CleaningPlanLabels.empresaFrequencias : CleaningPlanLabels.casaFrequencias)[_frequency] ?? _frequency;
    final mensal = _empresa && _frequency != 'once' && _billingMode == 'monthly';
    return [
      _Titulo('Está tudo certo?'.tr),
      Container(
        key: const Key('plano-resumo-preco'),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.primaryWash,
          borderRadius: BorderRadius.circular(16),
        ),
        child: q == null
            ? (_quoteLoading
                ? const Center(child: CircularProgressIndicator())
                : Text(_store.erro ?? 'Sem preço — verifica a ligação.'.tr, style: const TextStyle(fontSize: 16, color: AppColors.error)))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('{0} por limpeza'.trArgs([CleaningLabels.euro(q.totalPerVisitCents)]),
                    key: const Key('plano-preco-visita'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                if (q.frequency != 'once')
                  Text('cerca de {0} limpezas por mês'.trArgs([q.visitsPerMonth.round() < 1 ? 1 : q.visitsPerMonth.round()]),
                      key: const Key('plano-limpezas-mes'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ]),
      ),
      const SizedBox(height: Spacing.lg),
      _Linha(Icons.event_repeat, '${freq.tr} · $dias · $_horaTexto'),
      _Linha(Icons.timelapse, _teamSize > 1 ? '{0} h · {1} profissionais'.trArgs([_hours, _teamSize]) : '{0} h por limpeza'.trArgs([_hours])),
      if (_empresa || _productsBy == 'cleaner')
        _Linha(Icons.cleaning_services, _empresa ? 'Produtos incluídos'.tr : 'A profissional leva os produtos'.tr),
      if ((q?.travelFeeCents ?? 0) > 0)
        _Linha(Icons.directions_car, 'Inclui {0} de deslocação'.trArgs([CleaningLabels.euro(q!.travelFeeCents)])),
      if (_moradaEscrita.isNotEmpty) _Linha(Icons.place, _moradaEscrita),
      _Linha(Icons.play_circle_outline, 'Começa a {0}'.trArgs([_dataTexto])),
      const SizedBox(height: Spacing.lg),
      if (_empresa && _frequency != 'once') ...[
        _Opcao(
          key: const Key('plano-mes-de-uma-vez'),
          titulo: 'Prefiro pagar o mês de uma vez'.tr,
          escolhida: _billingMode == 'monthly',
          marcavel: true,
          onTap: () => setState(() => _billingMode = _billingMode == 'monthly' ? 'per_visit' : 'monthly'),
        ),
        const SizedBox(height: Spacing.md),
      ],
      Container(
        key: const Key('plano-linha-cartao'),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.credit_card, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              mensal
                  ? 'Pagas no cartão no início de cada mês, só as limpezas com profissional confirmada.'.tr
                  : 'Pagas no cartão na véspera de cada limpeza, só quando a profissional está confirmada.'.tr,
              key: const Key('plano-como-pagas'),
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
          ),
        ]),
      ),
      const SizedBox(height: Spacing.md),
      Text('Agora não pagas nada. Cancelas quando quiseres, sem taxa.'.tr,
          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.35)),
    ];
  }
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

// ── peças do assistente ─────────────────────────────────────────────────────

/// "Passo 2 de 5" e uma barra com um traço por passo.
class _Progresso extends StatelessWidget {
  const _Progresso({required this.passo, required this.total});
  final int passo;
  final int total;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Passo {0} de {1}'.trArgs([passo, total]),
              key: const Key('plano-passo'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.sm),
          Row(children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: Spacing.xs),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= passo ? AppColors.primary : AppColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ]),
        ]),
      );
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.lg),
        child: Text(texto, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.textPrimary)),
      );
}

class _Pergunta extends StatelessWidget {
  const _Pergunta(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(texto, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );
}

class _Ajuda extends StatelessWidget {
  const _Ajuda(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Text(texto, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.35)),
      );
}

/// Uma opção grande para tocar. Escolhida = verde cheio, texto branco e um visto.
class _Opcao extends StatelessWidget {
  const _Opcao({
    super.key,
    required this.titulo,
    required this.escolhida,
    required this.onTap,
    this.subtitulo,
    this.valor,
    this.selo,
    this.centrado = false,
    this.compacto = false,
    this.marcavel = false,
    this.grelha = false,
  });
  final String titulo;
  final String? subtitulo;
  final String? valor;
  final String? selo;
  final bool escolhida;
  final bool centrado;
  final bool compacto;
  /// Liga/desliga (várias ao mesmo tempo): mostra uma caixa vazia quando não está escolhida.
  final bool marcavel;
  /// Numa grelha de 2 colunas: sem a bola à esquerda (o texto precisa da largura); escolhida
  /// leva um visto pequeno no canto.
  final bool grelha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = escolhida ? Colors.white : AppColors.textPrimary;
    final sub = escolhida ? Colors.white : AppColors.textSecondary;
    final visto = Icon(
      escolhida ? Icons.check_circle : (marcavel ? Icons.check_box_outline_blank : Icons.radio_button_unchecked),
      color: escolhida ? Colors.white : AppColors.textSubtle,
      size: 24,
    );
    return Semantics(
      selected: escolhida,
      button: true,
      child: Material(
        color: escolhida ? AppColors.primary : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compacto ? 10 : 14),
          side: BorderSide(color: escolhida ? AppColors.primary : AppColors.dividerStrong, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: grelha
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.xs, Spacing.md),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(titulo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cor, height: 1.25))),
                      SizedBox(
                        width: 20,
                        child: escolhida ? const Icon(Icons.check_circle, color: Colors.white, size: 20) : null,
                      ),
                    ]),
                  )
                : compacto
                ? Center(
                    child: Text(titulo,
                        maxLines: 1,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cor)),
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: centrado ? Spacing.xs : Spacing.md, vertical: Spacing.md),
                    child: centrado
                        ? Center(
                            child: Text(titulo,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cor)),
                          )
                        : Row(children: [
                            visto,
                            const SizedBox(width: Spacing.md),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                  Text(titulo, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cor)),
                                  if (selo != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(Radii.pill)),
                                      child: Text(selo!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                                    ),
                                ]),
                                if (subtitulo != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(subtitulo!, style: TextStyle(fontSize: 16, color: sub, height: 1.3)),
                                  ),
                              ]),
                            ),
                            if (valor != null) ...[
                              const SizedBox(width: Spacing.sm),
                              Text(valor!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cor)),
                            ],
                          ]),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Duas colunas de opções do mesmo tamanho.
class _Grelha extends StatelessWidget {
  const _Grelha({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final linhas = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      linhas.add(Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: children[i]),
            const SizedBox(width: Spacing.sm),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
          ]),
        ),
      ));
    }
    return Column(children: linhas);
  }
}

/// − 4 h + grande, logo debaixo da pergunta.
class _Passador extends StatelessWidget {
  const _Passador({required this.valor, required this.menos, required this.mais});
  final String valor;
  final VoidCallback? menos;
  final VoidCallback? mais;

  Widget _botao(Key key, IconData icone, VoidCallback? onTap, String rotulo) => SizedBox(
        width: 56,
        height: 56,
        child: IconButton.outlined(
          key: key,
          tooltip: rotulo,
          onPressed: onTap,
          iconSize: 28,
          style: IconButton.styleFrom(side: const BorderSide(color: AppColors.dividerStrong, width: 1.5)),
          icon: Icon(icone),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(children: [
        _botao(const Key('plano-horas-menos'), Icons.remove, menos, 'Menos uma hora'.tr),
        Expanded(
          child: Text(valor,
              key: const Key('plano-horas'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        _botao(const Key('plano-horas-mais'), Icons.add, mais, 'Mais uma hora'.tr),
      ]);
}

class _BotaoGrande extends StatelessWidget {
  const _BotaoGrande({super.key, required this.icone, required this.texto, required this.onTap});
  final IconData icone;
  final String texto;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icone, color: AppColors.primary),
          label: Text(texto, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            side: const BorderSide(color: AppColors.dividerStrong, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}

class _Linha extends StatelessWidget {
  const _Linha(this.icone, this.texto);
  final IconData icone;
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icone, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.md),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 16, height: 1.35, color: AppColors.textPrimary))),
        ]),
      );
}
