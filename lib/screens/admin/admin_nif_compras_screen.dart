// Painel admin (PT-BR) — "NIF nas compras" (M10 b2-nif, 09/11/2026).
//
// Regra em vigor (Danilo, 10/11/2026, fechada com o contabilista; substitui a
// de 04/11 e 08/11): nas compras em loja NÃO parceira e nos Favores com compra,
// o entregador só dá NIF no caixa quando o CLIENTE pediu fatura com NIF. Sem NIF
// do cliente o talão é consumidor final. O NIF da Bora nunca vai no caixa (foi
// tirado do sistema a 10/11; o cartão e o editor dele saíram deste ecrã).
// Aqui o admin vê, pedido a pedido, o NIF do cliente que devia ser dado e se o
// entregador confirmou que deu ("Dei este NIF") ou disse "Não consegui" com o
// motivo; filtra 7/30 dias e "só os não dados"; exporta CSV.
//
// Servidor: RPC admin_nif_caixa_listar (só lista pedidos em que o cliente pediu
// NIF). Sem ela: aviso "ainda não publicada".
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

  /// Só o NIF do cliente vai no caixa (regra de 10/11/2026).
  String get tipoTexto => tipo == 'cliente' ? 'do cliente' : 'outro (rever)';

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
  const AdminNifComprasScreen({super.key, this.listar});

  /// Testes: em vez do Supabase.
  final Future<List<Map<String, dynamic>>> Function(int dias)? listar;

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

  @override
  void initState() {
    super.initState();
    _carregar();
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
            'Compras em loja não parceira e Favores com compra em que o cliente '
            'pediu fatura com NIF: o NIF que o entregador tinha de dar no caixa '
            'e se ele deu. Sem NIF do cliente o talão é consumidor final (o NIF '
            'da Bora não vai no caixa) e o pedido não aparece aqui.',
            key: Key('admin_nif_regra'),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
