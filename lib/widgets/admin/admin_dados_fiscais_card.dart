import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/dados_fiscais_parceiro.dart';
import '../../services/dados_fiscais_parceiro_service.dart';
import '../../utils/conformidade_mensagem.dart';
import '../legal_fields_section.dart' show LegalFieldsValidators;

/// O que o admin mudou nos dados fiscais (só os campos alterados; o resto vai
/// a null e o servidor deixa como está).
class AlteracaoDadosFiscais {
  const AlteracaoDadosFiscais({
    this.legalName,
    this.nif,
    this.address,
    this.iban,
    this.birthDateIso,
    this.autocertificadoEmIso,
    this.autocertVersao,
  });

  final String? legalName;
  final String? nif;
  final String? address;
  final String? iban;
  final String? birthDateIso;
  final String? autocertificadoEmIso;
  final String? autocertVersao;

  /// Os mesmos códigos que o servidor grava no histórico.
  List<String> get campos => [
        if (legalName != null) 'nome',
        if (nif != null) 'nif',
        if (address != null) 'morada',
        if (iban != null) 'iban',
        if (birthDateIso != null) 'data_nascimento',
        if (autocertificadoEmIso != null) 'autocertificacao',
      ];

  bool get vazia => campos.isEmpty;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _ddmmaaaa(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

bool _mesmoDia(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Compara o formulário do admin com o que o servidor tem. Devolve o erro
/// (PT-BR) ou a alteração a enviar — só com o que mudou. Função pura.
({String? erro, AlteracaoDadosFiscais? alteracao}) compararDadosFiscaisAdmin({
  required DadosFiscaisParceiro antes,
  required String nome,
  required String nif,
  required String morada,
  required String iban,
  DateTime? nascimento,
  DateTime? autocertData,
  required String autocertVersao,
  DateTime? agora,
}) {
  ({String? erro, AlteracaoDadosFiscais? alteracao}) falha(String m) =>
      (erro: m, alteracao: null);
  String apagar(String campo) =>
      'Não dá para apagar $campo por aqui (só corrigir).';

  final n = nome.trim();
  if (n.isEmpty && antes.legalName != null) return falha(apagar('o nome legal'));
  // Só se valida o que mudou: um valor antigo fora da regra não trava a
  // correção de outro campo.
  final f = LegalFieldsValidators.normalizeNif(nif);
  final mudouNif =
      f.isNotEmpty && f != LegalFieldsValidators.normalizeNif(antes.nif ?? '');
  if (f.isEmpty && antes.nif != null) return falha(apagar('o NIF'));
  if (mudouNif && !LegalFieldsValidators.isValidNif(f)) {
    return falha('NIF inválido — confira os 9 dígitos.');
  }
  final m = morada.trim();
  if (m.isEmpty && antes.address != null) return falha(apagar('a morada'));
  final ib = LegalFieldsValidators.normalizeIban(iban);
  final mudouIban = ib.isNotEmpty &&
      ib != LegalFieldsValidators.normalizeIban(antes.iban ?? '');
  if (ib.isEmpty && antes.iban != null) return falha(apagar('o IBAN'));
  if (mudouIban && !LegalFieldsValidators.isValidIban(ib)) {
    return falha('IBAN inválido — PT seguido de 23 dígitos.');
  }
  if (nascimento != null &&
      !_mesmoDia(nascimento, antes.birthDate) &&
      !LegalFieldsValidators.isAdult(nascimento, now: agora)) {
    return falha('A data de nascimento tem de ser de alguém com 18 anos ou mais.');
  }
  final hoje = agora ?? DateTime.now();
  final versao = autocertVersao.trim();
  final mudouData = !_mesmoDia(autocertData, antes.autocertificadoEm);
  final mudouVersao = versao != (antes.autocertVersao ?? '');
  if (autocertData == null && mudouVersao && versao.isNotEmpty) {
    return falha('Informe a data da autocertificação.');
  }
  if (autocertData != null &&
      autocertData.isAfter(hoje.add(const Duration(days: 1)))) {
    return falha('A data da autocertificação não pode ser no futuro.');
  }
  String? autocertIso;
  if (autocertData != null && (mudouData || mudouVersao)) {
    autocertIso = mudouData
        ? DateTime.utc(autocertData.year, autocertData.month, autocertData.day, 12)
            .toIso8601String()
        : antes.autocertificadoEm!.toUtc().toIso8601String();
  }
  return (
    erro: null,
    alteracao: AlteracaoDadosFiscais(
      legalName: (n.isNotEmpty && n != antes.legalName) ? n : null,
      nif: mudouNif ? f : null,
      address: (m.isNotEmpty && m != antes.address) ? m : null,
      iban: mudouIban ? ib : null,
      birthDateIso: (nascimento != null && !_mesmoDia(nascimento, antes.birthDate))
          ? _iso(nascimento)
          : null,
      autocertificadoEmIso: autocertIso,
      autocertVersao: autocertIso != null && versao.isNotEmpty ? versao : null,
    ),
  );
}

/// Lê os dados fiscais da loja (por defeito `parceiro_dados_fiscais`).
typedef CarregarDadosFiscaisAdmin = Future<DadosFiscaisParceiro> Function();

/// Grava a alteração (por defeito `admin_parceiro_atualizar_dados_fiscais`).
typedef GravarDadosFiscaisAdmin = Future<Map<String, dynamic>> Function(
    AlteracaoDadosFiscais alteracao, String motivo);

/// Painel admin (PT-BR) → ficha do parceiro → "Dados fiscais (DAC7)".
///
/// Missão boom-burger-2026-10-27, F3. Ver e corrigir nome legal, NIF, morada,
/// IBAN, data de nascimento e autocertificação (data e versão), com a lista
/// do que falta para a loja poder abrir ao público. O NIF e o IBAN só
/// aparecem neste cartão.
class AdminDadosFiscaisCard extends StatefulWidget {
  const AdminDadosFiscaisCard({
    super.key,
    required this.restaurantId,
    this.carregar,
    this.gravar,
  });

  final String restaurantId;

  /// Só para testes: substitui a leitura da base.
  @visibleForTesting
  final CarregarDadosFiscaisAdmin? carregar;

  /// Só para testes: substitui a gravação.
  @visibleForTesting
  final GravarDadosFiscaisAdmin? gravar;

  @override
  State<AdminDadosFiscaisCard> createState() => _AdminDadosFiscaisCardState();
}

class _AdminDadosFiscaisCardState extends State<AdminDadosFiscaisCard> {
  final _nome = TextEditingController();
  final _nif = TextEditingController();
  final _morada = TextEditingController();
  final _iban = TextEditingController();
  final _versao = TextEditingController();
  final _motivo = TextEditingController();
  DateTime? _nascimento;
  DateTime? _autocertData;
  DadosFiscaisParceiro? _dados;
  bool _carregando = true;
  bool _aSalvar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_nome, _nif, _morada, _iban, _versao, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    // Ao reler depois de salvar o formulário fica à vista (sem roda).
    setState(() {
      _carregando = _dados == null;
      _erro = null;
    });
    try {
      final d = await (widget.carregar?.call() ??
          DadosFiscaisParceiroService.ler(widget.restaurantId));
      if (!mounted) return;
      setState(() {
        _dados = d;
        _nome.text = d.legalName ?? '';
        _nif.text = d.nif ?? '';
        _morada.text = d.address ?? '';
        _iban.text = d.iban ?? '';
        _versao.text = d.autocertVersao ?? '';
        _nascimento = d.birthDate;
        _autocertData = d.autocertificadoEm?.toLocal();
        _carregando = false;
      });
    } catch (e) {
      debugPrint('[AdminDadosFiscais] leitura falhou: $e');
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível ler os dados fiscais.';
        _carregando = false;
      });
    }
  }

