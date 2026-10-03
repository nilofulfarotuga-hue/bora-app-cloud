// lib/screens/admin/admin_conformidade_legal_screen.dart
//
// [ronda-fecho-2026-09-22 · BLOCO D4] Painel admin (PT-BR): "Conformidade legal".
//
// Um só lugar para o estado legal da plataforma: os itens do DSA (Regulamento
// dos Serviços Digitais, art. 30: identificação do vendedor) e do DAC7
// (relatório anual de vendedores de plataforma para a AT), os prestadores com
// dados em falta, o opt-in de marketing, as lojas parceiras sem NIF ou morada,
// e a exportação DAC7 anual em CSV.
//
// Leitura: RPC admin_conformidade_legal (guarda is_admin()).
// Exportação: RPC admin_dac7_export(p_ano) → CSV com ';' descarregado (web) ou
// partilhado (telemóvel) pelo AdminExportService.
// Este ecrã não escreve nada na base.
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '_admin_rpc_errors.dart';

typedef CarregarConformidade = Future<Map<String, dynamic>> Function();
typedef ExportarDac7 = Future<Map<String, dynamic>> Function(int ano);
typedef GuardarCsv = Future<void> Function(String nomeFicheiro, String csv);

/// Rotas nomeadas que existem mesmo em `main.dart` (`routes:`), conferidas
/// com `grep "'/admin/" lib/main.dart` a 23/09/2026. O botão "Abrir" de um
/// item só aparece quando a rota que o servidor devolve está aqui: uma rota
/// que não existe abriria a página "rota desconhecida", e um botão que não
/// leva a lado nenhum é pior do que nenhum botão (PADRÃO BORA §1.2).
/// `/admin/conformidade` é este ecrã — não se abre a si próprio.
const Set<String> kRotasAdminConhecidas = {
  '/admin',
  '/admin/pendencias',
  '/admin/configuracoes',
  '/admin/parceiros',
  '/admin/notificacoes',
  '/admin/acertos-semana',
  '/admin/cleaning/cleaners',
  '/admin/crosstalk',
  '/admin/dinheiro-retido-falta',
  '/admin/drivers/approval',
  '/admin/ledger',
  '/admin/marcacoes-por-confirmar',
  '/admin/motores',
  '/admin/orders',
  '/admin/partners/pending',
  '/admin/ratings',
  '/admin/robot',
  '/admin/robot-suggestions',
  '/admin/settlements',
  '/admin/suggestions/metrics',
  '/admin/tvde',
  '/admin/tvde/access-requests',
  '/admin/tvde/noshows',
  '/admin/tvde/pagamentos',
  '/admin/tvde/reservas',
  '/admin/users',
  '/admin/whatsapp',
};

bool rotaAdminExiste(String? rota) =>
    rota != null && kRotasAdminConhecidas.contains(rota);

/// Cabeçalho do CSV DAC7 (PT-BR, separador ';'), pela ordem pedida.
const List<String> kCabecalhoCsvDac7 = [
  'ano',
  'tipo',
  'id',
  'nome',
  'nome_comercial',
  'nif',
  'morada',
  'data_nascimento',
  'iban',
  'pais',
  'autocertificado_em',
  'trimestre_1_eur',
  'trimestre_2_eur',
  'trimestre_3_eur',
  'trimestre_4_eur',
  'total_eur',
  'comissoes_bora_eur',
  'transacoes',
  'campos_em_falta',
];

/// Tipos de prestador que o servidor devolve, pela ordem da tabela, com o
/// rótulo PT-BR.
const List<(String, String)> kTiposPrestador = [
  ('driver', 'Estafetas/Motoristas'),
  ('partner', 'Parceiros'),
  ('cleaner', 'Faxineiros'),
  ('washer', 'Lavadores'),
  ('provider', 'Prestadores de serviços'),
];

String rotuloTipoPrestador(String? tipo) {
  for (final t in kTiposPrestador) {
    if (t.$1 == tipo) return t.$2;
  }
  return tipo ?? '—';
}

String rotuloAprovacao(String? estado) => switch (estado) {
      'approved' => 'Aprovado',
      'pending' => 'Pendente',
      'rejected' => 'Recusado',
      null || '' => 'Sem estado',
      _ => estado,
    };

/// Rótulo e cor do estado de um item: ok = verde, parcial = laranja,
/// falta = vermelho.
(String, Color) estadoItem(String? estado) => switch (estado) {
      'ok' => ('OK', AppColors.success),
      'parcial' => ('Parcial', AppColors.accent),
      'falta' => ('Falta', AppColors.error),
      _ => (estado ?? '—', AppColors.textSecondary),
    };

