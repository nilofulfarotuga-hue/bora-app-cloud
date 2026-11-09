// Painel /admin/assistente — separador "Amigo Bora", secção "Voz do servidor"
// (missão missao-pendencias-2026-11-09, bloco I). PT-BR, termos técnicos explicados.
//
// Quando o aparelho do cliente não tem voz de Portugal (ex.: Safari do iPhone), o
// Amigo pede a frase em áudio à Edge amigo-voz (Google Cloud Text-to-Speech, pt-PT).
// Aqui: o consumo do dia e do mês (caracteres e % do grátis da Google), o
// interruptor, o teto por dia, o limite por cliente, a voz e um botão para testar.
// Gravar usa admin_amigo_voz_definir (fica na auditoria). Nada aqui mexe em dinheiro.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/amigo_voz_servidor.dart';

typedef AdminAmigoVozCarregar = Future<Map<String, dynamic>?> Function(int dias);
typedef AdminAmigoVozDefinir = Future<void> Function(Map<String, Object> mudancas);
typedef AdminAmigoVozTestar = Future<AmigoAudioResposta> Function(String frase);

/// Vozes oferecidas no painel: as pt-PT da lista da Google a 09/11/2026 (o servidor recusa outras).
const Map<String, String> kAdminAmigoVozes = {
  'pt-PT-Standard-E': 'Standard E — feminina (padrão, grátis 4 milhões/mês)',
  'pt-PT-Standard-F': 'Standard F — masculina (grátis 4 milhões/mês)',
  'pt-PT-Wavenet-E': 'WaveNet E — feminina, mais natural (grátis 1 milhão/mês)',
  'pt-PT-Wavenet-F': 'WaveNet F — masculina, mais natural (grátis 1 milhão/mês)',
};

/// O que cada "usar o aparelho" quer dizer, para o admin.
String adminAmigoVozMotivo(String? m) => switch (m) {
      'desligado' => 'interruptor desligado',
      'sem_chave' => 'falta o segredo GOOGLE_TTS_API_KEY na Edge amigo-voz',
      'teto' => 'passou o teto do dia',
      'limite_utilizador' => 'passou o limite por cliente (o seu, como admin)',
      'erro_google' => 'a Google recusou (chave errada ou API não ativada)',
      'erro_base' => 'migração por aplicar ou banco fora do ar',
      'sem_sessao' => 'sem sessão',
      'texto_invalido' => 'frase vazia ou com mais de 800 caracteres',
      _ => 'sem ligação ao servidor (Edge amigo-voz não publicada?)',
    };

