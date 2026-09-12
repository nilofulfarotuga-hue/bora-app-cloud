import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// MULTI-PAPEL — resumo dos papéis do utilizador atual.
///
/// Nasceu para o convite cruzado estafeta⇄limpeza. Desde 2026-08-29 serve
/// também a lavagem e é o que enche a porta "Quero trabalhar no Bora": diz o
/// que a pessoa já é, o que tem em análise, e o que ainda pode ser — para
/// nunca lhe voltar a pedir os dados que já deu.
///
/// Uma leitura única (`my_roles_summary` RPC). Sem estado; chamar on demand.
class RolesSummary {
  RolesSummary({
    required this.hasDriver,
    required this.driverStatus,
    required this.hasCleaner,
    required this.cleanerStatus,
    required this.hasWasher,
    required this.washerStatus,
    required this.driverProfile,
    required this.cleanerProfile,
    required this.washerProfile,
  });

  final bool hasDriver;
  final String? driverStatus; // 'pending' | 'approved' | 'rejected' | null
  final bool hasCleaner;
  final String? cleanerStatus;
  final bool hasWasher;
  final String? washerStatus;
  final Map<String, dynamic>? driverProfile; // name/phone/email/nif/photo_url
  final Map<String, dynamic>? cleanerProfile;
  final Map<String, dynamic>? washerProfile;

  bool get driverApproved => driverStatus == 'approved';
  bool get cleanerApproved => cleanerStatus == 'approved';
  bool get washerApproved => washerStatus == 'approved';
  bool get driverPending => driverStatus == 'pending';
  bool get cleanerPending => cleanerStatus == 'pending';
  bool get washerPending => washerStatus == 'pending';

  /// A pessoa já é alguma coisa no Bora além de cliente?
  bool get temAlgumPapel => hasDriver || hasCleaner || hasWasher;

  /// Os dados comuns (nome, telemóvel, email, NIF, foto) de QUALQUER papel que
  /// a pessoa já tenha — para pré-preencher a candidatura seguinte.
  ///
  /// A ordem não é arbitrária: primeiro o perfil de estafeta, que é o mais
  /// completo (passou por documentos e veículo), depois os outros. Devolve
  /// null se não houver nada — e aí a candidatura pede tudo, como a primeira.
  Map<String, dynamic>? get dadosJaConhecidos =>
      driverProfile ?? cleanerProfile ?? washerProfile;

  factory RolesSummary.fromJson(Map<String, dynamic> j) => RolesSummary(
        hasDriver: j['has_driver'] == true,
        driverStatus: j['driver_status'] as String?,
        hasCleaner: j['has_cleaner'] == true,
        cleanerStatus: j['cleaner_status'] as String?,
        hasWasher: j['has_washer'] == true,
        washerStatus: j['washer_status'] as String?,
        driverProfile: (j['driver_profile'] as Map?)?.cast<String, dynamic>(),
        cleanerProfile: (j['cleaner_profile'] as Map?)?.cast<String, dynamic>(),
        washerProfile: (j['washer_profile'] as Map?)?.cast<String, dynamic>(),
      );

  static RolesSummary empty() => RolesSummary(
        hasDriver: false,
        driverStatus: null,
        hasCleaner: false,
        cleanerStatus: null,
        hasWasher: false,
        washerStatus: null,
        driverProfile: null,
        cleanerProfile: null,
        washerProfile: null,
      );
}

class RolesService {
  static Future<RolesSummary> mySummary() async {
    try {
      final res = await Supabase.instance.client.rpc('my_roles_summary');
      if (res is Map) {
        return RolesSummary.fromJson(res.cast<String, dynamic>());
      }
      return RolesSummary.empty();
    } catch (e) {
      debugPrint('RolesService.mySummary error => $e');
      return RolesSummary.empty();
    }
  }
}

/// Estado que um card de convite/troca de papel deve mostrar, derivado do
/// estado do OUTRO papel. Função pura → testável sem Supabase.
enum CrossRoleCardState {
  invite, // não tem o outro papel (ou foi rejeitado) → convidar a candidatar-se
  pending, // candidatura ao outro papel em análise
  active, // já tem o outro papel aprovado → abrir / trocar
}

CrossRoleCardState crossRoleStateFor(String? otherStatus) {
  switch (otherStatus) {
    case 'approved':
      return CrossRoleCardState.active;
    case 'pending':
      return CrossRoleCardState.pending;
    default: // null (não existe) ou 'rejected' → convidar (recandidatar)
      return CrossRoleCardState.invite;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// A PORTA "QUERO TRABALHAR NO BORA"
// ════════════════════════════════════════════════════════════════════════════

/// Uma actividade que se pode escolher na porta de entrada.
///
/// Os identificadores são os mesmos papéis de `user_roles` — nunca uma lista
/// paralela inventada aqui. Foi assim que a caixa do prestador se desencontrou
/// da base em Agosto.
class AtividadeDeTrabalho {
  const AtividadeDeTrabalho({
    required this.papel,
    required this.titulo,
    required this.descricao,
    required this.estado,
  });

  final String papel; // 'driver' | 'delivery' | 'cleaner' | 'washer'
  final String titulo;
  final String descricao;
  final CrossRoleCardState estado;

  bool get jaFaz => estado == CrossRoleCardState.active;
  bool get emAnalise => estado == CrossRoleCardState.pending;

  /// O que a linha diz à direita, em PT-PT.
  String get rotuloDeEstado => switch (estado) {
        CrossRoleCardState.active => 'Já fazes',
        CrossRoleCardState.pending => 'Em análise',
        CrossRoleCardState.invite => 'Candidatar-me',
      };
}

/// As quatro actividades, na ordem em que se lêem, com o estado real de cada
/// uma. Função pura → testável sem Supabase.
///
/// `driver` e `delivery` partilham a mesma candidatura (a tabela `drivers`) e
/// por isso partilham estado: quem já é estafeta não se candidata outra vez
/// para passar a fazer corridas — liga o interruptor na caixa dos papéis. O
/// que muda entre os dois é o veículo e, nas corridas, o certificado do IMT.
List<AtividadeDeTrabalho> atividadesDisponiveis(RolesSummary r) => [
      AtividadeDeTrabalho(
        papel: 'delivery',
        titulo: 'Entregas',
        descricao: 'Levar comida, compras e encomendas. De bicicleta, mota '
            'ou carro.',
        estado: crossRoleStateFor(r.driverStatus),
      ),
      AtividadeDeTrabalho(
        papel: 'driver',
        titulo: 'Corridas de passageiros',
        descricao: 'Levar pessoas de um lado ao outro. Precisas do '
            'certificado TVDE do IMT.',
        estado: crossRoleStateFor(r.driverStatus),
      ),
      AtividadeDeTrabalho(
        papel: 'cleaner',
        titulo: 'Limpeza',
        descricao: 'Limpezas de casas e escritórios. Recebes 85% de cada '
            'limpeza.',
        estado: crossRoleStateFor(r.cleanerStatus),
      ),
      AtividadeDeTrabalho(
        papel: 'washer',
        titulo: 'Lavagem de carros',
        descricao: 'Lavas o carro onde o cliente estiver e devolves.',
        estado: crossRoleStateFor(r.washerStatus),
      ),
    ];
