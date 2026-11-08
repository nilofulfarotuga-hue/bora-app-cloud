// Painel admin (PT-BR) — "Diferenças de Favor" (04/11/2026, missão
// favor-diferenca-mbway-2026-11-03, bloco E). Favores pagos por MB Way em que a
// compra passou o orçado: quanto falta, estado do pedido MB Way (pedido /
// pago / expirou / falhou), quantas tentativas e o botão "Reenviar pedido MB
// Way" (RPC admin_favor_diferenca_reenviar, fica no log de auditoria).
//
// 08/11/2026 (missão m1-dinheiro-favores, bloco 2): no topo, "Favores à espera
// de aprovação do cliente" (RPC admin_favor_aprovacoes_listar): o entregador
// está na loja, o preço passou o teto e o cliente tem poucos minutos para
// aprovar. Se o Danilo falou com o cliente por telefone, "Aprovar pelo
// cliente" (RPC admin_favor_aprovar_pelo_cliente, motivo obrigatório, fica no
// log de auditoria).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../../widgets/private_bucket_image.dart';

/// Texto PT-BR do estado do pedido MB Way.
String estadoDiferencaTexto(String? estado) => switch (estado) {
      'pedido' => 'Pedido MB Way enviado (aguardando o cliente aprovar no app MB Way)',
      'pago' => 'Pago',
      'expirou' => 'Expirou (o cliente não aprovou a tempo)',
      'falhou' => 'Falhou (recusado ou erro do MB Way)',
      _ => 'Sem pedido MB Way (diferença em disputa)',
    };

/// "15,40 €" a partir de centavos.
String eurosDeCentavos(Object? cents) =>
    '${(((cents as num?) ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

const String kFuncaoAindaNaoPublicada = 'Função ainda não publicada no servidor';

class AdminFavorDiferencasScreen extends StatefulWidget {
  const AdminFavorDiferencasScreen({
    super.key,
    this.listar,
    this.reenviar,
    this.listarAprovacoes,
    this.aprovarPeloCliente,
  });

  /// Só para testes.
  final Future<List<Map<String, dynamic>>> Function()? listar;
  final Future<Map<String, dynamic>> Function(String pedidoId)? reenviar;
  final Future<List<Map<String, dynamic>>> Function()? listarAprovacoes;
  final Future<Map<String, dynamic>> Function(String pedidoId, String motivo)? aprovarPeloCliente;

