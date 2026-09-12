import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates server-side `RAISE EXCEPTION` messages from `admin_*` RPCs
/// into user-facing Portuguese strings. Shared by every admin screen that
/// calls those RPCs so error wording stays consistent.
///
/// Error vocabulary defined in:
///   - migration `20260428000003_admin_driver_rpcs.sql`
///   - plan         `2026-04-28-fase2A-bug1-plan.md` §3.4
String humanizeAdminRpcError(Object error) {
  if (error is PostgrestException) {
    final msg = error.message;
    if (msg.startsWith('admin_required')) {
      return 'Sem permissões de admin para esta acção.';
    }
    if (msg.startsWith('driver_not_found')) {
      return 'Entregador não encontrado. Refresca a lista.';
    }
    if (msg.startsWith('driver_already_approved')) {
      return 'Este entregador já estava aprovado.';
    }
    if (msg.startsWith('driver_already_rejected')) {
      return 'Este entregador já estava rejeitado.';
    }
    if (msg.startsWith('missing_docs:')) {
      final list = msg.substring('missing_docs:'.length).trim();
      return 'Documentos em falta: $list';
    }
    if (msg.startsWith('justification_required')) {
      return 'Tens de preencher a justificação (mínimo 3 caracteres).';
    }
    if (msg.startsWith('reason_required')) {
      return 'Tens de preencher o motivo (mínimo 3 caracteres).';
    }
    return 'Erro do servidor: $msg';
  }
  return 'Erro inesperado: $error';
}
