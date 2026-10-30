/// PEDIDOS AGENDADOS — painel do Danilo (item 5 do adendo 5, 29/10/2026). PT-BR.
///
/// Mostra o interruptor (liga/desliga), o máximo de dias e a antecedência mínima,
/// e a lista dos pedidos com hora marcada de todas as lojas. Desde 30/10/2026
/// também mercados e lojas não parceiras: filtro Todos / Parceiros / Não
/// parceiros e etiqueta em cada linha (`is_partner_store` do servidor).
///
/// O interruptor nasce DESLIGADO. O servidor só deixa ligar depois de o revisor
/// independente dizer SIM (`scheduled_orders_revisor_ok`), porque o agendamento
/// mexe na hora em que o estafeta é chamado. Desligar é sempre possível.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/agendar_pedido.dart';
import '../../services/agendar_pedido_service.dart';
import '_admin_rpc_errors.dart';

/// Filtro da lista do painel.
enum FiltroAgendados { todos, parceiros, naoParceiros }

/// Os pedidos que o filtro deixa ver. Um pedido sem a marca do servidor
/// (`parceiro == null`) só aparece em "Todos".
List<PedidoAgendado> filtrarAgendados(List<PedidoAgendado> todos, FiltroAgendados f) =>
    switch (f) {
      FiltroAgendados.todos => todos,
      FiltroAgendados.parceiros => [for (final p in todos) if (p.parceiro == true) p],
      FiltroAgendados.naoParceiros => [for (final p in todos) if (p.parceiro == false) p],
    };

class AdminPedidosAgendadosScreen extends StatefulWidget {
  const AdminPedidosAgendadosScreen({super.key, this.api, this.relogio});

  /// Só para testes: troca o servidor por uma porta de mentira.
  final AgendarPedidoAdminApi? api;

  /// Só para testes: um relógio fixo.
  final DateTime Function()? relogio;

  @override
  State<AdminPedidosAgendadosScreen> createState() => _AdminPedidosAgendadosScreenState();
}

class _AdminPedidosAgendadosScreenState extends State<AdminPedidosAgendadosScreen> {
  late final AgendarPedidoAdminApi _api = widget.api ?? AgendarPedidoAdminSupabase();
  ConfigAgendarAdmin _cfg = const ConfigAgendarAdmin();
  List<PedidoAgendado> _pedidos = const [];
  FiltroAgendados _filtro = FiltroAgendados.todos;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  static const _diasPossiveis = <int>[3, 5, 7, 10, 14];
  static const _antecedencias = <int>[30, 60, 90, 120, 180];

