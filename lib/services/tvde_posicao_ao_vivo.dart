import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/rastreio_interpolacao.dart';

/// [A2 · 21/10/2026] Carro a deslizar — a posição do motorista num canal
/// PRIVADO do Supabase Realtime (broadcast), um por corrida:
/// `tvde_pos:<id da corrida>`.
///
/// * Motorista: [PosicaoAoVivoEmissor] abre o canal e emite, no máximo uma vez
///   por intervalo (`tvde_pos_ao_vivo_intervalo_s`, 2 s), `{lat, lng, heading,
///   speed_kmh, em}`. Não escreve nada no banco.
/// * Cliente: [PosicaoAoVivoOuvinte] abre o mesmo canal e entrega cada posição
///   como [AmostraPosicao] ao marcador que já desliza (`MarcadorAnimado`) — o
///   mapa não se redesenha e a rota não se refaz; só o marcador anda.
///
/// Segurança: canal `private: true`. Quem entra decide a RLS em
/// `realtime.messages` (migração `20261021123223_a2_posicao_ao_vivo_canal_privado`):
/// ouvir só o cliente e o motorista da corrida; emitir só o motorista; e só com
/// a corrida atribuída / a caminho / chegou / em andamento. Anónimos e
/// terceiros não entram.
///
/// Sem canal (rede em baixo, política, servidor antigo) nada parte: o mapa do
/// cliente continua com o que já tinha — a linha do motorista em
/// `driver_locations` por Realtime e o poll do cartão. As duas portas
/// alimentam o MESMO marcador; a amostra repetida ou mais velha é ignorada
/// pelo `InterpoladorDePosicao`.

/// Fases da corrida em que há posição ao vivo (as mesmas da RLS).
const Set<String> kTvdeFasesComPosicao = {
  'motorista_atribuido',
  'motorista_a_caminho',
  'motorista_chegou',
  'em_andamento',
};

/// `true` quando a corrida está numa fase com posição ao vivo.
bool tvdeCorridaComPosicao(String? status) =>
    status != null && kTvdeFasesComPosicao.contains(status);

/// Nome do canal de uma corrida.
String topicoPosicaoAoVivo(String rideId) => 'tvde_pos:$rideId';

/// Nome do evento de broadcast.
const String kEventoPosicao = 'pos';

/// Estado do canal, para o ecrã saber se está a receber pelo canal ou pela
/// reserva (o caminho antigo).
enum EstadoCanalPosicao { desligado, aLigar, ligado, falhou }

/// O transporte. Existe para os testes poderem trocar o Supabase por um falso.
abstract class CanalPosicao {
  /// Regista quem recebe as mensagens. Chamar antes de [ligar].
  void aoReceber(void Function(Map<String, dynamic> payload) callback);

  /// Abre o canal. [estado] recebe `true` quando entrou, `false` (+ erro)
  /// quando falhou, fechou ou passou o tempo.
  void ligar(void Function(bool ligado, Object? erro) estado);

  /// Envia uma mensagem. `false` = não foi (canal em baixo, sem permissão).
  Future<bool> enviar(Map<String, dynamic> payload);

  /// Fecha. Idempotente.
  Future<void> fechar();
}

/// O transporte real: Supabase Realtime, broadcast, canal privado.
class CanalPosicaoSupabase implements CanalPosicao {
  CanalPosicaoSupabase(this.topico, {SupabaseClient? cliente})
      : _sb = cliente ?? Supabase.instance.client;

  final String topico;
  final SupabaseClient _sb;
  RealtimeChannel? _canal;
  void Function(Map<String, dynamic>)? _cb;

  @override
  void aoReceber(void Function(Map<String, dynamic> payload) callback) {
    _cb = callback;
  }

  @override
  void ligar(void Function(bool ligado, Object? erro) estado) {
    final canal = _sb.channel(
      topico,
      opts: const RealtimeChannelConfig(private: true),
    );
    _canal = canal;
    canal.onBroadcast(
      event: kEventoPosicao,
      callback: (payload) {
        final cb = _cb;
        if (cb == null) return;
        // O payload do broadcast chega como {event, payload: {...}, type} ou
        // directamente o mapa enviado, conforme a versão do cliente.
        final dentro = payload['payload'];
        cb(dentro is Map ? Map<String, dynamic>.from(dentro) : payload);
      },
    );
    canal.subscribe((status, erro) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          estado(true, null);
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          estado(false, erro ?? status);
      }
    });
  }

  @override
  Future<bool> enviar(Map<String, dynamic> payload) async {
    final canal = _canal;
    if (canal == null) return false;
    try {
      final r = await canal.sendBroadcastMessage(
        event: kEventoPosicao,
        payload: payload,
      );
      return r == ChannelResponse.ok;
    } catch (e) {
      debugPrint('[PosicaoAoVivo] enviar falhou: $e');
      return false;
    }
  }

  @override
  Future<void> fechar() async {
    final canal = _canal;
    _canal = null;
    _cb = null;
    if (canal == null) return;
    try {
      await _sb.removeChannel(canal);
    } catch (_) {/* já fechado */}
  }
}

