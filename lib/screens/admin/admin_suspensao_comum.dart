import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/prestador_suspensao_service.dart';

/// Painel (PT-BR) — "Suspender com motivo" igual em todas as fichas de
/// prestador (entregador, limpeza, lavagem, Casa, parceiro, serviço).
///
/// Missão app-fechar-2026-11-01, bloco B8 (Diretiva (UE) 2024/2831, art. 11.º):
/// toda suspensão tem motivo escrito (mínimo 10 letras), quem decidiu (a conta
/// de admin), a data e até quando. Chama `admin_suspender_prestador`, que grava
/// o registo em `prestador_suspensoes` e aplica o estado na tabela certa.
/// O erro do servidor aparece DENTRO do diálogo (PADRAO_BORA 3.15 — 2).

/// O que a pessoa escolheu no diálogo.
class MotivoSuspensaoResultado {
  const MotivoSuspensaoResultado({
    required this.tipo,
    required this.motivo,
    this.ate,
  });

  /// suspensao_temporaria | suspensao | encerramento | restricao
  final String tipo;
  final String motivo;
  final DateTime? ate;
}

/// Tipos que o painel oferece (os mesmos de `admin_suspender_prestador`).
const List<(String, String)> kTiposSuspensaoPainel = [
  ('suspensao_temporaria', 'Suspensão temporária (com data de fim)'),
  ('suspensao', 'Suspensão sem data de fim'),
  ('encerramento', 'Encerrar a conta'),
  ('restricao', 'Restrição (só registra, não desliga a conta)'),
];

/// Estafeta/motorista: os mesmos tipos do painel. 02/11/2026 (zerar B4): a
/// correção do servidor está aplicada desde 01/11 (20261101230323) — a
/// manutenção de hora a hora (`prestador_suspensoes_manutencao`) levanta o
/// `is_banned` do estafeta quando a data de fim passa, por isso a temporária
/// volta a ser oferecida.
const List<(String, String)> kTiposSuspensaoEstafeta = kTiposSuspensaoPainel;

/// Só "desativar" (interruptor de loja/barbearia): suspensão sem data de fim.
const List<(String, String)> kTipoDesativar = [
  ('suspensao', 'Desativar (suspensão sem data de fim)'),
];

/// Chama o servidor com o que foi escolhido. Devolve a mensagem de erro (para
/// mostrar no diálogo) ou `null` se correu bem.
typedef ConfirmarSuspensao = Future<String?> Function(
    MotivoSuspensaoResultado resultado);

/// Diálogo PT-BR: tipo, até quando (só na temporária) e motivo (≥ 10 letras).
class DialogoSuspenderComMotivo extends StatefulWidget {
  const DialogoSuspenderComMotivo({
    super.key,
    this.titulo = 'Suspender com motivo',
    this.nome,
    this.tipos = kTiposSuspensaoPainel,
    this.tipoInicial = 'suspensao_temporaria',
    this.aoConfirmar,
    this.rotuloConfirmar = 'Suspender',
  });

  final String titulo;

  /// Nome do prestador, para a pessoa ter a certeza de quem é.
  final String? nome;
  final List<(String, String)> tipos;
  final String tipoInicial;

  /// Se vier, corre aqui dentro e o diálogo só fecha quando der certo.
  final ConfirmarSuspensao? aoConfirmar;
  final String rotuloConfirmar;

  @override
  State<DialogoSuspenderComMotivo> createState() =>
      _DialogoSuspenderComMotivoState();
}

