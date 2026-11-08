// Restaurante do dia (missão m6, 08/11/2026). PT-BR.
// Ordem do Danilo: "Notificação diária com um restaurante por dia."
// Aqui o Danilo:
//  - liga/desliga o aviso diário e muda a hora (padrão 17:30, hora de Lisboa);
//  - escolhe se vai só para quem aceitou promoções ou para todos com notificações ligadas;
//  - vê o próximo restaurante da rotação, a fila da rotação e os últimos envios
//    (restaurante, prato, motivo e quantas pessoas receberam).
// Servidor: admin_restaurante_do_dia_estado e admin_restaurante_do_dia_configurar
// (docs/propostas/PROPOSTA_20261108_restaurante_do_dia.sql). Sem o servidor, o ecrã diz o que falta.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

class AdminRestauranteDoDiaScreen extends StatefulWidget {
  const AdminRestauranteDoDiaScreen({super.key});

  @override
  State<AdminRestauranteDoDiaScreen> createState() => _AdminRestauranteDoDiaScreenState();
}

class _AdminRestauranteDoDiaScreenState extends State<AdminRestauranteDoDiaScreen> {
  bool _loading = true;
  bool _salvando = false;
  String? _error;
  bool _faltaServidor = false;
  Map<String, dynamic> _estado = const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Supabase.instance.client
          .rpc('admin_restaurante_do_dia_estado', params: {'p_dias': 14});
      if (!mounted) return;
      setState(() {
        _estado = Map<String, dynamic>.from(r as Map);
        _faltaServidor = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final texto = e.toString();
      setState(() {
        _faltaServidor = texto.contains('PGRST202') || texto.contains('Could not find the function');
        _error = _faltaServidor ? null : humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _configurar({bool? ativo, String? hora, bool? soOptIn}) async {
    setState(() => _salvando = true);
    try {
      final r = await Supabase.instance.client.rpc('admin_restaurante_do_dia_configurar', params: {
        'p_ativo': ativo,
        'p_hora': hora,
        'p_so_opt_in': soOptIn,
      });
      if (!mounted) return;
      setState(() => _estado = Map<String, dynamic>.from(r as Map));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salvo.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeAdminRpcError(e))),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _escolherHora() async {
    final atual = (_estado['hora'] ?? '17:30').toString().split(':');
    final escolhida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(atual.first) ?? 17,
        minute: int.tryParse(atual.length > 1 ? atual[1] : '30') ?? 30,
      ),
      helpText: 'Hora do aviso (Lisboa)',
    );
    if (escolhida == null) return;
    final hh = escolhida.hour.toString().padLeft(2, '0');
    final mm = escolhida.minute.toString().padLeft(2, '0');
    await _configurar(hora: '$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Restaurante do dia',
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _carregar,
          ),
        ],
      ),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_faltaServidor) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'O servidor do Restaurante do dia ainda não foi aplicado. '
          'Proposta pronta em docs/propostas/PROPOSTA_20261108_restaurante_do_dia.sql.',
        ),
      );
    }
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(_error!));
    }
    final ativo = _estado['ativo'] == true;
    final soOptIn = _estado['so_opt_in'] == true;
    final hora = (_estado['hora'] ?? '17:30').toString();
    final proxima = _estado['proxima'] is Map ? Map<String, dynamic>.from(_estado['proxima'] as Map) : null;
    final rotacao = (_estado['rotacao'] as List?) ?? const [];
    final envios = (_estado['envios'] as List?) ?? const [];

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Todo dia, à hora escolhida, cada cliente com notificações ligadas recebe um aviso com um '
            'restaurante e um prato. Quem abriu restaurantes nos últimos 30 dias recebe o que mais abriu; '
            'os outros recebem o restaurante da rotação. Tocar no aviso abre a loja.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Aviso diário ligado'),
            value: ativo,
            onChanged: _salvando ? null : (v) => _configurar(ativo: v),
          ),
          ListTile(
            title: const Text('Hora do aviso (Lisboa)'),
            subtitle: Text(hora),
            trailing: const Icon(Icons.schedule),
            onTap: _salvando ? null : _escolherHora,
          ),
          SwitchListTile(
            title: const Text('Só para quem aceitou promoções'),
            subtitle: const Text('Desligado = todos os clientes com notificações ligadas'),
            value: soOptIn,
            onChanged: _salvando ? null : (v) => _configurar(soOptIn: v),
          ),
          const Divider(height: 32),
          Text('Próximo da rotação (amanhã)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(proxima == null ? 'Nenhum restaurante aberto ao jantar amanhã.' : '${proxima['loja']}'),
          const SizedBox(height: 16),
          Text('Fila da rotação', style: Theme.of(context).textTheme.titleMedium),
          for (final item in rotacao)
            if (item is Map)
              ListTile(
                dense: true,
                leading: Icon(
                  item['parceiro'] == true ? Icons.handshake_outlined : Icons.storefront_outlined,
                  color: item['parceiro'] == true ? AppColors.primary : null,
                ),
                title: Text('${item['loja']}'),
                subtitle: Text(item['ultima'] == null
                    ? 'Ainda não foi o restaurante do dia'
                    : 'Última vez: ${item['ultima']}'),
              ),
          const Divider(height: 32),
          Text('Últimos envios (14 dias)', style: Theme.of(context).textTheme.titleMedium),
          if (envios.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nenhum envio ainda.')),
          for (final e in envios)
            if (e is Map)
              ListTile(
                dense: true,
                title: Text('${e['dia']} · ${e['loja']}'),
                subtitle: Text(
                  '${e['prato'] ?? '—'} · '
                  '${e['motivo'] == 'mais_vista' ? 'o que o cliente mais abriu' : 'rotação'} · '
                  '${e['pessoas']} pessoa(s)',
                ),
              ),
        ],
      ),
    );
  }
}
