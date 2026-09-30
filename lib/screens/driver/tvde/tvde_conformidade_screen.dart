import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../services/tvde_conformidade_service.dart';
import '../../../utils/safe_image_picker.dart';
import '../../../widgets/tvde/tvde_horas_servico_card.dart';
import 'ficha_legal_form_screen.dart';

/// Conformidade TVDE do motorista (Lei 45/2018 na versão da Lei 59/2026).
///
/// Quatro secções: operador (com contrato escrito), motorista (carta B,
/// português, curso de atualização, foto do certificado), carro (registo do
/// veículo, foto, seguro) e horas declaradas noutras plataformas.
///
/// O número e a validade do certificado TVDE e da carta vivem na Ficha legal
/// — aqui só há um botão para lá, para não haver dois sítios a dizer o mesmo.
///
/// Cada secção grava com o SEU botão e o seu estado de envio local
/// (PADRAO_BORA §3.13): nunca um `busy` partilhado.
///
/// A app não bloqueia nada por conta própria. O servidor decide; este ecrã
/// só mostra o estado que o servidor devolve.
class TvdeConformidadeScreen extends StatefulWidget {
  const TvdeConformidadeScreen({super.key});

  @override
  State<TvdeConformidadeScreen> createState() => _TvdeConformidadeScreenState();
}

class _TvdeConformidadeScreenState extends State<TvdeConformidadeScreen> {
  final _svc = TvdeConformidadeService.instance;

  Map<String, dynamic>? _conf;
  List<Map<String, dynamic>> _operadores = const [];
  bool _carregando = true;
  String? _erroCarregar;

  // (a) Operador
  String? _operadorId;
  bool _aGravarOperador = false;
  bool _aEnviarContrato = false;

  // (b) Motorista
  DateTime? _cartaB;
  bool? _falaPortugues;
  DateTime? _curso;
  bool _aGravarMotorista = false;
  bool _aEnviarCert = false;

  // (c) Carro
  final _matricula = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _cor = TextEditingController();
  final _anoFabrico = TextEditingController();
  final _lugares = TextEditingController();
  final _registoImt = TextEditingController();
  final _seguradora = TextEditingController();
  final _apolice = TextEditingController();
  final _distico = TextEditingController();
  DateTime? _primeiraMatricula;
  DateTime? _registoImtValidade;
  DateTime? _seguroValidade;
  DateTime? _inspecao;
  bool _eletrico = false;
  bool _acidentesPessoais = false;
  bool _adaptado = false;
  String? _fotoCarroPath;
  String? _seguroPath;
  bool _aEnviarFotoCarro = false;
  bool _aEnviarSeguro = false;
  bool _aGravarCarro = false;

