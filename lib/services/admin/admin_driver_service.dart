import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../prestador_suspensao_service.dart';

/// Thrown by [AdminDriverService] when an admin RPC / Edge Function fails.
/// Carries the canonical [code] (parsed from the server's `RAISE EXCEPTION`)
/// and a Portuguese [message] suitable for direct display in a toast/snackbar.
class AdminDriverException implements Exception {
  AdminDriverException({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AdminDriverException($code): $message';
}

/// Client wrapper around the FASE 3 BUG 2 admin endpoints.
///
/// Endpoints:
///   - `admin_ban_driver`            → [banDriver]
///   - `admin_reactivate_driver`     → [reactivateDriver]
///   - `admin_update_driver`         → [updateDriver]
///   - `admin_soft_delete_driver`    → [softDeleteDriver]
///   - `admin_driver_presence`       → [pedidosEmCurso]
///   - Edge Function `admin-force-driver-logout` → [forceLogout]
///
/// Every public method translates server-side errors into Portuguese and
/// throws [AdminDriverException]. Successful calls return the JSONB body
/// from the RPC as a `Map<String, dynamic>`.
class AdminDriverService {
  AdminDriverService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _msgSemConexao =
      'Sem conexão com o servidor. Verifique a internet e tente de novo.';

  // ── Os dois ids do entregador (painel 15/11/2026) ─────────────────────────
  //
  // Em 17 dos 22 entregadores `drivers.id` é diferente de `drivers.user_id`, e
  // esse drivers.id não é conta de login. Os pedidos guardam o entregador em
  // `assigned_driver_id` = user_id (os antigos, às vezes, com drivers.id); o
  // saldo e as transações usam `driver_id` = user_id. A ficha procura pelos
  // dois.

  /// Id da conta de login (auth.users.id): `user_id`; ficha antiga sem ele usa
  /// `drivers.id`.
  static String authIdDoEntregador(Map<String, dynamic> driver) =>
      (driver['user_id'] ?? driver['id']).toString();

  /// `[user_id, drivers.id]`, sem repetidos nem vazios.
  static List<String> idsDoEntregador(Map<String, dynamic> driver) {
    final ids = <String>[];
    for (final v in [driver['user_id'], driver['id']]) {
      final s = v?.toString().trim() ?? '';
      if (s.isNotEmpty && !ids.contains(s)) ids.add(s);
    }
    return ids;
  }

  /// Filtro `.or()` do histórico (`admin_audit_log`) pelos dois ids, nas duas
  /// colunas: `entity_id` (uuid) e `entity_id_text` (texto).
  static String filtroHistoricoDoEntregador(List<String> ids) {
    final lista = ids.join(',');
    return 'entity_id.in.($lista),entity_id_text.in.($lista)';
  }

  /// Linha de `driver_balances` a mostrar: a da conta de login (a que o app
  /// usa); sem ela, a da ficha. Só escolhe a linha — não soma nem faz contas.
  static Map<String, dynamic>? saldoDoEntregador(
    List<Map<String, dynamic>> linhas,
    String authId,
  ) {
    if (linhas.isEmpty) return null;
    for (final l in linhas) {
      if (l['driver_id']?.toString() == authId) return l;
    }
    return linhas.first;
  }

  /// `pedidos_em_curso` da resposta de `admin_driver_presence` (a RPC devolve
  /// uma tabela: lista de linhas). `null` = não deu para ler.
  static int? pedidosEmCursoDaPresenca(Object? resposta) {
    final linha = resposta is List
        ? (resposta.isEmpty ? null : resposta.first)
        : resposta;
    if (linha is! Map) return null;
    final v = linha['pedidos_em_curso'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  /// Mensagem que trava "Remover" quando há pedido em andamento; `null` =
  /// pode seguir.
  static String? bloqueioParaRemover(int pedidosEmCurso) => pedidosEmCurso > 0
      ? 'Este entregador tem $pedidosEmCurso pedido(s) em andamento. '
          'Passe esses pedidos para outro entregador antes de remover.'
      : null;

  /// `true` só quando o pedido nem chegou ao servidor (sem internet, nome do
  /// servidor que não resolve, ligação recusada). Uma resposta de erro do
  /// servidor NUNCA é falta de rede.
  static bool pareceSemRede(Object erro) {
    if (erro is FunctionException) return erro.status == 0;
    if (erro is PostgrestException) return false;
    return RegExp(
      r'SocketException|ClientException|Failed host lookup|Failed to fetch|'
      r'XMLHttpRequest error|Network is unreachable|'
      r'Connection (closed|refused|reset|failed)',
      caseSensitive: false,
    ).hasMatch(erro.toString());
  }

  /// Erro de "Forçar logout" em português (painel 15/11/2026). Antes, tudo o
  /// que falhava — até "sem permissão" ou a função não instalada — aparecia
  /// como falha de rede.
  static AdminDriverException erroAoForcarLogout(Object erro) {
    if (erro is AdminDriverException) return erro;
    if (erro is FunctionException && erro.status != 0) {
      final d = erro.details;
      final codigo = d is Map ? (d['error'] ?? d['code'])?.toString() : null;
      if (erro.status == 401 || erro.status == 403) {
        return AdminDriverException(
          code: 'admin_required',
          message: 'Sem permissão de admin para forçar logout. Se a sessão do '
              'painel expirou, entre de novo.',
          cause: erro,
        );
      }
      if (erro.status == 404) {
        if (codigo == 'driver_not_found') {
          return AdminDriverException(
            code: 'driver_not_found',
            message: 'Entregador não encontrado. Atualize a lista.',
            cause: erro,
          );
        }
        return AdminDriverException(
          code: 'function_not_installed',
          message: 'A função de forçar logout não está instalada no servidor. '
              'Nada foi feito.',
          cause: erro,
        );
      }
      final c = codigo ?? 'http_${erro.status}';
      return AdminDriverException(
        code: c,
        message: _humanizeForceLogoutError(c, erro.status),
        cause: erro,
      );
    }
    if (pareceSemRede(erro)) {
      return AdminDriverException(
          code: 'network', message: _msgSemConexao, cause: erro);
    }
    return AdminDriverException(
      code: 'unexpected',
      message: 'Erro inesperado ao forçar logout: $erro',
      cause: erro,
    );
  }

  /// As 10 chaves de `admin_update_driver`, SEMPRE todas (null = não mudar).
  /// O servidor tem duas versões da função (8 e 10 parâmetros): com só 8
  /// chaves o PostgREST não sabe qual usar (PGRST203); com as 10 só a nova
  /// serve.
  static Map<String, dynamic> paramsAtualizarEntregador({
    required String driverId,
    required String reason,
    String? name,
    String? phone,
    String? vehicleType,
    String? licensePlate,
    String? iban,
    String? nif,
    String? vehicleColor,
    String? vehicleMakeModel,
  }) =>
      <String, dynamic>{
        'p_driver_id': driverId,
        'p_reason': reason,
        'p_name': name,
        'p_phone': phone,
        'p_vehicle_type': vehicleType,
        'p_license_plate': licensePlate,
        'p_iban': iban,
        'p_nif': nif,
        'p_vehicle_color': vehicleColor,
        'p_vehicle_make_model': vehicleMakeModel,
      };

  // ── Public API ────────────────────────────────────────────────────────────

  /// Bans a driver. [bannedUntil] NULL = permanent; future timestamp =
  /// temporary suspension (auto-expires via `driver_effective_status`).
  Future<Map<String, dynamic>> banDriver({
    required String driverId,
    required String reasonCode, // ban_reason_code: fraud / misconduct / documents_invalid / inactivity / safety / other
    required String reason,
    DateTime? bannedUntil,
  }) async {
    return _callRpc('admin_ban_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_reason_code': reasonCode,
      'p_reason': reason,
      'p_banned_until': bannedUntil?.toUtc().toIso8601String(),
    });
  }

  /// Clears ban / suspension / soft-delete state in one call.
  Future<Map<String, dynamic>> reactivateDriver({
    required String driverId,
    String? note,
  }) async {
    return _callRpc('admin_reactivate_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_note': note,
    });
  }

  /// Whitelisted typed update. NULL parameter = no change.
  /// IBAN and NIF are flagged sensitive in the audit log (values redacted).
  /// Sends all 10 keys ([paramsAtualizarEntregador]).
  Future<Map<String, dynamic>> updateDriver({
    required String driverId,
    required String reason,
    String? name,
    String? phone,
    String? vehicleType, // 'motorcycle' | 'car' | 'bicycle' | 'carro_passageiros'
    String? licensePlate,
    String? iban,
    String? nif,
    String? vehicleColor, // TVDE — cor do carro (cartão do passageiro)
    String? vehicleMakeModel, // TVDE — marca/modelo
  }) async {
    return _callRpc(
      'admin_update_driver',
      paramsAtualizarEntregador(
        driverId: driverId,
        reason: reason,
        name: name,
        phone: phone,
        vehicleType: vehicleType,
        licensePlate: licensePlate,
        iban: iban,
        nif: nif,
        vehicleColor: vehicleColor,
        vehicleMakeModel: vehicleMakeModel,
      ),
    );
  }

  /// Soft-delete with three guards (active orders / non-zero balance /
  /// pending settlements). Throws with a user-readable message if any guard
  /// fails — message contains the offending count or amount.
  ///
  /// The server guards look only at `drivers.id`; the panel checks the orders
  /// in progress first with [pedidosEmCurso] (user_id).
  Future<Map<String, dynamic>> softDeleteDriver({
    required String driverId,
    required String reason,
  }) async {
    return _callRpc('admin_soft_delete_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_reason': reason,
    });
  }

  /// Pedidos em andamento do entregador, pela RPC `admin_driver_presence`
  /// (conta pela conta de login, [authIdDoEntregador]). Erros do servidor e de
  /// rede sobem tal e qual, para o painel os traduzir.
  Future<int> pedidosEmCurso({required String driverAuthId}) async {
    final r = await _client
        .rpc('admin_driver_presence', params: {'p_driver': driverAuthId});
    final n = pedidosEmCursoDaPresenca(r);
    if (n == null) {
      throw AdminDriverException(
        code: 'presence_unreadable',
        message: 'Não foi possível conferir os pedidos em andamento deste '
            'entregador. Tente de novo.',
      );
    }
    return n;
  }

  /// Asks the Edge Function `admin-force-driver-logout` to revoke the
  /// driver's sessions, clear `fcm_token`, set `is_online=false`, stamp
  /// `last_forced_logout_*` and write the audit row.
  ///
  /// Today (15/11/2026) the session revoke fails on the server
  /// (`sessions_revoked=false`): the phone may stay signed in until the driver
  /// leaves the app, and `driver_push_tokens` stay active (server fix
  /// proposed). [driverId] is `drivers.id`.
  Future<Map<String, dynamic>> forceLogout({
    required String driverId,
    required String reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-force-driver-logout',
        body: <String, dynamic>{
          'driver_id': driverId,
          'reason': reason,
        },
      );

      final body = response.data;
      if (body is! Map) {
        throw AdminDriverException(
          code: 'invalid_response',
          message: 'Resposta inesperada do servidor ao forçar logout.',
        );
      }
      final mapa = Map<String, dynamic>.from(body);
      // Edge Function returns {error:'…'} with non-2xx OR {success:true,…}.
      if (response.status >= 400 || mapa['error'] != null) {
        final code = (mapa['error'] ?? 'http_${response.status}').toString();
        throw AdminDriverException(
          code: code,
          message: _humanizeForceLogoutError(code, response.status),
        );
      }
      return mapa;
    } on AdminDriverException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminDriverService] forceLogout failed: $e');
      throw erroAoForcarLogout(e);
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _callRpc(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _client.rpc(fn, params: params);
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      throw AdminDriverException(
        code: 'invalid_response',
        message: 'Resposta inesperada do servidor ($fn).',
      );
    } on AdminDriverException {
      rethrow;
    } on PostgrestException catch (e) {
      final parsed = _parsePgError(e.message);
      throw AdminDriverException(
        code: parsed.code,
        message: parsed.message,
        cause: e,
      );
    } catch (e) {
      debugPrint('[AdminDriverService] $fn failed: $e');
      throw pareceSemRede(e)
          ? AdminDriverException(code: 'network', message: _msgSemConexao, cause: e)
          : AdminDriverException(
              code: 'unexpected',
              message: 'Erro inesperado ($fn): $e',
              cause: e,
            );
    }
  }

  /// Parses a `RAISE EXCEPTION` message and returns the canonical code +
  /// Portuguese message. Falls through to a generic server-error message.
  _ParsedError _parsePgError(String raw) {
    final msg = raw.trim();

    // ── Hard guards (admin_soft_delete_driver) ──────────────────────────────
    // These come VERBATIM from the server (already user-readable English with
    // numbers); we translate to PT.
    final activeOrders = RegExp(r'^Cannot delete: driver has (\d+) active order')
        .firstMatch(msg);
    if (activeOrders != null) {
      final n = activeOrders.group(1);
      return _ParsedError(
        'driver_has_active_orders',
        'Não é possível remover: este entregador tem $n pedido(s) em '
        'andamento. Espere terminar ou passe para outro entregador.',
      );
    }
    final balance = RegExp(r'^Cannot delete: driver has non-zero balance of EUR (\S+)')
        .firstMatch(msg);
    if (balance != null) {
      return _ParsedError(
        'driver_balance_not_zero',
        'Não é possível remover: o entregador tem saldo de €${balance.group(1)} '
        'a acertar.',
      );
    }
    final pending = RegExp(r'^Cannot delete: driver has (\d+) pending cash settlement')
        .firstMatch(msg);
    if (pending != null) {
      return _ParsedError(
        'driver_pending_settlements',
        'Não é possível remover: há ${pending.group(1)} acerto(s) pendente(s) '
        'deste entregador.',
      );
    }

    // ── Codes prefixed `code: detail` ──────────────────────────────────────
    if (msg.startsWith('admin_required')) {
      return const _ParsedError('admin_required',
          'Sem permissão de admin para esta ação.');
    }
    if (msg.startsWith('driver_not_found')) {
      return const _ParsedError('driver_not_found',
          'Entregador não encontrado. Atualize a lista.');
    }
    if (msg.startsWith('driver_already_banned')) {
      return const _ParsedError('driver_already_banned',
          'Este entregador já está banido. Reative primeiro para alterar.');
    }
    if (msg.startsWith('driver_already_active')) {
      return const _ParsedError('driver_already_active',
          'Este entregador já está ativo: não há banimento nem remoção para desfazer.');
    }
    if (msg.startsWith('driver_already_deleted')) {
      return const _ParsedError('driver_already_deleted',
          'Este entregador já foi removido. Reative se precisar.');
    }
    if (msg.startsWith('driver_deleted')) {
      return const _ParsedError('driver_deleted',
          'Entregador removido. Reative primeiro para fazer isso.');
    }
    if (msg.startsWith('reason_required')) {
      return const _ParsedError('reason_required',
          'Preencha o motivo (mínimo 3 caracteres).');
    }
    if (msg.startsWith('reason_code_required')) {
      return const _ParsedError('reason_code_required',
          'Escolha a categoria do banimento.');
    }
    if (msg.startsWith('banned_until_in_past')) {
      return const _ParsedError('banned_until_in_past',
          'A data de fim da suspensão precisa ser no futuro.');
    }
    if (msg.startsWith('invalid_vehicle_type')) {
      return const _ParsedError('invalid_vehicle_type',
          'Tipo de veículo inválido. Permitidos: moto, carro, bicicleta, '
          'carro de passageiros (TVDE).');
    }
    if (msg.startsWith('no_changes')) {
      return const _ParsedError('no_changes',
          'Nada para alterar: todos os valores são iguais aos atuais.');
    }
    if (msg.startsWith('justification_required')) {
      return const _ParsedError('justification_required',
          'Preencha a justificativa (mínimo 3 caracteres).');
    }
    if (msg.startsWith('missing_docs:')) {
      return _ParsedError('missing_docs',
          'Faltam documentos: ${msg.substring("missing_docs:".length).trim()}');
    }
    // [01/11/2026 · B8] Gatilho `fn_suspensao_so_com_humano` (Diretiva
    // 2024/2831): banir/suspender/remover exige motivo com 10 letras.
    if (msg.contains('SUSPENSAO_')) {
      final t = traduzirErroSuspensaoOuNull(msg);
      if (t != null) return _ParsedError('suspensao_recusada', t);
    }
    return _ParsedError('server_error', 'Erro do servidor: $msg');
  }

  static String _humanizeForceLogoutError(String code, int status) {
    switch (code) {
      case 'missing_token':
      case 'unauthorized':
        return 'A sessão do painel expirou. Entre de novo.';
      case 'admin_required':
        return 'Sem permissão de admin para forçar logout.';
      case 'invalid_driver_id':
      case 'invalid_body':
        return 'Pedido inválido. Atualize a lista e tente de novo.';
      case 'driver_not_found':
        return 'Entregador não encontrado. Atualize a lista.';
      case 'method_not_allowed':
        return 'Erro interno do painel (método HTTP inválido).';
      case 'lookup_failed':
      case 'update_failed':
      case 'server_misconfigured':
        return 'Erro do servidor ao forçar logout. Tente de novo em alguns segundos.';
      default:
        return 'Não foi possível forçar logout (HTTP $status, $code).';
    }
  }
}

class _ParsedError {
  const _ParsedError(this.code, this.message);
  final String code;
  final String message;
}
