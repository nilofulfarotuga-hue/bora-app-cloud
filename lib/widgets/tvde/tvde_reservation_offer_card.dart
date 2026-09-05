import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/tvde_ride.dart';

/// [Reserva agendada 2026-08-19] Cartão da OFERTA ANTECIPADA de reserva.
///
/// Aparece sobre o mapa quando `reservation_offer_driver_id` é este motorista.
/// O tempo para responder NÃO é calculado aqui: vem em
/// `reservation_offer_expires_at`, já pronto do servidor — o cartão só conta
/// para trás. Quando chega a zero o servidor passa ao seguinte da rotação.
class TvdeReservationOfferCard extends StatefulWidget {
  const TvdeReservationOfferCard({
    super.key,
    required this.ride,
    required this.onAccept,
    required this.onReject,
  });

  final TvdeRide ride;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<TvdeReservationOfferCard> createState() =>
      _TvdeReservationOfferCardState();
}

class _TvdeReservationOfferCardState extends State<TvdeReservationOfferCard> {
  Timer? _tick;

  /// Guarda de resposta LOCAL deste cartão (PADRAO_BORA.md 3.13, cicatriz de
  /// 05/09/2026). Antes os botões dependiam de `widget.busy` — o `busy`
  /// GLOBAL do `TvdeDriverStore`, mexido por dezenas de operações — sem
  /// nenhuma ligação a ESTE aceitar/recusar. Numa oferta com contagem
  /// decrescente isso é o pior caso: o botão morto e a oferta a expirar
  /// sozinha nas mãos do motorista.
  ///
  /// `onAccept`/`onReject` são `VoidCallback` (fire-and-forget) — este
  /// cartão não tem um Future para esperar, por isso destrava-se sozinho ao
  /// fim de alguns segundos em vez de ficar preso para sempre se a resposta
  /// do servidor demorar ou falhar em silêncio.
  bool _respondendo = false;
  Timer? _timeoutResposta;
  static const _tempoLimiteResposta = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TvdeReservationOfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A oferta rodou para outra ride — o que estava em curso já não se
    // aplica a esta decisão nova; destrava.
    if (_respondendo && oldWidget.ride.id != widget.ride.id) {
      _timeoutResposta?.cancel();
      _respondendo = false;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _timeoutResposta?.cancel();
    super.dispose();
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

  String get _quando {
    final d = widget.ride.scheduledAt?.toLocal();
    if (d == null) return 'hora a confirmar';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_meses[d.month - 1]} · $hh:$mm';
  }

  /// Segundos que faltam para a oferta expirar (0 se já passou).
  int get _segundosRestantes {
    final fim = widget.ride.reservationOfferExpiresAt;
    if (fim == null) return 0;
    final s = fim.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  void _tapAceitar() {
    if (_respondendo) return;
    _travarResposta();
    widget.onAccept();
  }

  void _tapRecusar() {
    if (_respondendo) return;
    _travarResposta();
    widget.onReject();
  }

  void _travarResposta() {
    setState(() => _respondendo = true);
    _timeoutResposta?.cancel();
    _timeoutResposta = Timer(_tempoLimiteResposta, () {
      if (mounted) setState(() => _respondendo = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _segundosRestantes;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    // [Regra de ouro do motorista, 2026-08-21] O numero GRANDE e o que ELE
    // ganha. A variavel chamava-se `ganho` mas lia o preco do CLIENTE
    // (estFareCents) — mostrava-lhe 25,00 EUR quando ele recebe 22,00 EUR.
    // O total do cliente passa a aparecer so em pequeno, e so em dinheiro.
    final ganho =
        ((widget.ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    final cobra = (widget.ride.estFareCents / 100).toStringAsFixed(2);
    final mostraCobranca =
        widget.ride.paymentMethod == 'cash' && widget.ride.estFareCents > 0;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Reserva para aceitar',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                if (s > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$mm:$ss',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: 16, color: AppColors.textSubtle),
                const SizedBox(width: 6),
                Text(_quando,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Text('€$ganho',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.primary)),
              ],
            ),
            if (mostraCobranca) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text('cobras €$cobra ao cliente',
                    key: const Key('oferta_cobra_cliente'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSubtle)),
              ),
            ],
            const SizedBox(height: 8),
            _linha(Icons.trip_origin, widget.ride.originLabel ?? 'Recolha'),
            const SizedBox(height: 4),
            _linha(Icons.place_outlined, widget.ride.destLabel ?? 'Destino'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _respondendo ? null : _tapRecusar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Recusar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _respondendo ? null : _tapAceitar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _respondendo
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Aceitar reserva'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(IconData icon, String texto) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSubtle),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
}