  // (d) Horas noutras plataformas
  final _horasOutras = TextEditingController();
  bool _aGravarHoras = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [
      _matricula, _marca, _modelo, _cor, _anoFabrico, _lugares, _registoImt,
      _seguradora, _apolice, _distico, _horasOutras,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Dados ─────────────────────────────────────────────────────────────────

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroCarregar = null;
    });
    try {
      final conf = await _svc.minhaConformidade();
      List<Map<String, dynamic>> ops = const [];
      try {
        ops = await _svc.operadoresAprovados();
      } catch (e) {
        debugPrint('[TvdeConformidadeScreen] operadores falhou: $e');
      }
      if (!mounted) return;
      setState(() {
        _operadores = ops;
        _aplicar(conf, preencherCarro: true);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroCarregar = 'Não foi possível carregar a tua conformidade.';
      });
    }
  }

  /// Aplica a resposta do servidor ao estado do ecrã.
  void _aplicar(Map<String, dynamic> conf, {bool preencherCarro = false}) {
    _conf = conf;
    final op = conf['operador'];
    _operadorId = op is Map ? op['id']?.toString() : _operadorId;
    _cartaB = _data(conf['carta_b_emitida_em']) ?? _cartaB;
    _falaPortugues = conf['fala_portugues'] is bool
        ? conf['fala_portugues'] as bool
        : _falaPortugues;
    _curso = _data(conf['curso_atualizacao_em']) ?? _curso;
    final h = conf['horas_outras_plataformas'];
    if (h is num && h > 0 && _horasOutras.text.isEmpty) {
      _horasOutras.text = TvdeHorasServicoCard.formatarHoras(h);
    }
    final v = conf['veiculo'];
    if (preencherCarro && v is Map) {
      String s(String k) => v[k]?.toString() ?? '';
      _matricula.text = s('matricula');
      _marca.text = s('marca');
      _modelo.text = s('modelo');
      _cor.text = s('cor');
      _anoFabrico.text = s('ano_fabrico');
      _lugares.text = s('lugares');
      _registoImt.text = s('registo_imt_numero');
      _seguradora.text = s('seguro_seguradora');
      _distico.text = s('distico_id');
      _primeiraMatricula = _data(v['primeira_matricula_em']);
      _registoImtValidade = _data(v['registo_imt_validade']);
      _seguroValidade = _data(v['seguro_validade']);
      _inspecao = _data(v['inspecao_proxima']);
      _eletrico = v['eletrico'] == true;
      _acidentesPessoais = v['seguro_acidentes_pessoais'] == true;
      _adaptado = v['adaptado_mobilidade_reduzida'] == true;
      _fotoCarroPath = v['foto_path']?.toString();
      _seguroPath = v['seguro_path']?.toString();
    }
  }

  static DateTime? _data(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  static String _mostrar(DateTime? d) => d == null
      ? 'Escolher data'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _erro(Object e) {
    final s = e.toString();
    if (s.contains('matricula_invalida')) return 'Matrícula inválida.';
    if (s.contains('horas_invalidas')) {
      return 'Indica um número de horas entre 0 e 24.';
    }
    if (s.contains('ficheiro_invalido')) {
      return 'Não foi possível guardar o ficheiro. Tenta outra vez.';
    }
    return mensagemErroConformidade(e);
  }

  void _msg(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Escolhe uma imagem e envia-a para o bucket privado `driver-documents`,
  /// em `<uid>/tvde/<tipo>_<timestamp>.<ext>` (a política exige a 1.ª pasta =
  /// uid). Devolve o caminho, ou null se o motorista desistiu.
  Future<String?> _enviarFicheiro(String tipo) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _msg('Sessão expirada. Entra outra vez.');
      return null;
    }
    final x = await SafeImagePicker.pickImage(
        source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (x == null) return null;
    final nome = x.name.toLowerCase();
    final ponto = nome.lastIndexOf('.');
    var ext = ponto >= 0 ? nome.substring(ponto + 1) : 'jpg';
    if (!const ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext)) ext = 'jpg';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    final bytes = await x.readAsBytes();
    final path = '$uid/tvde/${tipo}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await Supabase.instance.client.storage.from('driver-documents').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return path;
  }

  /// Regista o documento para o admin rever. Não falha o fluxo se der erro:
  /// o caminho já ficou gravado no perfil.
  Future<void> _registarParaRevisao(String tipo, String caminho,
      {DateTime? validade}) async {
    try {
      await _svc.registarDocumento(
          tipo: tipo, caminho: caminho, validade: validade);
    } catch (e) {
      debugPrint('[TvdeConformidadeScreen] registarDocumento($tipo) falhou: $e');
    }
  }

  // ── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _guardarMotorista(Map<String, dynamic> p,
      {required void Function(bool) marcar, String? ok}) async {
    setState(() => marcar(true));
    try {
      final conf = await _svc.guardarDadosMotorista(p);
      if (!mounted) return;
      setState(() => _aplicar(conf));
      if (ok != null) _msg(ok);
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => marcar(false));
    }
  }

  Future<void> _gravarOperador() async {
    final id = _operadorId;
    if (id == null) {
      _msg('Escolhe um operador da lista.');
      return;
    }
    await _guardarMotorista({'operador_id': id},
        marcar: (v) => _aGravarOperador = v, ok: 'Operador guardado.');
  }

  Future<void> _enviarContrato() async {
    setState(() => _aEnviarContrato = true);
    try {
      final path = await _enviarFicheiro('contrato_operador');
      if (path == null) return;
      final conf = await _svc.guardarDadosMotorista({'contrato_path': path});
      await _registarParaRevisao('contrato_operador', path);
      if (!mounted) return;
      setState(() => _aplicar(conf));
      _msg('Contrato enviado.');
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => _aEnviarContrato = false);
    }
  }

  Future<void> _gravarDadosMotorista() async {
    final p = <String, dynamic>{};
    if (_cartaB != null) p['carta_b_emitida_em'] = _iso(_cartaB!);
    if (_falaPortugues != null) p['fala_portugues'] = _falaPortugues;
    if (_curso != null) p['curso_atualizacao_em'] = _iso(_curso!);
    if (p.isEmpty) {
      _msg('Não há nada para guardar.');
      return;
    }
    await _guardarMotorista(p,
        marcar: (v) => _aGravarMotorista = v, ok: 'Dados guardados.');
  }

  Future<void> _enviarCertificado() async {
    setState(() => _aEnviarCert = true);
    try {
      final path = await _enviarFicheiro('certificado_tvde_imt');
      if (path == null) return;
      final conf = await _svc.guardarDadosMotorista({'cert_foto_path': path});
      await _registarParaRevisao('certificado_tvde_imt', path);
      if (!mounted) return;
      setState(() => _aplicar(conf));
      _msg('Foto do certificado enviada.');
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => _aEnviarCert = false);
    }
  }

  Future<void> _escolherFotoCarro() async {
    setState(() => _aEnviarFotoCarro = true);
    try {
      final path = await _enviarFicheiro('foto_veiculo');
      if (path != null && mounted) setState(() => _fotoCarroPath = path);
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => _aEnviarFotoCarro = false);
    }
  }

  Future<void> _escolherSeguro() async {
    setState(() => _aEnviarSeguro = true);
    try {
      final path = await _enviarFicheiro('seguro');
      if (path != null && mounted) setState(() => _seguroPath = path);
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => _aEnviarSeguro = false);
    }
  }

  Future<void> _gravarCarro() async {
    if (_matricula.text.trim().length < 6) {
      _msg('Indica a matrícula do carro.');
      return;
    }
    final lugares = int.tryParse(_lugares.text.trim());
    if (_lugares.text.trim().isNotEmpty &&
        (lugares == null || lugares < 1 || lugares > 9)) {
      _msg('Um carro TVDE tem no máximo 9 lugares.');
      return;
    }
    final seguroAnterior = (_conf?['veiculo'] is Map)
        ? (_conf!['veiculo'] as Map)['seguro_path']?.toString()
        : null;
    final p = <String, dynamic>{
      'matricula': _matricula.text.trim(),
      'marca': _marca.text.trim(),
      'modelo': _modelo.text.trim(),
      'cor': _cor.text.trim(),
      if (_anoFabrico.text.trim().isNotEmpty)
        'ano_fabrico': int.tryParse(_anoFabrico.text.trim()),
      if (lugares != null) 'lugares': lugares,
      if (_primeiraMatricula != null)
        'primeira_matricula_em': _iso(_primeiraMatricula!),
      'eletrico': _eletrico,
      if (_fotoCarroPath != null) 'foto_path': _fotoCarroPath,
      'registo_imt_numero': _registoImt.text.trim(),
      if (_registoImtValidade != null)
        'registo_imt_validade': _iso(_registoImtValidade!),
      'seguro_seguradora': _seguradora.text.trim(),
      if (_apolice.text.trim().isNotEmpty) 'seguro_apolice': _apolice.text.trim(),
      if (_seguroValidade != null) 'seguro_validade': _iso(_seguroValidade!),
      'seguro_acidentes_pessoais': _acidentesPessoais,
      if (_seguroPath != null) 'seguro_path': _seguroPath,
      if (_inspecao != null) 'inspecao_proxima': _iso(_inspecao!),
      'distico_id': _distico.text.trim(),
      'adaptado_mobilidade_reduzida': _adaptado,
    };
    setState(() => _aGravarCarro = true);
    try {
      final conf = await _svc.submeterVeiculo(p);
      final seguro = _seguroPath;
      if (seguro != null && seguro != seguroAnterior) {
        await _registarParaRevisao('seguro', seguro, validade: _seguroValidade);
      }
      if (!mounted) return;
      setState(() => _aplicar(conf));
      _msg('Carro enviado. Fica pendente até a Bora aprovar.');
    } catch (e) {
      _msg(_erro(e));
    } finally {
      if (mounted) setState(() => _aGravarCarro = false);
    }
  }

  Future<void> _gravarHoras() async {
    final h = num.tryParse(_horasOutras.text.trim().replaceAll(',', '.'));
    if (h == null || h < 0 || h > 24) {
      _msg('Indica um número de horas entre 0 e 24.');
      return;
    }
    await _guardarMotorista({'horas_outras_plataformas': h},
        marcar: (v) => _aGravarHoras = v, ok: 'Declaração guardada.');
  }

  Future<void> _abrirFichaLegal() async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FichaLegalFormScreen()));
    if (mounted) await _carregar();
  }

  Future<void> _escolherData(DateTime? atual, ValueChanged<DateTime> aplicar,
      {bool futuro = false}) async {
    final agora = DateTime.now();
    final primeira = DateTime(1950);
    final ultima = futuro ? DateTime(agora.year + 15) : agora;
    var inicial = atual ?? agora;
    if (inicial.isAfter(ultima)) inicial = ultima;
    if (inicial.isBefore(primeira)) inicial = primeira;
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primeira,
      lastDate: ultima,
    );
    if (d != null && mounted) setState(() => aplicar(d));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Conformidade TVDE'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erroCarregar != null
              ? _ErroCarregar(texto: _erroCarregar!, onTentar: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _estado(),
                      const SizedBox(height: 16),
                      _seccaoOperador(),
                      _seccaoMotorista(),
                      _seccaoCarro(),
                      _seccaoHoras(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _estado() {
    final conf = _conf ?? const <String, dynamic>{};
    final motivos = (conf['motivos'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final avisos = (conf['avisos'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final bloqueioEfetivo = conf['bloqueio_efetivo'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('O teu estado',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (motivos.isEmpty && avisos.isEmpty)
              const Row(children: [
                Icon(Icons.check_circle, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(child: Text('Está tudo em ordem.')),
              ]),
            if (motivos.isNotEmpty) ...[
              const Text('Impedimentos',
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w700)),
              for (final m in motivos)
                _linha(Icons.error_outline, AppColors.error,
                    _rotuloComValidade(m)),
            ],
            if (avisos.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Avisos',
                  style: TextStyle(
                      color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
              for (final a in avisos)
                _linha(Icons.warning_amber_rounded, const Color(0xFFD97706),
                    _rotuloAviso(a)),
            ],
            if (motivos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                bloqueioEfetivo
                    ? 'Com impedimentos não podes ficar online.'
                    : 'Estas verificações ainda não bloqueiam a tua conta '
                        '(a Bora está a preparar a licença IMT).',
                style: TextStyle(
                    color: bloqueioEfetivo
                        ? AppColors.error
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            TvdeHorasServicoCard.fromConformidade(conf),
          ],
        ),
      ),
    );
  }

  static String _rotuloComValidade(Map m) {
    final r = m['rotulo']?.toString() ?? m['codigo']?.toString() ?? '';
    final v = _data(m['validade']);
    return v == null ? r : '$r (${_mostrar(v)})';
  }

  static String _rotuloAviso(Map a) {
    final r = a['rotulo']?.toString() ?? a['codigo']?.toString() ?? '';
    final d = a['dias'];
    if (d is num) {
      return d <= 0
          ? '$r (caduca hoje)'
          : '$r (faltam ${d.round()} ${d.round() == 1 ? 'dia' : 'dias'})';
    }
    return r;
  }

  Widget _linha(IconData icone, Color cor, String texto) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 18, color: cor),
            const SizedBox(width: 6),
            Expanded(child: Text(texto)),
          ],
        ),
      );

  Widget _seccao(String titulo, IconData icone, List<Widget> filhos) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          leading: Icon(icone, color: AppColors.primary),
          title: Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: filhos,
        ),
      );

  Widget _botaoData(String rotulo, DateTime? valor, ValueChanged<DateTime> aplicar,
          {bool futuro = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
          icon: const Icon(Icons.event),
          label: Text('$rotulo: ${_mostrar(valor)}'),
          onPressed: () => _escolherData(valor, aplicar, futuro: futuro),
        ),
      );

  Widget _botaoAcao(String texto, bool aEnviar, VoidCallback onPressed,
          {IconData icone = Icons.save_outlined, bool destaque = true}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: destaque
            ? FilledButton.icon(
                onPressed: aEnviar ? null : onPressed,
                icon: aEnviar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(icone),
                label: Text(texto),
              )
            : OutlinedButton.icon(
                onPressed: aEnviar ? null : onPressed,
                icon: aEnviar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icone),
                label: Text(texto),
              ),
      );

  Widget _campo(TextEditingController c, String rotulo,
          {TextInputType? teclado, TextCapitalization cap = TextCapitalization.none}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          textCapitalization: cap,
          decoration: InputDecoration(
              labelText: rotulo, border: const OutlineInputBorder()),
        ),
      );

  Widget _seccaoOperador() {
    final conf = _conf ?? const <String, dynamic>{};
    final op = conf['operador'] is Map ? conf['operador'] as Map : null;
    final temContrato = conf['tem_contrato'] == true;
    final idsValidos = _operadores.map((o) => o['id']?.toString()).toSet();
    return _seccao('1. Operador', Icons.business_outlined, [
      const Text(
          'O operador TVDE é a empresa com licença do IMT com quem tens contrato.'),
      if (op != null) ...[
        const SizedBox(height: 8),
        Text('Atual: ${op['denominacao'] ?? '—'}'
            '${op['estado'] != null && op['estado'] != 'aprovado' ? ' (${op['estado']})' : ''}'),
      ],
      const SizedBox(height: 8),
      if (_operadores.isEmpty)
        Text('Ainda não há operadores aprovados no Bora.',
            style: TextStyle(color: AppColors.textSecondary))
      else ...[
        DropdownButtonFormField<String>(
          initialValue: idsValidos.contains(_operadorId) ? _operadorId : null,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Escolhe o teu operador',
              border: OutlineInputBorder()),
          items: [
            for (final o in _operadores)
              DropdownMenuItem(
                value: o['id']?.toString(),
                child: Text(o['denominacao']?.toString() ?? '—',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _operadorId = v),
        ),
        _botaoAcao('Guardar operador', _aGravarOperador, _gravarOperador),
      ],
      const SizedBox(height: 12),
      Text(temContrato
          ? 'Contrato escrito com o operador: enviado.'
          : 'Falta enviar o contrato escrito com o operador.'),
      _botaoAcao(
          temContrato ? 'Enviar novo contrato' : 'Enviar foto do contrato',
          _aEnviarContrato,
          _enviarContrato,
          icone: Icons.upload_file,
          destaque: false),
    ]);
  }

  Widget _seccaoMotorista() {
    final conf = _conf ?? const <String, dynamic>{};
    final temFoto = conf['tem_foto_cmtvde'] == true;
    final cartaB = _cartaB;
    final menosDe3Anos = cartaB != null &&
        DateTime.now()
            .isBefore(DateTime(cartaB.year + 3, cartaB.month, cartaB.day));
    return _seccao('2. Motorista', Icons.badge_outlined, [
      _botaoData('Carta B emitida em', _cartaB, (d) => _cartaB = d),
      if (menosDe3Anos)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _linha(Icons.warning_amber_rounded, const Color(0xFFD97706),
              'A lei pede carta B há pelo menos 3 anos para conduzir em TVDE.'),
        ),
      const SizedBox(height: 12),
      const Text('Falas português?'),
      Row(
        children: [
          ChoiceChip(
            label: const Text('Sim'),
            selected: _falaPortugues == true,
            onSelected: (_) => setState(() => _falaPortugues = true),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Não'),
            selected: _falaPortugues == false,
            onSelected: (_) => setState(() => _falaPortugues = false),
          ),
        ],
      ),
      _botaoData('Curso de atualização feito em', _curso, (d) => _curso = d),
      _botaoAcao('Guardar dados', _aGravarMotorista, _gravarDadosMotorista),
      const SizedBox(height: 12),
      Text(temFoto
          ? 'Foto do certificado de motorista TVDE: enviada.'
          : 'Falta a foto do certificado de motorista TVDE (IMT).'),
      _botaoAcao(
          temFoto ? 'Enviar nova foto do certificado' : 'Enviar foto do certificado',
          _aEnviarCert,
          _enviarCertificado,
          icone: Icons.photo_camera_outlined,
          destaque: false),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: _abrirFichaLegal,
        icon: const Icon(Icons.description_outlined),
        label: const Text(
            'Número e validade do certificado TVDE e da carta (Ficha legal)'),
      ),
    ]);
  }

  Widget _seccaoCarro() {
    final v = _conf?['veiculo'];
    final estado = v is Map ? v['estado']?.toString() : null;
    return _seccao('3. Carro', Icons.directions_car_outlined, [
      if (estado != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Estado do registo: $estado',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      _campo(_matricula, 'Matrícula', cap: TextCapitalization.characters),
      _campo(_marca, 'Marca', cap: TextCapitalization.words),
      _campo(_modelo, 'Modelo', cap: TextCapitalization.words),
      _campo(_cor, 'Cor', cap: TextCapitalization.sentences),
      _campo(_anoFabrico, 'Ano de fabrico', teclado: TextInputType.number),
      _botaoData('1.ª matrícula em', _primeiraMatricula,
          (d) => _primeiraMatricula = d),
      _campo(_lugares, 'Lugares (incluindo o condutor, máx. 9)',
          teclado: TextInputType.number),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Carro elétrico'),
        value: _eletrico,
        onChanged: (x) => setState(() => _eletrico = x),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Adaptado a mobilidade reduzida'),
        value: _adaptado,
        onChanged: (x) => setState(() => _adaptado = x),
      ),
      _campo(_registoImt, 'N.º de registo do veículo no IMT'),
      _botaoData('Registo IMT válido até', _registoImtValidade,
          (d) => _registoImtValidade = d,
          futuro: true),
      _campo(_distico, 'N.º do dístico TVDE'),
      _botaoData('Próxima inspeção', _inspecao, (d) => _inspecao = d,
          futuro: true),
      const SizedBox(height: 8),
      const Text('Seguro', style: TextStyle(fontWeight: FontWeight.w700)),
      _campo(_seguradora, 'Seguradora', cap: TextCapitalization.words),
      _campo(_apolice, 'N.º da apólice'),
      _botaoData('Seguro válido até', _seguroValidade,
          (d) => _seguroValidade = d,
          futuro: true),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Inclui seguro de acidentes pessoais'),
        value: _acidentesPessoais,
        onChanged: (x) => setState(() => _acidentesPessoais = x),
      ),
      _botaoAcao(
          _fotoCarroPath == null ? 'Foto do carro' : 'Foto do carro: escolhida ✓',
          _aEnviarFotoCarro,
          _escolherFotoCarro,
          icone: Icons.photo_camera_outlined,
          destaque: false),
      _botaoAcao(
          _seguroPath == null
              ? 'Foto do certificado do seguro'
              : 'Foto do seguro: escolhida ✓',
          _aEnviarSeguro,
          _escolherSeguro,
          icone: Icons.upload_file,
          destaque: false),
      _botaoAcao('Enviar carro para aprovação', _aGravarCarro, _gravarCarro,
          icone: Icons.send),
    ]);
  }

  Widget _seccaoHoras() {
    return _seccao('4. Horas noutras plataformas', Icons.schedule, [
      const Text(
          'A lei conta as horas de serviço em todas as plataformas. Declara '
          'quantas horas trabalhaste noutras apps nas últimas 24 horas.'),
      _campo(_horasOutras, 'Horas nas últimas 24 h',
          teclado: const TextInputType.numberWithOptions(decimal: true)),
      _botaoAcao('Guardar declaração', _aGravarHoras, _gravarHoras),
    ]);
  }
}

class _ErroCarregar extends StatelessWidget {
  const _ErroCarregar({required this.texto, required this.onTentar});
  final String texto;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onTentar, child: const Text('Tentar outra vez')),
          ],
        ),
      ),
    );
  }
}
