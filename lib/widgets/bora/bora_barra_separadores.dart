import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Um separador da barra de baixo do estafeta e do parceiro.
class BoraSeparador {
  const BoraSeparador({
    required this.rotulo,
    required this.icone,
    required this.iconeAtivo,
  });

  final String rotulo;
  final IconData icone;
  final IconData iconeAtivo;
}

/// Barra de baixo do estafeta e do parceiro (missão fechar-tudo, bloco F,
/// 10/11/2026), no padrão Uber/Glovo: 4 separadores, ícone com o texto
/// SEMPRE por baixo (nada só com ícone), o separador ativo a verde Bora
/// (`AppColors.primary`, #16A34A) e os outros a cinzento. O mesmo desenho
/// da barra do cliente ([BoraBottomNavV2]); a letra é a do tema (Inter).
///
/// Não conhece rotas: só diz qual foi tocado ([aoMudar]); quem a usa decide.
class BoraBarraSeparadores extends StatelessWidget {
  const BoraBarraSeparadores({
    super.key,
    required this.separadores,
    required this.atual,
    required this.aoMudar,
  });

  final List<BoraSeparador> separadores;
  final int atual;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: AppColors.shadowNav,
      ),
      child: SafeArea(
        top: false,
        // Letra grande do sistema: o texto cresce até 1,3× (o mesmo limite da
        // NavigationBar do Flutter) e nunca sai da barra de 64 px.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < separadores.length; i++)
                  Expanded(
                    child: _CelulaSeparador(
                      key: Key('separador_$i'),
                      separador: separadores[i],
                      ativo: i == atual,
                      aoTocar: () => aoMudar(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CelulaSeparador extends StatelessWidget {
  const _CelulaSeparador({
    super.key,
    required this.separador,
    required this.ativo,
    required this.aoTocar,
  });

  final BoraSeparador separador;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? AppColors.primary : AppColors.textSubtle;
    return Semantics(
      selected: ativo,
      child: InkWell(
        onTap: aoTocar,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              ativo ? separador.iconeAtivo : separador.icone,
              color: cor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              separador.rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cor,
                fontSize: 11,
                fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma entrada das listas simples dos separadores "Conta" (estafeta) e
/// "Loja"/"Ganhos" (parceiro): ícone + texto (+ uma linha a explicar).
/// É para aqui que vai o que antes vivia em botões só com ícone.
class BoraLigacao {
  const BoraLigacao({
    required this.chave,
    required this.icone,
    required this.titulo,
    this.subtitulo,
    required this.aoTocar,
  });

  /// Identifica a linha nos testes: `Key('ligacao_<chave>')`.
  final String chave;
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final VoidCallback aoTocar;
}

/// Lista simples de [BoraLigacao] num cartão, com uma linha a separar.
class BoraListaLigacoes extends StatelessWidget {
  const BoraListaLigacoes({super.key, required this.ligacoes});

  final List<BoraLigacao> ligacoes;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ligacoes.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              key: Key('ligacao_${ligacoes[i].chave}'),
              leading: Icon(ligacoes[i].icone, color: AppColors.primary),
              title: Text(ligacoes[i].titulo),
              subtitle: ligacoes[i].subtitulo == null
                  ? null
                  : Text(ligacoes[i].subtitulo!),
              trailing: const Icon(Icons.chevron_right),
              onTap: ligacoes[i].aoTocar,
            ),
          ],
        ],
      ),
    );
  }
}
