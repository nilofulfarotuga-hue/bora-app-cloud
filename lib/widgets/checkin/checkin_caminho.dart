// lib/widgets/checkin/checkin_caminho.dart
//
// O CAMINHO dos 30 dias do check-in (Bloco G, 10/11/2026 — "faça uma coisa bem
// bonita"). Como o caminho do Duolingo: os dias em serpentina ligados por uma linha
// que fica verde à medida que se avança.
//  - dia feito: círculo verde com chama;
//  - dia perdoado (R5): círculo azul-gelo com floco;
//  - hoje: círculo a brilhar (aro verde e brilho à volta);
//  - dia de prémio: a FOTO REAL do prémio dentro do círculo, um selo com o
//    presente e o valor em euros por baixo (o prémio da loja usa a foto da loja);
//  - os outros dias: o número e, por baixo, os tokens do dia.
// Cores do Bora (verde #16A34A; o selo é âmbar, nunca o laranja da marca — a home
// já tem o seu elemento laranja). Não recebe dados do servidor: recebe a lista de
// dias montada por [diasDoCaminho].
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../utils/checkin_regras.dart';
import 'premio_foto.dart';

/// Um dia do caminho.
class CaminhoDia {
  const CaminhoDia({required this.dia, required this.estado, this.marco, this.tokens = 0});

  final int dia;
  final EstadoDiaCaminho estado;

  /// O marco desse dia (prémio, ou os tokens do Dia 7), se houver.
  final CheckinMarco? marco;

  /// Tokens desse dia (5,5,10,10,15,15,40 em ciclo).
  final int tokens;
}

/// Os dias do ciclo (1..30) a partir do estado do servidor.
/// [feitoAte] = último dia feito; [hoje] = o dia de hoje na escada.
List<CaminhoDia> diasDoCaminho(CheckinPremiosEstado p, {required int feitoAte, required int hoje}) {
  final ciclo = p.cicloDias <= 0 ? 30 : p.cicloDias;
  final marcos = {for (final m in p.marcos) m.dia: m};
  final perdoados = p.perdao?.dias ?? const <int>[];
  return [
    for (var d = 1; d <= ciclo; d++)
      CaminhoDia(
        dia: d,
        estado: estadoDoDia(dia: d, feitoAte: feitoAte, hoje: hoje, perdoados: perdoados),
        marco: marcos[d],
        tokens: p.tokensDoDia(d),
      ),
  ];
}

const Color _verdeClaro = Color(0xFFDCFCE7);
const Color _gelo = Color(0xFFE0F2FE);
const Color _geloBorda = Color(0xFF7DD3FC);
const Color _geloIcone = Color(0xFF0284C7);
const Color _cinzaLinha = Color(0xFFE5E7EB);

class CheckinCaminho extends StatelessWidget {
  const CheckinCaminho({
    super.key,
    required this.dias,
    this.porLinha = 6,
    this.chaveDia = 'checkin_caminho_dia_',
    this.chaveMarco = 'checkin_caminho_marco_',
  });

  final List<CaminhoDia> dias;
  final int porLinha;

  /// Prefixo da chave de cada círculo (`<prefixo><dia>`) e do selo do prémio.
  final String chaveDia;
  final String chaveMarco;

  static const double _vao = 6;

