// Painel admin (PT-BR) — "NIF nas compras" (M10 b2-nif, 09/11/2026).
//
// Ordem do Danilo (04/11, caso do Auchan: o entregador nunca viu o NIF que o
// cliente pediu): nas compras em loja NÃO parceira e nos Favores com compra, o
// entregador dá SEMPRE um NIF no caixa — o do cliente, se pediu fatura; senão o
// da Bora. Nunca "consumidor final". Aqui o admin vê, pedido a pedido, qual
// NIF devia ser dado e se o entregador confirmou que deu ("Dei este NIF") ou
// disse "Não consegui" com o motivo; filtra 7/30 dias e "só os não dados";
// exporta CSV; e muda o NIF da Bora (setting `nif_compras_nao_parceiro`).
//
// Servidor: RPC admin_nif_caixa_listar e admin_nif_bora_definir (migração
// 20261109005413_m10_nif_na_caixa.sql). Sem ela: aviso "ainda não publicada".
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/nif_pt.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../../widgets/admin/admin_csv_button.dart';
import 'admin_order_detail_screen.dart';

const String kNifComprasNaoPublicada =
    'Função ainda não publicada no servidor (migração do NIF no caixa por aplicar).';

/// Uma linha da lista (o que `admin_nif_caixa_listar` devolve).
class NifCompraLinha {
  const NifCompraLinha({
    required this.orderId,
    this.criadoEm,
    this.loja,
    this.cliente,
    this.estado,
    this.tipo,
    this.nif,
    this.dado,
    this.motivo,
    this.confirmadoEm,
  });

  factory NifCompraLinha.deMapa(Map<String, dynamic> m) => NifCompraLinha(
        orderId: '${m['order_id'] ?? ''}',
        criadoEm: m['criado_em']?.toString(),
        loja: m['loja'] as String?,
        cliente: m['cliente'] as String?,
        estado: m['estado'] as String?,
        tipo: m['tipo'] as String?,
        nif: m['nif']?.toString(),
        dado: m['dado'] as bool?,
        motivo: m['motivo'] as String?,
        confirmadoEm: m['confirmado_em']?.toString(),
      );

  final String orderId;
  final String? criadoEm;
  final String? loja;
  final String? cliente;
  final String? estado;
  final String? tipo;
  final String? nif;
  final bool? dado;
  final String? motivo;
  final String? confirmadoEm;

  /// "Não dado" ou ainda sem resposta do entregador.
  bool get problema => dado != true;

  String get tipoTexto => tipo == 'cliente' ? 'do cliente' : 'da Bora';

  String get respostaTexto {
    if (dado == true) return 'Dado ✓';
    if (dado == false) {
      final m = (motivo ?? '').trim();
      return m.isEmpty ? 'Não dado' : 'Não dado: $m';
    }
    return 'Ainda não confirmado';
  }

  Map<String, dynamic> paraCsv() => {
        'order_id': orderId,
        'criado_em': criadoEm,
        'loja': loja,
        'cliente': cliente,
        'estado': estado,
        'tipo': tipoTexto,
        'nif': nif,
        'resposta': respostaTexto,
        'confirmado_em': confirmadoEm,
      };
}

class AdminNifComprasScreen extends StatefulWidget {
  const AdminNifComprasScreen({
    super.key,
    this.listar,
    this.lerNifBora,
    this.definirNifBora,
  });

  /// Testes: em vez do Supabase.
  final Future<List<Map<String, dynamic>>> Function(int dias)? listar;
  final Future<String?> Function()? lerNifBora;
  final Future<void> Function(String nif)? definirNifBora;

  static const List<(String, String)> colunasCsv = [
    ('order_id', 'Pedido'),
    ('criado_em', 'Criado em (Lisboa)'),
    ('loja', 'Loja'),
    ('cliente', 'Cliente'),
    ('estado', 'Estado do pedido'),
    ('tipo', 'NIF de quem'),
    ('nif', 'NIF'),
    ('resposta', 'Resposta do entregador'),
    ('confirmado_em', 'Respondido em (Lisboa)'),
  ];

  @override
  State<AdminNifComprasScreen> createState() => _AdminNifComprasScreenState();
}

class _AdminNifComprasScreenState extends State<AdminNifComprasScreen> {
  int _dias = 7;
  bool _soNaoDados = false;
  bool _aCarregar = true;
  String? _erro;
  List<NifCompraLinha> _linhas = const [];
  String? _nifBora;

  @override
  void initState() {
    super.initState();
    _carregar();
    _lerNifBora();
  }

  Future<List<Map<String, dynamic>>> _listar(int dias) async {
    final f = widget.listar;
    if (f != null) return f(dias);
    final res = await Supabase.instance.client
        .rpc('admin_nif_caixa_listar', params: {'p_dias': dias});
    return (res as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final rows = await _listar(_dias);
      if (!mounted) return;
      setState(() {
        _linhas = rows.map(NifCompraLinha.deMapa).toList();
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[AdminNifCompras] lista: $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _erro = servidorAindaSemIsto(e)
            ? kNifComprasNaoPublicada
            : 'Não foi possível carregar: $e';
      });
    }
  }

