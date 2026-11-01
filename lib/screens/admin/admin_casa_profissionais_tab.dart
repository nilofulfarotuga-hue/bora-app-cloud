/// CASA — aba "Profissionais" do hub e a ficha completa de cada profissional
/// (painel admin, PT-BR). Aprovar/recusar/suspender/banir/reativar a pessoa,
/// aprovar ofício a ofício (fase 2 só com o documento DGEG/IMPIC aprovado),
/// aprovar/recusar documentos com validade, editar raio/carrinha/ferramentas/
/// bio, ver o que falta da conformidade e o comprovativo de atividade.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '_admin_rpc_errors.dart' show rotuloCampoLegal;
import 'admin_casa_comum.dart';
import 'admin_casa_pedidos_tab.dart' show AdminCasaPedidoScreen;
import 'admin_ficha_prestador.dart' show abrirFichaPrestador;
import 'admin_suspensao_comum.dart';
import '../../services/prestador_suspensao_service.dart';
import '../../widgets/admin/papeis_da_pessoa.dart' show pedirMotivoAdmin;

/// Ações possíveis sobre a pessoa, conforme o estado da aprovação.
List<String> casaAcoesProfissional(String? estado) => switch (estado) {
      'pending' => const ['aprovar', 'recusar', 'banir'],
      'approved' => const ['suspender', 'banir'],
      'suspended' => const ['reativar', 'banir'],
      'rejected' => const ['reativar', 'banir'],
      'banned' => const ['reativar'],
      _ => const ['aprovar', 'recusar'],
    };

String casaAcaoProfissionalPtBr(String acao) => switch (acao) {
      'aprovar' => 'Aprovar',
      'recusar' => 'Recusar',
      'suspender' => 'Suspender',
      'banir' => 'Banir',
      'reativar' => 'Reativar',
      _ => acao,
    };

/// Recusar, suspender e banir pedem motivo (vai para a pessoa e para o
/// registro de auditoria).
bool casaAcaoPedeMotivo(String acao) =>
    acao == 'recusar' || acao == 'suspender' || acao == 'banir';

/// Ofício da fase 2 (eletricidade, gás, pladur, pintura) só se aprova com o
/// documento exigido (DGEG/IMPIC) já aprovado. Fase 1 aprova-se sempre.
bool casaOficioPodeAprovar(
    Map<String, dynamic> oficio, List<Map<String, dynamic>> documentos) {
  final exigido = (oficio['documento_exigido'] ?? '').toString().trim();
  final fase = casaInt(oficio['fase'] ?? 1);
  if (exigido.isEmpty && fase < 2) return true;
  if (exigido.isEmpty) return false;
  final codigo = (oficio['codigo'] ?? '').toString();
  return documentos.any((d) =>
      d['tipo'] == exigido &&
      d['estado'] == 'approved' &&
      (d['oficio'] == null || d['oficio'] == codigo));
}

/// Texto de cada item de `conformidade_em_falta` (texto ou objeto).
String casaRotuloFalta(Object? item) {
  if (item is Map) {
    final m = casaMapa(item);
    final r = m['rotulo'] ?? m['label'] ?? m['campo'] ?? m['codigo'];
    return r == null ? m.toString() : rotuloCampoLegal('$r');
  }
  return rotuloCampoLegal('${item ?? ''}');
}

// ═══════════════════════════════════════════════════════════════════════════
// Lista
// ═══════════════════════════════════════════════════════════════════════════

class AdminCasaProfissionaisTab extends StatefulWidget {
  const AdminCasaProfissionaisTab({super.key, this.rpc});
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaProfissionaisTab> createState() =>
      _AdminCasaProfissionaisTabState();
}

