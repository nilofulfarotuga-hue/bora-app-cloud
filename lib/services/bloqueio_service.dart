import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// BLOQUEAR UMA PESSOA (2026-09-10).
///
/// A directriz 1.2 da App Store exige, para apps com conteúdo de utilizadores,
/// três coisas do lado de quem usa: filtrar, **denunciar** e **bloquear**. A
/// Bora tinha as duas primeiras — a moderação no painel e o botão de denúncia
/// de 09/09 — e não tinha a terceira. A Apple recusou a primeira submissão a
/// 10/09 e nomeou-a: *"the required content reporting and blocking
/// mechanisms"*.
///
/// O que "bloquear" quer dizer aqui: a pessoa do outro lado **daquele pedido**
/// (o estafeta, ou o cliente). A tabela `messages` não guarda quem enviou —
/// só o papel — por isso o bloqueio é da pessoa, identificada pelo pedido, e
/// não da mensagem.
///
/// Guarda-se em `blocked_users`, com RLS: cada um só vê, cria e retira os seus.
class BloqueioService {
  BloqueioService._();

  static final Set<String> _bloqueados = <String>{};
  static bool _carregado = false;

  /// `true` quando a lista veio mesmo do servidor. Só para diagnóstico.
  static bool get carregadoDoServidor => _carregado;

  /// Quantas pessoas estão bloqueadas. Só para diagnóstico.
  static int get quantos => _bloqueados.length;

  /// Lê a lista de quem esta pessoa bloqueou. Nunca lança.
  ///
  /// Uma lista vazia **não** marca como carregado: sem sessão a RLS devolve
  /// `[]` sem erro, e a primeira leitura falhada fechava a porta para sempre.
  /// É a mesma cicatriz do interruptor 5.2.1 e do `RemoteFeesService`.
  static Future<void> carregar({bool forcar = false}) async {
    if (_carregado && !forcar) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        debugPrint('[Bloqueio] sem sessão — tenta-se depois de entrar.');
        return;
      }
      final linhas = await Supabase.instance.client
          .from('blocked_users')
          .select('blocked_ref')
          .eq('blocker_id', uid);
      _bloqueados
        ..clear()
        ..addAll((linhas as List)
            .map((l) => (l as Map<String, dynamic>)['blocked_ref'] as String));
      _carregado = true;
      debugPrint('[Bloqueio] ${_bloqueados.length} bloqueio(s) carregado(s).');
    } catch (e) {
      debugPrint('[Bloqueio] falhou a ler: $e');
    }
  }

  static bool estaBloqueado(String? ref) =>
      ref != null && ref.isNotEmpty && _bloqueados.contains(ref);

  /// Bloqueia. Devolve `true` quando ficou mesmo gravado.
  static Future<bool> bloquear(String ref,
      {String? etiqueta, String? motivo}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || ref.isEmpty) return false;
    try {
      await Supabase.instance.client.from('blocked_users').upsert({
        'blocker_id': uid,
        'blocked_ref': ref,
        'blocked_label': etiqueta,
        'motivo': motivo,
      }, onConflict: 'blocker_id,blocked_ref');
      _bloqueados.add(ref);
      return true;
    } catch (e) {
      debugPrint('[Bloqueio] falhou a bloquear: $e');
      return false;
    }
  }

  /// Retira o bloqueio. Devolve `true` quando ficou mesmo retirado.
  static Future<bool> desbloquear(String ref) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || ref.isEmpty) return false;
    try {
      await Supabase.instance.client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_ref', ref);
      _bloqueados.remove(ref);
      return true;
    } catch (e) {
      debugPrint('[Bloqueio] falhou a desbloquear: $e');
      return false;
    }
  }

  /// Usado ao sair da conta, para a lista não passar de pessoa para pessoa.
  static void esquecer() {
    _bloqueados.clear();
    _carregado = false;
  }
}
