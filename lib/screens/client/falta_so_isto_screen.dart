import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../services/client_address_service.dart';
import '../../services/location_service.dart';
import '../../stores/cart_store.dart';
import '../../utils/constants.dart';
import '../../utils/map_utils.dart';
import '../../utils/telefone_internacional.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/campo_telefone_internacional.dart';

/// Passo "Falta só isto" (28/11/2026, ordem do Danilo 09:38): "o cliente pode
/// entrar no aplicativo sem telefone, sem morada, mas quando ele for fazer o
/// pedido, ele tem que ter o telefone e a morada".
///
/// Como a Glovo, a Uber Eats e o iFood: antes de pagar, se faltar o telemóvel
/// ou a morada exata, abre este passo; depois de preencher volta-se ao fim do
/// pedido com tudo como estava (o carrinho não se perde).
///
/// - Telemóvel de qualquer país (adendo 10:10), gravado em formato
///   internacional pelo `client_update_my_profile`.
/// - Morada exata: rua e número da porta obrigatórios, andar/porta e
///   indicações para o estafeta, e o pino no mapa que se arrasta ("Confirma
///   onde é a tua porta"). A localização nunca trava: a morada escrita à mão
///   é aceite mesmo sem tocar nas sugestões. Guarda em `client_addresses`
///   (principal se for a primeira) e põe-na no carrinho.
///
/// Textos em PT-PT (app de cliente).
class FaltaSoIstoScreen extends StatefulWidget {
  const FaltaSoIstoScreen({
    super.key,
    required this.precisaTelefone,
    required this.precisaMorada,
    this.categoria = 'pedido',
  });

  final bool precisaTelefone;
  final bool precisaMorada;

  /// Para o painel saber onde a pessoa parou (carrinho, favor, casa, ...).
  final String categoria;

  /// Os testes de widget não têm mapa nativo: desligam-no aqui.
  @visibleForTesting
  static bool mostrarMapa = true;

  @override
  State<FaltaSoIstoScreen> createState() => _FaltaSoIstoScreenState();
}

