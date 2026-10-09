import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../screens/admin/_admin_rpc_errors.dart';
import '../../utils/hora_lisboa.dart';
import 'papeis_da_pessoa.dart';

/// OFERTAS DE LIMPEZA EM ABERTO (painel admin, PT-BR) — cartão no topo da tela
/// das profissionais de limpeza.
///
/// Servidor (aplicado 09/10/2026, só admin):
///  - `admin_cleaning_offers()` → `{repeticao_ligada, ofertas: [...]}` — as
///    ofertas à espera de resposta, mais as que expiraram nas últimas 2 h.
///  - `admin_set_cleaning_offer_reping(p_ligado, p_motivo)` → `{ok, antes,
///    depois}` — liga/desliga o toque repetido (fica em `admin_audit_log`).
///
/// Horas sempre em hora de Lisboa, nunca no fuso do navegador.
class OfertasLimpezaEmAberto extends StatefulWidget {
  const OfertasLimpezaEmAberto({super.key, this.rpc, this.agora});

  final ChamarRpcPainel? rpc;

  /// Relógio injetável (testes). Por omissão `DateTime.now()`.
  final DateTime Function()? agora;

  @override
  State<OfertasLimpezaEmAberto> createState() => _OfertasLimpezaEmAbertoState();
}

/// "expirou" / "expira em menos de 1 min" / "expira em N min".
String textoExpiraOferta(DateTime? expira, DateTime agora,
    {bool expirada = false}) {
  if (expirada || (expira != null && !expira.isAfter(agora))) return 'expirou';
  if (expira == null) return 'sem prazo';
  final min = (expira.difference(agora).inSeconds / 60).ceil();
  return min <= 1 ? 'expira em menos de 1 min' : 'expira em $min min';
}

/// "Ainda não tocou" / "Tocou 1 vez" / "Tocou N vezes · último às HH:mm"
/// (hora de Lisboa).
String textoToquesOferta(int toques, DateTime? ultimo) {
  final base = toques <= 0
      ? 'Ainda não tocou'
      : toques == 1
          ? 'Tocou 1 vez'
          : 'Tocou $toques vezes';
  if (ultimo == null) return base;
  final l = horaLisboa(ultimo);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '$base · último às ${dd(l.hour)}:${dd(l.minute)}';
}

class _OfertasLimpezaEmAbertoState extends State<OfertasLimpezaEmAberto> {
  bool _carregando = true;
  String? _erro;
  bool _repeticaoLigada = true;
  List<Map<String, dynamic>> _ofertas = const [];
  bool _gravandoRepeticao = false;

  ChamarRpcPainel get _rpc => widget.rpc ?? rpcPainelPadrao;
  DateTime get _agora => (widget.agora ?? DateTime.now)();

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
      final res = await _rpc('admin_cleaning_offers', const {});
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _repeticaoLigada = m['repeticao_ligada'] != false;
        _ofertas = ((m['ofertas'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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

  Future<void> _mudarRepeticao(bool ligar) async {
    final motivo = await pedirMotivoAdmin(
      context,
      titulo: ligar ? 'Ligar o toque repetido?' : 'Desligar o toque repetido?',
      explicacao: ligar
          ? 'O aviso da oferta volta a tocar a cada minuto até a '
              'profissional responder.'
          : 'O aviso da oferta deixa de se repetir: toca só quando a oferta '
              'é enviada.',
      confirmar: ligar ? 'Ligar' : 'Desligar',
      obrigatorio: false,
      perigoso: !ligar,
    );
    if (motivo == null || !mounted) return;
    setState(() => _gravandoRepeticao = true);
    try {
      final res = await _rpc('admin_set_cleaning_offer_reping',
          {'p_ligado': ligar, 'p_motivo': motivo});
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (m['ok'] == true) {
        _aviso(ligar ? 'Toque repetido ligado.' : 'Toque repetido desligado.');
      } else {
        final codigo = m['error']?.toString();
        _aviso(
            codigo == 'valor_em_falta'
                ? 'Faltou dizer se é para ligar ou desligar.'
                : 'Não deu certo (resposta do servidor: '
                    '${codigo ?? 'sem código'}).',
            ok: false);
      }
    } catch (e) {
      _aviso(humanizeAdminRpcError(e), ok: false);
    } finally {
      if (mounted) setState(() => _gravandoRepeticao = false);
    }
    if (mounted) await _carregar(silencioso: true);
  }

  void _aviso(String texto, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: ok ? AppColors.primary : AppColors.error,
    ));
  }

  Widget _oferta(Map<String, dynamic> o, DateTime agora) {
    final nome = (o['profissional'] ?? '').toString().trim();
    final cidade = (o['cidade'] ?? '').toString().trim();
    final ganho = (o['ganho_profissional_cents'] as num?)?.toInt() ?? 0;
    final expira = DateTime.tryParse('${o['expira_em'] ?? ''}');
    final expiraTxt =
        textoExpiraOferta(expira, agora, expirada: o['expirada'] == true);
    final expirou = expiraTxt == 'expirou';
    final toques = (o['toques'] as num?)?.toInt() ?? 0;
    final ultimo = DateTime.tryParse('${o['ultimo_toque'] ?? ''}');
    final aparelho = o['aparelho_registado'] == true;
    final teste = o['teste'] == true;
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);

    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(nome.isEmpty ? '(sem nome)' : nome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    if (teste)
                      const Text('TESTE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                    'Limpeza: ${dataHoraLisboa(o['marcada_para'])}'
                    '${cidade.isEmpty ? '' : ' · $cidade'}',
                    style: pequeno),
                Text(expiraTxt,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: expirou ? AppColors.error : AppColors.primary)),
                Text(textoToquesOferta(toques, ultimo), style: pequeno),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Aparelho registrado: ', style: pequeno),
                    Text(
                      aparelho ? 'Sim' : 'Não',
                      key: const ValueKey('aparelho_registado'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color:
                              aparelho ? AppColors.primary : AppColors.error),
                    ),
                    if (!aparelho)
                      const Text(
                          ' — sem celular registrado o aviso não chega',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.error)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // Regra do Danilo: o número grande é o que a profissional GANHA.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('€${(ganho / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
              const Text('ganho da profissional',
                  style: TextStyle(fontSize: 11, color: AppColors.textSubtle)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agora = _agora;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    _carregando || _erro != null
                        ? 'Ofertas em aberto'
                        : 'Ofertas em aberto (${_ofertas.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar ofertas',
                  icon: const Icon(Icons.refresh),
                  onPressed: _carregar,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Repetir o toque da oferta',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          'Repete o toque da oferta a cada minuto até a '
                          'profissional responder.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (_gravandoRepeticao)
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
                    key: const ValueKey('switch_repetir_toque'),
                    value: _repeticaoLigada,
                    activeThumbColor: AppColors.primary,
                    onChanged: _carregando || _erro != null
                        ? null
                        : (v) => _mudarRepeticao(v),
                  ),
              ],
            ),
            const Divider(height: Spacing.lg),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(Spacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: AppColors.error))
            else if (_ofertas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text('Nenhuma oferta à espera agora.',
                    style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              for (final o in _ofertas) _oferta(o, agora),
          ],
        ),
      ),
    );
  }
}
