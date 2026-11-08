/// O servidor da "A minha conta" (missão m2-estafeta-conta-fila-2026-11-08).
///
/// Lê: `driver_minha_conta_estado` (fonte única, também do painel). Enquanto a
/// função não está no servidor — ou sem resposta dela — monta o mesmo semáforo
/// na app com o que já existe (`drivers`, `driver_fiscal_status_get`,
/// comprovativo de atividade, recibo do mês, `meu_acerto_semanal`, robô dos
/// documentos), pela regra pura de `minha_conta.dart`.
///
/// Grava só por funções que já existem e são do próprio (`auth.uid()`):
/// fotos e números pelo `driver_register_or_update` (via
/// [EstafetaDocumentosService]); morada, data de nascimento e IBAN pelo
/// `provider_update_legal_fields` (valida o IBAN e os 18 anos no servidor);
/// "Já paguei" abre um pedido no Suporte (`support_tickets`), que avisa o
/// admin. Nada aqui mexe em valores de dinheiro.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'atividade_service.dart';
import 'estafeta_documentos_service.dart';
import 'legal_fields_service.dart';
import 'minha_conta.dart';

class MinhaContaService {
  MinhaContaService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// O número de MB Way da Bora para pagar a dívida.
  static const String mbwayBora = '937 501 673';

  /// Sobe sempre que algo se grava na "A minha conta": a barra fina do mapa
  /// e quem mais estiver a mostrar o estado volta a ler.
  static final ValueNotifier<int> versao = ValueNotifier<int>(0);

  static const Duration _tempo = Duration(seconds: 10);

  /// Colunas de `drivers` que o semáforo usa.
  static const String colunas =
      'user_id, name, phone, vehicle_type, approval_status, photo_url, '
      'registration_selfie_url, document_photo_url, document_number, '
      'vehicle_photo_url, vehicle_doc_url, license_plate, address, birth_date, '
      'iban, stripe_account_status, debt_cents, blocked_for_debt';

  /// O estado da conta de quem tem sessão ([userId] null) ou, para o admin,
  /// de outra pessoa. null = sem sessão / sem resposta nenhuma (falha aberta).
  static Future<EstadoMinhaConta?> carregar({String? userId}) async {
    final String? uid;
    try {
      uid = _sb.auth.currentUser?.id;
    } catch (_) {
      return null; // Supabase por iniciar (arranque/testes): falha aberta
    }
    if (uid == null) return null;
    try {
      final r = await _sb.rpc('driver_minha_conta_estado', params: {
        if (userId != null) 'p_user_id': userId,
      }).timeout(_tempo);
      final e = EstadoMinhaConta.fromJson(r);
      if (e.itens.isNotEmpty) return e;
    } catch (e) {
      // Função ainda não está no servidor (proposta da missão m2) ou sem rede.
      debugPrint('[MinhaConta] driver_minha_conta_estado: $e');
    }
    if (userId != null && userId != uid) return carregarParaAdmin(userId);
    return _montarNaApp(uid);
  }

  /// Painel, sem a função no servidor: só o que se lê da linha `drivers`.
  static Future<EstadoMinhaConta?> carregarParaAdmin(String userId) async {
    try {
      final d = await _sb
          .from('drivers')
          .select(colunas)
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(_tempo);
      if (d == null) return null;
      return montarMinhaConta(driver: Map<String, dynamic>.from(d));
    } catch (e) {
      debugPrint('[MinhaConta] admin $userId: $e');
      return null;
    }
  }

  static Future<EstadoMinhaConta?> _montarNaApp(String uid) async {
    final Map<String, dynamic> driver;
    try {
      final d = await _sb
          .from('drivers')
          .select(colunas)
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(_tempo);
      if (d == null) return null;
      driver = Map<String, dynamic>.from(d);
    } catch (e) {
      debugPrint('[MinhaConta] drivers: $e');
      return null;
    }

    final hoje = DateTime.now();
    final resultados = await Future.wait<Object?>([
      _tentar(() => _sb.rpc('driver_fiscal_status_get')),
      _tentar(AtividadeService.carregar),
      _tentar(() => _recibo(hoje)),
      _tentar(_divida),
      _tentar(_robo),
    ]);
    final fiscal = resultados[0];
    final atividade = resultados[1];
    final recibo = resultados[2];
    final divida = resultados[3];
    final robo = resultados[4];

    String? atividadeStatus;
    var atividadeTemDoc = false;
    if (atividade is AtividadeEstado && atividade.ePrestador) {
      atividadeStatus = switch (atividade.status) {
        AtividadeStatus.porEnviar => 'por_enviar',
        AtividadeStatus.emAnalise => 'em_analise',
        AtividadeStatus.aprovada => 'aprovada',
        AtividadeStatus.recusada => 'recusada',
      };
      atividadeTemDoc = atividade.temDocumento;
    }

    return montarMinhaConta(
      driver: driver,
      fiscal: fiscal is Map ? Map<String, dynamic>.from(fiscal) : null,
      atividadeStatus: atividadeStatus,
      atividadeTemDocumento: atividadeTemDoc,
      recibo: recibo is Map ? Map<String, dynamic>.from(recibo) : null,
      dividaCents: divida is int ? divida : 0,
      robo: robo is Map<String, DecisaoRobo> ? robo : const {},
      hoje: hoje,
    );
  }

