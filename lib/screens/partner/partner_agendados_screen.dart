/// AGENDAR PEDIDOS (item 5 do adendo 5, 29/10/2026) — o separador "Agendados"
/// do parceiro: os pedidos com hora marcada, do mais próximo para o mais
/// distante, com "faltam X min". Os que estão a 30 minutos ou menos ficam
/// destacados e tocam o som do alerta UMA vez (enquanto este ecrã estiver
/// aberto; o aviso com a app fechada vem do servidor — proposta 03).
///
/// Só se chega aqui com o interruptor `scheduled_orders_enabled` ligado (o
/// atalho do painel esconde-se desligado). Aceitar/recusar continua no ecrã
/// principal: aqui é para ver o que vem aí.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/restaurant_model.dart';
import '../../services/agendar_pedido.dart';
import '../../services/agendar_pedido_service.dart';
import '../../services/sound_service.dart';
import '../../utils/hora_lisboa.dart';

class PartnerAgendadosScreen extends StatefulWidget {
  const PartnerAgendadosScreen({
    super.key,
    required this.restaurant,
    this.api,
    this.relogio,
    this.aoAvisar,
    this.intervalo = const Duration(seconds: 30),
  });

  final RestaurantModel restaurant;

  /// Só para testes: troca o servidor por uma porta de mentira.
  final AgendarPedidoApi? api;

  /// Só para testes: um relógio fixo.
  final DateTime Function()? relogio;

  /// O que fazer quando um pedido entra nos 30 minutos (por defeito toca o alerta).
  final void Function(PedidoAgendado pedido)? aoAvisar;

  /// De quanto em quanto tempo o ecrã refaz as contas (e, de 4 em 4, vai ao servidor).
  final Duration intervalo;

  @override
  State<PartnerAgendadosScreen> createState() => _PartnerAgendadosScreenState();
}

class _PartnerAgendadosScreenState extends State<PartnerAgendadosScreen> {
  late final AgendarPedidoApi _api = widget.api ?? AgendarPedidoSupabase();
  List<PedidoAgendado> _pedidos = const [];
  bool _carregando = true;
  String? _erro;
  Timer? _timer;
  int _ticks = 0;
  final Set<String> _avisados = <String>{};
  SoundService? _som;

  DateTime _agora() => (widget.relogio ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(widget.intervalo, (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks % 4 == 0) {
        _carregar(silencioso: true);
      } else {
        setState(_verificarAvisos);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final lista = await _api.pedidosDoParceiro(widget.restaurant.id);
      if (!mounted) return;
      setState(() {
        _pedidos = lista;
        _carregando = false;
        _erro = null;
        _verificarAvisos();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        if (!silencioso || _pedidos.isEmpty) {
          _erro = 'Não consegui carregar os pedidos agendados. Puxa para atualizar.';
        }
      });
    }
  }

  /// Marca como avisados (e dispara o som) os pedidos que acabaram de entrar nos 30 min.
  void _verificarAvisos() {
    final agora = _agora();
    for (final p in _pedidos) {
      if (_avisados.contains(p.id)) continue;
      if (!deviaAvisarParceiro(p.quando, agora)) continue;
      _avisados.add(p.id);
      if (widget.aoAvisar != null) {
        widget.aoAvisar!(p);
      } else {
        unawaited((_som ??= SoundService()).playOnce());
      }
    }
  }

  String _metodo(PedidoAgendado p) {
    final m = switch (p.metodo) {
      'cash' => 'Dinheiro',
      'card' => 'Cartão',
      'mbway' => 'MB Way',
      final outro => outro ?? '—',
    };
    return p.pagamento == 'paid' ? '$m · pago' : m;
  }

  String _euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    final agora = _agora();
    final urgentes =
        _pedidos.where((p) => deviaAvisarParceiro(p.quando, agora)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos agendados')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                key: const Key('agendados-lista'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_erro!,
                          key: const Key('agendados-erro'),
                          style: const TextStyle(color: AppColors.error)),
                    ),
                  if (urgentes.isNotEmpty)
                    Container(
                      key: const Key('agendados-alerta'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm, color: AppColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              urgentes.length == 1
                                  ? 'Pedido agendado: ${faltaTexto(urgentes.first.quando, agora)}. Comece a preparar.'
                                  : '${urgentes.length} pedidos agendados a 30 minutos ou menos. Comece a preparar.',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_pedidos.isEmpty && _erro == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Nenhum pedido agendado de momento.',
                        key: Key('agendados-vazio'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ..._porDia(agora),
                ],
              ),
            ),
    );
  }

  List<Widget> _porDia(DateTime agora) {
    final out = <Widget>[];
    DateTime? diaAtual;
    for (final p in _pedidos) {
      final parede = paredeLisboa(p.quando);
      final dia = DateTime.utc(parede.year, parede.month, parede.day);
      if (diaAtual != dia) {
        diaAtual = dia;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            _tituloDoDia(dia, agora),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ));
      }
      out.add(_cartao(p, agora));
    }
    return out;
  }

  String _tituloDoDia(DateTime dia, DateTime agora) {
    final hoje = paredeLisboa(agora);
    final diff = dia.difference(DateTime.utc(hoje.year, hoje.month, hoje.day)).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Amanhã';
    const nomes = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
    return '${nomes[dia.weekday - 1]} ${dataCurta(dia)}';
  }

  Widget _cartao(PedidoAgendado p, DateTime agora) {
    final urgente = deviaAvisarParceiro(p.quando, agora);
    final parede = paredeLisboa(p.quando);
    final inicio = DateTime.utc(parede.year, parede.month, parede.day, parede.hour, parede.minute);
    final janela = JanelaAgendada(
      inicio: inicio,
      fim: inicio.add(const Duration(minutes: kAgendarJanelaMinutos)),
    );
    final cor = urgente ? AppColors.warning : AppColors.divider;
    return Card(
      key: Key('agendado-${p.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor, width: urgente ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(janela.horas,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    faltaTexto(p.quando, agora),
                    key: Key('agendado-falta-${p.id}'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: urgente ? AppColors.warning : AppColors.textSecondary,
                    ),
                  ),
                ),
                Text('#${p.codigo}',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 6),
            if ((p.clienteNome ?? '').trim().isNotEmpty)
              Text(p.clienteNome!, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (p.itens.isNotEmpty) Text(p.itens),
            const SizedBox(height: 4),
            Text('${_euros(p.totalEur)} · ${_metodo(p)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            if ((p.notas ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.notas!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 6),
            Text(
              p.aceite
                  ? 'Aceite${p.prepMin != null ? ' · preparação ${p.prepMin} min' : ''}'
                  : 'Por aceitar — aceita no ecrã principal',
              key: Key('agendado-estado-${p.id}'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.aceite ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
