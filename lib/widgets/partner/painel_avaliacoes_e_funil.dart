import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/interruptores_app.dart';
import '../../services/prato_visitas_service.dart';

/// Texto para o parceiro a partir da resposta da Edge Function
/// `resumo-avaliacoes` (`null` = correu bem).
String? avisoDaRespostaDoResumo(Object? r) {
  if (r is! Map) return 'Não foi possível atualizar o resumo.';
  if (r['ok'] == true) return null;
  switch (r['reason']) {
    case 'poucos_comentarios':
      return 'Ainda há poucos comentários para fazer um resumo.';
    case 'desligado':
      return 'O resumo por IA está desligado.';
    case 'gemini_nao_configurado':
      return 'A IA ainda não está configurada.';
  }
  return 'Não foi possível atualizar o resumo.';
}

/// Resumo das avaliações escrito por IA, para o painel do parceiro (adendo 4 ·
/// item 8, 29/10/2026). Lê `restaurant_review_summary` (só o dono e o admin
/// leem) e, se o painel admin deixar (`feature_resumo_avaliacoes_ia`), tem um
/// botão para o atualizar pela Edge Function `resumo-avaliacoes`.
///
/// Sem resumo e com a IA desligada, não desenha nada.
///
/// LIGAR em `lib/screens/partner_dashboard_screen.dart`: ver o relatório.
class ResumoAvaliacoesCard extends StatefulWidget {
  const ResumoAvaliacoesCard({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<ResumoAvaliacoesCard> createState() => _ResumoAvaliacoesCardState();
}

class _ResumoAvaliacoesCardState extends State<ResumoAvaliacoesCard> {
  bool _iaLigada = false;
  String? _resumo;
  int _comentarios = 0;
  bool _aAtualizar = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final ia = await InterruptoresApp.instance
        .ligado(InterruptoresApp.resumoAvaliacoesIa);
    String? resumo;
    var n = 0;
    try {
      final linha = await Supabase.instance.client
          .from('restaurant_review_summary')
          .select('summary, ratings_count')
          .eq('restaurant_id', widget.restaurantId)
          .maybeSingle();
      resumo = (linha?['summary'] as String?)?.trim();
      n = (linha?['ratings_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[ResumoAvaliacoes] $e');
    }
    if (!mounted) return;
    setState(() {
      _iaLigada = ia;
      _resumo = (resumo == null || resumo.isEmpty) ? null : resumo;
      _comentarios = n;
    });
  }

  Future<void> _atualizar() async {
    if (_aAtualizar) return;
    setState(() {
      _aAtualizar = true;
      _aviso = null;
    });
    Object? resposta;
    try {
      final r = await Supabase.instance.client.functions
          .invoke('resumo-avaliacoes', body: {'restaurant_id': widget.restaurantId});
      resposta = r.data;
    } catch (e) {
      debugPrint('[ResumoAvaliacoes] $e');
    }
    if (!mounted) return;
    final aviso = avisoDaRespostaDoResumo(resposta);
    final mapa = resposta is Map ? resposta : null;
    if (aviso == null && mapa != null) {
      setState(() {
        _resumo = '${mapa['resumo'] ?? ''}'.trim();
        _comentarios = (mapa['ratings_count'] as num?)?.toInt() ?? _comentarios;
        _aAtualizar = false;
      });
    } else {
      setState(() {
        _aviso = aviso;
        _aAtualizar = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resumo == null && !_iaLigada) return const SizedBox.shrink();
    return Card(
      key: const Key('resumo_avaliacoes_card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text('O que dizem as avaliações',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_resumo != null) ...[
              Text(_resumo!,
                  key: const Key('resumo_avaliacoes_texto'),
                  style: const TextStyle(fontSize: 16, height: 1.35)),
              const SizedBox(height: 4),
              Text(
                'Resumo escrito por IA com base em $_comentarios comentários. Pode errar: confirma nas avaliações.',
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ] else
              const Text('Ainda não há resumo. Carrega no botão para o criar.',
                  style: TextStyle(fontSize: 16)),
            if (_aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_aviso!,
                    key: const Key('resumo_avaliacoes_aviso'),
                    style: const TextStyle(fontSize: 14, color: AppColors.error)),
              ),
            if (_iaLigada) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('btn_atualizar_resumo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _aAtualizar ? null : _atualizar,
                icon: _aAtualizar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_resumo == null ? 'Criar resumo' : 'Atualizar resumo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Pratos muito vistos e pouco pedidos" (funil), para o painel do parceiro.
/// Usa as aberturas da ficha do prato (`product_view_daily`) contra as
/// unidades pedidas nos últimos 30 dias. Interruptor `feature_funil_pratos`.
///
/// LIGAR em `lib/screens/partner_dashboard_screen.dart`: ver o relatório.
class FunilPratosCard extends StatefulWidget {
  const FunilPratosCard({super.key, required this.restaurantId, this.dias = 30});

  final String restaurantId;
  final int dias;

  @override
  State<FunilPratosCard> createState() => _FunilPratosCardState();
}

class _FunilPratosCardState extends State<FunilPratosCard> {
  bool _ligado = true;
  bool _carregou = false;
  List<PratoNoFunil> _lista = const [];

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final ligado =
        await InterruptoresApp.instance.ligado(InterruptoresApp.funilPratos);
    var lista = <PratoNoFunil>[];
    if (ligado) {
      try {
        lista = await PratoVisitasService.funil(widget.restaurantId,
            dias: widget.dias);
      } catch (e) {
        debugPrint('[FunilPratos] $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _ligado = ligado;
      _lista = muitoVistosEPoucoPedidos(lista);
      _carregou = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado || !_carregou) return const SizedBox.shrink();
    return Card(
      key: const Key('funil_pratos_card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Muito vistos, pouco pedidos',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pratos cuja ficha foi aberta muitas vezes nos últimos ${widget.dias} dias e quase ninguém pediu. Vê a foto, a descrição e o preço.',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (_lista.isEmpty)
              const Text('Ainda não há nenhum prato nesta situação.',
                  key: Key('funil_vazio'), style: TextStyle(fontSize: 16))
            else
              for (final p in _lista.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    key: Key('funil_${p.id}'),
                    children: [
                      Expanded(
                        child: Text(p.nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text('${p.aberturas} vistas · ${p.pedidos} pedidos',
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
