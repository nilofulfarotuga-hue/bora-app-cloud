// Painel admin (PT-BR) — "Stripe — duas contas".
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
//
// Mostra que conta Stripe cada fluxo usa (PESSOAL = TVDE; EMPRESA = o resto), o interruptor
// `stripe_conta_nao_tvde` (com confirmação), se as chaves existem no servidor (nunca o valor),
// os últimos eventos de cada webhook e o link para o painel de cada conta.
//
// Termos técnicos explicados entre parênteses, como manda o painel admin.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

class AdminStripeContasScreen extends StatefulWidget {
  const AdminStripeContasScreen({super.key});

  static const String settingKey = 'stripe_conta_nao_tvde';
  static const String painelPessoal = 'https://dashboard.stripe.com/acct_1T8MFaGlT3R2jCYp';
  static const String painelEmpresa = 'https://dashboard.stripe.com/acct_1UX67LGWwQxC9wR2';

  @override
  State<AdminStripeContasScreen> createState() => _AdminStripeContasScreenState();
}

class _AdminStripeContasScreenState extends State<AdminStripeContasScreen> {
  bool _loading = true;
  String? _erro;
  String _contaNaoTvde = 'pessoal'; // valor do interruptor
  bool _interruptorExiste = false;
  Map<String, dynamic> _chaves = const {};
  String? _erroChaves;
  List<Map<String, dynamic>> _eventos = const [];
  String? _erroEventos;
  bool _aGuardar = false;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      await Future.wait([_lerInterruptor(), _lerChaves(), _lerEventos()]);
    } catch (e) {
      _erro = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _lerInterruptor() async {
    try {
      final res = await _sb.rpc('admin_list_settings');
      _interruptorExiste = false;
      if (res is List) {
        for (final s in res) {
          final m = (s as Map).cast<String, dynamic>();
          if (m['key'] == AdminStripeContasScreen.settingKey) {
            _interruptorExiste = true;
            final v = m['value'];
            final txt = v is String ? v : v?.toString() ?? '';
            _contaNaoTvde = txt.replaceAll('"', '') == 'empresa' ? 'empresa' : 'pessoal';
          }
        }
      }
    } catch (e) {
      _erro = 'Não deu para ler o interruptor: $e';
    }
  }

  Future<void> _lerChaves() async {
    try {
      final res = await _sb.functions.invoke('admin-payments', body: {'action': 'contas'});
      final data = res.data;
      if (data is Map && data['contas'] is Map) {
        _chaves = (data['contas'] as Map).cast<String, dynamic>();
        _erroChaves = null;
      } else {
        _erroChaves = 'Resposta inesperada do servidor (função admin-payments antiga?).';
      }
    } catch (e) {
      _erroChaves = 'Sem resposta da função admin-payments: $e';
    }
  }

  Future<void> _lerEventos() async {
    try {
      final res = await _sb
          .from('stripe_webhook_events')
          .select('event_id, type, received_at, processed_at, last_error, stripe_account')
          .order('received_at', ascending: false)
          .limit(40);
      _eventos = (res as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      _erroEventos = null;
    } catch (e) {
      // A coluna stripe_account só existe depois da migração; sem ela mostra-se o que houver.
      try {
        final res = await _sb
            .from('stripe_webhook_events')
            .select('event_id, type, received_at, processed_at, last_error')
            .order('received_at', ascending: false)
            .limit(40);
        _eventos = (res as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _erroEventos = 'Coluna da conta ainda não existe no banco (migração por aplicar): todos os eventos aparecem como Pessoal.';
      } catch (e2) {
        _erroEventos = 'Não deu para ler os eventos do webhook: $e2';
      }
    }
  }

  Future<void> _mudarInterruptor(String nova) async {
    if (nova == _contaNaoTvde) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar a conta Stripe dos pagamentos que não são TVDE?'),
        content: Text(nova == 'empresa'
            ? 'Entregas, Favores, limpeza, lavagem, Casa, agendamentos, reservas de mesa, gorjetas de entregas, dívida, peso e extras passam a ser cobrados na conta da EMPRESA (Unipessoal Lda).\n\nSó vale para apps atualizados (que enviam stripe_contas_v2). Apps antigos continuam na Pessoal. O TVDE fica sempre na Pessoal. Pagamentos já feitos ficam onde estão e são reembolsados na conta onde entraram.'
            : 'Tudo o que não é TVDE volta a ser cobrado na conta PESSOAL. Pagamentos já feitos na Empresa continuam lá (reembolsos saem de lá).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Mudar para ${nova == 'empresa' ? 'Empresa' : 'Pessoal'}')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _aGuardar = true);
    try {
      await _sb.rpc('admin_update_setting', params: {
        'p_key': AdminStripeContasScreen.settingKey,
        'p_value': nova, // jsonb string
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Interruptor em ${nova == 'empresa' ? 'Empresa' : 'Pessoal'}. A app pergunta ao servidor em cada pagamento; não precisa de nova versão.')));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não guardou: $e')));
    } finally {
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não abriu: $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stripe — duas contas'),
        actions: [
          IconButton(onPressed: _loading ? null : _carregar, icon: const Icon(Icons.refresh), tooltip: 'Recarregar'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  if (_erro != null) _aviso(_erro!, cor: Colors.red.shade700),
                  _cartaoInterruptor(),
                  const SizedBox(height: Spacing.md),
                  _cartaoFluxos(),
                  const SizedBox(height: Spacing.md),
                  _cartaoChaves(),
                  const SizedBox(height: Spacing.md),
                  _cartaoEventos(),
                  const SizedBox(height: Spacing.md),
                  _cartaoLinks(),
                ],
              ),
            ),
    );
  }

  Widget _cartao({required String titulo, required List<Widget> filhos}) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: Spacing.sm),
            ...filhos,
          ],
        ),
      );

  Widget _aviso(String texto, {Color? cor}) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(texto, style: TextStyle(fontSize: 12, color: cor ?? AppColors.textSecondary)),
      );

  Widget _cartaoInterruptor() {
    final empresa = _contaNaoTvde == 'empresa';
    return _cartao(titulo: 'Interruptor — conta dos pagamentos que NÃO são TVDE', filhos: [
      Text(
        'Hoje: ${empresa ? 'EMPRESA (Unipessoal Lda)' : 'PESSOAL (bora app)'}',
        style: TextStyle(fontWeight: FontWeight.w700, color: empresa ? AppColors.primary : AppColors.textSecondary),
      ),
      const SizedBox(height: Spacing.xs),
      const Text(
        'O TVDE (Bora Motorista) fica sempre na conta Pessoal. Este interruptor só muda o resto: entregas, Favores, limpeza, lavagem, Casa, agendamentos, reservas de mesa, gorjetas de entregas, dívida, peso e extras. Só vale para apps atualizados (mandam a marca stripe_contas_v2); apps antigos ficam na Pessoal.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      if (!_interruptorExiste)
        _aviso('A chave stripe_conta_nao_tvde ainda não existe em platform_settings (proposta SQL 02 por aplicar). O servidor trata como Pessoal.', cor: Colors.orange.shade800),
      const SizedBox(height: Spacing.sm),
      Row(children: [
        ChoiceChip(
          label: const Text('Pessoal'),
          selected: !empresa,
          onSelected: (_aGuardar || !_interruptorExiste) ? null : (_) => _mudarInterruptor('pessoal'),
        ),
        const SizedBox(width: Spacing.sm),
        ChoiceChip(
          label: const Text('Empresa'),
          selected: empresa,
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          onSelected: (_aGuardar || !_interruptorExiste) ? null : (_) => _mudarInterruptor('empresa'),
        ),
        if (_aGuardar) const Padding(padding: EdgeInsets.only(left: Spacing.sm), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      ]),
    ]);
  }

  Widget _cartaoFluxos() {
    final naoTvde = _contaNaoTvde == 'empresa' ? 'Empresa' : 'Pessoal';
    final linhas = <List<String>>[
      ['TVDE: corridas, pacote ida e volta, paragens, planos, reservas TVDE, mudança de destino, gorjeta de corrida', 'Pessoal (sempre)'],
      ['Entregas (restaurantes, mercados, lojas) e Favores', naoTvde],
      ['Limpeza e lavagem de carros', naoTvde],
      ['Casa & Manutenção', 'sem Stripe ainda'],
      ['Agendamentos (barbearia / beleza) e reservas de mesa (3 €)', naoTvde],
      ['Gorjetas de entregas, dívida / carteira, diferença de peso, extras e acertos de pedido', naoTvde],
      ['Reembolsos, capturas e extras de pagamentos já feitos', 'a conta onde o dinheiro entrou (stripe_account da linha)'],
    ];
    return _cartao(titulo: 'Que conta usa cada fluxo (agora)', filhos: [
      for (final l in linhas)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Text(l[0], style: const TextStyle(fontSize: 13))),
            const SizedBox(width: Spacing.sm),
            Expanded(flex: 2, child: Text(l[1], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: l[1].startsWith('Empresa') ? AppColors.primary : AppColors.textSecondary))),
          ]),
        ),
    ]);
  }

  Widget _cartaoChaves() {
    Widget linha(String rotulo, dynamic v) {
      final ok = v == true;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: ok ? AppColors.primary : Colors.red.shade700),
          const SizedBox(width: Spacing.xs),
          Expanded(child: Text(rotulo, style: const TextStyle(fontSize: 13))),
          Text(ok ? 'existe' : 'falta', style: TextStyle(fontSize: 12, color: ok ? AppColors.textSecondary : Colors.red.shade700)),
        ]),
      );
    }

    return _cartao(titulo: 'Chaves no servidor (só se existem — nunca o valor)', filhos: [
      if (_erroChaves != null) _aviso(_erroChaves!, cor: Colors.orange.shade800),
      if (_chaves.isNotEmpty) ...[
        Text('Modo: ${_chaves['modo'] ?? '?'} (live = dinheiro real)', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: Spacing.xs),
        const Text('Conta PESSOAL', style: TextStyle(fontWeight: FontWeight.w600)),
        linha('Chave secreta (STRIPE_SECRET_KEY — cobra e reembolsa)', _chaves['pessoal_secreta']),
        linha('Chave publicável (abre a folha do cartão no app)', _chaves['pessoal_publicavel']),
        linha('Segredo do webhook (a Stripe avisa o servidor)', _chaves['pessoal_webhook']),
        const SizedBox(height: Spacing.xs),
        const Text('Conta EMPRESA', style: TextStyle(fontWeight: FontWeight.w600)),
        linha('Chave secreta (STRIPE_SECRET_KEY_EMPRESA)', _chaves['empresa_secreta']),
        linha('Chave publicável (STRIPE_PUBLISHABLE_KEY_EMPRESA)', _chaves['empresa_publicavel']),
        linha('Segredo do webhook (STRIPE_WEBHOOK_SECRET_EMPRESA)', _chaves['empresa_webhook']),
      ],
    ]);
  }

  Widget _cartaoEventos() {
    return _cartao(titulo: 'Últimos eventos dos webhooks (o que a Stripe mandou ao servidor)', filhos: [
      if (_erroEventos != null) _aviso(_erroEventos!, cor: Colors.orange.shade800),
      if (_eventos.isEmpty) const Text('Sem eventos.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      for (final e in _eventos.take(40))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (e['stripe_account'] == 'empresa' ? AppColors.primary : AppColors.textSubtle).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(e['stripe_account'] == 'empresa' ? 'Empresa' : 'Pessoal', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                '${e['type'] ?? '?'} · ${_hora(e['received_at'])}'
                '${e['processed_at'] == null ? ' · POR PROCESSAR' : ''}'
                '${e['last_error'] != null ? ' · erro: ${e['last_error']}' : ''}',
                style: TextStyle(fontSize: 12, color: e['last_error'] != null ? Colors.red.shade700 : AppColors.textSecondary),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _cartaoLinks() => _cartao(titulo: 'Painéis da Stripe', filhos: [
        TextButton.icon(
          onPressed: () => _abrir(AdminStripeContasScreen.painelPessoal),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Conta PESSOAL — "bora app" (TVDE)'),
        ),
        TextButton.icon(
          onPressed: () => _abrir(AdminStripeContasScreen.painelEmpresa),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Conta EMPRESA — "Bora", Unipessoal Lda (entra-se com boraappbora@gmail.com)'),
        ),
        const Text(
          'Regra: o dinheiro mexe-se sempre na conta onde entrou. Um pedido pago na Pessoal é reembolsado na Pessoal, mesmo depois de a Empresa passar a ser a conta ativa.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ]);

  String _hora(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    if (d == null) return '';
    final l = d.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(l.day)}/${dois(l.month)} ${dois(l.hour)}:${dois(l.minute)}';
  }
}
