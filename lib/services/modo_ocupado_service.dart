import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/hora_lisboa.dart';

/// MODO OCUPADO DO PARCEIRO (C6, 29/10/2026) — "busy mode" da Uber Eats / Glovo /
/// iFood. A loja carrega em +10 / +20 / +30 min e, durante 2 horas (ou até
/// desligar), os pedidos novos mostram ao cliente um tempo de entrega maior.
///
/// Nada aqui mexe em valores cobrados ou pagos. O interruptor
/// `partner_busy_mode_enabled` (painel admin) nasce DESLIGADO: desligado, as apps
/// não desenham nada e o servidor devolve sempre 0 minutos extra.

/// Os botões do painel do parceiro.
const List<int> kMinutosOcupado = <int>[10, 20, 30];

/// Quanto dura o modo ocupado antes de expirar sozinho (o servidor grava
/// `busy_until = agora + 2 h`).
const Duration kDuracaoModoOcupado = Duration(hours: 2);

/// "HH:MM" em hora de Lisboa (nunca o fuso do telemóvel).
String hhmmLisboa(DateTime d) {
  final l = horaLisboa(d);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.hour)}:${dd(l.minute)}';
}

/// O modo ocupado de uma loja num instante: quantos minutos e até quando.
@immutable
class EstadoOcupado {
  const EstadoOcupado({this.extraMinutos = 0, this.ate});

  /// Sem modo ocupado.
  static const EstadoOcupado nenhum = EstadoOcupado();

  final int extraMinutos;
  final DateTime? ate;

  /// Está a contar em [agora]? (minutos > 0 e a hora de fim ainda não passou)
  bool ativoEm(DateTime agora) =>
      extraMinutos > 0 && ate != null && ate!.isAfter(agora);

  /// Minutos a somar em [agora] (0 se não está ativo ou já expirou).
  int extraEm(DateTime agora) => ativoEm(agora) ? extraMinutos : 0;

  /// "Ocupado: +20 min até 15:30" (ou vazio se não está ativo em [agora]).
  String textoEm(DateTime agora) => ativoEm(agora)
      ? 'Ocupado: +$extraMinutos min até ${hhmmLisboa(ate!)}'
      : '';

