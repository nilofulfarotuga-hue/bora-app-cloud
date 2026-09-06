import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/models/cart_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// LOJA FECHADA É VISITÁVEL (2026-08-27, pedido do Danilo).
///
/// A regra: fora de horário o cliente entra na loja e vê tudo — capa, menu,
/// preços, opções. O travão é só no momento de meter no carrinho, com uma
/// mensagem que diz a que horas abre. Sem agendamento, sem "avisar quando
/// abrir" — isso não existe.
///
/// "Fechada" ≠ "Em breve": a primeira já trabalha connosco e está fora de
/// horas; a segunda ainda não abriu no Bora e é travada só no pagamento.
RestaurantModel _loja({
  required String nome,
  required BusinessHours horario,
  BusinessCategory categoria = BusinessCategory.restaurant,
}) =>
    RestaurantModel(
      id: 'x',
      name: nome,
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: categoria,
      businessHours: horario,
    );

/// Horário que garante loja FECHADA à hora a que o teste corre.
BusinessHours _fechadaAgora() {
  final agora = DateTime.now();
  // Janela de uma hora que já passou (ou ainda vem longe), nunca a actual.
  final abre = (agora.hour + 3) % 24;
  final fecha = (abre + 1) % 24;
  final d = DayHours(
    open: '${abre.toString().padLeft(2, '0')}:00',
    close: '${fecha.toString().padLeft(2, '0')}:00',
  );
  return BusinessHours(
      mon: d, tue: d, wed: d, thu: d, fri: d, sat: d, sun: d);
}

/// Horário que garante loja ABERTA agora (24 h).
BusinessHours _abertaAgora() {
  const d = DayHours(open: '00:00', close: '23:59');
  return const BusinessHours(
      mon: d, tue: d, wed: d, thu: d, fri: d, sat: d, sun: d);
}

CartItem _item() => CartItem(
      productId: 'p1',
      name: 'Goola Bowl',
      price: 9.22,
      quantity: 1,
    );

void main() {
  // O CartStore grava o carrinho em SharedPreferences: sem isto o teste enche
  // o log de avisos de binding (passa na mesma, mas fica ilegivel).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('o cliente entra na loja fechada e vê tudo', () {
    test('a loja fechada continua a dizer a que horas abre', () {
      final loja = _loja(nome: 'Continente', horario: _fechadaAgora());
      expect(loja.isOpenNow(), isFalse);
      expect(loja.statusLabel(), startsWith('Fechada, abre às '));
      // Formato PT-PT com "h", não "10:00".
      expect(loja.statusLabel(), contains('h'));
      expect(loja.statusLabel(), isNot(contains(':')));
    });

    test('o aviso diz o que se passa e a que horas abre', () {
      final loja = _loja(nome: 'Continente', horario: _fechadaAgora());
      expect(loja.avisoLojaFechada, contains('Continente'));
      expect(loja.avisoLojaFechada, contains('fechada'));
      expect(loja.avisoLojaFechada, contains('Abre às '));
    });

    test('o aviso NÃO promete agendamento nem aviso de reabertura', () {
      final loja = _loja(nome: 'Continente', horario: _fechadaAgora());
      final t = loja.avisoLojaFechada.toLowerCase();
      for (final proibido in ['agendar', 'agendamento', 'avisar', 'notificar',
        'quando abrir', 'marcar']) {
        expect(t.contains(proibido), isFalse,
            reason: 'o aviso promete "$proibido", que ainda não existe');
      }
    });

    test('loja aberta diz Aberto, sem aviso nenhum', () {
      final loja = _loja(nome: 'Burger King', horario: _abertaAgora());
      expect(loja.isOpenNow(), isTrue);
      expect(loja.statusLabel(), 'Aberto');
    });

    test('casa de festas nunca é dada como fechada — vende por encomenda', () {
      final festa = _loja(
        nome: 'Sabores do Brasil',
        horario: _fechadaAgora(),
        categoria: BusinessCategory.festas,
      );
      expect(festa.statusLabel(), 'Aceita encomendas');
    });
  });

  group('o travão está no carrinho, não na porta', () {
    test('loja FECHADA não deixa adicionar', () {
      final cart = CartStore();
      cart.configureSession(
        serviceType: OrderServiceType.restaurant,
        vendorName: 'Continente',
        vendorFechada: true,
        vendorAvisoFechada: 'Continente está fechada agora. Abre às 08h00.',
      );
      cart.addItem(_item());
      expect(cart.items, isEmpty);
      expect(cart.lojaFechada, isTrue);
      expect(cart.avisoLojaFechada, contains('08h00'));
    });

    test('loja ABERTA adiciona normalmente', () {
      final cart = CartStore();
      cart.configureSession(
        serviceType: OrderServiceType.restaurant,
        vendorName: 'Burger King',
        vendorFechada: false,
      );
      cart.addItem(_item());
      expect(cart.items, hasLength(1));
      expect(cart.lojaFechada, isFalse);
    });

    test('loja em EM BREVE deixa encher o carrinho (só o pagamento trava)', () {
      // Isto era um bug: o addItem devolvia sem adicionar e sem dizer nada,
      // contra o que `vendorBlocksAddToCart` promete. Na Goola, o botão de
      // adicionar não fazia rigorosamente nada.
      final cart = CartStore();
      cart.configureSession(
        serviceType: OrderServiceType.restaurant,
        vendorName: 'Goola Açaí',
        vendorComingSoon: true,
      );
      cart.addItem(_item());
      expect(cart.items, hasLength(1),
          reason: '"Em breve" não pode travar o carrinho — trava no pagamento');
      expect(cart.vendorComingSoon, isTrue);
      expect(cart.vendorBlocksAddToCart, isFalse);
    });
  });
}
