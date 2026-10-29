import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';

/// Uma linha de `admin_parceiros_termos()` (migração
/// `20261027205557_termos_do_parceiro_2026_10_28.sql`).
class TermoParceiroLinha {
  const TermoParceiroLinha({
    required this.restaurantId,
    required this.loja,
    this.userId,
    this.email,
    this.versaoAtual,
    this.versaoAceite,
    this.aceiteEm,
    this.via,
    this.nota,
  });

  final String restaurantId;
  final String loja;
  final String? userId;
  final String? email;
  final String? versaoAtual;
  final String? versaoAceite;
  final DateTime? aceiteEm;

  /// 'whatsapp' / 'email' (registado pelo admin) ou a plataforma da app
  /// ('android', 'iOS', 'web'...) quando o parceiro tocou em "Aceito".
  final String? via;
  final String? nota;

  /// Aceitou a versão em vigor.
  bool get aceiteAtual =>
      versaoAceite != null && versaoAceite == versaoAtual;

  static String? _t(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory TermoParceiroLinha.fromJson(Map<String, dynamic> j) =>
      TermoParceiroLinha(
        restaurantId: j['restaurant_id']?.toString() ?? '',
        loja: _t(j['loja']) ?? '—',
        userId: _t(j['user_id']),
        email: _t(j['email']),
        versaoAtual: _t(j['versao_atual']),
        versaoAceite: _t(j['versao_aceite']),
        aceiteEm: DateTime.tryParse('${j['aceite_em'] ?? ''}'),
        via: _t(j['via']),
        nota: _t(j['nota']),
      );
}

/// "WhatsApp", "email" ou "no app (android)". Função pura.
String rotuloViaTermos(String? via) => switch (via?.trim().toLowerCase()) {
      null || '' => '—',
      'whatsapp' => 'WhatsApp',
      'email' => 'email',
      final outra => 'no app ($outra)',
    };

/// O estado de uma linha em PT-BR, para a lista. Função pura.
String estadoTermoParceiro(TermoParceiroLinha l) {
  if (l.versaoAceite == null) return 'Pendente';
  final quando = l.aceiteEm == null ? '' : ' em ${_dataHora(l.aceiteEm!)}';
  if (!l.aceiteAtual) {
    return 'Pendente (aceitou a versão antiga ${l.versaoAceite}$quando)';
  }
  return 'Aceitou a versão ${l.versaoAceite}$quando · ${rotuloViaTermos(l.via)}';
}

String _dataHora(DateTime d) {
  final l = paredeLisboa(d);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.day)}/${dd(l.month)}/${l.year} ${dd(l.hour)}:${dd(l.minute)}';
}

/// Erros das duas funções do servidor, em PT-BR. Função pura.
String mensagemErroTermosParceiro(Object erro) {
  final t = erro is PostgrestException ? erro.message : erro.toString();
  if (t.contains('admin_required')) return 'Sem permissão de admin.';
  if (t.contains('via_invalida')) return 'Escolha WhatsApp ou email.';
  if (t.contains('loja_sem_conta')) {
    return 'Esta loja não tem conta de dono ligada — não há a quem registrar o aceite.';
  }
  if (t.contains('sem_versao_parceiro')) {
    return 'Não há versão dos termos do parceiro publicada.';
  }
  return 'Erro do servidor: $t';
}

typedef CarregarTermosParceiros = Future<List<TermoParceiroLinha>> Function();
typedef RegistarAceiteParceiro = Future<Map<String, dynamic>> Function(
    String restaurantId, String via, String nota);

/// Painel admin (PT-BR) → Parceiros → "Termos dos parceiros".
///
/// Missão boom-burger-2026-10-27, F4 (Regulamento UE 2019/1150). Lista as
/// lojas parceiras aprovadas com a versão dos termos que aceitaram e quando,
/// ou "Pendente". Quem aceitou fora da app (WhatsApp ou email) fica
/// registado aqui com "Registrar aceite" (via + nota).
class AdminParceirosTermosScreen extends StatefulWidget {
  const AdminParceirosTermosScreen({super.key, this.carregar, this.registar});

  /// Por defeito `rpc('admin_parceiros_termos')`.
  final CarregarTermosParceiros? carregar;

  /// Por defeito `rpc('admin_registar_aceitacao_termos_parceiro')`.
  final RegistarAceiteParceiro? registar;

  @override
  State<AdminParceirosTermosScreen> createState() =>
      _AdminParceirosTermosScreenState();
}

