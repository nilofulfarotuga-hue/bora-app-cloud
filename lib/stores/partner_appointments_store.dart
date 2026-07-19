import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment_model.dart';
import '../models/provider_service_model.dart';
import '../models/service_provider_model.dart';
import '../models/staff_member_model.dart';
import '../utils/staff_terminology.dart';

/// Store partner-side da vertical Serviços / Barbearias.
///
/// Espelha o padrão de [PartnerReservasStore]:
/// - O parceiro é dono do seu prestador via `service_providers.user_id =
///   auth.uid()`.
/// - RPCs: partner_complete_appointment, partner_mark_no_show,
///   partner_add_walk_in, partner_block_slot, get_available_slots,
///   compute_provider_weekly_payout.
/// - CRUD direto (RLS partner owner) em provider_services, staff_members,
///   staff_availability (sem RPC; UPDATE is_active=false = soft delete).
class PartnerAppointmentsStore extends ChangeNotifier {
  PartnerAppointmentsStore({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  ServiceProviderModel? _provider;
  ServiceProviderModel? get provider => _provider;

  String? get providerId => _provider?.id;

  // ───────────── PROVIDER ─────────────

  /// Carrega o prestador do parceiro autenticado. Idempotente — devolve o
  /// cache se já tiver sido carregado.
  Future<ServiceProviderModel?> loadMyProvider({bool force = false}) async {
    if (_provider != null && !force) return _provider;
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) throw Exception('auth_required');
      final row = await _supabase
          .from('service_providers')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) {
        _provider = null;
        notifyListeners();
        return null;
      }
      _provider = ServiceProviderModel.fromSupabase(
        Map<String, dynamic>.from(row),
      );
      notifyListeners();
      return _provider;
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] loadMyProvider: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  // ───────────── AGENDA ─────────────

  /// Marcações de um intervalo. `day` (vista Hoje) ou `from`/`to` (vista
  /// Semana). JOIN ao serviço/staff para mostrar nomes nos cards.
  Future<List<AppointmentModel>> fetchAgenda({
    DateTime? day,
    DateTime? from,
    DateTime? to,
  }) async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    DateTime start;
    DateTime end;
    if (from != null && to != null) {
      start = DateTime(from.year, from.month, from.day);
      end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    } else {
      final d = day ?? DateTime.now();
      start = DateTime(d.year, d.month, d.day);
      end = start.add(const Duration(days: 1));
    }
    try {
      final res = await _supabase
          .from('appointments')
          .select(
            '*, provider_services(id, name), staff_members(id, name)',
          )
          .eq('provider_id', pid)
          .gte('scheduled_at', start.toUtc().toIso8601String())
          .lt('scheduled_at', end.toUtc().toIso8601String())
          .order('scheduled_at', ascending: true);
      return (res as List)
          .map((r) => AppointmentModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchAgenda: $e');
      throw Exception('Não foi possível carregar a agenda.');
    }
  }

