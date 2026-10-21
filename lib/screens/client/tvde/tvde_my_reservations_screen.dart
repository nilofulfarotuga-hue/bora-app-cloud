import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_dest_change.dart' show TvdeDestChangeQuote;
import '../../../models/tvde_ride.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/ver_nas_minhas_reservas.dart';
import 'ride_mbway_waiting_dialog.dart';

import '../../../l10n/tr.dart';
import '../../../models/ride_kind.dart';
import '../../../utils/ride_kind_context.dart';

/// [Reserva agendada 2026-08-19] "As minhas reservas" — as viagens que o
/// cliente marcou para depois.
///
/// O ecrã é READ-ONLY sobre o relógio: quem trata da rotação de motoristas,
/// dos lembretes e do re-despacho é o cron `tvde-reservations-sweep`. Aqui só
/// se mostra o que está na linha, se deixa cancelar e, desde 12/10/2026,
/// mudar a hora e o destino (padrão Uber Reserve): a cliente que teve de ligar
/// ao Danilo para passar a reserva das 17:30 para as 17:45 faz isto sozinha.
class TvdeMyReservationsScreen extends StatefulWidget {
  const TvdeMyReservationsScreen({super.key, this.acabadaDeMarcar = false});

  /// Aberto logo a seguir a marcar: mostra a faixa "Corrida marcada" com o
  /// botão para o separador Reservas (10/10/2026).
  final bool acabadaDeMarcar;

  @override
  State<TvdeMyReservationsScreen> createState() =>
      _TvdeMyReservationsScreenState();
}

class _TvdeMyReservationsScreenState extends State<TvdeMyReservationsScreen> {
  bool _aCarregar = true;
  int _horasCancelGratis = 2;
  int _maxDias = 30;

  /// Interruptor do servidor (`tvde_reservation_dest_change_enabled`). Nasce
  /// desligado: o botão "Mudar destino" só aparece quando o Danilo o ligar.
  bool _destinoLigado = false;

