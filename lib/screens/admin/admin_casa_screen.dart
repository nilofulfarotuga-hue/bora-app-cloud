/// CASA E MANUTENÇÃO (faz-tudo) — hub do painel admin (PT-BR, só o Danilo).
/// Missão casa-manutencao-2026-10-30. Um hub por assunto (regra
/// painel-admin-limpo): tudo da Casa vive aqui, em separadores.
///
///  1. Resumo · 2. Profissionais · 3. Pedidos · 4. Orçamentos ·
///  5. Catálogo e preços · 6. Configurações · 7. Acertos semanais · 8. Exportar
///
/// Tudo por funções `admin_casa_*` do servidor (contrato no ESPEC da missão);
/// o painel não calcula dinheiro, só mostra e pede confirmação antes de cada
/// ação. Entra no menu na secção "Limpeza, Lavagem e Casa".
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import 'admin_casa_acertos_tab.dart';
import 'admin_casa_catalogo_tab.dart';
import 'admin_casa_comum.dart';
import 'admin_casa_definicoes_tab.dart';
import 'admin_casa_exportar_tab.dart';
import 'admin_casa_orcamentos_tab.dart';
import 'admin_casa_pedidos_tab.dart';
import 'admin_casa_profissionais_tab.dart';
import 'admin_casa_resumo_tab.dart';

export 'admin_casa_pedidos_tab.dart' show AdminCasaPedidoScreen;
export 'admin_casa_profissionais_tab.dart' show AdminCasaProfissionalScreen;

/// Separadores, pela ordem (o índice é o que `separadorInicial` usa).
const List<String> kCasaSeparadores = [
  'Resumo',
  'Profissionais',
  'Pedidos',
  'Orçamentos',
  'Catálogo e preços',
  'Configurações',
  'Acertos semanais',
  'Exportar',
];

class AdminCasaScreen extends StatefulWidget {
  const AdminCasaScreen({
    super.key,
    this.separadorInicial = 0,
    this.profissionalId,
    this.pedidoId,
    this.rpc,
  });

  /// Separador que abre primeiro (índice de [kCasaSeparadores]).
  final int separadorInicial;

  /// Abre logo a ficha deste profissional (`casa_profissionais.id`) — usado
  /// pela tela "Papéis e candidaturas" ("Ver documentos").
  final String? profissionalId;

  /// Abre logo a ficha deste pedido (`casa_pedidos.id`) — para avisos.
  final String? pedidoId;

  /// Função do servidor injetável (testes sem rede).
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaScreen> createState() => _AdminCasaScreenState();
}

class _AdminCasaScreenState extends State<AdminCasaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: kCasaSeparadores.length,
    vsync: this,
    initialIndex: widget.profissionalId != null
        ? 1
        : widget.pedidoId != null
            ? 2
            : widget.separadorInicial.clamp(0, kCasaSeparadores.length - 1),
  );

  @override
  void initState() {
    super.initState();
    final prof = widget.profissionalId;
    final pedido = widget.pedidoId;
    if ((prof ?? '').isNotEmpty || (pedido ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => (prof ?? '').isNotEmpty
              ? AdminCasaProfissionalScreen(id: prof!, rpc: widget.rpc)
              : AdminCasaPedidoScreen(id: pedido!, rpc: widget.rpc),
        ));
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rpc = widget.rpc;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Casa e manutenção'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [for (final t in kCasaSeparadores) Tab(text: t)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          AdminCasaResumoTab(rpc: rpc, onIrPara: (i) => _tabs.animateTo(i)),
          AdminCasaProfissionaisTab(rpc: rpc),
          AdminCasaPedidosTab(rpc: rpc),
          AdminCasaOrcamentosTab(rpc: rpc),
          AdminCasaCatalogoTab(rpc: rpc),
          AdminCasaDefinicoesTab(rpc: rpc),
          AdminCasaAcertosTab(rpc: rpc),
          AdminCasaExportarTab(rpc: rpc),
        ],
      ),
    );
  }
}