  Future<void> _lerNifBora() async {
    try {
      final f = widget.lerNifBora;
      final String? v;
      if (f != null) {
        v = await f();
      } else {
        final row = await Supabase.instance.client
            .from('platform_settings')
            .select('value')
            .eq('key', 'nif_compras_nao_parceiro')
            .maybeSingle();
        v = row == null ? null : '${row['value']}';
      }
      if (mounted) setState(() => _nifBora = soDigitosNif(v));
    } catch (e) {
      debugPrint('[AdminNifCompras] NIF da Bora: $e');
    }
  }

  Future<void> _editarNifBora() async {
    final ctrl = TextEditingController(text: _nifBora ?? '');
    String? erro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('NIF da Bora nas compras'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'É o NIF que o entregador dá no caixa quando o cliente NÃO pediu '
                'fatura com NIF (lojas não parceiras e Favores com compra).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('admin_nif_bora_campo'),
                controller: ctrl,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: InputDecoration(
                  labelText: 'NIF (9 dígitos)',
                  errorText: erro,
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('admin_nif_bora_salvar'),
              onPressed: () {
                if (!nifPtValido(soDigitosNif(ctrl.text))) {
                  setD(() => erro =
                      'NIF inválido (o dígito de controle não bate).');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    final nif = soDigitosNif(ctrl.text);
    if (ok != true || !mounted) return;
    try {
      final f = widget.definirNifBora;
      if (f != null) {
        await f(nif);
      } else {
        await Supabase.instance.client
            .rpc('admin_nif_bora_definir', params: {'p_nif': nif});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NIF da Bora salvo: ${formatarNif(nif)}.')));
      await _lerNifBora();
      await _carregar();
    } catch (e) {
      debugPrint('[AdminNifCompras] salvar NIF da Bora: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(servidorAindaSemIsto(e)
              ? kNifComprasNaoPublicada
              : 'Erro ao salvar: $e')));
    }
  }

  List<NifCompraLinha> get _visiveis =>
      _soNaoDados ? _linhas.where((l) => l.problema).toList() : _linhas;

  @override
  Widget build(BuildContext context) {
    final visiveis = _visiveis;
    final dados = _linhas.where((l) => l.dado == true).length;
    final naoDados = _linhas.where((l) => l.dado == false).length;
    final semResposta = _linhas.where((l) => l.dado == null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NIF nas compras'),
        actions: [
          AdminCsvButton(
            nome: 'nif_nas_compras',
            colunas: AdminNifComprasScreen.colunasCsv,
            linhas: () => [for (final l in _visiveis) l.paraCsv()],
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Compras em loja não parceira e Favores com compra: o NIF que o '
            'entregador tinha de dar no caixa (do cliente, se pediu fatura; '
            'senão o da Bora — nunca "consumidor final") e se ele deu.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const Key('admin_nif_bora_cartao'),
              leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
              title: Text(
                  'NIF da Bora: ${_nifBora == null || _nifBora!.isEmpty ? '—' : formatarNif(_nifBora)}'),
              subtitle: const Text(
                  'Usado quando o cliente não pede fatura com NIF.'),
              trailing: TextButton.icon(
                key: const Key('admin_nif_bora_editar'),
                onPressed: _editarNifBora,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final d in const [7, 30])
                ChoiceChip(
                  key: Key('admin_nif_dias_$d'),
                  label: Text('$d dias'),
                  selected: _dias == d,
                  onSelected: (_) {
                    if (_dias == d) return;
                    setState(() => _dias = d);
                    _carregar();
                  },
                ),
              FilterChip(
                key: const Key('admin_nif_so_nao_dados'),
                label: const Text('Só os não dados (ou sem resposta)'),
                selected: _soNaoDados,
                onSelected: (v) => setState(() => _soNaoDados = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_aCarregar)
            const LinearProgressIndicator()
          else if (_erro != null)
            Text(_erro!,
                key: const Key('admin_nif_erro'),
                style: const TextStyle(color: AppColors.error))
          else ...[
            Text(
              '${_linhas.length} compras · $dados com NIF dado · $naoDados não dados · '
              '$semResposta sem resposta',
              key: const Key('admin_nif_resumo'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (visiveis.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Nada nestes dias.')),
              ),
            for (final l in visiveis) _linha(l),
          ],
        ],
      ),
    );
  }

  Widget _linha(NifCompraLinha l) {
    final cor = l.dado == true
        ? AppColors.success
        : (l.dado == false ? AppColors.error : AppColors.textSecondary);
    return Card(
      child: ListTile(
        key: Key('admin_nif_linha_${l.orderId}'),
        title: Text(
            '${l.loja ?? 'Loja'} · ${dataHoraLisboa(l.criadoEm)}'
            '${(l.cliente ?? '').trim().isEmpty ? '' : ' · ${l.cliente}'}'),
        subtitle: Text(
          'NIF ${formatarNif(l.nif)} (${l.tipoTexto}) — ${l.respostaTexto}',
          style: TextStyle(color: cor, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AdminOrderDetailScreen(orderId: l.orderId))),
      ),
    );
  }
}
