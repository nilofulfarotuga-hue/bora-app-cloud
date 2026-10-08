// Painel admin (PT-BR) — o Favor no detalhe do pedido (08/10/2026, pedido
// real 74dd4ecc). O Danilo vê e manda:
//  - os 3 passos (casa da cliente → local do favor → entrega) e em qual o
//    entregador está (`orders.errand_passo`);
//  - a foto do pedido (receita) e a foto do talão, ambas com zoom;
//  - compra estimada × valor do talão × total do pedido / a cobrar;
//  - editar o endereço da parada em casa (`admin_favor_editar_paragem`) e
//    mudar o passo à mão (`admin_favor_mudar_passo`). As duas ficam no log
//    de auditoria; nenhuma mexe em valores.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/maps_config.dart';
import '../../models/order_model.dart';
import '../../services/place_autocomplete_service.dart';
import '../../utils/favor_passos.dart';
import '../private_bucket_image.dart';

class AdminFavorPassosSection extends StatefulWidget {
  const AdminFavorPassosSection({
    super.key,
    required this.order,
    required this.onAlterado,
  });

  /// Linha do pedido como vem de `orders` (select do detalhe).
  final Map<String, dynamic> order;

  /// Recarregar o detalhe depois de uma alteração.
  final VoidCallback onAlterado;

  @override
  State<AdminFavorPassosSection> createState() =>
      _AdminFavorPassosSectionState();
}

class _AdminFavorPassosSectionState extends State<AdminFavorPassosSection> {
  Map<String, dynamic>? _talao;
  bool _aGravar = false;

  Map<String, dynamic> get o => widget.order;

  @override
  void initState() {
    super.initState();
    _carregarTalao();
  }

