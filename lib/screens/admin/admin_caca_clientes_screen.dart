// Painel admin (PT-BR) — Caça-clientes (missão caca-clientes-2026-10-03).
//
// O circuito que faltava às Avenças: achar o contato, preparar a peça, ENVIAR em nome da
// Bora e fazer o seguimento. Aqui o Danilo vê cada negócio, a peça (link único), o email
// escrito, e manda: enviar agora, pausar, marcar recusa ou cliente, editar o texto, apagar,
// exportar. O interruptor geral liga e desliga o carteiro (platform_settings.caca_clientes_enabled).
//
// Tudo passa por RPC com is_admin(). O envio em si é do carteiro na VPS: máximo 5 emails
// novos por dia útil, das 09h30 às 11h30, só para email verificado.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';

class AdminCacaClientesScreen extends StatefulWidget {
  const AdminCacaClientesScreen({super.key});

  @override
  State<AdminCacaClientesScreen> createState() => _AdminCacaClientesScreenState();
}

class _AdminCacaClientesScreenState extends State<AdminCacaClientesScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _resumo = const {};
  List<Map<String, dynamic>> _lista = const [];
  String? _estado;
  String? _tipo;
  String? _concelho;
  int _pontosMin = 0;

  static const _estados = <String?, String>{
    null: 'todos',
    'novo': 'novos',
    'proposta_rascunho': 'rascunho',
    'pronta': 'prontos para enviar',
    'enviada': 'enviados',
    'respondeu': 'responderam',
    'sem_resposta': 'sem resposta',
    'recusou': 'recusaram',
    'email_invalido': 'email inválido',
    'pausado': 'pausados',
    'cliente': 'clientes',
  };

  static const _tipos = <String?, String>{
    null: 'todos os tipos',
    'site': 'site',
    'parceiro-bora': 'parceiro Bora',
    'funcionario-digital': 'funcionário digital',
    'os-dois': 'os dois',
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
      final r = await _c.rpc('admin_caca_resumo');
      final l = await _c.rpc('admin_caca_lista', params: {
        'p_estado': _estado,
        'p_tipo': _tipo,
        'p_concelho': _concelho,
        'p_pontos_min': _pontosMin,
        'p_limite': 500,
      });
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

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? AppColors.error : null));
  }

  String _erroSimples(Object e) {
    final t = e.toString();
    if (t.contains('sem_email_verificado')) return 'Esse negócio ainda não tem email verificado.';
    if (t.contains('sem_proposta')) return 'Ainda não há email escrito para esse negócio.';
    if (t.contains('so_admin')) return 'Só o administrador pode fazer isso.';
    return 'Não deu certo: $t';
  }

  Future<void> _interruptor(bool ligado) async {
    try {
      await _c.rpc('admin_caca_interruptor', params: {'p_ligado': ligado});
      _aviso(ligado ? 'Carteiro ligado: envia até 5 emails novos por dia útil.' : 'Carteiro desligado: nada sai.');
      await _carregar();
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
    }
  }

  Future<bool> _acao(Map<String, dynamic> p, String acao, {String? assunto, String? texto}) async {
    try {
      await _c.rpc('admin_caca_acao', params: {'p_prospect': p['id'], 'p_acao': acao, 'p_assunto': assunto, 'p_texto': texto});
      const feito = {
        'enviar_agora': 'Vai sair na próxima passagem do carteiro (de hora em hora).',
        'pausar': 'Pausado.',
        'retomar': 'Voltou para a fila.',
        'recusou': 'Marcado como recusou. Nunca mais é contatado.',
        'cliente': 'Marcado como cliente.',
        'editar': 'Texto guardado.',
        'apagar': 'Apagado.',
      };
      _aviso(feito[acao] ?? 'Feito.');
      await _carregar();
      return true;
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
      return false;
    }
  }

  Future<void> _exportarCsv() async {
    String c(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final linhas = <String>[
      'id;nome;categoria;concelho;tipo;pontuacao;estado;email;email_verificado;canal;telefone;site;link;ultimo_contato;proximo_seguimento;resposta',
      for (final p in _lista)
        [
          p['id'], p['nome'], p['categoria'], p['concelho'], p['cliente_tipo'], p['pontuacao'], p['estado'], p['email'],
          p['email_verificado'], p['canal_preferido'], p['telefone'], p['website'], p['link'], p['ultimo_contacto_em'],
          p['proximo_seguimento_em'], p['resposta'],
        ].map(c).join(';'),
    ];
    await AdminExportService.instance.exportCsvText(
      filename: 'caca_clientes_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv: '\uFEFF${linhas.join('\n')}',
    );
    _aviso('CSV com ${_lista.length} negócios descarregado.');
  }

  Future<void> _editar(Map<String, dynamic> p, Map<String, dynamic> prop) async {
    final assunto = TextEditingController(text: '${prop['assunto'] ?? ''}');
    final texto = TextEditingController(text: '${prop['texto'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar o email para ${p['nome']}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: assunto, decoration: const InputDecoration(labelText: 'Assunto (até 7 palavras)')),
            const SizedBox(height: 10),
            TextField(controller: texto, maxLines: 12, decoration: const InputDecoration(labelText: 'Texto (sem preço)', alignLabelWithHint: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) await _acao(p, 'editar', assunto: assunto.text.trim(), texto: texto.text.trim());
  }

  Future<void> _confirmarApagar(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar ${p['nome']}?'),
        content: const Text('Some da lista com a peça e os emails escritos. Não dá para desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true && await _acao(p, 'apagar') && mounted) Navigator.pop(context);
  }

  Future<void> _abrirDetalhe(Map<String, dynamic> p) async {
    final prop = p['proposta'] == null ? null : Map<String, dynamic>.from(p['proposta'] as Map);
    final link = (p['link'] ?? '').toString();
    final verificado = p['email_verificado'] == true;
    final estado = '${p['estado']}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        builder: (_, controle) => ListView(
          controller: controle,
          padding: const EdgeInsets.all(20),
          children: [
            Text('${p['nome']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${p['categoria'] ?? '—'} · ${p['concelho'] ?? 'concelho por preencher'} · ${_tipos[p['cliente_tipo']] ?? 'tipo por definir'}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _linha('Estado', _estados[estado] ?? estado),
            _linha('Email', '${p['email'] ?? '—'}${verificado ? ' (verificado · ${p['email_fonte'] ?? ''})' : ' (não verificado)'}'),
            _linha('Canal', p['canal_preferido']),
            _linha('Telefone', p['telefone']),
            _linha('Site', p['website']),
            _linha('Instagram', p['instagram']),
            _linha('Facebook', p['facebook']),
            _linha('Livro de reclamações no site', p['livro_reclamacoes_ok'] == null ? 'não visto' : (p['livro_reclamacoes_ok'] == true ? 'tem' : 'FALTA')),
            _linha('Gancho', p['gancho']),
            _linha('Pontuação', '${p['pontuacao'] ?? '—'} em 100'),
            _linha('Último contato', p['ultimo_contacto_em']),
            _linha('Próximo seguimento', p['proximo_seguimento_em']),
            if ((p['resposta'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('O que responderam', style: TextStyle(fontWeight: FontWeight.w700)),
              SelectableText('${p['resposta']}', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 14),
            if (link.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ver a peça'),
              )
            else
              const Text('Ainda sem peça. Sem peça não há contato.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            const Text('Email escrito', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (prop == null)
              const Text('Ainda não há email escrito.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${prop['assunto'] ?? ''} · ${prop['canal']} · ${prop['estado']}'
                        '${(prop['seguimentos'] as num? ?? 0) > 0 ? ' · ${prop['seguimentos']} seguimento(s)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    SelectableText('${prop['texto'] ?? ''}', style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: prop == null || !verificado
                    ? null
                    : () async {
                        if (await _acao(p, 'enviar_agora') && ctx.mounted) Navigator.pop(ctx);
                      },
                icon: const Icon(Icons.send),
                label: const Text('Enviar agora'),
              ),
              if (prop != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _editar(p, prop);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar texto'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _acao(p, estado == 'pausado' ? 'retomar' : 'pausar') && ctx.mounted) Navigator.pop(ctx);
                },
                icon: Icon(estado == 'pausado' ? Icons.play_arrow : Icons.pause),
                label: Text(estado == 'pausado' ? 'Retomar' : 'Pausar'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _acao(p, 'recusou') && ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.block),
                label: const Text('Recusou'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _acao(p, 'cliente') && ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.verified),
                label: const Text('Marcar como cliente'),
              ),
              TextButton.icon(
                onPressed: () => _confirmarApagar(p),
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                label: const Text('Apagar', style: TextStyle(color: AppColors.error)),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _linha(String rotulo, Object? valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: SelectableText('$rotulo: ${(valor ?? '').toString().isEmpty ? '—' : valor}', style: const TextStyle(fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final ligado = _resumo['ligado'] == true;
    final concelhos = (_resumo['concelhos'] as List? ?? const []).map((e) => '$e').toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caça-clientes'),
        actions: [
          IconButton(onPressed: _lista.isEmpty ? null : _exportarCsv, icon: const Icon(Icons.download), tooltip: 'Exportar CSV'),
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error))))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: SwitchListTile(
                        value: ligado,
                        onChanged: _interruptor,
                        title: Text(ligado ? 'Carteiro ligado' : 'Carteiro desligado', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text(
                          'Ligado: envia até 5 emails novos por dia útil (09h30–11h30), em nome da Bora, e faz 2 seguimentos. '
                          'Desligado: nada sai, nem o que você mandar enviar agora.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 6, children: [
                      _ficha('encontrados', _resumo['encontrados']),
                      _ficha('com email', _resumo['com_email']),
                      _ficha('prontos', _resumo['prontas']),
                      _ficha('enviados', _resumo['enviados']),
                      _ficha('respostas', _resumo['respostas']),
                      _ficha('fechados', _resumo['fechados']),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final e in _estados.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: _estado == e.key,
                          onSelected: (_) {
                            setState(() => _estado = e.key);
                            _carregar();
                          },
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      DropdownButton<String?>(
                        value: _tipo,
                        items: [for (final e in _tipos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: (v) {
                          setState(() => _tipo = v);
                          _carregar();
                        },
                      ),
                      DropdownButton<String?>(
                        value: concelhos.contains(_concelho) ? _concelho : null,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('todos os concelhos')),
                          for (final x in concelhos) DropdownMenuItem<String?>(value: x, child: Text(x)),
                        ],
                        onChanged: (v) {
                          setState(() => _concelho = v);
                          _carregar();
                        },
                      ),
                      DropdownButton<int>(
                        value: _pontosMin,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('qualquer pontuação')),
                          DropdownMenuItem(value: 40, child: Text('40 pontos ou mais')),
                          DropdownMenuItem(value: 55, child: Text('55 pontos ou mais')),
                          DropdownMenuItem(value: 70, child: Text('70 pontos ou mais')),
                        ],
                        onChanged: (v) {
                          setState(() => _pontosMin = v ?? 0);
                          _carregar();
                        },
                      ),
                    ]),
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
    final verificado = p['email_verificado'] == true;
    final estado = '${p['estado']}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: cor, child: Text('$pont', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
        title: Text('${p['nome']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${p['categoria'] ?? '—'}'
          '${verificado ? ' · ${p['email']}' : ' · sem email verificado'}'
          '${(p['link'] ?? '').toString().isNotEmpty ? ' · com peça' : ' · sem peça'}'
          '${p['proposta'] != null ? ' · email escrito' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(_estados[estado] ?? estado, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        onTap: () => _abrirDetalhe(p),
      ),
    );
  }
}