typedef FabricaCanalPosicao = CanalPosicao Function(String topico);

CanalPosicao _fabricaPorDefeito(String topico) => CanalPosicaoSupabase(topico);

/// Converte o que vem no canal numa [AmostraPosicao]. Pura. `null` quando a
/// mensagem não traz um ponto válido (nunca se desenha lixo).
///
/// [chegada]: hora LOCAL a que a mensagem chegou. Quando vem, é ela que ordena
/// as amostras do canal (o relógio do telemóvel do motorista pode estar
/// adiantado ou atrasado; as mensagens chegam pela ordem pelo mesmo socket).
AmostraPosicao? amostraDePayloadPosicao(Map<String, dynamic> m,
    {DateTime? chegada}) {
  final lat = m['lat'];
  final lng = m['lng'];
  if (lat is! num || lng is! num) return null;
  final la = lat.toDouble();
  final lo = lng.toDouble();
  if (!la.isFinite || !lo.isFinite || la.abs() > 90 || lo.abs() > 180) {
    return null;
  }
  if (la == 0 && lo == 0) return null;
  final em = DateTime.tryParse('${m['em'] ?? ''}');
  final h = m['heading'];
  final v = m['speed_kmh'];
  return AmostraPosicao(
    ponto: LatLng(la, lo),
    em: (chegada ?? em ?? DateTime.now()).toUtc(),
    heading: h is num && h.isFinite ? h.toDouble() : null,
    velocidadeKmh: v is num && v.isFinite && v >= 0 ? v.toDouble() : null,
  );
}

/// O que o motorista envia. Pura.
Map<String, dynamic> payloadDePosicao({
  required double lat,
  required double lng,
  double? heading,
  double? speedKmh,
  required DateTime em,
}) =>
    <String, dynamic>{
      'lat': lat,
      'lng': lng,
      if (heading != null && heading.isFinite) 'heading': heading,
      if (speedKmh != null && speedKmh.isFinite && speedKmh >= 0)
        'speed_kmh': speedKmh,
      'em': em.toUtc().toIso8601String(),
    };

/// Lado do CLIENTE: ouve o canal da corrida.
class PosicaoAoVivoOuvinte {
  PosicaoAoVivoOuvinte({
    required this.rideId,
    required this.onAmostra,
    FabricaCanalPosicao? fabrica,
    DateTime Function()? relogio,
  })  : _fabrica = fabrica ?? _fabricaPorDefeito,
        _relogio = relogio ?? DateTime.now;

  final String rideId;
  final void Function(AmostraPosicao amostra) onAmostra;
  final FabricaCanalPosicao _fabrica;
  final DateTime Function() _relogio;

  CanalPosicao? _canal;
  EstadoCanalPosicao _estado = EstadoCanalPosicao.desligado;
  EstadoCanalPosicao get estado => _estado;
  int recebidas = 0;

  /// Abre o canal. Idempotente. Nunca atira: sem canal, fica [falhou] e o
  /// ecrã continua com o caminho antigo.
  void iniciar() {
    if (_canal != null) return;
    try {
      final c = _fabrica(topicoPosicaoAoVivo(rideId));
      _canal = c;
      _estado = EstadoCanalPosicao.aLigar;
      c.aoReceber((m) {
        if (_canal != c) return; // já fechado: mensagem atrasada fora
        final a = amostraDePayloadPosicao(m, chegada: _relogio());
        if (a == null) return;
        recebidas++;
        onAmostra(a);
      });
      c.ligar((ligado, erro) {
        if (_canal != c) return;
        _estado = ligado ? EstadoCanalPosicao.ligado : EstadoCanalPosicao.falhou;
        if (!ligado) {
          debugPrint('[PosicaoAoVivo] ouvinte sem canal ($erro) — fica o '
              'caminho antigo (driver_locations + poll)');
        }
      });
    } catch (e) {
      _estado = EstadoCanalPosicao.falhou;
      debugPrint('[PosicaoAoVivo] ouvinte não abriu: $e');
    }
  }

  /// Fecha o canal. Idempotente.
  Future<void> parar() async {
    final c = _canal;
    _canal = null;
    _estado = EstadoCanalPosicao.desligado;
    if (c != null) await c.fechar();
  }
}

/// Lado do MOTORISTA: emite a posição no canal da corrida, no máximo uma vez
/// por [intervalo]. A bateria e a rede não sobem: o GPS já está ligado para a
/// navegação; isto é uma mensagem pequena de 2 em 2 s pelo socket que a app
/// já tem aberto.
class PosicaoAoVivoEmissor {
  PosicaoAoVivoEmissor({
    required this.rideId,
    Duration intervalo = const Duration(seconds: 2),
    FabricaCanalPosicao? fabrica,
    DateTime Function()? relogio,
  })  : intervalo = intervalo < const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : intervalo,
        _fabrica = fabrica ?? _fabricaPorDefeito,
        _relogio = relogio ?? DateTime.now;

