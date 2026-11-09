import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/driver/minha_conta_screen.dart';
import '../services/minha_conta.dart';
import '../services/minha_conta_service.dart';

/// A BARRA FINA do mapa ocioso: "Falta: NIF, IBAN e dívida 1,47 €". Toque abre
/// "A minha conta". Sem nada em falta (ou sem resposta do servidor), não
/// aparece. Missão m2 (08/11/2026): o que falta à conta deixa de aparecer em
/// cartões quando toca uma oferta — vive aqui e no ecrã próprio.
///
/// Só se põe em ecrãs SEM oferta e SEM pedido em curso (o mapa ocioso do
/// estafeta e o mapa do motorista sem oferta por cima).
class BarraFaltaConta extends StatefulWidget {
  const BarraFaltaConta({super.key, this.margem, this.carregar});

  final EdgeInsetsGeometry? margem;

  /// Só para testes: troca o servidor.
  final Future<EstadoMinhaConta?> Function()? carregar;

  @override
  State<BarraFaltaConta> createState() => _BarraFaltaContaState();
}

class _BarraFaltaContaState extends State<BarraFaltaConta> {
  EstadoMinhaConta? _estado;

  @override
  void initState() {
    super.initState();
    MinhaContaService.versao.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    MinhaContaService.versao.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final e =
        await (widget.carregar?.call() ?? MinhaContaService.carregar());
    if (!mounted) return;
    setState(() => _estado = e);
  }

  Future<void> _abrir() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MinhaContaScreen()));
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final texto = _estado?.resumoBarra;
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.margem ?? EdgeInsets.zero,
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        elevation: 1,
        child: InkWell(
          key: const Key('barra_falta_conta'),
          borderRadius: BorderRadius.circular(10),
          onTap: _abrir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.error, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    texto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A folha do botão Online quando falta algo que impede de ficar online
/// (fiscal fora de prazo, conta por aprovar, bloqueio por dívida). Cada item
/// tem um botão que abre "A minha conta" nesse item.
Future<void> mostrarFolhaParaFicarOnline(
    BuildContext context, List<ItemConta> bloqueantes) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          key: const Key('folha_ficar_online'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para ficares online falta:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final item in bloqueantes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.rotulo,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (item.chave != 'aprovacao')
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  MinhaContaScreen(focar: item.chave)));
                        },
                        child: const Text('Tratar'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Depois de tratares, carrega outra vez em Online.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Depois de ficar online: se ainda falta alguma coisa que não impede
/// (recibo verde, IBAN, comprovativo…), diz-se numa linha com "Ver".
/// Pedido do Danilo: "quando a pessoa for ficar online, tem que falar: tá
/// faltando o recibo verde".
void avisarFaltasAoFicarOnline(BuildContext context, EstadoMinhaConta? conta) {
  final f = conta?.emFalta ?? const <ItemConta>[];
  if (f.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 8),
    content: Text(
        'Estás online. Ainda falta: ${juntarComVirgulas(f.map((i) => i.rotuloCurto).toList())}.'),
    action: SnackBarAction(
      label: 'Ver',
      onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MinhaContaScreen())),
    ),
  ));
}
