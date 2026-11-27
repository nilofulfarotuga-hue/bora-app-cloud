// LOJA FECHADA: ENCHER O CARRINHO E AGENDAR (27/11/2026, missão
// loja-fechada-agendar-2026-11-27, caso Sabores do Brasil às 21:38).
//
// Ordem do Danilo: com a loja fechada o cliente enche o carrinho e marca para
// amanhã (da abertura ao fecho) ou outro dia. Relógio fixo em hora de Lisboa
// (novembro = UTC+0). O servidor continua a ser a fonte de verdade; aqui
// prova-se o que a app decide.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/utils/loja_fechada_pedido.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sexta, 27/11/2026, 21:40 em Lisboa (a hora da Karen).
final noite = DateTime.utc(2026, 11, 27, 21, 40);

/// Sexta, 27/11/2026, 15:00 em Lisboa (pausa da Boom! Burger).
final tarde = DateTime.utc(2026, 11, 27, 15, 0);

BusinessHours todosOsDias(DayHours d) =>
    BusinessHours(mon: d, tue: d, wed: d, thu: d, fri: d, sat: d, sun: d);

final horasKeli = todosOsDias(const DayHours(open: '09:00', close: '20:00'));
final horasGoola = todosOsDias(const DayHours(open: '10:00', close: '20:00'));
const _boomDia = DayHours(
    open: '12:15', close: '22:15', breakStart: '14:15', breakEnd: '19:15');
const horasBoom = BusinessHours(
  mon: DayHours(open: '19:15', close: '22:15'),
  tue: _boomDia,
  wed: _boomDia,
  thu: _boomDia,
  fri: _boomDia,
  sat: _boomDia,
  sun: DayHours(open: '12:00', close: '22:30', closed: true),
);

RestaurantModel loja(
  String id,
  String nome, {
  required BusinessHours horas,
  bool parceira = true,
  BusinessCategory categoria = BusinessCategory.restaurant,
}) =>
    RestaurantModel(
      id: id,
      name: nome,
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: parceira,
      category: categoria,
      businessHours: horas,
    );

final keli = loja('sabores-brasil-guarda', 'Sabores do Brasil',
    horas: horasKeli, categoria: BusinessCategory.festas);
final goola = loja('goola-acai-guarda', 'Goola Açaí', horas: horasGoola);
final boom = loja('boom-burger-guarda', 'Boom! Burger', horas: horasBoom);
final continente = loja('continente-guarda', 'Continente',
    horas: todosOsDias(const DayHours(open: '08:00', close: '22:00')),
    parceira: false,
    categoria: BusinessCategory.supermarket);

/// Faz de servidor: as janelas vêm do horário da loja ao relógio fixo, como
/// o `scheduled_windows_for_store`. Com [falhaConfig] responde como o
/// servidor respondia ao convidado antes de 27/11 (401).
class ServidorFalso implements AgendarPedidoApi {
  ServidorFalso(this.agora, {this.falhaConfig = false, this.semJanelas = false});
  final DateTime agora;
  bool falhaConfig;
  final bool semJanelas;
  final Map<String, BusinessHours> horas = {
    keli.id: keli.businessHours,
    goola.id: goola.businessHours,
    boom.id: boom.businessHours,
    continente.id: continente.businessHours,
  };

  @override
  Future<ConfigAgendar> config() async {
    if (falhaConfig) throw Exception('401 auth_required');
    return const ConfigAgendar(ligado: true, maxDias: 7, antecedenciaMin: 60);
  }

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async {
    final h = horas[restaurantId];
    if (h == null || semJanelas) return const [];
    return janelasDoDia(horas: h, dia: dia, agora: agora);
  }

  @override
  Future<void> gravar(String orderId, DateTime instante) async {}

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async =>
      const [];
}

AgendarPedidoEstado get estado => AgendarPedidoEstado.instance;

