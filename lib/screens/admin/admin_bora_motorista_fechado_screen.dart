import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/tvde_visibilidade.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

// app-15-11 (auditoria S5): a leitura do interruptor e a frase dos botões
// travados vivem aqui, ao lado do ecrã do interruptor, e os outros ecrãs
// do arquivo usam-nas (uma leitura só, a deste ecrã).

/// Frase por baixo de cada botão travado com o Bora Motorista fechado.
const String kBotaoBoraMotoristaFechado =
    'Bora Motorista fechado: este botão volta quando reabrir.';

/// O valor de `get_setting('tvde_app_visivel')` quer dizer "aberto"?
/// A mesma leitura do ecrã do interruptor: só `true` abre.
bool boraMotoristaAbertoDoValor(Object? valor) =>
    valor?.toString().trim().toLowerCase() == 'true';

/// Lê o interruptor como o ecrã do interruptor (RPC `get_setting`). Nunca
/// lança: na dúvida (rede, chave em falta) devolve `false` — fechado.
Future<bool> lerBoraMotoristaAberto() async {
  try {
    final v = await Supabase.instance.client
        .rpc('get_setting', params: {'p_key': TvdeVisibilidade.chave});
    return boraMotoristaAbertoDoValor(v);
  } catch (e) {
    debugPrint('[BoraMotorista] ler o interruptor => $e');
    return false;
  }
}

/// A frase [kBotaoBoraMotoristaFechado], pequena, por baixo dos botões.
class AvisoBotaoBoraMotoristaFechado extends StatelessWidget {
  const AvisoBotaoBoraMotoristaFechado({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 14, color: AppColors.textSubtle),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              kBotaoBoraMotoristaFechado,
              key: Key('aviso_bora_motorista_fechado'),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão flutuante travado ("Nova reserva", "Nova corrida") com a frase
/// [kBotaoBoraMotoristaFechado] por cima, enquanto o Bora Motorista está
/// fechado. Antes o botão sumia sem dizer porquê.
class BotaoFlutuanteTravado extends StatelessWidget {
  const BotaoFlutuanteTravado(
      {super.key, required this.rotulo, required this.icone});

  final String rotulo;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Text(
            kBotaoBoraMotoristaFechado,
            key: Key('aviso_fab_bora_motorista_fechado'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        FloatingActionButton.extended(
          onPressed: null,
          tooltip: kBotaoBoraMotoristaFechado,
          backgroundColor: Colors.grey.shade400,
          foregroundColor: Colors.white,
          elevation: 0,
          icon: Icon(icone),
          label: Text(rotulo),
        ),
      ],
    );
  }
}

/// ARQUIVO — BORA MOTORISTA (FECHADO) · o interruptor das apps.
///
/// 04/11/2026 (missão fechar-bora-motorista): o Bora Motorista (TVDE de
/// passageiros) fechou porque ainda não tem a licença do IMT. Este ecrã é a
/// porta da secção "Arquivo — Bora Motorista (fechado)" do painel:
///  · mostra se o Bora Motorista está FECHADO ou ABERTO nas apps;
///  · liga/desliga `platform_settings.tvde_app_visivel` (com confirmação e
///    registo em admin_audit_log, pela RPC `admin_update_setting`);
///  · mostra quantas corridas, contas com acesso e pedidos de acesso há,
///    só para consulta.
///
/// Nada aqui apaga nem altera corridas, pagamentos, acertos ou saldos: o
/// contabilista precisa deles. Os ecrãs do arquivo continuam a abrir.
///
/// app-15-11 (auditoria S5): este ficheiro também guarda a leitura do
/// interruptor e a frase dos botões que ficam travados nos outros ecrãs do
/// arquivo enquanto o Bora Motorista está fechado (Reatribuir, Forçar nova
/// busca, Criar reserva, Trocar motorista, Remarcar, Mudar destino, Aprovar
/// acesso, Nova corrida de balcão). Uma leitura só, a deste ecrã.
class AdminBoraMotoristaFechadoScreen extends StatefulWidget {
  const AdminBoraMotoristaFechadoScreen({super.key});