class _AdminCasaProfissionaisTabState extends State<AdminCasaProfissionaisTab> {
  String? _estado = 'pending';
  late Future<List<Map<String, dynamic>>> _future = _load();

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<List<Map<String, dynamic>>> _load() async =>
      casaLista(casaVerOk(await _rpc('admin_casa_profissionais', {
        'p_estado': _estado,
      })));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _abrir(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          AdminCasaProfissionalScreen(id: '${p['id']}', rpc: widget.rpc),
    ));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CasaFiltros(
          opcoes: kCasaAprovacoes,
          valor: _estado,
          rotulo: (s) => '${casaAprovacaoPtBr(s)}s',
          onMudar: (v) {
            _estado = v;
            _refresh();
          },
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
              }
              final lista = snap.data ?? const <Map<String, dynamic>>[];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: lista.isEmpty
                    ? ListView(children: const [
                        CasaVazio('Nenhum profissional neste filtro.'),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: Spacing.huge),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _CartaoProfissional(
                          p: lista[i],
                          onTap: () => _abrir(lista[i]),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CartaoProfissional extends StatelessWidget {
  const _CartaoProfissional({required this.p, required this.onTap});
  final Map<String, dynamic> p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nome = casaTexto(p['name']);
    final estado = p['approval_status']?.toString();
    final docsPendentes = casaInt(p['docs_pendentes']);
    final oficios = casaLista(p['oficios']);
    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryWash,
                  child: Text(nome == '—' ? '?' : nome.substring(0, 1),
                      style: const TextStyle(color: AppColors.primary)),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                        '${casaTexto(p['phone'])} · ${casaTexto(p['email'])}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                CasaEtiqueta(casaAprovacaoPtBr(estado),
                    cor: casaAprovacaoCor(estado)),
              ]),
              const SizedBox(height: Spacing.sm),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final o in oficios)
                  CasaEtiqueta(
                    '${o['nome'] ?? o['codigo']}: '
                    '${casaOficioEstadoPtBr(o['estado']?.toString()).replaceFirst('Ofício ', '')}'
                    '${o['ligado'] == false ? ' (desligado)' : ''}',
                    cor: o['estado'] == 'approved'
                        ? AppColors.success
                        : o['estado'] == 'pending'
                            ? AppColors.warning
                            : AppColors.error,
                  ),
                if (docsPendentes > 0)
                  CasaEtiqueta(
                      '$docsPendentes documento${docsPendentes == 1 ? '' : 's'} por analisar',
                      cor: AppColors.warning),
                if (p['is_active'] == false)
                  const CasaEtiqueta('Pausado', cor: AppColors.textSecondary),
              ]),
              const SizedBox(height: Spacing.xs),
              Text(
                'Cadastro ${casaDataHora(p['created_at'])} · '
                'nota ${casaDouble(p['rating_avg']).toStringAsFixed(1).replaceAll('.', ',')} '
                '(${casaInt(p['ratings_count'])}) · '
                '${casaInt(p['jobs_done'])} trabalhos'
                '${p['sem_comissao_ate'] == null ? '' : ' · sem comissão até ${casaData(p['sem_comissao_ate'])}'}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ficha
// ═══════════════════════════════════════════════════════════════════════════

class AdminCasaProfissionalScreen extends StatefulWidget {
  const AdminCasaProfissionalScreen({super.key, required this.id, this.rpc});
  final String id;
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaProfissionalScreen> createState() =>
      _AdminCasaProfissionalScreenState();
}

class _AdminCasaProfissionalScreenState
    extends State<AdminCasaProfissionalScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _busy = false;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<Map<String, dynamic>> _load() async => casaMapa(casaVerOk(
      await _rpc('admin_casa_profissional', {'p_id': widget.id})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<bool> _correr(
      String fn, Map<String, dynamic> params, String sucesso) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final ok = await casaExecutar(context, () => _rpc(fn, params), sucesso);
    if (!mounted) return ok;
    setState(() => _busy = false);
    if (ok) await _refresh();
    return ok;
  }

  // ── Pessoa ──────────────────────────────────────────────────────────────

  Future<void> _decidirPessoa(
      String acao, String nome, List<Object?> falta) async {
    final rotulo = casaAcaoProfissionalPtBr(acao);
    final avisoFalta = acao == 'aprovar' && falta.isNotEmpty
        ? '\n\nAinda falta: ${falta.map(casaRotuloFalta).join(', ')}. O '
            'servidor pode recusar a aprovação até isto estar completo.'
        : '';
    final avisoOficios = acao == 'aprovar'
        ? '\n\nAprovar a pessoa não aprova os ofícios: cada ofício aprova-se '
            'abaixo, um a um.'
        : '';
    // [01/11/2026 · B8] Suspender/banir = decisão sobre a conta: motivo com
    // 10 letras (o gatilho do servidor recusa sem ele e o profissional
    // recebe-o por escrito — Diretiva 2024/2831).
    final String? motivo;
    if (acao == 'suspender' || acao == 'banir') {
      motivo = await pedirMotivoAdmin(
        context,
        titulo: '$rotulo $nome?',
        explicacao: 'A pessoa recebe o motivo por escrito, pode pedir '
            'revisão (uma pessoa responde em 7 dias) e fica no registro '
            'de auditoria.',
        confirmar: rotulo,
        perigoso: true,
        minimo: kMinLetrasMotivoSuspensao,
      );
    } else {
      motivo = await casaConfirmar(
        context,
        titulo: '$rotulo $nome?',
        texto: 'A pessoa é avisada da decisão e fica no registro de '
            'auditoria.$avisoOficios$avisoFalta',
        botao: rotulo,
        perigo: acao != 'aprovar' && acao != 'reativar',
        pedirTexto: true,
        textoObrigatorio: casaAcaoPedeMotivo(acao),
        rotuloTexto: 'Motivo',
      );
    }
    if (motivo == null || !mounted) return;
    final ok = await _correr('admin_casa_decidir_profissional', {
      'p_id': widget.id,
      'p_acao': acao,
      'p_motivo': motivo,
    }, 'Decisão registrada: $rotulo.');
    // Reativar fecha também o registo legal da suspensão.
    if (ok && acao == 'reativar') {
      await PrestadorSuspensaoService.fecharRegistoAberto('casa_profissionais',
          widget.id, 'Reativado no painel (Casa)');
    }
  }

  // ── Ofícios ─────────────────────────────────────────────────────────────

  Future<void> _decidirOficio(Map<String, dynamic> o, String acao) async {
    final nome = casaTexto(o['nome'] ?? o['codigo']);
    final rotulo = switch (acao) {
      'aprovar' => 'Aprovar',
      'recusar' => 'Recusar',
      _ => 'Suspender',
    };
    final motivo = await casaConfirmar(
      context,
      titulo: '$rotulo o ofício "$nome"?',
      texto: acao == 'aprovar'
          ? 'O profissional passa a receber ofertas e convites deste ofício.'
          : 'O profissional deixa de receber ofertas e convites deste ofício.',
      botao: rotulo,
      perigo: acao != 'aprovar',
      pedirTexto: true,
      textoObrigatorio: acao != 'aprovar',
    );
    if (motivo == null) return;
    await _correr('admin_casa_decidir_oficio', {
      'p_profissional_id': widget.id,
      'p_oficio': o['codigo'],
      'p_acao': acao,
      'p_motivo': motivo,
    }, 'Ofício "$nome": $rotulo registrado.');
  }

  // ── Documentos ──────────────────────────────────────────────────────────

  Future<void> _decidirDocumento(Map<String, dynamic> d, String acao) async {
    final tipo = casaDocumentoTipoPtBr(d['tipo']?.toString());
    if (acao == 'aprovar') {
      final escrito = await casaConfirmar(
        context,
        titulo: 'Aprovar "$tipo"?',
        texto: 'Confira o documento antes. Escreva a validade que está no '
            'documento (deixe vazio se não tiver).',
        botao: 'Aprovar',
        pedirTexto: true,
        rotuloTexto: 'Validade (DD/MM/AAAA ou AAAA-MM-DD)',
        inicial: d['validade'] == null ? '' : '${d['validade']}',
      );
      if (escrito == null) return;
      final v = casaLerValidade(escrito);
      if (!v.ok) {
        if (mounted) casaMsg(context, 'Validade inválida: "$escrito".');
        return;
      }
      await _correr('admin_casa_decidir_documento', {
        'p_documento_id': d['id'],
        'p_acao': 'aprovar',
        'p_motivo': '',
        'p_validade': v.iso,
      }, '"$tipo" aprovado.');
      return;
    }
    final motivo = await casaConfirmar(
      context,
      titulo: 'Recusar "$tipo"?',
      texto: 'O profissional é avisado para enviar de novo.',
      botao: 'Recusar',
      perigo: true,
      pedirTexto: true,
      textoObrigatorio: true,
      rotuloTexto: 'Motivo (vai para o profissional)',
    );
    if (motivo == null) return;
    await _correr('admin_casa_decidir_documento', {
      'p_documento_id': d['id'],
      'p_acao': 'recusar',
      'p_motivo': motivo,
      'p_validade': null,
    }, '"$tipo" recusado.');
  }

  // ── Editar ──────────────────────────────────────────────────────────────

  Future<void> _editar(Map<String, dynamic> perfil) async {
    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditarProfissionalDialog(perfil: perfil),
    );
    if (dados == null) return;
    await _correr('admin_casa_editar_profissional', {
      'p_id': widget.id,
      'p_dados': dados,
    }, 'Dados do profissional salvos.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profissional da Casa'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar'),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
          }
          return _corpo(snap.data ?? const {});
        },
      ),
    );
  }

  Widget _corpo(Map<String, dynamic> m) {
    final perfil = casaMapa(m['perfil']);
    final oficios = casaLista(m['oficios']);
    final documentos = casaLista(m['documentos']);
    final disponibilidade = casaLista(m['disponibilidade']);
    final pedidos = casaLista(m['pedidos']);
    final falta = (m['conformidade_em_falta'] is List)
        ? List<Object?>.from(m['conformidade_em_falta'] as List)
        : const <Object?>[];
    final nome = casaTexto(perfil['name']);
    final estado = perfil['approval_status']?.toString();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.huge),
        children: [
          Row(children: [
            Expanded(
              child: Text(nome,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            CasaEtiqueta(casaAprovacaoPtBr(estado),
                cor: casaAprovacaoCor(estado)),
          ]),
          if ((perfil['rejection_reason'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text('Motivo: ${perfil['rejection_reason']}',
                  style: const TextStyle(color: AppColors.error)),
            ),
          const SizedBox(height: Spacing.sm),
          Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
            for (final a in casaAcoesProfissional(estado))
              FilledButton(
                key: ValueKey('casa-prof-acao-$a'),
                style: FilledButton.styleFrom(
                    backgroundColor: a == 'aprovar' || a == 'reativar'
                        ? AppColors.primary
                        : AppColors.error),
                onPressed:
                    _busy ? null : () => _decidirPessoa(a, nome, falta),
                child: Text(casaAcaoProfissionalPtBr(a)),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _editar(perfil),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar raio, carrinha, ferramentas e bio'),
            ),
            // [01/11/2026 · B8] Registo legal completo (temporária, sem data,
            // encerramento ou restrição) com motivo escrito.
            if (estado == 'approved')
              BotaoSuspenderComMotivo(
                tabela: 'casa_profissionais',
                entidadeId: widget.id,
                nome: nome,
                onFeito: _refresh,
              ),
          ]),

          const CasaSeccao('Conformidade e atividade'),
          CasaLinha('Atividade', casaAtividadePtBr(m['atividade_status']?.toString()),
              cor: m['atividade_status'] == 'aprovada'
                  ? AppColors.success
                  : AppColors.error),
          if (falta.isEmpty)
            const CasaLinha('Dados legais', 'Completos', cor: AppColors.success)
          else
            CasaLinha('Ainda falta', falta.map(casaRotuloFalta).join(', '),
                cor: AppColors.error),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => abrirFichaPrestador(
                context,
                papel: 'handyman',
                linha: {...perfil, '_casa_documentos': documentos},
                aoMudar: _refresh,
              ),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Ficha legal completa (pedir o que falta)'),
            ),
          ),

          const CasaSeccao('Ofícios (aprovação um a um)'),
          if (oficios.isEmpty) const CasaVazio('Sem ofícios escolhidos.'),
          for (final o in oficios) _oficio(o, documentos),

          const CasaSeccao('Documentos'),
          if (documentos.isEmpty) const CasaVazio('Nenhum documento enviado.'),
          for (final d in documentos) _documento(d),

          const CasaSeccao('Dados'),
          CasaLinha('Telefone', perfil['phone']),
          CasaLinha('E-mail', perfil['email']),
          CasaLinha('NIF', perfil['nif']),
          CasaLinha('Nome legal', perfil['legal_name']),
          CasaLinha('Endereço fiscal', perfil['address']),
          CasaLinha('IBAN', perfil['iban']),
          CasaLinha('Zona base', perfil['base_address']),
          CasaLinha('Raio', perfil['service_radius_km'] == null
              ? null
              : '${casaDouble(perfil['service_radius_km']).round()} km'),
          CasaLinha('Carrinha', perfil['has_van'] == true ? 'Sim' : 'Não'),
          CasaLinha('Ferramentas próprias',
              perfil['has_tools'] == true ? 'Sim' : 'Não'),
          CasaLinha('Sobre', perfil['bio']),
          CasaLinha('Recebe trabalhos',
              perfil['is_active'] == false ? 'Pausado' : 'Ativo'),
          CasaLinha(
              'Nota',
              '${casaDouble(perfil['rating_avg']).toStringAsFixed(1).replaceAll('.', ',')} '
                  '(${casaInt(perfil['ratings_count'])} avaliações) · '
                  '${casaInt(perfil['jobs_done'])} trabalhos'),
          CasaLinha(
              'Sem comissão até',
              perfil['sem_comissao_ate'] == null
                  ? null
                  : '${casaData(perfil['sem_comissao_ate'])} (promoção dos 5 primeiros)'),
          CasaLinha('Cadastro', casaDataHora(perfil['created_at'])),
          CasaLinha('Aprovado em', casaDataHora(perfil['approved_at'])),

          const CasaSeccao('Disponibilidade (hora de Lisboa)'),
          if (disponibilidade.isEmpty)
            const CasaVazio('Sem horários definidos.')
          else
            for (final s in disponibilidade)
              CasaLinha(
                  casaDiaSemanaPtBr(s['weekday']),
                  '${casaTexto(s['start'] ?? s['start_time'])} – '
                  '${casaTexto(s['end'] ?? s['end_time'])}'),

          const CasaSeccao('Pedidos deste profissional'),
          if (pedidos.isEmpty) const CasaVazio('Ainda sem pedidos.'),
          for (final p in pedidos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(casaTexto(p['servico_nome'])),
              subtitle: Text('${casaEstadoPtBr(p['estado']?.toString())} · '
                  '${casaDataHora(p['scheduled_at'] ?? p['created_at'])}'),
              trailing: Text(casaEuroAdmin(p['total_cents'])),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    AdminCasaPedidoScreen(id: '${p['id']}', rpc: widget.rpc),
              )),
            ),
        ],
      ),
    );
  }

  Widget _oficio(Map<String, dynamic> o, List<Map<String, dynamic>> docs) {
    final estado = o['estado']?.toString();
    final fase = casaInt(o['fase'] ?? 1);
    final exigido = o['documento_exigido']?.toString();
    final podeAprovar = casaOficioPodeAprovar(o, docs);
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                    '${casaTexto(o['nome'] ?? o['codigo'])} · fase $fase',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              CasaEtiqueta(casaOficioEstadoPtBr(estado),
                  cor: estado == 'approved'
                      ? AppColors.success
                      : estado == 'pending'
                          ? AppColors.warning
                          : AppColors.error),
            ]),
            Text(
              o['ligado'] == false
                  ? 'Desligado pelo profissional'
                  : 'Ligado pelo profissional',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if ((o['motivo'] ?? '').toString().trim().isNotEmpty)
              Text('Motivo: ${o['motivo']}',
                  style: const TextStyle(fontSize: 12)),
            if (exigido != null && exigido.isNotEmpty)
              Container(
                key: ValueKey('casa-oficio-fase2-${o['codigo']}'),
                margin: const EdgeInsets.only(top: Spacing.xs),
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: (podeAprovar ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  podeAprovar
                      ? 'Documento exigido aprovado: ${casaDocumentoTipoPtBr(exigido)}.'
                      : 'Fase 2: só se aprova com o documento '
                          '${casaDocumentoTipoPtBr(exigido)} APROVADO. '
                          'Aprove primeiro o documento abaixo.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: Spacing.xs),
            Wrap(spacing: Spacing.sm, children: [
              if (estado != 'approved')
                TextButton(
                  key: ValueKey('casa-oficio-aprovar-${o['codigo']}'),
                  onPressed: _busy || !podeAprovar
                      ? null
                      : () => _decidirOficio(o, 'aprovar'),
                  child: const Text('Aprovar ofício'),
                ),
              if (estado == 'pending')
                TextButton(
                  onPressed: _busy ? null : () => _decidirOficio(o, 'recusar'),
                  child: const Text('Recusar',
                      style: TextStyle(color: AppColors.error)),
                ),
              if (estado == 'approved')
                TextButton(
                  onPressed:
                      _busy ? null : () => _decidirOficio(o, 'suspender'),
                  child: const Text('Suspender ofício',
                      style: TextStyle(color: AppColors.error)),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _documento(Map<String, dynamic> d) {
    final estado = d['estado']?.toString();
    final tipo = casaDocumentoTipoPtBr(d['tipo']?.toString());
    final caminho = (d['storage_path'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '$tipo${d['oficio'] == null ? '' : ' · ofício ${d['oficio']}'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              CasaEtiqueta(casaDocumentoEstadoPtBr(estado),
                  cor: estado == 'approved'
                      ? AppColors.success
                      : estado == 'pending'
                          ? AppColors.warning
                          : AppColors.error),
            ]),
            CasaLinha('Número', d['numero']),
            CasaLinha('Validade', casaData(d['validade'])),
            CasaLinha('Enviado em', casaDataHora(d['created_at'])),
            if ((d['motivo'] ?? '').toString().trim().isNotEmpty)
              CasaLinha('Motivo', d['motivo']),
            Wrap(spacing: Spacing.sm, children: [
              OutlinedButton.icon(
                onPressed: caminho.isEmpty
                    ? null
                    : () => casaAbrirFicheiro(context,
                        balde: kBaldeCasaDocumentos,
                        caminho: caminho,
                        titulo: tipo),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Abrir documento'),
              ),
              if (estado != 'approved')
                TextButton(
                  onPressed:
                      _busy ? null : () => _decidirDocumento(d, 'aprovar'),
                  child: const Text('Aprovar'),
                ),
              if (estado != 'rejected')
                TextButton(
                  onPressed:
                      _busy ? null : () => _decidirDocumento(d, 'recusar'),
                  child: const Text('Recusar',
                      style: TextStyle(color: AppColors.error)),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Editar raio, carrinha, ferramentas, bio e zona base. Devolve só as chaves
/// que o servidor aceita (`admin_casa_editar_profissional`).
class _EditarProfissionalDialog extends StatefulWidget {
  const _EditarProfissionalDialog({required this.perfil});
  final Map<String, dynamic> perfil;

  @override
  State<_EditarProfissionalDialog> createState() =>
      _EditarProfissionalDialogState();
}

class _EditarProfissionalDialogState extends State<_EditarProfissionalDialog> {
  late double _raio =
      casaDouble(widget.perfil['service_radius_km'] ?? 15).clamp(1.0, 100.0);
  late bool _van = widget.perfil['has_van'] == true;
  late bool _ferramentas = widget.perfil['has_tools'] != false;
  late final _bio = TextEditingController(text: '${widget.perfil['bio'] ?? ''}');
  late final _zona =
      TextEditingController(text: '${widget.perfil['base_address'] ?? ''}');
  late final _lat = TextEditingController(
      text: widget.perfil['base_lat'] == null ? '' : '${widget.perfil['base_lat']}');
  late final _lng = TextEditingController(
      text: widget.perfil['base_lng'] == null ? '' : '${widget.perfil['base_lng']}');

  @override
  void dispose() {
    _bio.dispose();
    _zona.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _guardar() {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    Navigator.pop(context, <String, dynamic>{
      'service_radius_km': _raio.round(),
      'has_van': _van,
      'has_tools': _ferramentas,
      'bio': _bio.text.trim(),
      'base_address': _zona.text.trim(),
      if (lat != null) 'base_lat': lat,
      if (lng != null) 'base_lng': lng,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar ${casaTexto(widget.perfil['name'])}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Raio de trabalho: ${_raio.round()} km'),
            Slider(
              value: _raio,
              min: 1,
              max: 100,
              divisions: 99,
              activeColor: AppColors.primary,
              label: '${_raio.round()} km',
              onChanged: (v) => setState(() => _raio = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tem carrinha'),
              value: _van,
              onChanged: (v) => setState(() => _van = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tem ferramentas próprias'),
              value: _ferramentas,
              onChanged: (v) => setState(() => _ferramentas = v),
            ),
            TextField(
              controller: _bio,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'Sobre (bio)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _zona,
              decoration: const InputDecoration(
                  labelText: 'Zona base (endereço)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: Spacing.sm),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Latitude', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: TextField(
                  controller: _lng,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Longitude', border: OutlineInputBorder()),
                ),
              ),
            ]),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Salvar')),
      ],
    );
  }
}
