import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../screens/admin/_admin_rpc_errors.dart';
import '../../services/sound_service.dart';
import '../../utils/hora_lisboa_ext.dart';

/// Painel admin (PT-BR) — 17/11/2026: bloco fixo no TOPO do dashboard com as
/// encomendas por telefone que ainda esperam pelo entregador.
///
/// O Danilo liga para a loja não-parceira (ex. Jyosmi), encomenda, e quando a
/// loja diz que fica pronto antes dos minutos de espera tem de chamar o
/// entregador logo. O botão vivia escondido em "Encomendas por telefone"; aqui
/// fica à frente: loja, cliente, hora, contagem até ao chamado automático,
/// "Chamar estafeta já" e "Encomendei à loja". Atualiza sozinho (tempo real +
/// a cada 20 s), toca e destaca quando entra pedido novo e some quando não há
/// nada à espera. O número de pedidos vai para [aguardar] (alerta no menu).
class EncomendasTelefoneAguardarCard extends StatefulWidget {
  const EncomendasTelefoneAguardarCard({super.key, this.som});

  /// Quantos pedidos estão à espera agora — o menu do painel mostra-o.
  static final ValueNotifier<int> aguardar = ValueNotifier<int>(0);

  /// Testes: troca o som real.
  final VoidCallback? som;

  @override
  State<EncomendasTelefoneAguardarCard> createState() =>
      _EncomendasTelefoneAguardarCardState();
}

/// Um pedido à espera, já lido da resposta do servidor.
@immutable
class EncomendaAguardar {
  const EncomendaAguardar({
    required this.orderId,
    required this.loja,
    required this.cliente,
    required this.telefone,
    required this.criadoEm,
    required this.encomendadoEm,
    required this.chamaEstafetaAs,
  });

  final String orderId;
  final String loja;
  final String? cliente;
  final String? telefone;
  final DateTime? criadoEm;
  final DateTime? encomendadoEm;
  final DateTime? chamaEstafetaAs;