/// 12168 → "121,68". Cêntimos inteiros para euros com vírgula decimal, sem
/// passar por vírgula flutuante (dinheiro soma-se em inteiros).
String centsParaEuros(dynamic cents) {
  final int n = switch (cents) {
    null => 0,
    final num v => v.round(),
    final String s => int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0,
    _ => 0,
  };
  final abs = n.abs();
  return '${n < 0 ? '-' : ''}${abs ~/ 100},'
      '${(abs % 100).toString().padLeft(2, '0')}';
}

String nomeFicheiroDac7(int ano) => 'dac7_${ano}_bora.csv';

/// Linhas do RPC `admin_dac7_export` → CSV com ';', valores em euros (2 casas,
/// vírgula decimal), `campos_em_falta` unidos por '|'. Campos com ';', aspas ou
/// quebra de linha ficam entre aspas, com as aspas interiores dobradas.
String construirCsvDac7(List<Map<String, dynamic>> linhas) {
  String txt(dynamic v) => v?.toString() ?? '';
  final rows = <List<String>>[
    kCabecalhoCsvDac7,
    for (final l in linhas)
      [
        txt(l['ano']),
        txt(l['tipo']),
        txt(l['id']),
        txt(l['nome']),
        txt(l['nome_comercial']),
        txt(l['nif']),
        txt(l['morada']),
        txt(l['data_nascimento']),
        txt(l['iban']),
        txt(l['pais']),
        txt(l['autocertificado_em']),
        centsParaEuros(l['trimestre_1_cents']),
        centsParaEuros(l['trimestre_2_cents']),
        centsParaEuros(l['trimestre_3_cents']),
        centsParaEuros(l['trimestre_4_cents']),
        centsParaEuros(l['total_cents']),
        centsParaEuros(l['comissoes_bora_cents']),
        txt(l['transacoes']),
        (l['campos_em_falta'] as List? ?? const []).map(txt).join('|'),
      ],
  ];
  return const ListToCsvConverter(fieldDelimiter: ';', eol: '\n').convert(rows);
}

/// ISO do servidor → "dd/MM/yyyy HH:mm" na hora local do navegador (o painel
/// vive na web, no fuso do Danilo). Sem `intl`: não é dependência direta.
String formatarDataHora(dynamic iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso.toString());
  if (dt == null) return iso.toString();
  final l = dt.toLocal();
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${d2(l.day)}/${d2(l.month)}/${l.year} ${d2(l.hour)}:${d2(l.minute)}';
}

