/// ROBÔ "FISCAL DE DOCUMENTOS" — o ecrã do Danilo (missão final-app-2026-10-29,
/// adendo 3, R7). Painel em PT-BR.
///
/// Mostra: o interruptor (liga/desliga), o modo (sombra = só olha / ativo = age),
/// a confiança mínima e o limite por dia; a lista "Prontos para aprovar"; o
/// histórico de tudo o que o robô viu, com "Desfazer" e "Lembrar este".
///
/// O robô NUNCA aprova nada: quem aprova é só o Danilo, nos ecrãs de cada papel.
/// Ligar o robô pede confirmação — passa a recusar documentos errados e a avisar
/// os candidatos (app, push e e-mail).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/robo_documentos.dart';
import '../../services/robo_documentos_service.dart';
import '../../widgets/admin_robo_documentos.dart';
import '_admin_rpc_errors.dart';

class AdminRoboDocumentosScreen extends StatefulWidget {
  const AdminRoboDocumentosScreen({super.key, this.api});

  /// Só para testes: troca o servidor por uma porta de mentira.
  final RoboAdminApi? api;

  @override
  State<AdminRoboDocumentosScreen> createState() => _AdminRoboDocumentosScreenState();
}

class _AdminRoboDocumentosScreenState extends State<AdminRoboDocumentosScreen> {
  late final RoboAdminApi _api = widget.api ?? RoboAdminSupabase();
  Map<String, dynamic> _cfg = const {};
  List<Map<String, dynamic>> _prontos = const [];
  List<VereditoRobo> _hist = const [];
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  static const _confiancas = <double>[0.7, 0.8, 0.85, 0.9, 0.95, 0.99];
  static const _limites = <int>[0, 50, 100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _msg(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final cfg = await _api.config();
      final prontos = await _api.prontos();
      final hist = await _api.historico(limite: 100);
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _prontos = prontos;
        _hist = hist;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  Future<bool> _confirmar(String titulo, String texto, {String ok = 'Confirmar', bool perigo = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: perigo ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _definir(String chave, Object valor) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final novo = await _api.definir(chave, valor);
      if (!mounted) return;
      setState(() => _cfg = novo);
    } catch (e) {
      _msg(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _ligar(bool ligar) async {
    if (ligar &&
        !await _confirmar(
          'Ligar o robô?',
          'Com o robô ligado e em modo "ativo", ele recusa os documentos que tiver a certeza que '
              'estão errados e avisa o candidato (aviso na app, notificação e e-mail), e lembra quem '
              'tem documentos em falta (dias 1, 3 e 7). Quem já estava parado não recebe nada. '
              'O robô NUNCA aprova: isso é só contigo.',
          ok: 'Ligar',
          perigo: true,
        )) {
      return;
    }
    await _definir('robo_documentos_ativo', ligar);
  }

  Future<void> _mudarModo(String modo) async {
    if (modo == 'ativo' &&
        !await _confirmar(
          'Passar a modo ativo?',
          'No modo ativo (e com o interruptor ligado) o robô passa a falar com os candidatos. '
              'No modo sombra ele só olha e regista.',
          ok: 'Modo ativo',
          perigo: true,
        )) {
      return;
    }
    await _definir('robo_documentos_modo', modo);
  }

  Future<void> _analisar() async {
    if (_ocupado) return;
    if (!await _confirmar(
      'Analisar os pendentes agora?',
      'O robô olha para os documentos de todos os candidatos pendentes e regista o que vê. '
          'Não manda mensagens nem muda nenhum estado. Custa menos de 1 cêntimo por documento.',
      ok: 'Analisar',
    )) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      final r = await _api.analisarPendentes();
      _msg('Mandei analisar ${r['candidatos'] ?? '?'} candidatos. Atualiza daqui a um minuto.');
    } catch (e) {
      _msg(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _lembrar(String userId, String nome) async {
    if (!await _confirmar(
      'Lembrar $nome?',
      'Manda a esta pessoa um aviso na app, uma notificação e um e-mail com a lista exata do que falta.',
      ok: 'Lembrar',
    )) {
      return;
    }
    try {
      final r = await _api.lembrar(userId);
      if (r['ok'] == true) {
        _msg('Lembrete enviado: falta ${(r['faltas'] as List?)?.join(', ') ?? ''}.');
      } else if (r['motivo'] == 'nada_a_pedir') {
        _msg('Esta pessoa não tem nada em falta.');
      } else {
        _msg('Não foi enviado (${r['motivo'] ?? 'erro'}).', erro: true);
      }
    } catch (e) {
      _msg(humanizeAdminRpcError(e), erro: true);
    }
  }

  String _data(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Robô de documentos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar outra vez')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _cartaoEstado(),
                      const SizedBox(height: 8),
                      _cartaoControlos(),
                      const SizedBox(height: 8),
                      _seccaoProntos(),
                      const SizedBox(height: 8),
                      _seccaoHistorico(),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoEstado() {
    final agir = _cfg['a_agir'] == true;
    final cor = agir ? AppColors.error : AppColors.success;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fiscal de documentos',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Lê cada documento que o candidato envia (estafeta, limpeza, lavagem, serviços), diz se é o '
              'certo e, quando está errado, avisa a pessoa do que falta. NUNCA aprova: quem aprova és só tu.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              key: const Key('robo-estado'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cor.withValues(alpha: 0.4)),
              ),
              child: Text(
                agir
                    ? 'O robô ESTÁ A AGIR: recusa o que tem certeza que está errado e avisa o candidato.'
                    : 'O robô só OLHA (modo sombra ou desligado): regista o que vê, mas não fala com ninguém '
                        'nem muda nada.',
                style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Análises nas últimas 24 h: ${_cfg['analises_24h'] ?? 0} (limite ${_cfg['limite_dia'] ?? '—'} por dia) · '
              'total registado: ${_cfg['total'] ?? 0}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoControlos() {
    final ligado = _cfg['ativo'] == true;
    final modo = (_cfg['modo'] ?? 'sombra').toString();
    final conf = (_cfg['confianca_min'] as num?)?.toDouble() ?? 0.85;
    final limite = (_cfg['limite_dia'] as num?)?.toInt() ?? 200;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('robo-interruptor'),
              title: const Text('Robô ligado (age)'),
              subtitle: const Text(
                  'Desligado: só olha e regista. Ligado e em modo ativo: recusa, avisa e lembra.'),
              value: ligado,
              onChanged: _ocupado ? null : _ligar,
            ),
            ListTile(
              title: const Text('Modo'),
              subtitle: Text(modo == 'ativo'
                  ? 'Ativo: age (se o interruptor estiver ligado).'
                  : 'Sombra: só olha e regista o veredito.'),
              trailing: SegmentedButton<String>(
                key: const Key('robo-modo'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'sombra', label: Text('Sombra')),
                  ButtonSegment(value: 'ativo', label: Text('Ativo')),
                ],
                selected: {modo},
                onSelectionChanged: _ocupado ? null : (s) => _mudarModo(s.first),
              ),
            ),
            ListTile(
              title: const Text('Confiança mínima'),
              subtitle: const Text('Abaixo disto o robô só tem dúvida e deixa para ti.'),
              trailing: DropdownButton<double>(
                key: const Key('robo-confianca'),
                value: _confiancas.contains(conf) ? conf : null,
                hint: Text('${(conf * 100).round()}%'),
                items: [
                  for (final c in _confiancas)
                    DropdownMenuItem(value: c, child: Text('${(c * 100).round()}%')),
                ],
                onChanged: _ocupado ? null : (v) => v == null ? null : _definir('robo_documentos_confianca_min', v),
              ),
            ),
            ListTile(
              title: const Text('Limite de análises por dia'),
              subtitle: const Text('0 pausa tudo (incluindo a IA). Cada análise custa menos de 1 cêntimo.'),
              trailing: DropdownButton<int>(
                key: const Key('robo-limite'),
                value: _limites.contains(limite) ? limite : null,
                hint: Text('$limite'),
                items: [for (final l in _limites) DropdownMenuItem(value: l, child: Text('$l'))],
                onChanged: _ocupado ? null : (v) => v == null ? null : _definir('robo_documentos_limite_dia', v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('robo-analisar'),
                  onPressed: _ocupado ? null : _analisar,
                  icon: const Icon(Icons.search),
                  label: const Text('Analisar pendentes agora (só olha)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccaoProntos() {
    return Card(
      key: const Key('robo-prontos'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prontos para aprovar (${_prontos.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            if (_prontos.isEmpty)
              const Text('Ninguém tem tudo certo e por aprovar neste momento.',
                  style: TextStyle(color: AppColors.textSecondary))
            else ...[
              const Text('Têm todos os documentos enviados e o robô achou tudo certo. Falta só aprovares '
                  '(no ecrã de cada papel).',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              for (final p in _prontos)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_outlined, color: AppColors.success),
                  title: Text('${p['nome'] ?? '—'}'),
                  subtitle: Text(((p['papeis'] as List?) ?? const []).join(' + ')),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seccaoHistorico() {
    return Card(
      key: const Key('robo-historico'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Histórico (${_hist.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            if (_hist.isEmpty)
              const Text('O robô ainda não viu nenhum documento.',
                  style: TextStyle(color: AppColors.textSecondary)),
            for (final v in _hist)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  v.ok ? Icons.check_circle_outline : (v.errado ? Icons.error_outline : Icons.help_outline),
                  color: v.ok ? AppColors.success : (v.errado ? AppColors.error : Colors.orange.shade800),
                ),
                title: Text('${v.nome ?? '—'} · ${rotuloDoCampo(v.campo)}'),
                subtitle: Text(
                  '${textoDoVeredito(v)}\n'
                  '${_data(v.criadoEm)} · ${v.modo == 'sombra' ? 'só olhou' : v.modo}'
                  '${v.acao != 'nenhuma' ? ' · robô: ${v.acao}' : ''}'
                  '${v.desfeito ? ' · desfeito' : ''}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  key: Key('robo-menu-${v.id}'),
                  onSelected: (a) async {
                    if (a == 'lembrar' && v.userId != null) {
                      await _lembrar(v.userId!, v.nome ?? 'esta pessoa');
                    } else if (a == 'desfazer') {
                      final fez = await desfazerDecisaoDoRobo(context, v, desfazer: _api.desfazer);
                      if (fez) await _carregar();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'lembrar', child: Text('Lembrar este')),
                    if (v.agiu) const PopupMenuItem(value: 'desfazer', child: Text('Desfazer decisão do robô')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
