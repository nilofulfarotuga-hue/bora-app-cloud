"""UMA CONTA, UMA PESSOA, TODOS OS PERFIS.

Corrige o mecanismo que deitava fora quem tem mais do que um papel: os tres
logins liam o campo unico `bora_role` do metadata e faziam signOut quando ele
nao batia certo com a porta por onde a pessoa entrou.
"""
import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")
p = r"lib\auth\auth_store.dart"
s = io.open(p, encoding="utf-8").read()


def troca(velho, novo, quantas=1):
    global s
    assert velho in s, "nao encontrei:\n" + velho[:160]
    s = s.replace(velho, novo, quantas)


# ── 1. CLIENTE — deixa de expulsar ─────────────────────────────────────────
troca(
    """      final meta = user.userMetadata ?? {};
      final metaRole = meta[_kRole] as String?;
      // Accept accounts with role 'client' OR legacy/demo accounts with no
      // role metadata. Reject anything explicitly tagged as driver/partner.
      if (metaRole != null && metaRole != 'client') {
        debugPrint(
            '[AuthStore] loginClientAsync → wrong role: "$metaRole" — signing out');
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return false;
      }
""",
    """      final meta = user.userMetadata ?? {};

      // UMA CONTA, UMA PESSOA, TODOS OS PERFIS (2026-08-29).
      //
      // Aqui estava a expulsão. Lia-se `bora_role` — que é UM campo só, o do
      // último papel usado — e fazia-se signOut a quem não dissesse 'client'.
      // Resultado, nos `auth_logs` de um cliente real a 28/08: login 200
      // seguido de logout no MESMO segundo, quatro vezes. A palavra-passe
      // estava certa; era a app que o deitava fora por ele também ser
      // estafeta.
      //
      // Cliente não tem aprovação nem candidatura: quem tem conta pode ser
      // cliente. Por isso não se pergunta nada — garante-se o papel e segue.
      // A verdade de quem é o quê vive em `user_roles`, que acumula; o
      // `bora_role` é só o modo em que a app está, e trocar de modo não é
      // motivo para pôr ninguém fora.
      try {
        await _supabase.rpc('add_client_role_to_me');
      } catch (e) {
        // Não bloqueia: sem rede, o papel entra na próxima vez. Expulsar por
        // causa disto seria repetir o defeito que se está a corrigir.
        debugPrint('[AuthStore] loginClientAsync → add_client_role_to_me: $e');
      }
""",
)

# ── 2. ESTAFETA — a verdade e ter perfil de estafeta, nao o metadata ───────
troca(
    """      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;
      if (role != 'driver') {
        debugPrint(
            '[AuthStore] loginDriverAsync → wrong role: "$role" (expected "driver") — signing out');
        // Sign out immediately so the non-driver session is not left active.
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return false;
      }

      debugPrint(
          '[AuthStore] loginDriverAsync → SUCCESS uid=${user.id} role=$role');
""",
    """      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;

      // UMA CONTA, TODOS OS PERFIS (2026-08-29). Era `role != 'driver'` →
      // signOut. Quem se candidatou a estafeta e depois usou a app como
      // cliente ficava com `bora_role: 'client'` e deixava de conseguir
      // entrar na SUA PRÓPRIA área de estafeta.
      //
      // O que decide é ter perfil de estafeta, não o modo em que a app
      // ficou da última vez. A linha em `drivers` é lida logo a seguir; se
      // não existir, aí sim não é estafeta — e devolve-se falso com a sessão
      // MANTIDA, para o ecrã poder dizer "ainda não és estafeta,
      // candidata-te" em vez de a pessoa levar com um erro de palavra-passe.
      if (role != 'driver') {
        debugPrint(
            '[AuthStore] loginDriverAsync → bora_role="$role"; confirmo pelo perfil');
      }

      debugPrint(
          '[AuthStore] loginDriverAsync → SUCCESS uid=${user.id} role=$role');
""",
)

