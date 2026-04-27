/// Portuguese relative time formatter for order history / reorder cards.
String formatRelativePt(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.inSeconds < 60) return 'agora mesmo';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? 'há 1 min' : 'há $m min';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? 'há 1 hora' : 'há $h horas';
  }
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';
  if (diff.inDays < 30) {
    final w = (diff.inDays / 7).floor();
    return w == 1 ? 'há 1 semana' : 'há $w semanas';
  }
  if (diff.inDays < 365) {
    final mo = (diff.inDays / 30).floor();
    return mo == 1 ? 'há 1 mês' : 'há $mo meses';
  }
  final y = (diff.inDays / 365).floor();
  return y == 1 ? 'há 1 ano' : 'há $y anos';
}
