// Painel admin — Farmácias, Bloco 5 (missão farmacias-loja-2026-11-14). PT-BR.
// Peças da ficha de cada farmácia: o que falta antes de abrir ao público (função pura, a mesma
// regra do gatilho do servidor trg_farmacia_abrir_exige_dados) e o formulário "Dados da empresa"
// (nome legal, NIF, IBAN, código da certidão permanente; termos aceitos só leitura).
//
// NIF e IBAN são lidos e gravados pelas RPCs que já existem para o cartão "Dados fiscais (DAC7)"
// da ficha do parceiro (parceiro_dados_fiscais / admin_parceiro_atualizar_dados_fiscais), com a
// mesma validação (compararDadosFiscaisAdmin). Os termos aceitos (dsa_self_certified_at) NÃO se
// editam aqui: ficam preenchidos quando a farmácia aceita os termos no app dela.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/dados_fiscais_parceiro.dart';
import '../../services/admin_farmacias_service.dart';
import '../../services/dados_fiscais_parceiro_service.dart';
import '../../utils/conformidade_mensagem.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_dados_fiscais_card.dart' show compararDadosFiscaisAdmin;

/// "14/11/2026" em hora de Lisboa; "—" sem data.
String dataLisboa(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '—';
  final l = horaLisboa(d);
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

/// Um item da lista "antes de abrir ao público".
class ItemAbrir {
  const ItemAbrir(this.rotulo, this.ok, {this.obrigatorio = true, this.ajuda});
  final String rotulo;
  final bool ok;
  final bool obrigatorio;
  final String? ajuda;
}

/// O que tem de estar pronto antes de abrir a farmácia ao público. Lê só a linha de
/// admin_farmacias_listar (chaves email_demonstracao, dono_user_id, em_falta,
/// business_registration_number). Mesma regra que o servidor aplica ao abrir.
List<ItemAbrir> itensParaAbrir(Map<String, dynamic> f) {
  final falta = codigosEmFalta(f['em_falta']);
  final temDono = (f['dono_user_id'] ?? '').toString().isNotEmpty;
  final emailReal = temDono && f['email_demonstracao'] != true;
  final certidao = (f['business_registration_number'] ?? '').toString().trim().isNotEmpty;
  return [
    ItemAbrir('E-mail de login verdadeiro (não o de demonstração)', emailReal,
        ajuda: temDono ? null : 'A loja não tem conta de dono ligada.'),
    ItemAbrir('Nome legal (razão social da empresa)', !falta.contains('nome')),
    ItemAbrir('NIF (número de contribuinte)', !falta.contains('nif')),
    ItemAbrir('IBAN (número da conta bancária)', !falta.contains('iban')),
    ItemAbrir('Morada fiscal', !falta.contains('morada'),
        ajuda: 'Corrige-se na ficha do parceiro, aba Dados.'),
    if (falta.contains('data_nascimento'))
      const ItemAbrir('Data de nascimento', false,
          ajuda: 'Só se pede quando o NIF é de pessoa singular. Com o NIF da empresa '
              '(começa por 5, 6, 7 ou 9) deixa de ser pedida.'),
    ItemAbrir('Termos aceitos pela farmácia (autocertificação)', !falta.contains('autocertificacao'),
        ajuda: 'Preenche-se sozinho quando a farmácia aceita os termos no app dela.'),
    ItemAbrir('Código da certidão permanente (registo comercial)', certidao, obrigatorio: false),
  ];
}

/// true quando todos os itens obrigatórios estão prontos.
bool podeAbrirAoPublico(List<ItemAbrir> itens) => itens.where((i) => i.obrigatorio).every((i) => i.ok);

/// Frase do erro do servidor ao abrir (gatilho trg_farmacia_abrir_exige_dados ou o portão antigo).
String mensagemErroAbrirFarmacia(Object erro) {
  final t = erro.toString();
  if (t.contains('email_demonstracao')) {
    return 'Não dá para abrir: a conta da farmácia ainda usa o e-mail de demonstração. '
        'Troque pelo e-mail verdadeiro em "Login da farmácia".';
  }
  if (t.contains('conformidade_incompleta')) {
    final rotulos = codigosDoErroConformidade(t).map(rotuloEmFalta).toList();
    return rotulos.isEmpty
        ? 'Não dá para abrir: faltam dados da empresa.'
        : 'Não dá para abrir: faltam ${rotulos.join(', ')}.';
  }
  return t;
}

/// Lista visual do que falta (✓ / ✗).
class AdminFarmaciaChecklist extends StatelessWidget {
  const AdminFarmaciaChecklist({super.key, required this.itens});
  final List<ItemAbrir> itens;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final i in itens)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              i.ok ? Icons.check_circle : (i.obrigatorio ? Icons.cancel : Icons.radio_button_unchecked),
              size: 18,
              color: i.ok ? AppColors.success : (i.obrigatorio ? AppColors.error : AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i.rotulo}${i.obrigatorio ? '' : ' — recomendado'}'),
                if (!i.ok && i.ajuda != null)
                  Text(i.ajuda!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Formulário "Dados da empresa" de uma farmácia. Carrega da rede ao abrir.
class AdminFarmaciaDadosEmpresa extends StatefulWidget {
  const AdminFarmaciaDadosEmpresa({
    super.key,
    required this.restaurantId,
    required this.certidaoAtual,
    required this.aoGravar,
  });

  final String restaurantId;

  /// business_registration_number vindo de admin_farmacias_listar.
  final String? certidaoAtual;

  /// Chamado depois de gravar (o ecrã recarrega a lista e o "o que falta").
  final VoidCallback aoGravar;

  @override
  State<AdminFarmaciaDadosEmpresa> createState() => _AdminFarmaciaDadosEmpresaState();
}

class _AdminFarmaciaDadosEmpresaState extends State<AdminFarmaciaDadosEmpresa> {
  final _svc = AdminFarmaciasService();
  final _nome = TextEditingController();
  final _nif = TextEditingController();
  final _iban = TextEditingController();
  final _certidao = TextEditingController();
  final _motivo = TextEditingController();

  DadosFiscaisParceiro? _dados;
  bool _carregando = true;
  bool _aSalvar = false;
  String? _erro;
  String? _aviso;
  bool _avisoOk = false;

  /// O código da certidão que está no servidor (o da lista, ou o que acabou de ser gravado).
  String? _certidaoBase;

  @override
  void initState() {
    super.initState();
    _certidaoBase = widget.certidaoAtual;
    _certidao.text = _certidaoBase ?? '';
    _carregar(inicial: true);
  }

  @override
  void didUpdateWidget(covariant AdminFarmaciaDadosEmpresa old) {
    super.didUpdateWidget(old);
    if (widget.certidaoAtual != old.certidaoAtual && widget.certidaoAtual != _certidaoBase) {
      _certidaoBase = widget.certidaoAtual;
      _certidao.text = _certidaoBase ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_nome, _nif, _iban, _certidao, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  /// [inicial]: chamado no initState (já começa a carregar; setState ali não é permitido).
  Future<void> _carregar({bool inicial = false}) async {
    if (!inicial) {
      if (!mounted) return;
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final d = await DadosFiscaisParceiroService.ler(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _dados = d;
        _nome.text = d.legalName ?? '';
        _nif.text = d.nif ?? '';
        _iban.text = d.iban ?? '';
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível ler os dados da empresa: $e';
        _carregando = false;
      });
    }
  }

  static String _digitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  void _msg(String m, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _aviso = m;
      _avisoOk = ok;
    });
  }

  Future<void> _salvar() async {
    final antes = _dados;
    if (antes == null || _aSalvar) return;
    // Só nome, NIF e IBAN mudam aqui: morada, data de nascimento e termos vão iguais ao servidor.
    final r = compararDadosFiscaisAdmin(
      antes: antes,
      nome: _nome.text,
      nif: _nif.text,
      morada: antes.address ?? '',
      iban: _iban.text,
      nascimento: antes.birthDate,
      autocertData: antes.autocertificadoEm,
      autocertVersao: antes.autocertVersao ?? '',
    );
    if (r.erro != null) {
      _msg(r.erro!);
      return;
    }
    final alt = r.alteracao!;
    final certNova = _digitos(_certidao.text);
    final mudouCertidao = certNova != _digitos(_certidaoBase ?? '');
    if (mudouCertidao && certNova.isNotEmpty && certNova.length != 12) {
      _msg('O código da certidão permanente tem 12 dígitos (0000-0000-0000).');
      return;
    }
    if (alt.vazia && !mudouCertidao) {
      _msg('Nada mudou — não há o que salvar.');
      return;
    }
    final motivo = _motivo.text.trim();
    if (motivo.length < 3) {
      _msg('Escreva o motivo (ex.: "enviado pela farmácia por e-mail em 14/11").');
      return;
    }
    setState(() {
      _aSalvar = true;
      _aviso = null;
    });
    try {
      if (!alt.vazia) {
        await DadosFiscaisParceiroService.adminAtualizar(
          restaurantId: widget.restaurantId,
          legalName: alt.legalName,
          nif: alt.nif,
          iban: alt.iban,
          motivo: motivo,
        );
      }
      if (mudouCertidao) {
        final gravado = await _svc.definirCertidao(widget.restaurantId, _certidao.text);
        _certidaoBase = gravado;
        _certidao.text = gravado ?? '';
      }
      _motivo.clear();
      _msg('Dados da empresa salvos.', ok: true);
      widget.aoGravar();
      await _carregar();
    } on AdminFarmaciaErro catch (e) {
      _msg(e.mensagem);
    } catch (e) {
      _msg(mensagemErroDadosFiscaisAdmin(e));
    } finally {
      if (mounted) setState(() => _aSalvar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final d = _dados;
    if (_erro != null || d == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_erro ?? 'Sem dados.', style: const TextStyle(color: AppColors.error)),
        TextButton.icon(onPressed: _carregar, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _campo(_nome, 'Nome legal (razão social, como está na certidão)'),
      _campo(_nif, 'NIF (número de contribuinte, 9 dígitos)', teclado: TextInputType.number),
      _campo(_iban, 'IBAN (número da conta bancária: PT + 23 dígitos)'),
      _campo(_certidao, 'Código da certidão permanente (registo comercial, 0000-0000-0000)',
          teclado: TextInputType.number),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'Morada fiscal: ${d.address ?? '— (falta; corrige-se na ficha do parceiro, aba Dados)'}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          d.autocertificadoEm == null
              ? 'Termos aceitos pela farmácia: ainda não. Fica preenchido sozinho quando a farmácia '
                  'aceita os termos no app (autocertificação DSA — declaração de que é um comerciante).'
              : 'Termos aceitos pela farmácia em ${dataHoraLisboa(d.autocertificadoEm!.toUtc().toIso8601String())}'
                  '${d.autocertVersao == null ? '' : ' (versão ${d.autocertVersao})'}. Só leitura.',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      _campo(_motivo, 'Motivo da alteração (obrigatório, fica na auditoria)'),
      if (_aviso != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_aviso!, style: TextStyle(color: _avisoOk ? AppColors.success : AppColors.error)),
        ),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _aSalvar ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          icon: _aSalvar
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Salvar dados da empresa'),
        ),
      ),
    ]);
  }

  Widget _campo(TextEditingController c, String rotulo, {TextInputType? teclado}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder(), isDense: true),
        ),
      );
}
