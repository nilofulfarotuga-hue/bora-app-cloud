import 'dart:io';

import 'package:bora_app/screens/admin/admin_complaints_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/utils/hora_lisboa_ext.dart';
import 'package:bora_app/widgets/admin/admin_csv_button.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ronda 04/10/2026 · admin-geral] O que estes testes trancam:
///  1. Os avisos que abriam "Página não encontrada" têm rota em main.dart.
///  2. Os ecrãs novos estão no menu (bloqueios, chat TVDE, pedidos de acesso
///     TVDE, escalamentos do suporte, reativação, mesas, folgas, opções).
///  3. "Hoje" no painel começa à meia-noite de Lisboa, não do navegador/UTC.
///  4. A foto da queixa (linha "Foto: <url>") sai do texto e vai para a imagem.
///  5. O CSV mostra datas em hora de Lisboa.
///  6. "Enviar a todos" pede confirmação com o número de pessoas.
void main() {
  final mainDart = File('lib/main.dart').readAsStringSync();

  test('rotas dos avisos registadas', () {
    for (final r in const [
      "'/admin/appointments':",
      "'/admin/receipts':",
      "'/admin/support-escalations':",
      "'/admin/carwash':",
      "'/admin/encomendas-telefone':",
      "'/admin/acertos-semana':",
      "'/admin/bloqueios':",
      "'/admin/tvde/chats':",
      "'/admin/reativacao':",
    ]) {
      expect(mainDart, contains(r), reason: '$r em falta em main.dart');
    }
  });

  test('ecrãs novos no menu, fora do arquivo', () {
    final vivos = adminMenuSections()
        .where((s) => !s.archived)
        .expand((s) => s.items)
        .map((i) => i.title)
        .toSet();
    for (final t in const [
      'Utilizadores bloqueados',
      'Chat das corridas',
      'Pedidos de acesso TVDE',
      'Suporte — falar com o Danilo',
      'Clientes parados (reativação)',
      'Reclamações',
      'Mesas',
      'Folgas da equipa',
      'Opções de produto',
    ]) {
      expect(vivos, contains(t), reason: '$t não está no menu');
    }
  });

  test('início do dia em Lisboa (verão e inverno)', () {
    // 04/10 00:30 em Lisboa (verão, UTC+1) = 03/10 23:30 UTC.
    expect(inicioDoDiaLisboaUtc(DateTime.utc(2026, 10, 3, 23, 30)),
        DateTime.utc(2026, 10, 3, 23));
    // 15/12 10:00 UTC (inverno, UTC+0).
    expect(inicioDoDiaLisboaUtc(DateTime.utc(2026, 12, 15, 10)),
        DateTime.utc(2026, 12, 15));
    expect(DateTime.utc(2026, 10, 3, 23, 30).toLisboa().day, 4);
  });

  test('foto da queixa separada do texto', () {
    final q = separarFotoDaQueixa(
        'Faltou produto: Coca-Cola\nFoto: https://x.supabase.co/storage/v1/object/order-photos/a/b.jpg');
    expect(q.texto, 'Faltou produto: Coca-Cola');
    expect(q.foto, endsWith('b.jpg'));
    expect(separarFotoDaQueixa('Sem foto aqui').foto, isNull);
  });

  test('CSV em hora de Lisboa', () {
    expect(AdminCsvButton.valor('created_at', '2026-10-03T23:30:00Z'),
        '04/10 00:30');
    expect(AdminCsvButton.valor('nome', 'Ana'), 'Ana');
    expect(AdminCsvButton.valor('x', null), '');
  });

  test('envio em massa pede confirmação com o número de pessoas', () {
    final src = File('lib/screens/admin/admin_send_notification_screen.dart')
        .readAsStringSync();
    expect(src, contains("rpc('admin_broadcast_preview'"));
    expect(src, contains('Confirmar envio em massa'));
    expect(src, isNot(contains('admin_save_broadcast_in_app')),
        reason: 'o sininho já é gravado por admin_broadcast_notification');
  });
}
