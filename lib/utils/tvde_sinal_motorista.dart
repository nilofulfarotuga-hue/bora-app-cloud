/// [TVDE 05/09 · 2C] Idade da posição do motorista — PURO, sem Flutter e sem
/// relógio escondido (o `agora` é injectável, senão o teste dependia da hora
/// da máquina).
///
/// **A cicatriz:** a RPC `tvde_ride_driver_card` já devolvia
/// `location_updated_at` e ninguém a lia. Um motorista com o GPS morto
/// aparecia ao cliente exactamente como um motorista parado — o carro imóvel
/// no mapa, sem explicação nenhuma. O cliente ficava a olhar sem perceber se
/// o carro tinha avariado, se o motorista tinha desistido, ou se era a app.
///
/// Três estados, e os dois limites vivem em `platform_settings` (categoria
/// `tvde`) para o Danilo afinar sem esperar por build:
///  - **fresco** — anima normalmente;
///  - **velho** (`tvde_driver_stale_seconds`, 45 s) — pára a animação, esbate
///    o carro, e diz há quanto tempo foi a última posição;
///  - **perdido** (`tvde_driver_lost_seconds`, 180 s) — já não se finge que o
///    ponto no mapa é o motorista.
library;

/// Fallbacks de arranque/offline. A verdade vive em `platform_settings`.
const int kTvdeDriverStaleSeconds = 45;
const int kTvdeDriverLostSeconds = 180;

enum EstadoSinalMotorista { semPosicao, fresco, velho, perdido }

/// Segundos desde a última posição. `null` quando nunca houve posição — aí não
/// há carro no mapa e não há nada a dizer sobre a idade dele.
///
/// O relógio do telemóvel pode estar adiantado em relação ao do servidor, o
/// que daria uma idade NEGATIVA. Trava-se em zero em vez de mostrar disparate
/// ("última posição há -3 min" é pior do que não dizer nada).
int? segundosDesdeFix(DateTime? ultimaPosicao, {DateTime? agora}) {
  if (ultimaPosicao == null) return null;
  final s = (agora ?? DateTime.now())
      .toUtc()
      .difference(ultimaPosicao.toUtc())
      .inSeconds;
  return s < 0 ? 0 : s;
}

/// Em que estado está o sinal do motorista.
///
/// Defensivo com valores disparatados vindos do painel: um `lost` menor ou
/// igual ao `stale` tornaria o estado "velho" inalcançável (saltava logo para
/// perdido), por isso nesse caso o `lost` é empurrado para cima do `stale`.
EstadoSinalMotorista estadoDoSinal(
  DateTime? ultimaPosicao, {
  DateTime? agora,
  int staleSeconds = kTvdeDriverStaleSeconds,
  int lostSeconds = kTvdeDriverLostSeconds,
}) {
  final s = segundosDesdeFix(ultimaPosicao, agora: agora);
  if (s == null) return EstadoSinalMotorista.semPosicao;

  final stale = staleSeconds < 1 ? 1 : staleSeconds;
  final lost = lostSeconds <= stale ? stale + 1 : lostSeconds;

  if (s >= lost) return EstadoSinalMotorista.perdido;
  if (s >= stale) return EstadoSinalMotorista.velho;
  return EstadoSinalMotorista.fresco;
}

/// O carro deve continuar a animar? Só com sinal fresco.
bool devoAnimarCarro(EstadoSinalMotorista estado) =>
    estado == EstadoSinalMotorista.fresco;

// NOTA: aqui esteve um `textoIdadeDaPosicao` que devolvia "há X min" em
// português cru. Foi removido de propósito: só o teste o usava, e um helper de
// texto que não passa pelo dicionário é uma armadilha — o primeiro ecrã que o
// adoptasse mostrava português a um cliente em inglês. A frase que o cliente
// lê é montada no ecrã com `.tr`, sobre as chaves 'Última posição há {0} s' e
// '... {0} min', que existem no dicionário. Se um dia isto voltar, tem de
// devolver a CHAVE, não a frase.
