/// CASA — aba "Resumo" do hub (painel admin, PT-BR): contadores do que
/// espera decisão, estado do interruptor e dos valores (AUTORIZADOS ou
/// PROPOSTA). Cada contador abre a aba onde se resolve. Zero é zero e
/// aparece (regra painel-admin-limpo).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';

/// (rótulo, chave do `admin_casa_resumo`, separador que abre).
const List<(String, String, int)> kCasaContadoresResumo = [
  ('Profissionais pendentes', 'profissionais_pendentes', 1),
  ('Ofícios por aprovar', 'oficios_pendentes', 1),
  ('Documentos por analisar', 'documentos_pendentes', 1),
  ('Pedidos ativos', 'pedidos_ativos', 2),
  ('Procurando profissional', 'pedidos_procura', 2),
  ('Orçamentos abertos', 'orcamentos_abertos', 3),
  ('Disputas', 'disputas', 2),
  ('Reembolsos pendentes', 'reembolsos_pendentes', 2),
];

class AdminCasaResumoTab extends StatefulWidget {
  const AdminCasaResumoTab({super.key, this.rpc, this.onIrPara});
  final ChamarRpcPainel? rpc;

  /// Muda de separador no hub (índice de `kCasaSeparadores`).
  final void Function(int separador)? onIrPara;

  @override
  State<AdminCasaResumoTab> createState() => _AdminCasaResumoTabState();
}

class _AdminCasaResumoTabState extends State<AdminCasaResumoTab> {
  late Future<Map<String, dynamic>> _future = _load();

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<Map<String, dynamic>> _load() async =>
      casaMapa(casaVerOk(await _rpc('admin_casa_resumo', {})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
        }
        final m = snap.data ?? const <String, dynamic>{};
        final ligado = m['enabled'] == true;
        final valores = CasaValores.fromJson(m['valores_autorizados']);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.huge),
            children: [
              Card(
                key: ValueKey(ligado ? 'casa-resumo-ligada' : 'casa-resumo-desligada'),
                color: ligado
                    ? AppColors.success.withValues(alpha: 0.10)
                    : AppColors.surface2,
                child: ListTile(
                  leading: Icon(
                    ligado ? Icons.toggle_on : Icons.toggle_off_outlined,
                    color: ligado ? AppColors.success : AppColors.textSecondary,
                    size: 36,
                  ),
                  title: Text(
                    ligado
                        ? 'Casa LIGADA — os clientes veem o ladrilho'
                        : 'Casa DESLIGADA — só os testadores veem',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Interruptor geral em Configurações.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onIrPara?.call(5),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              InkWell(
                onTap: () => widget.onIrPara?.call(5),
                child: CasaAvisoValores(valores: valores),
              ),
              const CasaSeccao('O que espera decisão'),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final (rotulo, chave, separador) in kCasaContadoresResumo)
                    _Contador(
                      rotulo: rotulo,
                      valor: casaInt(m[chave]),
                      chave: chave,
                      onTap: () => widget.onIrPara?.call(separador),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              const Text(
                'Datas e semanas na hora de Lisboa. Os números vêm do servidor '
                '(admin_casa_resumo).',
                style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({
    required this.rotulo,
    required this.valor,
    required this.chave,
    required this.onTap,
  });
  final String rotulo;
  final int valor;
  final String chave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final alerta = valor > 0 &&
        (chave == 'disputas' ||
            chave == 'reembolsos_pendentes' ||
            chave.endsWith('_pendentes'));
    return SizedBox(
      width: 165,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$valor',
                  key: ValueKey('casa-resumo-$chave'),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: alerta ? AppColors.error : AppColors.textPrimary),
                ),
                Text(rotulo,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
