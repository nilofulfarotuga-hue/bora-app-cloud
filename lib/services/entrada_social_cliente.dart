// Entrar com Google (e Apple no iPhone) — só para o CLIENTE.
//
// Missão pendencias-2026-11-09, bloco E. Escolha: OAuth pelo navegador do
// Supabase (`signInWithOAuth`), não o `google_sign_in` nativo:
//   * nenhum pacote novo no pubspec e nenhuma chave nova na app — o segredo do
//     cliente Web do Google vive no Supabase, os IDs são públicos;
//   * o mesmo código serve Android, iPhone e web;
//   * no Android o próprio supabase_flutter abre o Google no navegador externo
//     (o Google recusa entrar dentro de uma WebView); no iPhone abre numa
//     folha Safari dentro da app (SFSafariViewController), que é o que a Apple
//     pede na regra 4.0; na web vai e volta no mesmo separador.
//
// A volta à app no telemóvel é pela ligação `pt.boraapp.bora://auth/callback`
// (já está nas Redirect URLs do Supabase Auth); na web é a origem do próprio
// site (`https://app.boraguarda.com`, `https://bora-app-web.pages.dev`…, todas
// já aceites com `/**`).
//
// Quem conclui a entrada é o AuthStore (ouve a sessão nova, marca a conta como
// cliente e abre a app pelo _RootNavigator, igual ao registo por email).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show closeInAppWebView;

/// Ligação de volta à app (Android e iPhone). Está na allow-list do Supabase
/// Auth desde antes desta missão — não mudar sem mudar lá também.
const String oauthRedirectApp = 'pt.boraapp.bora://auth/callback';

/// Interruptores no servidor (`platform_settings`, lidos por `get_setting`).
const String kChaveLoginGoogle = 'login_google_ativo';
const String kChaveLoginApple = 'login_apple_ativo';

/// Para onde o Supabase manda a pessoa depois do Google/Apple.
String redirectDaEntradaSocial({required bool web, Uri? base}) =>
    web ? (base ?? Uri.base).origin : oauthRedirectApp;

/// Como se abre a página do Google/Apple.
LaunchMode modoDaPaginaDeEntrada({
  required bool web,
  required TargetPlatform plataforma,
}) {
  if (web) return LaunchMode.platformDefault; // o SDK usa o mesmo separador
  if (plataforma == TargetPlatform.iOS) {
    // Folha Safari dentro da app (a Apple recusa apps que mandam para o
    // Safari de fora só para entrar — regra 4.0).
    return LaunchMode.inAppBrowserView;
  }
  // Android: o Google só aceita o navegador de verdade (o SDK força isto).
  return LaunchMode.externalApplication;
}

/// Que botões se mostram.
///
/// Regra 4.8 da Apple: uma app de iPhone que ofereça entrar com o Google tem
/// de oferecer também "Iniciar sessão com a Apple". Por isso, no iPhone, o
/// Google só aparece quando a Apple também está ligada. No Android e na web
/// basta o Google.
({bool google, bool apple}) botoesDeEntradaVisiveis({
  required bool web,
  required TargetPlatform plataforma,
  required bool googleLigado,
  required bool appleLigado,
}) {
  final iphone = !web && plataforma == TargetPlatform.iOS;
  if (iphone) {
    return (google: googleLigado && appleLigado, apple: appleLigado);
  }
  return (google: googleLigado, apple: false);
}

/// Assinatura do `signInWithOAuth` (trocável nos testes por um falso).
typedef IniciarOAuth = Future<bool> Function(
  OAuthProvider fornecedor, {
  required String redirectTo,
  required LaunchMode modo,
});

class EntradaSocialCliente {
  EntradaSocialCliente._();

  /// Testes: substitui a chamada ao Supabase (nada sai para a rede).
  @visibleForTesting
  static IniciarOAuth? iniciarParaTeste;

  /// Testes: substitui a leitura dos interruptores do servidor.
  @visibleForTesting
  static Future<({bool google, bool apple})> Function()? interruptoresParaTeste;

  /// Último valor lido (o ecrã começa por aqui e depois confirma no
  /// servidor). Google ligado por defeito, Apple desligada por defeito.
  static ({bool google, bool apple}) ultimosInterruptores =
      (google: true, apple: false);

  static const _kPendente = 'bora_auth.entrada_social_cliente';
  static const _validade = Duration(minutes: 30);
  static DateTime? _pendenteEmMemoria;

  /// Lê os interruptores do painel. Google: sem linha ou sem rede → ligado
  /// (a definição só existe para o desligar depressa). Apple: só com `true`
  /// explícito (o servidor ainda não tem o segredo OAuth da Apple).
  static Future<({bool google, bool apple})> lerInterruptores() async {
    final teste = interruptoresParaTeste;
    if (teste != null) return ultimosInterruptores = await teste();
    final cliente = Supabase.instance.client;
    Future<Object?> ler(String chave) async {
      try {
        return await cliente.rpc('get_setting', params: {'p_key': chave});
      } catch (_) {
        return null;
      }
    }

    final valores =
        await Future.wait([ler(kChaveLoginGoogle), ler(kChaveLoginApple)]);
    return ultimosInterruptores =
        (google: valores[0] != false, apple: valores[1] == true);
  }

  /// Abre a página do Google/Apple. Devolve `false` se não abriu.
  ///
  /// Marca antes a entrada como "de cliente" (memória + armazenamento, para a
  /// web que recarrega a página), para o AuthStore saber o que fazer quando a
  /// sessão chegar.
  static Future<bool> iniciar(OAuthProvider fornecedor) async {
    await _marcarPendente();
    final redirect = redirectDaEntradaSocial(web: kIsWeb);
    final modo =
        modoDaPaginaDeEntrada(web: kIsWeb, plataforma: defaultTargetPlatform);
    final teste = iniciarParaTeste;
    if (teste != null) {
      return teste(fornecedor, redirectTo: redirect, modo: modo);
    }
    return Supabase.instance.client.auth.signInWithOAuth(
      fornecedor,
      redirectTo: redirect,
      authScreenLaunchMode: modo,
    );
  }

  static Future<void> _marcarPendente() async {
    final agora = DateTime.now();
    _pendenteEmMemoria = agora;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendente, agora.toUtc().toIso8601String());
    } catch (_) {}
  }

  /// Havia uma entrada de cliente com Google/Apple em curso (há menos de 30
  /// min)? Lê e apaga — só serve uma vez.
  static Future<bool> consumirPendente() async {
    final agora = DateTime.now();
    var quando = _pendenteEmMemoria;
    _pendenteEmMemoria = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getString(_kPendente);
      if (guardado != null) {
        await prefs.remove(_kPendente);
        quando ??= DateTime.tryParse(guardado)?.toLocal();
      }
    } catch (_) {}
    return quando != null && agora.difference(quando) < _validade;
  }

  /// A conta entrou por Google ou Apple?
  static bool contaSocial(User user) {
    const sociais = {'google', 'apple'};
    final app = user.appMetadata;
    if (sociais.contains(app['provider'])) return true;
    final lista = app['providers'];
    if (lista is List && lista.any(sociais.contains)) return true;
    return (user.identities ?? const <UserIdentity>[])
        .any((i) => sociais.contains(i.provider));
  }

  /// No iPhone, fecha a folha Safari que ficou aberta por cima da app.
  static Future<void> fecharPaginaDeEntrada() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await closeInAppWebView();
    } catch (_) {}
  }
}
