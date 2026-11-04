/// Interruptor geral do Bora Motorista (TVDE de passageiros) nas apps.
///
/// 04/11/2026 (missão fechar-bora-motorista): o Bora Motorista fecha porque
/// ainda não tem a licença do IMT. A Claude.ai fechou o servidor
/// (`users.tvde_access` = false e o pedir corrida recusa `no_tvde_access`);
/// este interruptor fecha a parte das apps: com
/// `platform_settings.tvde_app_visivel` = false nada do Bora Motorista se
/// desenha nem abre — ladrilhos, pesquisa, corridas nas reservas, retoma de
/// corrida, ofertas e modo de corridas do motorista, cadastro de motorista
/// de passageiros, ligações diretas.
///
/// O código fica todo (arquivado atrás deste interruptor): quando a licença
/// sair, o Danilo liga `tvde_app_visivel` no painel e tudo volta.
///
/// NA DÚVIDA, ESCONDE. Começa fechado e só abre depois de o servidor dizer
/// `true`. Uma falha de rede nunca muda o estado que já se leu (a mesma
/// tolerância do `TvdeStore.refreshAccess`): quem já viu fechado continua
/// fechado, e a primeira leitura falhada deixa fechado.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/falha_de_acao.dart' show kAcaoTimeout;

class TvdeVisibilidade {
  TvdeVisibilidade._();

  /// Chave em `platform_settings` (categoria `tvde`).
  static const String chave = 'tvde_app_visivel';

  /// `true` = o Bora Motorista aparece. Começa `false` (fechado).
  static final ValueNotifier<bool> visivel = ValueNotifier<bool>(false);

  /// Atalho de leitura.
  static bool get aberto => visivel.value;

  /// `true` depois da primeira leitura bem sucedida do servidor.
  static bool _lido = false;
  static bool get lido => _lido;

  static Future<void>? _emCurso;

  /// Lê o interruptor do servidor. Nunca lança. Chamadas em simultâneo
  /// partilham a mesma leitura.
  static Future<void> refresh() => _emCurso ??= _ler().whenComplete(() {
        _emCurso = null;
      });

  static Future<void> _ler() async {
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      try {
        final res = await Supabase.instance.client
            .rpc('get_setting', params: {'p_key': chave}).timeout(kAcaoTimeout);
        _aplicar(_comoBool(res));
        return;
      } catch (e) {
        debugPrint('TvdeVisibilidade.refresh (tentativa ${tentativa + 1}) => $e');
        if (tentativa == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    // Duas falhas: fica como estava (fechado, se nunca se leu).
  }

  /// `null` (chave ausente) conta como fechado.
  static bool _comoBool(Object? res) {
    if (res == null) return false;
    final s = res.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't';
  }

  static void _aplicar(bool v) {
    _lido = true;
    if (visivel.value != v) visivel.value = v;
  }

  /// Só para testes: abre/fecha sem ir ao servidor.
  @visibleForTesting
  static void definirParaTeste(bool v) {
    _lido = true;
    visivel.value = v;
  }
}
