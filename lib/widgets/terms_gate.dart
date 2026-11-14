import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// Categorias de loja (`restaurants.category` / `extra_categories`) que têm de
/// aceitar os Termos do Parceiro de 28/10/2026: comida e mercado. A mesma
/// lista está no servidor (`_categoria_com_termos_parceiro`, proposta F3).
/// 14/11/2026 (farmácias, bloco 2.6): as farmácias parceiras também aceitam os
/// termos no 1.º login; o "Aceito" preenche a autocertificação da farmácia
/// (`legal_terms_accept`, migração farmacias_loja_a1).
const Set<String> kCategoriasComTermosDoParceiro = {
  'restaurant',
  'sobremesa',
  'festas',
  'supermarket',
  'pharmacy',
};

/// F3 (28/10/2026): true se alguma das [lojas] do dono é parceira, está
/// aprovada e é de comida ou mercado.
bool termosDoParceiroAplicam(Iterable<Map<String, dynamic>> lojas) =>
    lojas.any((l) {
      if (l['is_partner'] != true) return false;
      if (l['approval_status'] != 'approved') return false;
      final extra = l['extra_categories'] is List
          ? (l['extra_categories'] as List).map((e) => '$e')
          : const <String>[];
      return kCategoriasComTermosDoParceiro
              .contains('${l['category'] ?? ''}') ||
          extra.any(kCategoriasComTermosDoParceiro.contains);
    });

/// Termos e Condições com versão (missão fecho-mensal-2026-09, B6A).
///
/// Embrulha o ecrã principal do cliente, do estafeta e do parceiro (este desde
/// 28/10/2026, Regulamento UE 2019/1150). No arranque pergunta ao
/// servidor (`legal_terms_pending`) se há uma versão em vigor que este
/// utilizador ainda não aceitou; se houver, põe por cima um ecrã com o texto e
/// um único botão "Aceito" (`legal_terms_accept`). Sem aceitar não se passa.
///
/// Falha aberta: sem sessão Supabase ou sem rede, a app segue normalmente e a
/// pergunta repete-se no próximo arranque — um erro de rede nunca tranca ninguém.
///
/// Parceiro (missao-geral-2026-10-28, F3): os termos de 28/10/2026 são das
/// lojas de COMIDA e MERCADO já APROVADAS. Antes de perguntar, o portão lê as
/// lojas do dono (`restaurants`, por `user_id`/`user_`) e só segue se
/// [termosDoParceiroAplicam]. Parceiros de serviços (barbearias, beleza) e
/// lojas por aprovar não veem estes termos — os serviços terão os seus.
///
/// [G2 · 01/11/2026] [garantirAceite]: o mesmo portão para quem entra A MEIO
/// de um fluxo. O visitante que cria conta no carrinho fica com o TermsGate da
/// raiz POR BAIXO do carrinho e pagava sem ver os termos; agora o
/// `garantirContactoDoCliente` pede-os antes de seguir para o pagamento.
class TermsGate extends StatefulWidget {
  const TermsGate({super.key, required this.audience, required this.child});

  /// 'cliente', 'estafeta' ou 'parceiro' (igual a
  /// `legal_terms_versions.audience`).
  final String audience;
  final Widget child;

  /// Aceitações feitas nesta sessão (`"<audience>|<version>"`). O portão da
  /// raiz ouve isto: aceite por [garantirAceite], tira os seus termos de cima
  /// em vez de os pedir uma segunda vez.
  static final StreamController<String> _aceites =
      StreamController<String>.broadcast();

  /// `"<uid>|<audience>"` já sem termos por aceitar nesta sessão. Só o
  /// [garantirAceite] lê isto (não pergunta outra vez ao servidor em cada
  /// "Finalizar"); o portão da raiz pergunta sempre ao arrancar.
  static final Set<String> _semTermosPorAceitar = <String>{};

