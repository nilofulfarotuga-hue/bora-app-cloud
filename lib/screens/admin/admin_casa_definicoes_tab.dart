/// CASA — aba "Configurações" do hub (painel admin, PT-BR):
///  · interruptor geral (NASCE DESLIGADO; ligar pede confirmação forte);
///  · registrar a autorização do Danilo (texto com "autorizo" + data) — só
///    depois de ele dizer "autorizo";
///  · novidade do lançamento: selo "Novo" no atalho (`casa_novo_ate`, ligar,
///    desligar e a data) e o caminho para a faixa da home (09/11/2026);
///  · testadores (lista de uuid em `casa_testadores`);
///  · comissão e promoção (PROPOSTA até ao autorizo);
///  · tempos de oferta, orçamento, cancelamento, garantia e o resto.
/// Tudo pelas funções `admin_casa_definicoes / guardar_definicao /
/// interruptor / autorizar_valores`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/casa_models.dart' show casaSeloNovoVisivel;
import 'admin_casa_comum.dart';
import 'admin_home_banners_screen.dart';

/// Chave do selo "Novo" do atalho da Casa (data AAAA-MM-DD; vazia = sem selo).
const String kCasaChaveNovoAte = 'casa_novo_ate';

/// Quantos dias dura o selo "Novo" quando se liga sem data (lançamento).
const int kCasaDiasSeloNovo = 14;

/// A data que o selo leva ao ligar: hoje (Lisboa) + [kCasaDiasSeloNovo] dias.
String casaNovoAteAoLigar(DateTime hojeLisboa) =>
    casaIsoData(hojeLisboa.add(const Duration(days: kCasaDiasSeloNovo)));

/// Grupo em que cada chave aparece.
String casaGrupoDefinicao(String key) {
  if (key == kCasaChaveNovoAte) return 'novidade';
  if (key == 'casa_enabled') return 'interruptor';
  if (key == 'casa_valores_autorizados') return 'autorizacao';
  if (key == 'casa_testadores') return 'testadores';
  if (key.startsWith('casa_bora_pct') ||
      key.startsWith('casa_promo_') ||
      key.contains('comissao')) {
    return 'proposta';
  }
  return 'tempos';
}

/// Lê o valor escrito no painel com o mesmo tipo que o valor antigo tinha.
/// Lança [FormatException] se não se perceber.
Object? casaLerValorDefinicao(Object? original, String texto) {
  final t = texto.trim();
  if (original is bool) {
    final l = t.toLowerCase();
    if (l == 'true' || l == 'sim' || l == 'ligado') return true;
    if (l == 'false' || l == 'não' || l == 'nao' || l == 'desligado') {
      return false;
    }
    throw const FormatException('Escreva sim ou não.');
  }
  if (original is num) {
    final n = num.tryParse(t.replaceAll(',', '.'));
    if (n == null) throw const FormatException('Escreva um número.');
    return original is int && n == n.roundToDouble() ? n.round() : n;
  }
  if (original is String) return t;
  try {
    return jsonDecode(t);
  } catch (_) {
    throw const FormatException('JSON inválido.');
  }
}

/// Valor para mostrar e para pôr no campo de edição.
String casaValorParaTexto(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return jsonEncode(v);
}

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

bool casaEhUuid(String s) => _uuid.hasMatch(s.trim());

/// O texto da autorização tem de conter "autorizo" (o servidor também confere).
bool casaTemAutorizo(String texto) =>
    texto.toLowerCase().contains('autorizo');