  /// Conclui a marcação. `method` ∈ 'on_site' (pago na loja) | 'app'.
  Future<Map<String, dynamic>> completeAppointment(
    String appointmentId,
    String method,
  ) async {
    try {
      final res = await _supabase.rpc(
        'partner_complete_appointment',
        params: {
          'p_appointment_id': appointmentId,
          'p_payment_method': method,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] complete: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  Future<Map<String, dynamic>> markNoShow(String appointmentId) async {
    try {
      final res = await _supabase.rpc(
        'partner_mark_no_show',
        params: {'p_appointment_id': appointmentId},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] noShow: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// M8: cancelamento pelo parceiro. Devolve {success, refund_due} — quando
  /// refund_due, o cliente foi avisado do reembolso e o admin alertado.
  Future<Map<String, dynamic>> partnerCancelAppointment(
    String appointmentId, {
    String? reason,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_cancel_appointment',
        params: {
          'p_appointment_id': appointmentId,
          'p_reason': reason,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] partnerCancel: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// Marcação sem reserva prévia (host stand). Devolve {appointment_id}.
  Future<Map<String, dynamic>> addWalkIn({
    required String serviceId,
    required String staffId,
    required DateTime scheduledAt,
    required String clientName,
  }) async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      final res = await _supabase.rpc(
        'partner_add_walk_in',
        params: {
          'p_provider_id': pid,
          'p_service_id': serviceId,
          'p_staff_id': staffId,
          'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'p_client_name': clientName,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] addWalkIn: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// Bloqueia um intervalo de um profissional (pausa, folga). Devolve
  /// {appointment_id}.
  Future<Map<String, dynamic>> blockSlot({
    required String staffId,
    required DateTime startAt,
    required DateTime endAt,
    String? reason,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_block_slot',
        params: {
          'p_staff_id': staffId,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
          if (reason != null) 'p_reason': reason,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] blockSlot: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// Slots disponíveis (útil no walk-in). Devolve DateTime locais.
  Future<List<DateTime>> availableSlots({
    required String staffId,
    required String serviceId,
    required DateTime day,
  }) async {
    try {
      final res = await _supabase.rpc('get_available_slots', params: {
        'p_staff_id': staffId,
        'p_service_id': serviceId,
        'p_date': _formatDate(day),
      });
      if (res is! List) return const [];
      final out = <DateTime>[];
      for (final item in res) {
        if (item is Map) {
          final v = item['slot_start'];
          if (v is String) {
            final dt = DateTime.tryParse(v);
            if (dt != null) out.add(dt.toLocal());
          }
        }
      }
      out.sort();
      return out;
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] availableSlots: $e');
      throw Exception('Não foi possível procurar horários.');
    }
  }

  // ───────────── SERVIÇOS (CRUD direto) ─────────────

  Future<List<ProviderServiceModel>> fetchServices() async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      final res = await _supabase
          .from('provider_services')
          .select()
          .eq('provider_id', pid)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (res as List)
          .map((r) => ProviderServiceModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchServices: $e');
      throw Exception('Não foi possível carregar os serviços.');
    }
  }

  Future<void> createService({
    required String name,
    String? description,
    required int durationMinutes,
    required int priceCents,
  }) async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      await _supabase.from('provider_services').insert({
        'provider_id': pid,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'duration_minutes': durationMinutes,
        'price_cents': priceCents,
        'is_active': true,
      });
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] createService: $e');
      throw Exception('Não foi possível criar o serviço.');
    }
  }

  Future<void> updateService({
    required String serviceId,
    String? name,
    String? description,
    int? durationMinutes,
    int? priceCents,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (name != null) update['name'] = name;
      if (description != null) update['description'] = description;
      if (durationMinutes != null) update['duration_minutes'] = durationMinutes;
      if (priceCents != null) update['price_cents'] = priceCents;
      if (update.isEmpty) return;
      await _supabase
          .from('provider_services')
          .update(update)
          .eq('id', serviceId);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] updateService: $e');
      throw Exception('Não foi possível actualizar o serviço.');
    }
  }

  /// Soft delete via is_active=false (mantém histórico de marcações).
  Future<void> deactivateService(String serviceId) async {
    try {
      await _supabase
          .from('provider_services')
          .update({'is_active': false}).eq('id', serviceId);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] deactivateService: $e');
      throw Exception('Não foi possível desactivar o serviço.');
    }
  }

  // ───────────── BARBEIROS (CRUD direto) ─────────────

  Future<List<StaffMemberModel>> fetchStaff() async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      final res = await _supabase
          .from('staff_members')
          .select()
          .eq('provider_id', pid)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (res as List)
          .map((r) => StaffMemberModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchStaff: $e');
      throw Exception('Não foi possível carregar a equipa.');
    }
  }

  Future<void> createStaff({
    required String name,
    String? bio,
    String? photoUrl,
    List<String> specialties = const [],
  }) async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      await _supabase.from('staff_members').insert({
        'provider_id': pid,
        'name': name,
        if (bio != null && bio.isNotEmpty) 'bio': bio,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
        'specialties': specialties,
        'is_active': true,
      });
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] createStaff: $e');
      throw Exception(
        'Não foi possível criar o '
        '${StaffTerminology.singular(_provider?.category).toLowerCase()}.',
      );
    }
  }

