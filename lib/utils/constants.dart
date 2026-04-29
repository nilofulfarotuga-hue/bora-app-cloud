import 'package:latlong2/latlong.dart';

/// Centro geográfico da Guarda (Sé Catedral) — fallback default
/// para todos os mapas e localizações antes de GPS/dados reais.
///
/// Substitui valores Lisboa (38.7223, -9.1393) hardcoded espalhados
/// pela app. Bora App opera apenas na Guarda; lançar mapa em Lisboa
/// induz utilizador em erro.
const double kGuardaLat = 40.5378;
const double kGuardaLng = -7.2683;

/// LatLng (latlong2) — uso directo em ficheiros que importam latlong2.
/// Para `google_maps_flutter.LatLng` construir manualmente com
/// `LatLng(kGuardaLat, kGuardaLng)` no contexto de import dessa lib.
const LatLng kGuardaCenter = LatLng(kGuardaLat, kGuardaLng);
