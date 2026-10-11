import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

/// App do estafeta/motorista (PT-PT) — interruptor "Aceito chamadas de
/// reforço quando estou desligado".
///
/// Decisão do Danilo de 10/10/2026: só pode ser chamado desligado quem ligar
/// isto. DESLIGADO por defeito. Lê e grava a própria linha em
/// `chamada_reforco_consentimento` (user_id = auth.uid(); RLS: o próprio lê,
/// cria e muda a sua). Se a tabela ainda não existir no servidor (ou não
/// houver sessão), o interruptor não aparece.
class ChamadaReforcoTile extends StatefulWidget {
  const ChamadaReforcoTile({super.key, this.userId, this.ler, this.gravar});

  /// Só para testes: substituem a sessão e as chamadas ao servidor.
  final String? userId;
  final Future<bool> Function(String uid)? ler;
  final Future<void> Function(String uid, bool ligado)? gravar;

  @override
  State<ChamadaReforcoTile> createState() => _ChamadaReforcoTileState();
}

class _ChamadaReforcoTileState extends State<ChamadaReforcoTile> {
  static const _tabela = 'chamada_reforco_consentimento';

  String? _uid;
  bool _visivel = false;
  bool _ligado = false;
  bool _gravando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _lerDoServidor(String uid) async {
    final r = await Supabase.instance.client
        .from(_tabela)
        .select('ligado')
        .eq('user_id', uid)
        .maybeSingle();
    return r?['ligado'] == true;
  }

  Future<void> _gravarNoServidor(String uid, bool ligado) async {
    await Supabase.instance.client
        .from(_tabela)
        .upsert({'user_id': uid, 'ligado': ligado}, onConflict: 'user_id');
  }

  Future<void> _load() async {
    try {
      final uid =
          widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return;
      final ligado = await (widget.ler ?? _lerDoServidor)(uid);
      if (!mounted) return;
      setState(() {
        _uid = uid;
        _ligado = ligado;
        _visivel = true;
      });
    } catch (_) {
      // Tabela ainda não existe (migração por aplicar) ou sem rede: o
      // interruptor fica escondido — nunca um erro no perfil do estafeta.
      if (mounted) setState(() => _visivel = false);
    }
  }

  Future<void> _mudar(bool v) async {
    final uid = _uid;
    if (uid == null) return;
    final antes = _ligado;
    setState(() {
      _ligado = v;
      _gravando = true;
    });
    try {
      await (widget.gravar ?? _gravarNoServidor)(uid, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ligado = antes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar. Tenta outra vez.'.tr)),
      );
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visivel) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.campaign_outlined, color: AppColors.primary),
      title: Text('Aceito chamadas de reforço quando estou desligado'.tr),
      subtitle: Text(
        'Se nenhum estafeta ligado aceitar um pedido, a Bora pode chamar-te mesmo desligado, das 8h às 23h, no máximo 3 vezes por dia. Recusar nunca te prejudica.'
            .tr,
        style: const TextStyle(fontSize: 12),
      ),
      value: _ligado,
      onChanged: _gravando ? null : _mudar,
    );
  }
}
