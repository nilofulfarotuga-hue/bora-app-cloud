import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/services/oferta_trabalho_aviso.dart';
import 'package:bora_app/stores/handyman_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CASA E MANUTENÇÃO — lado do PROFISSIONAL (missão casa-manutencao-2026-10-30).
/// Peças puras e derivados do store, sem rede.

CasaPerfil _perfil({
  String estado = 'approved',
  List<Map<String, dynamic>> oficios = const [],
  List<Map<String, dynamic>> documentos = const [],
  double pct = 15,
  String? semComissaoAte,
}) =>
    CasaPerfil.fromJson({
      'perfil': {
        'id': 'pro-1',
        'name': 'Zé',
        'approval_status': estado,
        if (semComissaoAte != null) 'sem_comissao_ate': semComissaoAte,
      },
      'oficios': oficios,
      'documentos': documentos,
      'comissao_pct': pct,
    });

CasaOferta _oferta({
  String id = 'ped-1',
  String tipo = 'oferta',
  bool jaOrcei = false,
  DateTime? expira,
  int? ganho = 2550,
}) =>
    CasaOferta.fromJson({
      'pedido_id': id,
      'tipo': tipo,
      'oficio': 'montagem',
      'oficio_nome': 'Montagem de móveis',
      'servico_nome': 'Montar roupeiro',
      'modo': tipo == 'convite_orcamento' ? 'orcamento' : 'fixo',
      'localidade': 'Guarda',
      'distancia_km': 3.24,
      'scheduled_at': '2026-11-08T10:00:00Z',
      'ganho_cents': ganho,
      'total_cents': 3000,
      'expira_em': (expira ?? DateTime.now().add(const Duration(minutes: 5)))
          .toUtc()
          .toIso8601String(),
      'orcamentos_recebidos': 1,
      'ja_orcei': jaOrcei,
    });

CasaPedido _pedido({String estado = 'em_curso', List<String> fotos = const []}) =>
    CasaPedido.fromJson({
      'id': 'ped-9',
      'estado': estado,
      'servico_nome': 'Trocar sifão',
      'ganho_cents': 2000,
      'total_cents': 2400,
      'payment_method': 'cash',
      'fotos': [
        for (var i = 0; i < fotos.length; i++)
          {'id': 'f$i', 'tipo': fotos[i], 'storage_path': 'u/ped-9/${fotos[i]}_$i.jpg'},
      ],
    });

