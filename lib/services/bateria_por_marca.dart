import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';

/// Pedido ÚNICO para tirar a Bora da poupança de bateria, explicado conforme a
/// marca do telemóvel (24/10/2026).
///
/// A cicatriz: o Valdemir (Samsung A23) ficou "ligado" de 20/10 03:01 em
/// diante sem mandar sinal — o telemóvel matou o serviço de fundo da Bora e
/// ele deixou de receber pedidos sem saber. O pedido genérico do Android
/// ("Não otimizar") não chega nas marcas que têm a sua própria lista de apps
/// adormecidas (Samsung, Xiaomi, Huawei, Oppo…): cada uma esconde o interruptor
/// num sítio diferente. Aqui diz-se à pessoa ONDE carregar, no telemóvel dela.
///
/// Só Android; uma vez por instalação; nunca bloqueia ficar online.

/// Marca a partir do `device_model` da bridge nativa ("samsung SM-A235F").
String marcaDoModelo(String? deviceModel) {
  final m = (deviceModel ?? '').trim().toLowerCase();
  if (m.isEmpty) return '';
  return m.split(RegExp(r'\s+')).first;
}

/// O passo a passo para a marca (PT-PT). Marca desconhecida → texto geral.
String instrucoesBateria(String marca) {
  switch (marca.toLowerCase()) {
    case 'samsung':
      return 'No teu Samsung:\n'
          '1. Definições › Bateria › Limites de utilização em segundo plano.\n'
          '2. Em "Apps que nunca são suspensas", adiciona a Bora.\n'
          '3. Confirma que a Bora NÃO está em "Apps suspensas" nem em '
          '"Apps em suspensão profunda".';
    case 'xiaomi':
    case 'redmi':
    case 'poco':
      return 'No teu Xiaomi:\n'
          '1. Definições › Apps › Gerir apps › Bora.\n'
          '2. Poupança de bateria › "Sem restrições".\n'
          '3. Liga também o "Arranque automático".';
    case 'huawei':
    case 'honor':
      return 'No teu Huawei/Honor:\n'
          '1. Definições › Bateria › Iniciar aplicações.\n'
          '2. Procura a Bora e desliga "Gerir automaticamente".\n'
          '3. Deixa ligados os três: arranque automático, arranque secundário '
          'e executar em segundo plano.';
    case 'oppo':
    case 'realme':
    case 'oneplus':
      return 'No teu telemóvel:\n'
          '1. Definições › Bateria › Mais definições › Otimizar uso da bateria.\n'
          '2. Escolhe a Bora › "Não otimizar".\n'
          '3. Em Definições › Apps › Bora › Utilização da bateria, liga '
          '"Permitir atividade em segundo plano".';
    case 'vivo':
      return 'No teu Vivo:\n'
          '1. Definições › Bateria › Consumo elevado em segundo plano.\n'
          '2. Liga a Bora.';
    default:
      return 'No teu telemóvel:\n'
          '1. Na janela a seguir, escolhe "Permitir" (ou "Não otimizar").\n'
          '2. Se o telemóvel tiver uma lista de "apps adormecidas" na bateria, '
          'tira a Bora de lá.';
  }
}

class BateriaPorMarca {
  BateriaPorMarca._();

  static const String _kPedido = 'bora_app.pediu_bateria_marca_v1';
  static const MethodChannel _bridge = MethodChannel('pt.boraapp.bora/native');

  /// Uma vez por instalação: se a Bora ainda está na poupança de bateria,
  /// explica onde carregar (pela marca) e abre o pedido do Android.
  static Future<void> pedirUmaVez(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kPedido) == true) return;
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await prefs.setBool(_kPedido, true);
        return;
      }
      String marca = '';
      try {
        final diag =
            await _bridge.invokeMethod<Map<dynamic, dynamic>>('getDeviceDiagnostics');
        marca = marcaDoModelo(diag?['device_model']?.toString());
      } catch (e) {
        debugPrint('[BateriaPorMarca] marca indisponível: $e');
      }
      await prefs.setBool(_kPedido, true);
      if (!context.mounted) return;
      final continuar = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ExplicacaoBateria(texto: instrucoesBateria(marca)),
          ) ??
          false;
      if (!continuar) return;
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e) {
      debugPrint('[BateriaPorMarca] pedirUmaVez: $e');
    }
  }
}

class _ExplicacaoBateria extends StatelessWidget {
  const _ExplicacaoBateria({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      icon: const Icon(Icons.battery_alert, color: AppColors.primary, size: 40),
      title: const Text(
        'Não deixes o telemóvel adormecer a Bora',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Text(
          'Se o telemóvel poupar bateria na Bora, deixas de receber pedidos '
          'sem dares por isso — mesmo com o botão ligado.\n\n$texto',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}
