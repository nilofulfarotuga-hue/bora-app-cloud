"""Nenhum ecra fica preso a espera de uma permissao."""
import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")
p = r"lib\screens\driver_home_screen.dart"
s = io.open(p, encoding="utf-8").read()


def troca(velho, novo):
    global s
    assert velho in s, "nao encontrei:\n" + velho[:160]
    s = s.replace(velho, novo, 1)


# ── 1. O pedido de posicao passa a ter fim ────────────────────────────────
troca(
    """  /// One-shot position request so the idle map opens centred on the driver's
  /// real GPS coordinates. Runs in parallel with the stream subscription.
  Future<void> _fetchInitialGpsCenter() async {
    try {
      // Quick service + permission check before issuing a hardware request.
      if (!await Geolocator.isLocationServiceEnabled()) {
        _resolveGpsFallback();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _resolveGpsFallback();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final gps = LatLng(pos.latitude, pos.longitude);
      setState(() => _initialGpsCenter = gps);
      // Propagate to DriverStore so the idle-map marker is also correct.
      final driverStore = context.read<DriverStore>();
      driverStore.updateDriverLocation(driverStore.currentDriverId, gps);
    } catch (_) {
      // Hardware unavailable — resolve with DriverStore fallback.
      _resolveGpsFallback();
    }
  }""",
    """  /// One-shot position request so the idle map opens centred on the driver's
  /// real GPS coordinates. Runs in parallel with the stream subscription.
  ///
  /// NENHUM ECRA FICA PRESO (2026-08-29). Isto tinha `try/catch` e um recurso
  /// que centrava na Guarda — parecia coberto. Nao estava: no browser, e num
  /// telemovel onde a pessoa nao responde ao pedido de permissao,
  /// `getCurrentPosition` **nao devolve e nao rebenta**. Fica pendurado, o
  /// `catch` nunca corre, `_initialGpsCenter` nunca deixa de ser nulo, e o
  /// ecra do estafeta roda um carregador para sempre, sem uma palavra a dizer
  /// porque. Quem instala, recusa o GPS e ve isto, desinstala.
  ///
  /// Agora ha limite de tempo em cada espera, e a recusa e tratada como
  /// recusa — com explicacao — em vez de silencio.
  Future<void> _fetchInitialGpsCenter() async {
    try {
      final ligado = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!ligado) {
        _resolveGpsFallback(recusado: true);
        return;
      }
      var permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5),
              onTimeout: () => LocationPermission.denied);
      if (permission == LocationPermission.denied) {
        // O pedido de permissao espera pela pessoa. Se ela nao responder, nao
        // se fica aqui: segue-se sem posicao e ela pode tentar depois.
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 30),
                onTimeout: () => LocationPermission.denied);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _resolveGpsFallback(recusado: true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final gps = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _initialGpsCenter = gps;
        _gpsRecusado = false;
      });
      // Propagate to DriverStore so the idle-map marker is also correct.
      final driverStore = context.read<DriverStore>();
      driverStore.updateDriverLocation(driverStore.currentDriverId, gps);
    } catch (e) {
      // Sem sinal ou demorou de mais: nao e recusa, e o mapa abre no centro
      // da Guarda. Nao se prende a pessoa por causa disto.
      debugPrint('[DriverHome] GPS inicial falhou => $e');
      _resolveGpsFallback();
    }
  }

  /// A pessoa recusou a localizacao (ou tem o servico desligado)?
  bool _gpsRecusado = false;

  /// Tentar outra vez, do botao do ecra de explicacao.
  Future<void> _tentarGpsOutraVez() async {
    setState(() {
      _gpsRecusado = false;
      _initialGpsCenter = null;
    });
    await _fetchInitialGpsCenter();
  }""",
)

troca(
    """  void _resolveGpsFallback() {
    if (!mounted) return;
    final driverStore = context.read<DriverStore>();
    final fallback = driverStore.currentDriver?.location;
    if (fallback != null) {
      setState(() => _initialGpsCenter = fallback);
    } else {
      // Último recurso — centro padrão.
      setState(() => _initialGpsCenter = kGuardaCenter);
    }
  }""",
    """  void _resolveGpsFallback({bool recusado = false}) {
    if (!mounted) return;
    if (recusado) {
      // Recusa e outra coisa de "sem sinal": merece explicacao, nao um mapa
      // no sitio errado sem dizer porque.
      setState(() => _gpsRecusado = true);
      return;
    }
    final driverStore = context.read<DriverStore>();
    final fallback = driverStore.currentDriver?.location;
    if (fallback != null) {
      setState(() => _initialGpsCenter = fallback);
    } else {
      // Último recurso — centro padrão.
      setState(() => _initialGpsCenter = kGuardaCenter);
    }
  }""",
)

# ── 2. O ecra que explica, em vez do carregador eterno ────────────────────
troca(
    """    // Block rendering until the one-shot GPS fetch completes so the map
    // never opens at the default fallback coordinates.
    if (_initialGpsCenter == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }""",
    """    // A localizacao foi recusada, ou o servico esta desligado: diz-se porque
    // e da-se caminho. Antes de 2026-08-29 isto era um carregador para sempre.
    if (_gpsRecusado) {
      return _SemLocalizacao(
        onTentarOutraVez: _tentarGpsOutraVez,
        onAbrirDefinicoes: () async {
          // Em Android abre as definicoes de localizacao do sistema; se o que
          // esta recusado e a permissao da app, as da app.
          try {
            await Geolocator.openLocationSettings();
          } catch (_) {
            try {
              await Geolocator.openAppSettings();
            } catch (_) {}
          }
        },
      );
    }

    // Block rendering until the one-shot GPS fetch completes so the map
    // never opens at the default fallback coordinates. Ja nao fica preso: o
    // pedido de posicao tem limite de tempo e cai sempre para algum lado.
    if (_initialGpsCenter == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }""",
)

# ── 3. O widget da explicacao ─────────────────────────────────────────────
s = s.rstrip("\n") + '''

/// O ecrã que aparece quando a localização está recusada ou desligada.
///
/// Existe porque o que estava lá era um carregador a rodar, sem erro, sem
/// explicação e sem fim. Quem instalasse a app, recusasse o GPS e visse isto,
/// desinstalava — e com razão.
class _SemLocalizacao extends StatelessWidget {
  const _SemLocalizacao({
    required this.onTentarOutraVez,
    required this.onAbrirDefinicoes,
  });

  final Future<void> Function() onTentarOutraVez;
  final Future<void> Function() onAbrirDefinicoes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.location_off_outlined,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 20),
              const Text(
                'Precisamos de saber onde estás',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              const Text(
                'O mapa dos pedidos mostra o que está perto de ti, e sem a '
                'localização não conseguimos saber o que te fica à mão.\\n\\n'
                'Podes ligar a localização nas definições do telemóvel e '
                'voltar aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: onTentarOutraVez,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar outra vez'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: onAbrirDefinicoes,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir as definições'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'''

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("driver_home_screen corrigido")