# ── 3. PARCEIRO — idem ─────────────────────────────────────────────────────
troca(
    """      final meta = user.userMetadata ?? {};
      if ((meta[_kRole] as String?) != 'partner') return false;
""",
    """      final meta = user.userMetadata ?? {};

      // UMA CONTA, TODOS OS PERFIS (2026-08-29). Era `!= 'partner'` → falso,
      // e o lojista que tivesse feito um pedido como cliente deixava de poder
      // entrar na sua própria loja. Confirma-se pelo papel em `user_roles`,
      // que acumula, e não pelo modo em que a app ficou.
      if ((meta[_kRole] as String?) != 'partner') {
        final tem = await _temPapelNoServidor('partner');
        if (!tem) {
          debugPrint('[AuthStore] loginPartnerAsync → sem papel de parceiro');
          return false;
        }
        debugPrint('[AuthStore] loginPartnerAsync → papel confirmado em user_roles');
      }
""",
)

# ── 4. RESTAURO BIOMETRICO — a mesma tolerancia ────────────────────────────
troca(
    """      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;
      // Contas legadas/demo de cliente podem não ter role nos metadados —
      // mesma tolerância do loginClientAsync.
      final roleOk =
          role == expectedRole || (expectedRole == 'client' && role == null);
      if (!roleOk) {""",
    """      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;
      // Contas legadas/demo de cliente podem não ter role nos metadados —
      // mesma tolerância do loginClientAsync.
      //
      // MULTI-PERFIL (2026-08-29): o `bora_role` é o modo em que a app ficou,
      // não a lista do que a pessoa é. Quem tem o papel em `user_roles` entra
      // pela biometria como entra pela palavra-passe.
      var roleOk =
          role == expectedRole || (expectedRole == 'client' && role == null);
      if (!roleOk) {
        roleOk = await _temPapelNoServidor(expectedRole);
        if (roleOk) {
          debugPrint(
              'AuthStore: restoreSession — "$expectedRole" confirmado em user_roles');
        }
      }
      if (!roleOk) {""",
)

# ── 5. O ajudante que le os papeis do servidor ─────────────────────────────
troca(
    """  // ─── Troca de papel (multi-papel) ──────────────────────────────────────────
""",
    """  /// Os papéis desta pessoa, lidos do servidor (`my_roles`).
  ///
  /// `user_roles` é a única fonte que aguenta acumulação — uma linha por
  /// papel. O `user_metadata.bora_role` guarda só o modo em que a app está e
  /// **nunca** deve ser usado para decidir se alguém pode entrar.
  Future<bool> _temPapelNoServidor(String papel) async {
    try {
      final res = await _supabase.rpc('my_roles');
      final lista = (res as List?) ?? const [];
      return lista.any((e) => (e as Map)['role'] == papel);
    } catch (e) {
      debugPrint('AuthStore: my_roles falhou => $e');
      // Na dúvida NÃO se expulsa. Um erro de rede não pode fechar a porta a
      // quem tem o papel — foi assim que se perdeu um cliente real.
      return false;
    }
  }

  // ─── Troca de papel (multi-papel) ──────────────────────────────────────────
""",
)

# ── 6. Trocar para estafeta sem ter os dados carregados neste aparelho ─────
troca(
    """      case AuthRole.driver:
        final account = _driversByEmail[email];
        if (account == null) return false;
        _currentDriver = account;""",
    """      case AuthRole.driver:
        // Se este aparelho nunca carregou os dados de estafeta (matrícula,
        // veículo) vai buscá-los à base em vez de recusar a troca. Recusar
        // obrigava a pessoa a sair e a escrever a palavra-passe outra vez —
        // que é exactamente o que esta troca existe para evitar.
        final account =
            _driversByEmail[email] ?? await _carregarEstafetaDaBase(email);
        if (account == null) return false;
        _driversByEmail[email] = account;
        _currentDriver = account;""",
)

troca(
    """  // ─── Logout ───────────────────────────────────────────────────────────────
""",
    """  /// Monta a conta de estafeta a partir da base, para a troca de perfil
  /// funcionar num aparelho onde só se entrou como cliente.
  Future<DriverAccount?> _carregarEstafetaDaBase(String email) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _supabase
          .from('drivers')
          .select('name, phone, vehicle_type, license_plate, approval_status')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      final vt = VehicleType.values.firstWhere(
        (v) => v.dbValue == (row['vehicle_type'] as String? ?? ''),
        orElse: () => VehicleType.motorcycle,
      );
      return DriverAccount(
        name: (row['name'] as String?) ?? '',
        phone: (row['phone'] as String?) ?? '',
        email: email,
        password: '',
        vehicleType: vt,
        licensePlate: (row['license_plate'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('AuthStore: _carregarEstafetaDaBase => $e');
      return null;
    }
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
""",
)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("auth_store corrigido")
