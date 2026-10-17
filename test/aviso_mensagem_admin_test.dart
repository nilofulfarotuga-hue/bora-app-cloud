// Cancelamento tardio TVDE (17/10/2026) — o lado do MOTORISTA.
//
// O servidor avisa o motorista com uma linha no sino (`in_app_notifications`,
// kind `tvde_cancel_comp`) e um push data-only pela Edge `notify-admin-message`
// (type `admin_message`). Até hoje o push não aparecia: o tipo não estava nas
// categorias persistentes, o fundo descartava-o e a app aberta só tocava um
// som. Estes testes prendem:
//  (iii) a função pura que decide a notificação de `admin_message`, e os fios
//        que a ligam (fundo + aberta, toque → ecrã de notificações, também na
//        home do motorista de TVDE);
//  e os ícones/textos do lado do motorista (sino, Ganhos, ecrã da corrida).
import 'dart:io';

import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart';
import 'package:bora_app/screens/ganhos_screen.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final servico =
      File('lib/services/notification_service.dart').readAsStringSync();

  group('(iii) notificação de admin_message', () {
    test('título e texto vêm do data (push data-only)', () {
      final a = avisoDaMensagemDoAdmin({
        'type': 'admin_message',
        'kind': 'tvde_cancel_compensation',
        'title': 'Corrida cancelada · recebes 3,75 €',
        'body':
            'O cliente cancelou depois dos 3 minutos. A compensação entra no teu acerto desta semana.',
        'channelId': 'bora_orders',
        'relatedId': 'ride-1',
      });
      expect(a.title, 'Corrida cancelada · recebes 3,75 €');
      expect(a.body, startsWith('O cliente cancelou depois dos 3 minutos.'));
      expect(a.payload,
          {'kind': 'tvde_cancel_compensation', 'relatedId': 'ride-1'});
    });

    test('sem título no data usa o da notification; sem nada, "Bora"', () {
      expect(
          avisoDaMensagemDoAdmin({'type': 'admin_message'},
                  notifTitle: 'Olá', notifBody: 'Mensagem')
              .title,
          'Olá');
      final vazio = avisoDaMensagemDoAdmin({'type': 'admin_message'});
      expect(vazio.title, 'Bora');
      expect(vazio.body, '');
      expect(vazio.payload['kind'], 'admin_message');
    });

    test('uma notificação por mensagem: o id repete-se só para a mesma', () {
      Map<String, dynamic> m(String rel) => {
            'type': 'admin_message',
            'kind': 'tvde_cancel_compensation',
            'title': 't',
            'body': 'b',
            'relatedId': rel,
          };
      expect(avisoDaMensagemDoAdmin(m('a')).notificationId,
          avisoDaMensagemDoAdmin(m('a')).notificationId,
          reason: 'o mesmo push entregue duas vezes não empilha');
      expect(avisoDaMensagemDoAdmin(m('a')).notificationId,
          isNot(avisoDaMensagemDoAdmin(m('b')).notificationId));
      // Mensagens livres do painel (sem relatedId) com textos diferentes não
      // se apagam uma à outra.
      expect(
          avisoDaMensagemDoAdmin({'title': 'Um', 'body': '1'}).notificationId,
          isNot(avisoDaMensagemDoAdmin({'title': 'Dois', 'body': '2'})
              .notificationId));
    });

    test('a app desenha admin_message em fundo e aberta (categoria persistente)',
        () {
      final i = servico.indexOf('const Set<String> _kPersistentCategoryTypes');
      final conjunto = servico.substring(i, servico.indexOf('};', i));
      expect(conjunto, contains("'admin_message'"),
          reason: 'sem esta entrada o fundo descarta o push');
      final caso = servico.indexOf("case 'admin_message':");
      expect(caso, isNonNegative, reason: 'falta o ramo que desenha o aviso');
      final ramo = servico.substring(caso, servico.indexOf('return;', caso));
      expect(ramo, contains('avisoDaMensagemDoAdmin(data'));
      expect(ramo, contains('_showPersistentStatusNotification'));
    });

    test('tocar abre o ecrã de notificações (com a app viva e a frio)', () {
      final toque = servico.indexOf("if (data['type'] == 'admin_message') {");
      expect(toque, isNonNegative);
      expect(
          servico.substring(toque, servico.indexOf('return;', toque)),
          contains('openInboxFromNotification()'));
      expect("'admin_message'".allMatches(servico).length,
          greaterThanOrEqualTo(4),
          reason: 'conjunto + desenho + toque + arranque a frio + deep link');
      final abre = servico.indexOf('Future<void> openInboxFromNotification()');
      expect(servico.substring(abre, abre + 600),
          contains('const NotificationsScreen()'));
    });

    test('a frio, o toque também tira a notificação persistente', () {
      // [Revisão 17/10] Sem isto "recebes 3,75 €" ficava presa na barra.
      final i = servico.indexOf(
          "if (data['type'] == 'admin_message') {", servico.indexOf('getNotificationAppLaunchDetails()'));
      expect(i, isNonNegative);
      final ramo = servico.substring(i, servico.indexOf('}', servico.indexOf('openInboxFromNotification', i)) + 1);
      expect(ramo, contains('localPlugin.cancel(id)'));
    });

    test('o @pragma do fundo continua na função que o handler chama', () {
      expect(
          RegExp(r"@pragma\('vm:entry-point'\)\s+Future<void> _showPersistentCategoryNotification\(")
              .hasMatch(servico),
          isTrue);
    });

    test('a home do motorista de TVDE liga o deep link das mensagens', () {
      final home = File('lib/screens/driver/tvde/tvde_driver_home_screen.dart')
          .readAsStringSync();
      expect(home, contains('NotificationService.setupBroadcastDeepLink(context)'));
    });
  });

  group('motorista: sino, Ganhos e ecrã da corrida', () {
    test('sino: tvde_cancel_comp tem o ícone do euro', () {
      final sino = File('lib/screens/notifications_screen.dart')
          .readAsStringSync();
      final caso = sino.indexOf("case 'tvde_cancel_comp':");
      expect(caso, isNonNegative);
      expect(sino.substring(caso, sino.indexOf(';', caso)),
          contains('Icons.euro'));
    });

    test('Ganhos: compensação de corrida leva o carro; a de entrega não', () {
      expect(
          iconeDoGanho({
            'tipo': 'entrega',
            'descricao': 'Compensação · corrida cancelada pelo cliente',
          }),
          Icons.directions_car_outlined);
      expect(
          iconeDoGanho({
            'tipo': 'entrega',
            'descricao':
                'Compensação · pedido cancelado depois de aceite · Goola',
          }),
          Icons.delivery_dining_outlined);
      expect(iconeDoGanho({'tipo': 'tvde', 'descricao': 'Corrida'}),
          Icons.directions_car_outlined);
      expect(iconeDoGanho({'tipo': 'tokens'}), Icons.monetization_on_outlined);
      expect(iconeDoGanho(const {}), Icons.delivery_dining_outlined);
    });

    test('ecrã da corrida: o texto da SnackBar quando o cliente cancela', () {
      expect(textoDoAvisoDeCancelamento(null), 'O cliente cancelou a corrida.');
      expect(textoDoAvisoDeCancelamento(const {'title': '', 'body': null}),
          'O cliente cancelou a corrida.');
      expect(
          textoDoAvisoDeCancelamento(const {
            'title': 'Corrida cancelada · recebes 3,75 €',
            'body':
                'O cliente cancelou depois dos 3 minutos. A compensação entra no teu acerto desta semana.',
          }),
          'Corrida cancelada · recebes 3,75 €. O cliente cancelou depois dos 3 minutos. A compensação entra no teu acerto desta semana.');
      expect(textoDoAvisoDeCancelamento(const {'title': 'Só título'}),
          'Só título');
    });

    test('ecrã da corrida: a SnackBar corre uma vez e só no cancelamento do cliente',
        () {
      final ecra = File('lib/screens/driver/tvde/tvde_ride_active_screen.dart')
          .readAsStringSync();
      final i = ecra.indexOf("ride.status == 'cancelada_cliente' && !_avisoClienteCancelou");
      expect(i, isNonNegative);
      expect(ecra.substring(i, i + 200), contains('_avisoClienteCancelou = true'));
      // A navegação de sempre continua lá, logo a seguir.
      final resto = ecra.substring(i, i + 900);
      expect(resto, contains('store.clearActive();'));
      expect(resto, contains('Navigator.of(context).maybePop();'));
    });
  });
}
