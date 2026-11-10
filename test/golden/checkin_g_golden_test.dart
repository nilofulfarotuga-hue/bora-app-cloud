// Golden tests do Bloco G (check-in a fundo, fechar-tudo-2026-11-10).
//
// Os PNG de referência NÃO vêm com este ficheiro: gera-os o Juiz no Flutter do CI com
//     flutter test --update-goldens test/golden/checkin_g_golden_test.dart
// (ficam em test/golden/goldens/checkin_g_*.png). Até lá o matchesGoldenFile falha
// por falta do ficheiro — de propósito, para ninguém dar a tela por vista sem a ver.
// A fábrica de fotos (fotografaTela) falha logo com qualquer estouro (overflow) e
// grava a foto em test/golden/_fotos/ para o juiz de visão.
// As fotos dos prémios são URLs que não abrem no teste: aparece o ícone de reserva.
import 'package:bora_app/screens/admin/admin_checkin_regras_screen.dart';
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/services/checkin_service.dart';
import 'package:bora_app/widgets/checkin/checkin_caminho.dart';
import 'package:bora_app/widgets/home/checkin_diario_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fabrica_de_fotos.dart';

const _marcos = <Map<String, dynamic>>[
  {'chave': 'semana', 'dia': 7, 'tipo': 'tokens', 'titulo': 'os tokens do Dia 7', 'tokens': 40},
  {'chave': 'leonidas_barra', 'dia': 8, 'tipo': 'produto', 'titulo': 'uma barra de chocolate Leonidas', 'valor_cents': 280, 'foto_url': 'https://exemplo.invalid/barra.jpg', 'loja_nome': 'Leonidas'},
  {'chave': 'bk_double', 'dia': 11, 'tipo': 'produto', 'titulo': 'um Double Cheeseburger do Burger King', 'valor_cents': 481, 'loja_nome': 'Burger King'},
  {'chave': 'salgados', 'dia': 14, 'tipo': 'produto', 'titulo': '2 salgados da Keli', 'valor_cents': 630, 'foto_url': 'https://exemplo.invalid/salgados.jpg', 'loja_nome': 'Sabores do Brasil'},
  {'chave': 'acai', 'dia': 19, 'tipo': 'produto', 'titulo': 'um açaí do Goola', 'valor_cents': 922, 'foto_url': 'https://exemplo.invalid/acai.jpg', 'loja_nome': 'Goola Açaí'},
  {'chave': 'boom_mes', 'dia': 28, 'tipo': 'produto', 'titulo': 'o hambúrguer do mês da Boom', 'valor_cents': 1610, 'loja_nome': 'Boom! Burger'},
  {'chave': 'mes', 'dia': 30, 'tipo': 'servico', 'titulo': '2 horas de limpeza ou uma lavagem exterior do carro'},
];

Map<String, dynamic> _estado({
  int dias = 16,
  List<int> perdoados = const [9],
  bool precisaPedido = false,
  Map<String, dynamic>? escada,
}) =>
    {
      'ok': true,
      'marcos_ativos': true,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': dias,
      'hoje_feito': false,
      'tokens_por_dia': [5, 5, 10, 10, 15, 15, 40],
      'marcos': _marcos,
      'precisa_pedido': precisaPedido,
      'perdao': {'ativo': true, 'por_mes': 1, 'usados_mes': perdoados.length, 'disponivel': false, 'pendente': false, 'dias': perdoados},
      'lembrete': {'ligado': true, 'hora': 9},
      'escada': escada ?? {'ativa': true, 'texto': ''},
      'texto': '',
      'vales': const [],
      'novos': const [],
    };

const _semana = CheckinEstado(
  enabled: true,
  eligible: true,
  reason: null,
  alreadyDone: false,
  streakDay: 3,
  tokensToday: 10,
  nextDay: 3,
  nextReward: 10,
  rewards: [5, 5, 10, 10, 15, 15, 40],
);

Widget _cartao(Map<String, dynamic> json) => Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CheckinDiarioCard(
          carregar: () async => _semana,
          carregarPremios: () async => CheckinPremiosEstado.fromJson(json),
          marcarVistos: (_) async {},
          abrirPremios: (_) async {},
          festaEscada: () async {},
          marcarPerdaoVisto: () async {},
          definirLembrete: (_) async => true,
        ),
      ),
    );