void main() {
  group('o aviso da Casa (casa_offer → casa)', () {
    test('categoria, tipo, RPC e parâmetros da recusa', () {
      expect(categoriaDaOfertaDeTrabalho('casa_offer'), 'casa');
      expect(categoriaDaOfertaDeTrabalho('casa_status'), isNull,
          reason: 'o estado não é oferta (não toca com Aceitar/Recusar)');
      expect(tipoDaOfertaDeTrabalho('casa'), 'casa_offer');
      expect(rpcRecusarOfertaDeTrabalho('casa'), 'casa_recusar_oferta');
      // A RPC da Casa recebe p_pedido_id; as outras ficam como estavam.
      expect(paramsRecusarOfertaDeTrabalho('casa', 'x'), {'p_pedido_id': 'x'});
      expect(paramsRecusarOfertaDeTrabalho('limpeza', 'x'), {'p_booking_id': 'x'});
      expect(paramsRecusarOfertaDeTrabalho('lavagem', 'x'), {'p_booking_id': 'x'});
      // O que já existia não mudou.
      expect(tipoDaOfertaDeTrabalho('lavagem'), 'carwash_offer');
      expect(tipoDaOfertaDeTrabalho('limpeza'), 'cleaning_offer');
      expect(rpcRecusarOfertaDeTrabalho('limpeza'), 'cleaner_reject_booking');
      expect(rpcRecusarOfertaDeTrabalho('lavagem'), 'washer_reject_booking');
    });

    test('o código da app trata casa_offer e casa_status como a limpeza', () {
      final app = File('lib/services/notification_service.dart').readAsStringSync();
      final i = app.indexOf("case 'casa_offer':");
      expect(i, isNonNegative);
      final ramo = app.substring(i, app.indexOf("case 'tvde_chat':", i));
      expect(ramo, contains("case 'casa_status':"));
      expect(ramo, contains('textoDoAvisoDeTrabalho('));
      expect(ramo, contains("categoria: 'casa'"));
      expect(ramo, contains("'🔧 Bora Casa'"));
      final p = app.indexOf('const Set<String> _kPersistentCategoryTypes');
      final lista = app.substring(p, app.indexOf('};', p));
      expect(lista, contains("'casa_offer'"));
      expect(lista, contains("'casa_status'"));
      expect(app, contains("'casa_status' => 'casa'"),
          reason: 'tocar no aviso de estado abre o trabalho da Casa');
      expect(app, contains("'casa_offer': 'casa'"));
      expect(app, contains('paramsRecusarOfertaDeTrabalho(categoria, bookingId)'));
    });
  });

  group('valores e caminhos', () {
    test('euros escritos → cêntimos', () {
      expect(casaEurosParaCents('25'), 2500);
      expect(casaEurosParaCents('25,5'), 2550);
      expect(casaEurosParaCents('25,50 €'), 2550);
      expect(casaEurosParaCents('25.50'), 2550);
      expect(casaEurosParaCents('0'), isNull);
      expect(casaEurosParaCents('abc'), isNull);
      expect(casaEurosParaCents('12,345'), isNull);
      expect(casaEurosParaCents(''), isNull);
    });

    test('caminhos nos baldes privados (contrato)', () {
      expect(kCasaBaldeDocumentos, 'handyman-documents');
      expect(kCasaBaldeFotos, 'casa-fotos');
      expect(casaCaminhoDocumento('u1', 'seguro_acidentes', 'jpg', 42),
          'u1/seguro_acidentes_42.jpg');
      expect(casaCaminhoFoto('u1', 'ped-1', 'depois', 42), 'u1/ped-1/depois_42.jpg');
      expect(casaDataIso(DateTime(2027, 3, 9)), '2027-03-09');
    });

    test('erros do servidor em PT-PT, pelo código curto', () {
      expect(casaErroTexto(const PostgrestException(message: 'foto_depois_em_falta')),
          contains('foto'));
      expect(casaErroTexto(const PostgrestException(message: 'valores_por_autorizar')),
          contains('aprovados'));
      expect(casaErroTexto(const PostgrestException(message: 'casa_desligada')),
          contains('não está ligada'));
      expect(casaErroTexto(TimeoutException('x')), contains('Sem rede'));
      expect(casaErroTexto(Exception('qualquer coisa')),
          'Não foi possível concluir. Tenta outra vez.');
      expect(casaFalhaDeRede(TimeoutException('x')), isTrue);
      expect(casaFalhaDeRede(const PostgrestException(message: 'estado_invalido')),
          isFalse);
    });
  });

  group('o trabalho: passos e fotos', () {
    test('um botão por estado; terminado não tem botão', () {
      expect(casaProximoPasso(CasaEstado.aceite)?.para, 'a_caminho');
      expect(casaProximoPasso(CasaEstado.aCaminho)?.para, 'chegou');
      expect(casaProximoPasso(CasaEstado.chegou)?.para, 'em_curso');
      expect(casaProximoPasso(CasaEstado.emCurso)?.para, 'concluido');
      expect(casaProximoPasso(CasaEstado.concluido), isNull);
      expect(casaProximoPasso(CasaEstado.cancelado), isNull);
      for (final p in kCasaPassosValidos) {
        expect(const {'a_caminho', 'chegou', 'em_curso', 'concluido'}, contains(p));
      }
    });

    test('concluir exige pelo menos uma foto de depois', () {
      expect(casaPodeConcluir(_pedido(fotos: const ['antes'])), isFalse);
      expect(casaPodeConcluir(_pedido(fotos: const ['antes', 'depois'])), isTrue);
    });

    test('o store recusa concluir sem foto de depois sem ir ao servidor', () async {
      final s = HandymanStore();
      s.debugDefinir(perfil: _perfil(), trabalhos: [_pedido(fotos: const ['antes'])]);
      final ok = await s.avancar('ped-9', 'concluido');
      expect(ok, isFalse);
      expect(s.lastError, contains('foto'));
      // Passo que não existe também não sai.
      expect(await s.avancar('ped-9', 'voar'), isFalse);
    });
  });

  group('ofertas no store', () {
    test('só aparecem a profissional aprovado', () {
      final s = HandymanStore();
      s.debugDefinir(perfil: _perfil(estado: 'pending'), ofertas: [_oferta()]);
      expect(s.ofertasParaAviso(), isEmpty);
      s.debugDefinir(perfil: _perfil());
      expect(s.ofertasParaAviso().map((o) => o.pedidoId), ['ped-1']);
    });

    test('expiradas e convites já orçados não tocam; convites ficam à parte', () {
      final s = HandymanStore();
      s.debugDefinir(perfil: _perfil(), ofertas: [
        _oferta(id: 'a'),
        _oferta(id: 'b', expira: DateTime.now().subtract(const Duration(minutes: 1))),
        _oferta(id: 'c', tipo: 'convite_orcamento', ganho: null),
        _oferta(id: 'd', tipo: 'convite_orcamento', ganho: null, jaOrcei: true),
      ]);
      expect(s.ofertasVivas().map((o) => o.pedidoId), ['a']);
      expect(s.convitesAbertos().map((o) => o.pedidoId), ['c', 'd']);
      expect(s.ofertasParaAviso().map((o) => o.pedidoId), ['a', 'c']);
      expect(s.ofertaPorId('c')?.convite, isTrue);
    });

    test('o trabalho ativo manda (regra 1.24); o histórico fica à parte', () {
      final s = HandymanStore();
      s.debugDefinir(perfil: _perfil(), trabalhos: [
        _pedido(estado: 'confirmado'),
        CasaPedido.fromJson(const {'id': 'ativo', 'estado': 'a_caminho'}),
      ]);
      expect(s.trabalhoAtivo?.id, 'ativo');
      expect(s.historico.map((p) => p.estado), [CasaEstado.confirmado]);
    });

    test('reset esquece tudo', () {
      final s = HandymanStore();
      s.debugDefinir(perfil: _perfil(), ofertas: [_oferta()]);
      s.reset();
      expect(s.perfil, isNull);
      expect(s.ofertas, isEmpty);
      expect(s.ofertasParaAviso(), isEmpty);
    });
  });

  group('comissão, documentos e validades', () {
    test('a comissão em palavras, com o que o servidor diz', () {
      final hoje = DateTime(2026, 11, 1);
      expect(casaTextoComissao(15, null, agora: hoje),
          'O Bora fica com 15% de cada trabalho concluído. O resto é teu.');
      expect(casaTextoComissao(15, DateTime(2026, 12, 31), agora: hoje),
          'Sem comissão até 31/12. Depois, o Bora fica com 15% de cada trabalho concluído.');
      // Promoção já passada → volta ao texto normal.
      expect(casaTextoComissao(15, DateTime(2026, 10, 1), agora: hoje),
          startsWith('O Bora fica com 15%'));
      expect(casaPct(12.5), '12,5');
    });

    test('o que falta: recusado, em falta por ofício e caducado', () {
      final p = _perfil(
        oficios: const [
          {'codigo': 'montagem', 'nome': 'Montagem', 'fase': 1, 'estado': 'approved'},
          {
            'codigo': 'eletricidade',
            'nome': 'Eletricidade',
            'fase': 2,
            'documento_exigido': 'dgeg_eletricidade',
            'estado': 'pending',
          },
        ],
        documentos: const [
          {
            'id': 'd1',
            'tipo': 'cartao_cidadao',
            'estado': 'approved',
            'validade': '2020-01-01',
            'created_at': '2026-10-30T10:00:00Z',
          },
          {
            'id': 'd2',
            'tipo': 'seguro_acidentes',
            'estado': 'rejected',
            'motivo': 'Ilegível',
            'created_at': '2026-10-30T10:00:00Z',
          },
        ],
      );
      final faltas = casaDocumentosEmFalta(p, agora: DateTime(2026, 11, 1));
      final porTipo = {for (final f in faltas) f.tipo: f};
      expect(porTipo['cartao_cidadao']?.razao, 'caducado');
      expect(porTipo['seguro_acidentes']?.razao, 'recusado');
      expect(porTipo['seguro_acidentes']?.explicacao, contains('Ilegível'));
      expect(porTipo['dgeg_eletricidade']?.razao, 'em_falta');
      expect(porTipo['dgeg_eletricidade']?.oficio, 'eletricidade');
      expect(faltas.length, 3);
    });

    test('o documento mais recente é o que conta', () {
      final docs = casaDocumentosAtuais([
        CasaDocumento.fromJson(const {
          'id': 'velho',
          'tipo': 'seguro_acidentes',
          'estado': 'rejected',
          'created_at': '2026-10-01T10:00:00Z',
        }),
        CasaDocumento.fromJson(const {
          'id': 'novo',
          'tipo': 'seguro_acidentes',
          'estado': 'pending',
          'created_at': '2026-10-20T10:00:00Z',
        }),
      ]);
      expect(docs.single.id, 'novo');
    });

    test('dias para caducar', () {
      final hoje = DateTime(2026, 11, 1);
      expect(casaDiasParaCaducar(DateTime(2026, 11, 11), agora: hoje), 10);
      expect(casaDiasParaCaducar(DateTime(2026, 10, 31), agora: hoje), -1);
      expect(casaDiasParaCaducar(null, agora: hoje), isNull);
    });
  });

  group('disponibilidade e ganhos (JSON do contrato)', () {
    test('janela semanal: 0 = domingo, HH:MM', () {
      final s = CasaSlot.fromJson(const {'weekday': 0, 'start': '09:00:00', 'end': '13:00'});
      expect(s.weekday, 0);
      expect(s.start, '09:00');
      expect(s.toJson(), {'weekday': 0, 'start': '09:00', 'end': '13:00'});
      expect(casaNomeDoDia(0), 'Domingo');
      expect(casaNomeDoDia(6), 'Sábado');
    });

    test('casa_meus_ganhos lê semana, acertos e trabalhos', () {
      final g = CasaGanhos.fromJson(const {
        'semana': {
          'inicio': '2026-10-27',
          'fim': '2026-11-02',
          'trabalhos': 3,
          'bruto_cents': 10000,
          'comissao_cents': 1500,
          'ganho_cents': 8500,
          'recebido_em_mao_cents': 4000,
          'a_receber_cents': 4500,
        },
        'acertos': [
          {'id': 'a1', 'total_jobs': 2, 'net_payout_cents': 3000, 'status': 'paid'},
        ],
        'trabalhos': [
          {'id': 't1', 'servico_nome': 'Montar roupeiro', 'ganho_cents': 2550, 'payment_method': 'cash'},
        ],
      });
      expect(g.ganhoCents, 8500);
      expect(g.aReceberCents, 4500);
      expect(g.acertos.single.pago, isTrue);
      expect(g.lista.single.ganhoCents, 2550);
    });
  });
}
