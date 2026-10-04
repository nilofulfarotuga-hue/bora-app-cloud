// Painel admin (PT-BR) — Radar de vídeos (missão radar-videos-crescimento-2026-09-24).
//
// O PC do Danilo recolhe todos os dias ~20 vídeos novos do YouTube sobre crescer no
// Instagram/Facebook/Reels/TikTok e ganhar dinheiro online / marketing de apps, tira a
// transcrição (legendas), pede a um modelo barato (GLM ou Gemini) um resumo, 3 ideias
// práticas e uma nota de utilidade, e guarda em radar_videos. Ao domingo destila o
// «playbook» (regras vistas em 3 ou mais vídeos, com os links como prova), que os robôs de
// conteúdo do Bora e do Em Dia seguem. Aqui: a lista do dia (filtro por tema e por dias) e o
// playbook atual. Só leitura.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';

class AdminRadarVideosScreen extends StatefulWidget {
  const AdminRadarVideosScreen({super.key});

  @override
  State<AdminRadarVideosScreen> createState() => _AdminRadarVideosScreenState();
}

class _AdminRadarVideosScreenState extends State<AdminRadarVideosScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  List<RadarVideo> _videos = const [];
  List<PlaybookRegra> _regras = const [];
  List<RadarPesquisa> _pesquisas = const [];
  String? _tema; // null = todos
  int _dias = 1;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final v = await _c.rpc('admin_radar_videos', params: {'p_dias': _dias, 'p_tema': _tema});
      final p = await _c.rpc('admin_playbook_redes');
      final q = await _c.rpc('admin_radar_pesquisas');
      if (!mounted) return;
      setState(() {
        _videos = (v as List).map((e) => RadarVideo.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        _regras = (p as List).map((e) => PlaybookRegra.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        _pesquisas = (q as List).map((e) => RadarPesquisa.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar de vídeos'),
        actions: [IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar')],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error))))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Vídeos novos do YouTube (ganhar dinheiro com IA, automação, ferramentas, redes, filme de animação…), recolhidos todos os dias pelo PC com transcrição e resumidos por um modelo barato. Nota = utilidade real para o Danilo (0-10). Todos os dias às 20:52 a Claude.ai revê os vídeos e grava o veredito (já temos / novo / rejeitado) e a ação.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final d in const [1, 7, 30])
                          ChoiceChip(label: Text(d == 1 ? 'hoje' : '$d dias'), selected: _dias == d, onSelected: (_) {
                            setState(() => _dias = d);
                            _carregar();
                          }),
                        const SizedBox(width: 12),
                        for (final t in const [null, 'ganhar_dinheiro_ia', 'automacao', 'ferramentas_ia', 'animacao_ia', 'marketing_apps', 'crescer_redes', 'conteudo_em_dia', 'ganhar_dinheiro', 'historico', 'recomendados', 'outro'])
                          ChoiceChip(label: Text(rotuloTema(t)), selected: _tema == t, onSelected: (_) {
                            setState(() => _tema = t);
                            _carregar();
                          }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${_videos.length} vídeos · ${_videos.where((v) => v.temTranscricao).length} com transcrição',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (_videos.isEmpty)
                      const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nenhum vídeo com estes filtros.'))),
                    for (final v in _videos) _cartaoVideo(v),
                    const SizedBox(height: 20),
                    Text('Playbook atual (${_regras.length} regras)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Só entra uma regra vista em 3 ou mais vídeos diferentes. Atualiza-se ao domingo. Os robôs de reels do Bora e das redes do Em Dia leem estas regras ao gerar peças; o fiscal de vídeo pontua-as.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    if (_regras.isEmpty) const Text('Ainda sem playbook (aparece depois da primeira destilação).'),
                    for (final r in _regras) _cartaoRegra(r),
                    const SizedBox(height: 20),
                    Text('Temas que o radar pesquisa (${_pesquisas.where((p) => p.ativo).length} ativos de ${_pesquisas.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('A Claude.ai acrescenta temas a partir das conversas com o Danilo e dos vídeos bons; desliga os que não rendem. Peso 3 = quase todos os dias, 1 = de 3 em 3 dias. Desligar aqui pára a pesquisa desse tema.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    for (final q in _pesquisas) _linhaPesquisa(q),
                  ],
                ),
    );
  }

  Widget _cartaoVideo(RadarVideo v) {
    final cor = (v.nota ?? 0) >= 8 ? AppColors.success : (v.nota ?? 0) >= 5 ? AppColors.warning : AppColors.textSubtle;
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: cor, child: Text('${v.nota ?? '–'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        title: Text(v.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${v.canal ?? '?'} · ${rotuloTema(v.tema)} · ${v.visualizacoes ?? 0} visualizações · ${v.publicadoEm ?? ''}'
            '${v.temTranscricao ? '' : ' · sem transcrição'}', style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.resumo != null) SelectableText(v.resumo!, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          for (final i in v.ideias) Text('• $i', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(v.link), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.play_circle_outline),
            label: Text(v.link, style: const TextStyle(fontSize: 12)),
          ),
          if (v.veredito != null) ...[
            const SizedBox(height: 6),
            Text('Veredito da Claude.ai: ${rotuloVeredito(v.veredito)}${v.para != null ? ' · para: ${v.para}' : ''}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: v.veredito == 'novo' || v.veredito == 'feito' ? AppColors.success : AppColors.textSecondary)),
            if (v.acao != null) Text(v.acao!, style: const TextStyle(fontSize: 13)),
          ] else
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Ainda por rever (a Claude.ai revê todos os dias às 20:52).', style: TextStyle(fontSize: 12, color: AppColors.textSubtle))),
          Text('motor: ${v.motor ?? '—'} · pesquisa: ${v.pesquisa ?? '—'}', style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
        ],
      ),
    );
  }

  Widget _linhaPesquisa(RadarPesquisa q) {
    return Card(
      child: SwitchListTile(
        value: q.ativo,
        onChanged: (v) async {
          try {
            await _c.rpc('admin_radar_pesquisa_ativar', params: {'p_id': q.id, 'p_ativo': v});
            _carregar();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não deu para mudar: $e')));
          }
        },
        title: Text(q.termo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${rotuloTema(q.tema)} · peso ${q.peso} · ${q.vezes} corridas · ${q.origem}${q.motivo != null ? ' · ${q.motivo}' : ''}',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _cartaoRegra(PlaybookRegra r) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.rule, color: AppColors.primary),
        title: Text(r.regra, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${r.categoria ?? 'outro'} · ${r.nVideos} vídeos · ${r.provas.map((p) => p['titulo'] ?? p['youtube_id']).take(3).join(' · ')}',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

String rotuloTema(String? t) => switch (t) {
      null => 'todos',
      'crescer_redes' => 'crescer nas redes',
      'ganhar_dinheiro' => 'ganhar dinheiro',
      'marketing_apps' => 'marketing de apps',
      'ganhar_dinheiro_ia' => 'ganhar dinheiro com IA',
      'automacao' => 'automação',
      'ferramentas_ia' => 'ferramentas de IA',
      'animacao_ia' => 'filme de animação',
      'conteudo_em_dia' => 'conteúdo Em Dia',
      'historico' => 'histórico YouTube',
      'recomendados' => 'sugestões YouTube',
      _ => t,
    };

String rotuloVeredito(String? v) => switch (v) {
      'ja_temos' => 'já temos',
      'novo' => 'novo — vale a pena',
      'feito' => 'feito',
      'rejeitado' => 'rejeitado',
      _ => v ?? '—',
    };

class RadarVideo {
  final String youtubeId, titulo, link;
  final String? canal, tema, resumo, motor, pesquisa, publicadoEm, veredito, para, acao;
  final int? visualizacoes, nota;
  final bool temTranscricao;
  final List<String> ideias;
  const RadarVideo({required this.youtubeId, required this.titulo, required this.link, this.canal, this.tema, this.resumo, this.motor,
      this.pesquisa, this.publicadoEm, this.visualizacoes, this.nota, this.temTranscricao = false, this.ideias = const [],
      this.veredito, this.para, this.acao});
  factory RadarVideo.fromMap(Map<String, dynamic> m) => RadarVideo(
        youtubeId: (m['youtube_id'] ?? '').toString(),
        titulo: (m['titulo'] ?? '').toString(),
        link: (m['link'] ?? '').toString(),
        canal: m['canal']?.toString(),
        tema: m['tema']?.toString(),
        resumo: m['transcricao_resumida']?.toString(),
        motor: m['motor_resumo']?.toString(),
        pesquisa: m['pesquisa']?.toString(),
        publicadoEm: m['publicado_em']?.toString(),
        visualizacoes: (m['visualizacoes'] as num?)?.toInt(),
        nota: (m['nota_utilidade'] as num?)?.toInt(),
        temTranscricao: m['tem_transcricao'] == true,
        ideias: ((m['ideias'] as List?) ?? const []).map((e) => e.toString()).toList(),
        veredito: m['veredito']?.toString(),
        para: m['para']?.toString(),
        acao: m['acao']?.toString(),
      );
}

class RadarPesquisa {
  final int id;
  final String termo, tema, origem;
  final String? motivo;
  final bool ativo;
  final int peso, vezes;
  const RadarPesquisa({required this.id, required this.termo, required this.tema, required this.origem, this.motivo, this.ativo = true, this.peso = 1, this.vezes = 0});
  factory RadarPesquisa.fromMap(Map<String, dynamic> m) => RadarPesquisa(
        id: (m['id'] as num).toInt(),
        termo: (m['termo'] ?? '').toString(),
        tema: (m['tema'] ?? 'outro').toString(),
        origem: (m['origem'] ?? '').toString(),
        motivo: m['motivo']?.toString(),
        ativo: m['ativo'] == true,
        peso: (m['peso'] as num?)?.toInt() ?? 1,
        vezes: (m['vezes'] as num?)?.toInt() ?? 0,
      );
}

class PlaybookRegra {
  final String regra;
  final String? categoria;
  final int nVideos;
  final List<Map<String, dynamic>> provas;
  const PlaybookRegra({required this.regra, this.categoria, this.nVideos = 0, this.provas = const []});
  factory PlaybookRegra.fromMap(Map<String, dynamic> m) => PlaybookRegra(
        regra: (m['regra'] ?? '').toString(),
        categoria: m['categoria']?.toString(),
        nVideos: (m['n_videos'] as num?)?.toInt() ?? 0,
        provas: ((m['provas'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
}
