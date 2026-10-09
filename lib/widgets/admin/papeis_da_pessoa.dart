import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../screens/admin/_admin_rpc_errors.dart';

/// PAPÉIS DESTA PESSOA (painel admin, PT-BR) — ligar e desligar os papéis de
/// trabalho de uma pessoa (estafeta, limpeza, lavagem) a partir de qualquer
/// cartão do painel. Usado na tela das profissionais de limpeza e na aba dos
/// lavadores.
///
/// Servidor (aplicado 09/10/2026, só admin):
///  - `admin_user_roles(p_user_id)` →
///    `{estafeta: {estado, ligado, ja_foi_aprovado} | null,
///      limpeza: {estado} | null, lavagem: {estado} | null}`
///  - `admin_set_user_role(p_user_id, p_papel, p_ativo, p_motivo)` →
///    `{ok:true, papel, antes, depois}` ou `{ok:false, error}`.
///
/// Desligar estafeta = fica `rejected` e offline; desligar limpeza/lavagem =
/// fica `suspended`. Ligar só repõe quem já foi aprovado antes. Tudo fica em
/// `admin_audit_log`. A verdade é o servidor: esta tela não adivinha quem pode
/// ser religado — pergunta e traduz a resposta.

/// Chama uma função do servidor (por omissão `Supabase.instance.client.rpc`).
/// Injetável para os testes não tocarem na rede.
typedef ChamarRpcPainel = Future<dynamic> Function(
    String fn, Map<String, dynamic> params);

Future<dynamic> rpcPainelPadrao(String fn, Map<String, dynamic> params) =>
    Supabase.instance.client.rpc(fn, params: params);

/// Os papéis que o servidor aceita, pela ordem em que aparecem.
const List<String> kPapeisDaPessoa = ['estafeta', 'limpeza', 'lavagem'];

/// Nome que o Danilo lê. Nunca devolve o nome técnico cru (PADRAO_BORA 1.16).
String rotuloPapelPessoa(String papel) => switch (papel) {
      'estafeta' => 'Estafeta (entregas)',
      'limpeza' => 'Limpeza',
      'lavagem' => 'Lavagem de carros',
      _ => 'Outro papel',
    };

/// Estado do papel em PT-BR. `null` = a pessoa não tem cadastro nesse papel.
String rotuloEstadoPapel(String? estado) => switch (estado) {
      null => 'Sem perfil',
      'approved' => 'Aprovado',
      'pending' => 'Em análise',
      'rejected' => 'Recusado',
      'suspended' => 'Suspenso',
      _ => 'Estado desconhecido',
    };

/// Frase simples para cada código `error` de `admin_set_user_role`.
String mensagemErroPapel(String? codigo) => switch (codigo) {
      'motivo_obrigatorio' => 'Falta o motivo: escreva pelo menos 3 letras.',
      'papel_invalido' =>
        'Papel inválido: só dá para mexer em estafeta, limpeza ou lavagem.',
      'sem_perfil' => 'Esta pessoa não tem cadastro nesse papel.',
      'usa_aprovacao_normal' =>
        'Esse papel nunca foi aprovado (está em análise ou foi recusado na '
            'candidatura). Aprove pela tela de candidaturas.',
      'trabalho_em_curso' =>
        'Não dá para desligar agora: a pessoa tem um trabalho em andamento. '
            'Espere terminar.',
      _ => 'Não deu certo (resposta do servidor: ${codigo ?? 'sem código'}).',
    };

/// Mesma regra do servidor: motivo com pelo menos 3 letras (sem espaços nas
/// pontas).
bool motivoValido(String motivo) => motivo.trim().length >= 3;

/// Diálogo que pede o motivo. Devolve `null` se cancelar; senão o texto (já
/// sem espaços nas pontas). Com [obrigatorio], não fecha sem 3 letras.
Future<String?> pedirMotivoAdmin(
  BuildContext context, {
  required String titulo,
  required String explicacao,
  required String confirmar,
  bool obrigatorio = true,
  bool perigoso = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogoMotivo(
      titulo: titulo,
      explicacao: explicacao,
      confirmar: confirmar,
      obrigatorio: obrigatorio,
      perigoso: perigoso,
    ),
  );
}

