// "Personalizados" (missão a3-guarda-16-11, parte 2; Bloco 2.4 da caixa 111).
// Produtos marcados personalizavel = true pedem foto + texto; o cliente vê uma pré-visualização
// simples (a foto no produto) e a nota "a loja envia prova antes de produzir". Vai a orçamento:
// a loja manda o preço, o cliente aceita no ecrã do pedido.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/impressao_service.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/bora/bora_bottom_action_bar.dart';
import '../../widgets/bora/bora_primary_button.dart';
import 'impressao_estado_screen.dart';

class PersonalizadosScreen extends StatefulWidget {
  const PersonalizadosScreen({super.key, required this.restaurantId, required this.lojaNome});
  final String restaurantId;
  final String lojaNome;

  @override
  State<PersonalizadosScreen> createState() => _PersonalizadosScreenState();
}

class _PersonalizadosScreenState extends State<PersonalizadosScreen> {
  late final Future<List<Map<String, dynamic>>> _f = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() async {
    final r = await Supabase.instance.client
        .from('products')
        .select('id,name,photo_url,price,description')
        .eq('restaurant_id', widget.restaurantId)
        .eq('personalizavel', true)
        .order('sort_order');
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Personalizados')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Não foi possível carregar.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          if (l.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Ainda não há personalizados nesta loja.')));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
            itemCount: l.length,
            itemBuilder: (context, i) {
              final p = l[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PersonalizadoPedirScreen(restaurantId: widget.restaurantId, lojaNome: widget.lojaNome, produto: p),
                  )),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: p['photo_url'] == null
                          ? const Icon(Icons.card_giftcard, size: 48, color: AppColors.primary)
                          : Image.network(p['photo_url'] as String, fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((p['name'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Preço a confirmar pela loja', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PersonalizadoPedirScreen extends StatefulWidget {
  const PersonalizadoPedirScreen({super.key, required this.restaurantId, required this.lojaNome, required this.produto});
  final String restaurantId;
  final String lojaNome;
  final Map<String, dynamic> produto;

  @override
  State<PersonalizadoPedirScreen> createState() => _PersonalizadoPedirScreenState();
}

class _PersonalizadoPedirScreenState extends State<PersonalizadoPedirScreen> {
  final _svc = ImpressaoService();
  final _texto = TextEditingController();
  final _nota = TextEditingController();
  final _morada = TextEditingController();
  Uint8List? _foto;
  String _fotoExt = 'jpg';
  int _qtd = 1;
  String _modo = 'levantar';
  bool _aEnviar = false;

  @override
  void dispose() {
    _texto.dispose();
    _nota.dispose();
    _morada.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    final x = await SafeImagePicker.pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (x == null) return;
    final b = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _foto = b;
      _fotoExt = x.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    });
  }

  Future<void> _enviar() async {
    if (_foto == null && _texto.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Junte uma foto ou um texto.')));
      return;
    }
    if (_modo == 'entrega' && _morada.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta a morada de entrega.')));
      return;
    }
    setState(() => _aEnviar = true);
    try {
      String? path;
      if (_foto != null) {
        path = await _svc.subirFicheiro(bytes: _foto!, extensao: _fotoExt, contentType: _fotoExt == 'png' ? 'image/png' : 'image/jpeg');
      }
      final r = await _svc.criar(widget.restaurantId, {
        'tipo': 'personalizado',
        'product_id': widget.produto['id'],
        'texto': _texto.text.trim(),
        'foto_path': path,
        'copias': _qtd,
        'modo': _modo,
        'morada': _modo == 'entrega' ? _morada.text.trim() : null,
        'nota': _nota.text.trim(),
      });
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ImpressaoEstadoScreen(pedidoId: r['id'].toString(), lojaNome: widget.lojaNome),
      ));
    } on ImpressaoErro catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  /// Pré-visualização simples: a foto do cliente dentro do produto, com o texto por baixo.
  Widget _previa() {
    final foto = widget.produto['photo_url'] as String?;
    return AspectRatio(
      aspectRatio: 1.3,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (foto != null) Opacity(opacity: 0.35, child: Image.network(foto, fit: BoxFit.cover)),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 150,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider, width: 2),
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                ),
                clipBehavior: Clip.antiAlias,
                child: _foto != null
                    ? Image.memory(_foto!, fit: BoxFit.cover)
                    : const Icon(Icons.add_photo_alternate, size: 44, color: AppColors.textSecondary),
              ),
              if (_texto.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    color: Colors.white.withValues(alpha: 0.85),
                    child: Text(_texto.text.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text((widget.produto['name'] ?? 'Personalizado').toString())),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _previa(),
        const SizedBox(height: 8),
        const Text('Pré-visualização simples. A loja envia-lhe uma prova antes de produzir.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _escolherFoto,
          icon: const Icon(Icons.photo_library),
          label: Text(_foto == null ? 'Escolher a foto' : 'Trocar a foto'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _texto,
          maxLength: 300,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Texto (opcional)', border: OutlineInputBorder()),
        ),
        Row(children: [
          const Expanded(child: Text('Quantidade', style: TextStyle(fontWeight: FontWeight.w700))),
          IconButton.filledTonal(onPressed: _qtd > 1 ? () => setState(() => _qtd--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 40, child: Text('$_qtd', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton.filledTonal(onPressed: _qtd < 200 ? () => setState(() => _qtd++) : null, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final m in const [('levantar', 'Levantar na loja'), ('entrega', 'Entrega pelo Bora')])
            ChoiceChip(label: Text(m.$2), selected: _modo == m.$1, onSelected: (_) => setState(() => _modo = m.$1)),
        ]),
        if (_modo == 'entrega')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(controller: _morada, decoration: const InputDecoration(labelText: 'Morada de entrega', border: OutlineInputBorder())),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _nota,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Para quando? Outros pormenores (opcional)', border: OutlineInputBorder()),
        ),
      ]),
      bottomNavigationBar: BoraBottomActionBar(children: [
        BoraPrimaryButton(label: 'Pedir preço à loja', icon: Icons.send, loading: _aEnviar, onPressed: _aEnviar ? null : _enviar),
      ]),
    );
  }
}
