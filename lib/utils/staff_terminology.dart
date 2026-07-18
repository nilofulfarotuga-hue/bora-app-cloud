/// Termo genérico para membros de equipa da vertical Serviços — "Barbeiro"
/// só quando o prestador é `category == 'barbershop'`; caso contrário
/// (cabeleireiro, manicure, esteticista, etc.) usa "Profissional".
class StaffTerminology {
  StaffTerminology._();

  static bool isBarbershop(String? category) => category == 'barbershop';

  static String singular(String? category) =>
      isBarbershop(category) ? 'Barbeiro' : 'Profissional';

  static String plural(String? category) =>
      isBarbershop(category) ? 'Barbeiros' : 'Profissionais';
}
