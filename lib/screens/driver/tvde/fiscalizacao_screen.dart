import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../services/ficha_legal_service.dart';
import 'ficha_legal_form_screen.dart';

/// "Mostrar à autoridade" — o que a PSP/GNR pede numa fiscalização TVDE, num
/// só ecrã (Lei 45/2018 revista pela Lei 59/2026, em vigor desde 01/09/2026):
/// motorista, veículo, operador, plataforma, seguro, inspeção, dístico e a
/// viagem em curso. Igual ao que a Uber e a Bolt mostram.
///
/// Ecrã inteiro, fundo claro e letra grande: é lido por outra pessoa, de pé,
/// muitas vezes à noite e através do vidro. Funciona sem rede com a última
/// cópia guardada — e diz que é cópia.
class FiscalizacaoScreen extends StatefulWidget {
  const FiscalizacaoScreen({super.key});

  @override
  State<FiscalizacaoScreen> createState() => _FiscalizacaoScreenState();
}

class _FiscalizacaoScreenState extends State<FiscalizacaoScreen> {
  FichaFiscalizacao? _ficha;
  String? _erro;
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _carregar();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final f = await FichaLegalService.carregarFiscalizacao();
      if (mounted) setState(() => _ficha = f);
    } catch (_) {
      if (mounted) {
        setState(() => _erro =
            'Sem ligação e ainda sem cópia guardada neste telemóvel. Abre este ecrã uma vez com rede para ficar disponível offline.');
      }
    }
  }

  Future<void> _enviarCopia() async {
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final email = await FichaLegalService.enviarCopiaPorEmail();
      messenger.showSnackBar(SnackBar(
          content: Text('Cópia em PDF enviada para $email.')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Não foi possível enviar agora. Tenta de novo quando tiveres rede.')));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  Future<void> _editar() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const FichaLegalFormScreen()));
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final f = _ficha;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _Topo(onFechar: () => Navigator.of(context).maybePop()),
            if (f?.offline == true)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF7ED),
                padding: const EdgeInsets.all(10),
                child: Text(
                  'Sem rede — cópia guardada de ${FichaTexto.dataHora(f!.geradoEm)}.',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            Expanded(
              child: f == null
                  ? Center(
                      child: _erro == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_erro!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 18)),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _carregar,
                                      child: const Text('Tentar de novo')),
                                ],
                              ),
                            ),
                    )
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          _Motorista(f),
                          _Veiculo(f),
                          _Entidades(f),
                          _Viagem(f),
                          _Documentos(f),
                          _Qr(f),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _aEnviar ? null : _enviarCopia,
                              icon: _aEnviar
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.picture_as_pdf),
                              label: const Text('Enviar cópia por e-mail',
                                  style: TextStyle(fontSize: 17)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _editar,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Atualizar os meus dados'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({required this.onFechar});
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.local_police_outlined, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Fiscalização TVDE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: onFechar,
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo, this.linhas);
  final String titulo;
  final List<Widget> linhas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: const TextStyle(
                  fontSize: 14,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 6),
          ...linhas,
          const Divider(height: 22),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {this.grande = false});
  final String rotulo;
  final String? valor;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final v = (valor == null || valor!.trim().isEmpty) ? '—' : valor!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
          Text(v,
              style: TextStyle(
                  fontSize: grande ? 34 : 20,
                  fontWeight: grande ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: grande ? 2 : 0,
                  color: const Color(0xFF111827))),
        ],
      ),
    );
  }
}

class _Motorista extends StatelessWidget {
  const _Motorista(this.f);
  final FichaFiscalizacao f;

