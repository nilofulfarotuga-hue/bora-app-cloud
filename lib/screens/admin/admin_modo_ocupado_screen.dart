/// MODO OCUPADO DOS PARCEIROS — tela do painel admin (C6, item 6 do adendo 5,
/// 29/10/2026). Painel em PT-BR.
///
/// O que é (igual ao "busy mode" da Uber Eats, Glovo e iFood): quando a loja está
/// com muitos pedidos, o parceiro aperta +10, +20 ou +30 min no painel dele. Durante
/// 2 horas (ou até ele desligar) os clientes veem um tempo de entrega maior. Não
/// muda nenhum preço nem valor pago.
///
/// Aqui o admin: liga ou desliga o recurso para todos (interruptor geral
/// `partner_busy_mode_enabled`, desligado de fábrica), vê quem está ocupado, com
/// quantos minutos e até que horas, e pode desligar o modo de uma loja.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/modo_ocupado_service.dart';

class AdminModoOcupadoScreen extends StatefulWidget {
  const AdminModoOcupadoScreen({super.key, this.api, this.agora});

  /// Só para testes: troca o servidor por uma porta de mentira.
  final ModoOcupadoApi? api;

  /// Só para testes: relógio fixo.
  final DateTime Function()? agora;

  @override
  State<AdminModoOcupadoScreen> createState() => _AdminModoOcupadoScreenState();
}

class _AdminModoOcupadoScreenState extends State<AdminModoOcupadoScreen> {
  late final ModoOcupadoApi _api = widget.api ?? ModoOcupadoSupabase();
  PainelOcupados? _painel;
  bool _carregando = true;
  bool _ocupado = false;
  bool _falhou = false;

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

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

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    final p = await _api.listarOcupados();
    if (!mounted) return;
    setState(() {
      _painel = p;
      _falhou = p == null;
      _carregando = false;
    });
  }

  Future<void> _mudarInterruptor(bool ligar) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final ok = await _api.definirInterruptor(ligar);
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!ok) {
      _msg('Não deu para mudar o interruptor. Tente de novo.', erro: true);
      return;
    }
    _msg(ligar
        ? 'Modo ocupado ligado. Os parceiros já veem o cartão na tela deles.'
        : 'Modo ocupado desligado. Os clientes voltam a ver o tempo normal.');
    await _carregar();
  }

  Future<void> _desligarLoja(LojaOcupada l) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final ok = await _api.desligarLoja(l.restaurantId);
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!ok) {
      _msg('Não deu para desligar o modo ocupado de ${l.nome}. Tente de novo.', erro: true);
      return;
    }
    _msg('Modo ocupado de ${l.nome} desligado.');
    await _carregar();
  }

  String _falta(LojaOcupada l) {
    final ate = l.ate;
    if (ate == null) return '';
    final min = ate.difference(_agora()).inMinutes;
    if (min <= 0) return 'acaba agora';
    if (min < 60) return 'faltam $min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? 'faltam $h h' : 'faltam $h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo ocupado dos parceiros'),
        actions: [
          IconButton(
            key: const Key('btn_atualizar_ocupados'),
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando && _painel == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _painel;
    if (_falhou || p == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Não deu para carregar. Se as funções novas do servidor ainda não foram aplicadas, é normal.',
                key: Key('ocupados_erro'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _carregar,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Quando a loja está com muitos pedidos, o parceiro aperta +10, +20 ou +30 min '
              'na tela dele. Por 2 horas (ou até ele desligar) os clientes veem um tempo de '
              'entrega maior e o aviso "Tempo maior do que o normal". Não muda nenhum preço '
              'nem valor pago. Expira sozinho.',
              style: TextStyle(fontSize: 16, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            key: const Key('switch_modo_ocupado'),
            title: const Text('Modo ocupado ligado para os parceiros',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            subtitle: Text(
              p.ligado
                  ? 'Ligado: os parceiros online veem o cartão "Modo ocupado".'
                  : 'Desligado: nada muda nas telas dos parceiros nem dos clientes.',
              style: const TextStyle(fontSize: 14),
            ),
            value: p.ligado,
            onChanged: _ocupado ? null : _mudarInterruptor,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Lojas ocupadas agora (${p.lojas.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (!p.ligado && p.lojas.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'O interruptor está desligado: estes tempos não estão sendo aplicados.',
              key: Key('ocupados_aviso_desligado'),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
        if (p.lojas.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nenhum parceiro está em modo ocupado agora.',
                key: Key('ocupados_vazio'),
                style: TextStyle(fontSize: 16),
              ),
            ),
          )
        else
          for (final l in p.lojas)
            Card(
              key: Key('ocupada_${l.restaurantId}'),
              child: ListTile(
                title: Text(l.nome.isEmpty ? l.restaurantId : l.nome,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '+${l.extraMinutos} min'
                  '${l.ate == null ? '' : ' até ${hhmmLisboa(l.ate!)} (${_falta(l)})'}',
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: OutlinedButton(
                  key: Key('btn_desligar_${l.restaurantId}'),
                  onPressed: _ocupado ? null : () => _desligarLoja(l),
                  child: const Text('Desligar'),
                ),
              ),
            ),
      ],
    );
  }
}
