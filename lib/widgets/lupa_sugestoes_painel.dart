import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../utils/lupa_sugestoes.dart';
import '../utils/pesquisa_lupa.dart';

/// Lista de sugestões da lupa com 1 ou 2 letras (17/11/2026, lupa-sugestoes).
///
/// Pede à RPC `lupa_sugestoes` quando a pessoa pára [espera] (250 ms) e guarda
/// cada prefixo [kMemoriaSugestoes] (10 min) no telemóvel. Sem sugestões, ou se
/// o servidor falhar, mostra só "Escreve mais letras…" — nunca "não encontrei".
class LupaSugestoesPainel extends StatefulWidget {
  const LupaSugestoesPainel({
    super.key,
    required this.texto,
    required this.aoEscolher,
    this.restaurantId,
    this.fonte,
    this.memoria,
    this.espera = kEsperaSugestoes,
  });

  /// O que está escrito na lupa (1 ou 2 letras).
  final String texto;

  /// null = lupa da página inicial; senão só as sugestões dessa loja.
  final String? restaurantId;

  final ValueChanged<SugestaoLupa> aoEscolher;

  /// Por defeito o servidor ([sugestoesDoServidor]); nos testes, uma falsa.
  final FonteSugestoes? fonte;

  /// Por defeito a memória partilhada ([memoriaSugestoes]).
  final MemoriaPesquisa<List<SugestaoLupa>>? memoria;

  final Duration espera;

  @override
  State<LupaSugestoesPainel> createState() => _LupaSugestoesPainelState();
}

class _LupaSugestoesPainelState extends State<LupaSugestoesPainel> {
  late final LupaAgendada<List<SugestaoLupa>> _lupa =
      LupaAgendada<List<SugestaoLupa>>(
    buscar: (t) => (widget.fonte ?? sugestoesDoServidor)(t, widget.restaurantId),
    memoria: widget.memoria ?? memoriaSugestoes,
    espera: widget.espera,
  );

  List<SugestaoLupa> _lista = const <SugestaoLupa>[];

  @override
  void initState() {
    super.initState();
    _pedir();
  }

  @override
  void didUpdateWidget(covariant LupaSugestoesPainel antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.texto != widget.texto ||
        antigo.restaurantId != widget.restaurantId) {
      _pedir();
    }
  }

  void _pedir() {
    final t = widget.texto.trim();
    if (modoDaLupa(t) != ModoLupa.sugestoes) {
      _lupa.parar();
      return;
    }
    // A sugestão que já está na memória aparece logo, sem esperar. (_pedir só
    // corre em initState/didUpdateWidget, a seguir aos quais vem sempre um
    // build: basta mudar a lista.)
    final chave = chaveDaPesquisa(t, loja: widget.restaurantId);
    final guardada = (widget.memoria ?? memoriaSugestoes).ler(chave);
    if (guardada != null) {
      _lupa.parar();
      _lista = guardada;
      return;
    }
    _lupa.escrever(
      t,
      chave,
      aoChegar: (lista) {
        if (mounted) setState(() => _lista = lista);
      },
      aoFalhar: (_) {
        if (mounted) setState(() => _lista = const <SugestaoLupa>[]);
      },
    );
  }

  @override
  void dispose() {
    _lupa.dispose();
    super.dispose();
  }

  IconData _icone(TipoSugestao t) => switch (t) {
        TipoSugestao.produto => Icons.shopping_basket_outlined,
        TipoSugestao.seccao => Icons.category_outlined,
        TipoSugestao.loja => Icons.storefront_outlined,
        TipoSugestao.palavra => Icons.search,
      };

  @override
  Widget build(BuildContext context) {
    // Só as sugestões que começam pelo que está escrito agora (a lista da
    // letra anterior não fica à vista enquanto chega a nova).
    final prefixo = normalizarParaSugestao(widget.texto);
    final visiveis = _lista
        .where((s) => normalizarParaSugestao(s.texto).startsWith(prefixo))
        .toList(growable: false);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final s in visiveis)
          ListTile(
            key: ValueKey('sugestao-${s.tipo.name}-${s.ref ?? s.texto}'),
            dense: true,
            leading: Icon(_icone(s.tipo),
                size: 20, color: AppColors.textSecondary),
            title: Text(
              s.texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            trailing: const Icon(Icons.north_west,
                size: 16, color: AppColors.textSecondary),
            onTap: () => widget.aoEscolher(s),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            'Escreve mais letras para ver todos os produtos.'.tr,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Minúsculas, sem acentos, só letras/algarismos e espaços simples — o mesmo
/// que `lupa_norm` no servidor, para comparar o começo do texto.
String normalizarParaSugestao(String texto) {
  const de = 'àáâãäåèéêëìíîïòóôõöùúûüýÿñç';
  const para = 'aaaaaaeeeeiiiiooooouuuuyync';
  final b = StringBuffer();
  for (final r in texto.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