  @override
  void didUpdateWidget(covariant AdminFavorPassosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order['id'] != widget.order['id']) _carregarTalao();
  }

  Future<void> _carregarTalao() async {
    try {
      final r = await Supabase.instance.client
          .from('order_receipts_v2')
          .select('photo_url, driver_typed_total_cents, photo_taken_at')
          .eq('order_id', '${o['id']}')
          .maybeSingle();
      if (mounted) setState(() => _talao = r);
    } catch (e) {
      debugPrint('[AdminFavor] talão: $e');
    }
  }

  OrderModel? get _modelo {
    try {
      return OrderModel.fromSupabase(o);
    } catch (e) {
      debugPrint('[AdminFavor] modelo: $e');
      return null;
    }
  }

  static String _eur(num? v) =>
      v == null ? '—' : '€${v.toDouble().toStringAsFixed(2)}';

  static String _motivo(String? r) => switch (r) {
        'receita' => 'Buscar receita médica',
        'cartao' => 'Buscar cartão',
        'dinheiro' => 'Buscar dinheiro da compra',
        null => '—',
        _ => 'Outro',
      };

  @override
  Widget build(BuildContext context) {
    final modelo = _modelo;
    final rota = modelo == null ? null : FavorRota.de(modelo);
    final fotoPedido = (o['errand_request_photo_url'] as String?)?.trim() ?? '';
    final fotoTalao = (_talao?['photo_url'] as String?)?.trim() ?? '';
    final talaoCents = (_talao?['driver_typed_total_cents'] as num?);
    final finalizado = o['is_purchase_finalized'] == true;
    final totalPedido = finalizado && o['final_total'] != null
        ? o['final_total'] as num
        : (o['price'] as num?);
    final emDinheiro = o['payment_method'] == 'cash';
    final terminal = o['status'] == 'delivered' || o['status'] == 'cancelled';

    return Column(
      key: const Key('admin_favor_passos'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text('Passos do entregador',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (rota == null)
          const Text('—')
        else
          for (var i = 0; i < rota.passos.length; i++)
            _linhaPasso(rota.passos[i],
                atual: i == rota.indiceAtual && !terminal,
                feito: i < rota.indiceAtual || o['status'] == 'delivered'),
        if (o['errand_passo'] == null)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Pedido antigo: o passo foi deduzido pelo status.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        if (o['errand_home_stop'] == true) ...[
          const SizedBox(height: 4),
          Text(
            'Motivo da parada: ${_motivo(o['errand_home_stop_reason'] as String?)}',
            style: const TextStyle(fontSize: 13),
          ),
          if ((o['errand_home_stop_cash_cents'] as num? ?? 0) > 0)
            Text(
              'Dinheiro a pegar em casa: ${_eur((o['errand_home_stop_cash_cents'] as num) / 100)}',
              style: const TextStyle(fontSize: 13),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (o['errand_home_stop'] == true)
              OutlinedButton.icon(
                key: const Key('admin_favor_editar_parada'),
                onPressed: _aGravar ? null : _editarParada,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Editar endereço da parada'),
              ),
            if (!terminal && rota != null)
              OutlinedButton.icon(
                key: const Key('admin_favor_mudar_passo'),
                onPressed: _aGravar ? null : () => _mudarPasso(rota),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Mudar passo'),
              ),
          ],
        ),
        const Divider(),
        const Text('Valores', style: TextStyle(fontWeight: FontWeight.w700)),
        _valor('Compra estimada',
            _eur((o['errand_estimated_purchase_cents'] as num?) == null
                ? null
                : (o['errand_estimated_purchase_cents'] as num) / 100)),
        _valor(
            'Valor do talão',
            o['final_purchase_value'] != null
                ? _eur(o['final_purchase_value'] as num)
                : (talaoCents != null ? _eur(talaoCents / 100) : 'Ainda sem talão')),
        _valor('Total do pedido', _eur(totalPedido),
            ajuda: finalizado ? 'taxas + talão' : 'estimado (antes do talão)'),
        if (emDinheiro)
          _valor('A cobrar em dinheiro',
              _eur((o['cash_total_due'] as num?) ?? totalPedido)),
        const Divider(),
        const Text('Fotos', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _foto('Foto do pedido (receita)', fotoPedido,
                  tituloAmpliada: 'Foto do pedido'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _foto(
                  'Foto do talão',
                  fotoTalao.isEmpty
                      ? ''
                      : withPrivateBucketPrefix('receipts', fotoTalao),
                  tituloAmpliada: 'Foto do talão'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _linhaPasso(FavorPasso p, {required bool atual, required bool feito}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: atual
                ? const Color(0xFF14B8A6)
                : (feito ? AppColors.divider : Colors.white),
            child: feito && !atual
                ? const Icon(Icons.check, size: 14, color: Color(0xFF0F766E))
                : Text('${p.numero}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: atual ? Colors.white : AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atual ? '${p.nome}  ← está aqui' : p.nome,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: atual ? FontWeight.w800 : FontWeight.w600),
                ),
                Text(p.morada.isEmpty ? 'Sem endereço' : p.morada,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valor(String rotulo, String valor, {String? ajuda}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(rotulo,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(ajuda == null ? valor : '$valor  ($ajuda)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _foto(String rotulo, String caminho, {required String tituloAmpliada}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        if (caminho.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.divider.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Sem foto',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          PrivateBucketImage(
            urlOrPath: caminho,
            height: 160,
            fit: BoxFit.contain,
            borderRadius: BorderRadius.circular(8),
            tituloAmpliada: tituloAmpliada,
          ),
      ],
    );
  }

  Future<void> _editarParada() async {
    final ctrl = TextEditingController(
        text: (o['errand_home_stop_address'] as String?) ??
            (o['dropoff_address'] as String?) ??
            '');
    final motivoCtrl = TextEditingController();
    final resultado = await showDialog<_NovaParada>(
      context: context,
      builder: (ctx) => _DialogoParada(
        ctrl: ctrl,
        motivoCtrl: motivoCtrl,
        entregaEndereco: o['dropoff_address'] as String?,
        entregaLat: (o['dropoff_lat'] as num?)?.toDouble(),
        entregaLng: (o['dropoff_lng'] as num?)?.toDouble(),
      ),
    );
    final motivo = motivoCtrl.text.trim();
    ctrl.dispose();
    motivoCtrl.dispose();
    if (resultado == null || !mounted) return;
    await _gravar(
      'admin_favor_editar_paragem',
      {
        'p_order_id': '${o['id']}',
        'p_address': resultado.endereco,
        'p_lat': resultado.lat,
        'p_lng': resultado.lng,
        'p_motivo': motivo.isEmpty ? null : motivo,
      },
      'Endereço da parada atualizado.',
    );
  }

  Future<void> _mudarPasso(FavorRota rota) async {
    var escolhido = passoAtual(_modelo!);
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Mudar passo do entregador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in rota.passos)
                Builder(builder: (_) {
                  final valor = switch (p.tipo) {
                    FavorPassoTipo.casa => 0,
                    FavorPassoTipo.favor => 1,
                    FavorPassoTipo.entrega => 2,
                  };
                  final marcado = escolhido == valor;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                        marcado
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: marcado ? AppColors.primary : null),
                    title: Text('${p.numero}. ${p.nome}'),
                    onTap: () => setD(() => escolhido = valor),
                  );
                }),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final motivo = motivoCtrl.text.trim();
    motivoCtrl.dispose();
    if (ok != true || !mounted) return;
    await _gravar(
      'admin_favor_mudar_passo',
      {
        'p_order_id': '${o['id']}',
        'p_passo': escolhido,
        'p_motivo': motivo.isEmpty ? null : motivo,
      },
      'Passo atualizado.',
    );
  }

  Future<void> _gravar(
      String rpc, Map<String, dynamic> params, String okMsg) async {
    setState(() => _aGravar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await Supabase.instance.client.rpc(rpc, params: params);
      if (r is Map && r['ok'] == true) {
        messenger.showSnackBar(SnackBar(content: Text(okMsg)));
        widget.onAlterado();
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Não salvou: $r')));
      }
    } catch (e) {
      final t = '$e';
      final msg = t.contains('talao_por_fechar')
          ? 'O talão ainda não foi fechado: o entregador tem de passar pela compra antes da entrega.'
          : t.contains('sem_paragem_em_casa')
              ? 'Este favor não tem parada em casa.'
              : t.contains('coordenadas_invalidas')
                  ? 'Não foi possível achar esse endereço no mapa.'
                  : 'Erro ao salvar: $e';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }
}

class _NovaParada {
  const _NovaParada(this.endereco, this.lat, this.lng);
  final String endereco;
  final double lat;
  final double lng;
}

class _DialogoParada extends StatefulWidget {
  const _DialogoParada({
    required this.ctrl,
    required this.motivoCtrl,
    this.entregaEndereco,
    this.entregaLat,
    this.entregaLng,
  });

  final TextEditingController ctrl;
  final TextEditingController motivoCtrl;
  final String? entregaEndereco;
  final double? entregaLat;
  final double? entregaLng;

  @override
  State<_DialogoParada> createState() => _DialogoParadaState();
}

class _DialogoParadaState extends State<_DialogoParada> {
  late final PlaceAutocompleteService _geo =
      createPlaceAutocompleteService(googleApiKey);
  bool _aProcurar = false;
  String? _erro;

  @override
  void dispose() {
    _geo.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final t = widget.ctrl.text.trim();
    if (t.isEmpty) {
      setState(() => _erro = 'Escreva o endereço.');
      return;
    }
    // Igual ao endereço de entrega → usa as coordenadas da entrega.
    if (t == (widget.entregaEndereco ?? '').trim() &&
        widget.entregaLat != null &&
        widget.entregaLng != null) {
      Navigator.pop(context,
          _NovaParada(t, widget.entregaLat!, widget.entregaLng!));
      return;
    }
    setState(() {
      _aProcurar = true;
      _erro = null;
    });
    try {
      final c = await _geo.geocodeAddress(t);
      if (!mounted) return;
      if (c == null) {
        setState(() {
          _aProcurar = false;
          _erro = 'Não achei esse endereço no mapa. Confira e tente de novo.';
        });
        return;
      }
      Navigator.pop(context, _NovaParada(t, c.latitude, c.longitude));
    } catch (e) {
      if (mounted) {
        setState(() {
          _aProcurar = false;
          _erro = 'Erro ao procurar o endereço: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Endereço da parada em casa'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('admin_favor_parada_endereco'),
            controller: widget.ctrl,
            decoration: const InputDecoration(labelText: 'Endereço'),
            maxLines: 2,
          ),
          if ((widget.entregaEndereco ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => widget.ctrl.text = widget.entregaEndereco!),
                child: const Text('Usar o endereço de entrega'),
              ),
            ),
          TextField(
            controller: widget.motivoCtrl,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: AppColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _aProcurar ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _aProcurar ? null : _salvar,
          child: Text(_aProcurar ? 'Procurando…' : 'Salvar'),
        ),
      ],
    );
  }
}
