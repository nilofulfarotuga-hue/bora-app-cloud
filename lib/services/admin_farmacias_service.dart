// Painel admin — Farmácias, Bloco 5 da missão farmacias-loja-2026-11-14 (PT-BR nas mensagens).
// Só o que o ecrã Farmácias precisa e o PrescricaoService não tinha:
//   • e-mail de login da farmácia (Edge Fn admin-farmacia-email) + link para criar a senha
//     (Edge Fn support-password-reset, a mesma do diálogo "Redefinir senha" do painel);
//   • código da certidão permanente (RPC admin_farmacia_certidao_definir);
//   • interruptor global das receitas reais (admin_list_settings / admin_update_setting);
//   • extrato semanal só de leitura (compute_partner_weekly_settlement com p_persist = false).
// A lista das farmácias, o modo da receita, a comissão extra e o "abrir ao público" continuam no
// PrescricaoService (admin_farmacias_listar, admin_farmacia_definir, admin_farmacia_abrir).
import 'package:supabase_flutter/supabase_flutter.dart';

/// Erro já com a frase em PT-BR para mostrar ao admin.
class AdminFarmaciaErro implements Exception {
  AdminFarmaciaErro(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

class AdminFarmaciasService {
  AdminFarmaciasService({SupabaseClient? client}) : _override = client;

  final SupabaseClient? _override;
  SupabaseClient get _sb => _override ?? Supabase.instance.client;

  static const Duration timeout = Duration(seconds: 20);

  /// platform_settings: criar pedido real (entregador + cobrança) quando o cliente confirma uma
  /// receita numa farmácia aberta. Desligado até ser provado.
  static const chaveReceitasReais = 'pharmacy_prescription_real_orders_enabled';

  // ---------------------------------------------------------------- login

  /// Troca o e-mail de login da conta do dono e o e-mail da loja. Por defeito troca também a
  /// senha por uma aleatória (a de demonstração deixa de entrar). Devolve a resposta da função.
  Future<Map<String, dynamic>> mudarEmailLogin({
    required String restaurantId,
    required String novoEmail,
    bool invalidarSenha = true,
  }) async {
    try {
      final res = await _sb.functions.invoke('admin-farmacia-email', body: {
        'restaurant_id': restaurantId,
        'novo_email': novoEmail.trim().toLowerCase(),
        'invalidar_senha': invalidarSenha,
      }).timeout(timeout);
      final d = res.data;
      if (d is Map && d['ok'] == true) return Map<String, dynamic>.from(d);
      throw AdminFarmaciaErro(mensagemErroEmail(d is Map ? d['error'] : d));
    } on AdminFarmaciaErro {
      rethrow;
    } on FunctionException catch (e) {
      final d = e.details;
      throw AdminFarmaciaErro(mensagemErroEmail(d is Map ? d['error'] : (d ?? e.status)));
    } catch (e) {
      throw AdminFarmaciaErro('Não foi possível trocar o e-mail (sem resposta do servidor). Tente outra vez.');
    }
  }

  /// Manda o e-mail com o link para a farmácia criar (ou trocar) a senha. Usa a função que já
  /// existe (support-password-reset), que confere que [email] é mesmo o da conta [userId].
  Future<void> enviarLinkSenha({required String userId, required String email}) async {
    try {
      final res = await _sb.functions.invoke('support-password-reset', body: {
        'user_id': userId,
        'email': email,
      }).timeout(timeout);
      final d = res.data;
      if (d is Map && d['ok'] == true) return;
      throw AdminFarmaciaErro('O link não foi enviado: ${d is Map ? (d['detail'] ?? d['error']) : d}');
    } on AdminFarmaciaErro {
      rethrow;
    } on FunctionException catch (e) {
      final d = e.details;
      final motivo = d is Map ? (d['detail'] ?? d['error']) : (d ?? e.status);
      throw AdminFarmaciaErro(motivo == 'email_mismatch'
          ? 'O e-mail da conta mudou entretanto. Atualize a lista e tente de novo.'
          : 'O link não foi enviado: $motivo');
    } catch (e) {
      throw AdminFarmaciaErro('O link não foi enviado (sem resposta do servidor). Tente outra vez.');
    }
  }

  static String mensagemErroEmail(Object? codigo) => switch ('$codigo') {
        'email_invalido' => 'E-mail inválido. Confira se está bem escrito.',
        'email_em_uso' => 'Esse e-mail já é usado por outra conta do app. Use outro ou fale com o suporte.',
        'farmacia_nao_encontrada' => 'Farmácia não encontrada. Atualize a lista.',
        'sem_dono' => 'Esta farmácia não tem conta de dono ligada. Ligue primeiro a conta na ficha do parceiro.',
        'dono_e_admin' => 'A conta desta farmácia é uma conta de administrador: por segurança não se troca por aqui.',
        'forbidden' || '403' => 'Sem permissão de admin para esta ação.',
        'unauthorized' || '401' => 'Sessão expirada. Entre de novo no painel.',
        'loja_falhou' => 'O login mudou, mas o e-mail da loja não foi gravado. Tente de novo (é seguro repetir).',
        _ => 'Não foi possível trocar o e-mail ($codigo).',
      };

  // ---------------------------------------------------------------- dados da empresa

  /// Grava o código da certidão permanente (12 dígitos, 0000-0000-0000). Vazio apaga.
  /// Devolve o código já formatado como ficou gravado (ou null).
  Future<String?> definirCertidao(String restaurantId, String codigo) async {
    try {
      final r = await _sb.rpc('admin_farmacia_certidao_definir', params: {
        'p_restaurant_id': restaurantId,
        'p_codigo': codigo.trim(),
      }).timeout(timeout);
      return r is Map ? r['business_registration_number'] as String? : null;
    } catch (e) {
      final t = e is PostgrestException ? e.message : '$e';
      if (t.contains('certidao_invalida')) {
        throw AdminFarmaciaErro('O código da certidão permanente tem 12 dígitos (0000-0000-0000).');
      }
      if (t.contains('forbidden')) throw AdminFarmaciaErro('Sem permissão de admin para esta ação.');
      throw AdminFarmaciaErro('Não foi possível salvar o código da certidão: $t');
    }
  }

  // ---------------------------------------------------------------- taxas ao cliente (por farmácia)

  /// Taxas que o cliente paga nesta farmácia (23/11/2026, missão farmacia-rego-2026-11-23):
  /// margem dentro do preço (restaurants.app_markup_pct), pedido mínimo e taxa de pedido pequeno
  /// (overrides da loja, senão os valores gerais das Configurações) e a taxa de serviço geral.
  Future<TaxasFarmacia> taxasLoja(String restaurantId) async {
    try {
      final loja = await _sb
          .from('restaurants')
          .select('app_markup_pct, min_order_cents_override, small_order_fee_cents_override')
          .eq('id', restaurantId)
          .single()
          .timeout(timeout);
      final cfg = await _sb
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', TaxasFarmacia.chavesGerais)
          .timeout(timeout);
      final geral = <String, num>{
        for (final e in (cfg as List)) '${e['key']}': num.tryParse('${e['value']}') ?? 0,
      };
      return TaxasFarmacia.deMapas(Map<String, dynamic>.from(loja), geral);
    } catch (e) {
      throw AdminFarmaciaErro('Não foi possível ler as taxas: ${e is PostgrestException ? e.message : e}');
    }
  }

  /// Grava a margem e os valores de pedido pequeno desta farmácia (admin; fica na auditoria da loja).
  /// [margem] em fração (0.15 = 15 %); null = sem margem (preço = balcão). Pedido mínimo e taxa em
  /// cêntimos; null = usa o valor geral das Configurações.
  Future<void> definirTaxas(
    String restaurantId, {
    required double? margem,
    required int? pedidoMinimoCents,
    required int? taxaPedidoPequenoCents,
  }) async {
    try {
      await _sb.from('restaurants').update({
        'app_markup_pct': margem,
        'min_order_cents_override': pedidoMinimoCents,
        'small_order_fee_cents_override': taxaPedidoPequenoCents,
      }).eq('id', restaurantId).timeout(timeout);
    } catch (e) {
      throw AdminFarmaciaErro('Não foi possível salvar as taxas: ${e is PostgrestException ? e.message : e}');
    }
  }

  /// Conta feita pelo SERVIDOR (as mesmas funções do pedido real) para 1 produto de [balcao] € de
  /// balcão a 2 km: mostra o que o cliente paga, o que a farmácia recebe e o que fica para a Bora.
  /// Assim o painel nunca promete uma regra que o servidor ainda não aplica.
  Future<ExemploTaxasFarmacia> exemploServidor(String restaurantId, {required double? margem, double balcao = 10}) async {
    final subtotal = double.parse((balcao * (1 + (margem ?? 0))).toStringAsFixed(2));
    try {
      final q = await _sb.rpc('pricing_calculate_loja', params: {
        'p_service_type': 'restaurant',
        'p_subtotal': subtotal,
        'p_distance_km': 2,
        'p_is_partner_store': true,
        'p_apartment_delivery': false,
        'p_is_stacked_partner': false,
        'p_bag_count': 0,
        'p_restaurant_id': restaurantId,
      }).timeout(timeout);
      final pequeno = await _sb.rpc('small_order_fee_calc', params: {
        'p_service_type': 'restaurant',
        'p_subtotal': subtotal,
        'p_restaurant_id': restaurantId,
      }).timeout(timeout);
      final recebe = await _sb.rpc('partner_store_share', params: {
        'p_subtotal': subtotal,
        'p_restaurant_id': restaurantId,
      }).timeout(timeout);
      final linha = Map<String, dynamic>.from(((q is List ? q.first : q) as Map));
      return ExemploTaxasFarmacia.deServidor(
        balcao: balcao,
        subtotal: subtotal,
        linha: linha,
        pedidoPequeno: num.tryParse('$pequeno') ?? 0,
        farmaciaRecebe: num.tryParse('$recebe') ?? 0,
      );
    } catch (e) {
      throw AdminFarmaciaErro('Não foi possível calcular o exemplo: ${e is PostgrestException ? e.message : e}');
    }
  }

  // ---------------------------------------------------------------- receitas reais (global)

  /// Estado do interruptor. null = não foi possível ler (o ecrã mostra "não consegui ler" e não
  /// deixa mudar). Nunca lança: o ecrã chama isto ao recarregar mesmo quando nada o está a ouvir.
  Future<bool?> receitasReaisLigadas() async {
    try {
      final r = await _sb.rpc('admin_list_settings', params: {'p_category': 'farmacias'}).timeout(timeout);
      for (final e in (r as List? ?? const [])) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['key'] == chaveReceitasReais) return m['value'] == true;
      }
      return false;
    } catch (_) {
      return null;
    }
  }