  final String rideId;
  final Duration intervalo;
  final FabricaCanalPosicao _fabrica;
  final DateTime Function() _relogio;

  CanalPosicao? _canal;
  EstadoCanalPosicao _estado = EstadoCanalPosicao.desligado;
  EstadoCanalPosicao get estado => _estado;
  DateTime? _ultimoEnvio;
  int enviadas = 0;

  void iniciar() {
    if (_canal != null) return;
    try {
      final c = _fabrica(topicoPosicaoAoVivo(rideId));
      _canal = c;
      _estado = EstadoCanalPosicao.aLigar;
      c.ligar((ligado, erro) {
        if (_canal != c) return;
        _estado = ligado ? EstadoCanalPosicao.ligado : EstadoCanalPosicao.falhou;
        if (!ligado) {
          debugPrint('[PosicaoAoVivo] emissor sem canal ($erro) — o cliente '
              'fica com driver_locations + poll');
        }
      });
    } catch (e) {
      _estado = EstadoCanalPosicao.falhou;
      debugPrint('[PosicaoAoVivo] emissor não abriu: $e');
    }
  }

  /// Emite se o canal está ligado e já passou o [intervalo] desde a última.
  /// Devolve `true` quando mandou.
  bool emitir({
    required double lat,
    required double lng,
    double? heading,
    double? speedKmh,
  }) {
    final c = _canal;
    if (c == null || _estado != EstadoCanalPosicao.ligado) return false;
    final agora = _relogio();
    final ultimo = _ultimoEnvio;
    if (ultimo != null && agora.difference(ultimo) < intervalo) return false;
    _ultimoEnvio = agora;
    enviadas++;
    unawaited(c.enviar(payloadDePosicao(
      lat: lat,
      lng: lng,
      heading: heading,
      speedKmh: speedKmh,
      em: agora,
    )));
    return true;
  }

  Future<void> parar() async {
    final c = _canal;
    _canal = null;
    _estado = EstadoCanalPosicao.desligado;
    _ultimoEnvio = null;
    if (c != null) await c.fechar();
  }
}

/// Qual das duas portas manda no marcador. Com o canal vivo (mensagem há menos
/// de [validadeCanal]) só o canal mexe no carro — um relógio de cada vez, para
/// a regra "nunca para trás" não comparar a hora do servidor com a da chegada.
/// O canal calou → a base (`driver_locations` + poll) volta a mandar.
class FonteDoCarro {
  FonteDoCarro({this.validadeCanal = const Duration(seconds: 7)});

  final Duration validadeCanal;
  DateTime? _ultimoDoCanal;
  bool _noCanal = false;

  bool get noCanal => _noCanal;

  /// Chegou posição pelo canal. `true` = trocou de fonte agora (o marcador
  /// deve recomeçar a contagem, assentando na posição nova).
  bool chegouDoCanal(DateTime agora) {
    _ultimoDoCanal = agora;
    final trocou = !_noCanal;
    _noCanal = true;
    return trocou;
  }

  /// Chegou posição pela base/poll. `null` = ignorar (o canal está vivo);
  /// `false` = aplicar; `true` = aplicar depois de recomeçar (o canal calou).
  bool? chegouDaBase(DateTime agora) {
    final u = _ultimoDoCanal;
    if (_noCanal && u != null && agora.difference(u) <= validadeCanal) {
      return null;
    }
    if (_noCanal) {
      _noCanal = false;
      return true;
    }
    return false;
  }
}

/// Liga e desliga o [PosicaoAoVivoOuvinte] conforme a corrida: abre quando a
/// corrida entra numa fase com posição, fecha quando sai (fim, cancelamento)
/// ou quando muda de corrida. Um só canal de cada vez.
class SincronizadorPosicaoAoVivo {
  SincronizadorPosicaoAoVivo({
    required this.onAmostra,
    FabricaCanalPosicao? fabrica,
    this.ligado = true,
  }) : _fabrica = fabrica;

  final void Function(AmostraPosicao amostra) onAmostra;
  final FabricaCanalPosicao? _fabrica;

  /// Interruptor `tvde_pos_ao_vivo_enabled`.
  bool ligado;

  PosicaoAoVivoOuvinte? _ouvinte;
  PosicaoAoVivoOuvinte? get ouvinte => _ouvinte;

  /// Chamar sempre que a corrida activa muda (id ou estado).
  void sincronizar({String? rideId, String? status}) {
    final quer = ligado && rideId != null && tvdeCorridaComPosicao(status);
    final atual = _ouvinte;
    if (quer && atual != null && atual.rideId == rideId) return;
    if (atual != null) {
      _ouvinte = null;
      unawaited(atual.parar());
    }
    if (!quer) return;
    final novo = PosicaoAoVivoOuvinte(
      rideId: rideId,
      onAmostra: onAmostra,
      fabrica: _fabrica,
    );
    _ouvinte = novo;
    novo.iniciar();
  }

  Future<void> parar() async {
    final atual = _ouvinte;
    _ouvinte = null;
    if (atual != null) await atual.parar();
  }
}
