import '../../../l10n/tr.dart';

/// Regras do botão de pedir corrida (missão tvde-pedir-nunca-trava, 14/10).
///
/// **Cicatriz:** a cliente Stela escreveu a morada, o botão ficou cinzento e
/// não disse porquê; ela desistiu e ligou ao Danilo. Daqui para a frente o
/// botão diz sempre o que falta. Funções puras para se poderem provar em teste
/// sem mapa nem rede.

/// O que falta para poder pedir, em palavras — `null` quando já se pode.
String? oQueFaltaParaPedir({
  required bool temRecolha,
  required bool temDestino,
  required bool aLocalizar,
  required bool aCalcular,
  required bool temPreco,
}) {
  if (!temRecolha) {
    return aLocalizar
        ? 'A procurar a tua localização…'.tr
        : 'Escolhe o ponto de recolha'.tr;
  }
  if (!temDestino) return 'Escolhe o destino'.tr;
  if (aLocalizar) return 'A procurar a tua localização…'.tr;
  if (aCalcular || !temPreco) return 'A calcular o preço…'.tr;
  return null;
}

/// Porque é que um toque em "pedir" não deu pedido — vai para
/// `web_health_events` (motivo `pedido_travado`) e para o painel admin.
String motivoPedidoTravado({
  required bool geocodeFalhou,
  required bool temRecolha,
  required bool gpsFalhou,
}) {
  if (geocodeFalhou) return 'geocode_falhou';
  if (!temRecolha) return gpsFalhou ? 'gps_falhou' : 'sem_recolha';
  return 'sem_destino';
}

/// Ajuda por baixo do campo da recolha: com o GPS negado/desligado e sem
/// recolha, diz o que fazer em vez de ficar vazio.
String? ajudaDaRecolha({required bool gpsFalhou, required bool temRecolha}) =>
    gpsFalhou && !temRecolha
        ? 'Liga a localização ou escreve a morada'.tr
        : null;
