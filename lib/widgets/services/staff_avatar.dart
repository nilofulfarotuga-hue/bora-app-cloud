import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/staff_member_model.dart';

/// Avatar redondo de um profissional da vertical Serviços / Beleza.
///
/// Mostra a foto (`photo_url`) quando existe. Em fallback, desenha as iniciais
/// sobre um gradiente suave do design system (escolhido de forma determinística
/// pelo nome, para o mesmo profissional ter sempre a mesma cor). Reutilizado no
/// cliente (detalhe do prestador + fluxo de marcação) e no admin.
class StaffAvatar extends StatelessWidget {
  const StaffAvatar({super.key, required this.staff, this.radius = 22});

  final StaffMemberModel staff;
  final double radius;

  /// Paleta de gradientes (topo-esquerda → fundo-direita). Verde Bora primeiro,
  /// depois teal, rosa-poeira, dourado e índigo suave.
  static const List<List<Color>> _gradients = [
    [Color(0xFF16A34A), Color(0xFF4ADE80)],
    [Color(0xFF0E9488), Color(0xFF5EEAD4)],
    [Color(0xFFB4708A), Color(0xFFE0A9BE)],
    [Color(0xFFC79A3A), Color(0xFFE8C874)],
    [Color(0xFF6366F1), Color(0xFFA5B4FC)],
  ];

  static const Set<String> _stopWords = {
    'dra.', 'dra', 'dr.', 'dr', 'de', 'da', 'do', 'e'
  };

  String get _initials {
    final tokens = staff.name
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty && !_stopWords.contains(t.toLowerCase()))
        .toList();
    if (tokens.isEmpty) {
      return staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?';
    }
    if (tokens.length == 1) {
      final t = tokens.first;
      return (t.length >= 2 ? t.substring(0, 2) : t).toUpperCase();
    }
    return (tokens.first[0] + tokens.last[0]).toUpperCase();
  }

  List<Color> get _gradient {
    final key = staff.name.isEmpty
        ? 0
        : staff.name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _gradients[key % _gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final url = staff.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryLight,
        backgroundImage: NetworkImage(url),
      );
    }
    final colors = _gradient;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.7,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