  static Future<Object?> _tentar(Future<Object?> Function() f) async {
    try {
      return await f().timeout(_tempo);
    } catch (e) {
      debugPrint('[MinhaConta] parte em falta: $e');
      return null;
    }
  }

  /// A linha do recibo verde do mês passado (o recibo começa em outubro/2026).
  static Future<Object?> _recibo(DateTime hoje) async {
    final ant = DateTime(hoje.year, hoje.month - 1, 1);
    if (ant.isBefore(DateTime(2026, 10))) return null;
    final s = await _sb.rpc('driver_monthly_invoice_summary',
        params: {'p_year': ant.year, 'p_month': ant.month});
    final lista = s is Map ? s['estafetas'] : null;
    if (lista is List && lista.isNotEmpty && lista.first is Map) {
      return Map<String, dynamic>.from(lista.first as Map);
    }
    return null;
  }

  /// Semanas fechadas em que a pessoa deve à Bora e ainda não pagou.
  static Future<Object?> _divida() async {
    final r = await _sb.rpc('meu_acerto_semanal', params: {'p_semanas': 8});
    var total = 0;
    if (r is List) {
      for (final s in r) {
        if (s is Map &&
            s['sentido'] == 'pessoa_deve' &&
            s['tudo_pago'] != true) {
          total += (s['total_cents'] as num?)?.toInt().abs() ?? 0;
        }
      }
    }
    return total;
  }

  /// O que o robô dos documentos decidiu (só quando está a agir).
  static Future<Object?> _robo() async {
    final r = await _sb.rpc('provider_documentos_estado');
    final out = <String, DecisaoRobo>{};
    if (r is Map && r['ativo'] == true && r['itens'] is List) {
      for (final i in r['itens'] as List) {
        if (i is! Map) continue;
        final campo = i['campo']?.toString();
        final decisao = i['decisao']?.toString();
        if (campo == null || decisao == null) continue;
        out[campo] = DecisaoRobo(decisao, i['motivo_pt']?.toString());
      }
    }
    return out;
  }

  // ── Gravar ────────────────────────────────────────────────────────────────

  /// Foto ou texto do cadastro (selfie, documento, veículo, número,
  /// matrícula) — pelo `driver_register_or_update` do próprio.
  static Future<void> gravarRegisto(String chave, String valor) async {
    await EstafetaDocumentosService.gravar(chave, valor, contaAprovada: true);
    versao.value++;
  }

  /// Morada, data de nascimento ou IBAN — só o campo dado; o resto fica.
  static Future<void> gravarLegal({
    String? morada,
    DateTime? nascimento,
    String? iban,
  }) async {
    final params = <String, dynamic>{
      'p_role': 'driver',
      if (morada != null) 'p_address': morada.trim(),
      if (iban != null) 'p_iban': limparIban(iban),
      if (nascimento != null)
        'p_birth_date': '${nascimento.year.toString().padLeft(4, '0')}-'
            '${nascimento.month.toString().padLeft(2, '0')}-'
            '${nascimento.day.toString().padLeft(2, '0')}',
    };
    try {
      final r = await _sb
          .rpc('provider_update_legal_fields', params: params)
          .timeout(LegalFieldsService.timeout);
      if (r is! Map || r['ok'] != true) {
        throw const MinhaContaException(
            'Não encontrámos a tua conta. Entra outra vez e tenta de novo.');
      }
    } on MinhaContaException {
      rethrow;
    } catch (e) {
      throw MinhaContaException(LegalFieldsService.messageFor(e));
    }
    versao.value++;
  }

  /// "Já paguei": abre um pedido no Suporte; o gatilho do servidor avisa a
  /// equipa. Não marca nada como pago — isso é sempre do admin.
  static Future<void> avisarQueJaPaguei(int cents) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      throw const MinhaContaException(
          'A tua sessão terminou. Entra outra vez e tenta de novo.');
    }
    try {
      await _sb.from('support_tickets').insert({
        'user_id': uid,
        'user_role': 'driver',
        'subject': 'Pagamento à Bora (estafeta)',
        'question':
            'Já paguei ${euros(cents)} à Bora por MB Way ($mbwayBora). '
                'Enviado pela app, em "A minha conta".',
      }).timeout(_tempo);
    } catch (e) {
      debugPrint('[MinhaConta] já paguei: $e');
      throw const MinhaContaException(
          'Não foi possível avisar. Verifica a ligação e tenta outra vez.');
    }
  }
}

class MinhaContaException implements Exception {
  const MinhaContaException(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}
