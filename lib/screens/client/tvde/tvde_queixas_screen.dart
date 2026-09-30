import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../services/tvde_conformidade_service.dart';
import '../../../widgets/bora/bora.dart';
import 'tvde_operador_plataforma_screen.dart';

/// Queixas do passageiro TVDE — Lei 45/2018, art. 19.º n.º 3 (versão da
/// Lei 59/2026).
///
/// Três coisas no mesmo sítio: o **Livro de Reclamações Eletrónico** (oficial),
/// o formulário interno da Bora (`tvde_queixa_criar`) com a lista "As minhas
/// queixas", e a informação sobre resolução alternativa de litígios.
/// Com [rideId] a queixa fica ligada a essa viagem.
class TvdeQueixasScreen extends StatefulWidget {
  const TvdeQueixasScreen({super.key, this.rideId});

  final String? rideId;

  @override
  State<TvdeQueixasScreen> createState() => _TvdeQueixasScreenState();
}

/// Categorias aceites pelo servidor, com o rótulo que o passageiro lê.
const kCategoriasQueixaTvde = <String, String>{
  'preco': 'Preço',
  'comportamento': 'Comportamento do motorista',
  'seguranca': 'Segurança',
  'veiculo': 'Veículo',
  'percurso': 'Percurso',
  'pagamento': 'Pagamento',
  'acessibilidade': 'Acessibilidade',
  'dados_pessoais': 'Dados pessoais',
  'outro': 'Outro',
};

const _estados = <String, String>{
  'recebida': 'Recebida',
  'em_analise': 'Em análise',
  'respondida': 'Respondida',
  'resolvida': 'Resolvida',
  'arquivada': 'Arquivada',
};

const _urlPortalConsumidor = 'https://www.consumidor.gov.pt';

class _TvdeQueixasScreenState extends State<TvdeQueixasScreen> {
  final _svc = TvdeConformidadeService.instance;
  final _descricao = TextEditingController();
  final _contacto = TextEditingController();

  String _categoria = 'outro';
  String _livroUrl = TvdeConformidadeConfig.desligado.livroReclamacoesUrl;

  /// Trava LOCAL do envio (PADRAO_BORA 3.13) — nunca um `busy` partilhado.
  bool _enviando = false;
  String? _erroDescricao;

  List<Map<String, dynamic>>? _queixas;
  bool _erroLista = false;

  @override
  void initState() {
    super.initState();
    _carregarConfig();
    _carregarQueixas();
  }

  @override
  void dispose() {
    _descricao.dispose();
    _contacto.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    final cfg = await _svc.config();
    if (!mounted) return;
    setState(() => _livroUrl = cfg.livroReclamacoesUrl);
  }

  Future<void> _carregarQueixas() async {
    try {
      final l = await _svc.minhasQueixas();
      if (!mounted) return;
      setState(() {
        _queixas = l;
        _erroLista = false;
      });
    } catch (e) {
      debugPrint('[TvdeQueixas] lista falhou: $e');
      if (!mounted) return;
      setState(() => _erroLista = true);
    }
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir $url')));
    }
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = _descricao.text.trim();
    if (texto.length < 5) {
      setState(() => _erroDescricao = 'Descreve o que aconteceu.');
      return;
    }
    setState(() {
      _enviando = true;
      _erroDescricao = null;
    });
    try {
      final res = await _svc.criarQueixa(
        rideId: widget.rideId,
        categoria: _categoria,
        descricao: texto,
        contacto: _contacto.text.trim().isEmpty ? null : _contacto.text.trim(),
      );
      if (!mounted) return;
      _descricao.clear();
      _contacto.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Queixa n.º ${res['numero'] ?? ''} registada. Vamos analisar e responder-te.')));
      _carregarQueixas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagemErroConformidade(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Queixas'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
            Spacing.xxl + MediaQuery.of(context).padding.bottom),
        children: [
          // ── Livro de Reclamações Eletrónico ─────────────────────────────
          _Bloco(
            titulo: 'Livro de Reclamações',
            children: [
              const Text(
                'Podes apresentar uma reclamação oficial no Livro de '
                'Reclamações Eletrónico.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                key: const Key('tvde_livro_reclamacoes'),
                onPressed: () => _abrir(_livroUrl),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Abrir o Livro de Reclamações Eletrónico'),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // ── Formulário interno ─────────────────────────────────────────
          _Bloco(
            titulo: 'Fazer uma queixa à Bora',
            children: [
              if (rideId != null) ...[
                Text(
                  'Sobre a viagem ${rideId.replaceAll('-', '').substring(0, 8).toUpperCase()}',
                  key: const Key('tvde_queixa_viagem'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              DropdownButtonFormField<String>(
                key: const Key('tvde_queixa_categoria'),
                initialValue: _categoria,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Assunto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final e in kCategoriasQueixaTvde.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _categoria = v ?? 'outro'),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('tvde_queixa_descricao'),
                controller: _descricao,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: 'O que aconteceu?',
                  border: const OutlineInputBorder(),
                  errorText: _erroDescricao,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('tvde_queixa_contacto'),
                controller: _contacto,
                decoration: const InputDecoration(
                  labelText: 'Contacto para resposta (opcional)',
                  hintText: 'Email ou telemóvel',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Spacing.md),
              BoraAccentButton(
                label: 'Enviar queixa',
                icon: Icons.send,
                loading: _enviando,
                onPressed: _enviando ? null : _enviar,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // ── As minhas queixas ──────────────────────────────────────────
          _Bloco(
            titulo: 'As minhas queixas',
            children: [
              if (_queixas == null && !_erroLista)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(Spacing.md),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              else if (_erroLista)
                Row(
                  children: [
                    const Expanded(
                        child: Text('Não foi possível carregar as queixas.',
                            style: TextStyle(color: AppColors.textSecondary))),
                    TextButton(
                        onPressed: _carregarQueixas,
                        child: const Text('Tentar outra vez')),
                  ],
                )
              else if (_queixas!.isEmpty)
                const Text('Ainda não fizeste nenhuma queixa.',
                    style: TextStyle(color: AppColors.textSecondary))
              else
                for (final q in _queixas!) _QueixaItem(q: q),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // ── Resolução alternativa de litígios ──────────────────────────
          _Bloco(
            titulo: 'Resolução de litígios',
            children: [
              const Text(
                'Em caso de litígio de consumo podes recorrer a um centro de '
                'arbitragem de conflitos de consumo. Mais informação no '
                'Portal do Consumidor: $_urlPortalConsumidor',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('tvde_portal_consumidor'),
                  onPressed: () => _abrir(_urlPortalConsumidor),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir o Portal do Consumidor'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Center(
            child: TextButton.icon(
              key: const Key('tvde_queixas_operador'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TvdeOperadorPlataformaScreen())),
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('Sobre o operador da plataforma'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _QueixaItem extends StatelessWidget {
  const _QueixaItem({required this.q});

  final Map<String, dynamic> q;

  @override
  Widget build(BuildContext context) {
    final estado = q['estado'] as String? ?? 'recebida';
    final categoria = q['categoria'] as String? ?? 'outro';
    final resposta = (q['resposta'] as String?)?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'N.º ${q['numero'] ?? ''} · ${kCategoriasQueixaTvde[categoria] ?? categoria}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              Text(_estados[estado] ?? estado,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          if (resposta != null && resposta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Resposta: $resposta',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
          const Divider(),
        ],
      ),
    );
  }
}
