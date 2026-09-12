/// [Fix botão preso 2026-08-20] Tradução das falhas dos botões de acção do
/// motorista para português simples.
///
/// Vive aqui, fora do ecrã, por dois motivos:
///  1. É lógica pura — não precisa de Flutter, logo é testável de verdade
///     (o mesmo princípio do `TvdeFareView`).
///  2. Estava enterrada como método privado do ecrã, onde nenhum teste lhe
///     chegava.
///
/// Regra da casa: o motorista está ao volante. Nada de nomes de excepções,
/// códigos SQL ou `PostgrestException(...)` — a frase diz o que aconteceu e o
/// que fazer a seguir.
///
/// As marcas que procuramos são as que o servidor levanta mesmo. Confirmado ao
/// vivo contra a produção a 2026-08-20:
/// ```
/// select public.tvde_driver_arrived('00000000-0000-0000-0000-000000000000');
/// ERROR:  P0001: ride_not_found
/// ```
library;

import 'dart:async';

/// Frase a mostrar ao motorista quando uma acção falha.
String mensagemDeFalhaDeAcao(Object erro) {
  if (erro is TimeoutException) {
    return 'O servidor demorou demasiado a responder. Fui verificar como está '
        'a corrida — se continuar igual, tenta outra vez.';
  }

  final txt = erro.toString();

  if (txt.contains('ride_not_found')) {
    return 'Esta corrida já não existe.';
  }
  if (txt.contains('not_ride_driver')) {
    return 'Esta corrida já não está atribuída a ti.';
  }
  if (txt.contains('SocketException') ||
      txt.contains('Failed host lookup') ||
      txt.contains('ClientException') ||
      txt.contains('Connection closed')) {
    return 'Sem ligação à internet. Verifica a rede e tenta outra vez.';
  }

  return 'Não consegui concluir. Verifica o estado da corrida e tenta outra vez.';
}

/// `true` quando a falha significa que já não há nada para fazer neste ecrã —
/// o ecrã deve sair em vez de deixar o motorista preso.
bool falhaFechaOEcra(Object erro) {
  final txt = erro.toString();
  return txt.contains('ride_not_found') || txt.contains('not_ride_driver');
}
