import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/prestador_suspensao_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel (PT-BR) → "Revisões": suspensões de prestadores com revisão pedida
/// e propostas automáticas à espera de uma pessoa.
///
/// Missão app-fechar-2026-11-01, bloco B8 (Diretiva (UE) 2024/2831, art. 11.º):
/// a revisão é feita por uma pessoa e respondida por escrito em 7 dias.
///
/// - Separador "Fila": vista `admin_fila_revisoes`. Ações: Responder
///   (`admin_responder_revisao`: mantida | reduzida | revertida) e Decidir
///   proposta (`admin_decidir_proposta`: arquivar | suspensão…).
/// - Separador "Em vigor": suspensões ativas. Ações: Registrar pedido vindo do
///   WhatsApp/email/telefone (`admin_registar_pedido_revisao`) e Reativar
///   (`admin_reativar_prestador`).
///
/// Os carregadores e as ações são injetáveis (testes sem rede).
class AdminRevisoesScreen extends StatefulWidget {
  const AdminRevisoesScreen({
    super.key,
    this.carregarFila,
    this.carregarAtivas,
    this.responder,
    this.decidir,
    this.registar,
    this.reativar,
  });

  final Future<List<RevisaoPendente>> Function()? carregarFila;
  final Future<List<RevisaoPendente>> Function()? carregarAtivas;

  /// (id, decisao, resposta, novaAte)
  final Future<void> Function(int, String, String, DateTime?)? responder;

  /// (id, decisao, motivo, ate)
  final Future<void> Function(int, String, String, DateTime?)? decidir;

  /// (id, via, texto)
  final Future<void> Function(int, String, String)? registar;

  /// (id, nota)
  final Future<void> Function(int, String)? reativar;

  @override
  State<AdminRevisoesScreen> createState() => _AdminRevisoesScreenState();
}

