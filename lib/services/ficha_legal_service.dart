import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ficha legal do motorista TVDE (Lei 45/2018 revista pela Lei 59/2026).
///
/// Tudo o que aqui se mostra vem do servidor (`motorista_ficha_fiscalizacao`,
/// `motorista_minha_ficha_legal`). A app não calcula validades nem estados:
/// só desenha o que o servidor devolve e guarda a última cópia no telemóvel,
/// porque a PSP/GNR manda parar onde calha — muitas vezes sem rede.
class FichaLegalService {
  FichaLegalService._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String _cacheKey(String uid) => 'bora.fiscalizacao.ficha.$uid';

  /// Ficha para mostrar à autoridade. Rede primeiro (8 s); sem rede, a última
  /// cópia guardada, marcada como offline. Sem rede e sem cópia → erro.
  static Future<FichaFiscalizacao> carregarFiscalizacao() async {
    final uid = _c.auth.currentUser?.id;
    try {
      final r = await _c
          .rpc('motorista_ficha_fiscalizacao')
          .timeout(const Duration(seconds: 8));
      final m = Map<String, dynamic>.from(r as Map);
      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey(uid), jsonEncode(m));
        } catch (_) {/* cache é conveniência; a ficha já está na mão */}
      }
      return FichaFiscalizacao(m, offline: false);
    } catch (e) {
      if (uid != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final s = prefs.getString(_cacheKey(uid));
          if (s != null) {
            return FichaFiscalizacao(
                Map<String, dynamic>.from(jsonDecode(s) as Map),
                offline: true);
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Os campos editáveis da ficha (formulário do motorista).
  static Future<Map<String, dynamic>> minhaFicha() async {
    final r = await _c
        .rpc('motorista_minha_ficha_legal')
        .timeout(const Duration(seconds: 10));
    if (r == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> guardar(Map<String, dynamic> campos) async {
    await _c.rpc('motorista_guardar_ficha_legal',
        params: {'p': campos}).timeout(const Duration(seconds: 12));
  }

  /// Pergunta ao servidor ANTES de ligar o "online". Se a rede falhar deixa
  /// seguir: o travão verdadeiro é o gatilho em `drivers`, e um aviso falso
  /// de "documento expirado" por falta de rede seria pior do que nenhum.
  static Future<List<String>> documentosExpirados() async {
    try {
      final r = await _c
          .rpc('motorista_pode_ficar_online')
          .timeout(const Duration(seconds: 5));
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] == true) return const [];
      return ((m['expirados'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Manda o PDF da ficha para o email da própria conta. Devolve o email.
  static Future<String> enviarCopiaPorEmail() async {
    final res = await _c.functions
        .invoke('ficha-fiscalizacao-email', body: const {})
        .timeout(const Duration(seconds: 30));
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    if (data['ok'] == true) return (data['email'] ?? '').toString();
    throw Exception((data['mensagem'] ?? data['error'] ?? 'falhou').toString());
  }
}

/// Leitura tipada (e tolerante) do JSON da fiscalização.
class FichaFiscalizacao {
  FichaFiscalizacao(this.raw, {required this.offline});

  final Map<String, dynamic> raw;
  final bool offline;

  Map<String, dynamic> _sec(String k) =>
      raw[k] is Map ? Map<String, dynamic>.from(raw[k] as Map) : const {};

  Map<String, dynamic> get motorista => _sec('motorista');
  Map<String, dynamic> get veiculo => _sec('veiculo');
  Map<String, dynamic>? get operador =>
      raw['operador'] is Map ? Map<String, dynamic>.from(raw['operador'] as Map) : null;
  Map<String, dynamic> get plataforma => _sec('plataforma');
  Map<String, dynamic>? get viagem =>
      raw['viagem'] is Map ? Map<String, dynamic>.from(raw['viagem'] as Map) : null;
  Map<String, dynamic> get verificacao => _sec('verificacao');
  String? get geradoEm => raw['gerado_em']?.toString();

  List<DocumentoEstado> get documentos => ((raw['documentos'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => DocumentoEstado.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  /// O QR só vale enquanto o token não expirar.
  bool tokenValido(DateTime agora) {
    final exp = DateTime.tryParse(verificacao['expira_em']?.toString() ?? '');
    return exp != null && exp.isAfter(agora);
  }
}

class DocumentoEstado {
  const DocumentoEstado(
      {required this.doc,
      required this.rotulo,
      required this.estado,
      this.validade,
      this.dias});

  factory DocumentoEstado.fromJson(Map<String, dynamic> m) => DocumentoEstado(
        doc: (m['doc'] ?? '').toString(),
        rotulo: (m['rotulo'] ?? '').toString(),
        estado: (m['estado'] ?? 'em_falta').toString(),
        validade: m['validade']?.toString(),
        dias: m['dias'] is num ? (m['dias'] as num).toInt() : null,
      );

  final String doc;
  final String rotulo;

  /// valido · a_expirar · expirado · em_falta — decidido pelo servidor.
  final String estado;
  final String? validade;
  final int? dias;
}

/// Textos e formatos partilhados pelo ecrã do motorista e pelo recibo.
class FichaTexto {
  FichaTexto._();

  static String estado(String e) => switch (e) {
        'valido' => 'Válido',
        'a_expirar' => 'A expirar',
        'expirado' => 'Expirado',
        _ => 'Por preencher',
      };

  /// '2027-03-01' → '01/03/2027'. Nulo/ inválido → 'por preencher'.
  static String data(String? iso) {
    if (iso == null || iso.isEmpty) return 'por preencher';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Data e hora em Lisboa, a partir de um instante UTC do servidor.
  static String dataHora(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '—';
    final l = paraLisboa(d.toUtc());
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(l.day)}/${p(l.month)}/${l.year} ${p(l.hour)}:${p(l.minute)}';
  }

  /// Portugal continental: UTC+1 do último domingo de Março ao último domingo
  /// de Outubro (01:00 UTC), UTC+0 no resto. Sem pacote de fusos.
  static DateTime paraLisboa(DateTime utc) {
    DateTime ultimoDomingo(int ano, int mes) {
      var d = DateTime.utc(ano, mes + 1, 0);
      while (d.weekday != DateTime.sunday) {
        d = d.subtract(const Duration(days: 1));
      }
      return DateTime.utc(d.year, d.month, d.day, 1);
    }

    final inicio = ultimoDomingo(utc.year, 3);
    final fim = ultimoDomingo(utc.year, 10);
    final verao = !utc.isBefore(inicio) && utc.isBefore(fim);
    return utc.add(Duration(hours: verao ? 1 : 0));
  }

  static String euro(int? cents) {
    if (cents == null) return '—';
    return '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String meio(String? m) => switch (m) {
        'card' => 'Cartão',
        'mbway' => 'MB Way',
        'cash' => 'Dinheiro',
        null => '—',
        _ => m,
      };
}