/// O que vai para `admin_casa_autorizar_valores(p_texto)`: o texto exato do
/// Danilo e o dia em que ele o disse (a função só recebe texto; o servidor
/// regista sozinho a hora do registro e quem registrou).
String casaTextoAutorizacao(String texto, DateTime dia) {
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${texto.trim()} (dito pelo Danilo em '
      '${dd(dia.day)}/${dd(dia.month)}/${dia.year})';
}

class AdminCasaDefinicoesTab extends StatefulWidget {
  const AdminCasaDefinicoesTab({super.key, this.rpc});
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaDefinicoesTab> createState() => _AdminCasaDefinicoesTabState();
}

class _AdminCasaDefinicoesTabState extends State<AdminCasaDefinicoesTab> {
  late Future<
      ({
        List<Map<String, dynamic>> defs,
        bool ligado,
        CasaValores valores
      })> _future = _load();
  bool _busy = false;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<({List<Map<String, dynamic>> defs, bool ligado, CasaValores valores})>
      _load() async {
    final defs = casaLista(casaVerOk(await _rpc('admin_casa_definicoes', {})));
    final resumo = casaMapa(casaVerOk(await _rpc('admin_casa_resumo', {})));
    return (
      defs: defs,
      ligado: resumo['enabled'] == true,
      valores: CasaValores.fromJson(resumo['valores_autorizados']),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _correr(
      String fn, Map<String, dynamic> params, String sucesso) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await casaExecutar(context, () => _rpc(fn, params), sucesso);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _refresh();
  }

  // ── Interruptor ─────────────────────────────────────────────────────────

  Future<void> _interruptor(bool ligar) async {
    final ok = ligar
        ? await casaConfirmar(
            context,
            titulo: 'LIGAR a Casa para todos os clientes?',
            texto: 'Todos os clientes passam a ver o atalho "Casa" na tela inicial e podem '
                'fazer pedidos reais. Confira antes: profissionais aprovados, '
                'ofícios aprovados e os valores AUTORIZADOS pelo Danilo.\n\n'
                'Para confirmar, escreva LIGAR.',
            botao: 'Ligar a Casa',
            perigo: true,
            exigido: 'LIGAR',
            rotuloTexto: 'Confirmação',
          )
        : await casaConfirmar(
            context,
            titulo: 'Desligar a Casa?',
            texto: 'Os clientes deixam de ver a Casa (só os testadores). '
                'Pedidos já feitos continuam.',
            botao: 'Desligar',
          );
    if (ok == null) return;
    await _correr('admin_casa_interruptor', {'p_ligado': ligar},
        ligar ? 'Casa LIGADA.' : 'Casa desligada.');
  }

  // ── Autorização ─────────────────────────────────────────────────────────

  Future<void> _autorizar() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => const CasaAutorizarDialog(),
    );
    if (texto == null) return;
    await _correr('admin_casa_autorizar_valores', {'p_texto': texto},
        'Autorização do Danilo registrada.');
  }

  // ── Testadores ──────────────────────────────────────────────────────────

  Future<void> _guardarTestadores(List<String> lista) async {
    final ok = await casaConfirmar(
      context,
      titulo: 'Salvar testadores?',
      texto: '${lista.length} testador${lista.length == 1 ? '' : 'es'}. Os '
          'testadores veem a Casa mesmo com o interruptor desligado e os '
          'pedidos deles ficam marcados como teste.',
      botao: 'Salvar',
    );
    if (ok == null) return;
    await _correr('admin_casa_guardar_definicao',
        {'p_key': 'casa_testadores', 'p_value': lista}, 'Testadores salvos.');
  }

  // ── Novidade: selo "Novo" no atalho ─────────────────────────────────────

  Future<void> _seloNovo(bool ligar) async {
    final valor = ligar ? casaNovoAteAoLigar(casaHojeLisboa()) : '';
    await _correr(
        'admin_casa_guardar_definicao',
        {'p_key': kCasaChaveNovoAte, 'p_value': valor},
        ligar
            ? 'Selo "Novo" ligado até ${casaData(valor)}.'
            : 'Selo "Novo" desligado.');
  }

  Future<void> _dataSeloNovo(String atual) async {
    final hoje = casaHojeLisboa();
    final lida = casaLerValidade(atual);
    final inicial = lida.iso == null
        ? hoje.add(const Duration(days: kCasaDiasSeloNovo))
        : DateTime.parse(lida.iso!);
    final escolhida = await showDatePicker(
      context: context,
      initialDate: inicial.isBefore(hoje) ? hoje : inicial,
      firstDate: hoje,
      lastDate: hoje.add(const Duration(days: 120)),
      helpText: 'Selo "Novo" até (inclusive)',
    );
    if (escolhida == null) return;
    final iso = casaIsoData(escolhida);
    await _correr('admin_casa_guardar_definicao',
        {'p_key': kCasaChaveNovoAte, 'p_value': iso},
        'Selo "Novo" até ${casaData(iso)}.');
  }

  // ── Definição genérica ──────────────────────────────────────────────────

  Future<void> _editar(Map<String, dynamic> d) async {
    final key = '${d['key']}';
    final original = d['value'];
    final proposta = casaGrupoDefinicao(key) == 'proposta';
    final escrito = await casaConfirmar(
      context,
      titulo: 'Mudar ${casaTexto(d['description'] ?? key)}',
      texto: '${proposta ? '$kCasaTextoProposta.\nMudar isto volta a pôr os '
              'valores como PROPOSTA até o Danilo dizer autorizo.\n\n' : ''}'
          'Chave técnica: $key',
      botao: 'Salvar',
      perigo: proposta,
      pedirTexto: true,
      // O tipo confere-se depois (casaLerValorDefinicao); "60" tem só 2
      // letras e não pode cair na regra dos 3 caracteres do motivo.
      textoObrigatorio: false,
      rotuloTexto: 'Novo valor',
      inicial: casaValorParaTexto(original),
      linhas: original is Map || original is List ? 4 : 1,
    );
    if (escrito == null) return;
    Object? valor;
    try {
      valor = casaLerValorDefinicao(original, escrito);
    } on FormatException catch (e) {
      if (mounted) casaMsg(context, 'Valor inválido: ${e.message}');
      return;
    }
    await _correr('admin_casa_guardar_definicao', {'p_key': key, 'p_value': valor},
        'Configuração salva.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        ({List<Map<String, dynamic>> defs, bool ligado, CasaValores valores})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
        }
        final dados = snap.data!;
        final defs = dados.defs;
        final testadores = defs
            .where((d) => d['key'] == 'casa_testadores')
            .map((d) => d['value'])
            .firstWhere((_) => true, orElse: () => null);
        final proposta =
            defs.where((d) => casaGrupoDefinicao('${d['key']}') == 'proposta');
        final tempos =
            defs.where((d) => casaGrupoDefinicao('${d['key']}') == 'tempos');
        // null = a chave ainda não existe no servidor (entra na publicação).
        String? novoAte;
        for (final d in defs) {
          if (d['key'] == kCasaChaveNovoAte) {
            novoAte = casaValorParaTexto(d['value']);
          }
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.huge),
            children: [
              // Interruptor geral
              Card(
                child: SwitchListTile(
                  key: const ValueKey('casa-interruptor'),
                  value: dados.ligado,
                  onChanged: _busy ? null : _interruptor,
                  title: Text(
                    dados.ligado
                        ? 'Casa LIGADA para todos os clientes'
                        : 'Casa DESLIGADA (só os testadores veem)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                      'Interruptor geral. Nasce desligado; ligar pede '
                      'confirmação forte.'),
                ),
              ),
              const SizedBox(height: Spacing.md),

              // Autorização dos valores
              CasaAvisoValores(valores: dados.valores),
              const SizedBox(height: Spacing.sm),
              FilledButton.icon(
                key: const ValueKey('casa-registrar-autorizo'),
                onPressed: _busy ? null : _autorizar,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Registrar autorização do Danilo'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  'Só se usa DEPOIS de o Danilo dizer "autorizo" (com a data). '
                  'Cole o texto exato dele. Qualquer mudança de preço, comissão '
                  'ou promoção volta a pôr os valores como PROPOSTA.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),

              const CasaSeccao('Novidade (lançamento)'),
              _CartaoNovidade(
                novoAte: novoAte,
                busy: _busy,
                onLigar: _seloNovo,
                onData: _dataSeloNovo,
              ),

              const CasaSeccao('Testadores'),
              _EditorTestadores(
                inicial: testadores is List
                    ? [for (final t in testadores) '$t']
                    : const <String>[],
                busy: _busy,
                onGuardar: _guardarTestadores,
              ),

              CasaSeccao('Comissão e promoção'
                  '${dados.valores.autorizado ? '' : ' — PROPOSTA'}'),
              if (proposta.isEmpty)
                const CasaVazio('Sem chaves de comissão no servidor.'),
              for (final d in proposta)
                _linhaDefinicao(d, proposta: !dados.valores.autorizado),

              const CasaSeccao('Tempos e limites'),
              if (tempos.isEmpty) const CasaVazio('Sem outras configurações.'),
              for (final d in tempos) _linhaDefinicao(d),
            ],
          ),
        );
      },
    );
  }

  Widget _linhaDefinicao(Map<String, dynamic> d, {bool proposta = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      child: ListTile(
        title: Text(casaTexto(d['description'] ?? d['key']),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${d['key']}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (proposta)
              const Padding(
                padding: EdgeInsets.only(right: Spacing.sm),
                child: CasaEtiqueta('PROPOSTA', cor: AppColors.warning),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(casaTexto(casaValorParaTexto(d['value'])),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        onTap: _busy ? null : () => _editar(d),
      ),
    );
  }
}

/// Lista de testadores (uuid de utilizador). Guarda a lista inteira.
class _EditorTestadores extends StatefulWidget {
  const _EditorTestadores(
      {required this.inicial, required this.busy, required this.onGuardar});
  final List<String> inicial;
  final bool busy;
  final Future<void> Function(List<String>) onGuardar;

  @override
  State<_EditorTestadores> createState() => _EditorTestadoresState();
}

class _EditorTestadoresState extends State<_EditorTestadores> {
  late List<String> _lista = List<String>.from(widget.inicial);
  final _novo = TextEditingController();
  String? _erro;

  @override
  void didUpdateWidget(covariant _EditorTestadores old) {
    super.didUpdateWidget(old);
    if (old.inicial.join(',') != widget.inicial.join(',')) {
      _lista = List<String>.from(widget.inicial);
    }
  }

  @override
  void dispose() {
    _novo.dispose();
    super.dispose();
  }

  void _juntar() {
    final t = _novo.text.trim().toLowerCase();
    if (!casaEhUuid(t)) {
      setState(() => _erro = 'Não é um id de usuário (uuid).');
      return;
    }
    if (_lista.contains(t)) {
      setState(() => _erro = 'Já está na lista.');
      return;
    }
    setState(() {
      _lista = [..._lista, t];
      _erro = null;
      _novo.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mudou = _lista.join(',') != widget.inicial.join(',');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Os testadores veem a Casa mesmo desligada e fazem pedidos de '
              'teste (correm mesmo com os valores por autorizar).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (_lista.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text('Nenhum testador.'),
              ),
            for (final t in _lista)
              Row(children: [
                Expanded(
                  child: SelectableText(t,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
                IconButton(
                  tooltip: 'Tirar',
                  onPressed: widget.busy
                      ? null
                      : () => setState(
                          () => _lista = _lista.where((x) => x != t).toList()),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: AppColors.error),
                ),
              ]),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('casa-testador-novo'),
                  controller: _novo,
                  decoration: InputDecoration(
                    labelText: 'Id do usuário (uuid)',
                    errorText: _erro,
                  ),
                  onSubmitted: (_) => _juntar(),
                ),
              ),
              IconButton(
                tooltip: 'Juntar',
                onPressed: widget.busy ? null : _juntar,
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            ]),
            const SizedBox(height: Spacing.sm),
            FilledButton(
              onPressed:
                  widget.busy || !mudou ? null : () => widget.onGuardar(_lista),
              child: const Text('Salvar testadores'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Novidade do lançamento (09/11/2026): o selo "Novo" no atalho da Casa (ligar,
/// desligar e a data, guardada em `casa_novo_ate`) e o caminho para a faixa
/// da home, que se gere no ecrã "Faixas da home" (ver/ligar/desligar/datas).
class _CartaoNovidade extends StatelessWidget {
  const _CartaoNovidade({
    required this.novoAte,
    required this.busy,
    required this.onLigar,
    required this.onData,
  });

  /// Valor de `casa_novo_ate`; null = a chave ainda não existe no servidor.
  final String? novoAte;
  final bool busy;
  final Future<void> Function(bool ligar) onLigar;
  final Future<void> Function(String atual) onData;

  @override
  Widget build(BuildContext context) {
    final existe = novoAte != null;
    final ativo = casaSeloNovoVisivel(novoAte, DateTime.now());
    final temData = (novoAte ?? '').trim().isNotEmpty;
    final String estado;
    if (!existe) {
      estado = 'A configuração $kCasaChaveNovoAte ainda não existe no servidor '
          '(entra na publicação da Casa).';
    } else if (ativo) {
      estado = 'Aparece no atalho "Casa" da tela inicial até '
          '${casaData(novoAte)} (inclusive, hora de Lisboa).';
    } else if (temData) {
      estado = 'Desligado — terminou em ${casaData(novoAte)}.';
    } else {
      estado = 'Desligado.';
    }
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('casa-selo-novo'),
            value: ativo,
            onChanged: !existe || busy ? null : onLigar,
            title: const Text('Selo "Novo" no atalho da Casa',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(estado, key: const ValueKey('casa-selo-novo-estado')),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: TextButton.icon(
                key: const ValueKey('casa-selo-novo-data'),
                onPressed: !existe || busy ? null : () => onData(novoAte!),
                icon: const Icon(Icons.event_outlined),
                label: Text(ativo ? 'Mudar a data' : 'Escolher a data'),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('casa-faixa-home'),
            leading: const Icon(Icons.view_carousel_outlined),
            title: const Text('Faixa da tela inicial'),
            subtitle: const Text(
                'Para ver, ligar, desligar ou mudar as datas da faixa '
                '"Novidade: Casa & Manutenção", abra Faixas da home '
                '(destino Categoria → Casa).'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const AdminHomeBannersScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo "Registrar autorização do Danilo": o texto exato dele (tem de ter
/// "autorizo") e a data em que o disse. Devolve o texto final ou null.
class CasaAutorizarDialog extends StatefulWidget {
  const CasaAutorizarDialog({super.key, this.hoje});

  /// Dia de hoje em Lisboa (injetável nos testes).
  final DateTime? hoje;

  @override
  State<CasaAutorizarDialog> createState() => _CasaAutorizarDialogState();
}

class _CasaAutorizarDialogState extends State<CasaAutorizarDialog> {
  final _texto = TextEditingController();
  late final _data = TextEditingController(
      text: casaData(casaIsoData(widget.hoje ?? casaHojeLisboa())));

  @override
  void dispose() {
    _texto.dispose();
    _data.dispose();
    super.dispose();
  }

  ({bool ok, String? iso}) get _dataLida => casaLerValidade(_data.text);

  bool get _ok =>
      casaTemAutorizo(_texto.text) && _dataLida.ok && _dataLida.iso != null;

  void _registrar() {
    final iso = _dataLida.iso!;
    final dia = DateTime.utc(int.parse(iso.substring(0, 4)),
        int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)));
    Navigator.pop(context, casaTextoAutorizacao(_texto.text, dia));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar autorização do Danilo'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use só DEPOIS de o Danilo dizer "autorizo". Cole aqui o texto '
              'exato dele (por exemplo: "autorizo os preços da Casa e a '
              'comissão de 15%"). A partir daqui o servidor aceita pedidos '
              'reais de preço fixo e calcula a comissão.',
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: const ValueKey('casa-autorizo-texto'),
              controller: _texto,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Texto exato do Danilo',
                helperText: 'Tem de conter a palavra "autorizo"',
                errorText: _texto.text.isNotEmpty &&
                        !casaTemAutorizo(_texto.text)
                    ? 'Falta a palavra "autorizo"'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: const ValueKey('casa-autorizo-data'),
              controller: _data,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Data em que o Danilo disse (DD/MM/AAAA)',
                errorText: _dataLida.ok && _dataLida.iso != null
                    ? null
                    : 'Data inválida',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar')),
        FilledButton(
          key: const ValueKey('casa-autorizo-ok'),
          onPressed: _ok ? _registrar : null,
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
