import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/papeis_de_trabalho.dart';

/// A caixa "O que queres aceitar?" para quem acumula papéis.
///
/// Um interruptor por papel, independentes. O de condução escreve em
/// `drivers.work_mode` (que é o que o dispatch das corridas já lê); os de
/// limpeza e lavagem escrevem na preferência por papel, que as funções de
/// aviso consultam antes de enviar. Sem essa consulta o interruptor seria
/// decorativo — e já tivemos disso que chegue.
class CaixaDePapeis extends StatefulWidget {
  const CaixaDePapeis({super.key, required this.iniciais});

  final List<PapelDeTrabalho> iniciais;

  @override
  State<CaixaDePapeis> createState() => _CaixaDePapeisState();
}

class _CaixaDePapeisState extends State<CaixaDePapeis> {
  late List<PapelDeTrabalho> _papeis = List.of(widget.iniciais);
  String? _aGravar;

  Future<void> _mexer(PapelDeTrabalho p, bool ligar) async {
    if (!ligar && !podeDesligar(_papeis)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(avisoUltimoPapel)),
      );
      return;
    }
    setState(() => _aGravar = p.papel);
    final ok = await PapeisDeTrabalhoService.definir(p.papel, ligar);
    if (!mounted) return;
    setState(() {
      _aGravar = null;
      if (ok) {
        _papeis = _papeis
            .map((x) => x.papel == p.papel ? x.copyWith(aceita: ligar) : x)
            .toList();
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível guardar. Tente outra vez.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
              child: Text('O que queres aceitar?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Text(
                'Liga e desliga o que quiseres receber hoje. Fica guardado.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            for (final p in _papeis)
              SwitchListTile(
                value: p.aceita,
                activeThumbColor: AppColors.primary,
                title: Text(p.titulo),
                subtitle: Text(p.descricao),
                secondary: _aGravar == p.papel
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onChanged:
                    _aGravar == null ? (v) => _mexer(p, v) : null,
              ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }
}
