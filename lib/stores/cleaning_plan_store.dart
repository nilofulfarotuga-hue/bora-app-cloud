import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/cleaning_plan_models.dart';
import '../models/falha_de_acao.dart';

/// PLANOS DE LIMPEZA (casas e Bora Empresas) — missão limpeza-planos-empresas-2026-11-28.
///
/// Camada fina: o preço, as datas, as cobranças e as devoluções decidem-se SEMPRE no servidor
/// (cleaning_plan_quote, cleaning_plan_create, cleaning_plan_*; Edge cleaning-plan para o
/// cartão). Aqui só se pede, guarda o que voltou e avisa o ecrã.
class CleaningPlanStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;

  List<CleaningPlan> _plans = const [];
  List<CleaningPlan> get plans => _plans;

  /// O plano aberto mais recente (ativo, em pausa ou à espera do cartão).
  CleaningPlan? get current {
    for (final p in _plans) {
      if (p.isOpen) return p;
    }
    return null;
  }

  bool _loading = false;
  bool get loading => _loading;

  String? _erro;
  String? get erro => _erro;

  /// Lê os planos do cliente (cleaning_plan_mine).
  Future<void> loadMine() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _sb.rpc('cleaning_plan_mine').timeout(kAcaoTimeout);
      _plans = [
        for (final p in (res as List? ?? const []))
          if (p is Map) CleaningPlan.fromJson(Map<String, dynamic>.from(p)),
      ];
      _erro = null;
    } catch (e) {
      debugPrint('CleaningPlanStore.loadMine error => $e');
      _erro = mensagem(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Preço do plano, calculado no servidor.
  Future<CleaningPlanQuote?> quote({
    required String segment,
    required String frequency,
    required int hours,
    required int daysPerWeek,
    required int teamSize,
    required String productsBy,
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await _sb.rpc('cleaning_plan_quote', params: {
        'p_segment': segment,
        'p_frequency': frequency,
        'p_hours': hours,
        'p_days_per_week': daysPerWeek,
        'p_team_size': teamSize,
        'p_products_by': productsBy,
        'p_lat': lat,
        'p_lng': lng,
      }).timeout(kAcaoTimeout);
      _erro = null;
      return res is Map ? CleaningPlanQuote.fromJson(Map<String, dynamic>.from(res)) : null;
    } catch (e) {
      debugPrint('CleaningPlanStore.quote error => $e');
      _erro = mensagem(e);
      return null;
    }
  }

  /// Minutos sugeridos por tipologia (platform_settings.cleaning_durations_min).
  Future<Map<String, int>> duracoesPorTipologia() async {
    const reserva = {'t0_t1': 180, 't2': 240, 't3': 300, 't4plus': 360};
    try {
      final row = await _sb
          .from('platform_settings')
          .select('value')
          .eq('key', 'cleaning_durations_min')
          .maybeSingle()
          .timeout(kAcaoTimeout);
      final v = row?['value'];
      if (v is Map) {
        return {
          for (final e in v.entries)
            '${e.key}': (e.value is num) ? (e.value as num).toInt() : (reserva['${e.key}'] ?? 180),
        };
      }
    } catch (e) {
      debugPrint('CleaningPlanStore.duracoesPorTipologia error => $e');
    }
    return reserva;
  }

  /// Cria o plano (fica à espera do cartão). Devolve o id, ou null com [erro] preenchido.
  Future<String?> createPlan({
    required String segment,
    required String frequency,
    required int hours,
    required List<int> days,
    required String time, // HH:MM (Lisboa)
    required DateTime startDate,
    required int teamSize,
    required String productsBy,
    String? homeSize,
    required String billingMode,
    required String street,
    required String city,
    required String postal,
    required double lat,
    required double lng,
    String notes = '',
    String? companyName,
    String? billingNif,
    String? billingEmail,
    String? spaceType,
    int? areaM2,
    List<String> tasks = const [],
    String? accessInstructions,
  }) async {
    try {
      final d = startDate;
      final res = await _sb.rpc('cleaning_plan_create', params: {
        'p_segment': segment,
        'p_frequency': frequency,
        'p_hours': hours,
        'p_days': days,
        'p_time': time,
        'p_start_date':
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'p_team_size': teamSize,
        'p_products_by': productsBy,
        'p_home_size': homeSize,
        'p_billing_mode': billingMode,
        'p_address_street': street,
        'p_address_city': city,
        'p_address_postal': postal,
        'p_lat': lat,
        'p_lng': lng,
        'p_notes': notes,
        'p_company_name': companyName,
        'p_billing_nif': billingNif,
        'p_billing_email': billingEmail,
        'p_space_type': spaceType,
        'p_area_m2': areaM2,
        'p_tasks': tasks,
        'p_access_instructions': accessInstructions,
        'p_idempotency_key': const Uuid().v4(),
      }).timeout(kAcaoTimeout);
      _erro = null;
      return res is Map ? '${res['id']}' : null;
    } catch (e) {
      debugPrint('CleaningPlanStore.createPlan error => $e');
      _erro = mensagem(e);
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> _edge(Map<String, dynamic> body) async {
    try {
      final res = await _sb.functions.invoke('cleaning-plan', body: body).timeout(kAcaoTimeout);
      final data = res.data;
      if (data is Map && data['error'] == null) return Map<String, dynamic>.from(data);
      _erro = data is Map ? mensagem(data['error']) : 'Não foi possível falar com o servidor.';
    } on FunctionException catch (e) {
      final d = e.details;
      _erro = d is Map ? mensagem(d['error']) : 'Não foi possível falar com o servidor.';
      debugPrint('CleaningPlanStore._edge ${body['action']} => ${e.status} $d');
    } catch (e) {
      _erro = mensagem(e);
      debugPrint('CleaningPlanStore._edge ${body['action']} error => $e');
    }
    return null;
  }

  /// SetupIntent para guardar/trocar o cartão do plano (conta Stripe da empresa).
  Future<Map<String, dynamic>?> startCardSetup(String planId) =>
      _edge({'action': 'setup', 'planId': planId});

  /// Depois da folha do cartão: grava o cartão no plano (e o plano começa).
  Future<bool> confirmCardSetup(String planId, String setupIntentId) async {
    final r = await _edge({'action': 'confirm_setup', 'planId': planId, 'setupIntentId': setupIntentId});
    if (r == null) return false;
    await loadMine();
    return true;
  }

  /// Segredo do pagamento que o banco pediu para confirmar (3D Secure).
  Future<Map<String, dynamic>?> actionSecret(String chargeId) =>
      _edge({'action': 'action_secret', 'chargeId': chargeId});

  /// Depois de o cliente confirmar no banco: lê a Stripe e grava o resultado.
  Future<String?> confirmAction(String chargeId) async {
    final r = await _edge({'action': 'confirm_action', 'chargeId': chargeId});
    await loadMine();
    return r?['status'] as String?;
  }

  Future<bool> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _sb.rpc(fn, params: params).timeout(kAcaoTimeout);
      _erro = null;
      await loadMine();
      return true;
    } catch (e) {
      debugPrint('CleaningPlanStore.$fn error => $e');
      _erro = mensagem(e);
      notifyListeners();
      return false;
    }
  }

  /// Saltar uma limpeza (grátis até 24 h antes).
  Future<bool> skip(String planId, String date) =>
      _rpc('cleaning_plan_skip', {'p_plan_id': planId, 'p_date': date});

  /// Mudar o(s) dia(s) e a hora, a partir da próxima.
  Future<bool> changeSchedule(String planId, List<int> days, String time) =>
      _rpc('cleaning_plan_change_schedule', {'p_plan_id': planId, 'p_days': days, 'p_time': time});

  /// Mudar as horas por limpeza (o preço por hora fica o mesmo).
  Future<bool> changeHours(String planId, int hours) =>
      _rpc('cleaning_plan_change_hours', {'p_plan_id': planId, 'p_hours': hours});

  /// Cancelar o plano (sem taxa).
  Future<bool> cancel(String planId) =>
      _rpc('cleaning_plan_cancel', {'p_plan_id': planId, 'p_reason': 'cliente'});

  /// Traduz os erros do servidor para frases simples (PT-PT).
  static String mensagem(Object? e) {
    final t = e is PostgrestException ? e.message : '${e ?? ''}';
    if (t.contains('horas_minimas')) return 'Escolhe pelo menos o mínimo de horas.';
    if (t.contains('horas_maximas') || t.contains('horas_invalidas')) return 'Escolhe entre o mínimo e 10 horas.';
    if (t.contains('horas_inteiras')) return 'As horas são inteiras (1, 2, 3…).';
    if (t.contains('dias_da_semana')) return 'Escolhe o número certo de dias da semana para esta frequência.';
    if (t.contains('hora_entre_6_e_23') || t.contains('hora_invalida')) return 'Escolhe uma hora entre as 06:00 e as 23:00.';
    if (t.contains('data_de_inicio') || t.contains('antecedencia_minima')) return 'Escolhe outra data de início (com pelo menos um dia e meio de antecedência).';
    if (t.contains('morada_obrigatoria')) return 'Falta a morada. Escolhe uma das sugestões para sabermos onde é.';
    if (t.contains('fora_da_area')) return 'Ainda não fazemos limpezas nessa morada (fica longe demais da Guarda).';
    if (t.contains('empresa_nome')) return 'Falta o nome da empresa.';
    if (t.contains('empresa_nif') || t.contains('nif_invalido')) return 'O NIF tem de ter 9 algarismos.';
    if (t.contains('empresa_email')) return 'Confirma o email de faturação.';
    if (t.contains('saltar_so_ate_24h')) return 'Só se pode saltar até 24 h antes da limpeza.';
    if (t.contains('plano_nao_ativo') || t.contains('plan_closed')) return 'Este plano já não está ativo.';
    if (t.contains('card_mbway_not_yet_enabled') || t.contains('planos_desligados')) return 'Os planos ainda não estão disponíveis.';
    if (t.contains('stripe_indisponivel')) return 'O pagamento por cartão está em baixo. Tenta daqui a pouco.';
    if (t.contains('setup_not_completed')) return 'O cartão não foi guardado. Tenta outra vez.';
    if (t.contains('nada_para_confirmar')) return 'Não há nenhum pagamento por confirmar.';
    if (t.contains('TimeoutException')) return 'Sem resposta do servidor. Verifica a internet e tenta outra vez.';
    return 'Não foi possível concluir. Tenta outra vez.';
  }
}
