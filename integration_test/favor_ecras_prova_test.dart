// PROVA VISUAL do Favor no estafeta e dos botões do fundo no Android 15
// (08/10/2026, pedido real 74dd4ecc). Sem login e sem dados reais: monta os
// widgets novos com um Favor de exemplo (receita INVENTADA) e pára em cada
// ecrã alguns segundos para o PC tirar a captura por adb — a captura do
// sistema traz a barra de navegação de 3 botões / gestos POR CIMA da app,
// que é o que se quer provar (o `takeScreenshot` do Flutter não a traz).
//
// Cada paragem anuncia-se no log: "[prova] PRONTO <nome>". O guião do PC
// (`.claude/.ai/provas/favor-farmacia-2026-10-08/capturar.ps1`) espera pela
// linha e fotografa.
//
// Corre-se como app normal (sem flutter drive):
//   flutter build apk --debug --target=integration_test/favor_ecras_prova_test.dart
//   adb install -r … ; adb shell am start -n pt.boraapp.bora/.MainActivity
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/order_store.dart';
import 'package:bora_app/widgets/bora_foto_ecra_inteiro.dart';
import 'package:bora_app/widgets/errand_execution_sheet_compat.dart';
import 'package:bora_app/widgets/favor_passos_card.dart';
import 'package:bora_app/widgets/folha_favor.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');

/// "SMS de receita" INVENTADO, desenhado aqui (720×1280, letra miúda como
/// numa captura de telemóvel). Mesmos números que
/// `.claude/.ai/provas/favor-farmacia-2026-10-08/gerar_receita_teste.py`.
Future<Uint8List> _receitaDeTeste() async {
  const w = 720.0, h = 1280.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFF5F5F5));
  c.drawRect(const Rect.fromLTWH(0, 0, w, 110), Paint()..color = const Color(0xFF1E1E1E));
  void escreve(String t, double x, double y, double tam,
      {Color cor = const Color(0xFF141414), bool negrito = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontSize: tam,
              color: cor,
              fontWeight: negrito ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - x - 24);
    tp.paint(c, Offset(x, y));
  }
  escreve('SNS  |  Mensagens', 30, 38, 30, cor: Colors.white, negrito: true);
  c.drawRRect(RRect.fromLTRBR(24, 150, w - 24, 710, const Radius.circular(28)),
      Paint()..color = const Color(0xFFE5E5EA));
  var y = 180.0;
  for (final (t, tam, b) in const [
    ('Receita Eletrónica SNS', 26.0, true),
    ('Utente: TESTE BORA', 22.0, false),
    ('', 22.0, false),
    ('N.º da receita:', 22.0, false),
    ('1012 3456 7890 1234 567', 24.0, true),
    ('', 22.0, false),
    ('Código de acesso e dispensa:', 22.0, false),
    ('482915', 24.0, true),
    ('', 22.0, false),
    ('Código de direito de opção:', 22.0, false),
    ('7731', 24.0, true),
    ('', 22.0, false),
    ('Castilium 10 mg  x1 embalagem', 22.0, false),
  ]) {
    escreve(t, 56, y, tam, negrito: b);
    y += 40;
  }
  c.drawRect(const Rect.fromLTWH(24, 780, w - 48, 80), Paint()..color = const Color(0xFFFFEB3B));
  escreve('IMAGEM DE TESTE — RECEITA INVENTADA', 48, 802, 26, negrito: true);
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

const _segundosPorCaptura = 9;

OrderModel _favor({int? passo, bool finalizado = false}) => OrderModel(
      id: 'prova-favor-0810',
      total: 12.00,
      serviceType: OrderServiceType.errand,
      status: passo == 2
          ? OrderStatus.onTheWay
          : (passo == 1 ? OrderStatus.pickedUp : OrderStatus.driverAccepted),
      paymentMethod: PaymentMethod.cash,
      customerName: 'Cristina (teste)',
      errandDescription: 'Vai à farmácia e compra castilium 10mg (TESTE)',
      errandLocation: 'Farmácia Tavares, Avenida Cidade de Safed, Guarda',
      errandLocationLat: 40.5420,
      errandLocationLng: -7.2560,
      errandHomeStop: true,
      errandHomeStopReason: 'outro',
      errandPasso: passo,
      errandHasPurchase: true,
      errandEstimatedPurchaseCents: 400,
      isPurchaseFinalized: finalizado,
      finalTotal: finalizado ? 9.88 : null,
      deliveryFee: 8.00,
      errandRequestPhotoUrl:
          'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/prova/inexistente.jpg',
      pickupAddress: 'Rua do Ferrinho, Guarda',
      dropoffAddress: 'Rua Pedro Álvares Cabral 31, Guarda',
      destination: const LatLng(40.5370, -7.2680),
    );

