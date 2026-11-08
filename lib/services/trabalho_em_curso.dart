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
    this.agendadoPara,
  });

  /// 'limpeza', 'lavagem' ou 'casa'.
  final String categoria;
  final String bookingId;
  final String estado;
  final String morada;
  final int ganhoCents;

  /// Hora marcada do trabalho (missão m2, 08/11/2026). null = não se sabe.
  final DateTime? agendadoPara;

  /// Quantas horas antes da hora marcada um trabalho só aceite já conta como
  /// "a decorrer" (a pessoa sai de casa). Igual ao SQL proposto.
  static const Duration janela = Duration(hours: 3);

  /// Aceite para outro dia / mais tarde: NÃO é trabalho a decorrer. Foi o
  /// caso de 08/11: uma limpeza aceite para sábado ficava na faixa "aceite —
  /// a caminho" dias a fio e tapava o interruptor Online.
  bool eParaMaisTarde(DateTime agora) {
    final quando = agendadoPara;
    if (quando == null) return false;
    if (estado != 'accepted' && estado != 'aceite') return false;
    return quando.isAfter(agora.add(janela));
  }

  /// "Próxima limpeza: sábado 13:30".
  String get textoProxima {
    final q = agendadoPara?.toLocal();
    final nome = switch (categoria) {
      'lavagem' => 'Próxima lavagem',
      'casa' => 'Próximo trabalho da Casa',
      _ => 'Próxima limpeza',
    };
    if (q == null) return nome;
    const dias = [
      'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo', //
    ];
    final hh = q.hour.toString().padLeft(2, '0');
    final mm = q.minute.toString().padLeft(2, '0');
    return '$nome: ${dias[q.weekday - 1]} $hh:$mm';
  }

  // Regra 1.18: um caso por categoria, sem "o resto é limpeza" para a Casa.
  String get titulo => switch (categoria) {
        'lavagem' => 'Lavagem a decorrer',
        'casa' => 'Trabalho da Casa a decorrer',
        _ => 'Limpeza a decorrer',
      };

  /// O que a pessoa está a fazer agora, em PT-PT e sem nome técnico.
  /// A Casa usa estados em português (casa_pedidos.estado): aceite,
  /// a_caminho, chegou, em_curso.
  String get passo => switch (estado) {
        'accepted' => 'aceite — a caminho',
        'on_the_way' => 'a caminho',
        'picked_up' => 'carro recolhido',
        'in_progress' => 'a trabalhar',
        'delivering' => 'a devolver o carro',
        'aceite' => 'aceite',
        'a_caminho' => 'a caminho',
        'chegou' => 'no local',
        'em_curso' => 'a trabalhar',
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
      agendadoPara: res['scheduled_at'] == null
          ? null
          : DateTime.tryParse(res['scheduled_at'].toString()),
    );
  }

  TrabalhoEmCurso comAgendadoPara(DateTime? quando) => TrabalhoEmCurso(
        categoria: categoria,
        bookingId: bookingId,
        estado: estado,
        morada: morada,
        ganhoCents: ganhoCents,
        agendadoPara: quando,
      );

  /// A tabela onde este trabalho vive (para a hora marcada e o tempo real).
  String? get tabela => switch (categoria) {
        'limpeza' => 'cleaning_bookings',
        'lavagem' => 'carwash_bookings',
        _ => null,
      };

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
    final t = TrabalhoEmCurso.fromJson(res);
    if (t == null) return null;
    return _comHoraMarcada(sb, t);
  } catch (e) {
    debugPrint('lerTrabalhoEmCurso => $e');
    return null;
  }
}

/// Missão m2: enquanto o servidor não devolve a hora marcada, lê-se da
/// própria marcação (a pessoa vê as suas). Sem resposta: fica como estava.
Future<TrabalhoEmCurso> _comHoraMarcada(
    SupabaseClient sb, TrabalhoEmCurso t) async {
  if (t.agendadoPara != null) return t;
  final tabela = t.tabela;
  if (tabela == null) return t;
  try {
    final b = await sb
        .from(tabela)
        .select('scheduled_at')
        .eq('id', t.bookingId)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    final q = b?['scheduled_at'];
    return q == null ? t : t.comAgendadoPara(DateTime.tryParse(q.toString()));
  } catch (_) {
    return t;
  }
}

/// Missão m2 (08/11/2026): o trabalho aceite para MAIS TARDE desta
/// [categoria] ('limpeza' | 'lavagem'), para o cartão pequeno "Próxima
/// limpeza: sábado 14:00" — nunca na faixa. null = nenhum (ou sem resposta).
Future<TrabalhoEmCurso?> lerProximoTrabalho(String categoria) async {
  try {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return null;
    final res = await sb.rpc('meu_trabalho_em_curso');
    // Servidor novo (proposta 02 da missão m2): vem em 'proxima'.
    if (res is Map && res['proxima'] is Map) {
      final p = Map<String, dynamic>.from(res['proxima'] as Map);
      if (p['categoria'] != categoria) return null;
      return TrabalhoEmCurso(
        categoria: categoria,
        bookingId: (p['booking_id'] ?? '').toString(),
        estado: 'accepted',
        morada: '',
        ganhoCents: 0,
        agendadoPara: DateTime.tryParse('${p['scheduled_at']}'),
      );
    }
    final t = TrabalhoEmCurso.fromJson(res);
    if (t == null || t.categoria != categoria) return null;
    final comHora = await _comHoraMarcada(sb, t);
    return comHora.eParaMaisTarde(DateTime.now()) ? comHora : null;
  } catch (e) {
    debugPrint('lerProximoTrabalho => $e');
    return null;
  }
}
