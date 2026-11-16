import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_colors.dart';
import '../services/recibo_verde_service.dart';
import '../utils/safe_image_picker.dart';
import 'driver_fiscal_card.dart';

/// Missão 12 recibos-verdes-15-11 (R2): o recibo verde do mês passado, igual
/// nas 4 apps de prestador (estafeta, limpeza, lavagem — pelo ecrã Ganhos — e
/// Casa — pelos ganhos da Casa). Um recibo por pessoa com TODOS os serviços.
///
/// Tudo vem do servidor (`prestador_recibo_mensal_resumo` e
/// `prestador_recibo_trava`); o NIF da Bora nunca está escrito aqui.
/// "Já passei o recibo" obriga a anexar o PDF ou a foto do recibo.
///
/// Servidor antigo (funções novas ainda por aplicar): mostra o cartão antigo
/// só com as entregas ([DriverReciboSecao]). Sem rede: não mostra nada.
class ReciboVerdeSecao extends StatefulWidget {
  const ReciboVerdeSecao({super.key, this.aoMarcar, this.agora});

  /// Chamado depois de o recibo ficar entregue.
  final VoidCallback? aoMarcar;

  /// Para os testes.
  final DateTime? agora;

  @override
  State<ReciboVerdeSecao> createState() => _ReciboVerdeSecaoState();
}

class _ReciboVerdeSecaoState extends State<ReciboVerdeSecao> {
  Map<String, dynamic>? _resumo;
  Map<String, dynamic>? _trava;
  bool _servidorAntigo = false;
  late final int _ano;
  late final int _mes;

  @override
  void initState() {
    super.initState();
    final agora = widget.agora ?? DateTime.now();
    final ant = DateTime(agora.year, agora.month - 1, 1);
    _ano = ant.year;
    _mes = ant.month;
    _carregar();
  }

  Future<void> _carregar() async {
    // O recibo verde começa com o mês de outubro de 2026.
    if (DateTime(_ano, _mes).isBefore(DateTime(2026, 10))) return;
    try {
      final r = await ReciboVerdeService.resumo(_ano, _mes);
      Map<String, dynamic>? t;
      try {
        t = await ReciboVerdeService.trava();
      } catch (e) {
        debugPrint('[ReciboVerdeSecao] trava: $e');
      }
      if (!mounted) return;
      setState(() {
        _resumo = r;
        _trava = t;
      });
    } catch (e) {
      debugPrint('[ReciboVerdeSecao] $e');
      if (ReciboVerdeService.faltaFuncaoNoServidor(e) && mounted) {
        setState(() => _servidorAntigo = true);
      }
    }
  }

  /// Anexa o recibo de [ano]/[mes] (por defeito o mês passado). Quem está
  /// retido por um mês mais antigo anexa ESSE mês (Juiz 15/11, achado 1).
  Future<void> _marcar({int? ano, int? mes, String? nome}) async {
    final ok = await anexarReciboVerde(context,
        ano: ano ?? _ano,
        mes: mes ?? _mes,
        nomeMes: nome ?? (_resumo?['nome_mes'] ?? '').toString());
    if (ok) {
      await _carregar();
      widget.aoMarcar?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_servidorAntigo) return DriverReciboSecao(aoMarcar: widget.aoMarcar);
    final r = _resumo;
    final t = _trava;
    if (r == null) return const SizedBox.shrink();
    final p = r['prestador'] is Map
        ? Map<String, dynamic>.from(r['prestador'] as Map)
        : null;
    final retido = t != null && t['retido'] == true;
    final precisa =
        p != null && p['precisa_recibo'] == true && p['estado'] != 'entregue';
    if (!retido && !precisa) {
      if (p != null && p['estado'] == 'entregue') {
        return Padding(
          key: const Key('recibo_verde_entregue'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    'Recibo de ${r['nome_mes'] ?? 'mês passado'} entregue',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (retido) ReciboRetidoAviso(trava: t),
        if (precisa)
          ReciboVerdeCard(
            resumo: r,
            prestador: p,
            onMarcar: _marcar,
          ),
        // Meses em falta que não são o do cartão acima: um botão por mês.
        if (retido)
          ReciboMesesEmFaltaBotoes(
            trava: t,
            excluirAno: precisa ? _ano : null,
            excluirMes: precisa ? _mes : null,
            onAnexar: (a, m, n) => _marcar(ano: a, mes: m, nome: n),
          ),
      ],
    );
  }
}

/// Um botão "Anexar o recibo de <mês>" por cada mês em falta que a trava
/// devolve (`meses_em_falta`), menos o mês que o cartão já mostra.
class ReciboMesesEmFaltaBotoes extends StatelessWidget {
  const ReciboMesesEmFaltaBotoes({
    super.key,
    required this.trava,
    required this.onAnexar,
    this.excluirAno,
    this.excluirMes,
  });

  final Map<String, dynamic> trava;
  final int? excluirAno;
  final int? excluirMes;
  final void Function(int ano, int mes, String nome) onAnexar;

  static int? _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  @override
  Widget build(BuildContext context) {
    final meses = <(int, int, String)>[];
    for (final m in (trava['meses_em_falta'] as List?) ?? const []) {
      if (m is! Map) continue;
      final a = _int(m['ano']);
      final mm = _int(m['mes']);
      if (a == null || mm == null) continue;
      if (a == excluirAno && mm == excluirMes) continue;
      meses.add((a, mm, '${m['nome'] ?? '$mm/$a'}'));
    }
    if (meses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (a, mm, nome) in meses)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              key: Key('recibo_verde_anexar_$a-$mm'),
              onPressed: () => onAnexar(a, mm, nome),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Anexar o recibo de $nome'),
            ),
          ),
      ],
    );
  }
}