Future<void> _parar(WidgetTester t, String nome) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  debugPrint('[prova] PRONTO $nome');
  for (var i = 0; i < _segundosPorCaptura * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
}

/// Painel do fundo como o do mapa do estafeta (mesma folga do sistema).
class _PainelProva extends StatelessWidget {
  const _PainelProva({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDE7E4), // "mapa"
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: FavorPassosCard(
              order: order,
              posicaoEstafeta: const LatLng(40.5300, -7.2900),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prova visual do Favor e dos botões do fundo', (t) async {
    await Supabase.initialize(url: _url, anonKey: _anon);
    final driverStore = DriverStore();
    final orderStore = OrderStore(driverStore: driverStore);
    final chave = GlobalKey<NavigatorState>();
    final pagina = ValueNotifier<Widget>(const SizedBox());

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DriverStore>.value(value: driverStore),
        ChangeNotifierProvider<OrderStore>.value(value: orderStore),
      ],
      child: MaterialApp(
        navigatorKey: chave,
        debugShowCheckedModeBanner: false,
        home: ValueListenableBuilder<Widget>(
          valueListenable: pagina,
          builder: (_, w, __) => w,
        ),
      ),
    ));

    // 1-3: o cartão dos passos em cada passo.
    pagina.value = _PainelProva(order: _favor(passo: 0));
    await _parar(t, '01_passo1_casa');
    pagina.value = _PainelProva(order: _favor(passo: 1));
    await _parar(t, '02_passo2_farmacia');
    pagina.value = _PainelProva(order: _favor(passo: 2, finalizado: true));
    await _parar(t, '03_passo3_entrega_9_88');

    // 4: a oferta, antes de aceitar (rota toda).
    pagina.value = Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FavorPassosCard(
            order: _favor(),
            compacto: true,
            posicaoEstafeta: const LatLng(40.5300, -7.2900),
          ),
        ),
      ),
    );
    await _parar(t, '04_oferta_rota');

    // 5: ANTES — a folha protegida aberta pelo caminho antigo (sem folga).
    pagina.value = const Scaffold(body: SizedBox.expand());
    await t.pump();
    final ctx = chave.currentContext!;
    final antes = _favor(passo: 2, finalizado: true);
    // ignore: unawaited_futures
    ErrandExecutionSheet.show(ctx, antes);
    await _parar(t, '05_ANTES_folha_entrega');
    chave.currentState!.pop();
    await t.pumpAndSettle();

    // 6: DEPOIS — a mesma folha pela FolhaFavor (pedido vivo + folga + passo).
    // ignore: unawaited_futures
    FolhaFavor.abrir(ctx, _favor(passo: 2, finalizado: true));
    await _parar(t, '06_DEPOIS_folha_entrega');
    chave.currentState!.pop();
    await t.pumpAndSettle();

    // 7-8: a receita de teste em ecrã inteiro, normal e ampliada.
    final receita = await t.runAsync(_receitaDeTeste);
    if (receita != null) {
      // ignore: unawaited_futures
      BoraFotoEcraInteiro.abrir(ctx,
          imagem: MemoryImage(receita), titulo: 'Foto da receita');
      await _parar(t, '07_receita_ecra_inteiro');
      final centro = t.getCenter(find.byType(InteractiveViewer));
      final alvo = Offset(centro.dx - 90, centro.dy - 170);
      await t.tapAt(alvo);
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(alvo);
      await t.pumpAndSettle();
      await _parar(t, '08_receita_ampliada');
    } else {
      debugPrint('[prova] SEM receita (falhou a desenhar)');
    }
    debugPrint('[prova] FIM');
  });
}
