import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_menu_registry.dart';

/// Menu do painel admin (PT-BR): busca no topo, favoritos fixos, secções
/// fechadas que abrem ao toque, e "Arquivado" no fim, escondido por defeito.
///
/// É um widget puro — recebe as secções, os favoritos e os contadores, e
/// não fala com o servidor. Assim testa-se sem Supabase e o dashboard fica
/// só com o que é dele: carregar números e desenhar cartões.
class AdminMenuAccordion extends StatefulWidget {
  const AdminMenuAccordion({
    super.key,
    required this.sections,
    required this.favoritos,
    required this.onToggleFavorito,
    this.badges = const {},
    this.onOpen,
  });

  final List<AdminMenuSection> sections;

  /// ids dos itens fixados pelo Danilo, pela ordem em que os fixou.
  final List<String> favoritos;
  final void Function(String id) onToggleFavorito;

  /// Contadores dinâmicos por chave de badge ('acertos', 'skills', …).
  final Map<String, int> badges;

  /// Quem abre o ecrã. Nulo = `Navigator.push` normal.
  final void Function(BuildContext, AdminMenuItem)? onOpen;

  @override
  State<AdminMenuAccordion> createState() => _AdminMenuAccordionState();
}

class _AdminMenuAccordionState extends State<AdminMenuAccordion> {
  final _busca = TextEditingController();
  String _q = '';
  bool _mostrarArquivado = false;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<AdminMenuItem> get _todos =>
      widget.sections.expand((s) => s.items).toList();

  void _abrir(BuildContext context, AdminMenuItem item) {
    if (widget.onOpen != null) {
      widget.onOpen!(context, item);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => item.builder()));
  }

  @override
  Widget build(BuildContext context) {
    final favoritos = widget.favoritos
        .map((id) => _todos.where((i) => i.id == id).firstOrNull)
        .whereType<AdminMenuItem>()
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _busca,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          hintText: 'Buscar um ecrã pelo nome (ex.: acertos, corridas, tokens)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _busca.clear();
                    setState(() => _q = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 12),
      if (_q.trim().isNotEmpty) ...[
        _resultadosBusca(context),
      ] else ...[
        if (favoritos.isNotEmpty) ...[
          _titulo('Favoritos', Icons.push_pin_outlined),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: favoritos
                .map((it) => ActionChip(
                      avatar: Icon(it.icon, size: 16, color: it.color),
                      label: Text(it.title),
                      onPressed: () => _abrir(context, it),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
        ],
        ...widget.sections.where((s) => !s.archived).map(_seccao),
        _arquivado(),
      ],
    ]);
  }

  Widget _titulo(String t, IconData i) => Row(children: [
        Icon(i, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      ]);

  Widget _resultadosBusca(BuildContext context) {
    final hits = _todos.where((i) => i.matches(_q)).toList();
    if (hits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Nenhum ecrã com esse nome.')),
      );
    }
    return Column(children: hits.map((i) => _linha(i)).toList());
  }

  Widget _seccao(AdminMenuSection s) {
    final badgeTotal = s.items
        .map((i) => i.badge == null ? 0 : (widget.badges[i.badge!] ?? 0))
        .fold<int>(0, (a, b) => a + b);
    return Card(
      key: ValueKey('sec_${s.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: s.color.withValues(alpha: 0.12),
          child: Icon(s.icon, color: s.color),
        ),
        title: Row(children: [
          Expanded(
            child: Text(s.title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (badgeTotal > 0) _badge(badgeTotal),
          const SizedBox(width: 6),
          Text('${s.items.length}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle)),
        ]),
        subtitle: Text(s.subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: s.items.map(_linha).toList(),
      ),
    );
  }

  Widget _arquivado() {
    final arq = widget.sections.where((s) => s.archived).toList();
    if (arq.isEmpty) return const SizedBox.shrink();
    final n = arq.fold<int>(0, (a, s) => a + s.items.length);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 6),
      TextButton.icon(
        key: const ValueKey('btn_arquivado'),
        onPressed: () => setState(() => _mostrarArquivado = !_mostrarArquivado),
        icon: Icon(_mostrarArquivado
            ? Icons.visibility_off_outlined
            : Icons.inventory_2_outlined),
        label: Text(_mostrarArquivado
            ? 'Esconder o arquivado'
            : 'Mostrar o arquivado ($n ecrãs que você não usa)'),
      ),
      if (_mostrarArquivado) ...arq.map(_seccao),
    ]);
  }

  Widget _linha(AdminMenuItem i) {
    final fav = widget.favoritos.contains(i.id);
    final n = i.badge == null ? 0 : (widget.badges[i.badge!] ?? 0);
    return ListTile(
      key: ValueKey('item_${i.id}'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: i.color.withValues(alpha: 0.12),
        child: Icon(i.icon, size: 16, color: i.color),
      ),
      title: Row(children: [
        Expanded(
            child: Text(i.title,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        if (n > 0) _badge(n),
      ]),
      subtitle: Text(
        i.archivedReason != null ? '${i.subtitle} · ${i.archivedReason}' : i.subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: IconButton(
        tooltip: fav ? 'Tirar dos favoritos' : 'Fixar nos favoritos',
        icon: Icon(fav ? Icons.push_pin : Icons.push_pin_outlined,
            size: 18, color: fav ? AppColors.accent : AppColors.textSubtle),
        onPressed: () => widget.onToggleFavorito(i.id),
      ),
      onTap: () => _abrir(context, i),
    );
  }

  Widget _badge(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(n > 99 ? '99+' : '$n',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}