class _AdminRevisoesScreenState extends State<AdminRevisoesScreen> {
  List<RevisaoPendente> _fila = const [];
  List<RevisaoPendente> _ativas = const [];
  bool _aCarregar = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final fila =
          await (widget.carregarFila ?? PrestadorSuspensaoService.fila)();
      final ativas =
          await (widget.carregarAtivas ?? PrestadorSuspensaoService.ativas)();
      if (!mounted) return;
      setState(() {
        _fila = fila;
        _ativas = ativas;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = traduzirErroSuspensao(e);
        _aCarregar = false;
      });
    }
  }

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _abrir(_Decisao d, RevisaoPendente r) async {
    final feito = await showDialog<bool>(
      context: context,
      builder: (_) => DialogoDecisaoRevisao(
        titulo: d.titulo,
        resumo: '${r.rotuloConta} · ${r.rotuloTipo}\nMotivo: ${r.motivo}',
        opcoes: d.opcoes,
        precisaData: d.precisaData,
        minimoTexto: d.minimoTexto,
        rotuloTexto: d.rotuloTexto,
        aoConfirmar: (opcao, texto, data) => d.correr(r.id, opcao, texto, data),
      ),
    );
    if (feito == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Registrado. O prestador é avisado na app.'),
      ));
      await _carregar();
    }
  }

  _Decisao get _responder => _Decisao(
        titulo: 'Responder à revisão',
        opcoes: const [
          ('mantida', 'Manter a decisão'),
          ('reduzida', 'Reduzir (nova data de fim)'),
          ('revertida', 'Reverter (reativar a conta)'),
        ],
        precisaData: (o) => o == 'reduzida',
        minimoTexto: (_) => kMinLetrasMotivoSuspensao,
        rotuloTexto: 'Resposta por escrito (o prestador recebe)',
        correr: _fazerResponder,
      );

  _Decisao get _decidir => _Decisao(
        titulo: 'Decidir proposta automática',
        opcoes: const [
          ('arquivar', 'Arquivar (não fazer nada)'),
          ('suspensao_temporaria', 'Suspensão temporária'),
          ('suspensao', 'Suspensão sem data de fim'),
          ('encerramento', 'Encerrar a conta'),
          ('restricao', 'Restrição (só registra)'),
        ],
        precisaData: (o) => o == 'suspensao_temporaria',
        minimoTexto: (o) => o == 'arquivar' ? 0 : kMinLetrasMotivoSuspensao,
        rotuloTexto: 'Motivo (o prestador recebe se for suspenso)',
        correr: _fazerDecidir,
      );

  _Decisao get _registar => _Decisao(
        titulo: 'Registrar pedido de revisão',
        opcoes: const [
          ('whatsapp', 'Chegou pelo WhatsApp'),
          ('email', 'Chegou por email'),
          ('telefone', 'Chegou por telefone'),
        ],
        precisaData: (_) => false,
        minimoTexto: (_) => 0,
        rotuloTexto: 'O que o prestador disse (resumo)',
        correr: (id, via, texto, _) => _fazerRegistar(id, via, texto),
      );

  _Decisao get _reativar => _Decisao(
        titulo: 'Reativar prestador',
        opcoes: const [('reativar', 'Reativar a conta agora')],
        precisaData: (_) => false,
        minimoTexto: (_) => 3,
        rotuloTexto: 'Nota (o prestador recebe)',
        correr: (id, _, nota, __) => _fazerReativar(id, nota),
      );

  Future<void> _fazerResponder(
      int id, String decisao, String resposta, DateTime? novaAte) async {
    final f = widget.responder;
    if (f != null) return f(id, decisao, resposta, novaAte);
    await PrestadorSuspensaoService.responderRevisao(
        suspensaoId: id,
        decisao: decisao,
        resposta: resposta,
        novaAte: novaAte);
  }

  Future<void> _fazerDecidir(
      int id, String decisao, String motivo, DateTime? ate) async {
    final f = widget.decidir;
    if (f != null) return f(id, decisao, motivo, ate);
    await PrestadorSuspensaoService.decidirProposta(
        suspensaoId: id, decisao: decisao, motivo: motivo, ate: ate);
  }

  Future<void> _fazerRegistar(int id, String via, String texto) async {
    final f = widget.registar;
    if (f != null) return f(id, via, texto);
    await PrestadorSuspensaoService.registarPedido(
        suspensaoId: id, via: via, texto: texto);
  }

  Future<void> _fazerReativar(int id, String nota) async {
    final f = widget.reativar;
    if (f != null) return f(id, nota);
    await PrestadorSuspensaoService.reativar(suspensaoId: id, nota: nota);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(
          title: 'Revisões (suspensões)',
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _aCarregar ? null : _carregar,
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Fila (${_fila.length})'),
              Tab(text: 'Em vigor (${_ativas.length})'),
            ],
          ),
        ),
        body: _aCarregar
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? _ErroCarregar(texto: _erro!, onTentar: _carregar)
                : TabBarView(
                    children: [
                      _lista(
                        _fila,
                        vazio: 'Nenhuma revisão pendente. Quando um prestador '
                            'pedir revisão (na app ou pelo WhatsApp), aparece '
                            'aqui com o prazo de 7 dias.',
                        acoes: (r) => [
                          if (r.eProposta)
                            FilledButton.icon(
                              key: ValueKey('decidir-${r.id}'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary),
                              onPressed: () => _abrir(_decidir, r),
                              icon: const Icon(Icons.how_to_vote_outlined,
                                  size: 18),
                              label: const Text('Decidir proposta'),
                            )
                          else
                            FilledButton.icon(
                              key: ValueKey('responder-${r.id}'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary),
                              onPressed: () => _abrir(_responder, r),
                              icon: const Icon(Icons.reply, size: 18),
                              label: const Text('Responder'),
                            ),
                        ],
                      ),
                      _lista(
                        _ativas,
                        vazio: 'Nenhuma suspensão em vigor.',
                        acoes: (r) => [
                          OutlinedButton.icon(
                            key: ValueKey('registar-${r.id}'),
                            onPressed: () => _abrir(_registar, r),
                            icon: const Icon(Icons.chat_outlined, size: 18),
                            label: const Text('Registrar pedido do WhatsApp'),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey('reativar-${r.id}'),
                            onPressed: () => _abrir(_reativar, r),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reativar'),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _lista(
    List<RevisaoPendente> linhas, {
    required String vazio,
    required List<Widget> Function(RevisaoPendente) acoes,
  }) {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: Spacing.md),
            child: Text(
              'A lei (Diretiva UE 2024/2831) exige que uma pessoa reveja e '
              'responda por escrito. A Bora promete resposta em 7 dias.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          if (linhas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xxl),
              child: Text(vazio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          for (final r in linhas) _CartaoRevisao(r: r, acoes: acoes(r)),
        ],
      ),
    );
  }
}

class _Decisao {
  const _Decisao({
    required this.titulo,
    required this.opcoes,
    required this.precisaData,
    required this.minimoTexto,
    required this.rotuloTexto,
    required this.correr,
  });
  final String titulo;
  final List<(String, String)> opcoes;
  final bool Function(String opcao) precisaData;
  final int Function(String opcao) minimoTexto;
  final String rotuloTexto;
  final Future<void> Function(
      int id, String opcao, String texto, DateTime? data) correr;
}

class _CartaoRevisao extends StatelessWidget {
  const _CartaoRevisao({required this.r, required this.acoes});
  final RevisaoPendente r;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final idCurto =
        r.entidadeId.length > 8 ? r.entidadeId.substring(0, 8) : r.entidadeId;
    final prazo = r.revisaoPrazo;
    final corEstado = r.atrasada
        ? AppColors.error
        : r.eProposta
            ? AppColors.warning
            : AppColors.info;
    return Card(
      key: ValueKey('revisao-${r.id}'),
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.rotuloConta} · ${r.rotuloTipo}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: Spacing.xxs),
                  decoration: BoxDecoration(
                    color: corEstado.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    r.atrasada ? 'ATRASADA' : r.rotuloEstado,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: corEstado),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text('Quem: ${r.entidadeTabela} $idCurto',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xs),
            Text('Motivo: ${r.motivo}'),
            if (r.decididoEm != null)
              Text(
                'Decidido em ${diaEHoraSuspensao(r.decididoEm!)}'
                '${r.decididoPorEmail != null ? ' por ${r.decididoPorEmail}' : ''}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            if (r.ate != null)
              Text('Até ${diaEHoraSuspensao(r.ate!)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            if (r.revisaoPedidaEm != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Pedido em: ${diaEHoraSuspensao(r.revisaoPedidaEm!)}'
                '${r.revisaoVia != null ? ' (via ${r.revisaoVia})' : ''}',
              ),
            ],
            if (r.revisaoTexto != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text('O prestador disse: "${r.revisaoTexto}"',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            if (prazo != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  r.atrasada
                      ? 'Prazo: ${diaEHoraSuspensao(prazo)} — ATRASADA, responda já'
                      : 'Prazo: ${diaEHoraSuspensao(prazo)}'
                          '${r.diasRestantes != null ? ' (faltam ${r.diasRestantes!.toStringAsFixed(1)} dias)' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: r.atrasada ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ),
            if (r.eProposta && r.factos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  'Factos: ${r.factos.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: Spacing.sm),
            Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: acoes),
          ],
        ),
      ),
    );
  }
}