  void _msg(String texto, {Color? cor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: cor,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _escolherNascimento() async {
    final hoje = DateTime.now();
    final limite = DateTime(hoje.year - 18, hoje.month, hoje.day);
    final atual = _nascimento;
    final p = await showDatePicker(
      context: context,
      initialDate: (atual == null || atual.isAfter(limite))
          ? DateTime(hoje.year - 30)
          : atual,
      firstDate: DateTime(hoje.year - 100),
      lastDate: limite,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Data de nascimento',
    );
    if (p != null) setState(() => _nascimento = p);
  }

  Future<void> _escolherAutocert() async {
    final hoje = DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: _autocertData ?? hoje,
      firstDate: DateTime(2026),
      lastDate: hoje,
      helpText: 'Data da autocertificação',
    );
    if (p != null) setState(() => _autocertData = p);
  }

  Future<void> _salvar() async {
    final antes = _dados;
    if (antes == null || _aSalvar) return;
    final r = compararDadosFiscaisAdmin(
      antes: antes,
      nome: _nome.text,
      nif: _nif.text,
      morada: _morada.text,
      iban: _iban.text,
      nascimento: _nascimento,
      autocertData: _autocertData,
      autocertVersao: _versao.text,
    );
    if (r.erro != null) {
      _msg(r.erro!, cor: AppColors.error);
      return;
    }
    final alt = r.alteracao!;
    if (alt.vazia) {
      _msg('Nada mudou — não há o que salvar.');
      return;
    }
    final motivo = _motivo.text.trim();
    if (motivo.length < 3) {
      _msg('Escreva o motivo (ex.: "enviado por WhatsApp em 27/10").',
          cor: AppColors.error);
      return;
    }
    setState(() => _aSalvar = true);
    try {
      final res = await (widget.gravar?.call(alt, motivo) ??
          DadosFiscaisParceiroService.adminAtualizar(
            restaurantId: widget.restaurantId,
            legalName: alt.legalName,
            nif: alt.nif,
            address: alt.address,
            iban: alt.iban,
            birthDateIso: alt.birthDateIso,
            autocertificadoEmIso: alt.autocertificadoEmIso,
            autocertVersao: alt.autocertVersao,
            motivo: motivo,
          ));
      final falta = rotulosEmFalta(res['em_falta']);
      _motivo.clear();
      _msg(
        falta.isEmpty
            ? 'Dados fiscais salvos. Completos: a loja pode abrir ao público.'
            : 'Dados fiscais salvos. Ainda falta: ${falta.join(', ')}.',
        cor: AppColors.success,
      );
      await _carregar();
    } catch (e) {
      _msg(mensagemErroDadosFiscaisAdmin(e), cor: AppColors.error);
    } finally {
      if (mounted) setState(() => _aSalvar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.gavel, size: 20),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Dados fiscais (DAC7)',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ]),
            const SizedBox(height: Spacing.xs),
            const Text(
              'Exigidos para abrir a loja ao público (Lei 36/2023). '
              'Campo vazio no servidor = em falta.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            ..._conteudo(),
          ],
        ),
      ),
    );
  }

  List<Widget> _conteudo() {
    if (_carregando) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    final d = _dados;
    if (_erro != null || d == null) {
      return [
        Text(_erro ?? 'Sem dados.',
            style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: Spacing.sm),
        OutlinedButton.icon(
          onPressed: _carregar,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar de novo'),
        ),
      ];
    }
    final falta = d.rotulosEmFalta;
    return [
      if (falta.isEmpty)
        const Row(children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 18),
          SizedBox(width: Spacing.xs),
          Text('Dados fiscais completos',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.success)),
        ])
      else ...[
        const Text('Falta para abrir ao público:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            for (final f in falta)
              Chip(
                label: Text(f,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error)),
                backgroundColor: AppColors.error.withValues(alpha: 0.08),
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
      const SizedBox(height: Spacing.md),
      _campo(_nome, 'Nome legal'),
      _campo(_nif, 'NIF', teclado: TextInputType.number),
      _campo(_morada, 'Morada', linhas: 2),
      _campo(_iban, 'IBAN (PT + 23 dígitos)'),
      _data(
        rotulo: 'Data de nascimento',
        valor: _nascimento,
        ajuda: d.empresa
            ? 'Empresa (NIF começa por 5, 6, 7 ou 9): não é exigida.'
            : 'Exigida para pessoa singular.',
        onTap: _escolherNascimento,
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _data(
              rotulo: 'Autocertificação (data)',
              valor: _autocertData,
              ajuda: 'Dia em que a loja confirmou a declaração.',
              onTap: _escolherAutocert,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: _campo(_versao, 'Versão do texto')),
        ],
      ),
      _campo(_motivo, 'Motivo da alteração (obrigatório)'),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _aSalvar ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          icon: _aSalvar
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Salvar dados fiscais'),
        ),
      ),
    ];
  }

  Widget _campo(TextEditingController c, String rotulo,
          {TextInputType? teclado, int linhas = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          maxLines: linhas,
          enabled: !_aSalvar,
          decoration: InputDecoration(
            labelText: rotulo,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _data({
    required String rotulo,
    required DateTime? valor,
    required String ajuda,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: InkWell(
          onTap: _aSalvar ? null : onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: rotulo,
              helperText: ajuda,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            child: Text(valor == null ? '—' : _ddmmaaaa(valor)),
          ),
        ),
      );
}