  static String? _chaveDaSessao(String audience) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid == null ? null : '$uid|$audience';
  }

  static void _registarSemPendentes(String audience) {
    final chave = _chaveDaSessao(audience);
    if (chave != null) _semTermosPorAceitar.add(chave);
  }

  static void _registarAceite(String audience, Object? versao) {
    _registarSemPendentes(audience);
    _aceites.add('$audience|$versao');
  }

  /// Pergunta ao servidor a versão por aceitar. `pendente` null = nada por
  /// aceitar; `respondeu` false = sem sessão ou erro (falha aberta).
  static Future<({Map<String, dynamic>? pendente, bool respondeu})>
      _perguntarPendente(String audience) async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return (pendente: null, respondeu: false);
    if (audience == 'parceiro') {
      try {
        // Limite de tempo: isto está no caminho do "Finalizar" (rede pendurada
        // não pode deixar o botão preso); o catch deixa seguir.
        final lojas = await sb
            .from('restaurants')
            .select('category, extra_categories, is_partner, approval_status')
            .or('user_id.eq.$uid,user_.eq.$uid')
            .timeout(const Duration(seconds: 8));
        if (!termosDoParceiroAplicam(
            (lojas as List).whereType<Map>().map(Map<String, dynamic>.from))) {
          return (pendente: null, respondeu: true);
        }
      } catch (e) {
        debugPrint('[TermsGate] lojas do parceiro: $e');
        return (pendente: null, respondeu: false);
      }
    }
    try {
      final r = await sb
          .rpc('legal_terms_pending', params: {'p_audience': audience})
          .timeout(const Duration(seconds: 8));
      return (
        pendente: r is Map ? Map<String, dynamic>.from(r) : null,
        respondeu: true,
      );
    } catch (e) {
      debugPrint('[TermsGate] legal_terms_pending: $e');
      return (pendente: null, respondeu: false);
    }
  }

  static Future<void> _gravarAceite(String audience, Object? versao) =>
      Supabase.instance.client.rpc('legal_terms_accept', params: {
        'p_audience': audience,
        'p_version': versao,
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });

  /// [G2 · 01/11/2026] Antes de seguir (ex.: para o pagamento): se há termos
  /// por aceitar para [audience], abre-os por cima e só devolve `true` depois
  /// de "Aceito". Sem termos, sem sessão ou sem rede devolve `true` (falha
  /// aberta, igual ao portão). Voltar atrás sem aceitar devolve `false`.
  static Future<bool> garantirAceite(BuildContext context,
      {String audience = 'cliente'}) async {
    final chave = _chaveDaSessao(audience);
    if (chave == null) return true;
    if (_semTermosPorAceitar.contains(chave)) return true;
    final r = await _perguntarPendente(audience);
    final pendente = r.pendente;
    if (pendente == null) {
      if (r.respondeu) _semTermosPorAceitar.add(chave);
      return true;
    }
    if (!context.mounted) return false;
    final aceitou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TermosPorCima(audience: audience, pendente: pendente),
      ),
    );
    return aceitou == true;
  }

  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  Map<String, dynamic>? _pendente;
  bool _aGravar = false;
  String? _erro;
  StreamSubscription<String>? _aceitesSub;

  @override
  void initState() {
    super.initState();
    _aceitesSub = TermsGate._aceites.stream.listen((aceite) {
      final v = _pendente;
      if (v == null || !mounted) return;
      if (aceite == '${widget.audience}|${v['version']}') {
        setState(() => _pendente = null);
      }
    });
    _verificar();
  }

  @override
  void dispose() {
    _aceitesSub?.cancel();
    super.dispose();
  }

  Future<void> _verificar() async {
    final r = await TermsGate._perguntarPendente(widget.audience);
    if (!mounted) return;
    final pendente = r.pendente;
    if (pendente == null) {
      if (r.respondeu) TermsGate._registarSemPendentes(widget.audience);
      return;
    }
    setState(() => _pendente = pendente);
  }

  Future<void> _aceitar() async {
    final v = _pendente;
    if (v == null) return;
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      await TermsGate._gravarAceite(widget.audience, v['version']);
      if (mounted) setState(() => _pendente = null);
      TermsGate._registarAceite(widget.audience, v['version']);
    } catch (e) {
      if (mounted) {
        setState(() => _erro =
            'Não foi possível gravar a aceitação. Verifique a ligação e tente outra vez.');
      }
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _pendente;
    if (v == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: _EcraDosTermos(
            pendente: v,
            aGravar: _aGravar,
            erro: _erro,
            onAceitar: _aceitar,
          ),
        ),
      ],
    );
  }
}

/// [G2] Os termos numa página por cima (fluxo a meio). "Aceito" grava e fecha
/// com `true`.
class _TermosPorCima extends StatefulWidget {
  const _TermosPorCima({required this.audience, required this.pendente});

  final String audience;
  final Map<String, dynamic> pendente;

  @override
  State<_TermosPorCima> createState() => _TermosPorCimaState();
}

class _TermosPorCimaState extends State<_TermosPorCima> {
  bool _aGravar = false;
  String? _erro;

  Future<void> _aceitar() async {
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      await TermsGate._gravarAceite(
          widget.audience, widget.pendente['version']);
      TermsGate._registarAceite(widget.audience, widget.pendente['version']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _erro =
            'Não foi possível gravar a aceitação. Verifique a ligação e tente outra vez.');
      }
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  // A barra de cima só traz o "fechar" (rota fullscreenDialog): quem não
  // quer aceitar agora volta ao carrinho, sem pagar.
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          elevation: 0,
        ),
        body: _EcraDosTermos(
          pendente: widget.pendente,
          aGravar: _aGravar,
          erro: _erro,
          onAceitar: _aceitar,
        ),
      );
}

/// O ecrã dos termos (texto + um só botão "Aceito"), igual no portão da raiz
/// e na página por cima.
class _EcraDosTermos extends StatelessWidget {
  const _EcraDosTermos({
    required this.pendente,
    required this.aGravar,
    required this.erro,
    required this.onAceitar,
  });

  final Map<String, dynamic> pendente;
  final bool aGravar;
  final String? erro;
  final VoidCallback onAceitar;

  @override
  Widget build(BuildContext context) {
    final v = pendente;
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.description_outlined,
                  size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                (v['title'] ?? 'Termos e Condições').toString(),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    (v['body'] ?? '').toString(),
                    style: const TextStyle(fontSize: 15, height: 1.45),
                  ),
                ),
              ),
              if (erro != null) ...[
                const SizedBox(height: 8),
                Text(erro!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: aGravar ? null : onAceitar,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: aGravar
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Aceito',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
