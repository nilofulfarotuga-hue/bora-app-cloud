import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../utils/telefone_internacional.dart';

/// Campo do telemóvel com o seletor de indicativo (28/11/2026, adendo do
/// Danilo: qualquer país, Portugal +351 por defeito). Valida pelo país
/// escolhido; quem o usa lê o número já em formato internacional com
/// [CampoTelefoneInternacionalState.internacional].
class CampoTelefoneInternacional extends StatefulWidget {
  const CampoTelefoneInternacional({
    super.key,
    required this.controller,
    this.inicial,
    this.campoKey,
    this.onChanged,
    this.helperText,
    this.enabled = true,
  });

  /// O texto do número (sem o indicativo, ou colado inteiro com `+`).
  final TextEditingController controller;

  /// O telefone já guardado, para escolher o país certo ao abrir.
  final String? inicial;

  /// Chave do campo de texto (os testes escrevem nele).
  final Key? campoKey;

  final VoidCallback? onChanged;
  final String? helperText;
  final bool enabled;

  @override
  State<CampoTelefoneInternacional> createState() =>
      CampoTelefoneInternacionalState();
}

class CampoTelefoneInternacionalState
    extends State<CampoTelefoneInternacional> {
  late PaisTelefone _pais;

  PaisTelefone get pais => _pais;

  /// O número em formato internacional, ou `null` se não for válido.
  String? get internacional =>
      telefoneInternacional(widget.controller.text, _pais.iso);

  @override
  void initState() {
    super.initState();
    final partes = separarTelefone(widget.inicial);
    _pais = partes.pais;
    if (widget.controller.text.trim().isEmpty ||
        widget.controller.text.trim() == (widget.inicial ?? '').trim()) {
      widget.controller.text = partes.nacional;
    }
  }

  Future<void> _escolherPais() async {
    final escolhido = await showModalBottomSheet<PaisTelefone>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Indicativo do país'.tr,
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final p in kPaisesTelefone)
                      ListTile(
                        key: ValueKey('pais_telefone_${p.iso.name}'),
                        leading: Text(p.bandeira,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(p.nome),
                        trailing: Text('+${p.indicativo}'),
                        selected: p.iso == _pais.iso,
                        onTap: () => Navigator.of(ctx).pop(p),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    setState(() => _pais = escolhido);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton(
            key: const Key('telefone_indicativo'),
            onPressed: widget.enabled ? _escolherPais : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text('${_pais.bandeira} +${_pais.indicativo}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: widget.campoKey,
            controller: widget.controller,
            enabled: widget.enabled,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            decoration: InputDecoration(
              labelText: 'Telemóvel'.tr,
              hintText: _pais.iso.name == 'PT' ? '912345678' : null,
              helperText: widget.helperText,
              helperMaxLines: 3,
            ),
            onChanged: (_) => widget.onChanged?.call(),
            validator: (v) => validarTelefone(v, _pais.iso)?.tr,
          ),
        ),
      ],
    );
  }
}
