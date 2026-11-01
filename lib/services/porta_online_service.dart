import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/falha_de_acao.dart' show kAcaoTimeout;
import '../models/online_resultado.dart';

/// [B4 · 01/11/2026] A pergunta ao servidor ANTES de ficar online.
///
/// `prestador_pode_ficar_online()` diz se esta conta pode ligar o botão
/// (aprovada, não bloqueada, não apagada e — TVDE — conforme). Usam-na o
/// `DriverStore.toggleAvailability` (no toque) e o `HeartbeatService.start`
/// (antes de bater: o `driver_heartbeat` põe online quem bate com GPS vivo).
///
/// Falha aberta: sem resposta (rede, tempo) deixa seguir. O travão verdadeiro
/// é o gatilho `trg_online_so_aprovado` em `drivers`, que nunca deixa
/// `is_online=true` sem aprovação.
class PortaOnline {
  PortaOnline._();

  /// Quanto tempo vale uma resposta guardada para o batimento (o toque no
  /// botão pergunta sempre de novo).
  static const Duration validade = Duration(seconds: 60);

  /// Quem pergunta ao servidor. Os testes trocam isto (sem rede).
  @visibleForTesting
  static Future<dynamic> Function() perguntar =
      () => Supabase.instance.client.rpc('prestador_pode_ficar_online');

  static OnlineResultado? _ultima;
  static DateTime? _ultimaEm;

  /// A última resposta do servidor (null se nunca respondeu ou foi esquecida).
  static OnlineResultado? get ultimaResposta => _ultima;

  /// Pergunta ao servidor. Com [forcar] = false aproveita uma resposta com
  /// menos de [validade].
  static Future<OnlineResultado> verificar({bool forcar = true}) async {
    final guardada = _ultima;
    final em = _ultimaEm;
    if (!forcar &&
        guardada != null &&
        em != null &&
        DateTime.now().difference(em) < validade) {
      return guardada;
    }
    try {
      final res = await perguntar().timeout(kAcaoTimeout);
      final r = OnlineResultado.daResposta(res);
      if (!r.semRespostaDoServidor) {
        _ultima = r;
        _ultimaEm = DateTime.now();
      }
      return r;
    } catch (e) {
      debugPrint('[PortaOnline] sem resposta do servidor: $e');
      return const OnlineResultado.semResposta();
    }
  }

  /// Esquece a resposta guardada (sair da conta, troca de estafeta, testes).
  static void esquecer() {
    _ultima = null;
    _ultimaEm = null;
  }
}