class _DialogoMotivo extends StatefulWidget {
  const _DialogoMotivo({
    required this.titulo,
    required this.explicacao,
    required this.confirmar,
    required this.obrigatorio,
    required this.perigoso,
  });

  final String titulo;
  final String explicacao;
  final String confirmar;
  final bool obrigatorio;
  final bool perigoso;

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _ctrl = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _ctrl.text.trim();
    if (widget.obrigatorio && !motivoValido(texto)) {
      setState(() => _erro = 'Escreva o motivo (mínimo 3 letras).');
      return;
    }
    Navigator.pop(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.explicacao),
          const SizedBox(height: Spacing.md),
          TextField(
            key: const ValueKey('campo_motivo'),
            controller: _ctrl,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.obrigatorio
                  ? 'Motivo (obrigatório)'
                  : 'Motivo (opcional)',
              errorText: _erro,
            ),
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          style: FilledButton.styleFrom(
              backgroundColor:
                  widget.perigoso ? AppColors.error : AppColors.primary),
          child: Text(widget.confirmar),
        ),
      ],
    );
  }
}

/// Bloco "Papéis desta pessoa": uma linha por papel com o estado e um
/// interruptor. Mudar o interruptor pede o motivo, chama o servidor e mostra a
/// resposta aqui mesmo (por baixo das linhas).
class PapeisDaPessoa extends StatefulWidget {
  const PapeisDaPessoa({
    super.key,
    required this.userId,
    this.nome,
    this.rpc,
    this.aoMudar,
  });

  /// `auth.users.id` da pessoa (o `user_id` dos cadastros).
  final String userId;
  final String? nome;
  final ChamarRpcPainel? rpc;

  /// Chamado quando um papel mudou mesmo (antes ≠ depois).
  final VoidCallback? aoMudar;

  @override
  State<PapeisDaPessoa> createState() => _PapeisDaPessoaState();
}

class _PapeisDaPessoaState extends State<PapeisDaPessoa> {
  bool _carregando = true;
  String? _erro;
  Map<String, Map<String, dynamic>?> _papeis = const {};

  /// Papel cujo pedido está a caminho — só ESSE interruptor fica a girar.
  String? _aGravar;
  String? _resultado;
  bool _resultadoOk = true;

  ChamarRpcPainel get _rpc => widget.rpc ?? rpcPainelPadrao;

