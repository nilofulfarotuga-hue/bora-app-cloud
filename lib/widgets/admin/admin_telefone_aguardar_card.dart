import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../screens/admin/_admin_rpc_errors.dart';
import '../../services/sound_service.dart';
import '../../utils/hora_lisboa_ext.dart';

/// Painel admin (PT-BR) — bloco fixo no TOPO do dashboard: "Encomendas por
/// telefone a aguardar" (17/11/2026).
///
/// O Danilo liga à loja não-parceira (ex.: Jyosmi), encomenda, e quando a loja
/// diz que está pronto antes dos minutos de espera tem de chamar o estafeta
/// LOGO. O botão "Chamar estafeta já" estava só no ecrã "Encomendas por
/// telefone" e ele não o encontrava. Aqui aparece sozinho, só quando há pedidos
/// em 'preparing' com o estafeta ainda por chamar, com contagem decrescente
/// até ao chamado automático. Some quando não há pedidos.
///
/// Atualiza por tempo real (tabela encomendas_telefone) e, de reserva, a cada
/// 20 s. Pedido novo: toca o alerta uma vez e fica destacado 60 s.
class AdminTelefoneAguardarCard extends StatefulWidget {
  const AdminTelefoneAguardarCard({super.key, this.carregadorParaTeste});

  /// Só para testes: devolve a lista sem falar com o servidor.
  final Future<List<Map<String, dynamic>>> Function()? carregadorParaTeste;

  /// Quantos pedidos estão a aguardar — o menu e a barra do topo mostram o
  /// alerta a partir daqui.
  static final ValueNotifier<int> contagem = ValueNotifier<int>(0);

  @override
  State<AdminTelefoneAguardarCard> createState() =>
      _AdminTelefoneAguardarCardState();
}

/// Texto da contagem até ao chamado automático. Público para o teste.
String contagemAteChamar(DateTime alvo, DateTime agora) {
  final falta = alvo.difference(agora);
  if (falta.inSeconds <= 0) return 'a chamar o estafeta agora…';
  final m = falta.inMinutes;
  final s = falta.inSeconds % 60;
  return 'estafeta chamado sozinho em $m:${s.toString().padLeft(2, '0')}';
}

