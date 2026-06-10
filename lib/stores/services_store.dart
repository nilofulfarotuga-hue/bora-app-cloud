import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// `flutter_stripe` exporta `Card` que colide com Material `Card`.
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment_model.dart';
import '../models/provider_service_model.dart';
import '../models/service_provider_model.dart';
import '../models/staff_member_model.dart';

/// Resultado do fluxo `bookAndPay` — informa o ecrã de sucesso/erro.
class BookingResult {
  BookingResult({
    required this.success,
    this.appointmentId,
    this.cancelled = false,
    this.errorMessage,
  });

  final bool success;
  final String? appointmentId;
  final bool cancelled; // utilizador fechou o Payment Sheet
  final String? errorMessage;
}

/// Store cliente para a vertical Serviços (barbearias / marcações).
///
/// Espelha o padrão de [ReservationStore]:
/// - Tabelas: service_providers, provider_services, staff_members, appointments
/// - RPCs: get_available_slots, client_book_appointment,
///   client_confirm_appointment_payment, client_cancel_appointment
/// - Edge Fn: create-appointment-payment-intent
class ServicesStore extends ChangeNotifier {
  ServicesStore({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  List<ServiceProviderModel> _providers = const [];
  bool _loadingProviders = false;
  String? _providersError;

  List<AppointmentModel> _myAppointments = const [];
  bool _loadingAppointments = false;
  String? _appointmentsError;

  // Realtime das marcações do user (.stream() não suporta JOIN — cache).
  StreamSubscription? _myAppointmentsSub;
  bool _subscribed = false;
  final Map<String, AppointmentModel> _joinInfoCache =
      <String, AppointmentModel>{};

  // ─── Getters ───────────────────────────────────────────────────────────────

  List<ServiceProviderModel> get providers => _providers;
  bool get loadingProviders => _loadingProviders;
  String? get providersError => _providersError;

  List<AppointmentModel> get myAppointments => _myAppointments;
  bool get loadingAppointments => _loadingAppointments;
  String? get appointmentsError => _appointmentsError;

  List<AppointmentModel> get upcomingAppointments =>
      _myAppointments.where((a) => a.isUpcoming).toList();

  List<AppointmentModel> get pastAppointments =>
      _myAppointments.where((a) => a.isPast && !a.isCancelled).toList();

  List<AppointmentModel> get cancelledAppointments =>
      _myAppointments.where((a) => a.isCancelled).toList();

  // ─── Prestadores ─────────────────────────────────────────────────────────

  /// Lista prestadores aprovados + online (RLS filtra server-side, mas
  /// reforçamos os filtros para clareza/robustez).
  Future<void> fetchProviders() async {
    _loadingProviders = true;
    _providersError = null;
    notifyListeners();
    try {
      final response = await _supabase
          .from('service_providers')
          .select()
          .eq('is_online', true)
          .eq('approval_status', 'approved')
          .order('avg_rating', ascending: false)
          .limit(100);
      final rows = response as List;
      final parsed = <ServiceProviderModel>[];
      for (final r in rows) {
        try {
          parsed.add(ServiceProviderModel.fromSupabase(
            Map<String, dynamic>.from(r as Map),
          ));
        } catch (e) {
          // Uma linha malformada NUNCA deve esvaziar a lista inteira.
          debugPrint('[SERVICOS] linha ignorada (parse): $e');
        }
      }
      _providers = parsed;
      debugPrint(
          '[SERVICOS] fetchProviders raw=${rows.length} parsed=${parsed.length}');
    } on PostgrestException catch (e) {
      _providersError = _mapErrorPtPt(e.code ?? e.message);
      debugPrint('[ServicesStore] fetchProviders Postgrest: ${e.code} ${e.message}');
    } catch (e) {
      _providersError = 'Não foi possível carregar os serviços. Tenta de novo.';
      debugPrint('[ServicesStore] fetchProviders error: $e');
    } finally {
      _loadingProviders = false;
      notifyListeners();
    }
  }

  /// Lê o detalhe de um prestador específico.
  Future<ServiceProviderModel?> fetchProviderDetail(String id) async {
    try {
      final row = await _supabase
          .from('service_providers')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return ServiceProviderModel.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('[ServicesStore] fetchProviderDetail $id: $e');
      throw Exception('Não foi possível carregar o prestador.');
    }
  }

  /// Lista serviços activos de um prestador.
  Future<List<ProviderServiceModel>> fetchServices(String providerId) async {
    try {
      final res = await _supabase
          .from('provider_services')
          .select()
          .eq('provider_id', providerId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (res as List)
          .map((r) => ProviderServiceModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[ServicesStore] fetchServices $providerId: $e');
      throw Exception('Não foi possível carregar os serviços.');
    }
  }

  /// Lista colaboradores activos de um prestador.
  Future<List<StaffMemberModel>> fetchStaff(String providerId) async {
    try {
      final res = await _supabase
          .from('staff_members')
          .select()
          .eq('provider_id', providerId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (res as List)
          .map((r) => StaffMemberModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[ServicesStore] fetchStaff $providerId: $e');
      throw Exception('Não foi possível carregar a equipa.');
    }
  }

  /// Slots disponíveis para um colaborador/serviço numa data (RPC).
  /// Devolve a lista de DateTime (locais) dos inícios de slot disponíveis.
  Future<List<DateTime>> getAvailableSlots({
    required String staffId,
    required String serviceId,
    required DateTime day,
  }) async {
    try {
      final result = await _supabase.rpc('get_available_slots', params: {
        'p_staff_id': staffId,
        'p_service_id': serviceId,
        'p_date': _formatDate(day),
      });
      if (result is! List) return const [];
      final out = <DateTime>[];
      for (final item in result) {
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
    } on PostgrestException catch (e) {
      debugPrint('[ServicesStore] getAvailableSlots Postgrest: ${e.code} ${e.message}');
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      debugPrint('[ServicesStore] getAvailableSlots error: $e');
      throw Exception('Erro ao procurar horários. Tenta de novo.');
    }
  }

  // ─── Marcar + pagar (orquestra os 4 passos) ────────────────────────────────

  /// Fluxo MBWay do sinal (M7 — paridade com reservas, sem PaymentSheet):
  /// 1) rpc client_book_appointment → appointment_id
  /// 2) invoke create-mbway-appointment-payment-intent {appointment_id, phone}
  ///    → Stripe envia push à app MBWay do cliente.
  /// A confirmação é feita pelo AppointmentMBWayWaitingDialog (polling à Edge
  /// confirm-mbway-appointment-payment, que verifica o PI no Stripe).
  Future<BookingResult> bookMbway({
    required String serviceId,
    required String staffId,
    required DateTime scheduledAt,
    required String mbwayPhone,
    String? notes,
  }) async {
    try {
      final booking = await _supabase.rpc('client_book_appointment', params: {
        'p_service_id': serviceId,
        'p_staff_id': staffId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_client_notes': notes,
      });
      final bookingMap = Map<String, dynamic>.from(booking as Map);
      final appointmentId = bookingMap['appointment_id'] as String?;
      if (appointmentId == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      final response = await _supabase.functions.invoke(
        'create-mbway-appointment-payment-intent',
        body: {'appointment_id': appointmentId, 'phone': mbwayPhone},
      );
      if (response.data == null) {
        throw Exception('Resposta vazia do servidor.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data.containsKey('error')) {
        throw Exception(_mapErrorPtPt(data['error'].toString()));
      }

      await fetchMyAppointments();
      return BookingResult(success: true, appointmentId: appointmentId);
    } on PostgrestException catch (e) {
      debugPrint('[ServicesStore] bookMbway Postgrest: ${e.code} ${e.message}');
      return BookingResult(
        success: false,
        errorMessage: _mapErrorPtPt(e.code ?? e.message),
      );
    } catch (e) {
      debugPrint('[ServicesStore] bookMbway error: $e');
      return BookingResult(
        success: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Fluxo completo de marcação com pagamento por cartão (padrão Stripe
  /// canónico BORA APP — igual ao das reservas):
  /// 1) rpc client_book_appointment → appointment_id (+ deposit_cents)
  /// 2) invoke create-appointment-payment-intent → clientSecret
  /// 3) Stripe initPaymentSheet + presentPaymentSheet
  /// 4) rpc client_confirm_appointment_payment
  Future<BookingResult> bookAndPay({
    required String serviceId,
    required String staffId,
    required DateTime scheduledAt,
    String? notes,
    required BuildContext context,
  }) async {
    if (kIsWeb) {
      return BookingResult(
        success: false,
        errorMessage: 'Os pagamentos por cartão só estão disponíveis no telemóvel.',
      );
    }
    try {
      // 1) Criar marcação pending_payment.
      final booking = await _supabase.rpc('client_book_appointment', params: {
        'p_service_id': serviceId,
        'p_staff_id': staffId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_client_notes': notes,
      });
      final bookingMap = Map<String, dynamic>.from(booking as Map);
      final appointmentId = bookingMap['appointment_id'] as String?;
      if (appointmentId == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      // 2) Criar PaymentIntent do sinal.
      final response = await _supabase.functions.invoke(
        'create-appointment-payment-intent',
        body: {'appointment_id': appointmentId},
      );
      if (response.data == null) {
        throw Exception('Resposta vazia do servidor.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data.containsKey('error')) {
        throw Exception(_mapErrorPtPt(data['error'].toString()));
      }
      final clientSecret = data['clientSecret'] as String?;
      if (clientSecret == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      // 3) Payment Sheet — PADRÃO CANÓNICO BORA APP.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'BORA APP',
          style: ThemeMode.system,
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
            name: CollectionMode.always,
          ),
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'PT'),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'PT',
            currencyCode: 'EUR',
            testEnv: false,
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // 4) Confirmar pagamento (RPC fallback — webhook pode já ter confirmado).
      try {
        await _supabase.rpc('client_confirm_appointment_payment',
            params: {'p_appointment_id': appointmentId});
      } catch (_) {
        // Webhook já confirmou — não é erro para o utilizador.
      }

      // Refresh state local.
      await fetchMyAppointments();

      return BookingResult(success: true, appointmentId: appointmentId);
    } on StripeException catch (e) {
      final isCanceled = e.error.code == FailureCode.Canceled;
      debugPrint('[ServicesStore] bookAndPay Stripe: ${e.error.localizedMessage}');
      return BookingResult(
        success: false,
        cancelled: isCanceled,
        errorMessage:
            isCanceled ? 'Pagamento cancelado.' : 'Erro no pagamento. Tenta de novo.',
      );
    } on PostgrestException catch (e) {
      debugPrint('[ServicesStore] bookAndPay Postgrest: ${e.code} ${e.message}');
      return BookingResult(
        success: false,
        errorMessage: _mapErrorPtPt(e.code ?? e.message),
      );
    } catch (e) {
      debugPrint('[ServicesStore] bookAndPay error: $e');
      return BookingResult(
        success: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Cancela uma marcação (RPC). O reembolso (quando elegível) é tratado
  /// server-side — igual ao padrão das reservas (client_cancel_reservation),
  /// que NÃO dispara refund Stripe client-side. Devolve `will_refund`.
  Future<bool> cancelAppointment(String appointmentId, {String? reason}) async {
    try {
      final result = await _supabase.rpc('client_cancel_appointment', params: {
        'p_appointment_id': appointmentId,
        'p_reason': reason,
      });
      final map = Map<String, dynamic>.from(result as Map);
      await fetchMyAppointments();
      return (map['will_refund'] as bool?) ?? false;
    } on PostgrestException catch (e) {
      debugPrint('[ServicesStore] cancelAppointment Postgrest: ${e.code} ${e.message}');
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      debugPrint('[ServicesStore] cancelAppointment error: $e');
      throw Exception('Não foi possível cancelar a marcação. Tenta de novo.');
    }
  }

  // ─── Marcações do cliente ─────────────────────────────────────────────────

  /// Lê marcações do cliente (RLS filtra por client_user_id = auth.uid())
  /// com JOIN ao prestador/serviço/staff para mostrar nomes nos cards.
  Future<void> fetchMyAppointments() async {
    _loadingAppointments = true;
    _appointmentsError = null;
    notifyListeners();
    try {
      final response = await _supabase
          .from('appointments')
          .select(
            '*, service_providers(id, name, photo_url, hero_image_url), '
            'provider_services(id, name), staff_members(id, name)',
          )
          .order('scheduled_at', ascending: false)
          .limit(100);
      _myAppointments = (response as List).map((r) {
        final a = AppointmentModel.fromSupabase(Map<String, dynamic>.from(r as Map));
        if (a.providerName != null) _joinInfoCache[a.id] = a;
        return a;
      }).toList();
    } on PostgrestException catch (e) {
      _appointmentsError = _mapErrorPtPt(e.code ?? e.message);
      debugPrint('[ServicesStore] fetchMyAppointments Postgrest: ${e.code} ${e.message}');
    } catch (e) {
      _appointmentsError = 'Não foi possível carregar as marcações. Tenta de novo.';
      debugPrint('[ServicesStore] fetchMyAppointments error: $e');
    } finally {
      _loadingAppointments = false;
      notifyListeners();
    }
  }

  /// Subscreve mudanças em tempo real das marcações do user. Idempotente.
  /// .stream() não suporta JOIN — preserva nomes via cache por id (igual ao
  /// padrão do ReservationStore).
  void subscribeMyAppointments() {
    if (_subscribed) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    _subscribed = true;
    _myAppointmentsSub = _supabase
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('client_user_id', uid)
        .order('scheduled_at', ascending: false)
        .listen((rows) {
      final byId = {for (final a in _myAppointments) a.id: a};
      _myAppointments = rows.map((row) {
        final fresh =
            AppointmentModel.fromSupabase(Map<String, dynamic>.from(row));
        // .stream() não traz joins — recupera de cache ou do estado anterior.
        final cached = _joinInfoCache[fresh.id] ?? byId[fresh.id];
        if (cached != null && cached.providerName != null) {
          return fresh.copyWithJoinInfo(
            providerName: cached.providerName,
            providerPhotoUrl: cached.providerPhotoUrl,
            serviceName: cached.serviceName,
            staffName: cached.staffName,
          );
        }
        return fresh;
      }).toList();
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('[ServicesStore] realtime stream error: $e');
    });
  }

  void unsubscribeMyAppointments() {
    _myAppointmentsSub?.cancel();
    _myAppointmentsSub = null;
    _subscribed = false;
  }

  @override
  void dispose() {
    _myAppointmentsSub?.cancel();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _mapErrorPtPt(String code) {
    const mapping = <String, String>{
      'auth_required': 'Sessão expirada. Volta a entrar.',
      'provider_not_found': 'Prestador não encontrado.',
      'service_not_found': 'Serviço não encontrado.',
      'staff_not_found': 'Profissional não encontrado.',
      'slot_taken': 'Esse horário já foi reservado. Escolhe outro.',
      'slot_unavailable': 'Horário indisponível. Escolhe outro.',
      'date_in_past': 'Data inválida (no passado).',
      'date_too_far': 'Data muito distante. Tenta uma data mais próxima.',
      'appointment_not_found': 'Marcação não encontrada.',
      'not_your_appointment': 'Esta marcação não é tua.',
      'already_cancelled': 'Esta marcação já foi cancelada.',
      'cannot_cancel': 'Não é possível cancelar esta marcação.',
      'client_blocked': 'Não podes marcar neste prestador.',
    };
    if (mapping.containsKey(code)) return mapping[code]!;
    return 'Ocorreu um erro. Tenta de novo.';
  }
}
