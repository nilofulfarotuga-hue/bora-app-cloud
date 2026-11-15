import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/hora_lisboa.dart';
import '_admin_rpc_errors.dart';

/// Missão 12 recibos-verdes-15-11 (R2): "Retido" nos acertos (PT-BR).
///
/// A partir dos recibos de novembro/2026, quem não anexou o recibo verde do
/// mês até ao dia 10 fica com o "Marcar pago" bloqueado pelo servidor. Aqui só
/// se MOSTRA o que o servidor diz em cada linha (`retido`, `retido_motivo`,
/// `retido_solto`, `retido_compensa_divida`) e se oferece "Soltar" com motivo
/// (`admin_soltar_retido_recibo`). Soltar não paga nada e não muda valores.

/// true quando o erro é a trava do recibo verde (`recibo_verde_em_falta:`).
bool eErroReciboVerde(Object e) =>
    e.toString().contains('recibo_verde_em_falta');

/// O motivo legível do erro da trava (sem o prefixo técnico).
String motivoReciboVerde(Object e) {
  final t = e is PostgrestException ? e.message : e.toString();
  final i = t.indexOf('recibo_verde_em_falta:');
  if (i < 0) return 'Falta o recibo verde desta pessoa.';
  final resto = t.substring(i + 'recibo_verde_em_falta:'.length).trim();
  return resto.isEmpty ? 'Falta o recibo verde desta pessoa.' : resto;
}

/// A semana que o servidor pôs no erro (`details` = JSON com `semana`), para
/// os ecrãs que marcam várias semanas de uma vez. '' se não vier.
String semanaDoErroReciboVerde(Object e) {
  if (e is! PostgrestException) return '';
  try {
    final d = jsonDecode(e.details?.toString() ?? '');
    return d is Map ? adminDataSemana(d['semana']) : '';
  } catch (_) {
    return '';
  }
}

/// Pede o motivo e solta a semana. true = solta (o "Marcar pago" já passa).
Future<bool> adminSoltarRetidoRecibo(
  BuildContext context, {
  required String subjectType,
  required String subjectId,
  required String weekStart,
  String? motivoRetido,
}) async {
  final ctrl = TextEditingController();
  String? erro;
  bool aEnviar = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      Future<void> soltar() async {
        if (aEnviar) return;
        if (ctrl.text.trim().length < 5) {
          setD(() => erro = 'Escreva o motivo (5 letras ou mais).');
          return;
        }
        setD(() {
          aEnviar = true;
          erro = null;
        });
        try {
          await Supabase.instance.client
              .rpc('admin_soltar_retido_recibo', params: {
            'p_subject_type': subjectType,
            'p_subject_id': subjectId,
            'p_week_start': weekStart,
            'p_motivo': ctrl.text.trim(),
          });
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setD(() {
            aEnviar = false;
            erro = humanizeAdminRpcError(e);
          });
        }
      }

      return AlertDialog(
        key: const Key('admin_soltar_retido'),
        title: const Text('Soltar o pagamento desta semana'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((motivoRetido ?? '').isNotEmpty)
              Text(motivoRetido!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Soltar deixa marcar "pago" só nesta semana, mesmo sem o recibo '
                'verde (retenção = o pagamento fica guardado). Não paga nada '
                'sozinho e fica na auditoria.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                  labelText: 'Motivo (ex.: recibo chegou por e-mail)'),
            ),
            if (erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(erro!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: aEnviar ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: aEnviar ? null : soltar, child: const Text('Soltar')),
        ],
      );
    }),
  );
  return ok == true;
}

/// Quando o "Marcar pago" falha pela trava: mostra o motivo e oferece Soltar.
/// true = soltou (o chamador recarrega e o admin volta a carregar em pago).
Future<bool> adminOferecerSoltarDepoisDoErro(
  BuildContext context,
  Object erro, {
  required String subjectType,
  required String subjectId,
  required String weekStart,
}) async {
  // Sem pessoa ou sem semana não há o que soltar: só se mostra o motivo.
  final podeSoltar =
      subjectId.isNotEmpty && subjectId != 'null' && weekStart.isNotEmpty;
  final querSoltar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pagamento retido'),
      content: Text('${motivoReciboVerde(erro)}\n\nPeça o recibo à pessoa'
          '${podeSoltar ? ' ou solte esta semana com um motivo.' : '.'}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fechar')),
        if (podeSoltar)
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Soltar')),
      ],
    ),
  );
  if (querSoltar != true || !context.mounted) return false;
  return adminSoltarRetidoRecibo(context,
      subjectType: subjectType,
      subjectId: subjectId,
      weekStart: weekStart,
      motivoRetido: motivoReciboVerde(erro));
}

/// A etiqueta da linha: "Retido — falta o recibo…" com o botão Soltar, ou
/// "Solto: motivo", ou nada. Lê só as chaves que o servidor devolve.
class AdminReciboRetidoLinha extends StatelessWidget {
  const AdminReciboRetidoLinha({
    super.key,
    required this.linha,
    required this.subjectType,
    required this.subjectId,
    required this.weekStart,
    required this.aoSoltar,
  });

  final Map<String, dynamic> linha;
  final String subjectType;
  final String subjectId;
  final String weekStart;
  final VoidCallback aoSoltar;

  @override
  Widget build(BuildContext context) {
    final l = linha;
    if (l['retido_erro'] != null) {
      return Text(
          'Retenção do recibo: não consegui calcular (${l['retido_erro']}).',
          style: const TextStyle(fontSize: 12, color: Colors.black54));
    }
    if (l['retido_solto'] == true) {
      return Text('Solto à mão: ${l['retido_solto_motivo'] ?? ''}',
          style: const TextStyle(fontSize: 12, color: Colors.black54));
    }
    if (l['retido_compensa_divida'] == true && l['retido'] != true) {
      return const Text(
          'Sem recibo, mas deve mais do que recebe: passa como acerto de dívida.',
          style: TextStyle(fontSize: 12, color: Colors.black54));
    }
    if (l['retido'] != true) return const SizedBox.shrink();
    return Container(
      key: const Key('admin_recibo_retido'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, size: 16, color: Colors.deepOrange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                '${l['retido_motivo'] ?? 'Retido — falta o recibo verde'}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepOrange)),
          ),
          TextButton(
            onPressed: subjectId.isEmpty || weekStart.isEmpty
                ? null
                : () async {
                    if (await adminSoltarRetidoRecibo(context,
                        subjectType: subjectType,
                        subjectId: subjectId,
                        weekStart: weekStart,
                        motivoRetido: '${l['retido_motivo'] ?? ''}')) {
                      aoSoltar();
                    }
                  },
            child: const Text('Soltar'),
          ),
        ],
      ),
    );
  }
}

/// 'YYYY-MM-DD' (dia de Lisboa) da semana que o servidor pede. Aceita uma
/// data simples ('2026-12-07'), um instante ISO com hora (convertido para o
/// relógio de Lisboa: no verão a meia-noite é 23:00 UTC do dia anterior) ou um
/// DateTime de calendário (lido tal como está).
String adminDataSemana(dynamic v) {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (v is DateTime) return fmt(v);
  final s = (v ?? '').toString().trim();
  if (s.length <= 10) return s;
  final d = DateTime.tryParse(s);
  if (d == null) return s.substring(0, 10);
  return d.isUtc ? fmt(paredeLisboa(d)) : fmt(d);
}
