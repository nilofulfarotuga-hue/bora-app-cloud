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