Future<void> servidor(ServidorFalso s) async {
  estado.reporParaTeste(s);
  await estado.carregarConfig(forcar: true, agora: s.agora);
}

/// Prateleiras da Keli: os ids `festa-*` são da `Para festa (encomenda)`.
String? prateleira(String productId) =>
    productId.startsWith('festa-') ? kFestasPrateleiraEncomenda : 'Na hora';

/// O carrinho como a página da loja o configura (`openRestaurantBusiness` /
/// `openRetailBusiness`), já com a resposta do servidor sobre as janelas.
Future<CartStore> carrinho(RestaurantModel l, DateTime agora) async {
  final c = CartStore()..categoriaDoProduto = prateleira;
  final festas = l.belongsTo(BusinessCategory.festas);
  c.configureSession(
    serviceType: l.category == BusinessCategory.supermarket
        ? OrderServiceType.storeShopping
        : OrderServiceType.restaurant,
    isPartnerStore: l.isPartner,
    vendorName: l.name,
    vendorRestaurantId: l.id,
    vendorIsFestas: festas,
    vendorFechada:
        l.emPausa(agora) || (!l.isOpenNow(agora) && !festas),
    vendorForaDeHoras: l.emPausa(agora) || !l.isOpenNow(agora),
    vendorAvisoFechada: l.avisoLojaFechadaEm(agora),
  );
  // A pergunta que o configureSession fez (relógio verdadeiro) acaba; depois
  // pergunta-se outra vez com o relógio fixo.
  await estado.verificarLoja(l.id);
  await estado.verificarLoja(l.id, agora: agora, forcar: true);
  return c;
}

CartItem naHora() =>
    CartItem(productId: 'coxinha-catupiri', name: 'Coxinha com catupiri', price: 2.5, quantity: 2);
CartItem centoSalgados() =>
    CartItem(productId: 'festa-cento-salgados', name: 'Cento de Salgados', price: 35, quantity: 1);
CartItem acai() => CartItem(productId: 'acai-500', name: 'Açaí 500 ml', price: 7, quantity: 1);
CartItem leite() => CartItem(productId: 'leite', name: 'Leite', price: 0.89, quantity: 1);