  /// Lê a resposta de `partner_set_busy` / uma linha de `restaurants`.
  /// Tolerante: campos em falta dão [nenhum].
  static EstadoOcupado doMapa(Map<dynamic, dynamic> m) {
    final minutos = (m['extra_minutes'] ?? m['busy_extra_minutes']) as num?;
    final fim = m['busy_until'];
    return EstadoOcupado(
      extraMinutos: minutos?.toInt() ?? 0,
      ate: fim == null ? null : DateTime.tryParse(fim.toString()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EstadoOcupado &&
      other.extraMinutos == extraMinutos &&
      other.ate == ate;

  @override
  int get hashCode => Object.hash(extraMinutos, ate);
}

/// Minutos extra que o CLIENTE soma ao tempo de uma loja: 0 com o interruptor
/// desligado, 0 se o modo expirou. É a única conta — os ecrãs não repetem a regra.
int minutosExtraParaCliente({
  required bool interruptorLigado,
  required int busyExtraMinutes,
  required DateTime? busyUntil,
  DateTime? agora,
}) {
  if (!interruptorLigado) return 0;
  return EstadoOcupado(extraMinutos: busyExtraMinutes, ate: busyUntil)
      .extraEm(agora ?? DateTime.now());
}

/// A hora de hoje (ou de amanhã, se já passou) em que a loja diz que o pedido
/// fica pronto, como instante absoluto — ou null se for daqui a mais de 4 horas
/// (o servidor recusa, por isso nem se tenta).
///
/// [hora]/[minuto] são lidos no relógio de LISBOA, como a loja os vê.
DateTime? instanteDoFicaPronto({
  required int hora,
  required int minuto,
  required DateTime agora,
}) {
  final lis = horaLisboa(agora);
  var parede = DateTime(lis.year, lis.month, lis.day, hora, minuto);
  var instante = instanteDeLisboa(parede);
  if (instante.isBefore(agora.subtract(const Duration(minutes: 1)))) {
    parede = DateTime(lis.year, lis.month, lis.day + 1, hora, minuto);
    instante = instanteDeLisboa(parede);
  }
  if (instante.isAfter(agora.add(const Duration(hours: 4)))) return null;
  return instante;
}

/// Uma loja ocupada, como o painel admin a vê.
@immutable
class LojaOcupada {
  const LojaOcupada({
    required this.restaurantId,
    required this.nome,
    required this.extraMinutos,
    required this.ate,
  });

  final String restaurantId;
  final String nome;
  final int extraMinutos;
  final DateTime? ate;

  static LojaOcupada doMapa(Map<dynamic, dynamic> m) => LojaOcupada(
        restaurantId: '${m['restaurant_id'] ?? ''}',
        nome: '${m['nome'] ?? ''}'.trim(),
        extraMinutos: (m['extra_minutes'] as num?)?.toInt() ?? 0,
        ate: m['busy_until'] == null
            ? null
            : DateTime.tryParse(m['busy_until'].toString()),
      );
}

/// Resposta do painel admin: o interruptor geral e as lojas ocupadas.
@immutable
class PainelOcupados {
  const PainelOcupados({required this.ligado, required this.lojas});

  final bool ligado;
  final List<LojaOcupada> lojas;
}

/// A ponte com o servidor. Existe como classe abstrata para os testes porem uma
/// versão falsa; em produção é [ModoOcupadoSupabase].
abstract class ModoOcupadoApi {
  /// Liga ([minutos] 10/20/30) ou desliga (0) o modo ocupado da loja. Devolve o
  /// estado novo, ou null se o servidor recusou ou falhou ([erro] diz porquê).
  Future<EstadoOcupado?> definir(String restaurantId, int minutos);

  /// Texto de erro da última chamada que devolveu null (vazio se não houve).
  String get ultimoErro;

  /// "Fica pronto às…": grava a hora prometida do pedido (null apaga a promessa).
  /// Devolve true se o servidor aceitou.
  Future<bool> prometerPronto(String orderId, DateTime? hora);

  /// Painel admin: quem está ocupado + o interruptor geral.
  Future<PainelOcupados?> listarOcupados();

  /// Painel admin: desliga o modo ocupado de uma loja.
  Future<bool> desligarLoja(String restaurantId);

  /// Painel admin: liga ou desliga o interruptor geral.
  Future<bool> definirInterruptor(bool ligado);
}

class ModoOcupadoSupabase implements ModoOcupadoApi {
  ModoOcupadoSupabase([SupabaseClient? cliente]) : _cliente = cliente;

  final SupabaseClient? _cliente;
  SupabaseClient get _sb => _cliente ?? Supabase.instance.client;

  String _erro = '';
  @override
  String get ultimoErro => _erro;

  @override
  Future<EstadoOcupado?> definir(String restaurantId, int minutos) async {
    _erro = '';
    try {
      final r = await _sb.rpc('partner_set_busy', params: {
        'p_restaurant_id': restaurantId,
        'p_extra_minutes': minutos,
      });
      if (r is Map && r['ok'] == true) return EstadoOcupado.doMapa(r);
      _erro = r is Map ? '${r['error'] ?? ''}' : 'resposta';
    } catch (e) {
      debugPrint('[ModoOcupado] partner_set_busy: $e');
      _erro = 'falhou';
    }
    return null;
  }

  @override
  Future<bool> prometerPronto(String orderId, DateTime? hora) async {
    try {
      final r = await _sb.rpc('partner_set_ready_at', params: {
        'p_order_id': orderId,
        'p_ready_at': hora?.toUtc().toIso8601String(),
      });
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[ModoOcupado] partner_set_ready_at: $e');
      return false;
    }
  }

  @override
  Future<PainelOcupados?> listarOcupados() async {
    try {
      final r = await _sb.rpc('admin_partner_busy_list');
      if (r is! Map || r['ok'] != true) return null;
      final lista = (r['lojas'] as List?) ?? const [];
      return PainelOcupados(
        ligado: r['ligado'] == true,
        lojas: [
          for (final l in lista)
            if (l is Map) LojaOcupada.doMapa(l),
        ],
      );
    } catch (e) {
      debugPrint('[ModoOcupado] admin_partner_busy_list: $e');
      return null;
    }
  }

  @override
  Future<bool> desligarLoja(String restaurantId) async {
    try {
      final r = await _sb.rpc('admin_partner_busy_desligar',
          params: {'p_restaurant_id': restaurantId});
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[ModoOcupado] admin_partner_busy_desligar: $e');
      return false;
    }
  }

  @override
  Future<bool> definirInterruptor(bool ligado) async {
    try {
      await _sb.rpc('admin_update_setting', params: {
        'p_key': 'partner_busy_mode_enabled',
        'p_value': ligado,
      });
      return true;
    } catch (e) {
      debugPrint('[ModoOcupado] admin_update_setting: $e');
      return false;
    }
  }
}
