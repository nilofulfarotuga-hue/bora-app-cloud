// Painel admin — Farmácias (missão farmacias-2026-11-11; ficha completa a 14/11, missão
// farmacias-loja-2026-11-14, Bloco 5). PT-BR.
// Aba 1 "Farmácias": interruptor global dos pedidos reais de receita e, por farmácia: login (e-mail
//   verdadeiro + link para criar a senha), dados da empresa (nome legal, NIF, IBAN, certidão
//   permanente; termos aceitos só leitura), horário e preços (atalhos para a ficha do parceiro),
//   modo da receita, lista de permissão, comissão extra e data de início, e "Abrir ao público"
//   com a lista do que falta e confirmação forte.
// Aba 2 "Pedidos de receita": todos os estados, quem respondeu e quando, forçar/cancelar, exportar CSV.
// Aba 3 "Extrato semanal": só leitura por farmácia, com exportar CSV.
// Nunca mostra fotos nem códigos da receita (dados de saúde): só "tem foto: sim/não".
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/admin_farmacias_service.dart';
import '../../services/prescricao_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '_admin_password_reset_dialog.dart';
import 'admin_farmacia_ficha.dart';
import 'admin_farmacias_extrato_aba.dart';
import 'admin_partner_detail_screen.dart';

class AdminFarmaciasScreen extends StatelessWidget {
  const AdminFarmaciasScreen({super.key, this.abaInicial = 0});