  /// Reserva com uma mudança em curso — trava LOCAL do botão (lição 05/09:
  /// nunca um `busy` partilhado do store).
  String? _aMudar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final store = context.read<TvdeStore>();
    final limites = await store.loadReservationLimits();
    final destino = await store.reservationDestChangeEnabled();
    await store.loadMyReservations();
    if (!mounted) return;
    setState(() {
      _horasCancelGratis = limites['freeCancelHours'] ?? 2;
      _maxDias = limites['maxAdvanceDays'] ?? 30;
      _destinoLigado = destino;
      _aCarregar = false;
    });
  }

  static const _meses = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  String _quando(DateTime? d) {
    if (d == null) return 'sem hora'.tr;
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${_meses[l.month - 1]} · $hh:$mm';
  }

  /// Cancelar é grátis enquanto faltar mais do que a janela das definições.
  bool _cancelaGratis(TvdeRide r) {
    final quando = r.scheduledAt;
    if (quando == null) return true;
    return quando.toLocal().difference(DateTime.now()).inMinutes >
        _horasCancelGratis * 60;
  }

  /// Ainda se pode mexer: só reservas marcadas que ainda não arrancaram.
  bool _podeMudar(TvdeRide r) =>
      r.status == 'agendada' &&
      r.reservationStatus != 'cancelada' &&
      r.scheduledAt != null;

  Future<void> _cancelar(TvdeRide r) async {
    final gratis = _cancelaGratis(r);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancelar a reserva?'.tr),
        content: Text(
          gratis
              ? 'Ainda estás a tempo — o cancelamento é grátis.'.tr
              : 'Faltam menos de {0} horas para a viagem. Pode haver uma taxa de cancelamento.'.trArgsK(r.rideKind, [_horasCancelGratis]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Manter reserva'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancelar reserva'.tr),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final store = context.read<TvdeStore>();
    try {
      await store.cancelReservation(r.id);
      if (!mounted) return;
      final online = r.paymentMethod != 'cash';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(online
            // O reembolso é automático do lado do servidor — a app só informa.
            ? 'Reserva cancelada. O reembolso é feito automaticamente.'.tr
            : 'Reserva cancelada.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(traduzErroReserva(e))));
    }
  }

  // ── Mudar a HORA (12/10/2026) ───────────────────────────────────────────

  Future<void> _mudarHora(TvdeRide r) async {
    if (_aMudar != null) return;
    final atual = (r.scheduledAt ?? DateTime.now()).toLocal();
    final agora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: atual.isBefore(agora) ? agora : atual,
      firstDate: agora,
      lastDate: agora.add(Duration(days: _maxDias)),
      helpText: 'Dia da viagem'.trK(r.rideKind),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(atual),
      helpText: 'Hora da viagem'.trK(r.rideKind),
    );
    if (hora == null || !mounted) return;
    final nova = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Passar a reserva para {0}?'.trArgs([_quando(nova)])),
        content: Text(
          'O motorista é avisado. Se já tiver outra reserva perto dessa hora, procuramos outro motorista.'.trK(r.rideKind),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Manter como está'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Mudar'.tr),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _aMudar = r.id);
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<TvdeStore>();
    try {
      final res = await store.rescheduleReservation(r.id, nova);
      if (!mounted) return;
      final mantem = res['motorista_mantem'] == true;
      messenger.showSnackBar(SnackBar(
        content: Text(res['sem_mudanca'] == true
            ? 'A reserva já estava nessa hora.'.tr
            : mantem
                ? 'Hora alterada. O teu motorista mantém-se.'.trK(r.rideKind)
                : 'Hora alterada. Vamos procurar motorista para a hora nova.'.trK(r.rideKind)),
      ));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(traduzErroReserva(e))));
      }
    } finally {
      if (mounted) setState(() => _aMudar = null);
    }
  }

  // ── Mudar o DESTINO (12/10/2026, Bloco 2 — atrás do interruptor) ────────

  Future<void> _mudarDestino(TvdeRide r) async {
    if (_aMudar != null) return;
    final escolhido = await showModalBottomSheet<_DestinoEscolhido>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EscolherDestinoSheet(),
    );
    if (escolhido == null || !mounted) return;

    setState(() => _aMudar = r.id);
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<TvdeStore>();
    try {
      // Rota e preço SEMPRE do servidor (Edge tvde-dest-change → RPC).
      final quote = await store.quoteReservationDest(r.id,
          lat: escolhido.lat, lng: escolhido.lng, label: escolhido.morada);
      if (!mounted) return;

      final decisao = await showModalBottomSheet<_DestinoDecisao>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _ReservaDestinoSheet(
          quote: quote,
          method: r.paymentMethod,
          initialPhone: Supabase.instance.client.auth.currentUser?.phone ?? '',
          rideKind: r.rideKind,
        ),
      );
      if (decisao == null || !mounted) return;

      final diff = _int(quote['client_diff_cents']);
      final res = await store.changeReservationDest(r.id,
          lat: escolhido.lat,
          lng: escolhido.lng,
          label: (quote['dest_label'] ?? escolhido.morada).toString(),
          expectedClientDiffCents: diff);

      var mudou = res['estado'] == 'aplicada' || res['applied'] == true;
      Map<String, dynamic>? outcome;
      if (res['needs_payment'] == true) {
        // Diferença a mais com cartão/MB Way: o MESMO caminho da mudança a
        // meio da corrida (tvde-payment charge_dest_change → confirm).
        final changeId = res['change_id']?.toString() ?? '';
        final pmethod = r.paymentMethod == 'mbway' ? 'mbway' : 'card';
        try {
          final charge = await store.chargeDestChange(changeId,
              method: pmethod,
              mbwayPhone: pmethod == 'mbway' ? decisao.phone : null);
          final piId = charge['paymentIntentId'] as String?;
          if (piId == null) throw Exception('sem_payment_intent');
          final amountEur =
              ((charge['amountCents'] as num?)?.toInt() ?? diff) / 100;
          if (pmethod == 'card') {
            final clientSecret = charge['clientSecret'] as String?;
            if (clientSecret == null) throw Exception('sem_client_secret');
            await PaymentService().processPayment(clientSecret);
            outcome = await store.confirmDestChangePayment(piId);
            mudou = outcome?['succeeded'] == true;
          } else {
            if (!mounted) return;
            final ok = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => TvdeRideMbwayWaitingDialog.forDestChange(
                paymentIntentId: piId,
                amountEur: amountEur,
                onResponse: (o) => outcome = o,
              ),
            );
            mudou = ok == true;
          }
        } catch (e) {
          debugPrint('TvdeMyReservations._mudarDestino pagamento => $e');
          mudou = false;
        }
        if (!mudou && changeId.isNotEmpty) {
          await store.cancelDestChange(changeId);
        }
        await store.loadMyReservations();
      }

      if (!mounted) return;
      if (mudou) {
        messenger.showSnackBar(SnackBar(
          content: Text(diff > 0
              ? 'Destino mudado. Pagas mais {0}.'
                  .trArgs([TvdeDestChangeQuote.eur(diff)])
              : diff < 0 && r.paymentMethod != 'cash'
                  ? 'Destino mudado. Devolvemos {0}.'
                      .trArgs([TvdeDestChangeQuote.eur(-diff)])
                  : 'Destino mudado. O preço fica igual.'.tr),
        ));
      } else if (outcome?['refunded'] == true) {
        messenger.showSnackBar(SnackBar(
          content: Text('Pagamento devolvido — o destino não mudou.'.tr),
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Não recebemos a confirmação do pagamento. O destino não mudou.'.tr),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(traduzErroReserva(e))));
      }
    } finally {
      if (mounted) setState(() => _aMudar = null);
    }
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final reservas = store.reservations;

    final Widget lista = _aCarregar
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: reservas.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        const Icon(Icons.event_available,
                            size: 56, color: AppColors.textSubtle),
                        const SizedBox(height: Spacing.md),
                        Center(
                          child: Text(
                            'Ainda não tens viagens marcadas.'.tr,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: Spacing.xl),
                            child: Text(
                              'No ecrã de pedir motorista tens "Marcar para depois".'.trK(context.tvdeKind),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSubtle, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Spacing.lg),
                      itemCount: reservas.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Spacing.md),
                      itemBuilder: (_, i) => _cartao(reservas[i], reservas),
                    ),
            );

    return Scaffold(
      appBar: AppBar(title: Text('As minhas reservas'.tr)),
      body: widget.acabadaDeMarcar
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.lg, Spacing.lg, 0),
                  child: ReservaMarcadaFaixa(titulo: 'Corrida marcada!'.trK(context.tvdeKind)),
                ),
                Expanded(child: lista),
              ],
            )
          : lista,
    );
  }

  /// Etiqueta do pacote ida-e-volta, quando esta reserva é uma das duas pernas.
  ///
  /// [24/09/2026] Antes, as duas pernas apareciam como duas reservas soltas e ninguém
  /// percebia que eram a mesma viagem — e quando a volta não chegava a ser criada, o
  /// cliente via UMA reserva e pensava que estava tudo bem. Agora diz-se qual é qual, e
  /// diz-se também quando falta a outra metade.
  String? _etiquetaPacote(TvdeRide r, List<TvdeRide> todas) {
    if (r.roundtripCreditId == null) return null;
    final irmas = todas.where((o) =>
        o.roundtripCreditId == r.roundtripCreditId && o.id != r.id);
    final temIrma = irmas.isNotEmpty;
    if (r.isReturnLeg) {
      return temIrma ? 'Volta do pacote' : 'Volta do pacote (a ida já passou)';
    }
    return temIrma ? 'Ida do pacote' : 'Ida do pacote · a volta ainda não está marcada';
  }

  Widget _cartao(TvdeRide r, List<TvdeRide> todas) {
    final estado = estadoReservaPt(r);
    final preco = (r.estFareCents / 100).toStringAsFixed(2);
    final podeCancelar = r.reservationStatus != 'cancelada';
    final etiqueta = _etiquetaPacote(r, todas);
    final aMexer = _aMudar == r.id;
    final podeMudar = _podeMudar(r) && !aMexer;
    // O destino de um pacote ida-e-volta, de uma corrida de balcão ou de uma
    // reserva ainda por pagar não se muda daqui (o servidor também recusa).
    final podeMudarDestino = podeMudar &&
        _destinoLigado &&
        r.roundtripCreditId == null &&
        r.agreedFareCents == null &&
        !r.reservationAwaitingPayment;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [21/10 · A1 r1] Encomenda: diz-se logo no topo do cartão.
          if (r.isEncomenda) ...[
            Text('📦 Encomenda'.tr,
                key: const Key('reserva_etiqueta_encomenda'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            const SizedBox(height: 6),
          ],
          if (etiqueta != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryWash,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(r.isReturnLeg ? Icons.u_turn_left : Icons.arrow_forward,
                      size: 14, color: AppColors.primaryDark),
                  const SizedBox(width: 6),
                  Text(etiqueta.tr,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark)),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          Row(
            children: [
              const Icon(Icons.event, size: 18, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Text(
                _quando(r.scheduledAt),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              Text('€$preco',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          _linha(Icons.trip_origin, r.originLabel ?? 'Recolha'),
          const SizedBox(height: Spacing.xs),
          _linha(Icons.place_outlined, r.destLabel ?? 'Destino'),
          const SizedBox(height: Spacing.md),
          _chipEstado(r, estado),
          // O servidor cancela sozinho as reservas não pagas ao fim de 15 min.
          if (r.reservationAwaitingPayment) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Termina o pagamento para a reserva ficar marcada. Se não concluíres em 15 minutos, cancelamos sozinhos e não és cobrado.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (r.reservationStatus == 'sem_motorista') ...[
            const SizedBox(height: Spacing.sm),
            Text(
              r.paymentMethod == 'cash'
                  ? 'Não encontrámos motorista para esta hora. Podes marcar outra viagem.'.trK(r.rideKind)
                  : 'Não encontrámos motorista para esta hora. O reembolso é automático — não precisas de fazer nada.'.trK(r.rideKind),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (r.cancelReason == 'payment_timeout') ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'A reserva foi cancelada por o pagamento não ter sido concluído a tempo. Não foste cobrado.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (podeCancelar) ...[
            const SizedBox(height: Spacing.sm),
            // [12/10/2026] Mudar hora / destino ao lado do cancelar (Uber Reserve).
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_podeMudar(r))
                  TextButton.icon(
                    key: Key('reserva_mudar_hora_${r.id}'),
                    onPressed: podeMudar ? () => _mudarHora(r) : null,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('Mudar hora'.tr),
                  ),
                if (podeMudarDestino)
                  TextButton.icon(
                    key: Key('reserva_mudar_destino_${r.id}'),
                    onPressed: () => _mudarDestino(r),
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                    label: Text('Mudar destino'.tr),
                  ),
                if (aMexer)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Spacing.sm),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                TextButton(
                  onPressed: () => _cancelar(r),
                  child: Text(
                    _cancelaGratis(r)
                        ? 'Cancelar (grátis)'.tr
                        : 'Cancelar reserva',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(IconData icon, String texto) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSubtle),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      );

  Widget _chipEstado(TvdeRide r, String estado) {
    Color cor;
    switch (r.reservationStatus) {
      case 'atribuida':
      case 'ativada':
        cor = AppColors.primary;
        break;
      case 'sem_motorista':
      case 'cancelada':
        cor = AppColors.error;
        break;
      default:
        cor = AppColors.textSecondary;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado,
        style: TextStyle(
            color: cor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Destino escolhido na folha: morada escrita + ponto no mapa (do autocomplete).
class _DestinoEscolhido {
  const _DestinoEscolhido(
      {required this.morada, required this.lat, required this.lng});
  final String morada;
  final double lat;
  final double lng;
}

/// Folha para escolher o destino novo. Só deixa continuar com uma morada
/// escolhida NA LISTA (com coordenadas) — o servidor nunca recebe texto solto.
class _EscolherDestinoSheet extends StatefulWidget {
  const _EscolherDestinoSheet();

  @override
  State<_EscolherDestinoSheet> createState() => _EscolherDestinoSheetState();
}

class _EscolherDestinoSheetState extends State<_EscolherDestinoSheet> {
  final _ctrl = TextEditingController();
  final _campoKey = GlobalKey<AddressAutocompleteFieldState>();
  String? _morada;
  ll.LatLng? _coords;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// "Continuar" sem morada com coordenadas: aceita a morada escrita (se a
  /// encontrar, o botão passa a "Continuar"); senão leva o foco ao campo.
  Future<void> _semDestino() async {
    final campo = _campoKey.currentState;
    if (campo != null && campo.temTextoPorConfirmar) {
      final ok = await campo.confirmarTextoEscrito();
      if (ok || !mounted) return;
    }
    campo?.pedirFoco();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_location_alt_outlined,
                  color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Mudar destino'.tr,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                tooltip: 'Fechar'.tr,
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text('Escreve a morada nova e escolhe-a na lista.'.tr,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: Spacing.md),
          KeyedSubtree(
            key: const Key('reserva_destino_novo'),
            child: AddressAutocompleteField(
              key: _campoKey,
              controller: _ctrl,
              labelText: 'Destino novo'.tr,
              prefixIcon: const Icon(Icons.place_outlined),
              onChanged: (_) {
                if (_coords != null) setState(() => _coords = null);
              },
              onSelected: (address, coords) =>
                  setState(() {
                    _morada = address;
                    _coords = coords;
                  }),
            ),
          ),
          // Espaço para o overlay de sugestões não ficar escondido na folha.
          const SizedBox(height: 220),
          // [14/10, tvde-pedir-nunca-trava] Era cinzento e mudo sem morada
          // escolhida. Agora diz o que falta e, tocado, aceita a morada
          // escrita (geocode) ou leva o foco ao campo.
          BoraAccentButton(
            key: const Key('reserva_destino_continuar'),
            label: _coords == null ? 'Escolhe o destino novo'.tr : 'Continuar'.tr,
            onPressed: _coords == null
                ? _semDestino
                : () => Navigator.pop(
                    context,
                    _DestinoEscolhido(
                        morada: _morada ?? _ctrl.text.trim(),
                        lat: _coords!.latitude,
                        lng: _coords!.longitude)),
          ),
        ],
      ),
    );
  }
}

/// O que o cliente decidiu na folha de confirmação do destino.
class _DestinoDecisao {
  const _DestinoDecisao({required this.phone});

  /// 9 dígitos, só preenchido quando a diferença se paga por MB Way.
  final String phone;
}

/// Confirmação do destino novo de uma RESERVA: morada encontrada, km, preço
/// combinado, preço novo e a diferença (a mais, a menos ou igual). Tudo vem do
/// servidor; "Aceitar" devolve a decisão, fechar devolve null e nada muda.
class _ReservaDestinoSheet extends StatefulWidget {
  const _ReservaDestinoSheet({
    required this.quote,
    required this.method,
    this.initialPhone = '',
    this.rideKind = RideKind.passageiros,
  });

  final Map<String, dynamic> quote;
  final String method;
  final String initialPhone;

  /// [21/10 · A1 r1] As palavras vêm do tipo DESTA reserva.
  final RideKind rideKind;

  @override
  State<_ReservaDestinoSheet> createState() => _ReservaDestinoSheetState();
}

class _ReservaDestinoSheetState extends State<_ReservaDestinoSheet> {
  late final TextEditingController _phone;
  String? _phoneError;

  int get _diff => _TvdeMyReservationsScreenState._int(widget.quote['client_diff_cents']);
  bool get _pagaAgora =>
      _diff > 0 && widget.method != 'cash' && widget.quote['needs_payment'] == true;
  bool get _mbway => _pagaAgora && widget.method == 'mbway';

  @override
  void initState() {
    super.initState();
    final digits = widget.initialPhone.replaceAll(RegExp(r'\D'), '');
    _phone = TextEditingController(
        text: digits.length >= 9 ? digits.substring(digits.length - 9) : '');
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _aceitar() {
    if (_mbway) {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 9) {
        setState(() => _phoneError = 'Indica um número com 9 dígitos.'.tr);
        return;
      }
      Navigator.pop(context, _DestinoDecisao(phone: digits));
      return;
    }
    Navigator.pop(context, const _DestinoDecisao(phone: ''));
  }

  String get _comoPagas {
    const eur = TvdeDestChangeQuote.eur;
    if (_diff == 0) return 'Não há nada a pagar.'.tr;
    if (_diff < 0) {
      return widget.method == 'cash'
          ? 'Pagas {0} a menos ao motorista, em dinheiro.'.trArgsK(widget.rideKind, [eur(-_diff)])
          : 'Devolvemos {0} para o cartão ou MB Way.'.trArgs([eur(-_diff)]);
    }
    switch (widget.method) {
      case 'card':
        return 'Cobramos {0} no cartão agora. O destino só muda depois de o pagamento passar.'
            .trArgs([eur(_diff)]);
      case 'mbway':
        return 'Cobramos {0} por MB Way agora. O destino só muda depois de confirmares no MB Way.'
            .trArgs([eur(_diff)]);
      default:
        return 'Pagas {0} a mais ao motorista, em dinheiro, no fim da viagem.'
            .trArgsK(widget.rideKind, [eur(_diff)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    const secundario = TextStyle(color: AppColors.textSecondary, fontSize: 13);
    const eur = TvdeDestChangeQuote.eur;
    final km = (q['route_km'] ?? q['km_new'] ?? 0);
    final kmTxt = TvdeDestChangeQuote.km(km is num ? km.toDouble() : 0);
    final antes = _TvdeMyReservationsScreenState._int(q['price_before_cents']);
    final depois = _TvdeMyReservationsScreenState._int(q['price_new_cents']);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: Spacing.lg + inset + media.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_location_alt_outlined,
                  color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Mudar destino'.tr,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                tooltip: 'Fechar'.tr,
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text('Destino novo'.tr, style: secundario),
          Text((q['dest_label'] ?? '').toString(),
              key: const Key('reserva_destino_label'),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.md),
          Text('A viagem fica com {0} km.'.trArgsK(widget.rideKind, [kmTxt]),
              key: const Key('reserva_destino_km'), style: secundario),
          const SizedBox(height: Spacing.sm),
          _linha('Preço combinado'.tr, eur(antes)),
          _linha('Preço novo'.tr, eur(depois), forte: true),
          const SizedBox(height: Spacing.sm),
          Text(
            _diff > 0
                ? 'Pagas mais {0}'.trArgs([eur(_diff)])
                : _diff < 0
                    ? 'Devolvemos {0}'.trArgs([eur(-_diff)])
                    : 'Não pagas mais nada'.tr,
            key: const Key('reserva_destino_diff'),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: Spacing.sm),
          Text(_comoPagas, style: secundario),
          if (_mbway) ...[
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('reserva_destino_mbway_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Número MBWay'.tr,
                hintText: '9XXXXXXXX'.tr,
                prefixText: '+351 ',
                errorText: _phoneError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          BoraAccentButton(
            key: const Key('reserva_destino_aceitar'),
            label: 'Aceitar'.tr,
            onPressed: _aceitar,
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'.tr),
          ),
        ],
      ),
    );
  }

  Widget _linha(String k, String v, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13.5))),
            Text(v,
                style: TextStyle(
                    fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary,
                    fontSize: 13.5)),
          ],
        ),
      );
}