  DateTime _agora() => (widget.relogio ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _msg(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  String _erroLegivel(Object e) {
    if (e is PostgrestException && e.message.startsWith('revisor_em_falta')) {
      return 'O revisor independente ainda não disse SIM. Sem isso não dá para ligar.';
    }
    return humanizeAdminRpcError(e);
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final cfg = await _api.config();
      final lista = await _api.pedidos();
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _pedidos = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _erroLegivel(e);
        _carregando = false;
      });
    }
  }

  Future<bool> _confirmar(String titulo, String texto, {String ok = 'Confirmar'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _definir(String chave, Object valor) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final nova = await _api.definir(chave, valor);
      if (!mounted) return;
      setState(() => _cfg = nova);
    } catch (e) {
      _msg(_erroLegivel(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _ligar(bool ligar) async {
    if (ligar &&
        !await _confirmar(
          'Ligar os pedidos agendados?',
          'Os clientes passam a poder agendar pedidos (até ${_cfg.maxDias} dias) mesmo com a loja '
              'fechada, e o estafeta é chamado perto da hora marcada. Só ligue depois de o revisor '
              'independente dizer SIM e de as propostas do servidor estarem aplicadas.',
          ok: 'Ligar',
        )) {
      return;
    }
    await _definir('scheduled_orders_enabled', ligar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos agendados')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!,
                            key: const Key('agendados-admin-erro'),
                            style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _cartaoControlos(),
                      const SizedBox(height: 8),
                      _secaoLista(),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoControlos() {
    final podeLigar = _cfg.revisorOk || _cfg.ligado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('agendados-interruptor'),
              title: const Text('Pedidos agendados ligados'),
              subtitle: Text(
                _cfg.ligado
                    ? 'LIGADO: o cliente pode agendar (dia + janela de 30 min), mesmo com a loja fechada.'
                    : 'DESLIGADO: nada muda para os clientes nem para os parceiros.',
              ),
              value: _cfg.ligado,
              onChanged: (_ocupado || !podeLigar) ? null : _ligar,
            ),
            if (!_cfg.revisorOk && !_cfg.ligado)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Falta o SIM do revisor independente. Como o agendamento mexe na hora em que o '
                  'estafeta é chamado, o servidor só deixa ligar depois dele.',
                  key: Key('agendados-sem-revisor'),
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ),
            ListTile(
              title: const Text('Máximo de dias à frente'),
              trailing: DropdownButton<int>(
                key: const Key('agendados-dias'),
                value: _diasPossiveis.contains(_cfg.maxDias) ? _cfg.maxDias : null,
                items: [
                  for (final d in _diasPossiveis)
                    DropdownMenuItem(value: d, child: Text('$d dias')),
                ],
                onChanged: _ocupado
                    ? null
                    : (v) {
                        if (v != null) _definir('scheduled_orders_max_days', v);
                      },
              ),
            ),
            ListTile(
              title: const Text('Antecedência mínima'),
              subtitle: const Text('Tempo entre o pedido e o início da janela escolhida'),
              trailing: DropdownButton<int>(
                key: const Key('agendados-antecedencia'),
                value: _antecedencias.contains(_cfg.antecedenciaMin) ? _cfg.antecedenciaMin : null,
                items: [
                  for (final m in _antecedencias)
                    DropdownMenuItem(value: m, child: Text('$m min')),
                ],
                onChanged: _ocupado
                    ? null
                    : (v) {
                        if (v != null) _definir('scheduled_orders_min_lead_minutes', v);
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Agendados à frente: ${_cfg.total} · nas próximas 24 h: ${_cfg.proximas24h}',
                key: const Key('agendados-contagem'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoLista() {
    if (_pedidos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum pedido agendado no momento.',
              key: Key('agendados-admin-vazio'),
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final agora = _agora();
    final visiveis = filtrarAgendados(_pedidos, _filtro);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SegmentedButton<FiltroAgendados>(
            key: const Key('agendados-filtro'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: FiltroAgendados.todos,
                label: Text('Todos', key: Key('agendados-filtro-todos')),
              ),
              ButtonSegment(
                value: FiltroAgendados.parceiros,
                label: Text('Parceiros', key: Key('agendados-filtro-parceiros')),
              ),
              ButtonSegment(
                value: FiltroAgendados.naoParceiros,
                label: Text('Não parceiros', key: Key('agendados-filtro-nao-parceiros')),
              ),
            ],
            selected: {_filtro},
            onSelectionChanged: (s) => setState(() => _filtro = s.first),
          ),
        ),
        if (visiveis.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum pedido agendado neste filtro.',
                  key: Key('agendados-admin-vazio-filtro'),
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        for (final p in visiveis) _linha(p, agora),
      ],
    );
  }

  /// Etiqueta de cada linha: "Parceiro" (verde) ou "Não parceiro" (cinza),
  /// com "Mercado/loja" quando é compra em loja.
  Widget _etiqueta(PedidoAgendado p) {
    final parceiro = p.parceiro;
    if (parceiro == null) return const SizedBox.shrink();
    final loja = p.tipoServico == 'storeShopping' ? ' · Mercado/loja' : '';
    final cor = parceiro ? AppColors.primaryDark : AppColors.textSecondary;
    return Container(
      key: Key('agendado-etiqueta-${p.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${parceiro ? 'Parceiro' : 'Não parceiro'}$loja',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor),
      ),
    );
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

  String _estado(PedidoAgendado p) => switch (p.estado) {
        'created' => 'Aguardando a loja aceitar',
        // Não parceiro: o servidor segura o pedido em "preparing", sem
        // estafeta, até 30 min antes da hora marcada.
        'preparing' when p.parceiro == false => 'Aguardando a hora (sem estafeta ainda)',
        'preparing' => 'Aceito, em preparo',
        'callingDriver' => 'Chamando estafeta',
        'driverAccepted' => 'Estafeta a caminho da loja',
        'pickedUp' || 'onTheWay' => 'A caminho do cliente',
        final outro => outro,
      };

  Widget _linha(PedidoAgendado p, DateTime agora) {
    final janela = janelaDoInstante(p.quando);
    final total = '${p.totalEur.toStringAsFixed(2).replaceAll('.', ',')} €';
    return Card(
      key: Key('agendado-admin-${p.id}'),
      child: ListTile(
        title: Text('${p.lojaNome ?? 'Loja'} · ${diaComData(janela.dia)} ${janela.horas}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${faltaTexto(p.quando, agora)} · ${_estado(p)}\n'
              '${(p.clienteNome ?? '').trim().isEmpty ? 'Cliente' : p.clienteNome} · $total · ${_metodo(p)} · #${p.codigo}',
            ),
            if (p.parceiro != null) ...[
              const SizedBox(height: 4),
              _etiqueta(p),
            ],
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