List<Map<String, dynamic>> _lista(dynamic v) => (v as List? ?? const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

Map<String, dynamic> _mapa(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class AdminConformidadeLegalScreen extends StatefulWidget {
  const AdminConformidadeLegalScreen({
    super.key,
    this.carregar,
    this.exportar,
    this.guardarCsv,
    this.anoAtual,
  });

  /// Lê o estado (por defeito `rpc('admin_conformidade_legal')`).
  final CarregarConformidade? carregar;

  /// Gera as linhas DAC7 de um ano (por defeito `rpc('admin_dac7_export')`).
  final ExportarDac7? exportar;

  /// Entrega o CSV ao Danilo (por defeito descarrega na web ou abre a folha
  /// de partilha no telemóvel, via [AdminExportService.exportCsvText]).
  final GuardarCsv? guardarCsv;

  /// Ano de referência do seletor DAC7 (por defeito o ano civil de hoje).
  /// Os testes fixam-no para não dependerem do calendário.
  final int? anoAtual;

  @override
  State<AdminConformidadeLegalScreen> createState() =>
      _AdminConformidadeLegalScreenState();
}

class _AdminConformidadeLegalScreenState
    extends State<AdminConformidadeLegalScreen> {
  bool _loading = true;
  String? _erro;
  Map<String, dynamic> _dados = const {};
  String? _filtroTipo; // null = todos os tipos
  late int _ano;
  bool _exportando = false;
  String? _notaDac7;
  int? _linhasExportadas;
  int? _anoExportado;

  @override
  void initState() {
    super.initState();
    _ano = widget.anoAtual ?? DateTime.now().year;
    _load();
  }

  Future<Map<String, dynamic>> _carregarPadrao() async {
    final r = await Supabase.instance.client.rpc('admin_conformidade_legal');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<Map<String, dynamic>> _exportarPadrao(int ano) async {
    final r = await Supabase.instance.client
        .rpc('admin_dac7_export', params: {'p_ano': ano});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> _guardarCsvPadrao(String nome, String csv) => AdminExportService
      .instance
      .exportCsvText(filename: nome, csv: csv, subject: 'DAC7 Bora — $nome');

  Future<void> _load({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _loading = true;
        _erro = null;
      });
    }
    try {
      final d = await (widget.carregar ?? _carregarPadrao)();
      if (!mounted) return;
      setState(() {
        _dados = d;
        _erro = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _exportarDac7() async {
    final ano = _ano;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportando = true);
    try {
      final r = await (widget.exportar ?? _exportarPadrao)(ano);
      final linhas = _lista(r['linhas']);
      if (linhas.isNotEmpty) {
        await (widget.guardarCsv ?? _guardarCsvPadrao)(
            nomeFicheiroDac7(ano), construirCsvDac7(linhas));
      }
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(switch (linhas.length) {
            0 => 'Sem linhas para $ano',
            1 => 'Exportada 1 linha',
            final n => 'Exportadas $n linhas',
          }),
        ));
      if (!mounted) return;
      setState(() {
        _notaDac7 = r['nota']?.toString();
        _linhasExportadas = linhas.length;
        _anoExportado = ano;
      });
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content:
              Text('Não foi possível exportar: ${humanizeAdminRpcError(e)}'),
        ));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Conformidade legal'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final erro = _erro;
    if (erro != null) {
      return _Aviso(
        icone: Icons.error_outline,
        cor: AppColors.error,
        titulo: 'Não foi possível carregar.',
        texto: erro,
        botao: 'Tentar de novo',
        onBotao: _load,
      );
    }
    final itens = _lista(_dados['itens']);
    final prestadores = _mapa(_dados['prestadores']);
    final resumo = _mapa(prestadores['resumo']);
    final incompletos = _lista(prestadores['incompletos']);
    if (itens.isEmpty && resumo.isEmpty && incompletos.isEmpty) {
      return _Aviso(
        icone: Icons.inbox_outlined,
        cor: AppColors.textSecondary,
        titulo: 'Nada para mostrar.',
        texto: 'O servidor não devolveu itens de conformidade.',
        botao: 'Atualizar',
        onBotao: _load,
      );
    }
    final filtrados = _filtroTipo == null
        ? incompletos
        : incompletos.where((p) => p['tipo'] == _filtroTipo).toList();
    final anos = [_ano - 2, _ano - 1, _ano];
    if (!anos.contains(_ano)) anos.add(_ano);

    return RefreshIndicator(
      onRefresh: () => _load(silencioso: true),
      child: ListView(
        key: const Key('conformidade-lista'),
        padding: const EdgeInsets.all(12),
        children: [
          _cabecalho(),
          const SizedBox(height: 8),
          const _TituloSeccao(
            'Itens legais',
            ajuda: 'DSA = Regulamento dos Serviços Digitais (art. 30: '
                'identificação do vendedor). DAC7 = relatório anual de '
                'vendedores de plataforma para a AT.',
          ),
          for (final it in itens)
            _ItemCard(
              item: it,
              onAbrir: rotaAdminExiste(it['rota']?.toString())
                  ? () => Navigator.of(context).pushNamed(it['rota'].toString())
                  : null,
            ),
          const SizedBox(height: 12),
          _PrestadoresCard(resumo: resumo),
          const SizedBox(height: 12),
          _IncompletosCard(
            todos: incompletos,
            filtrados: filtrados,
            filtro: _filtroTipo,
            onFiltro: (t) => setState(() => _filtroTipo = t),
          ),
          const SizedBox(height: 12),
          _MarketingCard(marketing: _mapa(_dados['marketing'])),
          const SizedBox(height: 12),
          _LojasCard(lojas: _mapa(_dados['lojas'])),
          const SizedBox(height: 12),
          _Dac7Card(
            anos: anos,
            ano: _ano,
            exportando: _exportando,
            nota: _notaDac7,
            linhasExportadas: _linhasExportadas,
            anoExportado: _anoExportado,
            onAno: (a) => setState(() => _ano = a),
            onExportar: _exportarDac7,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    final obrig = _dados['ativacao_obrigatoria'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gerado em ${formatarDataHora(_dados['gerado_em'])}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  obrig ? Icons.lock_outline : Icons.lock_open,
                  size: 16,
                  color: obrig ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    obrig
                        ? 'Ativação obrigatória: ligada. Ninguém é aprovado '
                            'sem os dados legais.'
                        : 'Ativação obrigatória: desligada. O servidor só '
                            'avisa; um prestador pode ser aprovado sem os '
                            'dados legais.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: obrig ? AppColors.textPrimary : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.texto,
    required this.botao,
    required this.onBotao,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final String texto;
  final String botao;
  final VoidCallback onBotao;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 44, color: cor),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(texto,
                textAlign: TextAlign.center, style: TextStyle(color: cor)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: onBotao,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(botao),
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSeccao extends StatelessWidget {
  const _TituloSeccao(this.titulo, {this.ajuda});

  final String titulo;
  final String? ajuda;

  @override
  Widget build(BuildContext context) {
    final ajuda = this.ajuda;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          if (ajuda != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ajuda,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pilula extends StatelessWidget {
  const _Pilula({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.onAbrir});

  final Map<String, dynamic> item;
  final VoidCallback? onAbrir;

  @override
  Widget build(BuildContext context) {
    final codigo = item['codigo']?.toString() ?? '';
    final (rotulo, cor) = estadoItem(item['estado']?.toString());
    final detalhe = item['detalhe']?.toString() ?? '';
    return Card(
      key: ValueKey('conformidade-item-$codigo'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Pilula(texto: rotulo, cor: cor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['titulo']?.toString() ?? codigo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
            if (detalhe.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detalhe,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            if (onAbrir != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAbrir,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrestadoresCard extends StatelessWidget {
  const _PrestadoresCard({required this.resumo});

  final Map<String, dynamic> resumo;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('tabela-prestadores'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSeccao(
              'Prestadores',
              ajuda: 'Completo = tem nome legal, NIF, morada, IBAN, data de '
                  'nascimento e autocertificação DSA. Os aprovados '
                  'incompletos já trabalham sem os dados: precisam de '
                  'completar na app.',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 8,
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Total'), numeric: true),
                  DataColumn(label: Text('Aprovados'), numeric: true),
                  DataColumn(label: Text('Completos'), numeric: true),
                  DataColumn(label: Text('Incompletos'), numeric: true),
                  DataColumn(
                      label: Text('Aprovados incompletos'), numeric: true),
                ],
                rows: [
                  for (final (tipo, rotulo) in kTiposPrestador)
                    _linha(tipo, rotulo, _mapa(resumo[tipo])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _linha(String tipo, String rotulo, Map<String, dynamic> r) {
    final aprInc = _int(r['aprovados_incompletos']);
    return DataRow(
      key: ValueKey('prestadores-$tipo'),
      cells: [
        DataCell(
            Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Text('${_int(r['total'])}')),
        DataCell(Text('${_int(r['aprovados'])}')),
        DataCell(Text('${_int(r['completos'])}')),
        DataCell(Text('${_int(r['incompletos'])}')),
        DataCell(Text(
          '$aprInc',
          key: ValueKey('apr-inc-$tipo'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: aprInc > 0 ? AppColors.error : AppColors.textPrimary,
          ),
        )),
      ],
    );
  }
}

class _IncompletosCard extends StatelessWidget {
  const _IncompletosCard({
    required this.todos,
    required this.filtrados,
    required this.filtro,
    required this.onFiltro,
  });

  final List<Map<String, dynamic>> todos;
  final List<Map<String, dynamic>> filtrados;
  final String? filtro;
  final ValueChanged<String?> onFiltro;

  int _conta(String? tipo) => tipo == null
      ? todos.length
      : todos.where((p) => p['tipo'] == tipo).length;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('seccao-incompletos'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TituloSeccao(
              'Incompletos (${todos.length})',
              ajuda: 'Quem ainda não tem todos os dados legais. Sem eles a '
                  'ativação fica bloqueada (DSA art. 30) e o DAC7 sai com '
                  'campos em falta.',
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text('Todos (${_conta(null)})'),
                  selected: filtro == null,
                  onSelected: (_) => onFiltro(null),
                ),
                for (final (tipo, rotulo) in kTiposPrestador)
                  ChoiceChip(
                    label: Text('$rotulo (${_conta(tipo)})'),
                    selected: filtro == tipo,
                    onSelected: (_) => onFiltro(tipo),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (filtrados.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  todos.isEmpty
                      ? 'Todos os prestadores têm os dados legais completos.'
                      : 'Nenhum incompleto neste tipo.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ...filtrados.map((p) => _IncompletoLinha(p: p)),
          ],
        ),
      ),
    );
  }
}

class _IncompletoLinha extends StatelessWidget {
  const _IncompletoLinha({required this.p});

  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final tipo = p['tipo']?.toString();
    final aprov = p['approval_status']?.toString();
    final aprovado = aprov == 'approved';
    final falta = (p['falta'] as List? ?? const []).map((e) => '$e').toList();
    final nome = (p['nome']?.toString() ?? '').trim();
    final phone = (p['phone']?.toString() ?? '').trim();
    return Container(
      key: ValueKey('incompleto-$tipo-${p['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: aprovado ? const Color(0xFFFCA5A5) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  nome.isEmpty ? '(sem nome)' : nome,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // Aprovado E incompleto é o caso grave: já trabalha sem os
              // dados legais. Por isso o vermelho vai para o "Aprovado".
              _Pilula(
                texto: rotuloAprovacao(aprov),
                cor: aprovado ? AppColors.error : AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${rotuloTipoPrestador(tipo)} · '
            '${phone.isEmpty ? 'sem telefone' : phone}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final f in falta)
                _Pilula(texto: rotuloCampoLegal(f), cor: AppColors.error),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({super.key, required this.rotulo, required this.valor, this.cor});

  final String rotulo;
  final String valor;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cor ?? AppColors.textPrimary,
            ),
          ),
          Text(
            rotulo,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MarketingCard extends StatelessWidget {
  const _MarketingCard({required this.marketing});

  final Map<String, dynamic> marketing;

  @override
  Widget build(BuildContext context) {
    final ultimo = marketing['ultimo_opt_in'];
    return Card(
      key: const Key('cartao-marketing'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSeccao(
              'Marketing',
              ajuda: 'Opt-in = o cliente autorizou receber promoções. O push '
                  'comercial (promo, cashback, referral) só vai a quem tem '
                  'opt-in.',
            ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _Kpi(
                  key: const Key('kpi-clientes'),
                  rotulo: 'Clientes',
                  valor: '${_int(marketing['clientes'])}',
                ),
                _Kpi(
                  key: const Key('kpi-com-opt-in'),
                  rotulo: 'Com opt-in',
                  valor: '${_int(marketing['com_opt_in'])}',
                ),
                _Kpi(
                  key: const Key('kpi-ultimo-opt-in'),
                  rotulo: 'Último opt-in',
                  valor: ultimo == null ? 'nunca' : formatarDataHora(ultimo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LojasCard extends StatelessWidget {
  const _LojasCard({required this.lojas});

  final Map<String, dynamic> lojas;

  @override
  Widget build(BuildContext context) {
    final semNif = _int(lojas['sem_nif']);
    final semMorada = _int(lojas['sem_morada']);
    return Card(
      key: const Key('cartao-lojas'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSeccao(
              'Lojas parceiras',
              ajuda: 'O recibo do cliente tem de mostrar nome, NIF e morada '
                  'do vendedor (DSA art. 30). Sem NIF ou sem morada, o '
                  'recibo sai incompleto.',
            ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _Kpi(
                  key: const Key('kpi-aprovadas'),
                  rotulo: 'Aprovadas',
                  valor: '${_int(lojas['aprovadas'])}',
                ),
                _Kpi(
                  key: const Key('kpi-sem-nif'),
                  rotulo: 'Sem NIF',
                  valor: '$semNif',
                  cor: semNif > 0 ? AppColors.error : null,
                ),
                _Kpi(
                  key: const Key('kpi-sem-morada'),
                  rotulo: 'Sem morada',
                  valor: '$semMorada',
                  cor: semMorada > 0 ? AppColors.error : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dac7Card extends StatelessWidget {
  const _Dac7Card({
    required this.anos,
    required this.ano,
    required this.exportando,
    required this.onAno,
    required this.onExportar,
    this.nota,
    this.linhasExportadas,
    this.anoExportado,
  });

  final List<int> anos;
  final int ano;
  final bool exportando;
  final ValueChanged<int> onAno;
  final VoidCallback onExportar;
  final String? nota;
  final int? linhasExportadas;
  final int? anoExportado;

  @override
  Widget build(BuildContext context) {
    final nota = this.nota;
    final n = linhasExportadas;
    return Card(
      key: const Key('cartao-dac7'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSeccao(
              'DAC7 (relatório anual de vendedores de plataforma para a AT)',
              ajuda: 'Uma linha por vendedor com os totais por trimestre (em '
                  'euros), as comissões da Bora e o número de operações. '
                  'Entregar à AT até 31 de janeiro do ano seguinte.',
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in anos)
                  ChoiceChip(
                    key: ValueKey('ano-$a'),
                    label: Text('$a'),
                    selected: a == ano,
                    onSelected: exportando ? null : (_) => onAno(a),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('botao-exportar-dac7'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: exportando ? null : onExportar,
                icon: exportando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text('Exportar CSV DAC7 ($ano)'),
              ),
            ),
            if (n != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  n == 0
                      ? 'Última exportação: sem linhas para $anoExportado.'
                      : 'Última exportação: $n linhas de $anoExportado '
                          '(${nomeFicheiroDac7(anoExportado ?? ano)}).',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            if (nota != null && nota.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  nota,
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