class _DialogoSuspenderComMotivoState extends State<DialogoSuspenderComMotivo> {
  late String _tipo = widget.tipos.any((t) => t.$1 == widget.tipoInicial)
      ? widget.tipoInicial
      : widget.tipos.first.$1;
  final TextEditingController _motivo = TextEditingController();
  DateTime? _ate;
  String? _erroMotivo;
  String? _erroServidor;
  bool _aEnviar = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final agora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _ate ?? agora.add(const Duration(days: 7)),
      firstDate: agora.add(const Duration(days: 1)),
      lastDate: agora.add(const Duration(days: 365)),
      helpText: 'Suspenso até',
    );
    if (d != null && mounted) {
      // Fim do dia escolhido (23:59, hora do aparelho).
      setState(() => _ate = DateTime(d.year, d.month, d.day, 23, 59));
    }
  }

  Future<void> _confirmar() async {
    final erro = validarMotivoSuspensao(_motivo.text);
    if (erro != null) {
      setState(() => _erroMotivo = erro);
      return;
    }
    if (_tipo == 'suspensao_temporaria' && _ate == null) {
      setState(() => _erroServidor =
          'Escolha até quando (suspensão temporária precisa de data de fim).');
      return;
    }
    final r = MotivoSuspensaoResultado(
      tipo: _tipo,
      motivo: _motivo.text.trim(),
      ate: _tipo == 'suspensao_temporaria' ? _ate : null,
    );
    final confirmar = widget.aoConfirmar;
    if (confirmar == null) {
      Navigator.of(context).pop(r);
      return;
    }
    setState(() {
      _aEnviar = true;
      _erroServidor = null;
    });
    String? erroServidor;
    try {
      erroServidor = await confirmar(r);
    } catch (e) {
      erroServidor = traduzirErroSuspensao(e);
    }
    if (!mounted) return;
    if (erroServidor == null) {
      Navigator.of(context).pop(r);
      return;
    }
    setState(() {
      _aEnviar = false;
      _erroServidor = erroServidor;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.nome != null && widget.nome!.trim().isNotEmpty) ...[
              Text(widget.nome!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: Spacing.sm),
            ],
            const Text(
              'O prestador recebe o motivo por escrito, com a data e até '
              'quando, e pode pedir revisão (uma pessoa responde em 7 dias).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            if (widget.tipos.length > 1)
              DropdownButtonFormField<String>(
                key: const ValueKey('suspensao-tipo'),
                // ignore: deprecated_member_use
                value: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final t in widget.tipos)
                    DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                ],
                onChanged: _aEnviar
                    ? null
                    : (v) => setState(() {
                          _tipo = v ?? _tipo;
                          _erroServidor = null;
                        }),
              ),
            if (_tipo == 'suspensao_temporaria') ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _ate == null
                          ? 'Até quando: escolha a data'
                          : 'Até ${diaEHoraSuspensao(_ate!)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('suspensao-data'),
                    onPressed: _aEnviar ? null : _escolherData,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_ate == null ? 'Escolher' : 'Alterar'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey('suspensao-motivo'),
              controller: _motivo,
              enabled: !_aEnviar,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText:
                    'Motivo (mínimo $kMinLetrasMotivoSuspensao letras, com os fatos)',
                errorText: _erroMotivo,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_erroMotivo != null) setState(() => _erroMotivo = null);
              },
            ),
            if (_erroServidor != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                _erroServidor!,
                key: const ValueKey('suspensao-erro'),
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('suspensao-confirmar'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _aEnviar ? null : _confirmar,
          child: _aEnviar
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.rotuloConfirmar),
        ),
      ],
    );
  }
}

/// Abre o diálogo e chama `admin_suspender_prestador`. Devolve `true` se
/// ficou registado.
Future<bool> suspenderComMotivo(
  BuildContext context, {
  required String tabela,
  required String entidadeId,
  String? nome,
  List<(String, String)> tipos = kTiposSuspensaoPainel,
  String titulo = 'Suspender com motivo',
  String rotuloConfirmar = 'Suspender',
}) async {
  final r = await showDialog<MotivoSuspensaoResultado>(
    context: context,
    builder: (_) => DialogoSuspenderComMotivo(
      titulo: titulo,
      rotuloConfirmar: rotuloConfirmar,
      nome: nome,
      tipos: tipos,
      tipoInicial: tipos.first.$1,
      aoConfirmar: (escolha) async {
        await PrestadorSuspensaoService.suspender(
          tabela: tabela,
          entidadeId: entidadeId,
          tipo: escolha.tipo,
          motivo: escolha.motivo,
          ate: escolha.ate,
        );
        return null;
      },
    ),
  );
  if (r == null) return false;
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text('${rotuloTipoSuspensao(r.tipo)} registrada. O prestador '
          'recebe o motivo e pode pedir revisão (painel → Revisões).'),
    ));
  }
  return true;
}

/// Botão "Suspender com motivo" para as fichas do painel.
class BotaoSuspenderComMotivo extends StatelessWidget {
  const BotaoSuspenderComMotivo({
    super.key,
    required this.tabela,
    required this.entidadeId,
    this.nome,
    this.onFeito,
    this.tipos = kTiposSuspensaoPainel,
  });

  /// drivers | cleaners | washers | casa_profissionais | restaurants |
  /// service_providers
  final String tabela;
  final String entidadeId;
  final String? nome;
  final VoidCallback? onFeito;
  final List<(String, String)> tipos;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: ValueKey('suspender-com-motivo-$tabela'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
      onPressed: () async {
        final ok = await suspenderComMotivo(
          context,
          tabela: tabela,
          entidadeId: entidadeId,
          nome: nome,
          tipos: tipos,
        );
        if (ok) onFeito?.call();
      },
      icon: const Icon(Icons.gavel, size: 18),
      label: const Text('Suspender com motivo'),
    );
  }
}
