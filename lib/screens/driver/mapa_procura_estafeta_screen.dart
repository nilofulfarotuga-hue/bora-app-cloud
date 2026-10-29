import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/interruptores_app.dart';
import '../../services/mapa_procura_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Centro da Guarda: onde o mapa abre quando ainda não há dados.
const LatLng kCentroDaGuarda = LatLng(40.5373, -7.2680);

/// Lê as células. Trocável nos testes.
typedef LeitorDeProcura = Future<List<CelulaProcura>> Function();

/// Desenha o mapa. Trocável nos testes (o mapa a sério precisa do aparelho).
typedef ConstrutorDoMapa = Widget Function(
    BuildContext context, Set<Circle> zonas, LatLng centro);

Widget _mapaGoogle(BuildContext context, Set<Circle> zonas, LatLng centro) =>
    GoogleMap(
      initialCameraPosition: CameraPosition(target: centro, zoom: 13),
      circles: zonas,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );

/// Mapa simples de procura para estafetas (adendo 4 · item 10, 29/10/2026):
/// onde houve mais pedidos de loja, por hora do dia, nos últimos 30 dias. Só
/// leitura. Usa o ponto de recolha (a loja), nunca a morada de um cliente.
/// Interruptor `feature_mapa_procura_estafeta`.
class MapaProcuraEstafetaScreen extends StatefulWidget {
  const MapaProcuraEstafetaScreen({
    super.key,
    this.leitor,
    this.construirMapa = _mapaGoogle,
    this.horaAgora,
  });

  final LeitorDeProcura? leitor;
  final ConstrutorDoMapa construirMapa;

  /// Para testes: a hora atual de Lisboa.
  final int? horaAgora;

  @override
  State<MapaProcuraEstafetaScreen> createState() =>
      _MapaProcuraEstafetaScreenState();
}

class _MapaProcuraEstafetaScreenState extends State<MapaProcuraEstafetaScreen> {
  List<CelulaProcura> _todas = const [];
  bool _carregou = false;
  bool _ligado = true;
  String? _erro;
  int _hora = 12;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  /// Hora de Lisboa a partir do relógio do aparelho (UTC + 0 no inverno, +1 no
  /// verão): o servidor agrupa por hora de Lisboa, por isso converte-se.
  static int _horaDeLisboa() {
    final utc = DateTime.now().toUtc();
    // Horário de verão da Europa: último domingo de março a último de outubro.
    bool verao(DateTime d) {
      DateTime ultimoDomingo(int mes) {
        var dia = DateTime.utc(d.year, mes + 1, 0);
        while (dia.weekday != DateTime.sunday) {
          dia = dia.subtract(const Duration(days: 1));
        }
        return DateTime.utc(d.year, mes, dia.day, 1);
      }

      return !d.isBefore(ultimoDomingo(3)) && d.isBefore(ultimoDomingo(10));
    }

    return utc.add(Duration(hours: verao(utc) ? 1 : 0)).hour;
  }

  Future<void> _carregar() async {
    final ligado = await InterruptoresApp.instance
        .ligado(InterruptoresApp.mapaProcuraEstafeta);
    if (!ligado) {
      if (mounted) setState(() => _ligado = false);
      return;
    }
    try {
      final todas = await (widget.leitor ?? MapaProcuraService.ler)();
      if (!mounted) return;
      final agora = widget.horaAgora ?? _horaDeLisboa();
      setState(() {
        _todas = todas;
        _hora = horaInicial(pedidosPorHora(todas), agora);
        _carregou = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível ler o mapa agora. Tenta outra vez daqui a pouco.';
          _carregou = true;
        });
      }
    }
  }

  Set<Circle> _zonas(List<CelulaProcura> daHora) {
    final maximo = daHora.isEmpty ? 0 : daHora.first.pedidos;
    return {
      for (var i = 0; i < daHora.length; i++)
        Circle(
          circleId: CircleId('z$i'),
          center: LatLng(daHora[i].lat, daHora[i].lng),
          radius: 260,
          strokeWidth: 1,
          strokeColor: AppColors.primary,
          fillColor: AppColors.primary.withValues(
              alpha: 0.18 + 0.52 * intensidade(daHora[i].pedidos, maximo)),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final porHora = pedidosPorHora(_todas);
    final daHora = celulasDaHora(_todas, _hora);
    final centro = daHora.isNotEmpty
        ? LatLng(daHora.first.lat, daHora.first.lng)
        : kCentroDaGuarda;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Onde há mais pedidos'),
      body: !_ligado
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Este mapa está desligado neste momento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16)),
              ),
            )
          : !_carregou
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_erro!,
                            key: const Key('mapa_procura_erro'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16)),
                      ),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 56,
                          child: ListView.separated(
                            key: const Key('mapa_procura_horas'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            itemCount: 24,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, h) {
                              final tem = (porHora[h] ?? 0) > 0;
                              final ativa = h == _hora;
                              return Semantics(
                                button: true,
                                selected: ativa,
                                label: '${h.toString().padLeft(2, '0')}h',
                                child: InkWell(
                                  key: Key('hora_$h'),
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () => setState(() => _hora = h),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                        minWidth: 56, minHeight: 44),
                                    alignment: Alignment.center,
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: ativa
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                          color: ativa
                                              ? AppColors.primary
                                              : AppColors.divider),
                                    ),
                                    child: Text(
                                      '${h.toString().padLeft(2, '0')}h',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: tem
                                            ? FontWeight.w800
                                            : FontWeight.w400,
                                        color: ativa
                                            ? Colors.white
                                            : (tem
                                                ? AppColors.textPrimary
                                                : AppColors.textSubtle),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: widget.construirMapa(
                              context, _zonas(daHora), centro),
                        ),
                        Container(
                          width: double.infinity,
                          color: Colors.white,
                          padding: EdgeInsets.fromLTRB(16, 12, 16,
                              12 + MediaQuery.of(context).viewPadding.bottom),
                          child: Text(
                            daHora.isEmpty
                                ? 'Sem pedidos nesta hora nos últimos 30 dias.'
                                : 'Quanto mais forte a cor, mais pedidos de loja nesta hora nos últimos 30 dias. A zona é a da loja onde se recolhe.',
                            key: const Key('mapa_procura_legenda'),
                            style: const TextStyle(fontSize: 16, height: 1.3),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Atalho para o mapa, no cartão do topo do ecrã do estafeta. Some se o
/// painel admin desligar `feature_mapa_procura_estafeta`.
class BotaoMapaProcuraEstafeta extends StatefulWidget {
  const BotaoMapaProcuraEstafeta({super.key});

  @override
  State<BotaoMapaProcuraEstafeta> createState() =>
      _BotaoMapaProcuraEstafetaState();
}

class _BotaoMapaProcuraEstafetaState extends State<BotaoMapaProcuraEstafeta> {
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance
        .ligado(InterruptoresApp.mapaProcuraEstafeta)
        .then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    return InkWell(
      key: const Key('btn_mapa_procura'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const MapaProcuraEstafetaScreen())),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.local_fire_department_outlined,
                color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text('Onde há mais pedidos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