  /// 0 Farmácias · 1 Pedidos de receita · 2 Extrato semanal.
  final int abaInicial;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: abaInicial.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Farmácias'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Farmácias'), Tab(text: 'Pedidos de receita'), Tab(text: 'Extrato semanal')],
          ),
        ),
        body: const TabBarView(children: [_AbaFarmacias(), AdminPedidosReceitaAba(), AdminFarmaciasExtratoAba()]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── aba Farmácias

class _AbaFarmacias extends StatefulWidget {
  const _AbaFarmacias();
  @override
  State<_AbaFarmacias> createState() => _AbaFarmaciasState();
}

class _AbaFarmaciasState extends State<_AbaFarmacias> {
  final _svc = PrescricaoService();
  final _admin = AdminFarmaciasService();
  late Future<List<Map<String, dynamic>>> _f = _svc.adminFarmacias();
  late Future<bool?> _fReceitasReais = _admin.receitasReaisLigadas();

  void _recarregar() => setState(() {
        _f = _svc.adminFarmacias();
        _fReceitasReais = _admin.receitasReaisLigadas();
      });

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 6)));
  }

  /// Confirmação forte: o botão só acende depois de escrever [palavra] (ex.: ABRIR).
  Future<bool> _confirmarForte({
    required String titulo,
    required List<String> pontos,
    required String palavra,
    required String botao,
  }) async {
    final ctrl = TextEditingController();
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final p in pontos) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $p')),
                const SizedBox(height: 10),
                Text('Para confirmar, escreva $palavra:', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => set(() {}),
                  decoration: InputDecoration(hintText: palavra),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: ctrl.text.trim().toUpperCase() == palavra ? () => Navigator.pop(c, true) : null,
              child: Text(botao),
            ),
          ],
        ),
      ),
    );
    return r == true;
  }

  Future<void> _acao(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  Future<bool> _confirmar(String titulo, String texto) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _mudarModo(Map<String, dynamic> f, String modo) async {
    if (modo == 'publico') {
      if (!await _confirmar('Ligar a receita para TODOS?',
          'Qualquer cliente que veja esta farmácia vai poder enviar receitas. Só ligue depois de a farmácia confirmar com o diretor técnico.')) {
        return;
      }
      if (!await _confirmar('Tem certeza?', 'Confirme outra vez: receita ligada ao público em ${f['name']}.')) return;
    }
    await _acao(() => _svc.adminFarmaciaDefinir(restaurantId: f['id'], modo: modo), 'Modo da receita atualizado.');
  }

  Future<void> _editarLista(Map<String, dynamic> f) async {
    final atual = (f['lista'] as List? ?? const []).map((e) => e.toString()).toList();
    final ctrl = TextEditingController(text: atual.join('\n'));
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lista de permissão'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Um e-mail por linha. Só estas contas (mais o admin e o dono da loja) veem a farmácia enquanto estiver escondida.'),
            const SizedBox(height: 10),
            TextField(controller: ctrl, minLines: 4, maxLines: 10, decoration: const InputDecoration(border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (r == null) return;
    final emails = r.split(RegExp(r'[\s,;]+')).where((e) => e.contains('@')).toList();
    try {
      final naoExistem = await _svc.adminListaPermissaoDefinir(f['id'], emails);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(naoExistem.isEmpty ? 'Lista salva.' : 'Lista salva. Sem conta no app: ${naoExistem.join(', ')}'),
      ));
      _recarregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  static String _pctTexto(num fracao) {
    final v = fracao * 100;
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  /// Comissão extra (percentagem) e data de início — admin_farmacia_definir(p_extra_pct, p_extra_inicio).
  Future<void> _editarComissao(Map<String, dynamic> f) async {
    final pct = TextEditingController(text: _pctTexto((f['partner_extra_commission_pct'] as num?) ?? 0.10));
    final inicioAtual = DateTime.tryParse('${f['partner_extra_commission_starts_at'] ?? ''}');
    DateTime? inicio = inicioAtual == null ? null : horaLisboa(inicioAtual);
    String? erro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Comissão extra da farmácia'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Percentagem sobre o que a farmácia vende pelo app. Só conta a partir da data de início; '
                  'antes disso é zero. Se a data ficar em branco, é marcada sozinha ao abrir ao público '
                  '(dia da abertura + os meses sem comissão das Configurações).'),
              const SizedBox(height: 6),
              const Text('Atenção: isto muda o que a Bora cobra à farmácia. Só salve com a ordem do Danilo.',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: pct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Comissão extra', suffixText: '%'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text(inicio == null
                      ? 'Data de início: ao abrir ao público'
                      : 'Data de início: ${dataLisboa(DateTime.utc(inicio!.year, inicio!.month, inicio!.day, 12).toIso8601String())}'),
                ),
                TextButton(
                  onPressed: () async {
                    final hoje = DateTime.now();
                    final p = await showDatePicker(
                      context: c,
                      initialDate: inicio ?? hoje,
                      firstDate: DateTime(hoje.year - 1),
                      lastDate: DateTime(hoje.year + 3),
                      helpText: 'Início da comissão extra',
                    );
                    if (p != null) set(() => inicio = p);
                  },
                  child: const Text('Escolher data'),
                ),
              ]),
              if (erro != null) Text(erro!, style: const TextStyle(color: AppColors.error)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(pct.text.replaceAll('%', '').replaceAll(',', '.').trim());
                if (v == null || v < 0 || v > 50) {
                  set(() => erro = 'Escreva uma percentagem entre 0 e 50 (ex.: 10).');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.parse(pct.text.replaceAll('%', '').replaceAll(',', '.').trim());
    final d = inicio;
    final antes = inicioAtual == null ? null : horaLisboa(inicioAtual);
    final mudouDia = d != null && (antes == null || antes.year != d.year || antes.month != d.month || antes.day != d.day);
    // Só se manda a data quando o dia mudou (senão a hora exata gravada no servidor ficava igual).
    // Meia-noite de Lisboa do dia escolhido (nunca o fuso do navegador).
    final instante = (mudouDia && d != null) ? instanteDeLisboa(DateTime(d.year, d.month, d.day)) : null;
    await _acao(
      () => _svc.adminFarmaciaDefinir(restaurantId: '${f['id']}', extraPct: v / 100, extraInicio: instante),
      'Comissão extra salva.',
    );
  }

  /// Troca o e-mail de login (Edge Fn admin-farmacia-email) e, se pedido, manda o link para criar
  /// a senha (support-password-reset). Erros aparecem dentro do diálogo.
  Future<void> _trocarEmail(Map<String, dynamic> f) async {
    final novo = TextEditingController();
    final repete = TextEditingController();
    var invalidar = true;
    var link = true;
    var aCorrer = false;
    String? erro;
    final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Future<void> confirmar() async {
            final e = novo.text.trim().toLowerCase();
            String? invalido;
            if (!emailRe.hasMatch(e)) {
              invalido = 'E-mail inválido. Confira se está bem escrito.';
            } else if (e != repete.text.trim().toLowerCase()) {
              invalido = 'Os dois e-mails não são iguais.';
            } else if (RegExp(r'^demo[._+-]').hasMatch(e)) {
              invalido = 'Esse é um e-mail de demonstração. Use o e-mail verdadeiro da farmácia.';
            }
            if (invalido != null) {
              set(() => erro = invalido);
              return;
            }
            set(() {
              aCorrer = true;
              erro = null;
            });
            try {
              final r = await _admin.mudarEmailLogin(
                  restaurantId: '${f['id']}', novoEmail: e, invalidarSenha: invalidar);
              var msg = 'E-mail de login trocado para ${r['email_novo']}.';
              if (link) {
                try {
                  await _admin.enviarLinkSenha(userId: '${r['user_id']}', email: '${r['email_novo']}');
                  msg += ' Link para criar a senha enviado.';
                } on AdminFarmaciaErro catch (x) {
                  msg += ' ${x.mensagem} Use "Mandar link de senha" para tentar de novo.';
                }
              }
              if (c.mounted) Navigator.pop(c, msg);
            } on AdminFarmaciaErro catch (x) {
              set(() {
                aCorrer = false;
                erro = x.mensagem;
              });
            }
          }

          return AlertDialog(
            title: Text('Trocar o e-mail de login — ${f['name']}'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('E-mail atual: ${f['dono_email'] ?? '—'}'),
                  const SizedBox(height: 4),
                  const Text(
                    'Muda o e-mail com que a farmácia entra no app (login) e o e-mail de contacto da loja. '
                    'A conta, os produtos e os pedidos ficam iguais.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: novo,
                    enabled: !aCorrer,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail verdadeiro da farmácia'),
                  ),
                  TextField(
                    controller: repete,
                    enabled: !aCorrer,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Repita o e-mail'),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: invalidar,
                    onChanged: aCorrer ? null : (v) => set(() => invalidar = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Cancelar a senha de demonstração (recomendado)'),
                    subtitle: const Text('Quem sabia a senha de teste deixa de conseguir entrar nesta conta.'),
                  ),
                  CheckboxListTile(
                    value: link,
                    onChanged: aCorrer ? null : (v) => set(() => link = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Mandar já o link para a farmácia criar a senha'),
                    subtitle: const Text('Chega ao e-mail novo. O link vale 1 hora e pode ser reenviado.'),
                  ),
                  if (erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(erro!, style: const TextStyle(color: AppColors.error)),
                    ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: aCorrer ? null : () => Navigator.pop(c), child: const Text('Cancelar')),
              FilledButton(
                onPressed: aCorrer ? null : confirmar,
                child: aCorrer
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Trocar e-mail'),
              ),
            ],
          );
        },
      ),
    );
    if (resultado == null) return;
    _aviso(resultado);
    _recarregar();
  }

  void _enviarLinkSenha(Map<String, dynamic> f) {
    final uid = (f['dono_user_id'] ?? '').toString();
    final email = (f['dono_email'] ?? '').toString();
    if (uid.isEmpty || email.isEmpty) {
      _aviso('Esta farmácia não tem conta de dono ligada.');
      return;
    }
    showAdminPasswordResetDialog(context, userId: uid, email: email, displayName: '${f['name']}');
  }

  void _abrirFicha(Map<String, dynamic> f, int aba) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdminPartnerDetailScreen(restaurantId: '${f['id']}', initialName: '${f['name']}', abaInicial: aba),
    ));
  }

  /// Interruptor global platform_settings.pharmacy_prescription_real_orders_enabled.
  Future<void> _mudarReceitasReais(bool ligar) async {
    final ok = ligar
        ? await _confirmarForte(
            titulo: 'Ligar os pedidos reais de receita?',
            pontos: const [
              'Vale para TODAS as farmácias abertas ao público.',
              'Quando o cliente confirma uma receita, cria-se um pedido de verdade: chama um entregador '
                  'e cobra o cliente (cartão, MB Way ou dinheiro).',
              'Só ligue depois de testado de ponta a ponta e com o "vai" do Danilo.',
            ],
            palavra: 'LIGAR',
            botao: 'Ligar pedidos reais',
          )
        : await _confirmar('Desligar os pedidos reais de receita?',
            'As receitas confirmadas deixam de criar pedido com entregador e cobrança. Os pedidos que já existem não mudam.');
    if (!ok) return;
    try {
      await _admin.definirReceitasReais(ligar);
      _aviso(ligar ? 'Pedidos reais de receita LIGADOS.' : 'Pedidos reais de receita desligados.');
      _recarregar();
    } on AdminFarmaciaErro catch (e) {
      _aviso(e.mensagem);
    }
  }

  Future<void> _abrir(Map<String, dynamic> f) async {
    final itens = itensParaAbrir(f);
    if (!podeAbrirAoPublico(itens)) {
      final falta = itens.where((i) => i.obrigatorio && !i.ok).map((i) => i.rotulo).join('; ');
      _aviso('Ainda falta: $falta.');
      return;
    }
    final semData = f['partner_extra_commission_starts_at'] == null && f['partner_extra_commission_pct'] != null;
    if (!await _confirmarForte(
      titulo: 'Abrir ${f['name']} ao público?',
      pontos: [
        'Todos os clientes passam a ver a farmácia: categoria Farmácias, pesquisa e faixas da página inicial.',
        'A lista de permissão deixa de contar (fica guardada, mas já não esconde nada).',
        if (semData) 'Começa a contar o período sem comissão extra; a data de início fica marcada hoje + os meses das Configurações.',
        'A receita continua no modo escolhido (${f['pharmacy_prescription_mode'] ?? 'desligado'}).',
        'Antes de confirmar: a farmácia já aceitou os termos e os dados da empresa estão certos.',
      ],
      palavra: 'ABRIR',
      botao: 'Abrir ao público',
    )) {
      return;
    }
    try {
      await _svc.adminFarmaciaAbrir('${f['id']}');
      _aviso('Farmácia aberta ao público.');
      _recarregar();
    } catch (e) {
      _aviso(mensagemErroAbrirFarmacia(e));
    }
  }

  /// Volta a esconder (só a lista de permissão vê) — admin_farmacia_definir(p_so_lista: true).
  Future<void> _esconder(Map<String, dynamic> f) async {
    if (!await _confirmar('Voltar a esconder ${f['name']}?',
        'Só as contas da lista de permissão, o admin e o dono voltam a ver a farmácia. Os clientes deixam de a ver.')) {
      return;
    }
    await _acao(() => _svc.adminFarmaciaDefinir(restaurantId: '${f['id']}', soLista: true), 'Farmácia escondida outra vez.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        // Ao recarregar mantém-se a lista anterior à vista (os formulários abertos não se perdem).
        if (!s.hasData) {
          if (s.hasError) return Center(child: Text(PrescricaoService.mensagemDe(s.error!)));
          return const Center(child: CircularProgressIndicator());
        }
        final l = s.data!;
        return RefreshIndicator(
          onRefresh: () async => _recarregar(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              FutureBuilder<bool?>(
                future: _fReceitasReais,
                builder: (context, r) {
                  final pronto = r.connectionState == ConnectionState.done;
                  return AdminReceitasReaisCartao(
                    ligado: pronto ? r.data : null,
                    erro: pronto && r.data == null,
                    aoMudar: _mudarReceitasReais,
                  );
                },
              ),
              for (final f in l)
                AdminFarmaciaCartao(
                  key: ValueKey('farmacia-${f['id']}'),
                  farmacia: f,
                  aoMudarModo: (m) => _mudarModo(f, m),
                  aoEditarLista: () => _editarLista(f),
                  aoEditarComissao: () => _editarComissao(f),
                  aoAbrir: () => _abrir(f),
                  formatarData: dataLisboa,
                  aoTrocarEmail: () => _trocarEmail(f),
                  aoEnviarLinkSenha: () => _enviarLinkSenha(f),
                  aoAbrirHorario: () => _abrirFicha(f, 1),
                  aoAbrirPrecos: () => _abrirFicha(f, 5),
                  aoEsconder: () => _esconder(f),
                  dadosEmpresa: AdminFarmaciaDadosEmpresa(
                    restaurantId: '${f['id']}',
                    certidaoAtual: f['business_registration_number'] as String?,
                    aoGravar: _recarregar,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Interruptor global dos pedidos reais de receita (testável sem rede).
class AdminReceitasReaisCartao extends StatelessWidget {
  const AdminReceitasReaisCartao({super.key, required this.ligado, required this.aoMudar, this.erro = false});

  /// null = a ler (ou erro).
  final bool? ligado;
  final bool erro;
  final ValueChanged<bool> aoMudar;

  @override
  Widget build(BuildContext context) {
    final l = ligado;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: SwitchListTile(
        value: l ?? false,
        onChanged: l == null ? null : aoMudar,
        title: const Text('Pedidos reais de receita (todas as farmácias)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          erro
              ? 'Não consegui ler o estado. Puxe para baixo para tentar de novo.'
              : l == null
                  ? 'A ler o estado…'
                  : l
                      ? 'LIGADO: ao confirmar uma receita numa farmácia aberta ao público cria-se um pedido com '
                          'entregador e cobrança.'
                      : 'DESLIGADO (fase de testes): o cliente confirma a receita, mas não se cria pedido com '
                          'entregador nem cobrança. Mudar pede confirmação.',
        ),
      ),
    );
  }
}

/// Cartão de uma farmácia (testável sem rede: tudo o que fala com o servidor vem por callbacks,
/// e o formulário "Dados da empresa" vem já construído em [dadosEmpresa]).
class AdminFarmaciaCartao extends StatelessWidget {
  const AdminFarmaciaCartao({
    super.key,
    required this.farmacia,
    required this.aoMudarModo,
    required this.aoEditarLista,
    required this.aoEditarComissao,
    required this.aoAbrir,
    required this.formatarData,
    this.aoTrocarEmail,
    this.aoEnviarLinkSenha,
    this.aoAbrirHorario,
    this.aoAbrirPrecos,
    this.aoEsconder,
    this.dadosEmpresa,
  });

  final Map<String, dynamic> farmacia;
  final ValueChanged<String> aoMudarModo;
  final VoidCallback aoEditarLista;
  final VoidCallback aoEditarComissao;
  final VoidCallback aoAbrir;
  final String Function(dynamic) formatarData;
  final VoidCallback? aoTrocarEmail;
  final VoidCallback? aoEnviarLinkSenha;
  final VoidCallback? aoAbrirHorario;
  final VoidCallback? aoAbrirPrecos;
  final VoidCallback? aoEsconder;
  final Widget? dadosEmpresa;

  static const _titulo = TextStyle(fontWeight: FontWeight.w700);
  static const _pequeno = TextStyle(color: AppColors.textSecondary, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final f = farmacia;
    final escondida = f['so_lista_permissao'] == true;
    final lista = (f['lista'] as List? ?? const []).map((e) => e.toString()).toList();
    final pct = (f['partner_extra_commission_pct'] as num?);
    final demo = f['email_demonstracao'] == true;
    final temDono = (f['dono_user_id'] ?? '').toString().isNotEmpty;
    final itens = itensParaAbrir(f);
    final pode = podeAbrirAoPublico(itens);
    final certidao = (f['business_registration_number'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${f['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            Chip(
              label: Text(escondida ? 'Escondida (só a lista)' : 'Aberta ao público'),
              backgroundColor: escondida ? const Color(0xFFFFF7ED) : AppColors.primaryWash,
            ),
          ]),
          Text('${f['id']} · ${f['produtos'] ?? 0} produtos '
              '(${f['produtos_provisorios'] ?? 0} com preço provisório da Glovo) · ${f['pedidos_receita'] ?? 0} pedidos de receita'
              '${f['is_partner'] == false ? ' · não parceira' : ''}'),
          // ── Login ───────────────────────────────────────────────────────────────────────
          const Divider(height: 24),
          Row(children: [
            const Expanded(child: Text('Login da farmácia', style: _titulo)),
            if (demo)
              Chip(
                label: const Text('e-mail de demonstração'),
                backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                visualDensity: VisualDensity.compact,
              ),
          ]),
          if (!temDono)
            const Text('Sem conta de dono ligada a esta loja.')
          else ...[
            Text('E-mail de login (conta do dono): ${f['dono_email'] ?? '—'}'),
            Text('E-mail da loja (contacto): ${f['email'] ?? '—'}'),
            Text(
              'Último acesso: ${dataHoraLisboa(f['dono_ultimo_login'])} · '
              'último link de senha: ${f['dono_link_senha_em'] == null ? 'nunca' : dataHoraLisboa(f['dono_link_senha_em'])}',
              style: _pequeno,
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: aoTrocarEmail,
                icon: const Icon(Icons.alternate_email, size: 18),
                label: const Text('Trocar e-mail'),
              ),
              OutlinedButton.icon(
                // Para um e-mail de demonstração não se manda link (não é caixa de ninguém).
                onPressed: demo ? null : aoEnviarLinkSenha,
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text('Mandar link de senha'),
              ),
            ]),
          ],
          // ── Dados da empresa ────────────────────────────────────────────────────────────
          const Divider(height: 24),
          if (dadosEmpresa != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Dados da empresa', style: _titulo),
              subtitle: Text(
                'Nome legal: ${f['legal_name'] ?? '—'} · certidão permanente: ${certidao.isEmpty ? '—' : certidao} · '
                'termos aceitos: ${f['dsa_self_certified_at'] == null ? 'ainda não' : formatarData(f['dsa_self_certified_at'])}',
                style: _pequeno,
              ),
              children: [dadosEmpresa!],
            ),
          // ── Horário e preços ────────────────────────────────────────────────────────────
          const Divider(height: 24),
          const Text('Horário e preços', style: _titulo),
          const Text('Abrem a ficha do parceiro já na aba certa (o mesmo editor das outras lojas).', style: _pequeno),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: aoAbrirHorario,
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Editar horário'),
            ),
            OutlinedButton.icon(
              onPressed: aoAbrirPrecos,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('Ver e editar preços'),
            ),
          ]),
          const Divider(height: 24),
          const Text('Receita e botões da farmácia', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'desligado', label: Text('Desligado')),
              ButtonSegment(value: 'so_lista', label: Text('Só a lista')),
              ButtonSegment(value: 'publico', label: Text('Público')),
            ],
            selected: {(f['pharmacy_prescription_mode'] ?? 'desligado').toString()},
            onSelectionChanged: (s) => aoMudarModo(s.first),
          ),
          const SizedBox(height: 4),
          const Text('"Só a lista" = só as contas da lista de permissão, o admin e o dono veem os botões e enviam receitas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Divider(height: 24),
          Row(children: [
            const Expanded(child: Text('Lista de permissão', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: aoEditarLista, icon: const Icon(Icons.edit, size: 18), label: const Text('Editar')),
          ]),
          if (lista.isEmpty) const Text('Ninguém na lista.') else for (final e in lista) Text('• $e'),
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: Text(
                'Comissão extra: ${pct == null ? 'nenhuma' : '${(pct * 100).toStringAsFixed(0)}%'} · '
                'começa em ${formatarData(f['partner_extra_commission_starts_at'])}'
                '${f['partner_extra_commission_starts_at'] == null ? ' (marcada ao abrir ao público)' : ''}',
              ),
            ),
            TextButton(onPressed: aoEditarComissao, child: const Text('Editar')),
          ]),
          // ── Abrir ao público ────────────────────────────────────────────────────────────
          const Divider(height: 24),
          if (escondida) ...[
            const Text('Antes de abrir ao público', style: _titulo),
            const SizedBox(height: 6),
            AdminFarmaciaChecklist(itens: itens),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: pode ? aoAbrir : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.storefront),
                label: Text(pode ? 'Abrir ao público' : 'Abrir ao público (complete o que falta acima)'),
              ),
            ),
          ] else
            Row(children: [
              Expanded(child: Text('Aberta ao público em ${formatarData(f['aberta_ao_publico_em'])}')),
              if (aoEsconder != null) TextButton(onPressed: aoEsconder, child: const Text('Voltar a esconder')),
            ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── aba Pedidos de receita

const kEstadosReceita = <String, String>{
  'enviado': 'À espera da farmácia',
  'aceite': 'Aceito',
  'aceite_parcial': 'Aceito em parte',
  'recusado': 'Recusado',
  'expirado': 'Expirado',
  'cancelado': 'Cancelado',
  'confirmado': 'Confirmado',
  'entregue': 'Entregue',
};

class AdminPedidosReceitaAba extends StatefulWidget {
  const AdminPedidosReceitaAba({super.key});
  @override
  State<AdminPedidosReceitaAba> createState() => _AdminPedidosReceitaAbaState();
}

class _AdminPedidosReceitaAbaState extends State<AdminPedidosReceitaAba> {
  final _svc = PrescricaoService();
  String? _estado;
  late Future<List<Map<String, dynamic>>> _f = _svc.adminListar();

  void _recarregar() => setState(() => _f = _svc.adminListar(estado: _estado));

  String _dt(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _forcar(Map<String, dynamic> r, {bool cancelar = false}) async {
    String estado = cancelar ? 'cancelado' : (r['estado'] ?? 'enviado').toString();
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cancelar ? 'Cancelar pedido de receita' : 'Forçar estado'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!cancelar)
              DropdownButton<String>(
                value: estado,
                isExpanded: true,
                items: [for (final e in kEstadosReceita.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => estado = v ?? estado),
              ),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (obrigatório)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (motivo.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Motivo obrigatório.')));
      return;
    }
    try {
      await _svc.adminForcar(r['id'].toString(), estado: estado, motivo: motivo.text.trim());
      _recarregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        final linhas = s.data ?? const <Map<String, dynamic>>[];
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _estado == null,
                onSelected: (_) {
                  _estado = null;
                  _recarregar();
                },
              ),
              for (final e in kEstadosReceita.entries) ...[
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(e.value),
                  selected: _estado == e.key,
                  onSelected: (_) {
                    _estado = e.key;
                    _recarregar();
                  },
                ),
              ],
              const SizedBox(width: 12),
              AdminCsvButton(
                nome: 'pedidos_receita',
                colunas: const [
                  ('created_at', 'Data'),
                  ('loja', 'Loja'),
                  ('cliente_email', 'Cliente'),
                  ('tipo', 'Tipo'),
                  ('estado_txt', 'Estado'),
                  ('respondido_por_email', 'Respondido por'),
                  ('respondido_em', 'Respondido em'),
                  ('valor_txt', 'Valor remédios'),
                  ('taxa_txt', 'Taxa'),
                  ('total_txt', 'Total'),
                  ('metodo_pagamento', 'Método'),
                  ('demo_txt', 'Demonstração'),
                  ('foto_txt', 'Tem foto'),
                ],
                linhas: () => [
                  for (final r in linhas)
                    {
                      ...r,
                      'estado_txt': kEstadosReceita[r['estado']] ?? '${r['estado']}',
                      'valor_txt': eurosDeCents((r['valor_medicamentos_cents'] as num?)?.toInt()),
                      'taxa_txt': eurosDeCents((r['taxa_servico_cents'] as num?)?.toInt()),
                      'total_txt': eurosDeCents((r['total_cents'] as num?)?.toInt()),
                      'demo_txt': r['is_demo'] == true ? 'sim' : 'não',
                      'foto_txt': r['tem_foto'] == true ? 'sim' : 'não',
                    },
                ],
              ),
            ]),
          ),
          Expanded(
            child: s.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : s.hasError
                    ? Center(child: Text(PrescricaoService.mensagemDe(s.error!)))
                    : linhas.isEmpty
                        ? const Center(child: Text('Nenhum pedido de receita.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: linhas.length,
                            itemBuilder: (context, i) {
                              final r = linhas[i];
                              return Card(
                                child: ListTile(
                                  title: Text('${r['loja']} · ${kEstadosReceita[r['estado']] ?? r['estado']}'
                                      '${r['is_demo'] == true ? ' · demonstração' : ''}'),
                                  subtitle: Text([
                                    _dt(r['created_at']),
                                    r['tipo'] == 'receita' ? 'Receita' : 'Pedido especial',
                                    '${r['cliente_email'] ?? ''}',
                                    if (r['respondido_em'] != null) 'respondido ${_dt(r['respondido_em'])} por ${r['respondido_por_email'] ?? '—'}',
                                    if (r['total_cents'] != null) 'total ${eurosDeCents((r['total_cents'] as num).toInt())}',
                                    'foto: ${r['tem_foto'] == true ? 'sim' : 'não'}',
                                  ].join(' · ')),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) => _forcar(r, cancelar: v == 'cancelar'),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'forcar', child: Text('Forçar estado')),
                                      PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ]);
      },
    );
  }
}