  /// Muda o interruptor (auditado pelo admin_update_setting). O ecrã pede confirmação forte antes.
  Future<void> definirReceitasReais(bool ligar) async {
    try {
      await _sb.rpc('admin_update_setting', params: {
        'p_key': chaveReceitasReais,
        'p_value': ligar,
      }).timeout(timeout);
    } catch (e) {
      throw AdminFarmaciaErro('Não foi possível mudar o interruptor: ${e is PostgrestException ? e.message : e}');
    }
  }

  // ---------------------------------------------------------------- extrato semanal

  /// Extrato da semana que contém [diaDaSemana] para uma farmácia. Só leitura (p_persist = false):
  /// não grava nada em partner_weekly_settlements. Valores em euros (numeric).
  Future<Map<String, dynamic>> extratoSemana(String restaurantId, DateTime diaDaSemana) async {
    final r = await _sb.rpc('compute_partner_weekly_settlement', params: {
      'p_partner_id': restaurantId,
      'p_week_start': diaDaSemana.toUtc().toIso8601String(),
      'p_persist': false,
    }).timeout(timeout);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}

/// Taxas de uma farmácia (valores da loja + gerais das Configurações). Função pura, testável.
class TaxasFarmacia {
  const TaxasFarmacia({
    required this.margem,
    required this.pedidoMinimoCents,
    required this.taxaPedidoPequenoCents,
    required this.pedidoMinimoGeralCents,
    required this.taxaPedidoPequenoGeralCents,
    required this.taxaServicoPct,
    required this.taxaServicoFixaFarmaciasCents,
  });

