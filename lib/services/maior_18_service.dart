// Missão maiores-18 (07/10/2026) — chamadas ao servidor da verificação de
// idade. Só lê/escreve pelas RPCs da migration
// `20261007180000_maiores_18_verificacao_idade.sql`; nunca toca em `orders`.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de `driver_confirm_age_check`. [ok] false → [erro] traz o código
/// do servidor (`auth_required`, `not_your_order`, `invalid_status`, …) ou
/// `network` quando não houve resposta.
class VerificacaoIdadeResultado {
  const VerificacaoIdadeResultado({
    required this.ok,
    this.status,
    this.erro,
    this.ja = false,
    this.naoExigida = false,
  });

  final bool ok;

  /// 'confirmado' | 'recusado' quando [ok].
  final String? status;
  final String? erro;

  /// A decisão já tinha sido tomada (outro toque, outro aparelho).
  final bool ja;

  /// O pedido afinal não tem produtos +18 — segue sem passo.
  final bool naoExigida;

  factory VerificacaoIdadeResultado.fromRpc(dynamic r) {
    if (r is! Map) {
      return const VerificacaoIdadeResultado(ok: false, erro: 'network');
    }
    final m = Map<String, dynamic>.from(r);
    return VerificacaoIdadeResultado(
      ok: m['ok'] == true,
      status: m['status']?.toString(),
      erro: m['error']?.toString(),
      ja: m['already'] == true,
      naoExigida: m['not_required'] == true,
    );
  }

  /// Mensagem em PT-PT para o estafeta. A chave do dicionário é o próprio
  /// português (ver `lib/l10n/tr.dart`); quem mostra aplica `.tr`.
  String get mensagem {
    switch (erro) {
      case 'not_your_order':
        return 'Este pedido não está atribuído a ti.';
      case 'invalid_status':
        return 'Esta entrega já não está em curso. Fecha e confirma em Pedidos.';
      case 'order_not_found':
        return 'Pedido não encontrado. Fecha e tenta de novo.';
      case 'auth_required':
        return 'A tua sessão expirou. Entra outra vez.';
      case 'network':
        return 'Sem ligação ao servidor. Tenta de novo.';
      default:
        return 'Não foi possível registar a verificação. Tenta de novo.';
    }
  }
}

/// Assinatura injectável para os testes de widget (sem Supabase).
typedef ConfirmarIdadeFn = Future<VerificacaoIdadeResultado> Function(
    String orderId, bool ok);

class Maior18Service {
  Maior18Service._();

  /// A descrição de um Favor fala de tabaco ou álcool? Chama a RPC
  /// `texto_pede_maior_18` (só lê). Em erro de rede devolve false — o aviso é
  /// informativo; a marca do pedido é posta pelo servidor ao criar.
  static Future<bool> textoPedeMaior18(String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return false;
    try {
      final r = await Supabase.instance.client
          .rpc('texto_pede_maior_18', params: {'p_texto': t})
          .timeout(const Duration(seconds: 6));
      return r == true;
    } catch (e) {
      debugPrint('[maior-18] texto_pede_maior_18: $e');
      return false;
    }
  }

  /// O passo do estafeta: `driver_confirm_age_check(order, ok)`.
  /// ok=true "Vi o documento, tem 18 ou mais"; ok=false "Não mostrou
  /// documento / é menor" (o servidor abre o pedido de cancelamento pelo
  /// caminho que já existe — a app não mexe em dinheiro).
  static Future<VerificacaoIdadeResultado> confirmar(
      String orderId, bool ok) async {
    try {
      final r = await Supabase.instance.client.rpc(
        'driver_confirm_age_check',
        params: {'p_order_id': orderId, 'p_ok': ok},
      ).timeout(const Duration(seconds: 12));
      return VerificacaoIdadeResultado.fromRpc(r);
    } catch (e) {
      debugPrint('[maior-18] driver_confirm_age_check: $e');
      return const VerificacaoIdadeResultado(ok: false, erro: 'network');
    }
  }
}
