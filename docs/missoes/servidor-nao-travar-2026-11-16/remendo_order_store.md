# Remendo pronto — `lib/stores/order_store.dart` (canal geral dos pedidos)

Missão `servidor-nao-travar-2026-11-16`, bloco B1.2. Escrito na sessão da nuvem a 16/11/2026.
O ficheiro está trancado em `.claude/settings.json` (`permissions.deny`), por isso esta sessão
NÃO o editou. Quem tiver a janela da tranca aberta aplica as 5 trocas abaixo, com Edit, uma a uma.
Autorização: Danilo, 16/11/2026 16:50 e 17:20 (citada no PROMPT da missão), só "reler pedidos e
ligar o tempo real". Não mexe em preços, despacho, carteira nem pagamentos.

## Porquê (prova)

- `edge_logs`: GET `/rest/v1/orders` da Isabel (`4abf0e49…`) por 10 min: 16:20 780 · 16:40 857 ·
  16:50 4145 · 17:00 13904 · 17:10 3837. O "voltar à app" correu só ~23 vezes (washers/cleaners = 23).
- `realtime_logs` no mesmo período: `SocketJoinRateLimitReached: Too many joins on this socket`
  (30/9/128/55/50) e `ChannelRateLimitReached: Too many channels` (1/6/26/11/3).
- Código: em `_subscribeToOrders`, `onError`/`onDone` faziam `_ordersSubscription = null` SEM
  `cancel()` e `Future.delayed(5 s, _subscribeToOrders)`. O `.stream()` do supabase 2.x, em
  `timedOut`/`channelError`, só emite o erro: o canal continua vivo e, a cada religação, volta a ler
  todos os pedidos (`_getPostgrestData`). Cada erro deixava um canal fantasma e abria outro → mais
  canais → "Too many channels" → mais erros. Bola de neve geométrica. O PR #28 não fecha isto.

## As 5 trocas

Pré-requisito já no ramo: `lib/utils/religar_com_espera.dart` (classe `ReligarComEspera`) e os testes
em `test/servidor_nao_travar_test.dart`.

**1. Import** — depois de `import '../services/pricing_service.dart';` (linha ~23) acrescentar:

```dart
import '../utils/religar_com_espera.dart';
```

**2. Campo** — trocar

```dart
  // Conta para a qual o canal geral está ligado ('isClient|uid').
  String? _ordersSubKey;
```

por

```dart
  // Conta para a qual o canal geral está ligado ('isClient|uid').
  String? _ordersSubKey;
  // [16/11/2026 servidor-nao-travar] Uma religação do canal geral de cada
  // vez, com espera crescente (5→60 s). Ver ReligarComEspera.
  final ReligarComEspera _religarGeral = ReligarComEspera();
```

**3. Ligar o canal** — em `_subscribeToOrders`, trocar

```dart
    _ordersSubscription = (isClient
            ? supabase
                .from('orders')
                .stream(primaryKey: ['id']).eq('user_id', uid!)
            : supabase.from('orders').stream(primaryKey: ['id']))
        .order('created_at', ascending: false)
        .listen(
      (rows) {
        debugPrint(
            '[OrderStore] orders received=${rows.length} (general stream)');
```

por

```dart
    _religarGeral.cancelar();
    late final StreamSubscription<List<Map<String, dynamic>>> sub;
    sub = (isClient
            ? supabase
                .from('orders')
                .stream(primaryKey: ['id']).eq('user_id', uid!)
            : supabase.from('orders').stream(primaryKey: ['id']))
        .order('created_at', ascending: false)
        .listen(
      (rows) {
        debugPrint(
            '[OrderStore] orders received=${rows.length} (general stream)');
        _religarGeral.correuBem();
```

e, no fim do mesmo `listen`, trocar

```dart
      onError: (Object e) {
        debugPrint(
            '[OrderStore] general stream error: $e — reconnecting in 5s');
        _ordersSubscription = null;
        Future.delayed(const Duration(seconds: 5), _subscribeToOrders);
      },
      onDone: () {
        debugPrint('[OrderStore] general stream closed — reconnecting in 5s');
        _ordersSubscription = null;
        Future.delayed(const Duration(seconds: 5), _subscribeToOrders);
      },
    );
```

por

```dart
      onError: (Object e) {
        debugPrint('[OrderStore] general stream error: $e');
        _canalGeralFalhou(sub);
      },
      onDone: () {
        debugPrint('[OrderStore] general stream closed');
        _canalGeralFalhou(sub);
      },
    );
    _ordersSubscription = sub;
```

**4. Função nova** — logo antes de `/// Driver-specific filtered streams. Called the moment a real driverId is`:

```dart
  /// [16/11/2026 servidor-nao-travar] O canal geral falhou (erro ou fecho).
  /// Antes punha-se `_ordersSubscription = null` SEM cancelar: o canal velho
  /// ficava vivo a religar-se sozinho (e a reler todos os pedidos a cada
  /// religação) e abria-se outro por cima 5 s depois — a cada erro mais um
  /// canal fantasma, até "Too many channels" no servidor e 27 leituras/s.
  /// Agora fecha-se o canal que falhou e marca-se UMA religação, com espera
  /// crescente; se entretanto passou para os canais do estafeta, não religa.
  void _canalGeralFalhou(StreamSubscription<List<Map<String, dynamic>>> sub) {
    unawaited(sub.cancel());
    if (!identical(_ordersSubscription, sub)) return; // canal já substituído
    _ordersSubscription = null;
    final marcada = _religarGeral.agendar(() {
      if (_ordersSubscription != null ||
          _driverOffersSubscription != null ||
          _driverActiveSubscription != null) {
        return;
      }
      _subscribeToOrders();
    });
    if (marcada) {
      debugPrint('[OrderStore] general stream: religa em '
          '${_religarGeral.proximaEspera.inSeconds}s '
          '(falhas seguidas: ${_religarGeral.falhasSeguidas})');
    }
  }

```

**5. Desmarcar a religação pendente** — em `_subscribeToDriverStreams`, antes de
`debugPrint('[OrderStore] driverId=$driverId');` acrescentar `_religarGeral.cancelar();`; e em
`dispose()`, como primeira linha, `_religarGeral.cancelar();`.

## Depois de aplicar

`flutter analyze` (0 erros) · `flutter test test/servidor_nao_travar_test.dart` · `python
.claude/juiz/anti_trapaca.py` · commit no ramo `ai/2026-11-16-servidor-nao-travar` (PR #28).

Nota (não mexido, fica a reportar): os canais do estafeta (`_scheduleDriverReconnect`) já cancelam o
velho antes de abrir o novo e juntam erros num só agendamento, mas religam sempre aos 5 s sem espera
crescente. Com o servidor em baixo, cada estafeta faz 2 leituras a cada 5 s. É despacho: só proposta.