class _FaltaSoIstoScreenState extends State<FaltaSoIstoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _campoTel = GlobalKey<CampoTelefoneInternacionalState>();
  final _telCtrl = TextEditingController();
  final _ruaCtrl = TextEditingController();
  final _andarCtrl = TextEditingController();
  final _indicacoesCtrl = TextEditingController();
  gmaps.GoogleMapController? _mapa;
  LatLng _pino = kGuardaCenter;
  bool _pinoConhecido = false;
  bool _aGuardar = false;
  bool _completou = false;

  @override
  void initState() {
    super.initState();
    final cliente = context.read<AuthStore>().currentClient;
    _telCtrl.text = cliente?.phone ?? '';
    final cart = context.read<CartStore>();
    if (cart.dropoffStreet.trim().isNotEmpty) _ruaCtrl.text = cart.dropoffStreet;
    if (cart.deliveryLocation != null) {
      _pino = cart.deliveryLocation!;
      _pinoConhecido = true;
    } else if (widget.precisaMorada) {
      unawaited(_irParaOGps());
    }
    unawaited(registarFaltaSoIsto(widget.categoria,
        telefone: widget.precisaTelefone, morada: widget.precisaMorada));
  }

  @override
  void dispose() {
    if (!_completou) {
      unawaited(registarFaltaSoIsto(widget.categoria,
          telefone: widget.precisaTelefone,
          morada: widget.precisaMorada,
          acao: 'desistiu'));
    }
    _telCtrl.dispose();
    _ruaCtrl.dispose();
    _andarCtrl.dispose();
    _indicacoesCtrl.dispose();
    super.dispose();
  }

  Future<void> _irParaOGps() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted || _pinoConhecido) return;
    _moverPino(pos);
  }

  void _moverPino(LatLng p) {
    setState(() {
      _pino = p;
      _pinoConhecido = true;
    });
    _mapa?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(p.toGMaps(), 17));
  }

  String? _validarRua(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 3) return 'Escreve a rua e o número da porta.'.tr;
    final temNumero = RegExp(r'\d').hasMatch(t) ||
        RegExp(r'\bs/?n\b|sem n[uú]mero', caseSensitive: false).hasMatch(t);
    if (!temNumero) {
      return 'Falta o número da porta (ex.: Rua do Comércio, 12).'.tr;
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthStore>();
    final cart = context.read<CartStore>();
    setState(() => _aGuardar = true);

    if (widget.precisaTelefone) {
      final tel = _campoTel.currentState?.internacional;
      if (tel == null) {
        setState(() => _aGuardar = false);
        messenger.showSnackBar(SnackBar(
            content: Text(
                'Número inválido para o país escolhido. Confirma o indicativo e o número.'
                    .tr)));
        return;
      }
      final erro = await auth.editClientProfile(
          name: auth.currentClient?.name ?? '', phone: tel);
      if (!mounted) return;
      if (erro != null) {
        setState(() => _aGuardar = false);
        messenger.showSnackBar(SnackBar(content: Text(erro.tr)));
        return;
      }
    }

    if (widget.precisaMorada) {
      final rua = _ruaCtrl.text.trim();
      final andar = _andarCtrl.text.trim();
      final indicacoes = _indicacoesCtrl.text.trim();
      final linha = andar.isEmpty ? rua : '$rua, $andar';
      final detalhes = [andar, indicacoes].where((s) => s.isNotEmpty).join(' · ');
      try {
        final ja = await ClientAddressService.instance.list();
        await ClientAddressService.instance.create(
          label: 'Casa',
          address: linha,
          street: rua,
          lat: _pino.latitude,
          lng: _pino.longitude,
          isDefault: ja.isEmpty,
          details: detalhes.isEmpty ? null : detalhes,
        );
      } catch (e) {
        // Sem rede: o pedido leva a morada na mesma (o servidor confere a do
        // pedido); guardar na lista fica para a próxima vez.
        debugPrint('FaltaSoIsto: guardar morada falhou (não-fatal): $e');
      }
      cart.updateDeliveryAddress(
        street: linha,
        city: cart.dropoffCity,
        postalCode: cart.dropoffPostalCode,
        location: _pino,
      );
    }

    _completou = true;
    unawaited(registarFaltaSoIsto(widget.categoria,
        telefone: widget.precisaTelefone,
        morada: widget.precisaMorada,
        acao: 'completou'));
    if (!mounted) return;
    setState(() => _aGuardar = false);
    Navigator.of(context).pop(true);
  }

  Widget _mapaComPino() {
    if (!FaltaSoIsto.mapaDisponivel) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: gmaps.GoogleMap(
          key: const Key('falta_so_isto_mapa'),
          initialCameraPosition:
              gmaps.CameraPosition(target: _pino.toGMaps(), zoom: 17),
          onMapCreated: (c) => _mapa = c,
          markers: {
            gmaps.Marker(
              markerId: const gmaps.MarkerId('porta'),
              position: _pino.toGMaps(),
              draggable: true,
              onDragEnd: (p) => setState(() {
                _pino = LatLng(p.latitude, p.longitude);
                _pinoConhecido = true;
              }),
              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  gmaps.BitmapDescriptor.hueGreen),
            ),
          },
          onTap: (p) => setState(() {
            _pino = LatLng(p.latitude, p.longitude);
            _pinoConhecido = true;
          }),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          // Dentro da lista que rola: o mapa fica com o dedo para arrastar o pino.
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Text('Falta só isto'.tr),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.xxl, Spacing.xl, Spacing.xxl, Spacing.xxxl),
            children: [
              Text(
                'Para o estafeta te encontrar e falar contigo.'.tr,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSubtle),
              ),
              if (widget.precisaTelefone) ...[
                const SizedBox(height: Spacing.xl),
                Text('O teu telemóvel'.tr,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Spacing.sm),
                CampoTelefoneInternacional(
                  key: _campoTel,
                  controller: _telCtrl,
                  inicial: context.read<AuthStore>().currentClient?.phone,
                  campoKey: const Key('falta_so_isto_telefone'),
                  helperText:
                      'O estafeta usa este número para te contactar (chamada ou WhatsApp) se precisar.'
                          .tr,
                ),
              ],
              if (widget.precisaMorada) ...[
                const SizedBox(height: Spacing.xl),
                Text('A tua morada exata'.tr,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Spacing.sm),
                AddressAutocompleteField(
                  key: const Key('falta_so_isto_rua'),
                  controller: _ruaCtrl,
                  labelText: 'Rua e número da porta'.tr,
                  prefixIcon: const Icon(Icons.home_outlined),
                  validator: _validarRua,
                  onSelected: (morada, coords) {
                    if (coords != null) _moverPino(coords);
                  },
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  key: const Key('falta_so_isto_andar'),
                  controller: _andarCtrl,
                  decoration: InputDecoration(
                    labelText: 'Andar e porta (opcional)'.tr,
                    hintText: '2.º esq.',
                    prefixIcon: const Icon(Icons.apartment_outlined),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  key: const Key('falta_so_isto_indicacoes'),
                  controller: _indicacoesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Indicações para o estafeta (opcional)'.tr,
                    hintText: 'Portão verde, tocar à campainha 3'.tr,
                    prefixIcon: const Icon(Icons.info_outline),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text('Confirma onde é a tua porta'.tr,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Arrasta o pino ou toca no mapa até ficar em cima da tua porta.'
                      .tr,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSubtle),
                ),
                const SizedBox(height: Spacing.sm),
                _mapaComPino(),
              ],
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                key: const Key('falta_so_isto_continuar'),
                label: 'Continuar'.tr,
                loading: _aGuardar,
                color: AppColors.primary,
                onPressed: _aGuardar ? null : _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O que falta e a abertura do passo.
class FaltaSoIsto {
  FaltaSoIsto._();

  /// O mapa só onde há mapa nativo (nos testes de widget não há).
  static bool get mapaDisponivel => FaltaSoIstoScreen.mostrarMapa;

  /// Telemóvel e morada em falta para este pedido.
  ///
  /// [precisaMorada]: há entrega ou visita. [exigirMoradaGuardada]: além da
  /// morada do carrinho, o cliente tem de ter uma morada exata guardada (o
  /// servidor diz se tem). Sem rede, só se usa o que a app sabe: nunca trava
  /// por falta de ligação.
  static Future<({bool telefone, bool morada})> emFalta(
    BuildContext context, {
    required bool precisaMorada,
    bool exigirMoradaGuardada = true,
  }) async {
    final cliente = context.read<AuthStore>().currentClient;
    final telefone = !telefoneGuardadoValido(cliente?.phone);
    var morada = false;
    if (precisaMorada) {
      final cart = context.read<CartStore>();
      morada = cart.deliveryLocation == null ||
          cart.dropoffStreet.trim().length < 3;
      if (!morada && exigirMoradaGuardada) {
        try {
          final r = await Supabase.instance.client
              .rpc('cliente_dados_em_falta')
              .timeout(const Duration(seconds: 6));
          if (r is Map && r['ok'] == true) morada = r['falta_morada'] == true;
        } catch (_) {/* sem rede ou sem a função: não trava */}
      }
    }
    return (telefone: telefone, morada: morada);
  }

  /// Abre o passo quando falta alguma coisa. `true` = pode seguir.
  static Future<bool> garantir(
    BuildContext context, {
    required bool precisaMorada,
    bool exigirMoradaGuardada = true,
    String categoria = 'pedido',
  }) async {
    final f = await emFalta(context,
        precisaMorada: precisaMorada,
        exigirMoradaGuardada: exigirMoradaGuardada);
    if (!f.telefone && !f.morada) return true;
    if (!context.mounted) return false;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaltaSoIstoScreen(
          precisaTelefone: f.telefone,
          precisaMorada: f.morada,
          categoria: categoria,
        ),
      ),
    );
    return ok ?? false;
  }

  /// Só o telemóvel (reservas de mesa, marcações, Casa, limpeza, lavagem:
  /// a morada já vem do próprio pedido). Sem sessão não faz nada — essas
  /// rotas já pedem a conta antes.
  static Future<bool> garantirTelefone(BuildContext context,
      {String categoria = 'marcacao'}) async {
    final cliente = context.read<AuthStore>().currentClient;
    if (cliente == null || telefoneGuardadoValido(cliente.phone)) return true;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaltaSoIstoScreen(
          precisaTelefone: true,
          precisaMorada: false,
          categoria: categoria,
        ),
      ),
    );
    return ok ?? false;
  }
}

/// Regista no servidor que o passo abriu, foi completado ou ficou a meio (o
/// painel mostra quem parou, para o Danilo poder ajudar). Nunca rebenta.
Future<void> registarFaltaSoIsto(String categoria,
    {required bool telefone, required bool morada, String acao = 'abriu'}) async {
  try {
    await Supabase.instance.client.rpc('falta_so_isto_registar', params: {
      'p_categoria': categoria,
      'p_faltava_telefone': telefone,
      'p_faltava_morada': morada,
      'p_acao': acao,
    }).timeout(const Duration(seconds: 6));
  } catch (_) {/* o registo nunca trava o pedido */}
}