  Future<void> updateStaff({
    required String staffId,
    String? name,
    String? bio,
    String? photoUrl,
    List<String>? specialties,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (name != null) update['name'] = name;
      if (bio != null) update['bio'] = bio;
      if (photoUrl != null) update['photo_url'] = photoUrl;
      if (specialties != null) update['specialties'] = specialties;
      if (update.isEmpty) return;
      await _supabase.from('staff_members').update(update).eq('id', staffId);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] updateStaff: $e');
      throw Exception(
        'Não foi possível actualizar o '
        '${StaffTerminology.singular(_provider?.category).toLowerCase()}.',
      );
    }
  }

  Future<void> deactivateStaff(String staffId) async {
    try {
      await _supabase
          .from('staff_members')
          .update({'is_active': false}).eq('id', staffId);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] deactivateStaff: $e');
      throw Exception(
        'Não foi possível desactivar o '
        '${StaffTerminology.singular(_provider?.category).toLowerCase()}.',
      );
    }
  }

  // ───────────── DISPONIBILIDADE SEMANAL (CRUD direto) ─────────────

  /// Linhas de `staff_availability` de um profissional. day_of_week: 0=Dom..6=Sáb.
  Future<List<Map<String, dynamic>>> fetchStaffAvailability(
    String staffId,
  ) async {
    try {
      final res = await _supabase
          .from('staff_availability')
          .select()
          .eq('staff_id', staffId)
          .order('day_of_week', ascending: true);
      return (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchStaffAvailability: $e');
      throw Exception('Não foi possível carregar a disponibilidade.');
    }
  }

  /// Define a disponibilidade de um dia. Apaga a linha existente do dia e
  /// insere a nova (upsert simples — não há constraint conhecida para
  /// onConflict). `startTime`/`endTime` no formato 'HH:mm'.
  Future<void> upsertAvailability({
    required String staffId,
    required int dayOfWeek,
    required bool isWorking,
    String? startTime,
    String? endTime,
  }) async {
    try {
      await _supabase
          .from('staff_availability')
          .delete()
          .eq('staff_id', staffId)
          .eq('day_of_week', dayOfWeek);
      await _supabase.from('staff_availability').insert({
        'staff_id': staffId,
        'day_of_week': dayOfWeek,
        'is_working': isWorking,
        'start_time': isWorking ? (startTime ?? '09:00') : null,
        'end_time': isWorking ? (endTime ?? '18:00') : null,
      });
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] upsertAvailability: $e');
      throw Exception('Não foi possível guardar a disponibilidade.');
    }
  }

  // ───────────── EXCEÇÕES DE DISPONIBILIDADE (calendário mensal) ─────────────
  // Datas específicas que fogem ao padrão semanal (folgas, feriados, horário
  // diferente). O padrão semanal (staff_availability) continua a ser o modelo
  // base; get_available_slots dá prioridade à exceção quando existe.

  /// Exceções de um profissional dentro do mês de `month`.
  Future<List<Map<String, dynamic>>> fetchAvailabilityExceptions({
    required String staffId,
    required DateTime month,
  }) async {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    try {
      final res = await _supabase
          .from('staff_availability_exceptions')
          .select()
          .eq('staff_id', staffId)
          .gte('date', _formatDate(first))
          .lte('date', _formatDate(last))
          .order('date', ascending: true);
      return (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchAvailabilityExceptions: $e');
      throw Exception('Não foi possível carregar as exceções do calendário.');
    }
  }

  /// Cria/actualiza a exceção de UMA data (upsert on_conflict staff_id,date).
  /// `startTime`/`endTime` em 'HH:mm' — só relevantes quando isWorking=true.
  Future<void> upsertAvailabilityException({
    required String staffId,
    required DateTime date,
    required bool isWorking,
    String? startTime,
    String? endTime,
    String? note,
  }) async {
    try {
      await _supabase.from('staff_availability_exceptions').upsert({
        'staff_id': staffId,
        'date': _formatDate(date),
        'is_working': isWorking,
        'start_time': isWorking ? (startTime ?? '09:00') : null,
        'end_time': isWorking ? (endTime ?? '18:00') : null,
        if (note != null) 'note': note,
      }, onConflict: 'staff_id,date');
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] upsertAvailabilityException: $e');
      throw Exception('Não foi possível guardar a exceção do dia.');
    }
  }

  /// Remove a exceção de uma data → o dia volta a seguir o padrão semanal.
  Future<void> deleteAvailabilityException({
    required String staffId,
    required DateTime date,
  }) async {
    try {
      await _supabase
          .from('staff_availability_exceptions')
          .delete()
          .eq('staff_id', staffId)
          .eq('date', _formatDate(date));
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] deleteAvailabilityException: $e');
      throw Exception('Não foi possível remover a exceção do dia.');
    }
  }

  // ───────────── FINANCEIRO ─────────────

  /// Histórico de liquidações (appointment_payouts) do prestador.
  Future<List<Map<String, dynamic>>> fetchPayouts() async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      final res = await _supabase
          .from('appointment_payouts')
          .select()
          .eq('provider_id', pid)
          .order('week_start_at', ascending: false)
          .limit(52);
      return (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] fetchPayouts: $e');
      throw Exception('Não foi possível carregar as liquidações.');
    }
  }

  /// Pré-visualização da semana actual (p_persist=false → não grava).
  /// Devolve {net_payout_cents, bora_revenue_cents, total_appointments}.
  Future<Map<String, dynamic>> weeklyPreview() async {
    final pid = _provider?.id;
    if (pid == null) throw Exception('Carrega primeiro o teu negócio.');
    try {
      final res = await _supabase.rpc(
        'compute_provider_weekly_payout',
        params: {
          'p_provider_id': pid,
          'p_week_start': _weekStart().toIso8601String(),
          'p_persist': false,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerAppointmentsStore] weeklyPreview: $e');
      throw Exception('Não foi possível calcular o resumo da semana.');
    }
  }

  // ───────────── HELPERS ─────────────

  DateTime _weekStart() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day - (now.weekday - 1));
  }

  String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _mapErrorPtPt(String error) {
    final e = error.toLowerCase();
    if (e.contains('auth_required')) return 'Sessão expirada. Volta a entrar.';
    if (e.contains('provider_not_found')) return 'Negócio não encontrado.';
    if (e.contains('not_provider_owner') || e.contains('not_your_provider')) {
      return 'Não tens acesso a este negócio.';
    }
    if (e.contains('appointment_not_found')) {
      return 'Marcação não encontrada.';
    }
    if (e.contains('not_your_appointment')) {
      return 'Esta marcação não é tua.';
    }
    if (e.contains('already_completed')) return 'Marcação já concluída.';
    if (e.contains('already_no_show')) return 'Falta já registada.';
    if (e.contains('already_cancelled')) return 'Marcação já cancelada.';
    if (e.contains('cannot_complete')) {
      return 'Não é possível concluir neste estado.';
    }
    if (e.contains('invalid_payment_method')) {
      return 'Método de pagamento inválido.';
    }
    if (e.contains('service_not_found')) return 'Serviço não encontrado.';
    if (e.contains('staff_not_found')) {
      return '${StaffTerminology.singular(_provider?.category)} não encontrado.';
    }
    if (e.contains('slot_taken') || e.contains('slot_unavailable')) {
      return 'Horário indisponível. Escolhe outro.';
    }
    if (e.contains('invalid_interval') || e.contains('end_before_start')) {
      return 'Intervalo inválido.';
    }
    return 'Erro: ${error.replaceFirst('Exception: ', '')}';
  }
}