class _AdminTelefoneAguardarCardState extends State<AdminTelefoneAguardarCard> {
  SupabaseClient get _sb => Supabase.instance.client;
  late final SoundService? _som =
      widget.carregadorParaTeste == null ? SoundService() : null;
  List<Map<String, dynamic>> _pedidos = const [];
  final Set<String> _vistos = {};
  final Map<String, DateTime> _novosAte = {};
  bool _primeiraCarga = true;
  bool _aCarregar = false;
  String? _aGravar;
  Timer? _relogio;
  Timer? _reserva;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _carregar();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _pedidos.isNotEmpty) setState(() {});
    });
    if (widget.carregadorParaTeste != null) return;
    _reserva = Timer.periodic(const Duration(seconds: 20), (_) => _carregar());
    _canal = _sb
        .channel('admin-telefone-aguardar')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encomendas_telefone',
          callback: (_) => _carregar(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _reserva?.cancel();
    final c = _canal;
    _canal = null;
    if (c != null) unawaited(_sb.removeChannel(c));
    _som?.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _lerDoServidor() async {
    final teste = widget.carregadorParaTeste;
    if (teste != null) return teste();
    try {
      final r = await _sb.rpc('admin_telefone_a_aguardar');
      return List<Map<String, dynamic>>.from(r as List);
    } on PostgrestException catch (e) {
      // A função nova (migração 20261117210000) ainda pode não estar no ar:
      // usa a lista que já existe e filtra aqui.
      if (e.code != 'PGRST202' && !e.message.contains('Could not find')) rethrow;
    }
    final r = await _sb.rpc('admin_listar_encomendas_telefone', params: {'p_dias': 1});
    final lista = List<Map<String, dynamic>>.from(r as List)
        .where((p) =>
            p['estado_pedido'] == 'preparing' &&
            p['libertado_em'] == null &&
            p['cancelado_em'] == null)
        .toList();
    if (lista.isEmpty) return lista;
    final nomes = <String, String>{};
    try {
      final o = await _sb
          .from('orders')
          .select('id, customer_name')
          .inFilter('id', lista.map((p) => p['order_id']).toList());
      for (final row in List<Map<String, dynamic>>.from(o as List)) {
        nomes['${row['id']}'] = (row['customer_name'] ?? '').toString();
      }
    } catch (_) {}
    return [
      for (final p in lista.reversed)
        {...p, 'cliente': nomes['${p['order_id']}'] ?? ''},
    ];
  }

  Future<void> _carregar() async {
    if (_aCarregar) return;
    _aCarregar = true;
    try {
      final lista = await _lerDoServidor();
      if (!mounted) return;
      final agora = DateTime.now();
      var houveNovo = false;
      for (final p in lista) {
        final id = '${p['order_id']}';
        if (_vistos.add(id) && !_primeiraCarga) {
          houveNovo = true;
          _novosAte[id] = agora.add(const Duration(seconds: 60));
        }
      }
      _primeiraCarga = false;
      setState(() => _pedidos = lista);
      AdminTelefoneAguardarCard.contagem.value = lista.length;
      final som = _som;
      if (houveNovo && som != null) unawaited(som.playOnce());
    } catch (e) {
      // Sem rede ou sessão: fica o que já estava; tenta de novo daqui a 20 s.
      debugPrint('AdminTelefoneAguardarCard: $e');
    } finally {
      _aCarregar = false;
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _chamarJa(Map<String, dynamic> p) async {
    if (_aGravar != null) return;
    final orderId = '${p['order_id']}';
    setState(() => _aGravar = orderId);
    try {
      final r = await _sb.rpc('admin_chamar_estafeta_ja', params: {'p_order_id': orderId});
      final m = Map<String, dynamic>.from(r as Map);
      const motivos = {
        'estafeta_ja_chamado': 'O estafeta já tinha sido chamado.',
        'encomenda_cancelada': 'Este pedido foi cancelado.',
        'pedido_nao_esta_em_preparacao': 'O pedido já não está em preparação.',
        'nao_e_encomenda_por_telefone': 'Este pedido não é de encomenda por telefone.',
      };
      _aviso(m['ok'] == true
          ? 'Estafeta chamado às ${m['chamado_as']} (${p['loja']}).'
          : (motivos[m['motivo']] ?? 'Não deu: ${m['motivo']}'));
      await _carregar();
    } catch (e) {
      _aviso('Não chamou: ${humanizeAdminRpcError(e)}');
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
  }

  Future<void> _encomendei(Map<String, dynamic> p) async {
    if (_aGravar != null) return;
    final orderId = '${p['order_id']}';
    setState(() => _aGravar = orderId);
    try {
      final r = await _sb.rpc('admin_encomendado_a_loja', params: {'p_order_id': orderId});
      final m = Map<String, dynamic>.from(r as Map);
      _aviso(m['ok'] == true
          ? 'Registrado. O estafeta é chamado sozinho às ${m['estafeta_chamado_as']}.'
          : 'Já estava registrado (ou o pedido saiu da fila).');
      await _carregar();
    } catch (e) {
      _aviso('Não registrou: ${humanizeAdminRpcError(e)}');
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
  }

  String _hora(dynamic iso) {
    final t = DateTime.tryParse('${iso ?? ''}')?.toLisboa();
    if (t == null) return '—';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _linha(Map<String, dynamic> p, DateTime agora) {
    final id = '${p['order_id']}';
    final novo = (_novosAte[id]?.isAfter(agora)) ?? false;
    final encomendado = p['encomendado_em'] != null;
    final alvo = DateTime.tryParse('${p['chama_estafeta_as'] ?? ''}');
    final cliente = '${p['cliente'] ?? ''}'.trim();
    final ocupado = _aGravar != null;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: novo ? const Color(0xFFFFEDD5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: novo ? AppColors.accent : const Color(0xFFFED7AA),
            width: novo ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (novo)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('NOVO',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            Expanded(
              child: Text('${p['loja'] ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if ((p['telefone'] ?? '').toString().isNotEmpty)
              IconButton(
                tooltip: 'Ligar para a loja (${p['telefone']})',
                icon: const Icon(Icons.call, color: AppColors.primary),
                onPressed: () => launchUrl(Uri.parse(
                    'tel:${p['telefone'].toString().replaceAll(' ', '')}')),
              ),
          ]),
          Text(
              '${cliente.isEmpty ? 'Cliente' : cliente} · pedido às ${_hora(p['criado_em'])}'
              '${encomendado ? ' · encomendado às ${_hora(p['encomendado_em'])}' : ' · ainda não encomendado à loja'}'),
          const SizedBox(height: 4),
          if (alvo != null)
            Text(contagemAteChamar(alvo, agora),
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentDark)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 52),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              onPressed: ocupado ? null : () => _chamarJa(p),
              icon: _aGravar == id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.two_wheeler),
              label: const Text('Chamar estafeta já'),
            ),
            if (!encomendado)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: ocupado ? null : () => _encomendei(p),
                icon: const Icon(Icons.check),
                label: const Text('Encomendei à loja'),
              ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pedidos.isEmpty) return const SizedBox.shrink();
    final agora = DateTime.now();
    return Container(
      key: const Key('admin_telefone_aguardar'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.phone_in_talk, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Encomendas por telefone a aguardar (${_pedidos.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ]),
              for (final p in _pedidos) _linha(p, agora),
            ],
          ),
        ),
      ),
    );
  }
}