  @override
  Widget build(BuildContext context) {
    if (dias.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final largura = c.maxWidth.isFinite ? c.maxWidth : 320.0;
      final celula = (largura - _vao * (porLinha - 1)) / porLinha;
      final circulo = (celula < 46 ? celula : 46.0) * 0.86;
      const etiqueta = 13.0;
      final linhaAltura = circulo + 4 + etiqueta + 10;
      final linhas = (dias.length + porLinha - 1) ~/ porLinha;

      Offset canto(int i) {
        final linha = i ~/ porLinha;
        final naLinha = i % porLinha;
        final coluna = linha.isOdd ? porLinha - 1 - naLinha : naLinha;
        return Offset(coluna * (celula + _vao), linha * linhaAltura);
      }

      final centros = [
        for (var i = 0; i < dias.length; i++) canto(i) + Offset(celula / 2, circulo / 2),
      ];
      final andados = [
        for (final d in dias) d.estado == EstadoDiaCaminho.feito || d.estado == EstadoDiaCaminho.perdoado,
      ];

      return SizedBox(
        width: largura,
        height: linhas * linhaAltura,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LinhaDoCaminho(centros: centros, andados: andados, curva: celula * 0.55),
              ),
            ),
            for (var i = 0; i < dias.length; i++)
              Positioned(
                left: canto(i).dx,
                top: canto(i).dy,
                width: celula,
                child: _No(
                  dia: dias[i],
                  circulo: circulo,
                  chaveDia: chaveDia,
                  chaveMarco: chaveMarco,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _No extends StatelessWidget {
  const _No({required this.dia, required this.circulo, required this.chaveDia, required this.chaveMarco});

  final CaminhoDia dia;
  final double circulo;
  final String chaveDia;
  final String chaveMarco;

  @override
  Widget build(BuildContext context) {
    final m = dia.marco;
    final premio = m != null && ehPremio(m);
    final estado = dia.estado;
    final feito = estado == EstadoDiaCaminho.feito;
    final perdoado = estado == EstadoDiaCaminho.perdoado;
    final hoje = estado == EstadoDiaCaminho.hoje;

    final Color fundo = feito
        ? AppColors.primary
        : perdoado
            ? _gelo
            : hoje
                ? _verdeClaro
                : Colors.white;
    final Color borda = hoje
        ? AppColors.primary
        : perdoado
            ? _geloBorda
            : (m != null && !feito)
                ? AppColors.primary.withValues(alpha: 0.4)
                : (feito ? AppColors.primary : _cinzaLinha);

    final Widget dentro;
    if (feito) {
      dentro = Icon(Icons.local_fire_department_rounded, size: circulo * 0.56, color: Colors.white);
    } else if (perdoado) {
      dentro = Icon(Icons.ac_unit_rounded, size: circulo * 0.5, color: _geloIcone);
    } else if (premio) {
      dentro = PremioFoto(url: m.fotoUrl ?? m.lojaFotoUrl, tipo: m.tipo, tamanho: circulo - 6);
    } else if (m != null && m.tipo == 'tokens') {
      dentro = Icon(Icons.star_rounded, size: circulo * 0.55, color: AppColors.warning);
    } else {
      dentro = Text(
        '${dia.dia}',
        style: TextStyle(
          fontSize: circulo * 0.36,
          fontWeight: hoje ? FontWeight.w800 : FontWeight.w600,
          color: hoje ? AppColors.primaryDark : AppColors.textSubtle,
        ),
      );
    }

    final etiqueta = premio
        ? (valorEmEuros(m.valorCents).isNotEmpty ? valorEmEuros(m.valorCents) : 'Prémio'.tr)
        : (dia.tokens > 0 ? '+${dia.tokens}' : '');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: circulo,
          height: circulo,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: Key('$chaveDia${dia.dia}'),
                width: circulo,
                height: circulo,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fundo,
                  shape: BoxShape.circle,
                  border: Border.all(color: borda, width: hoje ? 2.5 : 1.5),
                  boxShadow: hoje
                      ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 2)]
                      : null,
                ),
                child: dentro,
              ),
              if (m != null)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: feito ? Colors.white : AppColors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      m.tipo == 'tokens'
                          ? Icons.star_rounded
                          : (m.tipo == 'servico' ? Icons.cleaning_services_outlined : Icons.card_giftcard),
                      key: Key('$chaveMarco${dia.dia}'),
                      size: 9,
                      color: feito ? AppColors.primaryDark : Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              etiqueta,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: premio ? FontWeight.w800 : FontWeight.w600,
                color: premio ? AppColors.primaryDark : AppColors.textSubtle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A linha que liga os dias, em serpentina: verde até onde já se andou.
class _LinhaDoCaminho extends CustomPainter {
  _LinhaDoCaminho({required this.centros, required this.andados, required this.curva});

  final List<Offset> centros;
  final List<bool> andados;
  final double curva;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < centros.length - 1; i++) {
      final a = centros[i];
      final b = centros[i + 1];
      p.color = (andados[i] && andados[i + 1]) ? AppColors.primary.withValues(alpha: 0.55) : _cinzaLinha;
      if ((a.dy - b.dy).abs() < 0.5) {
        canvas.drawLine(a, b, p);
      } else {
        // muda de linha: curva para fora, do lado onde a linha acaba
        final lado = a.dx > size.width / 2 ? 1.0 : -1.0;
        final caminho = Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(a.dx + lado * curva, a.dy, b.dx + lado * curva, b.dy, b.dx, b.dy);
        canvas.drawPath(caminho, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinhaDoCaminho old) =>
      old.centros != centros || old.andados != andados || old.curva != curva;
}