  static Future<List<Map<String, dynamic>>> listarDoServidor() async {
    final r = await Supabase.instance.client.rpc('admin_favor_diferencas_listar');
    if (r is List) {
      return r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static Future<Map<String, dynamic>> reenviarNoServidor(String pedidoId) async {
    final r = await Supabase.instance.client
        .rpc('admin_favor_diferenca_reenviar', params: {'p_pedido': pedidoId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Favores com pedido de aprovação PENDENTE (o cliente ainda não respondeu).
  static Future<List<Map<String, dynamic>>> listarAprovacoesDoServidor() async {
    final r = await Supabase.instance.client.rpc('admin_favor_aprovacoes_listar',
        params: {'p_so_pendentes': true, 'p_limite': 50});
    if (r is List) {
      return r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static Future<Map<String, dynamic>> aprovarPeloClienteNoServidor(String pedidoId, String motivo) async {
    final r = await Supabase.instance.client.rpc('admin_favor_aprovar_pelo_cliente',
        params: {'p_order_id': pedidoId, 'p_motivo': motivo});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Mensagem PT-BR da resposta de admin_favor_aprovar_pelo_cliente.
  static String mensagemAprovacao(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      final aprovado = 'Aprovado pelo cliente (${eurosDeCentavos(r['pedido_cents'])}).';
      final mb = r['mbway'];
      if (mb is! Map) return '$aprovado O entregador foi avisado que pode comprar.';
      if (mb['ok'] == true) {
        return '$aprovado Pedido MB Way de ${eurosDeCentavos(mb['valor_cents'])} enviado ao cliente; '
            'o entregador só compra depois de pago.';
      }
      if (mb['error'] == 'nada_a_pagar') {
        return '$aprovado A diferença é menor que 0,50 €: não precisa de MB Way.';
      }
      return '$aprovado Mas o pedido MB Way da diferença não saiu (${mb['error'] ?? 'erro desconhecido'}). '
          'Veja em "Diferenças por cobrar" e use Reenviar.';
    }
    return switch (r['error']) {
      'motivo_obrigatorio' => 'Escreva o motivo (mínimo 5 letras).',
      'pedido_fechado' => 'O pedido já está fechado (entregue ou cancelado).',
      'sem_pedido_pendente' =>
        'Este Favor já não está à espera de aprovação (estado do orçamento: ${r['budget_status'] ?? '—'}).',
      'pedido_nao_encontrado' => 'Pedido não encontrado.',
      _ => 'Não foi possível: ${r['error'] ?? 'erro desconhecido'}',
    };
  }

  @override
  State<AdminFavorDiferencasScreen> createState() => _AdminFavorDiferencasScreenState();
}

class _AdminFavorDiferencasScreenState extends State<AdminFavorDiferencasScreen> {
  List<Map<String, dynamic>>? _linhas;
  String? _erro;
  bool _diferencasSemServidor = false;
  final Set<String> _aEnviar = {};

  // Aprovações pendentes (bloco 2, 08/11).
  List<Map<String, dynamic>>? _aprovacoes;
  String? _erroAprovacoes;
  bool _aprovacoesSemServidor = false;
  DateTime _aprovacoesLidasEm = DateTime.now();
  final Set<String> _aAprovar = {};
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarAprovacoes();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _carregarTudo() => Future.wait([_carregar(), _carregarAprovacoes()]);

  Future<void> _carregar() async {
    try {
      final l = await (widget.listar ?? AdminFavorDiferencasScreen.listarDoServidor)();
      if (mounted) {
        setState(() {
          _linhas = l;
          _erro = null;
          _diferencasSemServidor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diferencasSemServidor = servidorAindaSemIsto(e);
          _erro = _diferencasSemServidor ? null : e.toString();
        });
      }
    }
  }

  Future<void> _carregarAprovacoes() async {
    try {
      final l = await (widget.listarAprovacoes ?? AdminFavorDiferencasScreen.listarAprovacoesDoServidor)();
      if (!mounted) return;
      setState(() {
        _aprovacoes = l;
        _aprovacoesLidasEm = DateTime.now();
        _erroAprovacoes = null;
        _aprovacoesSemServidor = false;
      });
      _ligarRelogio();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aprovacoesSemServidor = servidorAindaSemIsto(e);
        _erroAprovacoes = _aprovacoesSemServidor ? null : e.toString();
      });
    }
  }

  /// Segundos que faltam, contados a partir do que o servidor disse quando a
  /// lista foi lida (não depende do relógio do aparelho).
  int _segundosRestantes(Map<String, dynamic> a) {
    final s = (a['segundos_restantes'] as num?)?.toInt() ?? 0;
    final passados = DateTime.now().difference(_aprovacoesLidasEm).inSeconds;
    final r = s - passados;
    return r < 0 ? 0 : r;
  }

  /// Contagem decrescente na tela enquanto houver prazo a correr.
  void _ligarRelogio() {
    _relogio?.cancel();
    final a = _aprovacoes ?? const [];
    if (a.every((x) => _segundosRestantes(x) == 0)) return;
    _relogio = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {});
      if ((_aprovacoes ?? const []).every((x) => _segundosRestantes(x) == 0)) t.cancel();
    });
  }

  Future<void> _reenviar(String pedidoId) async {
    setState(() => _aEnviar.add(pedidoId));
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      final r = await (widget.reenviar ?? AdminFavorDiferencasScreen.reenviarNoServidor)(pedidoId);
      msg = r['ok'] == true
          ? 'Novo pedido MB Way enviado (tentativa ${r['tentativa']}).'
          : 'Não enviado: ${r['error'] ?? 'erro desconhecido'}';
    } catch (e) {
      msg = servidorAindaSemIsto(e) ? kFuncaoAindaNaoPublicada : 'Erro ao reenviar: $e';
    }
    if (!mounted) return;
    setState(() => _aEnviar.remove(pedidoId));
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    await _carregar();
  }

  Future<void> _aprovar(String pedidoId) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _AprovarPeloClienteDialog(pedidoCurto: _curto(pedidoId)),
    );
    if (motivo == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (motivo.length < 5) {
      messenger.showSnackBar(const SnackBar(content: Text('Escreva o motivo (mínimo 5 letras).')));
      return;
    }
    setState(() => _aAprovar.add(pedidoId));
    String msg;
    try {
      final r = await (widget.aprovarPeloCliente ?? AdminFavorDiferencasScreen.aprovarPeloClienteNoServidor)(
          pedidoId, motivo);
      msg = AdminFavorDiferencasScreen.mensagemAprovacao(r);
    } catch (e) {
      msg = servidorAindaSemIsto(e) ? kFuncaoAindaNaoPublicada : 'Erro ao aprovar: $e';
    }
    if (!mounted) return;
    setState(() => _aAprovar.remove(pedidoId));
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    await _carregarTudo();
  }

