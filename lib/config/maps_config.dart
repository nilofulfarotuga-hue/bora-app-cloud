// Injected at build time via --dart-define=GOOGLE_MAPS_API_KEY=...
// or --dart-define-from-file=.dart_defines
// Never hardcode the key here.
const String googleApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

// Viés geográfico do autocomplete de lugares para a Guarda (centro do
// município — a área servida pelo Bora). Como o Bora SÓ opera na Guarda,
// enviamos location + radius para PUXAR os resultados locais para o topo
// (ex.: "Continente" → Continente da Guarda em primeiro).
//
// NÃO usamos strictbounds=true: no telemóvel real (build de produção) o
// strictbounds ELIMINAVA comércios locais legítimos — "Lavie" (shopping da
// Guarda) devolvia ZERO resultados porque a API só devolve estabelecimentos
// cujo viewport cai INTEIRO dentro do raio, e falha para lojas pequenas mal
// indexadas. Com viés suave (radius sem strictbounds) o local fica em cima
// mas nada é excluído à força. Para o caso raro em que o viés ainda devolve
// vazio, o serviço faz um retry SEM viés (cobertura nacional) — ver
// place_autocomplete_service_io.dart. Assim "Lavie" nunca fica vazio.
const double kGuardaBiasLat = 40.5373;
const double kGuardaBiasLng = -7.2657;
const int kGuardaBiasRadiusMeters = 25000;
const bool kGuardaStrictBounds = false;
