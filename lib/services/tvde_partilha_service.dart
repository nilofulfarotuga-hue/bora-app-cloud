import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';

/// Partilhar a viagem TVDE em tempo real (como a Uber/Bolt): o cliente cria um
/// link (`tvde_criar_partilha`) e envia-o pela folha de partilha do sistema.
/// Quem abre o link vê, numa página pública (`web/viagem.html`), o carro no
/// mapa, o nome próprio do motorista, a matrícula, o estado e a hora prevista
/// de chegada — nunca telefones nem a morada exata de recolha. O link deixa de
/// funcionar 30 minutos depois de a viagem terminar.
class TvdePartilhaService {
  TvdePartilhaService._();

  /// Cria (ou reaproveita) o link desta corrida. `origem`: 'corrida' | 'sos'.
  static Future<String> criarLink(String rideId, {String origem = 'corrida'}) async {
    final res = await Supabase.instance.client.rpc('tvde_criar_partilha',
        params: {'p_ride': rideId, 'p_origem': origem});
    final mapa = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    final url = (mapa['url'] ?? '').toString();
    if (url.isEmpty) throw StateError('sem_link');
    return url;
  }

  /// Abre a folha de partilha com o link. Erros aparecem em PT-PT simples.
  static Future<void> partilhar(BuildContext context, String rideId,
      {String origem = 'corrida'}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final url = await criarLink(rideId, origem: origem);
      await Share.share(
          'Segue a minha viagem Bora em tempo real: {0}'.trArgs([url]));
    } catch (e) {
      debugPrint('[TvdePartilha] falhou: $e');
      messenger?.showSnackBar(SnackBar(
          content: Text(
              'Não foi possível criar o link da viagem. Tenta de novo.'.tr)));
    }
  }
}