  Future<void> _ligar(String numero) async {
    final limpo = numero.replaceAll(' ', '');
    if (limpo.isEmpty) return;
    await launchUrl(Uri.parse('tel:$limpo'));
  }

  static String _curto(String id) => id.substring(0, id.length < 8 ? id.length : 8);

  static String _eur(Object? cents) =>
      '€${(((cents as num?) ?? 0) / 100).toStringAsFixed(2)}';

  static String _metodo(Object? m) => switch (m) {
        'mbway' => 'MB Way',
        'cash' => 'Dinheiro',
        'card' || 'stripe' => 'Cartão',
        _ => '${m ?? '—'}',
      };

  static String _prazo(int s) {
    if (s <= 0) {
      return 'Prazo acabou (o entregador pode comprar só até o teto ou cancelar o Favor)';
    }
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return 'Faltam $s s ($m:$ss) para o cliente responder';
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _avisoSemServidor(String detalhe) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$kFuncaoAindaNaoPublicada. $detalhe',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ]),
        ),
      );

  Widget _textoErro(String erro) => Text('Não foi possível carregar: $erro',
      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.error));

  Widget _carregando() => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  List<Widget> _blocoAprovacoes() {
    final lista = _aprovacoes;
    return [
      _titulo('Favores à espera de aprovação do cliente'),
      const Text(
        'O entregador está na loja e o preço passou o teto (o máximo que ele pode comprar sem perguntar). '
        'O cliente recebe um toque para aprovar no app. Se você falou com o cliente por telefone, '
        'use "Aprovar pelo cliente" — fica no log de auditoria com o motivo.',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      if (_aprovacoesSemServidor)
        _avisoSemServidor('A lista de aprovações aparece aqui quando a migração do Favor com teto for aplicada.')
      else if (_erroAprovacoes != null)
        _textoErro(_erroAprovacoes!)
      else if (lista == null)
        _carregando()
      else if (lista.isEmpty)
        const Text('Nenhum Favor à espera de aprovação agora.')
      else
        for (final a in lista) ...[
          _cartaoAprovacao(a),
          const SizedBox(height: 8),
        ],
    ];
  }

  Widget _cartaoAprovacao(Map<String, dynamic> a) {
    final id = '${a['pedido_id']}';
    final telefone = '${a['cliente_telefone'] ?? ''}'.trim();
    final foto = '${a['foto_url'] ?? ''}'.trim();
    final descricao = '${a['descricao'] ?? ''}'.trim();
    final pedido = (a['pedido_cents'] as num?) ?? 0;
    final teto = (a['teto_cents'] as num?) ?? 0;
    final restam = _segundosRestantes(a);
    final aAprovar = _aAprovar.contains(id);
    return Card(
      key: Key('favor_aprovacao_$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pedido ${_curto(id)} · ${a['cliente'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (telefone.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('ligar_$id'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => _ligar(telefone),
                  icon: const Icon(Icons.phone, size: 16),
                  label: Text(telefone),
                ),
              )
            else
              const Text('Sem telefone na conta',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (descricao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(descricao, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 6),
            Text('Valor pedido: ${eurosDeCentavos(pedido)} · Teto: ${eurosDeCentavos(teto)}'
                '${pedido > teto ? ' (passa ${eurosDeCentavos(pedido - teto)})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Pagamento: ${_metodo(a['payment_method'])} · status ${a['status_pedido'] ?? '—'} · '
                'pedido às ${dataHoraLisboa(a['criado_em'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Text(_prazo(restam),
                key: Key('prazo_$id'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: restam > 0 ? AppColors.warning : AppColors.error)),
            if (foto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: PrivateBucketImage(
                  urlOrPath: foto,
                  height: 160,
                  fit: BoxFit.contain,
                  borderRadius: BorderRadius.circular(8),
                  tituloAmpliada: 'Foto da etiqueta · pedido ${_curto(id)}',
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: Key('aprovar_pelo_cliente_$id'),
                onPressed: aAprovar ? null : () => _aprovar(id),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(aAprovar ? 'Aprovando…' : 'Aprovar pelo cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _blocoDiferencas() {
    final linhas = _linhas;
    return [
      _titulo('Diferenças por cobrar (MB Way)'),
      if (_diferencasSemServidor)
        _avisoSemServidor('A lista de diferenças aparece aqui quando a migração das diferenças do Favor for aplicada.')
      else if (_erro != null)
        _textoErro(_erro!)
      else if (linhas == null)
        _carregando()
      else if (linhas.isEmpty)
        const Text('Nenhuma diferença de Favor por cobrar.')
      else ...[
        const Text(
          'Favores pagos por MB Way em que a compra passou o orçado. O servidor pede a diferença '
          'por MB Way (o cliente tem poucos minutos para aprovar). "Reenviar" manda um pedido novo.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        for (final l in linhas) ...[
          const SizedBox(height: 8),
          _cartaoDiferenca(l),
        ],
      ],
    ];
  }

  Widget _cartaoDiferenca(Map<String, dynamic> l) {
    final id = '${l['pedido_id']}';
    final acertado = l['acertado_em'] != null;
    return Card(
      key: Key('favor_dif_$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pedido ${_curto(id)} · ${l['cliente'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Criado em ${dataHoraLisboa(l['criado_em'])} · status ${l['status']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(acertado
                ? 'Acertado (${l['acertado_via']})'
                : 'Falta cobrar: ${_eur(l['devido_cents'])}'),
            Text('MB Way: ${estadoDiferencaTexto(l['estado'] as String?)} · tentativas: ${l['tentativas'] ?? 0}'),
            if (!acertado && l['payment_method'] == 'mbway' && l['estado'] != 'pago')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key('reenviar_$id'),
                  onPressed: _aEnviar.contains(id) ? null : () => _reenviar(id),
                  icon: const Icon(Icons.send_to_mobile),
                  label: Text(_aEnviar.contains(id) ? 'Enviando…' : 'Reenviar pedido MB Way'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diferenças de Favor'),
        actions: [
          IconButton(tooltip: 'Atualizar', onPressed: _carregarTudo, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarTudo,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            ..._blocoAprovacoes(),
            const Divider(height: 32),
            ..._blocoDiferencas(),
          ],
        ),
      ),
    );
  }
}

/// Janela "Aprovar pelo cliente": motivo obrigatório (mínimo 5 letras). A
/// janela é dona do seu campo de texto (fechar a meio da animação não rebenta).
class _AprovarPeloClienteDialog extends StatefulWidget {
  const _AprovarPeloClienteDialog({required this.pedidoCurto});
  final String pedidoCurto;

  @override
  State<_AprovarPeloClienteDialog> createState() => _AprovarPeloClienteDialogState();
}

class _AprovarPeloClienteDialogState extends State<_AprovarPeloClienteDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = _ctrl.text.trim().length >= 5;
    return AlertDialog(
      title: Text('Aprovar pelo cliente · pedido ${widget.pedidoCurto}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Use só quando o cliente disse que aceita o preço (por exemplo, por telefone). '
              'Fica registrado no log de auditoria com o seu nome e o motivo.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('motivo_aprovar_pelo_cliente'),
            controller: _ctrl,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatório, mínimo 5 letras)',
              hintText: 'Ex.: falei com o cliente por telefone às 19h40',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          key: const Key('confirmar_aprovar_pelo_cliente'),
          onPressed: valido ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: const Text('Aprovar'),
        ),
      ],
    );
  }
}