  @override
  Widget build(BuildContext context) {
    final m = f.motorista;
    final foto = m['foto']?.toString();
    return _Secao('Motorista', [
      Row(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primaryWash,
            backgroundImage:
                (foto != null && foto.isNotEmpty) ? NetworkImage(foto) : null,
            child: (foto == null || foto.isEmpty)
                ? const Icon(Icons.person, size: 44, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(m['nome']?.toString() ?? '—',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _Linha('Certificado de motorista TVDE (IMT)',
          '${m['tvde_cert_numero'] ?? '—'} · válido até ${FichaTexto.data(m['tvde_cert_validade']?.toString())}'),
      _Linha('Carta de condução',
          '${m['carta_numero'] ?? '—'} · válida até ${FichaTexto.data(m['carta_validade']?.toString())}'),
      _Linha('NIF', m['nif']?.toString()),
    ]);
  }
}

class _Veiculo extends StatelessWidget {
  const _Veiculo(this.f);
  final FichaFiscalizacao f;

  @override
  Widget build(BuildContext context) {
    final v = f.veiculo;
    final cobre = v['seguro_cobre_passageiros'];
    return _Secao('Veículo', [
      _Linha('Matrícula', v['matricula']?.toString(), grande: true),
      _Linha('Marca / modelo · cor · ano',
          '${v['marca_modelo'] ?? '—'} · ${v['cor'] ?? '—'} · ${v['ano'] ?? '—'}'),
      _Linha('Dístico TVDE (IMT)',
          '${v['distico_numero'] ?? '—'} · válido até ${FichaTexto.data(v['distico_validade']?.toString())}'),
      _Linha('Inspeção periódica',
          'válida até ${FichaTexto.data(v['inspecao_validade']?.toString())}'),
      _Linha('Seguro',
          '${v['seguro_seguradora'] ?? '—'} · apólice ${v['seguro_apolice'] ?? '—'}'),
      _Linha('Seguro válido até · cobre passageiros',
          '${FichaTexto.data(v['seguro_validade']?.toString())} · ${cobre == true ? 'sim' : cobre == false ? 'não' : '—'}'),
    ]);
  }
}

class _Entidades extends StatelessWidget {
  const _Entidades(this.f);
  final FichaFiscalizacao f;

  @override
  Widget build(BuildContext context) {
    final o = f.operador;
    final p = f.plataforma;
    return _Secao('Operador e plataforma', [
      _Linha(
          'Operador TVDE',
          o == null
              ? 'Motorista por conta própria (sem frota)'
              : '${o['nome']} · NIF ${o['nif'] ?? '—'} · licença IMT ${o['licenca'] ?? '—'}'),
      _Linha('Operador de plataforma',
          '${p['nome'] ?? 'Bora'} · NIF ${p['nif'] ?? 'em processo'} · licença IMT ${p['licenca'] ?? 'em processo'}'),
      if (p['em_processo'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
              'Licença de operador de plataforma em processo de registo.',
              style: TextStyle(fontSize: 14, color: Color(0xFF92400E))),
        ),
    ]);
  }
}

class _Viagem extends StatelessWidget {
  const _Viagem(this.f);
  final FichaFiscalizacao f;

  @override
  Widget build(BuildContext context) {
    final v = f.viagem;
    if (v == null) {
      return const _Secao('Viagem', [_Linha('Estado', 'Sem viagens registadas')]);
    }
    final emCurso = v['em_curso'] == true;
    final preco = v['preco_cents'] is num ? (v['preco_cents'] as num).toInt() : null;
    return _Secao(emCurso ? 'Viagem em curso' : 'Última viagem', [
      _Linha('Início', FichaTexto.dataHora(v['inicio']?.toString())),
      _Linha('Origem', v['origem']?.toString()),
      _Linha('Destino', v['destino']?.toString()),
      _Linha(v['preco_final'] == true ? 'Preço cobrado' : 'Preço estimado',
          FichaTexto.euro(preco)),
      _Linha('Pagamento · passageiro',
          '${FichaTexto.meio(v['pagamento']?.toString())} · ${v['passageiro_inicial'] ?? '—'}'),
    ]);
  }
}

class _Documentos extends StatelessWidget {
  const _Documentos(this.f);
  final FichaFiscalizacao f;

  Color _cor(String e) => switch (e) {
        'valido' => AppColors.success,
        'a_expirar' => AppColors.warning,
        'expirado' => AppColors.error,
        _ => const Color(0xFF9CA3AF),
      };

  @override
  Widget build(BuildContext context) {
    return _Secao('Validade dos documentos', [
      for (final d in f.documentos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.circle, size: 14, color: _cor(d.estado)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(d.rotulo, style: const TextStyle(fontSize: 18))),
              Text(
                  '${FichaTexto.estado(d.estado)}${d.validade == null ? '' : ' · ${FichaTexto.data(d.validade)}'}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _cor(d.estado))),
            ],
          ),
        ),
    ]);
  }
}

class _Qr extends StatelessWidget {
  const _Qr(this.f);
  final FichaFiscalizacao f;

  @override
  Widget build(BuildContext context) {
    final url = f.verificacao['url']?.toString();
    final valido = f.tokenValido(DateTime.now().toUtc());
    return _Secao('Verificação pela autoridade', [
      if (url == null || !valido)
        const _Linha('Código de verificação',
            'Expirado. Liga a rede e reabre este ecrã para gerar um novo.')
      else ...[
        Center(
          child: QrImageView(
            data: url,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: SelectableText(url,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15)),
        ),
        Center(
          child: Text(
              'Gerado a ${FichaTexto.dataHora(f.verificacao['criado_em']?.toString())} · válido até ${FichaTexto.dataHora(f.verificacao['expira_em']?.toString())}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
        ),
      ],
    ]);
  }
}