String _milhar(Object? v) {
  final n = (v is num ? v : num.tryParse('${v ?? 0}') ?? 0).round();
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

class AdminAmigoVozSecao extends StatefulWidget {
  const AdminAmigoVozSecao({
    super.key,
    this.dias = 30,
    this.carregar,
    this.definir,
    this.testar,
    this.tocador,
  });

  final int dias;

  /// Trocáveis nos testes (por defeito, o Supabase e o tocador da plataforma).
  final AdminAmigoVozCarregar? carregar;
  final AdminAmigoVozDefinir? definir;
  final AdminAmigoVozTestar? testar;
  final AmigoTocador? tocador;

  @override
  State<AdminAmigoVozSecao> createState() => _AdminAmigoVozSecaoState();
}

class _AdminAmigoVozSecaoState extends State<AdminAmigoVozSecao> {
  Map<String, dynamic>? _v;
  bool _carregando = true;
  bool _semServidor = false;
  final _teto = TextEditingController();
  final _tetoCliente = TextEditingController();
  final _frase = TextEditingController(text: 'Olá! Eu sou o Amigo da Bora. Em que te posso ajudar?');
  bool _aTestar = false;
  String? _resultadoTeste;
  AmigoTocador? _tocadorCriado;
  AmigoTocador get _tocador => widget.tocador ?? (_tocadorCriado ??= criarAmigoTocador());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminAmigoVozSecao old) {
    super.didUpdateWidget(old);
    if (old.dias != widget.dias) _load();
  }

  @override
  void dispose() {
    _tocadorCriado?.libertar();
    _teto.dispose();
    _tetoCliente.dispose();
    _frase.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _carregarSupabase(int dias) async {
    final r = await Supabase.instance.client
        .rpc('admin_amigo_voz_overview', params: {'p_dias': dias});
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<void> _definirSupabase(Map<String, Object> m) async {
    await Supabase.instance.client.rpc('admin_amigo_voz_definir', params: m);
  }

  Future<void> _load() async {
    setState(() => _carregando = true);
    try {
      final v = await (widget.carregar ?? _carregarSupabase)(widget.dias);
      if (!mounted) return;
      final d = Map<String, dynamic>.from((v?['definicoes'] as Map?) ?? const {});
      setState(() {
        _v = v;
        _semServidor = v == null;
        _carregando = false;
        _teto.text = '${d['amigo_voz_teto_dia'] ?? 20000}';
        _tetoCliente.text = '${d['amigo_voz_teto_utilizador_dia'] ?? 3000}';
      });
    } catch (e) {
      debugPrint('[AdminAmigoVoz] $e');
      if (!mounted) return;
      setState(() {
        _semServidor = true;
        _carregando = false;
      });
    }
  }

  Future<void> _definir(Map<String, Object> m, String oQue) async {
    try {
      await (widget.definir ?? _definirSupabase)(m);
      _aviso('Salvo: $oQue (fica na auditoria)');
      await _load();
    } catch (e) {
      _aviso('Não salvei $oQue: $e');
    }
  }

  Future<void> _salvarNumero(TextEditingController c, String param, int max, String oQue) async {
    final n = int.tryParse(c.text.trim());
    if (n == null || n < 0 || n > max) {
      _aviso('$oQue: escreva um número entre 0 e ${_milhar(max)}.');
      return;
    }
    await _definir({param: n}, oQue);
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _testar() async {
    final t = _frase.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _aTestar = true;
      _resultadoTeste = null;
    });
    final testar = widget.testar ?? (f) => const AmigoVozServidorSupabase().pedir(f);
    final r = await testar(t);
    if (!mounted) return;
    final audio = r.audio;
    if (audio == null) {
      setState(() {
        _aTestar = false;
        _resultadoTeste = 'O servidor respondeu "usar a voz do aparelho": ${adminAmigoVozMotivo(r.motivo)}.';
      });
      return;
    }
    setState(() => _resultadoTeste =
        'Áudio recebido (${audio.origem == 'cache' ? 'da cache, sem gastar' : 'gerado na Google'}, '
        '${(audio.bytes.length / 1024).toStringAsFixed(1)} KB). A tocar…');
    await _tocador.tocar(
      audio,
      aoComecar: (_) {},
      aoAcabar: () {},
      aoErro: (m) {
        if (!mounted) return;
        setState(() => _resultadoTeste =
            'O áudio chegou mas o navegador não tocou ($m). Toque na página e tente outra vez.');
      },
    );
    // o botão só fica preso enquanto se espera pelo servidor
    if (mounted) setState(() => _aTestar = false);
  }

  Map<String, dynamic> _mapa(String k) => Map<String, dynamic>.from((_v?[k] as Map?) ?? const {});

  @override
  Widget build(BuildContext context) {
    final d = _mapa('definicoes');
    final hoje = _mapa('hoje');
    final mes = _mapa('mes');
    final ativo = d['amigo_voz_servidor_ativo'] == true;
    final vozAtual = '${d['amigo_voz_nome'] ?? 'pt-PT-Standard-E'}';
    final vozes = {
      ...kAdminAmigoVozes,
      if (!kAdminAmigoVozes.containsKey(vozAtual)) vozAtual: vozAtual,
    };
    final podeGravar = !_semServidor && !_carregando;

    return Column(
      key: const Key('admin-amigo-voz'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Voz do servidor (Google, português de Portugal)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'Só entra quando o aparelho do cliente não tem voz de Portugal (ex.: Safari do iPhone): o Amigo pede '
          'a frase em áudio ao servidor (Edge Function amigo-voz, Google Cloud Text-to-Speech). Frases repetidas '
          'saem da cache e não gastam. Grátis por mês na Google: 4 milhões de caracteres nas vozes Standard, '
          '1 milhão nas WaveNet/Neural2. Desligada, sem chave, acima do teto ou com erro da Google: o Amigo '
          'volta à legenda, sem erro para o cliente.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (_semServidor && !_carregando)
          Container(
            key: const Key('admin-amigo-voz-sem-migracao'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'A voz do servidor ainda não existe no banco (migração 20261109223000_amigo_voz por aplicar). '
              'Enquanto isso o Amigo usa a voz do aparelho ou a legenda, como antes.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        SwitchListTile(
          key: const Key('admin-amigo-voz-ativo'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Voz do servidor ligada (amigo_voz_servidor_ativo)'),
          subtitle: const Text(
              'Ligar só depois de pôr o segredo GOOGLE_TTS_API_KEY na Edge amigo-voz. Desligada = legenda nesses aparelhos.'),
          value: ativo,
          onChanged: podeGravar ? (x) => _definir({'p_ativo': x}, 'voz do servidor ${x ? 'ligada' : 'desligada'}') : null,
        ),
        const SizedBox(height: 4),
        if (_carregando)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Numero(
                'Hoje — gerados na Google',
                '${_milhar(hoje['caracteres_gerados'])} car.',
                '${_v?['pct_teto_hoje'] ?? 0}% do teto de ${_milhar(d['amigo_voz_teto_dia'])} · '
                    '${_milhar(_v?['clientes_hoje'])} clientes',
              ),
              _Numero(
                'Hoje — da cache',
                '${_milhar(hoje['caracteres_cache'])} car.',
                '${_milhar(hoje['pedidos_cache'])} frases sem gastar nada',
              ),
              _Numero(
                'Hoje — recusados',
                _milhar(hoje['pedidos_recusados']),
                'teto, limite por cliente ou sem chave · ${_milhar(hoje['erros'])} erros da Google',
              ),
              _Numero(
                'Mês — gerados na Google',
                '${_milhar(mes['caracteres_gerados'])} car.',
                '${_v?['pct_gratis_mes'] ?? 0}% do grátis de ${_milhar(_v?['gratis_mes'] ?? 4000000)} · '
                    '${_milhar(mes['caracteres_cache'])} da cache',
              ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('admin-amigo-voz-teto'),
                controller: _teto,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Teto por dia (caracteres)',
                  helperText: 'amigo_voz_teto_dia · máx. 133.000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            OutlinedButton(
              key: const Key('admin-amigo-voz-teto-salvar'),
              onPressed: podeGravar
                  ? () => _salvarNumero(_teto, 'p_teto_dia', 133000, 'teto por dia')
                  : null,
              child: const Text('Salvar teto'),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('admin-amigo-voz-teto-cliente'),
                controller: _tetoCliente,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Limite por cliente/dia',
                  helperText: 'amigo_voz_teto_utilizador_dia',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            OutlinedButton(
              key: const Key('admin-amigo-voz-teto-cliente-salvar'),
              onPressed: podeGravar
                  ? () => _salvarNumero(_tetoCliente, 'p_teto_utilizador_dia', 20000, 'limite por cliente')
                  : null,
              child: const Text('Salvar limite'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Voz da Google (amigo_voz_nome) — sempre pt-PT', style: TextStyle(fontSize: 12)),
        DropdownButton<String>(
          key: const Key('admin-amigo-voz-nome'),
          value: vozAtual,
          isExpanded: true,
          items: [
            for (final e in vozes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: podeGravar
              ? (v) {
                  if (v != null && v != vozAtual) _definir({'p_voz': v}, 'voz $v');
                }
              : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('admin-amigo-voz-frase'),
                controller: _frase,
                decoration: const InputDecoration(
                  labelText: 'Frase para testar a voz do servidor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('admin-amigo-voz-testar'),
              onPressed: _aTestar ? null : _testar,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('Testar'),
            ),
          ],
        ),
        if (_resultadoTeste != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_resultadoTeste!,
                key: const Key('admin-amigo-voz-resultado'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
      ],
    );
  }
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