class _AdminParceirosTermosScreenState
    extends State<AdminParceirosTermosScreen> {
  List<TermoParceiroLinha> _linhas = const [];
  bool _carregando = true;
  String? _erro;
  String? _aRegistar; // restaurantId em curso

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  static Future<List<TermoParceiroLinha>> _lerDaBase() async {
    final r = await Supabase.instance.client.rpc('admin_parceiros_termos');
    return [
      for (final e in (r as List? ?? const []))
        TermoParceiroLinha.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  static Future<Map<String, dynamic>> _registarNaBase(
      String restaurantId, String via, String nota) async {
    final r = await Supabase.instance.client
        .rpc('admin_registar_aceitacao_termos_parceiro', params: {
      'p_restaurant_id': restaurantId,
      'p_via': via,
      'p_nota': nota,
    });
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = _linhas.isEmpty;
      _erro = null;
    });
    try {
      final l = await (widget.carregar?.call() ?? _lerDaBase());
      if (!mounted) return;
      setState(() {
        _linhas = l;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = mensagemErroTermosParceiro(e);
        _carregando = false;
      });
    }
  }

  void _msg(String t, {Color? cor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), backgroundColor: cor));
  }

  Future<void> _registar(TermoParceiroLinha l) async {
    final escolha = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _RegistarAceiteDialog(loja: l.loja),
    );
    if (escolha == null || !mounted) return;
    final (via, nota) = escolha;
    setState(() => _aRegistar = l.restaurantId);
    try {
      final r = await (widget.registar?.call(l.restaurantId, via, nota) ??
          _registarNaBase(l.restaurantId, via, nota));
      final versao = r['version'] ?? l.versaoAtual ?? '';
      _msg(
        r['ja_aceite'] == true
            ? '${l.loja} já tinha aceitado a versão $versao.'
            : 'Aceite registrado: ${l.loja}, versão $versao (${rotuloViaTermos(via)}).',
        cor: AppColors.success,
      );
      await _carregar();
    } catch (e) {
      _msg(mensagemErroTermosParceiro(e), cor: AppColors.error);
    } finally {
      if (mounted) setState(() => _aRegistar = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termos dos parceiros')),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erro!, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ]),
        ),
      );
    }
    final atual = _linhas.isEmpty ? null : _linhas.first.versaoAtual;
    final aceites = _linhas.where((l) => l.aceiteAtual).length;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text(
            atual == null
                ? 'Nenhuma loja parceira aprovada.'
                : 'Versão em vigor: $atual. $aceites de ${_linhas.length} '
                    'lojas aceitaram.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: Spacing.xs),
          const Text(
            'O parceiro aceita no app (botão "Aceito"). Quem respondeu '
            '"Aceito" por WhatsApp ou email: registre aqui, com uma nota.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.md),
          for (final l in _linhas) _linha(l),
        ],
      ),
    );
  }

  Widget _linha(TermoParceiroLinha l) {
    final ok = l.aceiteAtual;
    final aRegistar = _aRegistar == l.restaurantId;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.hourglass_empty,
                  size: 18, color: ok ? AppColors.success : AppColors.warning),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(l.loja,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: Spacing.xs),
            Text(estadoTermoParceiro(l),
                style: const TextStyle(fontSize: 13)),
            if (l.nota != null)
              Text('Nota: ${l.nota}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            if (l.email != null)
              Text(l.email!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            if (!ok) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed:
                      (_aRegistar != null || l.userId == null) ? null : () => _registar(l),
                  icon: aRegistar
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.how_to_reg, size: 18),
                  label: Text(l.userId == null
                      ? 'Loja sem conta de dono'
                      : 'Registrar aceite'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pede a via (WhatsApp ou email) e uma nota. Devolve `(via, nota)`.
class _RegistarAceiteDialog extends StatefulWidget {
  const _RegistarAceiteDialog({required this.loja});
  final String loja;

  @override
  State<_RegistarAceiteDialog> createState() => _RegistarAceiteDialogState();
}

class _RegistarAceiteDialogState extends State<_RegistarAceiteDialog> {
  String _via = 'whatsapp';
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar aceite'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.loja,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: Spacing.md),
            const Text('Como o parceiro aceitou?'),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
                ButtonSegment(value: 'email', label: Text('Email')),
              ],
              selected: {_via},
              onSelectionChanged: (s) => setState(() => _via = s.first),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _nota,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota',
                hintText: 'Ex.: respondeu "Aceito" no WhatsApp em 27/10',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_via, _nota.text.trim())),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
