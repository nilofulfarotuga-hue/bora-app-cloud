import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart';

/// PAINEL ADMIN (PT-BR) — "Quem foi chamado" num pedido, Favor ou corrida.
///
/// Lê `admin_ofertas_do_pedido(p_ref)` (migração 20261010063000): uma linha
/// por oferta — hora (Lisboa), nome, fase, se estava online, se tinha
/// aparelho, quanto tempo teve, se o toque foi entregue ao FCM e como acabou.
///
/// Se a migração ainda não estiver aplicada, mostra "Ainda não ativo no
/// servidor" em vez de um erro vermelho.
class AdminOfertasDoPedidoSection extends StatefulWidget {
  const AdminOfertasDoPedidoSection({
    super.key,
    required this.pedidoRef,
    this.carregar,
  });

  /// `orders.id` (texto) ou `tvde_rides.id` (uuid em texto).
  final String pedidoRef;

  /// Só para testes: substitui a chamada ao servidor.
  final Future<Object?> Function(String ref)? carregar;

  @override
  State<AdminOfertasDoPedidoSection> createState() =>
      _AdminOfertasDoPedidoSectionState();
}

class _AdminOfertasDoPedidoSectionState
    extends State<AdminOfertasDoPedidoSection> {
  bool _loading = true;
  bool _semServidor = false;
  String? _erro;
  List<Map<String, dynamic>> _itens = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Object?> _chamar(String ref) => Supabase.instance.client
      .rpc('admin_ofertas_do_pedido', params: {'p_ref': ref});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
      _semServidor = false;
    });
    try {
      final res = await (widget.carregar ?? _chamar)(widget.pedidoRef);
      final m = (res as Map).cast<String, dynamic>();
      if (m['ok'] != true) {
        throw Exception(m['erro'] ?? m['error'] ?? 'resposta inesperada');
      }
      final itens = ((m['itens'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semServidor = servidorAindaSemIsto(e);
        _erro = _semServidor ? null : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _itens.isEmpty
                        ? 'Quem foi chamado'
                        : 'Quem foi chamado (${_itens.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            const Text(
              'Hora de Lisboa. FCM = serviço do Google que entrega o toque no '
              'telemóvel; "entregue" quer dizer que o Google aceitou mandar.',
              style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_semServidor)
              const _Aviso(
                icone: Icons.cloud_off_outlined,
                texto: kAindaNaoAtivo,
                detalhe: 'O registro de quem foi chamado começa quando a '
                    'migração do registro de ofertas for aplicada.',
              )
            else if (_erro != null)
              _Aviso(
                icone: Icons.info_outline,
                texto: 'Não deu para carregar quem foi chamado.',
                detalhe: _erro,
              )
            else if (_itens.isEmpty)
              const _Aviso(
                icone: Icons.hourglass_empty,
                texto: 'Ninguém foi chamado neste pedido.',
                detalhe: 'Ou o pedido é de antes de o registro começar.',
              )
            else
              for (var i = 0; i < _itens.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                LinhaOfertaChamada(item: _itens[i]),
              ],
          ],
        ),
      ),
    );
  }
}

/// Uma oferta, em palavras. Público para o registro geral reutilizar.
class LinhaOfertaChamada extends StatelessWidget {
  const LinhaOfertaChamada({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final desfecho = '${item['desfecho'] ?? ''}';
    final enviados = item['push_enviados'];
    final toqueFalhou = enviados is num && enviados == 0;
    final detalhe = '${item['push_detalhe'] ?? ''}'.trim();
    final online = item['estava_online'];
    final aparelho = item['tem_aparelho'];

    String simNao(Object? v) => v == true
        ? 'sim'
        : v == false
            ? 'não'
            : '—';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${_horaComSegundos(item['oferecida_em'])} · '
                  '${item['nome'] ?? '(sem nome)'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              _ChipDesfecho(desfecho: desfecho),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Fase: ${faseEmPalavras(item['fase'])} · '
            'estava online: ${simNao(online)} · '
            'tinha aparelho: ${simNao(aparelho)} · '
            'teve ${janelaEmPalavras(item['janela_s'])}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'Toque entregue ao FCM: '
            '${toqueEntregueEmPalavras(enviados, item['push_aparelhos'])}',
            style: TextStyle(
              fontSize: 12,
              color: toqueFalhou ? AppColors.error : AppColors.textSecondary,
              fontWeight: toqueFalhou ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (toqueFalhou && detalhe.isNotEmpty)
            Text(
              detalhe.length > 160 ? '${detalhe.substring(0, 160)}…' : detalhe,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
          if (aparelho == false)
            const Text(
              'Sem aparelho registrado: esta pessoa não tinha como ser avisada.',
              style: TextStyle(fontSize: 11, color: AppColors.warning),
            ),
        ],
      ),
    );
  }
}

class _ChipDesfecho extends StatelessWidget {
  const _ChipDesfecho({required this.desfecho});
  final String desfecho;

  @override
  Widget build(BuildContext context) {
    final cor = switch (desfecho) {
      'aceite' => AppColors.primary,
      'a decorrer' || '' => AppColors.info,
      'recusou' || 'recusada' => AppColors.warning,
      _ => AppColors.textSubtle,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        desfechoEmPalavras(desfecho),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto, this.detalhe});
  final IconData icone;
  final String texto;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: AppColors.textSubtle),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                if (detalhe != null && detalhe!.isNotEmpty)
                  Text(detalhe!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSubtle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "10/10 19:05:12" em hora de Lisboa; "—" se não houver.
String _horaComSegundos(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '—';
  final l = horaLisboa(d);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.day)}/${dd(l.month)} ${dd(l.hour)}:${dd(l.minute)}:${dd(l.second)}';
}
