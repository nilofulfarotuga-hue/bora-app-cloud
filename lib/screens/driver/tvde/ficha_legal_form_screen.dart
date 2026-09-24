import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/ficha_legal_service.dart';

/// Os dados que a lei pede ao motorista TVDE e que ainda não viviam na app:
/// certificado IMT, carta, dístico, inspeção, seguro e o operador (frota).
///
/// Matrícula, marca/modelo e cor já existiam na conta do motorista — este
/// formulário edita-os no mesmo sítio de sempre (o servidor escreve em
/// `drivers`), para não haver duas matrículas a dizer coisas diferentes.
///
/// Nada é obrigatório para gravar: grava-se o que houver, e o ecrã de
/// fiscalização mostra "por preencher" no que faltar.
class FichaLegalFormScreen extends StatefulWidget {
  const FichaLegalFormScreen({super.key});

  @override
  State<FichaLegalFormScreen> createState() => _FichaLegalFormScreenState();
}

class _FichaLegalFormScreenState extends State<FichaLegalFormScreen> {
  static const _textos = <String, String>{
    'tvde_cert_numero': 'N.º do certificado de motorista TVDE (IMT)',
    'carta_numero': 'N.º da carta de condução',
    'matricula': 'Matrícula',
    'marca_modelo': 'Marca e modelo',
    'cor': 'Cor',
    'veiculo_ano': 'Ano do veículo',
    'distico_numero': 'N.º do dístico TVDE (IMT)',
    'seguro_seguradora': 'Seguradora',
    'seguro_apolice': 'N.º da apólice',
    'operador_nome': 'Nome do operador (frota)',
    'operador_nif': 'NIF do operador',
    'operador_licenca': 'N.º de licença IMT do operador',
  };
  static const _datas = <String, String>{
    'tvde_cert_validade': 'Certificado TVDE válido até',
    'carta_validade': 'Carta válida até',
    'distico_validade': 'Dístico válido até',
    'inspecao_validade': 'Inspeção válida até',
    'seguro_validade': 'Seguro válido até',
  };

  final _ctl = <String, TextEditingController>{
    for (final k in _textos.keys) k: TextEditingController(),
  };
  final _valores = <String, String?>{};
  bool? _cobrePassageiros;
  bool _carregado = false;

  /// Só se grava o que a pessoa mudou, e só depois de ler o que já existia:
  /// gravar por cima sem ter lido apagava a matrícula de quem abriu o
  /// formulário sem rede.
  Map<String, dynamic>? _original;
  bool _aGravar = false;
  String? _erroNif;
  final _nifKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final m = await FichaLegalService.minhaFicha();
      if (!mounted) return;
      setState(() {
        for (final k in _textos.keys) {
          _ctl[k]!.text = m[k]?.toString() ?? '';
        }
        for (final k in _datas.keys) {
          _valores[k] = m[k]?.toString();
        }
        _cobrePassageiros = m['seguro_cobre_passageiros'] as bool?;
        _original = _atuais();
        _carregado = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregado = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem ligação — não deu para ler os teus dados.')));
    }
  }

  Future<void> _escolherData(String k) async {
    final atual = DateTime.tryParse(_valores[k] ?? '');
    final agora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: atual ?? agora,
      firstDate: DateTime(agora.year - 10),
      lastDate: DateTime(agora.year + 20),
      helpText: _datas[k],
    );
    if (d == null || !mounted) return;
    setState(() => _valores[k] =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  Future<void> _gravar() async {
    final nif = _ctl['operador_nif']!.text.replaceAll(RegExp(r'\s'), '');
    if (nif.isNotEmpty && !RegExp(r'^\d{9}$').hasMatch(nif)) {
      // Nunca voltar atrás em silêncio: diz o que falta e leva lá.
      setState(() => _erroNif = 'O NIF do operador tem 9 algarismos.');
      final ctx = _nifKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      return;
    }
    setState(() {
      _erroNif = null;
      _aGravar = true;
    });
    final campos = fichaCamposMudados(_original ?? const {}, _atuais());
    if (campos.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await FichaLegalService.guardar(campos);
      messenger.showSnackBar(
          const SnackBar(content: Text('Ficha legal guardada.')));
      nav.maybePop();
    } catch (e) {
      final nifErr = e.toString().contains('nif_operador_invalido');
      messenger.showSnackBar(SnackBar(
          content: Text(nifErr
              ? 'O NIF do operador tem 9 algarismos.'
              : 'Não foi possível guardar. Verifica a ligação e tenta de novo.')));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  Map<String, dynamic> _atuais() => <String, dynamic>{
        for (final k in _textos.keys) k: _ctl[k]!.text.trim(),
        for (final k in _datas.keys) k: _valores[k] ?? '',
        if (_cobrePassageiros != null)
          'seguro_cobre_passageiros': _cobrePassageiros,
      };

  Widget _campo(String k, {TextInputType? teclado, Key? key, String? erro}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctl[k],
        keyboardType: teclado,
        textCapitalization: k == 'matricula'
            ? TextCapitalization.characters
            : TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: _textos[k],
          errorText: erro,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _data(String k) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _escolherData(k),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: _datas[k],
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(FichaTexto.data(_valores[k])),
        ),
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha legal do motorista'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: !_carregado
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_original == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                        'Sem ligação: não deu para ler os teus dados, por isso não é possível gravar agora. Volta a abrir com rede.',
                        style: TextStyle(color: AppColors.error)),
                  ),
                const Text(
                  'Estes dados aparecem no ecrã "Mostrar à autoridade". Recebes um aviso 30 dias antes de cada documento expirar; com um documento expirado não consegues ficar online.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                _titulo('Motorista'),
                _campo('tvde_cert_numero'),
                _data('tvde_cert_validade'),
                _campo('carta_numero'),
                _data('carta_validade'),
                _titulo('Veículo'),
                _campo('matricula'),
                _campo('marca_modelo'),
                _campo('cor'),
                _campo('veiculo_ano', teclado: TextInputType.number),
                _campo('distico_numero'),
                _data('distico_validade'),
                _data('inspecao_validade'),
                _titulo('Seguro'),
                _campo('seguro_seguradora'),
                _campo('seguro_apolice'),
                _data('seguro_validade'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('O seguro cobre os passageiros'),
                  value: _cobrePassageiros ?? false,
                  onChanged: (v) => setState(() => _cobrePassageiros = v),
                ),
                _titulo('Operador TVDE (só se trabalhas por uma frota)'),
                _campo('operador_nome'),
                _campo('operador_nif',
                    teclado: TextInputType.number, key: _nifKey, erro: _erroNif),
                _campo('operador_licenca'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: (_aGravar || _original == null) ? null : _gravar,
                    child: _aGravar
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Só as chaves cujo valor mudou em relação ao que o servidor devolveu.
/// Um campo esvaziado de propósito conta como mudança (o servidor apaga-o).
Map<String, dynamic> fichaCamposMudados(
    Map<String, dynamic> original, Map<String, dynamic> atual) {
  final out = <String, dynamic>{};
  atual.forEach((k, v) {
    final antes = original[k];
    final a = antes == null ? '' : antes.toString();
    final d = v == null ? '' : v.toString();
    if (a != d) out[k] = v;
  });
  return out;
}
