// Injected at build time via --dart-define=GOOGLE_MAPS_API_KEY=...
// or --dart-define-from-file=.dart_defines
// Never hardcode the key here.
const String googleApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