  static const chavesGerais = [
    'min_order_cents',
    'small_order_fee_cents',
    'client_service_fee_pct',
    'pharmacy_service_fee_fixed_cents',
  ];

  /// Fração (0.15 = 15 %) ou null (sem margem: preço = balcão).
  final double? margem;
  final int? pedidoMinimoCents;
  final int? taxaPedidoPequenoCents;
  final int pedidoMinimoGeralCents;
  final int taxaPedidoPequenoGeralCents;
  final double taxaServicoPct;
  final int taxaServicoFixaFarmaciasCents;

  factory TaxasFarmacia.deMapas(Map<String, dynamic> loja, Map<String, num> geral) => TaxasFarmacia(
        margem: (loja['app_markup_pct'] as num?)?.toDouble(),
        pedidoMinimoCents: (loja['min_order_cents_override'] as num?)?.toInt(),
        taxaPedidoPequenoCents: (loja['small_order_fee_cents_override'] as num?)?.toInt(),
        pedidoMinimoGeralCents: (geral['min_order_cents'] ?? 0).toInt(),
        taxaPedidoPequenoGeralCents: (geral['small_order_fee_cents'] ?? 0).toInt(),
        taxaServicoPct: (geral['client_service_fee_pct'] ?? 0).toDouble(),
        taxaServicoFixaFarmaciasCents: (geral['pharmacy_service_fee_fixed_cents'] ?? 0).toInt(),
      );

