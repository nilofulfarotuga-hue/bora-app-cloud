import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// MULTI-PAPEL — resumo dos papéis do utilizador atual (estafeta ⇄ limpeza).
/// Uma leitura única (`my_roles_summary` RPC) que serve os cards de convite e
/// o pré-preenchimento da candidatura cruzada. Sem estado; chamar on demand.
class RolesSummary {
  RolesSummary({
    required this.hasDriver,
    required this.driverStatus,
    required this.hasCleaner,
    required this.cleanerStatus,
    required this.driverProfile,
    required this.cleanerProfile,
  });

  final bool hasDriver;
  final String? driverStatus; // 'pending' | 'approved' | 'rejected' | null
  final bool hasCleaner;
  final String? cleanerStatus;
  final Map<String, dynamic>? driverProfile; // name/phone/email/nif/photo_url
  final Map<String, dynamic>? cleanerProfile;

  bool get driverApproved => driverStatus == 'approved';
  bool get cleanerApproved => cleanerStatus == 'approved';
  bool get driverPending => driverStatus == 'pending';
  bool get cleanerPending => cleanerStatus == 'pending';

  factory RolesSummary.fromJson(Map<String, dynamic> j) => RolesSummary(
        hasDriver: j['has_driver'] == true,
        driverStatus: j['driver_status'] as String?,
        hasCleaner: j['has_cleaner'] == true,
        cleanerStatus: j['cleaner_status'] as String?,
        driverProfile: (j['driver_profile'] as Map?)?.cast<String, dynamic>(),
        cleanerProfile: (j['cleaner_profile'] as Map?)?.cast<String, dynamic>(),
      );

  static RolesSummary empty() => RolesSummary(
        hasDriver: false,
        driverStatus: null,
        hasCleaner: false,
        cleanerStatus: null,
        driverProfile: null,
        cleanerProfile: null,
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