String _eurCents(dynamic cents) {
  final n =
      cents is num ? cents.toDouble() : double.tryParse('${cents ?? ''}') ?? 0;
  return '${(n / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
}

String _eur(dynamic v) {
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return '${n.toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// "O teu pagamento fica guardado até anexares o recibo…" com o valor por
/// pagar em número grande (regra do ganho do prestador em destaque).
class ReciboRetidoAviso extends StatelessWidget {
  const ReciboRetidoAviso({super.key, required this.trava});

  final Map<String, dynamic> trava;

  @override
  Widget build(BuildContext context) {
    final porPagar = trava['por_pagar'] is Map
        ? (trava['por_pagar'] as Map)['total_cents']
        : null;
    final meses = (trava['meses_em_falta'] as List?) ?? const [];
    return Card(
      key: const Key('recibo_verde_retido'),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pagamento guardado',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (porPagar != null && porPagar != 0) ...[
              const SizedBox(height: 4),
              Text(_eurCents(porPagar),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary)),
            ],
            const SizedBox(height: 6),
            Text('${trava['texto_app'] ?? ''}'),
            if (meses.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Em falta: ${meses.map((m) => m is Map ? m['nome'] : m).join(', ')}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cartão do recibo verde do mês: total em grande, linhas por serviço, a quem
/// se passa o recibo (com copiar o NIF), a descrição pronta a copiar e o prazo.
class ReciboVerdeCard extends StatelessWidget {
  const ReciboVerdeCard({
    super.key,
    required this.resumo,
    required this.prestador,
    required this.onMarcar,
  });

  final Map<String, dynamic> resumo;
  final Map<String, dynamic> prestador;
  final VoidCallback onMarcar;

  @override
  Widget build(BuildContext context) {
    final p = prestador;
    final regras = resumo['regras'] is Map
        ? Map<String, dynamic>.from(resumo['regras'] as Map)
        : const <String, dynamic>{};
    final adq = resumo['adquirente'] is Map
        ? Map<String, dynamic>.from(resumo['adquirente'] as Map)
        : const <String, dynamic>{};
    final adqNome = (adq['nome'] ?? '').toString();
    final adqNif = (adq['nif'] ?? '').toString().trim();
    final linhas = (p['linhas'] as List?) ?? const [];
    final descricao = (p['descricao'] ?? '').toString();
    final semPdf = p['estado'] == 'sem_pdf';
    return Card(
      key: const Key('recibo_verde_card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recibo verde de ${resumo['nome_mes'] ?? 'mês passado'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(_eur(p['total']),
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary)),
            for (final l in linhas)
              if (l is Map)
                Text('${l['nome']}: ${l['quantidade']} · ${_eur(l['valor'])}',
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black54)),
            if (adqNome.isNotEmpty || adqNif.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('recibo_verde_adquirente'),
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Passa o recibo a $adqNome${adqNif.isEmpty ? '' : ', NIF $adqNif'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (adqNif.isNotEmpty)
                      IconButton(
                        tooltip: 'Copiar NIF',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: adqNif));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('NIF copiado.')));
                        },
                      ),
                  ],
                ),
              ),
            ],
            if (descricao.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(descricao, style: const TextStyle(fontSize: 13)),
            ],
            for (final k in ['iva_texto', 'prazo_texto', 'anexar_texto'])
              if ((regras[k] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${regras[k]}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
            if (semPdf) ...[
              const SizedBox(height: 6),
              const Text('Falta anexar o PDF ou a foto do recibo.',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.deepOrange)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (descricao.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: descricao));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Texto copiado.')));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar texto'),
                  ),
                FilledButton(
                  key: const Key('recibo_verde_marcar'),
                  onPressed: onMarcar,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Já passei o recibo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Já passei o recibo": número, data e PDF/foto (ficheiro ou câmara)
/// obrigatórios; envia o ficheiro e depois marca. true = recibo entregue.
Future<bool> anexarReciboVerde(BuildContext context,
    {required int ano, required int mes, String nomeMes = ''}) async {
  final ctrl = TextEditingController();
  Uint8List? bytes;
  String? nome;
  String? erro;
  bool enviando = false;
  var data = DateTime.now();
  String dataTexto(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> escolher() async {
          try {
            final r = await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: ReciboVerdeService.extensoes,
              withData: true,
            );
            final f = (r == null || r.files.isEmpty) ? null : r.files.first;
            if (f == null) return;
            if (f.bytes == null) {
              setD(() =>
                  erro = 'Não foi possível ler o ficheiro. Tenta outra vez.');
              return;
            }
            setD(() {
              bytes = f.bytes;
              nome = f.name;
              erro = null;
            });
          } catch (_) {
            setD(() =>
                erro = 'Não foi possível abrir os ficheiros. Tenta outra vez.');
          }
        }

        Future<void> fotografar() async {
          try {
            // imageQuality/maxWidth fazem a câmara devolver JPEG (também no
            // iPhone, onde grava HEIC).
            final x = await SafeImagePicker.pickImage(
                source: ImageSource.camera, maxWidth: 2200, imageQuality: 85);
            if (x == null) return;
            final b = await x.readAsBytes();
            setD(() {
              bytes = b;
              nome = 'recibo-foto.jpg';
              erro = null;
            });
          } on PlatformException catch (e) {
            setD(() => erro = e.code.contains('denied') ||
                    e.code.contains('access')
                ? 'A app não tem acesso à câmara. Permite o acesso nas definições '
                    'do telemóvel, ou escolhe um ficheiro.'
                : 'Não foi possível abrir a câmara. Tenta outra vez ou escolhe um ficheiro.');
          } catch (_) {
            setD(() => erro = 'Não foi possível ler a foto. Tenta outra vez.');
          }
        }

        Future<void> escolherData() async {
          final hoje = DateTime.now();
          final d = await showDatePicker(
            context: ctx,
            initialDate: data,
            firstDate: DateTime(ano, mes, 1),
            lastDate: hoje,
          );
          if (d != null) setD(() => data = d);
        }

        Future<void> enviar() async {
          if (enviando) return;
          if (ctrl.text.trim().isEmpty) {
            setD(() => erro = 'Escreve o número do recibo verde.');
            return;
          }
          final b = bytes;
          final n = nome;
          if (b == null || n == null) {
            setD(() => erro = 'Anexa o PDF ou a foto do recibo.');
            return;
          }
          setD(() {
            enviando = true;
            erro = null;
          });
          try {
            await ReciboVerdeService.enviarEMarcar(
                ano: ano,
                mes: mes,
                numero: ctrl.text,
                data: data,
                bytes: b,
                nomeFicheiro: n);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setD(() {
              enviando = false;
              erro = ReciboVerdeService.mensagemDoErro(e);
            });
          }
        }

        return AlertDialog(
          title: const Text('Já passei o recibo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('recibo_verde_numero'),
                controller: ctrl,
                decoration: const InputDecoration(
                    labelText: 'N.º do recibo verde (ex.: FR ATSIRE01FR/12)'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('recibo_verde_data'),
                onPressed: enviando ? null : escolherData,
                icon: const Icon(Icons.event, size: 18),
                label: Text('Data do recibo: ${dataTexto(data)}'),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                key: const Key('recibo_verde_escolher'),
                onPressed: enviando ? null : escolher,
                icon: const Icon(Icons.attach_file),
                label: Text(nome == null ? 'Anexar PDF ou foto' : nome!,
                    overflow: TextOverflow.ellipsis),
              ),
              if (!kIsWeb)
                TextButton.icon(
                  key: const Key('recibo_verde_camara'),
                  onPressed: enviando ? null : fotografar,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Tirar foto ao recibo'),
                ),
              if (erro != null) ...[
                const SizedBox(height: 8),
                Text(erro!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: enviando ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              key: const Key('recibo_verde_enviar'),
              onPressed: enviando ? null : enviar,
              child: enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar'),
            ),
          ],
        );
      },
    ),
  );
  // Sem dispose: o diálogo ainda anima a sair com o campo montado (como em
  // marcarReciboPassado).
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nomeMes.isEmpty
            ? 'Recibo entregue. Obrigado!'
            : 'Recibo de $nomeMes entregue. Obrigado!')));
  }
  return ok == true;
}
