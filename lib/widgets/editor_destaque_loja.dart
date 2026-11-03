import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/destaque_loja_service.dart';

/// Textos do editor: o painel do parceiro é PT-PT, o do admin PT-BR.
class EditorDestaqueTextos {
  const EditorDestaqueTextos({
    required this.titulo,
    required this.ajuda,
    required this.produto,
    required this.semDestaque,
    required this.selo,
    required this.guardar,
    required this.tirar,
    required this.guardado,
    required this.tirado,
    required this.erro,
  });

  final String titulo;
  final String ajuda;
  final String produto;
  final String semDestaque;
  final String selo;
  final String guardar;
  final String tirar;
  final String guardado;
  final String tirado;
  final String erro;

  /// Painel do parceiro (PT-PT).
  static const parceiro = EditorDestaqueTextos(
    titulo: '🔥 Produto em destaque',
    ajuda: 'Aparece em grande no topo da tua loja na app, como o hambúrguer do mês.',
    produto: 'Produto',
    semDestaque: 'Sem destaque',
    selo: 'Selo (ex.: Hambúrguer do mês)',
    guardar: 'Guardar',
    tirar: 'Tirar destaque',
    guardado: 'Destaque guardado.',
    tirado: 'Destaque tirado.',
    erro: 'Não foi possível guardar o destaque.',
  );

  /// Painel admin (PT-BR).
  static const admin = EditorDestaqueTextos(
    titulo: '🔥 Produto em destaque',
    ajuda: 'Aparece grande no topo da loja no app (ex.: hambúrguer do mês). '
        'O parceiro também pode trocar pelo painel dele.',
    produto: 'Produto',
    semDestaque: 'Sem destaque',
    selo: 'Selo (ex.: Hambúrguer do mês)',
    guardar: 'Salvar',
    tirar: 'Remover destaque',
    guardado: 'Destaque salvo.',
    tirado: 'Destaque removido.',
    erro: 'Não deu para salvar o destaque.',
  );
}

/// Um produto que se pode pôr em destaque.
class ProdutoEscolhivel {
  const ProdutoEscolhivel(this.id, this.nome);
  final String id;
  final String nome;
}

typedef GuardarDestaque = Future<void> Function(String? produtoId, String? rotulo);

/// Escolher o produto em destaque da loja e o selo, ou tirar (02/11/2026,
/// missão boom-hamburguer-mes, bloco C). Dobrável: fechado mostra o estado.
class EditorDestaqueLoja extends StatefulWidget {
  const EditorDestaqueLoja({
    super.key,
    required this.produtos,
    required this.inicial,
    required this.onGuardar,
    this.textos = EditorDestaqueTextos.parceiro,
  });

  final List<ProdutoEscolhivel> produtos;
  final DestaqueLoja? inicial;
  final GuardarDestaque onGuardar;
  final EditorDestaqueTextos textos;

  @override
  State<EditorDestaqueLoja> createState() => _EditorDestaqueLojaState();
}

class _EditorDestaqueLojaState extends State<EditorDestaqueLoja> {
  String? _produtoId;
  late final TextEditingController _selo;
  bool _aGuardar = false;

  @override
  void initState() {
    super.initState();
    _produtoId = widget.inicial?.produtoId;
    _selo = TextEditingController(
        text: widget.inicial?.rotulo ?? DestaqueLoja.rotuloPorDefeito);
  }

  @override
  void didUpdateWidget(covariant EditorDestaqueLoja old) {
    super.didUpdateWidget(old);
    if (old.inicial?.produtoId != widget.inicial?.produtoId ||
        old.inicial?.rotulo != widget.inicial?.rotulo) {
      _produtoId = widget.inicial?.produtoId;
      _selo.text = widget.inicial?.rotulo ?? DestaqueLoja.rotuloPorDefeito;
    }
  }

  @override
  void dispose() {
    _selo.dispose();
    super.dispose();
  }

  String? get _nomeAtual {
    final id = widget.inicial?.produtoId;
    if (id == null) return null;
    for (final p in widget.produtos) {
      if (p.id == id) return p.nome;
    }
    return id;
  }

  Future<void> _guardar(String? produtoId) async {
    final t = widget.textos;
    setState(() => _aGuardar = true);
    try {
      final selo = _selo.text.trim();
      await widget.onGuardar(produtoId, selo.isEmpty ? null : selo);
      if (!mounted) return;
      if (produtoId == null) setState(() => _produtoId = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(produtoId == null ? t.tirado : t.guardado)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.erro)));
    } finally {
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.textos;
    final atual = _nomeAtual;
    final valido = _produtoId == null || widget.produtos.any((p) => p.id == _produtoId);
    return Card(
      key: const Key('editor_destaque_loja'),
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ExpansionTile(
        title: Text(t.titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        subtitle: Text(
          atual == null ? t.semDestaque : '$atual · ${widget.inicial!.rotulo}',
          key: const Key('editor_destaque_estado'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(t.ajuda,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('editor_destaque_produto'),
            initialValue: valido ? _produtoId : null,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: t.produto, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(t.semDestaque)),
              for (final p in widget.produtos)
                DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(p.nome, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _aGuardar ? null : (v) => setState(() => _produtoId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('editor_destaque_selo'),
            controller: _selo,
            maxLength: 40,
            decoration: InputDecoration(
                labelText: t.selo, border: const OutlineInputBorder()),
          ),
          Row(
            children: [
              if (widget.inicial != null)
                TextButton(
                  key: const Key('editor_destaque_tirar'),
                  onPressed: _aGuardar ? null : () => _guardar(null),
                  child: Text(t.tirar),
                ),
              const Spacer(),
              FilledButton(
                key: const Key('editor_destaque_guardar'),
                onPressed: _aGuardar ? null : () => _guardar(_produtoId),
                child: Text(t.guardar),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
