// lib/screens/client/checkin_premio_servico_screen.dart
//
// Prémio dos 30 dias (Bloco D, 21/10/2026): o cliente escolhe 2 horas de
// limpeza ou uma lavagem exterior do carro e marca. Não paga nada: a marcação
// nasce com o pagamento "prémio" e o prestador recebe o ganho normal no acerto.
// As regras da marcação (antecedência da limpeza, zona da lavagem) são as de
// sempre, ditas pelo servidor.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../stores/cart_store.dart';

class CheckinPremioServicoScreen extends StatefulWidget {
  const CheckinPremioServicoScreen({super.key, required this.vale, this.service});

  final CheckinVale vale;
  final CheckinPremiosService? service;

  @override
  State<CheckinPremioServicoScreen> createState() => _CheckinPremioServicoScreenState();
}

class _CheckinPremioServicoScreenState extends State<CheckinPremioServicoScreen> {
  String _opcao = 'limpeza';
  DateTime? _quando;
  bool _lavarAgora = true;
  bool _aEnviar = false;
  String? _erro;

  final _rua = TextEditingController();
  final _cidade = TextEditingController(text: 'Guarda');
  final _cp = TextEditingController();
  final _notas = TextEditingController();
  final _matricula = TextEditingController();
  final _carro = TextEditingController();
  final _cor = TextEditingController();
  final _tel = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.vale.opcao != null && widget.vale.opcoes.contains(widget.vale.opcao)) {
      _opcao = widget.vale.opcao!;
    } else if (widget.vale.opcoes.isNotEmpty) {
      _opcao = widget.vale.opcoes.first;
    }
    // A morada do último pedido serve de ponto de partida (editável).
    final cart = context.read<CartStore>();
    _rua.text = cart.dropoffStreet;
    if (cart.dropoffCity.isNotEmpty) _cidade.text = cart.dropoffCity;
    _cp.text = cart.dropoffPostalCode;
  }

  @override
  void dispose() {
    for (final c in [_rua, _cidade, _cp, _notas, _matricula, _carro, _cor, _tel]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherQuando() async {
    final agora = DateTime.now();
    final minimo = _opcao == 'limpeza' ? agora.add(const Duration(hours: 13)) : agora;
    final dia = await showDatePicker(
      context: context,
      initialDate: _quando ?? minimo,
      firstDate: DateTime(minimo.year, minimo.month, minimo.day),
      lastDate: agora.add(const Duration(days: 30)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_quando ?? DateTime(dia.year, dia.month, dia.day, 10)),
    );
    if (hora == null || !mounted) return;
    setState(() => _quando = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute));
  }

  Future<void> _enviar() async {
    if (_aEnviar) return;
    if (_rua.text.trim().isEmpty) {
      setState(() => _erro = 'Escreve a morada.'.tr);
      return;
    }
    final precisaHora = _opcao == 'limpeza' || !_lavarAgora;
    if (precisaHora && _quando == null) {
      setState(() => _erro = 'Escolhe o dia e a hora.'.tr);
      return;
    }
    setState(() {
      _aEnviar = true;
      _erro = null;
    });
    final s = widget.service ?? CheckinPremiosService.instance;
    final loc = context.read<CartStore>().deliveryLocation;
    try {
      if (_opcao == 'limpeza') {
        await s.marcarLimpeza(
          valeId: widget.vale.id,
          quando: _quando!,
          rua: _rua.text.trim(),
          cidade: _cidade.text.trim(),
          codigoPostal: _cp.text.trim(),
          lat: loc?.latitude,
          lng: loc?.longitude,
          notas: _notas.text.trim(),
        );
      } else {
        await s.marcarLavagem(
          valeId: widget.vale.id,
          matricula: _matricula.text.trim(),
          telefone: _tel.text.trim(),
          agora: _lavarAgora,
          quando: _quando,
          rua: _rua.text.trim(),
          cidade: _cidade.text.trim(),
          codigoPostal: _cp.text.trim(),
          lat: loc?.latitude,
          lng: loc?.longitude,
          carro: _carro.text.trim(),
          cor: _cor.text.trim(),
          notas: _notas.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_opcao == 'limpeza'
            ? 'Limpeza marcada. Vês o estado em Reservas.'.tr
            : 'Lavagem pedida. Vês o estado em Reservas.'.tr),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aEnviar = false;
        _erro = mensagemErroPremio(e);
      });
    }
  }

  String _dataHora(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final temLimpeza = widget.vale.opcoes.contains('limpeza');
    final temLavagem = widget.vale.opcoes.contains('lavagem');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('O teu prémio dos {0} dias'.trArgs([widget.vale.marco]))),
      body: ListView(
        key: const Key('premio_servico_form'),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Escolhe o teu prémio'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Não pagas nada por este serviço.'.tr, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (temLimpeza)
            _Opcao(
              key: const Key('opcao_limpeza'),
              escolhida: _opcao == 'limpeza',
              onTap: () => setState(() => _opcao = 'limpeza'),
              titulo: '2 horas de limpeza em casa'.tr,
              subtitulo: 'Marca-se com pelo menos 12 horas de antecedência.'.tr,
            ),
          if (temLavagem)
            _Opcao(
              key: const Key('opcao_lavagem'),
              escolhida: _opcao == 'lavagem',
              onTap: () => setState(() => _opcao = 'lavagem'),
              titulo: 'Lavagem exterior do carro'.tr,
              subtitulo: 'Só por fora (ducha exterior).'.tr,
            ),
          const Divider(height: 24),
          if (_opcao == 'lavagem') ...[
            TextField(controller: _matricula, decoration: InputDecoration(labelText: 'Matrícula'.tr)),
            TextField(controller: _carro, decoration: InputDecoration(labelText: 'Marca e modelo (opcional)'.tr)),
            TextField(controller: _cor, decoration: InputDecoration(labelText: 'Cor (opcional)'.tr)),
            TextField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Telemóvel'.tr),
            ),
            SwitchListTile(
              value: _lavarAgora,
              onChanged: (v) => setState(() => _lavarAgora = v),
              title: Text('Para agora'.tr),
            ),
          ],
          TextField(controller: _rua, decoration: InputDecoration(labelText: 'Morada'.tr)),
          TextField(controller: _cidade, decoration: InputDecoration(labelText: 'Cidade'.tr)),
          TextField(controller: _cp, decoration: InputDecoration(labelText: 'Código postal'.tr)),
          if (_opcao == 'limpeza' || !_lavarAgora) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('btn_quando'),
              onPressed: _escolherQuando,
              icon: const Icon(Icons.event, size: 18),
              label: Text(_quando == null ? 'Escolher dia e hora'.tr : _dataHora(_quando!)),
            ),
          ],
          TextField(controller: _notas, decoration: InputDecoration(labelText: 'Notas (opcional)'.tr)),
          if (_erro != null) ...[
            const SizedBox(height: 10),
            Text(_erro!, key: const Key('premio_servico_erro'), style: TextStyle(color: Colors.red.shade900)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('btn_marcar_premio'),
            onPressed: _aEnviar ? null : _enviar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_aEnviar ? 'A marcar…'.tr : 'Marcar o meu prémio'.tr),
          ),
        ],
      ),
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({
    super.key,
    required this.escolhida,
    required this.onTap,
    required this.titulo,
    required this.subtitulo,
  });

  final bool escolhida;
  final VoidCallback onTap;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: escolhida ? AppColors.primary : const Color(0xFFE5E7EB), width: escolhida ? 2 : 1),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          escolhida ? Icons.check_circle : Icons.circle_outlined,
          color: escolhida ? AppColors.primary : AppColors.textSubtle,
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitulo),
      ),
    );
  }
}