Future<JanelaAgendada> primeiraJanelaDe(RestaurantModel l, DateTime agora) async {
  final dia = estado.primeiroDiaComJanelas(l.id)!;
  return (await estado.api.janelas(l.id, dia)).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => estado.reporParaTeste(ServidorFalso(noite, falhaConfig: true)));

  group('o travão ao criar o pedido (lojaFechadaTravaPedido)', () {
    test('parceira fechada + janela de amanhã escolhida → não trava', () async {
      await servidor(ServidorFalso(noite));
      final c = await carrinho(goola, noite);
      c.addItem(acai());
      expect(c.items, hasLength(1), reason: 'a loja fechada deixa encher o carrinho');
      expect(goola.isOpenNow(noite), isFalse);
      final janela = await primeiraJanelaDe(goola, noite);
      expect(janela.dia, DateTime.utc(2026, 11, 28), reason: 'a 1.ª janela é amanhã');
      expect(janela.horas, '10:00–10:30', reason: 'da abertura da loja');
      estado.escolher(goola.id, janela);

      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: goola, itens: c.items, categoriaDoProduto: prateleira, agora: noite),
        isFalse,
      );
    });

    test('parceira fechada sem janela → trava, e a frase diz quando abre', () async {
      await servidor(ServidorFalso(noite));
      await carrinho(goola, noite);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: goola, itens: [acai()], categoriaDoProduto: prateleira, agora: noite),
        isTrue,
      );
      expect(goola.avisoLojaFechadaEm(noite), contains('Abre amanhã às 10h00'));
      expect(
        goola.avisoAgendarEm(noite),
        'Esta loja está fechada agora. Abre amanhã às 10:00 e fecha às 20:00. '
        'Podes marcar o teu pedido para amanhã ou para outro dia.',
      );
    });

    test('a janela de OUTRA loja não destrava esta', () async {
      await servidor(ServidorFalso(noite));
      await carrinho(goola, noite);
      final janela = await primeiraJanelaDe(goola, noite);
      estado.escolher(boom.id, janela);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: goola, itens: [acai()], categoriaDoProduto: prateleira, agora: noite),
        isTrue,
      );
    });

    test('loja aberta nunca trava; loja desconhecida decide o servidor', () {
      expect(lojaFechadaTravaPedido(loja: boom, agora: noite), isFalse,
          reason: 'a Boom! Burger fecha às 22:15 à sexta');
      expect(lojaFechadaTravaPedido(loja: null, agora: noite), isFalse);
    });

    test('não parceira fechada + janela → passa (sem regressão)', () async {
      await servidor(ServidorFalso(DateTime.utc(2026, 11, 27, 23, 0)));
      final agora = DateTime.utc(2026, 11, 27, 23, 0);
      final c = await carrinho(continente, agora);
      expect(c.lojaFechada, isFalse);
      c.addItem(leite());
      expect(c.items, hasLength(1));
      expect(c.agendamentoObrigatorio, isTrue);
      expect(c.agendamentoEmFalta, isTrue);
      estado.escolher(continente.id, await primeiraJanelaDe(continente, agora));
      expect(c.agendamentoEmFalta, isFalse);
      expect(c.fechadaSemHora, isFalse);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: continente, itens: c.items, categoriaDoProduto: prateleira, agora: agora),
        isFalse,
      );
    });
  });

  group('Sabores do Brasil (Keli) às 21:40', () {
    test('só "Na hora" → pede agendamento e passa com a janela de amanhã', () async {
      await servidor(ServidorFalso(noite));
      final c = await carrinho(keli, noite);
      c.addItem(naHora());
      expect(c.items, hasLength(1));
      expect(c.carrinhoEncomendaFesta, isFalse);
      expect(c.lojaFechadaAgora, isTrue);
      expect(c.agendamentoDisponivel, isTrue, reason: 'festas têm janelas desde 27/11');
      expect(c.agendamentoObrigatorio, isTrue);
      expect(c.agendamentoEmFalta, isTrue);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: keli, itens: c.items, categoriaDoProduto: prateleira, agora: noite),
        isTrue,
        reason: 'sem hora marcada, "Na hora" com a loja fechada não passa',
      );

      final janela = await primeiraJanelaDe(keli, noite);
      expect(janela.dia, DateTime.utc(2026, 11, 28));
      expect(janela.horas, '09:00–09:30');
      estado.escolher(keli.id, janela);
      expect(c.agendamentoEmFalta, isFalse);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: keli, itens: c.items, categoriaDoProduto: prateleira, agora: noite),
        isFalse,
      );
      expect(
        keli.avisoAgendarEm(noite),
        'Esta loja está fechada agora. Abre amanhã às 09:00 e fecha às 20:00. '
        'Podes marcar o teu pedido para amanhã ou para outro dia.',
      );
    });

    test('com "Cento de Salgados" → data de festa, passa sem agendamento', () async {
      await servidor(ServidorFalso(noite));
      final c = await carrinho(keli, noite);
      c.addItem(centoSalgados());
      expect(c.items, hasLength(1));
      expect(c.carrinhoEncomendaFesta, isTrue);
      expect(c.agendamentoDisponivel, isFalse, reason: 'a festa marca o dia no ecrã dela');
      expect(c.agendamentoEmFalta, isFalse);
      expect(c.fechadaSemHora, isFalse);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: keli, itens: c.items, categoriaDoProduto: prateleira, agora: noite),
        isFalse,
      );
    });

    test('carrinho misto = festa (regra de 25/08)', () async {
      await servidor(ServidorFalso(noite));
      final c = await carrinho(keli, noite);
      c.addItem(naHora());
      c.addItem(centoSalgados());
      expect(c.items, hasLength(2));
      expect(c.carrinhoEncomendaFesta, isTrue);
      expect(c.agendamentoEmFalta, isFalse);
      expect(
        lojaFechadaTravaPedidoDoCarrinho(
            loja: keli, itens: c.items, categoriaDoProduto: prateleira, agora: noite),
        isFalse,
      );
    });

    test('sem janelas (interruptor desligado): "Na hora" fica à espera, encomenda segue', () async {
      await servidor(ServidorFalso(noite, semJanelas: true));
      final c = await carrinho(keli, noite);
      c.addItem(naHora());
      expect(c.items, hasLength(1), reason: 'as festas nunca travaram o adicionar');
      expect(c.fechadaSemHora, isTrue, reason: 'o "Finalizar" mostra o aviso da loja');
      c.addItem(centoSalgados());
      expect(c.fechadaSemHora, isFalse);
    });
  });

  group('convidado (sem conta)', () {
    test('com a loja fechada consegue meter no carrinho', () async {
      // Desde 27/11 o servidor responde ao convidado (GRANT ... TO anon).
      await servidor(ServidorFalso(noite));
      final c = await carrinho(goola, noite);
      expect(c.lojaFechada, isFalse);
      c.addItem(acai());
      expect(c.items, hasLength(1));
    });

    test('depois de entrar na conta, o agendamento volta a ser lido e o carrinho fica',
        () async {
      // Antes de 27/11: o convidado recebia 401 e o agendamento ficava desligado.
      final s = ServidorFalso(noite, falhaConfig: true);
      await servidor(s);
      final c = await carrinho(keli, noite);
      c.addItem(centoSalgados());
      expect(c.items, hasLength(1), reason: 'a encomenda de festa nunca fica de fora');
      expect(estado.ligado, isFalse);

      // Entrou na conta: o servidor já responde.
      s.falhaConfig = false;
      await c.relerAgendamento();
      await estado.verificarLoja(keli.id, agora: noite, forcar: true);
      expect(estado.ligado, isTrue);
      expect(c.items, hasLength(1), reason: 'o carrinho mantém-se');
      c.addItem(naHora());
      expect(c.items, hasLength(2));
    });
  });

  group('painel admin (PT-BR): agendados da Keli', () {
    test('a linha sabe que é uma casa de festas (restaurant_category)', () {
      final p = PedidoAgendado.fromJson({
        'id': 'ord-keli-0001',
        'status': 'created',
        'scheduled_for': '2026-11-28T09:00:00Z',
        'restaurant_id': keli.id,
        'restaurant_name': 'Sabores do Brasil - Keli Barbosa',
        'restaurant_category': 'festas',
        'is_partner_store': true,
        'service_type': 'restaurant',
      });
      expect(p.categoriaLoja, 'festas');
      expect(p.parceiro, isTrue);
      expect(p.quando, DateTime.utc(2026, 11, 28, 9));
    });
  });

  group('pausa da Boom! Burger (14:15–19:15)', () {
    test('enche o carrinho, a frase diz "hoje às 19:15" e a 1.ª janela é 19:30', () async {
      await servidor(ServidorFalso(tarde));
      expect(boom.isOpenNow(tarde), isFalse);
      final c = await carrinho(boom, tarde);
      expect(c.lojaFechada, isFalse);
      c.addItem(CartItem(productId: 'boom-classic', name: 'Boom Classic', price: 9.9, quantity: 1));
      expect(c.items, hasLength(1));
      expect(c.agendamentoObrigatorio, isTrue);
      expect(
        boom.avisoAgendarEm(tarde),
        'Esta loja está fechada agora. Abre hoje às 19:15 e fecha às 22:15. '
        'Podes marcar o teu pedido para hoje ou para outro dia.',
      );
      final janela = await primeiraJanelaDe(boom, tarde);
      expect(janela.dia, DateTime.utc(2026, 11, 27));
      expect(janela.horas, '19:30–20:00');
    });
  });
}