  @override
  State<AdminBoraMotoristaFechadoScreen> createState() =>
      _AdminBoraMotoristaFechadoScreenState();
}

class _AdminBoraMotoristaFechadoScreenState
    extends State<AdminBoraMotoristaFechadoScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  bool _carregando = true;
  bool _aGravar = false;
  String? _erro;
  bool? _aberto;
  int? _corridas;
  int? _comAcesso;
  int? _pedidosPendentes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  /// app-15-11 (S5): conta no servidor, ao número exato, sem baixar as
  /// linhas (antes baixava até 100 000 ids só para os contar).
  Future<int?> _contar(Future<int> Function() q) async {
    try {
      return await q();
    } catch (e) {
      debugPrint('[AdminBoraMotoristaFechado] contar => $e');
      return null;
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final v = await _sb.rpc('get_setting',
          params: {'p_key': TvdeVisibilidade.chave});
      final aberto = boraMotoristaAbertoDoValor(v);
      final r = await Future.wait([
        _contar(() => _sb.from('tvde_rides').count(CountOption.exact)),
        _contar(() => _sb
            .from('users')
            .count(CountOption.exact)
            .eq('tvde_access', true)),
        _contar(() => _sb
            .from('tvde_access_requests')
            .count(CountOption.exact)
            .eq('status', 'pendente')),
      ]);
      if (!mounted) return;
      setState(() {
        _aberto = aberto;
        _corridas = r[0];
        _comAcesso = r[1];
        _pedidosPendentes = r[2];
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para ler o interruptor: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _mudar(bool abrir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(abrir ? 'Reabrir o Bora Motorista?' : 'Fechar o Bora Motorista?'),
        content: Text(abrir
            ? 'O ladrilho, a pesquisa, as corridas nas reservas e o modo de '
                'corridas do motorista voltam a aparecer nas apps (só para quem '
                'tem acesso TVDE). Faça isto só quando a licença do IMT sair.'
            : 'Tudo o que é do Bora Motorista some das apps do cliente e do '
                'motorista. Os dados ficam todos guardados aqui no painel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(abrir ? 'Reabrir' : 'Fechar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aGravar = true);
    try {
      await _sb.rpc('admin_update_setting', params: {
        'p_key': TvdeVisibilidade.chave,
        'p_value': abrir,
      });
      await TvdeVisibilidade.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(abrir
            ? 'Bora Motorista reaberto nas apps.'
            : 'Bora Motorista fechado nas apps.'),
      ));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gravar: $e')),
      );
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  String _n(int? v) => v == null ? '—' : '$v';

  @override
  Widget build(BuildContext context) {
    final aberto = _aberto ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Bora Motorista — interruptor'),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: AppColors.error))
            else ...[
              Card(
                color: aberto ? AppColors.primaryWash : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            aberto ? Icons.lock_open : Icons.lock,
                            color: aberto ? AppColors.primary : Colors.red.shade700,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              aberto
                                  ? 'ABERTO nas apps'
                                  : 'FECHADO nas apps',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        aberto
                            ? 'Quem tem acesso TVDE vê o Bora Motorista na app.'
                            : 'Fechado desde 04/11/2026 (sem licença do IMT). '
                                'Ninguém vê o Bora Motorista nas apps: nem o '
                                'ladrilho, nem a pesquisa, nem as corridas, nem o '
                                'modo de corridas do motorista. O servidor também '
                                'recusa pedir corrida.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: Spacing.md),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar o Bora Motorista nas apps'),
                        // app-15-11 (S5): sem nomes técnicos.
                        subtitle: const Text(
                            'Liga ou desliga o Bora Motorista nas apps. Fica registrado quem mudou.'),
                        value: aberto,
                        onChanged: _aGravar ? null : (v) => _mudar(v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              const Text('Arquivo (só consulta)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: Spacing.sm),
              _linha(Icons.local_taxi, 'Corridas guardadas', _n(_corridas)),
              _linha(Icons.how_to_reg, 'Contas com acesso TVDE', _n(_comAcesso)),
              _linha(Icons.hourglass_top, 'Pedidos de acesso pendentes',
                  _n(_pedidosPendentes)),
              const SizedBox(height: Spacing.md),
              const Text(
                'Corridas, pagamentos, recibos, acertos, dívidas, motoristas e '
                'pedidos de acesso continuam nos ecrãs desta secção. Nada foi '
                'apagado: o contabilista precisa deles. Com o Bora Motorista '
                'fechado, aprovar pedidos de acesso e criar corridas de balcão '
                'ficam travados.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linha(IconData icon, String texto, String valor) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(texto),
        trailing: Text(valor,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}
