/// [Fix botão preso 2026-08-20] Tradução das falhas de QUALQUER botão de acção
/// para português simples, e decisão de sair (ou não) do ecrã.
///
/// Nasceu no ecrã de corrida do motorista (`tvde_driver_action_error.dart`) e
/// foi renomeado quando passou a servir também o estafeta do delivery, a
/// limpeza, as marcações e as reservas — deixou de ser só do TVDE.
///
/// Vive fora dos ecrãs por dois motivos:
///  1. É lógica pura — não precisa de Flutter, logo é testável de verdade
///     (o mesmo princípio do `TvdeFareView`).
///  2. Enterrada como método privado de um ecrã, nenhum teste lhe chegava.
///
/// Regra da casa: quem lê isto está a trabalhar — muitas vezes ao volante.
/// Nada de nomes de excepções, códigos SQL ou `PostgrestException(...)`. A
/// frase diz o que aconteceu e o que fazer a seguir.
///
/// **As marcas não foram inventadas.** Saíram de um varrimento ao código das
/// funções em produção a 2026-08-20 (`RAISE EXCEPTION '<marca>'`), com a
/// contagem de funções que as levantam:
/// ```
/// not_authenticated 19 · ride_not_found 15 · reservation_not_found 8
/// auth_required 7 · booking_not_found 6 · not_ride_driver 6
/// appointment_not_found 5 · booking_not_yours 4 · invalid_status 3
/// offer_no_longer_valid 3 · not_ride_client 2 · not_ride_owner 2
/// not_your_appointment 2 · not_your_reservation 2 · ride_already_taken 2
/// ```
/// E confirmadas ao vivo contra a produção:
/// ```
/// select public.tvde_driver_arrived('00000000-0000-0000-0000-000000000000');
/// ERROR:  P0001: ride_not_found
/// ```
library;

import 'dart:async';

/// O que está a ser tratado quando a acção falha. Serve só para a frase sair
/// natural em português: *"Esta corrida já não existe"* vs *"Este pedido já
/// não existe"*. É obrigatório de propósito — um valor por omissão faria um
/// ecrã de entregas dizer "corrida" sem ninguém dar por isso.
enum TrabalhoEmCurso {
  corrida, // TVDE
  pedido, // delivery
  limpeza,
  marcacao, // serviços / barbearias
  reserva,
}

extension _Nomes on TrabalhoEmCurso {
  /// "Esta corrida", "Este pedido", …
  String get comMaiuscula => switch (this) {
        TrabalhoEmCurso.corrida => 'Esta corrida',
        TrabalhoEmCurso.pedido => 'Este pedido',
        TrabalhoEmCurso.limpeza => 'Esta limpeza',
        TrabalhoEmCurso.marcacao => 'Esta marcação',
        TrabalhoEmCurso.reserva => 'Esta reserva',
      };

  /// "a corrida", "o pedido", … (para o meio de uma frase)
  String get comMinuscula => switch (this) {
        TrabalhoEmCurso.corrida => 'a corrida',
        TrabalhoEmCurso.pedido => 'o pedido',
        TrabalhoEmCurso.limpeza => 'a limpeza',
        TrabalhoEmCurso.marcacao => 'a marcação',
        TrabalhoEmCurso.reserva => 'a reserva',
      };

  /// Concordância: "atribuída" / "atribuído".
  String get atribuido =>
      this == TrabalhoEmCurso.pedido ? 'atribuído' : 'atribuída';
}

/// Marcas que o servidor levanta quando a coisa simplesmente já não existe.
const _naoExiste = <String>[
  'ride_not_found',
  'reservation_not_found',
  'booking_not_found',
  'appointment_not_found',
  'provider_not_found',
];

/// Marcas de "existe, mas já não é teu".
const _naoEhTeu = <String>[
  'not_ride_driver',
  'not_ride_client',
  'not_ride_owner',
  'booking_not_yours',
  'not_your_appointment',
  'not_your_reservation',
  'not_authorized',
  'forbidden',
];

/// Marcas de "outra pessoa ficou com isto / a oferta expirou".
const _jaFoiTirado = <String>[
  'ride_already_taken',
  'offer_no_longer_valid',
  'offer_not_yours_or_expired',
];

/// Marcas de sessão perdida.
const _semSessao = <String>[
  'not_authenticated',
  'auth_required',
];

/// Marcas de "o estado mudou por baixo de ti".
const _estadoErrado = <String>[
  'invalid_status',
  'booking_not_active',
  'booking_not_finished',
  'cannot_cancel',
  'cancellation_not_allowed_reschedule_only',
];

/// Marcas de rede em baixo.
const _semRede = <String>[
  'SocketException',
  'Failed host lookup',
  'ClientException',
  'Connection closed',
  'Connection refused',
];

bool _tem(String txt, List<String> marcas) =>
    marcas.any((m) => txt.contains(m));

/// Frase a mostrar quando uma acção falha.
String mensagemDeFalhaDeAcao(
  Object erro, {
  required TrabalhoEmCurso trabalho,
}) {
  if (erro is TimeoutException) {
    return 'O servidor demorou demasiado a responder. Fui verificar como está '
        '${trabalho.comMinuscula} — se continuar igual, tenta outra vez.';
  }

  final txt = erro.toString();

  if (_tem(txt, _naoExiste)) {
    return '${trabalho.comMaiuscula} já não existe.';
  }
  if (_tem(txt, _naoEhTeu)) {
    return '${trabalho.comMaiuscula} já não está ${trabalho.atribuido} a ti.';
  }
  if (_tem(txt, _jaFoiTirado)) {
    return 'Já não está disponível — outra pessoa chegou primeiro.';
  }
  if (_tem(txt, _semSessao)) {
    return 'A tua sessão terminou. Entra outra vez para continuar.';
  }
  if (_tem(txt, _estadoErrado)) {
    return '${trabalho.comMaiuscula} já não está nesse estado. Atualiza para '
        'veres como está agora.';
  }
  if (_tem(txt, _semRede)) {
    return 'Sem ligação à internet. Verifica a rede e tenta outra vez.';
  }

  return 'Não consegui concluir. Verifica ${trabalho.comMinuscula} e tenta '
      'outra vez.';
}

/// `true` quando a falha significa que já não há nada para fazer neste ecrã —
/// o ecrã deve sair em vez de deixar a pessoa presa.
///
/// Rede e timeout NÃO fecham o ecrã de propósito: aí não sabemos o que se
/// passou, e a acção até pode ter-se aplicado.
bool falhaFechaOEcra(Object erro) {
  if (erro is TimeoutException) return false;
  final txt = erro.toString();
  return _tem(txt, _naoExiste) ||
      _tem(txt, _naoEhTeu) ||
      _tem(txt, _jaFoiTirado);
}

/// Tecto de espera de QUALQUER acção com botão, em toda a app.
///
/// Sem isto, uma chamada que nunca responde (rede fraca, servidor pendurado)
/// deixa o `finally` por correr e o botão fica a girar para sempre — foi
/// exactamente o defeito de 2026-08-20 no ecrã de corrida do motorista.
const Duration kAcaoTimeout = Duration(seconds: 12);
