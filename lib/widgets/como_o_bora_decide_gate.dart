import 'package:flutter/material.dart';

import '../screens/prestador/como_o_bora_decide_screen.dart';
import '../services/prestador_avisos_service.dart';

/// Lê as versões de "Como o Bora decide" que a pessoa já leu.
typedef LerVersoesAviso = Future<({bool respondeu, Set<String> versoes})>
    Function();

/// Grava "Li e percebi" (com o papel em que a pessoa estava).
typedef MarcarAvisoLido = Future<void> Function(String? papel);

/// PORTÃO "Como o Bora decide" (missão fechar-tudo-2026-11-10, E4).
///
/// Diretiva (UE) 2024/2831, art. 9.º: cada prestador recebe por escrito a
/// informação sobre os sistemas automáticos no primeiro dia e sempre que ela
/// mudar. Embrulha a entrada de quem trabalha no Bora (`PortaoDoPrestador`:
/// estafeta, limpeza, lavagem, Casa). Quando [ativo] (a pessoa tem um papel
/// aprovado) pergunta ao servidor se já leu a versão em vigor
/// ([ComoOBoraDecide.versaoId]); se não leu, põe por cima o ecrã inteiro com o
/// botão "Li e percebi", que grava em `prestador_avisos_lidos`. Aparece uma
/// vez por versão: uma versão nova volta a mostrá-lo.
///
/// Falha aberta, como o `TermsGate`: sem sessão ou sem rede segue sem o ecrã
/// e pergunta outra vez no próximo arranque. Não manda mensagens nem push.
class ComoOBoraDecideGate extends StatefulWidget {
  const ComoOBoraDecideGate({
    super.key,
    required this.ativo,
    required this.child,
    this.papel,
    this.lerVersoes,
    this.marcarLido,
    this.uidAtual,
  });

  /// A pessoa tem um papel de prestador aprovado (só aí se pergunta).
  final bool ativo;

  /// 'estafeta', 'limpeza', 'lavagem' ou 'casa' — fica no registo.
  final String? papel;

  final Widget child;

  /// Testes: substituem o servidor.
  final LerVersoesAviso? lerVersoes;
  final MarcarAvisoLido? marcarLido;
  final String? Function()? uidAtual;

  /// `"<uid>|<versão>"` já resolvidos nesta sessão da app: não se volta a
  /// perguntar ao servidor a cada reconstrução nem a cada mudança de modo.
  static final Set<String> _resolvidos = <String>{};

  @visibleForTesting
  static void limparSessaoParaTeste() => _resolvidos.clear();

  @override
  State<ComoOBoraDecideGate> createState() => _ComoOBoraDecideGateState();
}

class _ComoOBoraDecideGateState extends State<ComoOBoraDecideGate> {
  bool _mostrar = false;
  bool _aVerificar = false;

  String? _chave() {
    final uid = (widget.uidAtual ?? PrestadorAvisos.uidAtual)();
    return uid == null ? null : '$uid|${ComoOBoraDecide.versaoId}';
  }

  @override
  void initState() {
    super.initState();
    if (widget.ativo) _verificar();
  }

  @override
  void didUpdateWidget(covariant ComoOBoraDecideGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ativo && !oldWidget.ativo) _verificar();
  }

  Future<void> _verificar() async {
    if (_aVerificar || _mostrar) return;
    final chave = _chave();
    if (chave == null || ComoOBoraDecideGate._resolvidos.contains(chave)) {
      return;
    }
    _aVerificar = true;
    final ler = widget.lerVersoes ??
        () => PrestadorAvisos.versoesLidas(ComoOBoraDecide.aviso);
    final r = await ler();
    _aVerificar = false;
    if (!mounted) return;
    if (PrestadorAvisos.precisaDeMostrar(
      respondeu: r.respondeu,
      versoesLidas: r.versoes,
      versaoAtual: ComoOBoraDecide.versaoId,
    )) {
      setState(() => _mostrar = true);
    } else if (r.respondeu) {
      ComoOBoraDecideGate._resolvidos.add(chave);
    }
  }

  Future<void> _gravar() async {
    final marcar = widget.marcarLido ??
        (String? papel) => PrestadorAvisos.marcarLido(
              aviso: ComoOBoraDecide.aviso,
              versao: ComoOBoraDecide.versaoId,
              papel: papel,
            );
    await marcar(widget.papel);
    final chave = _chave();
    if (chave != null) ComoOBoraDecideGate._resolvidos.add(chave);
    if (mounted) setState(() => _mostrar = false);
  }

  // Sempre o mesmo Stack com o ecrã de trabalho no lugar 0: mostrar ou tirar
  // o aviso por cima NÃO recria o ecrã de baixo (o do estafeta tem lá o
  // batimento, o GPS e as ofertas).
  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_mostrar)
            Positioned.fill(child: ComoOBoraDecideScreen(aoLer: _gravar)),
        ],
      );
}
