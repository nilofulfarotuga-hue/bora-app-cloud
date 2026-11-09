// Painel /admin/assistente — separador "Amigo Bora", secção "Rosto do Amigo"
// (missão m11-amigo-rosto, 09/11/2026). PT-BR, termos técnicos explicados.
//
// Pré-visualização AO VIVO do rosto com um botão por expressão, campo para
// escrever uma frase e ouvir o Amigo falar (teste de voz e de boca), escolha
// da variante (só o rosto / rosto com camisa), os interruptores do rosto e os
// números de uso (admin_amigo_rosto_overview). Gravar usa admin_update_setting
// (fica na auditoria, como o resto do painel). Nada aqui mexe em dinheiro.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/amigo_voz.dart';
import '../../widgets/amigo/amigo_rosto.dart';

typedef AdminAmigoCarregar = Future<Map<String, dynamic>?> Function(int dias);
typedef AdminAmigoGravar = Future<void> Function(String chave, Object valor);

class AdminAmigoRostoSecao extends StatefulWidget {
  const AdminAmigoRostoSecao({
    super.key,
    this.dias = 30,
    this.carregar,
    this.gravar,
    this.voz,
  });

  final int dias;

  /// Trocáveis nos testes (por defeito, o Supabase).
  final AdminAmigoCarregar? carregar;
  final AdminAmigoGravar? gravar;
  final AmigoVoz? voz;

  @override
  State<AdminAmigoRostoSecao> createState() => _AdminAmigoRostoSecaoState();
}

class _AdminAmigoRostoSecaoState extends State<AdminAmigoRostoSecao> {
  Map<String, dynamic>? _v;
  bool _semServidor = false;
  bool _carregando = true;
  AmigoEmocao _emocao = AmigoEmocao.alegre;
  AmigoVariante? _variantePrevia;
  double? _velocidade;
  late final AmigoVoz _voz;
  final _frase = TextEditingController(
      text: 'Olá! Eu sou o Amigo. Hoje apetece-te um hambúrguer?');
  bool _aFalar = false;

  @override
  void initState() {
    super.initState();
    _voz = widget.voz ?? AmigoVoz(somPorDefeito: true);
    _voz.preparar().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminAmigoRostoSecao old) {
    super.didUpdateWidget(old);
    if (old.dias != widget.dias) _load();
  }