class _ErroCarregar extends StatelessWidget {
  const _ErroCarregar({required this.texto, required this.onTentar});
  final String texto;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off,
                  size: 48, color: AppColors.textSubtle),
              const SizedBox(height: Spacing.md),
              Text(texto, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              FilledButton(
                onPressed: onTentar,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
}

/// Diálogo genérico das decisões (escolha + data opcional + texto). O pedido
/// ao servidor corre aqui dentro e o erro aparece aqui (PADRAO_BORA 3.15 — 2).
class DialogoDecisaoRevisao extends StatefulWidget {
  const DialogoDecisaoRevisao({
    super.key,
    required this.titulo,
    required this.resumo,
    required this.opcoes,
    required this.precisaData,
    required this.minimoTexto,
    required this.rotuloTexto,
    required this.aoConfirmar,
  });

  final String titulo;
  final String resumo;
  final List<(String, String)> opcoes;
  final bool Function(String opcao) precisaData;
  final int Function(String opcao) minimoTexto;
  final String rotuloTexto;
  final Future<void> Function(String opcao, String texto, DateTime? data)
      aoConfirmar;

  @override
  State<DialogoDecisaoRevisao> createState() => _DialogoDecisaoRevisaoState();
}

class _DialogoDecisaoRevisaoState extends State<DialogoDecisaoRevisao> {
  late String _opcao = widget.opcoes.first.$1;
  final TextEditingController _texto = TextEditingController();
  DateTime? _data;
  String? _erroTexto;
  String? _erroServidor;
  bool _aEnviar = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final agora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data ?? agora.add(const Duration(days: 3)),
      firstDate: agora.add(const Duration(days: 1)),
      lastDate: agora.add(const Duration(days: 365)),
    );
    if (d != null && mounted) {
      setState(() => _data = DateTime(d.year, d.month, d.day, 23, 59));
    }
  }

  Future<void> _confirmar() async {
    final minimo = widget.minimoTexto(_opcao);
    if (_texto.text.trim().length < minimo) {
      setState(() => _erroTexto = 'Escreva pelo menos $minimo letras.');
      return;
    }
    if (widget.precisaData(_opcao) && _data == null) {
      setState(() => _erroServidor = 'Escolha a data de fim.');
      return;
    }
    setState(() {
      _aEnviar = true;
      _erroServidor = null;
    });
    try {
      await widget.aoConfirmar(_opcao, _texto.text.trim(),
          widget.precisaData(_opcao) ? _data : null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aEnviar = false;
        _erroServidor = traduzirErroSuspensao(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.resumo,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.md),
            if (widget.opcoes.length > 1)
              DropdownButtonFormField<String>(
                key: const ValueKey('decisao-opcao'),
                // ignore: deprecated_member_use
                value: _opcao,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Decisão'),
                items: [
                  for (final o in widget.opcoes)
                    DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                ],
                onChanged: _aEnviar
                    ? null
                    : (v) => setState(() {
                          _opcao = v ?? _opcao;
                          _erroServidor = null;
                          _erroTexto = null;
                        }),
              ),
            if (widget.precisaData(_opcao))
              Row(
                children: [
                  Expanded(
                    child: Text(_data == null
                        ? 'Nova data de fim: escolha'
                        : 'Até ${diaEHoraSuspensao(_data!)}'),
                  ),
                  TextButton(
                    onPressed: _aEnviar ? null : _escolherData,
                    child: Text(_data == null ? 'Escolher' : 'Alterar'),
                  ),
                ],
              ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey('decisao-texto'),
              controller: _texto,
              enabled: !_aEnviar,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: widget.rotuloTexto,
                errorText: _erroTexto,
              ),
              onChanged: (_) {
                if (_erroTexto != null) setState(() => _erroTexto = null);
              },
            ),
            if (_erroServidor != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(_erroServidor!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('decisao-confirmar'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _aEnviar ? null : _confirmar,
          child: _aEnviar
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirmar'),
        ),
      ],
    );
  }
}
