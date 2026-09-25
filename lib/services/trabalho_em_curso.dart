import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O TRABALHO EM CURSO — quem manda no ecrã enquanto durar.
///
/// Teste ao vivo de 2026-08-29: o Danilo aceitou uma lavagem, saiu da app e
/// voltou. Caiu no ecrã de motorista e **julgou que tinha perdido a lavagem**.
/// A app decidia o ecrã só pelo papel guardado no telemóvel e nunca perguntava
/// ao servidor se havia trabalho a meio.
///
/// A fonte é o servidor (`meu_trabalho_em_curso`), nunca a memória local:
/// estado guardado só no telemóvel morre quando o Android mata a app, que é
/// exactamente o momento em que ele faz falta.
@immutable
class TrabalhoEmCurso {
  const TrabalhoEmCurso({
    required this.categoria,
    required this.bookingId,
    required this.estado,
    required this.morada,
    required this.ganhoCents,
  });

  /// 'limpeza' ou 'lavagem'.
  final String categoria;
  final String bookingId;
  final String estado;
  final String morada;
  final int ganhoCents;

  String get titulo =>
      categoria == 'lavagem' ? 'Lavagem a decorrer' : 'Limpeza a decorrer';

  /// O que a pessoa está a fazer agora, em PT-PT e sem nome técnico.
  String get passo => switch (estado) {
        'accepted' => 'aceite — a caminho',
        'on_the_way' => 'a caminho',
        'picked_up' => 'carro recolhido',
        'in_progress' => 'a trabalhar',
        'delivering' => 'a devolver o carro',
        _ => 'a decorrer',
      };

  static TrabalhoEmCurso? fromJson(Object? res) {
    if (res is! Map) return null;
    if (res['tem'] != true) return null;
    return TrabalhoEmCurso(
      categoria: (res['categoria'] ?? '').toString(),
      bookingId: (res['booking_id'] ?? '').toString(),
      estado: (res['estado'] ?? '').toString(),
      morada: (res['morada'] ?? '').toString(),
      ganhoCents: (res['ganho_cents'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrabalhoEmCurso &&
      other.bookingId == bookingId &&
      other.estado == estado;

  @override
  int get hashCode => Object.hash(bookingId, estado);
}

/// Pergunta ao servidor. Devolve null quando não há trabalho a meio, e também
/// quando a chamada falha — um erro de rede não pode empurrar ninguém para
/// dentro de um trabalho que não existe.
Future<TrabalhoEmCurso?> lerTrabalhoEmCurso() async {
  final sb = Supabase.instance.client;
  if (sb.auth.currentUser == null) return null;
  try {
    final res = await sb.rpc('meu_trabalho_em_curso');
    return TrabalhoEmCurso.fromJson(res);
  } catch (e) {
    debugPrint('lerTrabalhoEmCurso => $e');
    return null;
  }
}