  @override
  void dispose() {
    _voz.dispose();
    _frase.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _carregarSupabase(int dias) async {
    final r = await Supabase.instance.client
        .rpc('admin_amigo_rosto_overview', params: {'p_dias': dias});
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<void> _load() async {
    setState(() => _carregando = true);
    try {
      final v = await (widget.carregar ?? _carregarSupabase)(widget.dias);
      if (!mounted) return;
      setState(() {
        _v = v;
        _semServidor = v == null;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('[AdminAmigoRosto] $e');
      if (!mounted) return;
      setState(() {
        _semServidor = true;
        _carregando = false;
      });
    }
  }

  Future<void> _gravar(String chave, Object valor) async {
    try {
      if (widget.gravar != null) {
        await widget.gravar!(chave, valor);
      } else {
        await Supabase.instance.client
            .rpc('admin_update_setting', params: {'p_key': chave, 'p_value': valor});
      }
      _aviso('Salvo: $chave (fica na auditoria)');
      await _load();
    } catch (e) {
      _aviso('Não salvei $chave: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _ouvir() async {
    final t = _frase.text.trim();
    if (t.isEmpty) return;
    setState(() => _aFalar = true);
    await _voz.falar(t);
    if (mounted) setState(() => _aFalar = false);
  }

  Map<String, dynamic> get _interruptores =>
      Map<String, dynamic>.from((_v?['interruptores'] as Map?) ?? const {});

  @override
  Widget build(BuildContext context) {
    final it = _interruptores;
    final variante = _variantePrevia ?? amigoVarianteDe(it['amigo_rosto_variante']);
    final ativo = it['amigo_rosto_ativo'] != false;
    final vozPadrao = it['amigo_voz_ligada_por_defeito'] != false;
    final mosaico = it['amigo_mosaico_categorias'] != false;
    final vel = _velocidade ??
        (num.tryParse('${it['amigo_voz_velocidade'] ?? 1}')?.toDouble() ?? 1).clamp(0.5, 2.0);
    final podeGravar = !_semServidor && !_carregando;

    return Column(
      key: const Key('admin-amigo-rosto'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rosto do Amigo (o personagem que fala)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'O cliente vê o Amigo como um rosto vivo: pisca, olha, muda de expressão e fala em português de Portugal '
          'com a boca a acompanhar a voz. Teste aqui as expressões e a voz.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (_semServidor && !_carregando)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'As definições do rosto ainda não existem no servidor (migração 20261109060000_amigo_rosto por aplicar). '
              'A app usa os valores padrão (rosto ligado, com camisa, voz ligada, velocidade 1, mosaico ligado). '
              'A pré-visualização funciona na mesma.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryLight),
              ),
              child: Center(
                child: AmigoRosto(
                  key: const Key('admin-amigo-previa'),
                  tamanho: 180,
                  emocao: _aFalar && _emocao == AmigoEmocao.neutro ? AmigoEmocao.aFalar : _emocao,
                  variante: variante,
                  boca: _voz.bocaAgora,
                ),
              ),
            ),
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expressão (toque para ver)', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in AmigoEmocao.values)
                        ChoiceChip(
                          key: Key('admin-amigo-emocao-${amigoEmocaoNome(e)}'),
                          label: Text(amigoEmocaoRotulo(e)),
                          selected: _emocao == e,
                          onSelected: (_) => setState(() => _emocao = e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('admin-amigo-frase'),
                    controller: _frase,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Frase para testar a voz e a boca',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton.icon(
                        key: const Key('admin-amigo-ouvir'),
                        onPressed: _aFalar ? _voz.parar : _ouvir,
                        icon: Icon(_aFalar ? Icons.stop : Icons.record_voice_over_outlined),
                        label: Text(_aFalar ? 'Parar' : 'Ouvir o Amigo'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _voz.temVozPtPt
                              ? 'Voz: ${_voz.nomeVoz}'
                              : 'Sem voz pt-PT neste aparelho/navegador: o Amigo fala só por legenda.',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Desenho (amigo_rosto_variante)', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        SegmentedButton<AmigoVariante>(
          key: const Key('admin-amigo-variante'),
          segments: const [
            ButtonSegment(value: AmigoVariante.rosto, label: Text('Só o rosto')),
            ButtonSegment(value: AmigoVariante.rostoCamisa, label: Text('Rosto com camisa')),
          ],
          selected: {variante},
          onSelectionChanged: (s) {
            final v = s.first;
            setState(() => _variantePrevia = v);
            if (podeGravar) {
              _gravar('amigo_rosto_variante', v == AmigoVariante.rosto ? 'rosto' : 'rosto_camisa');
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rosto ligado (amigo_rosto_ativo)'),
          subtitle: const Text(
              'Desligado: volta o botão "Ajuda-me a escolher" e a conversa escrita de 08/11 (o assistente continua).'),
          value: ativo,
          onChanged: podeGravar ? (x) => _gravar('amigo_rosto_ativo', x) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Voz ligada ao abrir (amigo_voz_ligada_por_defeito)'),
          subtitle: const Text(
              'O Amigo fala em voz alta. O cliente pode desligar o som no ecrã e fica lembrado no aparelho.'),
          value: vozPadrao,
          onChanged: podeGravar ? (x) => _gravar('amigo_voz_ligada_por_defeito', x) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mosaico "Amigo" nas categorias (amigo_mosaico_categorias)'),
          subtitle: const Text('O rostinho animado no início da grelha de categorias da home.'),
          value: mosaico,
          onChanged: podeGravar ? (x) => _gravar('amigo_mosaico_categorias', x) : null,
        ),
        Text('Velocidade da voz (amigo_voz_velocidade): ${vel.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13)),
        Slider(
          key: const Key('admin-amigo-velocidade'),
          min: 0.5,
          max: 2,
          divisions: 15,
          value: vel.toDouble(),
          label: vel.toStringAsFixed(2),
          onChanged: (x) {
            setState(() => _velocidade = x);
            _voz.velocidade = x;
          },
          onChangeEnd: podeGravar ? (x) => _gravar('amigo_voz_velocidade', double.parse(x.toStringAsFixed(2))) : null,
        ),
        const SizedBox(height: 8),
        const Text('Uso do rosto', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 6),
        if (_carregando)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Numero('Aberturas do ecrã', '${_v?['aberturas'] ?? 0}',
                  '${_v?['clientes'] ?? 0} clientes diferentes'),
              _Numero('Voz vs escrita', '${_v?['pct_voz'] ?? 0}% voz',
                  '${_v?['mensagens_voz'] ?? 0} por voz · ${_v?['mensagens_escrita'] ?? 0} escritas'),
              _Numero('Tempo de conversa', '${_v?['tempo_medio_s'] ?? 0} s',
                  'média por abertura · total ${_v?['tempo_total_min'] ?? 0} min'),
              _Numero(
                'Por plataforma',
                ((_v?['por_plataforma'] as List?) ?? const [])
                    .whereType<Map>()
                    .map((p) => '${p['plataforma']}: ${p['n']}')
                    .join(' · ')
                    .ifEmpty('-'),
                'aberturas (android / ios / web)',
              ),
            ],
          ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String outro) => isEmpty ? outro : this;
}

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor, this.detalhe);
  final String titulo;
  final String valor;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(detalhe, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
