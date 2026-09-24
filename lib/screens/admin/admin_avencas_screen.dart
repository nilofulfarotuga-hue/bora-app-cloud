// Painel admin (PT-BR) — Avenças «Presença Digital Bora»
// (missão agente-avenca-preparacao-2026-09-24).
//
// A linha de dinheiro nova: vender aos negócios da Guarda (raio 20 km) o trabalho que os
// robôs já fazem para a Bora — publicações, mini-site, ficha Google e atendimento. Aqui vê-se
// a lista dos negócios encontrados (só dados públicos do próprio negócio), a amostra que se
// fez para cada um e o RASCUNHO da proposta.
//
// Só leitura. Nada sai daqui: as propostas ficam em 'rascunho' até o Danilo decidir, e é ele
// que as envia. O ecrã não tem botão de enviar de propósito.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';

class AdminAvencasScreen extends StatefulWidget {
  const AdminAvencasScreen({super.key});

  @override
  State<AdminAvencasScreen> createState() => _AdminAvencasScreenState();
}

class _AdminAvencasScreenState extends State<AdminAvencasScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _resumo = const {};
  List<Map<String, dynamic>> _lista = const [];
  String? _estado;

  static const _estados = <String?, String>{
    null: 'todos',
    'novo': 'novos',
    'amostra_pronta': 'com amostra',
    'proposta_rascunho': 'proposta escrita',
    'enviado': 'enviados',
    'cliente': 'clientes',
  };

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
      final r = await _c.rpc('admin_prospects_resumo');
      final l = await _c.rpc('admin_prospects_presenca', params: {'p_estado': _estado, 'p_limite': 400});
      if (!mounted) return;
      setState(() {
        _resumo = r == null ? const {} : Map<String, dynamic>.from(r as Map);
        _lista = (l as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> _abrirDetalhe(Map<String, dynamic> p) async {
    final d = await _c.rpc('admin_prospect_detalhe', params: {'p_id': p['id']});
    if (!mounted || d == null) return;
    final m = Map<String, dynamic>.from(d as Map);
    final amostras = (m['amostras'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final propostas = (m['propostas'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, controle) => ListView(
          controller: controle,
          padding: const EdgeInsets.all(20),
          children: [
            Text('${p['nome']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${p['categoria'] ?? '—'} · ${p['morada'] ?? ''} · ${p['km_da_guarda'] ?? '?'} km da Guarda',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _linha('Telefone', p['telefone']),
            _linha('Site', p['website']),
            _linha('Ficha Google', p['ficha_google']),
            _linha('Pontuação', '${p['pontuacao'] ?? '—'} em 100'),
            if ((p['notas'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('O que falta', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('${p['notas']}', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 18),
            Text('Amostras (${amostras.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            for (final a in amostras)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link, color: AppColors.primary),
                title: Text('${a['link_unico']}', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${(a['publicacoes'] as List? ?? const []).length} publicações prontas'),
                onTap: () => launchUrl(Uri.parse('${a['link_unico']}'), mode: LaunchMode.externalApplication),
              ),
            const SizedBox(height: 12),
            Text('Propostas (${propostas.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Text('Ficam em rascunho. Quem envia é você — o painel não envia nada.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            for (final r in propostas)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['assunto'] ?? ''} · ${r['canal']} · ${r['preco_mes_eur']} €/mês · ${r['estado']}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      SelectableText('${r['texto']}', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _linha(String rotulo, Object? valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$rotulo: ${valor ?? '—'}', style: const TextStyle(fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avenças'),
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
                      'Presença Digital Bora: negócios da Guarda e à volta (20 km) com presença digital fraca. '
                      'Só dados públicos do próprio negócio. Nada foi enviado a ninguém: as propostas ficam em rascunho até você mandar.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 6, children: [
                      _ficha('negócios', _resumo['total']),
                      _ficha('sem site', _resumo['sem_site']),
                      _ficha('amostras', _resumo['amostras']),
                      _ficha('propostas', _resumo['propostas_rascunho']),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final e in _estados.entries)
                          ChoiceChip(
                            label: Text(e.value),
                            selected: _estado == e.key,
                            onSelected: (_) {
                              setState(() => _estado = e.key);
                              _carregar();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('${_lista.length} na lista', style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final p in _lista) _cartao(p),
                  ],
                ),
    );
  }

  Widget _ficha(String rotulo, Object? valor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text('${valor ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(rotulo, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      );

  Widget _cartao(Map<String, dynamic> p) {
    final pont = (p['pontuacao'] as num?)?.toInt() ?? 0;
    final cor = pont >= 70 ? AppColors.success : pont >= 50 ? AppColors.warning : AppColors.textSubtle;
    final amostras = (p['amostras'] as num?)?.toInt() ?? 0;
    final propostas = (p['propostas'] as num?)?.toInt() ?? 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: cor, child: Text('$pont', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
        title: Text('${p['nome']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${p['categoria'] ?? '—'} · ficha ${p['ficha_google'] ?? '?'}'
          '${p['telefone'] != null ? ' · ${p['telefone']}' : ' · sem telefone'}'
          '${amostras > 0 ? ' · $amostras amostra(s)' : ''}${propostas > 0 ? ' · $propostas proposta(s)' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text('${p['estado']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        onTap: () => _abrirDetalhe(p),
      ),
    );
  }
}
