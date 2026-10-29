// lib/screens/client/receita_do_dia_screen.dart
//
// Ecrã da Receita do Dia (Bora Todo Dia, 15/10/2026): ingredientes, modo de
// preparação, o interruptor do aviso diário (opt-in) e o botão "Pôr no
// carrinho", que cota os ingredientes nos supermercados não-parceiros pelo
// motor do Bora Assistente e enche o carrinho do mais barato pelo caminho
// normal da loja (`encherCarrinhoDaProposta`). Não calcula preços.
// Um laranja só: o botão "Pôr no carrinho".
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../services/assistant_service.dart';
import '../../services/receita_service.dart';
import '../../stores/cart_store.dart';
import '../../stores/restaurant_store.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'assistant/assistant_encher_carrinho.dart';

class ReceitaDoDiaScreen extends StatefulWidget {
  const ReceitaDoDiaScreen({
    super.key,
    required this.hoje,
    this.cotar,
    this.encher,
  });

  final ReceitaHoje hoje;

  /// Cota os ingredientes. Por omissão: supermercados não-parceiros abertos +
  /// morada do carrinho (`ReceitaService.cotarCesto`). Existe para os testes.
  final Future<ReceitaCesto> Function(ReceitaDoDia receita)? cotar;

  /// Enche o carrinho com a proposta escolhida. Por omissão:
  /// `encherCarrinhoDaProposta`. Existe para os testes.
  final Future<bool> Function(BuildContext context, AssistantProposal proposta)?
      encher;

  @override
  State<ReceitaDoDiaScreen> createState() => _ReceitaDoDiaScreenState();
}

class _ReceitaDoDiaScreenState extends State<ReceitaDoDiaScreen> {
  late ReceitaHoje _hoje = widget.hoje;
  bool _aMontar = false;
  bool _aGravarAviso = false;

  void _aviso(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _mudarAviso(bool ligado) async {
    if (_aGravarAviso) return;
    final antes = _hoje;
    setState(() {
      _aGravarAviso = true;
      _hoje = _hoje.copyWith(avisoLigado: ligado);
    });
    try {
      final ficou = await ReceitaService.instance.definirAviso(ligado);
      if (!mounted) return;
      setState(() => _hoje = _hoje.copyWith(avisoLigado: ficou));
    } catch (e) {
      debugPrint('[Receita] aviso: $e');
      if (!mounted) return;
      setState(() => _hoje = antes);
      _aviso('Não foi possível gravar agora. Tenta outra vez.'.tr);
    } finally {
      if (mounted) setState(() => _aGravarAviso = false);
    }
  }

  /// O caminho normal: supermercados não-parceiros + a morada escolhida no
  /// carrinho, como o Bora Assistente faz.
  Future<ReceitaCesto> _cotarPorOmissao(ReceitaDoDia receita) async {
    final store = context.read<RestaurantStore>();
    final cart = context.read<CartStore>();
    if (!store.restaurantsLoadedOnce) {
      await store.loadRestaurantsFromSupabase();
    }
    final mercados = ReceitaService.mercadosNaoParceiros(store.restaurants);
    final entrega = cart.deliveryLocation;
    return ReceitaService.instance.cotarCesto(
      receita,
      mercados,
      lat: entrega?.latitude,
      lng: entrega?.longitude,
      apartamento: cart.apartmentDelivery,
    );
  }

  Future<void> _porNoCarrinho() async {
    if (_aMontar) return;
    setState(() => _aMontar = true);
    try {
      final cesto = await (widget.cotar ?? _cotarPorOmissao)(_hoje.receita);
      if (!mounted) return;
      final p = cesto.proposta;
      if (p == null) {
        _aviso(cesto.erro == 'sem_morada'
            ? 'Escolhe primeiro a tua morada de entrega na página inicial.'.tr
            : 'Não encontrámos estes ingredientes nos supermercados agora. Tenta mais tarde.'
                .tr);
        return;
      }
      // O cliente vê exactamente o que vai para o carrinho antes de entrar.
      final nomes = <String, String>{
        for (final i in _hoje.receita.ingredientes) i.pesquisa: i.nome,
      };
      final faltam =
          p.missingItems.map((m) => nomes[m.query] ?? m.query).join(', ');
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('No carrinho do {0}'.trArgs([p.restaurantName])),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final it in p.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${it.quantity} × ${it.name}',
                        style: const TextStyle(fontSize: 14)),
                  ),
                if (faltam.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Não há: {0}.'.trArgs([faltam]),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Pôr no carrinho'.tr),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
      await (widget.encher ?? encherCarrinhoDaProposta)(context, p);
    } catch (e) {
      debugPrint('[Receita] carrinho: $e');
      if (mounted) {
        _aviso('Não foi possível montar o carrinho agora. Tenta outra vez.'.tr);
      }
    } finally {
      if (mounted) setState(() => _aMontar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _hoje.receita;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Receita do dia'.tr),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxxl),
        children: [
          if (r.fotoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: r.fotoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: AppColors.primaryWash),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          Text(
            r.titulo,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (r.resumo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.resumo,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (r.tempoMin != null)
                _Etiqueta(
                    icone: Icons.schedule,
                    texto: '{0} min'.trArgs([r.tempoMin!])),
              if (r.doses != null)
                _Etiqueta(
                    icone: Icons.people_outline,
                    texto: '{0} pessoas'.trArgs([r.doses!])),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _Titulo(texto: 'Ingredientes'.tr),
          const SizedBox(height: Spacing.sm),
          for (final i in r.ingredientes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      i.quantidade.isEmpty ? i.nome : '${i.nome} — ${i.quantidade}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Spacing.lg),
          _Titulo(texto: 'Como fazer'.tr),
          const SizedBox(height: Spacing.sm),
          for (var n = 0; n < r.passos.length; n++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primaryWash,
                    child: Text(
                      '${n + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(r.passos[n],
                        style: const TextStyle(fontSize: 15, height: 1.35)),
                  ),
                ],
              ),
            ),
          if (_hoje.avisoDisponivel) ...[
            const SizedBox(height: Spacing.md),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: SwitchListTile(
                key: const Key('receita_aviso_switch'),
                value: _hoje.avisoLigado,
                onChanged: _aGravarAviso ? null : _mudarAviso,
                title: Text(
                  'Avisar-me todos os dias às {0}h'.trArgs([_hoje.avisoHora]),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Uma notificação com a receita do dia. Desligas quando quiseres.'
                      .tr,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            key: const Key('receita_por_no_carrinho'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _aMontar ? null : _porNoCarrinho,
            icon: _aMontar
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.shopping_cart_outlined),
            label: Text(
              _aMontar ? 'A procurar o mais barato…'.tr : 'Pôr no carrinho'.tr,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icone, required this.texto});
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(texto,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
}
