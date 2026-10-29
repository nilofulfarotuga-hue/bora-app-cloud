import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/order_service_type.dart';
import '../services/fatura_nif_service.dart';
import '../utils/nif_pt.dart';

/// Estado da "fatura com NIF" do ecrã de pagamento (28/10/2026).
///
/// O NIF é SEMPRE opcional: o interruptor nasce DESLIGADO. Só nasce ligado
/// quando o cliente já tem um NIF guardado (`client_billing_get`) — e mesmo
/// assim pode desligar. Nada aqui chama o servidor para criar o pedido: quem
/// usa isto só lê [pedido] DEPOIS de o pedido ter id real.
class FaturaNifController extends ChangeNotifier {
  FaturaNifController() {
    // O erro "NIF inválido" tem de aparecer ao escrever, não só ao ligar.
    nif.addListener(notifyListeners);
  }

  final TextEditingController nif = TextEditingController();
  final TextEditingController nome = TextEditingController();

  bool _ligado = false;
  bool _mexido = false;

  /// O interruptor "Quero fatura com NIF".
  bool get ligado => _ligado;

  /// O cliente carregou no interruptor.
  void definirLigado(bool valor) {
    _mexido = true;
    if (_ligado == valor) return;
    _ligado = valor;
    notifyListeners();
  }

  /// O NIF guardado chegou: liga e preenche — mas só se o cliente ainda não
  /// mexeu no interruptor (nunca desfaz uma escolha dele).
  void aplicarPerfil(DadosFatura? perfil) {
    if (perfil == null || _mexido) return;
    _ligado = true;
    nif.text = soDigitosNif(perfil.nif);
    nome.text = perfil.nome ?? '';
    notifyListeners();
  }

  /// Lê o perfil guardado. Falhar (sem rede) nunca estraga o pagamento.
  Future<void> carregarPerfil(FaturaNifService servico) async {
    try {
      aplicarPerfil(await servico.lerPerfil());
    } catch (e) {
      debugPrint('[FaturaNif] perfil não lido: $e');
    }
  }

  String get nifLimpo => soDigitosNif(nif.text);
  bool get nifValido => nifPtValido(nifLimpo);

  String? get nomeLimpo {
    final t = nome.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Ligado com um NIF que não vale: o ecrã avisa antes de cobrar.
  bool get nifPorCorrigir => _ligado && !nifValido;

  /// O que se pede ao servidor depois de o pedido existir; `null` = sem fatura
  /// com NIF (interruptor desligado ou NIF por corrigir).
  DadosFatura? get pedido =>
      (_ligado && nifValido) ? DadosFatura(nif: nifLimpo, nome: nomeLimpo) : null;

  /// A frase de baixo do interruptor.
  static String textoExplicativo(OrderServiceType tipo, bool lojaParceira) {
    final eCompraDeLoja = tipo == OrderServiceType.restaurant ||
        tipo == OrderServiceType.storeShopping ||
        tipo == OrderServiceType.takeaway;
    if (!eCompraDeLoja) return 'A Bora fatura o serviço em seu nome.'.tr;
    return lojaParceira
        ? 'A loja fatura os produtos e a Bora o resto, as duas com o seu NIF.'.tr
        : 'A Bora fatura em seu nome; os produtos vão com o talão da loja.'.tr;
  }

  @override
  void dispose() {
    nif.removeListener(notifyListeners);
    nif.dispose();
    nome.dispose();
    super.dispose();
  }
}

/// "Quero fatura com NIF" — cartão do ecrã de pagamento.
class FaturaNifCard extends StatelessWidget {
  const FaturaNifCard({
    super.key,
    required this.controller,
    required this.serviceType,
    required this.lojaParceira,
  });

  final FaturaNifController controller;
  final OrderServiceType serviceType;
  final bool lojaParceira;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final texto = FaturaNifController.textoExplicativo(
            serviceType, lojaParceira);
        final noveDigitos = controller.nifLimpo.length == 9;
        final erro = controller.ligado && noveDigitos && !controller.nifValido
            ? 'NIF inválido. Confere os 9 dígitos.'.tr
            : null;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                key: const Key('fatura_nif_interruptor'),
                value: controller.ligado,
                onChanged: controller.definirLigado,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
                title: Text(
                  'Quero fatura com NIF'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  texto,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (controller.ligado) ...[
                const SizedBox(height: Spacing.xs),
                TextField(
                  key: const Key('fatura_nif_campo'),
                  controller: controller.nif,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: InputDecoration(
                    labelText: 'NIF'.tr,
                    errorText: erro,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('fatura_nif_nome'),
                  controller: controller.nome,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'Nome na fatura (opcional)'.tr,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }
}