  @override
  void initState() {
    super.initState();
    _carregar(silencioso: true);
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final res = await _rpc('admin_user_roles', {'p_user_id': widget.userId});
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _papeis = {
          for (final p in kPapeisDaPessoa)
            p: m[p] is Map ? Map<String, dynamic>.from(m[p] as Map) : null,
        };
        _erro = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  Future<void> _mudar(String papel, bool ativo) async {
    final rotulo = rotuloPapelPessoa(papel);
    final efeito = ativo
        ? 'Só volta quem já foi aprovado antes. Candidatura nova é aprovada '
            'na tela de candidaturas.'
        : papel == 'estafeta'
            ? 'A pessoa fica recusada como estafeta e offline (desligada da '
                'app). Não dá se tiver uma entrega em andamento.'
            : 'A pessoa fica suspensa em $rotulo. Não dá se tiver um '
                'trabalho em andamento.';
    final motivo = await pedirMotivoAdmin(
      context,
      titulo: ativo ? 'Ligar $rotulo?' : 'Desligar $rotulo?',
      explicacao: efeito,
      confirmar: ativo ? 'Ligar' : 'Desligar',
      perigoso: !ativo,
    );
    if (motivo == null || !mounted) return;

    setState(() {
      _aGravar = papel;
      _resultado = null;
    });
    try {
      final res = await _rpc('admin_set_user_role', {
        'p_user_id': widget.userId,
        'p_papel': papel,
        'p_ativo': ativo,
        'p_motivo': motivo,
      });
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (m['ok'] == true) {
        final antes = m['antes']?.toString();
        final depois = m['depois']?.toString();
        if (antes == depois) {
          _mostrar('Sem mudança: $rotulo continua '
              '${rotuloEstadoPapel(depois).toLowerCase()}.');
        } else {
          _mostrar('$rotulo: ${rotuloEstadoPapel(antes)} → '
              '${rotuloEstadoPapel(depois)}. Fica registrado no histórico '
              '(admin_audit_log).');
          widget.aoMudar?.call();
        }
      } else {
        _mostrar(mensagemErroPapel(m['error']?.toString()), ok: false);
      }
    } catch (e) {
      _mostrar(humanizeAdminRpcError(e), ok: false);
    } finally {
      if (mounted) setState(() => _aGravar = null);
    }
    if (mounted) await _carregar(silencioso: true);
  }

  void _mostrar(String texto, {bool ok = true}) {
    if (!mounted) return;
    setState(() {
      _resultado = texto;
      _resultadoOk = ok;
    });
  }

  static IconData _icone(String papel) => switch (papel) {
        'estafeta' => Icons.delivery_dining,
        'limpeza' => Icons.cleaning_services_outlined,
        'lavagem' => Icons.local_car_wash_outlined,
        _ => Icons.badge_outlined,
      };

  static Color _corEstado(String? estado) => switch (estado) {
        'approved' => AppColors.primary,
        'pending' => AppColors.warning,
        'rejected' || 'suspended' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  Widget _linha(String papel) {
    final p = _papeis[papel];
    final semPerfil = p == null;
    final estado = p == null ? null : (p['estado']?.toString() ?? '');
    var sub = rotuloEstadoPapel(estado);
    if (papel == 'estafeta' && p?['ligado'] == true) {
      sub += ' · online agora (app ligada)';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Icon(_icone(papel), size: 22, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotuloPapelPessoa(papel),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12,
                        color: _corEstado(estado),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (_aGravar == papel)
            const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch(
              key: ValueKey('papel_switch_$papel'),
              value: estado == 'approved',
              activeThumbColor: AppColors.primary,
              onChanged: semPerfil ? null : (v) => _mudar(papel, v),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.nome?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          nome.isEmpty ? 'Papéis desta pessoa' : 'Papéis desta pessoa — $nome',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Spacing.sm),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.all(Spacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_erro != null) ...[
          Text(_erro!, style: const TextStyle(color: AppColors.error)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tentar de novo'),
            ),
          ),
        ] else ...[
          for (final p in kPapeisDaPessoa) _linha(p),
          if (_resultado != null)
            Container(
              key: const ValueKey('papeis_resultado'),
              margin: const EdgeInsets.only(top: Spacing.sm),
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: (_resultadoOk ? AppColors.primary : AppColors.error)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(
                _resultado!,
                style: TextStyle(
                    fontSize: 13,
                    color: _resultadoOk ? AppColors.primary : AppColors.error,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
        const SizedBox(height: Spacing.md),
        const Text(
          'Desligar um papel tira a pessoa desse trabalho (estafeta: fica '
          'recusado e offline; limpeza/lavagem: fica suspenso). Ligar só repõe '
          'quem já foi aprovado antes — candidaturas novas são aprovadas na '
          'tela de candidaturas.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Abre "Papéis desta pessoa" numa folha de baixo (bottom sheet). Devolve
/// `true` se algum papel mudou (para a tela de origem recarregar a lista).
Future<bool> mostrarPapeisDaPessoa(
  BuildContext context, {
  required String userId,
  String? nome,
  ChamarRpcPainel? rpc,
}) async {
  var mudou = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PapeisDaPessoa(
              userId: userId,
              nome: nome,
              rpc: rpc,
              aoMudar: () => mudou = true,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return mudou;
}

/// Botão "Papéis desta pessoa" para pôr no cartão. Não depende de nenhum
/// "ocupado" da tela (PADRAO_BORA 3.13): abrir a folha é sempre seguro.
class BotaoPapeisDaPessoa extends StatelessWidget {
  const BotaoPapeisDaPessoa({
    super.key,
    required this.userId,
    this.nome,
    this.aoMudar,
  });

  final String userId;
  final String? nome;

  /// Chamado ao fechar a folha, se algum papel mudou.
  final VoidCallback? aoMudar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final mudou =
            await mostrarPapeisDaPessoa(context, userId: userId, nome: nome);
        if (mudou) aoMudar?.call();
      },
      icon: const Icon(Icons.badge_outlined, size: 18),
      label: const Text('Papéis desta pessoa'),
    );
  }
}
