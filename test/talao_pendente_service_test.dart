// M1 08/11/2026 — "toda foto de talão que o estafeta tira tem de ficar
// guardada num sítio certo, para sempre, e nunca se pode perder."
//
// Prova a fila do telemóvel (TalaoPendenteService) sem Supabase: pasta
// temporária no lugar dos documentos da app, SharedPreferences em memória e
// um envio falso que regista o que recebeu.

import 'dart:io';

import 'package:bora_app/services/receipt_upload_service.dart';
import 'package:bora_app/services/talao_pendente_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory raiz;
  late Directory camara;
  late List<Map<String, Object?>> chamadas;
  late bool falhar;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TalaoPendenteService.reiniciarMemoriaParaTeste();
    raiz = await Directory.systemTemp.createTemp('talao_pendente_');
    camara = await Directory('${raiz.path}/camara').create(recursive: true);
    final documentos =
        await Directory('${raiz.path}/documentos').create(recursive: true);
    TalaoPendenteService.pastaBase = () async => documentos.path;
    TalaoPendenteService.agora = DateTime.now;
    chamadas = <Map<String, Object?>>[];
    falhar = true;
    TalaoPendenteService.enviarParaServidor = ({
      required String orderId,
      required File photoFile,
      required int totalCents,
      String? fotoId,
      DateTime? tiradaEm,
    }) async {
      chamadas.add(<String, Object?>{
        'orderId': orderId,
        'fotoId': fotoId,
        'totalCents': totalCents,
        'tiradaEm': tiradaEm,
        'bytes': await photoFile.readAsBytes(),
      });
      if (falhar) throw const SocketException('Failed host lookup');
      return '2026/11/$orderId/$fotoId.jpg';
    };
  });

  tearDown(() async {
    TalaoPendenteService.reiniciarMemoriaParaTeste();
    TalaoPendenteService.enviarParaServidor =
        ReceiptUploadService.uploadReceipt;
    TalaoPendenteService.agora = DateTime.now;
    if (await raiz.exists()) await raiz.delete(recursive: true);
  });

  Future<File> fotoDaCamara(String nome, List<int> bytes) async {
    final f = File('${camara.path}/$nome');
    await f.writeAsBytes(bytes);
    return f;
  }

  test('(a) envio falha: fica pendente, a cópia local existe e sobrevive a '
      'um reinício da app', () async {
    final bytes = List<int>.generate(64, (i) => i);
    final original = await fotoDaCamara('cam_1.jpg', bytes);

    final t = await TalaoPendenteService.guardar(
      orderId: 'ORD-1',
      foto: original,
      totalCents: 1234,
    );
    expect(t.pendente, isTrue);
    expect(t.localPath, isNot(original.path));
    expect(t.localPath, contains(TalaoPendenteService.pasta));
    expect(t.fotoId, matches(RegExp(r'^[A-Za-z0-9_-]{6,64}$')));
    expect(await File(t.localPath).readAsBytes(), bytes);

    final caminho = await TalaoPendenteService.enviar(t);
    expect(caminho, isNull);
    expect(chamadas, hasLength(1));

    // O SO limpa a cache da câmara: a cópia da fila continua lá.
    await original.delete();
    expect(File(t.localPath).existsSync(), isTrue);

    // App fechada e aberta de novo: a fila vem do disco.
    TalaoPendenteService.reiniciarMemoriaParaTeste();
    expect(TalaoPendenteService.ultimoDo('ORD-1'), isNull);
    await TalaoPendenteService.carregar();
    final depois = TalaoPendenteService.ultimoDo('ORD-1');
    expect(depois, isNotNull);
    expect(depois!.fotoId, t.fotoId);
    expect(depois.estado, TalaoPendente.estadoPendente);
    expect(depois.path, isNull);
    expect(depois.tentativas, 1);
    expect(depois.totalCents, 1234);
    expect(depois.falhouPorRede, isTrue);
    expect(TalaoPendenteService.pendentesDo('ORD-1'), hasLength(1));
    expect(File(depois.localPath).existsSync(), isTrue);
    expect(TalaoPendenteService.avisoNaoEnviado(depois), startsWith('Sem rede'));
  });

  test('(b) reenvio mais tarde sobe a MESMA foto (mesmo fotoId) e fica '
      'enviada com o caminho do servidor', () async {
    final bytes = List<int>.generate(32, (i) => 255 - i);
    final t = await TalaoPendenteService.guardar(
      orderId: 'ORD-2',
      foto: await fotoDaCamara('cam_2.jpg', bytes),
      totalCents: 990,
    );
    expect(await TalaoPendenteService.enviar(t), isNull);

    falhar = false;
    await TalaoPendenteService.reenviarPendentes();

    final depois = TalaoPendenteService.porFotoId(t.fotoId)!;
    expect(depois.estado, TalaoPendente.estadoEnviado);
    expect(depois.enviado, isTrue);
    expect(depois.path, '2026/11/ORD-2/${t.fotoId}.jpg');
    expect(depois.enviadoEm, isNotNull);
    expect(chamadas, hasLength(2));
    expect(chamadas.map((c) => c['fotoId']).toSet(), {t.fotoId});
    expect(chamadas.map((c) => c['tiradaEm']).toSet(), {t.tiradaEm});
    expect(chamadas.last['bytes'], bytes);
    expect(chamadas.last['totalCents'], 990);
    expect(TalaoPendenteService.pendentesDo('ORD-2'), isEmpty);
    // A cópia local não se apaga logo a seguir ao envio.
    expect(File(t.localPath).existsSync(), isTrue);

    // Já está no servidor: pedir outra vez não volta a subir.
    expect(await TalaoPendenteService.enviar(t), depois.path);
    expect(chamadas, hasLength(2));

    // E o estado "enviado" ficou gravado no disco.
    TalaoPendenteService.reiniciarMemoriaParaTeste();
    await TalaoPendenteService.carregar();
    final relido = TalaoPendenteService.ultimoDo('ORD-2')!;
    expect(relido.enviado, isTrue);
    expect(relido.path, depois.path);
  });

  test('(c) duas fotos do mesmo pedido: duas entradas e dois ficheiros, '
      'a segunda nunca substitui a primeira', () async {
    final a = await TalaoPendenteService.guardar(
      orderId: 'ORD-3',
      foto: await fotoDaCamara('cam_a.jpg', <int>[1, 2, 3]),
      totalCents: 500,
    );
    final b = await TalaoPendenteService.guardar(
      orderId: 'ORD-3',
      foto: await fotoDaCamara('cam_b.jpg', <int>[4, 5, 6, 7]),
      totalCents: 700,
    );

    expect(a.fotoId, isNot(b.fotoId));
    expect(a.localPath, isNot(b.localPath));
    expect(await File(a.localPath).readAsBytes(), <int>[1, 2, 3]);
    expect(await File(b.localPath).readAsBytes(), <int>[4, 5, 6, 7]);
    expect(TalaoPendenteService.pendentesDo('ORD-3'), hasLength(2));
    expect(TalaoPendenteService.ultimoDo('ORD-3')!.fotoId, b.fotoId);

    falhar = false;
    await TalaoPendenteService.reenviarPendentes();

    final a2 = TalaoPendenteService.porFotoId(a.fotoId)!;
    final b2 = TalaoPendenteService.porFotoId(b.fotoId)!;
    expect(a2.enviado, isTrue);
    expect(b2.enviado, isTrue);
    expect(a2.path, isNot(b2.path));
    expect(chamadas.map((c) => c['fotoId']).toSet(), {a.fotoId, b.fotoId});
    expect(File(a.localPath).existsSync(), isTrue);
    expect(File(b.localPath).existsSync(), isTrue);
  });

  test('limpeza: só apaga a cópia de foto confirmada há mais de 7 dias; '
      'uma pendente nunca', () async {
    final enviada = await TalaoPendenteService.guardar(
      orderId: 'ORD-4',
      foto: await fotoDaCamara('cam_4.jpg', <int>[9, 9]),
      totalCents: 100,
    );
    falhar = false;
    expect(await TalaoPendenteService.enviar(enviada), isNotNull);

    falhar = true;
    final pendente = await TalaoPendenteService.guardar(
      orderId: 'ORD-5',
      foto: await fotoDaCamara('cam_5.jpg', <int>[8, 8]),
      totalCents: 200,
    );
    expect(await TalaoPendenteService.enviar(pendente), isNull);

    final daquiAOitoDias = DateTime.now().add(const Duration(days: 8));
    TalaoPendenteService.agora = () => daquiAOitoDias;
    await TalaoPendenteService.reenviarPendentes();

    expect(File(enviada.localPath).existsSync(), isFalse);
    expect(TalaoPendenteService.porFotoId(enviada.fotoId), isNull);
    expect(File(pendente.localPath).existsSync(), isTrue);
    expect(TalaoPendenteService.porFotoId(pendente.fotoId)!.pendente, isTrue);
  });
}
