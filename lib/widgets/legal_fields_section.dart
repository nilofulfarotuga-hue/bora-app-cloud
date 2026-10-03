import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/legal_fields_service.dart';

/// D3 (ronda-fecho-2026-09-22) — DSA art. 30 + DAC7.
///
/// Secção de formulário reutilizável com os dados legais e fiscais que TODO o
/// prestador (estafeta, parceiro, faxineira, lavador, salão) tem de dar antes
/// de ser ativado: nome como no documento, NIF, morada completa, IBAN, data de
/// nascimento e a autocertificação do DSA art. 30 n.º 1 e). O servidor
/// (`provider_update_legal_fields` + `fn_conformidade_antes_de_ativar`)
/// recusa o "aprovar" enquanto faltar um destes — por isso o formulário
/// obriga a todos, sem exceção.
///
/// Regra PADRAO_BORA §1.2 (cicatriz 27/08: botão que falhava calado): quando
/// a validação falha, rola-se até ao primeiro campo em falta, realça-se e
/// diz-se em palavras o que falta. [LegalFieldsController.validateAndReveal]
/// faz as três coisas e devolve o rótulo para a SnackBar `Falta: …`.
///
/// A secção tem o seu próprio `Form` interior: os ecrãs que já têm um `Form`
/// à volta (os Steppers) continuam a validar os campos deles sem que os
/// campos legais os bloqueiem a meio do fluxo (ex.: criar a conta no passo 2
/// do estafeta antes de chegar aos dados fiscais no passo 4).

/// Texto da autocertificação (DSA art. 30 n.º 1 e) + DAC7). Não se altera
/// sem mudar também `dsa_self_cert_version` no servidor.
const String kDsaSelfCertificationText =
    'Declaro que os dados acima são verdadeiros e atuais, que exerço esta '
    'atividade por conta própria e que só forneço bens ou serviços conformes '
    'com a lei da União Europeia e portuguesa. Autorizo a Bora a comunicar os '
    'meus rendimentos na plataforma à Autoridade Tributária quando a lei o '
    'exigir (DAC7).';

/// Os seis campos, pela ordem em que aparecem no ecrã (e pela ordem em que
/// se reporta o que falta).
enum LegalField { legalName, nif, address, iban, birthDate, selfCertify }

/// Validadores puros (sem UI) — provados em
/// `test/legal_fields_section_test.dart`. As mesmas regras que o servidor
/// aplica em `_conformidade_em_falta` e em `provider_update_legal_fields`.
class LegalFieldsValidators {
  LegalFieldsValidators._();

