// Livro de Reclamações — registro das reclamações recebidas (missão
// fechar-tudo-2026-11-10, bloco E2e). PT-BR (painel).
//
// DL 156/2005, art. 5.º-B: a Bora responde ao consumidor em 15 dias ÚTEIS.
// Aqui o Danilo registra cada reclamação que chega (Livro eletrônico ou
// físico, entidade reguladora, email), vê quantos dias úteis faltam e marca
// como respondida. O prazo é calculado por `lib/utils/dias_uteis.dart`
// (sem fins de semana nem feriados nacionais) e fica gravado na linha.
// O aviso no topo do painel é o `AlertaLivroReclamacoesCard`.
//
// Tabela `livro_reclamacoes_registo` (migração 20261110190200): só admin.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/legal_identity.dart';
import '../../services/admin_audit_service.dart';
import '../../utils/dias_uteis.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Canais de entrada (valores da coluna `canal`) e o nome no painel.
const Map<String, String> kCanaisReclamacao = {
  'livro_eletronico': 'Livro de Reclamações eletrônico',
  'livro_fisico': 'Livro de Reclamações físico',
  'entidade_reguladora': 'Entidade reguladora (DGC/ASAE)',
  'email': 'Email',
  'outro': 'Outro',
};

String dataCurta(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Hoje, em Lisboa (só a data).
DateTime hojeLisboa() => soData(horaLisboa(DateTime.now()));

/// O texto do prazo de uma reclamação (função pura, testada).
String textoDoPrazo({
  required DateTime hoje,
  required DateTime prazo,
  bool respondida = false,
  DateTime? respondidaEm,
}) {
  switch (estadoDoPrazo(hoje: hoje, prazo: prazo, respondida: respondida)) {
    case EstadoPrazoReclamacao.respondida:
      return respondidaEm == null
          ? 'Respondida'
          : 'Respondida em ${dataCurta(respondidaEm)}';
    case EstadoPrazoReclamacao.vencido:
      final n = -diasUteisAtePrazo(hoje, prazo);
      return 'VENCIDA — o prazo era ${dataCurta(prazo)}'
          '${n > 0 ? ' ($n ${n == 1 ? 'dia útil' : 'dias úteis'} de atraso)' : ''}';
    case EstadoPrazoReclamacao.alerta:
    case EstadoPrazoReclamacao.emDia:
      final n = diasUteisAtePrazo(hoje, prazo);
      if (n == 0) return 'Prazo termina HOJE (${dataCurta(prazo)})';
      return 'Faltam $n ${n == 1 ? 'dia útil' : 'dias úteis'} — prazo ${dataCurta(prazo)}';
  }
}

Color corDoPrazo(EstadoPrazoReclamacao e) => switch (e) {
      EstadoPrazoReclamacao.vencido => AppColors.error,
      EstadoPrazoReclamacao.alerta => AppColors.warning,
      EstadoPrazoReclamacao.emDia => AppColors.primary,
      EstadoPrazoReclamacao.respondida => AppColors.textSecondary,
    };

class AdminLivroReclamacoesScreen extends StatefulWidget {
  const AdminLivroReclamacoesScreen({super.key});

  @override
  State<AdminLivroReclamacoesScreen> createState() =>
      _AdminLivroReclamacoesScreenState();
}

class _AdminLivroReclamacoesScreenState
    extends State<AdminLivroReclamacoesScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _sb
          .from('livro_reclamacoes_registo')
          .select()
          .order('estado', ascending: true)
          .order('prazo', ascending: true)
          .limit(500);
      if (!mounted) return;
      setState(() {
        _rows = [for (final e in res) Map<String, dynamic>.from(e)];
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminLivroReclamacoes] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar o registro. Se a migração '
            '20261110190200_livro_reclamacoes_registo ainda não foi aplicada, '
            'a tabela não existe.';
        _loading = false;
      });
    }
  }

  Future<void> _registrar() async {
    final novo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _DialogoNovaReclamacao(),
    );
    if (novo == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final linhas = await _sb
          .from('livro_reclamacoes_registo')
          .insert(novo)
          .select('id');
      if (linhas.isEmpty) {
        throw StateError('nenhuma linha gravada (sem permissão?)');
      }
      await AdminAuditService.logAction(
        action: 'livro_reclamacoes_registada',
        entityType: 'livro_reclamacoes',
        details: {
          'id': linhas.first['id'],
          'canal': novo['canal'],
          'numero': novo['numero'],
          'prazo': novo['prazo'],
        },
      );
      messenger.showSnackBar(const SnackBar(content: Text('Reclamação registrada.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível registrar: $e')));
    }
  }

  Future<void> _marcarRespondida(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como respondida'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Resumo da resposta enviada ao consumidor (opcional)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Respondida')),
        ],
      ),
    );
    final resposta = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final linhas = await _sb
          .from('livro_reclamacoes_registo')
          .update({
            'estado': 'respondida',
            'respondida_em': DateTime.now().toUtc().toIso8601String(),
            if (resposta.isNotEmpty) 'resposta_resumo': resposta,
          })
          .eq('id', r['id'])
          .select('id');
      if (linhas.isEmpty) {
        throw StateError('nenhuma linha gravada (sem permissão?)');
      }
      await AdminAuditService.logAction(
        action: 'livro_reclamacoes_respondida',
        entityType: 'livro_reclamacoes',
        details: {'id': r['id'], 'numero': r['numero']},
      );
      messenger.showSnackBar(const SnackBar(content: Text('Marcada como respondida.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoje = hojeLisboa();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Livro de Reclamações',
        actions: [
          AdminCsvButton(
            nome: 'livro_reclamacoes',
            colunas: const [
              ('recebida_em', 'recebida em'),
              ('canal', 'canal'),
              ('numero', 'número/referência'),
              ('quem', 'quem'),
              ('resumo', 'resumo'),
              ('prazo', 'prazo (15 dias úteis)'),
              ('estado', 'estado'),
              ('respondida_em', 'respondida em (Lisboa)'),
              ('resposta_resumo', 'resposta'),
            ],
            linhas: () => _rows,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrar,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Registrar reclamação'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      const _ComoFunciona(),
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma reclamação registrada.',
                              textAlign: TextAlign.center),
                        )
                      else
                        for (final r in _rows) _cartao(r, hoje),
                    ],
                  ),
                ),
    );
  }

  Widget _cartao(Map<String, dynamic> r, DateTime hoje) {
    final prazo = DateTime.tryParse('${r['prazo']}');
    final recebida = DateTime.tryParse('${r['recebida_em']}');
    final respondida = r['estado'] != 'aberta';
    final respondidaEm = DateTime.tryParse('${r['respondida_em'] ?? ''}');
    final estado = prazo == null
        ? EstadoPrazoReclamacao.emDia
        : estadoDoPrazo(hoje: hoje, prazo: prazo, respondida: respondida);
    final cor = corDoPrazo(estado);
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: estado == EstadoPrazoReclamacao.vencido ||
                    estado == EstadoPrazoReclamacao.alerta
                ? cor
                : AppColors.divider,
            width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(r['numero'] ?? '').toString().isEmpty ? 'Sem número' : 'N.º ${r['numero']}'}'
              ' · ${kCanaisReclamacao[r['canal']] ?? r['canal']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Recebida em ${recebida == null ? '—' : dataCurta(recebida)}'
              '${(r['quem'] ?? '').toString().isEmpty ? '' : ' · ${r['quem']}'}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text('${r['resumo'] ?? ''}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  estado == EstadoPrazoReclamacao.respondida
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                  size: 18,
                  color: cor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    prazo == null
                        ? 'Sem prazo'
                        : textoDoPrazo(
                            hoje: hoje,
                            prazo: prazo,
                            respondida: respondida,
                            respondidaEm: respondidaEm == null
                                ? null
                                : horaLisboa(respondidaEm)),
                    style: TextStyle(
                        color: cor, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (!respondida)
                  TextButton(
                    onPressed: () => _marcarRespondida(r),
                    child: const Text('Marcar respondida'),
                  ),
              ],
            ),
            if ((r['resposta_resumo'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Resposta: ${r['resposta_resumo']}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona();

  @override
  Widget build(BuildContext context) => const Card(
        color: Colors.white,
        margin: EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Prazo legal: responder ao consumidor em 15 dias úteis '
            '(DL 156/2005, art. 5.º-B). Os dias úteis contam a partir do dia '
            'seguinte ao recebimento, sem sábados, domingos e feriados '
            'nacionais (o feriado municipal da Guarda não é descontado, para '
            'o prazo nunca ficar mais longo). O painel avisa quando faltam 3 '
            'dias úteis ou menos. As reclamações do Livro eletrônico chegam por '
            'email da plataforma ${LegalIdentity.livroReclamacoesUrl} — '
            'registre aqui assim que chegarem.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
}

/// Formulário "Registrar reclamação". Devolve a linha para inserir.
class _DialogoNovaReclamacao extends StatefulWidget {
  const _DialogoNovaReclamacao();

  @override
  State<_DialogoNovaReclamacao> createState() => _DialogoNovaReclamacaoState();
}

class _DialogoNovaReclamacaoState extends State<_DialogoNovaReclamacao> {
  DateTime _recebida = hojeLisboa();
  String _canal = 'livro_eletronico';
  final _numero = TextEditingController();
  final _quem = TextEditingController();
  final _resumo = TextEditingController();

  @override
  void dispose() {
    _numero.dispose();
    _quem.dispose();
    _resumo.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _recebida,
      firstDate: DateTime(2025, 1, 1),
      lastDate: hojeLisboa(),
    );
    if (d != null) setState(() => _recebida = soData(d));
  }

  @override
  Widget build(BuildContext context) {
    final prazo = somarDiasUteis(_recebida, kDiasUteisLivroReclamacoes);
    final podeGravar = _resumo.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Registrar reclamação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.event),
              label: Text('Recebida em ${dataCurta(_recebida)}'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _canal,
              decoration: const InputDecoration(labelText: 'Canal'),
              items: [
                for (final e in kCanaisReclamacao.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _canal = v ?? _canal),
            ),
            TextField(
              controller: _numero,
              maxLength: 80,
              decoration: const InputDecoration(
                  labelText: 'Número / referência da reclamação'),
            ),
            TextField(
              controller: _quem,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Quem reclamou (nome ou email)'),
            ),
            TextField(
              controller: _resumo,
              maxLines: 4,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Resumo da reclamação (obrigatório)'),
            ),
            const SizedBox(height: 4),
            Text(
              'Prazo para responder: ${dataCurta(prazo)} '
              '(15 dias úteis depois de ${dataCurta(_recebida)})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: !podeGravar
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                    'recebida_em': _iso(_recebida),
                    'canal': _canal,
                    if (_numero.text.trim().isNotEmpty)
                      'numero': _numero.text.trim(),
                    if (_quem.text.trim().isNotEmpty) 'quem': _quem.text.trim(),
                    'resumo': _resumo.text.trim(),
                    'prazo': _iso(prazo),
                  }),
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
