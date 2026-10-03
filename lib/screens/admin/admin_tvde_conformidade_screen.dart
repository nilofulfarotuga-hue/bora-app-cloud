// lib/screens/admin/admin_tvde_conformidade_screen.dart
//
// [tvde-conformidade-lei-59-2026] Painel admin (PT-BR): "Conformidade TVDE
// (IMT/AMT)". Tudo o que a Lei 45/2018 (revista pela Lei 59/2026) pede à
// plataforma TVDE, num só ecrã com 12 separadores:
//   1 Interruptores · 2 Operadores · 3 Veículos · 4 Motoristas · 5 A caducar
//   6 Horas · 7 Queixas · 8 Fiscalização · 9 Relatório AMT · 10 Teto 25%
//   11 Checklist "Pronto para licenciamento" · 12 Registo (auditoria)
//
// Siglas: IMT = Instituto da Mobilidade e dos Transportes (licencia operadores
// e veículos); AMT = Autoridade da Mobilidade e dos Transportes (regula e
// recebe a contribuição de 5%); CMTVDE = certificado de motorista TVDE.
//
// Todas as ações passam pelas RPCs `admin_tvde_*` (migration
// 20260930123000_tvde_conformidade_rpcs.sql) — nunca UPDATE direto. Cada uma
// guarda is_admin() e escreve em tvde_compliance_events / admin_audit_log.
// A função que chama as RPCs é injetável ([rpc]) para os testes.
import 'package:flutter/material.dart';

import 'tvde_conformidade/_comum.dart';
import 'tvde_conformidade/a_caducar_tab.dart';
import 'tvde_conformidade/amt_tab.dart';
import 'tvde_conformidade/checklist_tab.dart';
import 'tvde_conformidade/fiscalizacao_tab.dart';
import 'tvde_conformidade/horas_tab.dart';
import 'tvde_conformidade/interruptores_tab.dart';
import 'tvde_conformidade/motoristas_tab.dart';
import 'tvde_conformidade/operadores_tab.dart';
import 'tvde_conformidade/queixas_tab.dart';
import 'tvde_conformidade/registo_tab.dart';
import 'tvde_conformidade/teto_tab.dart';
import 'tvde_conformidade/veiculos_tab.dart';

export 'tvde_conformidade/_comum.dart' show TvdeRpc, TvdeGuardarCsv, TvdeGuardarPdf;

/// Rótulos dos separadores, pela ordem.
const List<String> kTvdeSeparadores = [
  'Interruptores',
  'Operadores',
  'Veículos',
  'Motoristas',
  'A caducar',
  'Horas',
  'Queixas',
  'Fiscalização',
  'Relatório AMT',
  'Teto 25%',
  'Checklist',
  'Registo',
];

class AdminTvdeConformidadeScreen extends StatelessWidget {
  const AdminTvdeConformidadeScreen({
    super.key,
    this.rpc,
    this.guardarCsv,
    this.guardarPdf,
    this.separadorInicial = 0,
  });

  /// Chama as RPCs (por defeito `Supabase.instance.client.rpc`).
  final TvdeRpc? rpc;

  /// Entrega CSVs (por defeito AdminExportService.exportCsvText).
  final TvdeGuardarCsv? guardarCsv;

  /// Entrega PDFs (por defeito AdminExportService.exportPdfTable).
  final TvdeGuardarPdf? guardarPdf;

  /// Separador aberto ao entrar (0 = Interruptores, 10 = Checklist).
  final int separadorInicial;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kTvdeSeparadores.length,
      initialIndex: separadorInicial.clamp(0, kTvdeSeparadores.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conformidade TVDE (IMT/AMT)'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in kTvdeSeparadores) Tab(text: t)],
          ),
        ),
        body: TabBarView(children: [
          TvdeInterruptoresTab(rpc: rpc),
          TvdeOperadoresTab(rpc: rpc),
          TvdeVeiculosTab(rpc: rpc),
          TvdeMotoristasTab(rpc: rpc),
          TvdeACaducarTab(rpc: rpc, guardarCsv: guardarCsv),
          TvdeHorasTab(rpc: rpc, guardarCsv: guardarCsv),
          TvdeQueixasTab(rpc: rpc),
          TvdeFiscalizacaoTab(rpc: rpc, guardarCsv: guardarCsv, guardarPdf: guardarPdf),
          TvdeAmtTab(rpc: rpc, guardarCsv: guardarCsv),
          TvdeTetoTab(rpc: rpc),
          TvdeChecklistTab(rpc: rpc),
          TvdeRegistoTab(rpc: rpc, guardarCsv: guardarCsv),
        ]),
      ),
    );
  }
}