Future<void> _abrirMes(WidgetTester t) async {
  await t.pump();
  await t.tap(find.byKey(const Key('btn_checkin_mes')));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final tamanho in [('pequeno', kEcraPequeno), ('medio', kEcraMedio)]) {
    testWidgets('cartão da home com o mês aberto (caminho, barra, perdão) — ${tamanho.$1}', (t) async {
      await fotografaTela(
        t,
        nome: 'checkin_g_cartao_mes',
        tamanho: tamanho,
        tela: _cartao(_estado()),
        interagir: _abrirMes,
      );
      expect(find.byKey(const Key('checkin_mes_calendario')), findsOneWidget);
      expect(find.byKey(const Key('checkin_barra_proximo')), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkin_g_cartao_mes_${tamanho.$1}.png'));
      await t.pumpAndSettle();
    });
  }

  testWidgets('festa do degrau com o prémio em grande (sem pedido pago)', (t) async {
    await fotografaTela(
      t,
      nome: 'checkin_g_festa',
      tamanho: ('medio', kEcraMedio),
      tela: _cartao(_estado(
        dias: 14,
        precisaPedido: true,
        escada: {
          'ativa': true,
          'texto': 'Em cada sequência levas UM prémio: o mais valioso a que chegares. «Quero este» leva o prémio e a escada dos prémios volta ao dia 1 (os tokens de cada dia continuam). «Continuar» troca por um prémio maior.',
          'guardado': {
            'chave': 'salgados', 'dia': 14, 'titulo': '2 salgados da Keli', 'tipo': 'produto', 'valor_cents': 630,
            'loja_nome': 'Sabores do Brasil', 'foto_url': 'https://exemplo.invalid/salgados.jpg',
            'guardado_em': '2026-11-10T10:00:00+00:00', 'garantido_ate': '2026-12-10T10:00:00+00:00',
          },
          'decisao': 'pendente',
          'pendente_decisao': true,
          'pode_continuar': true,
          'proximo_maior': {'chave': 'acai', 'dia': 19, 'titulo': 'um açaí do Goola', 'faltam': 5, 'foto_url': 'https://exemplo.invalid/acai.jpg'},
        },
      )),
    );
    expect(find.byKey(const Key('checkin_escada_escolha')), findsOneWidget);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkin_g_festa.png'));
  });

  testWidgets('caminho dos 30 dias em 320 px', (t) async {
    final e = CheckinPremiosEstado.fromJson(_estado(dias: 12));
    await fotografaTela(
      t,
      nome: 'checkin_g_caminho',
      tamanho: ('pequeno', kEcraPequeno),
      tela: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CheckinCaminho(dias: diasDoCaminho(e, feitoAte: 12, hoje: 13)),
        ),
      ),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkin_g_caminho.png'));
  });

  testWidgets('painel: regras do check-in com o aviso dos 80%', (t) async {
    await fotografaTela(
      t,
      nome: 'checkin_g_admin_regras',
      tamanho: ('medio', kEcraMedio),
      tela: AdminCheckinRegrasScreen(
        carregar: () async => {
          'definicoes': {
            for (final r in kRegrasCheckin)
              r.chave: {
                'valor': r.numero ? (r.euros ? 10000 : (r.chave.endsWith('pct') ? 80 : 3)) : !r.chave.contains('tvde') && !r.chave.contains('semana'),
                'descricao': r.explicacao,
              },
          },
          'mes': '2026-11',
          'custo_mes_cents': 8500,
          'tecto_ativo': true,
          'tecto_cents': 10000,
          'aviso_pct': 80,
          'pct_usado': 85,
          'aviso': true,
          'por_dia': [
            {'dia': 1, 'pessoas': 12},
            {'dia': 5, 'pessoas': 4},
            {'dia': 11, 'pessoas': 1},
            {'dia': 19, 'pessoas': 1},
          ],
          'premios': {'guardados_escada': 5, 'a_espera_pedido': 2, 'guardados_teto': 0, 'por_usar': 3, 'levantados_mes': 2, 'usados_mes': 0},
          'perdoes_mes': 1,
          'lembretes_hoje': 14,
          'lembretes_desligados': 1,
          'degraus': [
            {'chave': 'salgados', 'dia': 14, 'tipo': 'produto', 'titulo': '2 salgados da Keli', 'valor_cents': 630, 'custo_cents': 540, 'loja_nome': 'Sabores do Brasil', 'ativo': true},
            {'chave': 'desconto_continente_3', 'dia': 10, 'tipo': 'desconto', 'titulo': '3 € de desconto no Continente', 'valor_cents': 300, 'custo_cents': 300, 'loja_nome': 'Continente', 'ativo': false},
          ],
          'descontos': {'total': 6, 'ligados': 0},
        },
        definir: (_, __) async {},
        editarDegrau: (_, __) async {},
      ),
    );
    expect(find.byKey(const Key('admin_checkin_tecto_aviso')), findsOneWidget);
    expect(find.text('Atenção: o custo dos prêmios já está em 85% do teto.'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/checkin_g_admin_regras.png'));
  });
}
