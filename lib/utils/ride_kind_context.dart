import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/ride_kind.dart';
import '../stores/tvde_driver_store.dart';
import '../stores/tvde_store.dart';

/// Onde os ecrãs vão buscar o tipo do pedido (passageiros/encomendas) para
/// escolher as palavras. Nunca rebenta: sem o store por perto (testes, ecrã
/// solto) é passageiros — o texto de sempre.
extension RideKindDoContexto on BuildContext {
  /// Cliente: a corrida viva manda; sem corrida viva, o que está a pedir.
  RideKind get tvdeKind {
    try {
      return Provider.of<TvdeStore>(this, listen: false).rideKind;
    } catch (_) {
      return RideKind.passageiros;
    }
  }

  /// Motorista/estafeta: a corrida que está a fazer; senão a que lhe é oferecida.
  RideKind get tvdeDriverKind {
    try {
      final s = Provider.of<TvdeDriverStore>(this, listen: false);
      return (s.activeRide ?? s.offeredRide)?.rideKind ?? RideKind.passageiros;
    } catch (_) {
      return RideKind.passageiros;
    }
  }
}
