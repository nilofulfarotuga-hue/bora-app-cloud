// lib/utils/sinal_motorista.dart
//
// [24/10/2026 · missão geral-sabado-24-10, bloco 1] "Ligado sem sinal" no
// painel admin (PT-BR).
//
// A cicatriz: o Valdemir aparecia "Online" no painel desde 20/10 03:01 sem
// mandar sinal nenhum — o telemóvel tinha matado o serviço de fundo. O botão
// dele continua ligado (regra de 25/09: só o botão desliga), mas para o
// despacho ele não existe. O painel tem de dizer isso em vez de um "Online"
// falso. O servidor avisa o motorista a partir dos mesmos 10 min
// (`drivers_sem_sinal_avisar`, cron de 2 em 2 min).
//
// Funções puras (testes em `test/sinal_motorista_test.dart`).
import 'hora_lisboa.dart';

/// Botão ligado e sem sinal há mais do que isto = "Ligado sem sinal".
const Duration kSemSinalApos = Duration(minutes: 10);

/// O motorista tem o botão ligado mas o telemóvel não manda sinal há mais de
/// [kSemSinalApos] (ou nunca mandou).
bool ligadoSemSinal({
  required bool ligado,
  DateTime? ultimoSinal,
  DateTime? agora,
}) {
  if (!ligado) return false;
  if (ultimoSinal == null) return true;
  final idade =
      (agora ?? DateTime.now()).toUtc().difference(ultimoSinal.toUtc());
  return idade > kSemSinalApos;
}

String _doisDigitos(int n) => n.toString().padLeft(2, '0');

/// "Ligado sem sinal desde 03:01" (hoje) ou "Ligado sem sinal desde 20/10 às
/// 03:01", sempre na hora de Lisboa.
String ligadoSemSinalTexto(DateTime? ultimoSinal, {DateTime? agora}) {
  if (ultimoSinal == null) return 'Ligado sem sinal (nunca enviou)';
  final p = paredeLisboa(ultimoSinal.toUtc());
  final hoje = paredeLisboa((agora ?? DateTime.now()).toUtc());
  final hora = '${_doisDigitos(p.hour)}:${_doisDigitos(p.minute)}';
  if (p.year == hoje.year && p.month == hoje.month && p.day == hoje.day) {
    return 'Ligado sem sinal desde $hora';
  }
  return 'Ligado sem sinal desde ${_doisDigitos(p.day)}/${_doisDigitos(p.month)} às $hora';
}
