// Painel admin (PT-BR) — "Talão (foto e NIF)" (08/11/2026, missão
// m1-dinheiro-favores, adendo 1: "toda foto de talão fica guardada para
// sempre — papel fiscal, 10 anos"). No detalhe do pedido o admin vê TODAS as
// fotos do talão que o entregador mandou (cada uma no seu arquivo, nunca
// substituída), o valor que o entregador escreveu, o NIF usado no talão e se
// a foto já tem a 2.ª cópia no Google Drive da Bora.
//
// Servidor: RPC admin_talao_do_pedido(p_order_id). Sem a RPC publicada mostra
// "Função ainda não publicada no servidor" (servidorAindaSemIsto).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../bora_foto_ecra_inteiro.dart';
import '../private_bucket_image.dart';

const String kTalaoFuncaoNaoPublicada = 'Função ainda não publicada no servidor';

/// "29,95 €" a partir de centavos; "—" quando não há valor.
String eurosDoTalao(Object? cents) {
  if (cents is! num) return '—';
  return '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// Linha do NIF usado no talão, a partir de `{nif, origem}` do servidor
/// (`_talao_nif_usado`). Regra de 10/11/2026: sem NIF do cliente o talão é
/// consumidor final — o NIF da Bora nunca vai no talão.
String textoNifUsado(Object? nif) {
  final m = nif is Map ? nif : const <String, dynamic>{};
  final numero = '${m['nif'] ?? ''}'.trim();
  return switch (m['origem']) {
    'loja_parceira' => 'Loja parceira: fatura da loja',
    'cliente' => 'NIF usado: ${numero.isEmpty ? '—' : numero} (pedido pelo cliente)',
    'consumidor_final' => 'Sem NIF: consumidor final (o cliente não pediu fatura com NIF)',
    _ => 'NIF usado: ${numero.isEmpty ? '—' : numero}',
  };
}

/// Pedidos em que o entregador compra e tem de trazer talão: mercados e
/// restaurantes (os parceiros o servidor marca como "loja_parceira") e Favores
/// com compra. Igual ao filtro de admin_pedidos_sem_talao.
bool talaoPrecisa(String? serviceType, {bool errandHasPurchase = false}) =>
    switch (serviceType) {
      'storeShopping' || 'restaurant' => true,
      'errand' => errandHasPurchase,
      _ => false,
    };

/// Caminho da foto pronto para o [PrivateBucketImage] ("receipts/AAAA/MM/…").
String caminhoDaFotoDoTalao(Map<String, dynamic> f) {
  final bucket = '${f['bucket'] ?? ''}'.trim();
  return withPrivateBucketPrefix(bucket.isEmpty ? 'receipts' : bucket, '${f['path'] ?? ''}'.trim());
}

class AdminTalaoPedidoSection extends StatefulWidget {
  const AdminTalaoPedidoSection({
    super.key,
    required this.orderId,
    this.status,
    this.serviceType,
    this.errandHasPurchase = false,
    this.carregar,
  });

  final String orderId;

  /// Status do pedido (`delivered` → sem foto mostra o aviso "Sem talão").
  final String? status;
  final String? serviceType;
  final bool errandHasPurchase;

  /// Só para testes.
  final Future<Map<String, dynamic>> Function(String orderId)? carregar;

  static Future<Map<String, dynamic>> carregarDoServidor(String orderId) async {
    final r = await Supabase.instance.client
        .rpc('admin_talao_do_pedido', params: {'p_order_id': orderId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  @override
  State<AdminTalaoPedidoSection> createState() => _AdminTalaoPedidoSectionState();
}

class _AdminTalaoPedidoSectionState extends State<AdminTalaoPedidoSection> {
  bool _loading = true;
  bool _semServidor = false;
  String? _erro;
  Map<String, dynamic> _talao = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
      _semServidor = false;
    });
    try {
      final r = await (widget.carregar ?? AdminTalaoPedidoSection.carregarDoServidor)(widget.orderId);
      if (!mounted) return;
      setState(() {
        _talao = r;
        _erro = r['ok'] == false ? '${r['error'] ?? 'erro desconhecido'}' : null;
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

  String get _curto =>
      widget.orderId.substring(0, widget.orderId.length < 8 ? widget.orderId.length : 8);

  List<Map<String, dynamic>> get _fotos {
    final l = _talao['fotos'];
    if (l is! List) return const [];
    return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Widget _cartao(List<Widget> filhos) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          key: const Key('admin_talao_pedido'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.receipt_outlined, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Talão (foto e NIF)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Atualizar',
                    onPressed: _loading ? null : _load,
                  ),
                ]),
                ...filhos,
              ],
            ),
          ),
        ),
      );

  Widget _linha(String rotulo, String valor, {Key? key, Color? cor}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$rotulo: ', style: const TextStyle(color: AppColors.textSecondary)),
            TextSpan(text: valor, style: TextStyle(fontWeight: FontWeight.w600, color: cor)),
          ]),
          key: key,
          style: const TextStyle(fontSize: 13),
        ),
      );

  Widget _selo(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          border: Border.all(color: cor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(texto, style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600)),
      );

  Widget _foto(List<Map<String, dynamic>> fotos, int i) {
    final f = fotos[i];
    final antigo = f['origem'] == 'antigo';
    final copia = f['copia_em'] != null;
    return SizedBox(
      key: Key('talao_foto_$i'),
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Ampliar foto do talão',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => BoraFotoEcraInteiro.abrirVarias(
                context,
                [for (final x in fotos) BoraFoto.url(caminhoDaFotoDoTalao(x))],
                inicial: i,
                titulo: 'Talão · pedido $_curto',
              ),
              child: PrivateBucketImage(
                urlOrPath: caminhoDaFotoDoTalao(f),
                width: 120,
                height: 120,
                placeholderHeight: 120,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(Radii.sm),
                tocarParaAmpliar: false,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Recebida ${dataHoraLisboa(f['recebida_em'])}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (f['total_cents'] is num)
            Text(eurosDoTalao(f['total_cents']),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (antigo || copia)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(spacing: 4, runSpacing: 2, children: [
                if (antigo) _selo('antigo', AppColors.textSecondary),
                if (copia) _selo('cópia no Drive ✓', AppColors.success),
              ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final precisa = talaoPrecisa(widget.serviceType, errandHasPurchase: widget.errandHasPurchase);

    if (_loading) {
      return precisa
          ? _cartao(const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ])
          : const SizedBox.shrink();
    }
    if (_semServidor) {
      return precisa
          ? _cartao(const [
              Text(
                '$kTalaoFuncaoNaoPublicada. As fotos do talão aparecem aqui quando a migração '
                'dos talões guardados for aplicada.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ])
          : const SizedBox.shrink();
    }
    if (_erro != null) {
      return precisa
          ? _cartao([
              Text('Não foi possível carregar: $_erro',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ])
          : const SizedBox.shrink();
    }

    final fotos = _fotos;
    final nif = _talao['nif'];
    final parceira = nif is Map && nif['origem'] == 'loja_parceira';
    // Loja parceira passa fatura própria; e pedidos sem compra não têm talão.
    if (fotos.isEmpty && (parceira || !precisa)) return const SizedBox.shrink();

    final entregue = widget.status == 'delivered';
    final fotoAtual = '${_talao['foto_atual'] ?? ''}'.trim();
    final valor = _talao['valor_escrito_cents'];

    return _cartao([
      if (fotos.isEmpty && entregue) ...[
        const Row(
          key: Key('talao_sem_talao'),
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
            SizedBox(width: 6),
            Text('Sem talão',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'Pedido entregue sem foto do talão guardada. O talão é papel fiscal (guardado 10 anos): '
            'peça ao entregador a foto ou o talão em papel.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ] else if (fotos.isEmpty)
        const Text(
          'Ainda sem foto do talão (o entregador tira a foto na loja, na hora da compra).',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      _linha('Valor escrito pelo entregador', valor is num ? eurosDoTalao(valor) : '— (ainda não escrito)'),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(textoNifUsado(nif),
            key: const Key('talao_nif'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      if (fotos.isEmpty && fotoAtual.isNotEmpty)
        _linha('Caminho no registro antigo (sem arquivo guardado)', fotoAtual),
      if (fotos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          fotos.length == 1 ? '1 foto (toque para ampliar)' : '${fotos.length} fotos (toque para ampliar)',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (var i = 0; i < fotos.length; i++) _foto(fotos, i)],
        ),
        const SizedBox(height: 6),
        const Text(
          'Guardadas 10 anos (papel fiscal). Cada foto tem o seu arquivo e nunca é substituída.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ]);
  }
}