  /// Só dígitos (o servidor faz o mesmo `regexp_replace`).
  static String normalizeNif(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// Sem espaços e em maiúsculas (o servidor faz o mesmo).
  static String normalizeIban(String raw) =>
      raw.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// NIF português: 9 dígitos + dígito de controlo (mod 11) — o mesmo cálculo
  /// de `validateNif` em `supabase/functions/register-partner/index.ts`.
  ///
  /// Rejeita ainda os números de recurso que toda a gente escreve para
  /// despachar o campo (111111111, 123456789…): passam no mod 11 mas não
  /// identificam ninguém, e um registo DAC7 com esse NIF não serve para nada.
  static bool isValidNif(String raw) {
    final nif = normalizeNif(raw);
    if (nif.length != 9) return false;
    if (_placeholderNifs.contains(nif)) return false;
    final digits = nif.codeUnits.map((c) => c - 0x30).toList();
    var sum = 0;
    for (var i = 0; i < 8; i++) {
      sum += digits[i] * (9 - i);
    }
    final check = (11 - (sum % 11)) % 11;
    return check == 10 ? digits[8] == 0 : digits[8] == check;
  }

  static final Set<String> _placeholderNifs = {
    '123456789',
    for (var d = 0; d <= 9; d++) '$d' * 9,
  };

  /// IBAN português: `PT` + 23 dígitos (2 de controlo + NIB de 21).
  static bool isValidIban(String raw) =>
      RegExp(r'^PT\d{23}$').hasMatch(normalizeIban(raw));

  /// Maior de idade no dia de hoje (ou em [now], para os testes).
  static bool isAdult(DateTime birthDate, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final limit = DateTime(today.year - 18, today.month, today.day);
    final d = DateTime(birthDate.year, birthDate.month, birthDate.day);
    return !d.isAfter(limit);
  }

  static String? legalName(String? v) => (v ?? '').trim().length < 3
      ? 'Indica o nome completo, como está no documento.'
      : null;

  static String? nif(String? v) {
    if (normalizeNif(v ?? '').isEmpty) return 'Indica o NIF.';
    if (!isValidNif(v!)) return 'NIF inválido — confirma os 9 dígitos.';
    return null;
  }

  static String? address(String? v) => (v ?? '').trim().length < 5
      ? 'Indica a morada completa (rua, n.º, código postal, localidade).'
      : null;

  static String? iban(String? v) {
    if (normalizeIban(v ?? '').isEmpty) return 'Indica o IBAN.';
    if (!isValidIban(v!)) return 'IBAN inválido — PT seguido de 23 dígitos.';
    return null;
  }

  static String? birthDate(DateTime? d, {DateTime? now}) {
    if (d == null) return 'Indica a data de nascimento.';
    if (!isAdult(d, now: now)) return 'Tens de ter pelo menos 18 anos.';
    return null;
  }

  static String? selfCertify(bool? v) =>
      v == true ? null : 'Tens de confirmar a declaração para continuar.';
}

/// Estado dos seis campos + a lógica de "o que falta". Os ecrãs que já têm
/// controladores para NIF/IBAN/morada (rascunho guardado, resumo, RPC
/// antiga) passam-nos aqui para não haver dois campos com a mesma verdade;
/// o que não é passado é criado e descartado por este controlador.
class LegalFieldsController {
  LegalFieldsController({
    TextEditingController? legalName,
    TextEditingController? nif,
    TextEditingController? address,
    TextEditingController? iban,
    DateTime? birthDate,
  })  : legalName = legalName ?? TextEditingController(),
        nif = nif ?? TextEditingController(),
        address = address ?? TextEditingController(),
        iban = iban ?? TextEditingController(),
        birthDate = ValueNotifier<DateTime?>(birthDate),
        _owned = [
          if (legalName == null) 'legalName',
          if (nif == null) 'nif',
          if (address == null) 'address',
          if (iban == null) 'iban',
        ];

  final TextEditingController legalName;
  final TextEditingController nif;
  final TextEditingController address;
  final TextEditingController iban;
  final ValueNotifier<DateTime?> birthDate;
  final ValueNotifier<bool> selfCertified = ValueNotifier<bool>(false);
  final List<String> _owned;

  /// `Form` interior da secção — validar por aqui mostra os erros inline.
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  /// Uma chave por campo, para rolar até ele ([Scrollable.ensureVisible]).
  final Map<LegalField, GlobalKey> fieldKeys = {
    for (final f in LegalField.values) f: GlobalKey(),
  };

  /// Foco dos campos de texto (o de data é só de leitura; a declaração não
  /// tem foco de teclado).
  final Map<LegalField, FocusNode> focusNodes = {
    LegalField.legalName: FocusNode(),
    LegalField.nif: FocusNode(),
    LegalField.address: FocusNode(),
    LegalField.iban: FocusNode(),
    LegalField.birthDate: FocusNode(),
  };

  /// Rótulo curto para a SnackBar `Falta: <rótulo>`.
  static String labelOf(LegalField f) => switch (f) {
        LegalField.legalName => 'nome completo (como no documento)',
        LegalField.nif => 'NIF válido (9 dígitos)',
        LegalField.address => 'morada completa',
        LegalField.iban => 'IBAN válido (PT + 23 dígitos)',
        LegalField.birthDate => 'data de nascimento (mínimo 18 anos)',
        LegalField.selfCertify => 'confirmar a declaração de veracidade',
      };

  /// Mensagem de erro do campo, ou null se está bom.
  String? errorOf(LegalField f, {DateTime? now}) => switch (f) {
        LegalField.legalName => LegalFieldsValidators.legalName(legalName.text),
        LegalField.nif => LegalFieldsValidators.nif(nif.text),
        LegalField.address => LegalFieldsValidators.address(address.text),
        LegalField.iban => LegalFieldsValidators.iban(iban.text),
        LegalField.birthDate =>
          LegalFieldsValidators.birthDate(birthDate.value, now: now),
        LegalField.selfCertify =>
          LegalFieldsValidators.selfCertify(selfCertified.value),
      };