  bool get temMargem => (margem ?? 0) > 0;
  int get pedidoMinimoEfetivoCents => pedidoMinimoCents ?? pedidoMinimoGeralCents;
  int get taxaPedidoPequenoEfetivaCents => taxaPedidoPequenoCents ?? taxaPedidoPequenoGeralCents;
}

/// Exemplo de um pedido calculado pelo servidor (euros).
class ExemploTaxasFarmacia {
  const ExemploTaxasFarmacia({
    required this.balcao,
    required this.produto,
    required this.taxaServico,
    required this.entrega,
    required this.saco,
    required this.pedidoPequeno,
    required this.clientePaga,
    required this.farmaciaRecebe,
    required this.estafeta,
  });

  factory ExemploTaxasFarmacia.deServidor({
    required double balcao,
    required double subtotal,
    required Map<String, dynamic> linha,
    required num pedidoPequeno,
    required num farmaciaRecebe,
  }) {
    double n(String k) => (num.tryParse('${linha[k]}') ?? 0).toDouble();
    return ExemploTaxasFarmacia(
      balcao: balcao,
      produto: subtotal,
      taxaServico: n('service_fee'),
      entrega: n('delivery_fee'),
      saco: n('bag_fee'),
      pedidoPequeno: pedidoPequeno.toDouble(),
      clientePaga: n('customer_total') + pedidoPequeno.toDouble(),
      farmaciaRecebe: farmaciaRecebe.toDouble(),
      estafeta: n('driver_earnings'),
    );
  }

  final double balcao;
  final double produto;
  final double taxaServico;
  final double entrega;
  final double saco;
  final double pedidoPequeno;
  final double clientePaga;
  final double farmaciaRecebe;
  final double estafeta;

  double get bora => double.parse((clientePaga - farmaciaRecebe - estafeta).toStringAsFixed(2));
}