  static DateTime? _data(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory EncomendaAguardar.fromMap(Map<String, dynamic> m) => EncomendaAguardar(
        orderId: m['order_id'].toString(),
        loja: (m['loja'] ?? '—').toString(),
        cliente: m['cliente']?.toString(),
        telefone: m['telefone']?.toString(),
        criadoEm: _data(m['criado_em']),
        encomendadoEm: _data(m['encomendado_em']),
        chamaEstafetaAs: _data(m['chama_estafeta_as']),
      );

  /// Lista antiga (`admin_listar_encomendas_telefone`), usada enquanto a
  /// função nova não está no servidor: fica só o que ainda espera.
  static List<EncomendaAguardar> daListaAntiga(List<dynamic> linhas) => linhas
      .map((l) => Map<String, dynamic>.from(l as Map))
      .where((m) =>
          m['estado_pedido'] == 'preparing' &&
          m['libertado_em'] == null &&
          m['cancelado_em'] == null)
      .map(EncomendaAguardar.fromMap)
      .toList();
}

/// "mm:ss" que falta até [alvo]; "a chamar…" quando já passou.
String contagemAteChamar(DateTime? alvo, DateTime agora) {
  if (alvo == null) return '—';
  final s = alvo.difference(agora).inSeconds;
  if (s <= 0) return 'a chamar…';
  final m = s ~/ 60;
  return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class _EncomendasTelefoneAguardarCardState
    extends State<EncomendasTelefoneAguardarCard> {
  final _sb = Supabase.instance.client;
  RealtimeChannel? _canal;
  Timer? _relogio;
  Timer? _recarga;
  List<EncomendaAguardar> _pedidos = const [];
  final Set<String> _vistos = {};
  final Set<String> _novos = {};
  bool _primeiraCarga = true;
  bool _semFuncaoNova = false;
  String? _aGravar;
  // Diferença entre o relógio do servidor e o deste aparelho.
  Duration _desvio = Duration.zero;
  SoundService? _somReal;

  @override
  void initState() {
    super.initState();
    _carregar();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _pedidos.isNotEmpty) setState(() {});
    });
    _recarga =
        Timer.periodic(const Duration(seconds: 20), (_) => _carregar());
    _canal = _sb.channel('admin_encomendas_telefone_aguardar')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'encomendas_telefone',
        callback: (_) => _carregar(),
      ).subscribe();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _recarga?.cancel();
    final c = _canal;
    _canal = null;
    if (c != null) unawaited(_sb.removeChannel(c));
    super.dispose();
  }

  Future<void> _carregar() async {
    List<EncomendaAguardar> lista;
    try {
      if (_semFuncaoNova) {
        lista = await _carregarListaAntiga();
      } else {
        final r = await _sb.rpc('admin_encomendas_telefone_a_aguardar');
        final m = Map<String, dynamic>.from(r as Map);
        final agoraServidor = DateTime.tryParse('${m['agora']}');
        if (agoraServidor != null) {
          _desvio = agoraServidor.difference(DateTime.now());
        }
        lista = ((m['pedidos'] as List?) ?? const [])
            .map((p) => EncomendaAguardar.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList();
      }
    } on PostgrestException catch (e) {
      // Função nova ainda não aplicada no servidor: usa a lista antiga.
      if (!_semFuncaoNova && (e.code == 'PGRST202' || e.message.contains('Could not find'))) {
        _semFuncaoNova = true;
        return _carregar();
      }
      debugPrint('[EncomendasTelefoneAguardar] ${humanizeAdminRpcError(e)}');
      return;
    } catch (e) {
      debugPrint('[EncomendasTelefoneAguardar] ${humanizeAdminRpcError(e)}');
      return;
    }
    if (!mounted) return;
    final entraram = lista.where((p) => !_vistos.contains(p.orderId)).toList();
    setState(() {
      _pedidos = lista;
      if (!_primeiraCarga) _novos.addAll(entraram.map((p) => p.orderId));
      _novos.retainAll(lista.map((p) => p.orderId));
      _vistos.addAll(lista.map((p) => p.orderId));
    });
    EncomendasTelefoneAguardarCard.aguardar.value = lista.length;
    if (!_primeiraCarga && entraram.isNotEmpty) _tocar();
    _primeiraCarga = false;
  }

  Future<List<EncomendaAguardar>> _carregarListaAntiga() async {
    final r = await _sb.rpc('admin_listar_encomendas_telefone', params: {'p_dias': 1});
    return EncomendaAguardar.daListaAntiga(r as List);
  }

  void _tocar() {
    if (widget.som != null) return widget.som!();
    unawaited((_somReal ??= SoundService()).playOnce());
  }

  String _hora(DateTime? t) {
    if (t == null) return '—';
    final l = t.toLisboa();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _encomendei(EncomendaAguardar p) async {
    if (_aGravar != null) return;
    setState(() => _aGravar = p.orderId);
    try {
      final r = await _sb.rpc('admin_encomendado_a_loja', params: {'p_order_id': p.orderId});
      final m = Map<String, dynamic>.from(r as Map);
      _aviso(m['ok'] == true
          ? 'Registrado. O entregador é chamado às ${m['estafeta_chamado_as']}.'
          : 'Já estava encomendado (ou o pedido saiu da fila).');
      await _carregar();
    } catch (e) {
      _aviso(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
  }

  Future<void> _chamarJa(EncomendaAguardar p) async {
    if (_aGravar != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chamar o entregador já?'),
        content: Text('A loja ${p.loja} disse que fica pronto antes? O pedido entra já na fila dos '
            'entregadores, sem esperar os minutos configurados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Chamar já')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _aGravar = p.orderId);
    try {
      final r = await _sb.rpc('admin_chamar_estafeta_ja', params: {'p_order_id': p.orderId});
      final m = Map<String, dynamic>.from(r as Map);
      const motivos = {
        'estafeta_ja_chamado': 'O entregador já tinha sido chamado.',
        'encomenda_cancelada': 'Este pedido foi cancelado.',
        'pedido_nao_esta_em_preparacao': 'O pedido já não está em preparação.',
        'nao_e_encomenda_por_telefone': 'Este pedido não é de encomenda por telefone.',
        'nao_libertou': 'Não deu para chamar agora. Tente de novo.',
      };
      _aviso(m['ok'] == true
          ? 'Entregador chamado às ${m['chamado_as']}.'
          : (motivos[m['motivo']] ?? 'Não deu: ${m['motivo']}'));
      await _carregar();
    } catch (e) {
      _aviso(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Widget _linha(EncomendaAguardar p, DateTime agora) {
    final novo = _novos.contains(p.orderId);
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            if (novo)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                child: const Text('NOVO',
                    style: TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            Expanded(
              child: Text(p.loja,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Text(contagemAteChamar(p.chamaEstafetaAs, agora),
                key: ValueKey('contagem_${p.orderId}'),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 4),
          Text('Cliente: ${p.cliente ?? '—'} · pedido às ${_hora(p.criadoEm)}'),
          Text(
            p.encomendadoEm != null
                ? 'Encomendado à loja às ${_hora(p.encomendadoEm)} · entregador automático às ${_hora(p.chamaEstafetaAs)}'
                : 'Ainda não encomendado à loja · entregador automático às ${_hora(p.chamaEstafetaAs)}',
            style: TextStyle(
                fontSize: 12,
                color: p.encomendadoEm != null ? AppColors.textSubtle : AppColors.warning,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              onPressed: ocupado ? null : () => _chamarJa(p),
              icon: _aGravar == p.orderId
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.two_wheeler),
              label: const Text('Chamar estafeta já'),
            ),
          ),
          if (p.encomendadoEm == null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: ocupado ? null : () => _encomendei(p),
              icon: const Icon(Icons.check),
              label: const Text('Encomendei à loja'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pedidos.isEmpty) return const SizedBox.shrink();
    final agora = DateTime.now().add(_desvio);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFFFF7ED),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.accent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.phone_in_talk, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Encomendas por telefone a aguardar (${_pedidos.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            const Text(
              'A contagem mostra quanto falta para o entregador ser chamado sozinho. '
              'Se a loja já disse que está pronto, toque em "Chamar estafeta já".',
              style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
            if (_semFuncaoNova)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'O nome do cliente aparece quando a função nova for aplicada no servidor.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
              ),
            for (final p in _pedidos) _linha(p, agora),
          ],
        ),
      ),
    );
  }
}