  /// O primeiro campo em falta, pela ordem do ecrã — ou null se está tudo.
  LegalField? firstMissingField({DateTime? now}) {
    for (final f in LegalField.values) {
      if (errorOf(f, now: now) != null) return f;
    }
    return null;
  }

  /// Rótulo do primeiro campo em falta (para `Falta: …`), ou null.
  String? firstMissingLabel({DateTime? now}) {
    final f = firstMissingField(now: now);
    return f == null ? null : labelOf(f);
  }

  bool get isComplete => firstMissingField() == null;

  /// Valida (mostra os erros inline), rola até ao primeiro campo em falta,
  /// dá-lhe o foco e devolve o rótulo do que falta — null quando está tudo.
  /// É isto que o botão de submeter chama antes de qualquer pedido à rede.
  Future<String?> validateAndReveal() async {
    formKey.currentState?.validate();
    final f = firstMissingField();
    if (f == null) return null;
    final ctx = fieldKeys[f]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 300),
      );
    }
    focusNodes[f]?.requestFocus();
    return labelOf(f);
  }

  /// `yyyy-MM-dd` para o parâmetro `date` da RPC.
  String? get birthDateIso {
    final d = birthDate.value;
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Grava no servidor (`provider_update_legal_fields`) para o papel dado.
  /// Lança [LegalFieldsException] com mensagem PT-PT quando não grava.
  Future<Map<String, dynamic>> save(String role) {
    final d = birthDate.value;
    if (d == null) {
      throw const LegalFieldsException('Indica a data de nascimento.',
          code: 'data_nascimento');
    }
    return LegalFieldsService.saveLegalFields(
      role: role,
      legalName: legalName.text,
      nif: nif.text,
      address: address.text,
      iban: iban.text,
      birthDate: d,
      selfCertify: selfCertified.value,
    );
  }

  void dispose() {
    if (_owned.contains('legalName')) legalName.dispose();
    if (_owned.contains('nif')) nif.dispose();
    if (_owned.contains('address')) address.dispose();
    if (_owned.contains('iban')) iban.dispose();
    birthDate.dispose();
    selfCertified.dispose();
    for (final n in focusNodes.values) {
      n.dispose();
    }
  }
}

/// A secção em si. Todos os campos são obrigatórios.
class LegalFieldsSection extends StatefulWidget {
  const LegalFieldsSection({
    super.key,
    required this.controller,
    this.legalNameLabel = 'Nome completo (como no documento)',
    this.showAddress = true,
    this.enabled = true,
    this.onChanged,
  });

  final LegalFieldsController controller;

  /// O parceiro chama-lhe "Nome completo do responsável (como no documento)".
  final String legalNameLabel;

  /// Falso quando a morada já é pedida noutro sítio do mesmo ecrã (o
  /// parceiro dá a morada do estabelecimento no passo 1 — é essa que a lei
  /// quer e é essa que o servidor grava em `restaurants.address`). O
  /// controlador continua a validar o texto; só não há segundo campo.
  final bool showAddress;

  final bool enabled;

  /// Chamado a cada alteração (os ecrãs com rascunho gravam aqui).
  final VoidCallback? onChanged;

  @override
  State<LegalFieldsSection> createState() => _LegalFieldsSectionState();
}

class _LegalFieldsSectionState extends State<LegalFieldsSection> {
  final _birthTextCtrl = TextEditingController();

  LegalFieldsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncBirthText();
    _c.birthDate.addListener(_syncBirthText);
    _c.selfCertified.addListener(_onNotifier);
  }

  @override
  void didUpdateWidget(covariant LegalFieldsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.birthDate.removeListener(_syncBirthText);
      oldWidget.controller.selfCertified.removeListener(_onNotifier);
      _c.birthDate.addListener(_syncBirthText);
      _c.selfCertified.addListener(_onNotifier);
      _syncBirthText();
    }
  }

  @override
  void dispose() {
    _c.birthDate.removeListener(_syncBirthText);
    _c.selfCertified.removeListener(_onNotifier);
    _birthTextCtrl.dispose();
    super.dispose();
  }

  void _onNotifier() {
    if (mounted) setState(() {});
  }

  void _syncBirthText() {
    final d = _c.birthDate.value;
    _birthTextCtrl.text = d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
    if (mounted) setState(() {});
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final last = DateTime(now.year - 18, now.month, now.day);
    final current = _c.birthDate.value;
    final initial = (current == null || current.isAfter(last))
        ? DateTime(now.year - 30, now.month, now.day)
        : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100, 1, 1),
      lastDate: last,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Data de nascimento',
      fieldLabelText: 'Data de nascimento',
      errorInvalidText: 'Tens de ter pelo menos 18 anos.',
    );
    if (picked == null) return;
    _c.birthDate.value = picked;
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Form(
      key: _c.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  color: AppColors.primary, size: 20),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Dados legais e fiscais (obrigatórios)',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          const Text(
            'A lei europeia (DSA, art. 30) e a DAC7 obrigam a Bora a recolher '
            'e confirmar estes dados antes de ativar a tua conta.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: _c.fieldKeys[LegalField.legalName],
            controller: _c.legalName,
            focusNode: _c.focusNodes[LegalField.legalName],
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => widget.onChanged?.call(),
            decoration: InputDecoration(
              labelText: '${widget.legalNameLabel} *',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            validator: LegalFieldsValidators.legalName,
          ),
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: _c.fieldKeys[LegalField.nif],
            controller: _c.nif,
            focusNode: _c.focusNodes[LegalField.nif],
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => widget.onChanged?.call(),
            decoration: const InputDecoration(
              labelText: 'NIF *',
              hintText: '9 dígitos',
              prefixIcon: Icon(Icons.numbers),
            ),
            validator: LegalFieldsValidators.nif,
          ),
          if (widget.showAddress) ...[
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: _c.fieldKeys[LegalField.address],
              controller: _c.address,
              focusNode: _c.focusNodes[LegalField.address],
              enabled: enabled,
              keyboardType: TextInputType.streetAddress,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLines: 2,
              onChanged: (_) => widget.onChanged?.call(),
              decoration: const InputDecoration(
                labelText:
                    'Morada completa (rua, n.º, código postal, localidade) *',
                prefixIcon: Icon(Icons.home_outlined),
              ),
              validator: LegalFieldsValidators.address,
            ),
          ],
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: _c.fieldKeys[LegalField.iban],
            controller: _c.iban,
            focusNode: _c.focusNodes[LegalField.iban],
            enabled: enabled,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
            ],
            onChanged: (_) => widget.onChanged?.call(),
            decoration: const InputDecoration(
              labelText: 'IBAN (PT + 23 dígitos) *',
              hintText: 'PT50 0000 0000 0000 0000 0000 0',
              helperText: 'Para receberes os teus pagamentos.',
              prefixIcon: Icon(Icons.account_balance_outlined),
            ),
            validator: LegalFieldsValidators.iban,
          ),
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: _c.fieldKeys[LegalField.birthDate],
            controller: _birthTextCtrl,
            focusNode: _c.focusNodes[LegalField.birthDate],
            enabled: enabled,
            readOnly: true,
            onTap: enabled ? _pickBirthDate : null,
            decoration: const InputDecoration(
              labelText: 'Data de nascimento *',
              hintText: 'dd/mm/aaaa',
              prefixIcon: Icon(Icons.cake_outlined),
              suffixIcon: Icon(Icons.calendar_month_outlined),
            ),
            validator: (_) =>
                LegalFieldsValidators.birthDate(_c.birthDate.value),
          ),
          const SizedBox(height: Spacing.md),
          FormField<bool>(
            key: _c.fieldKeys[LegalField.selfCertify],
            initialValue: _c.selfCertified.value,
            validator: (_) =>
                LegalFieldsValidators.selfCertify(_c.selfCertified.value),
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: _c.selfCertified.value,
                  onChanged: enabled
                      ? (v) {
                          _c.selfCertified.value = v ?? false;
                          state.didChange(v);
                          widget.onChanged?.call();
                        }
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.primary,
                  title: const Text(
                    kDsaSelfCertificationText,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textPrimary),
                  ),
                ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(left: Spacing.md),
                    child: Text(
                      state.errorText!,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
