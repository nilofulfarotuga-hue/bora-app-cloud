# Relatório — Fix "78 crashes em 7 dias" (2026-07-08)

Investigação via MCP Supabase (`debug_crash_logs`): dos 78 registos analisados,
a maioria eram breadcrumbs de debug (não-crashes) + erro de rede. Só 2 eram
bugs reais de código. Os 4 pontos abaixo foram tratados de ponta a ponta.

## BUG REAL 1 — Null check no dispose do chat TVDE ✅ CORRIGIDO

- **Ficheiro:** `lib/screens/shared/tvde_chat_screen.dart`
- **Causa:** `dispose()` chamava `context.read<TvdeChatStore>()` durante a
  desmontagem do widget — o Provider já não está acessível nesse ponto do
  ciclo de vida → "Null check operator used on a null value".
- **Correção:** guardada a referência do store (`late final TvdeChatStore
  _chatStore`) no `initState()`, usada no `dispose()` em vez de `context.read()`.
- Afetava Xiaomi (A13) e Samsung (A16), 5 ocorrências, 2 utilizadores.

## BUG REAL 2 — Image picker "already_active" na candidatura de limpeza ✅ CORRIGIDO

- **Ficheiro:** `lib/screens/cleaner/cleaner_apply_screen.dart`
- **Causa:** toque duplo/rápido no botão de foto abria o `ImagePicker` 2x
  antes do primeiro fechar → `PlatformException(already_active, ...)`.
- **Correção:** guard de reentrância `_isPicking` em `_pick()` — ignora
  chamadas concorrentes, reset no `finally`. Cobre ambos os botões do ecrã
  (foto de perfil + documento), já que partilham o mesmo método `_pick`.
- 3 ocorrências, Xiaomi A13.

## PONTO 3 — Erro de rede filtrado do crash log ✅ CORRIGIDO

- **Ficheiro:** `lib/main.dart` (`_logCrashToSupabase`)
- `AuthRetryableFetchException` / `Failed host lookup` / `SocketException` são
  falhas de conectividade do dispositivo (sem internet / DNS instável), não
  bugs de código. Eram o maior grupo (21 das 78 ocorrências) e poluíam o
  log de crashes.
- **Correção:** nova função `_isConnectivityError()` filtra estes erros
  ANTES de chegarem à RPC `log_client_crash` — deixam de contar como crash.
  Não mexi no fluxo de auth em si (baixo risco, só logging).
- Não foi adicionada UI de aviso "sem ligação" — o fluxo de auth/retry já
  existente não foi tocado; ficou fora de escopo por segurança.

## PONTO 4 — Breadcrumbs removidos (debug já resolvido) ✅ CORRIGIDO

- Confirmado via `git log` que o bug de tela branca que motivou os
  breadcrumbs já foi corrigido (commit `2c80205 fix(tela-branca): blindar
  SendPackage/CarryGroceries contra insets absurdos Android 16`, antes deste
  fix). Os breadcrumbs (`BREADCRUMB: ...`) já cumpriram o propósito.
- **Removidos** (função `logScreenBreadcrumb` e todas as chamadas):
  - `lib/main.dart` — função `logScreenBreadcrumb`
  - `lib/widgets/quote_price_footer.dart`
  - `lib/screens/send_package_form_screen.dart`
  - `lib/screens/carry_groceries_form_screen.dart`
- Mantida a blindagem real (clamp de `viewInsets`/`padding` absurdos) — só o
  logging de diagnóstico foi removido.

## PAINEL ADMIN

Não existe ecrã de crashes/debug no admin (`lib/screens/admin`) — confirmado
por grep. Não construído agora (fora de escopo deste prompt); fica assinalado
para paridade futura: distinguir crash real / breadcrumb / erro de rede.

## Validação

- `flutter analyze` nos 6 ficheiros tocados: **0 erros**, 7 avisos `info`
  pré-existentes de estilo (`prefer_const_constructors`), não relacionados
  com as mudanças.
- App compila (analyze não reportou erros de sintaxe/tipo).
- Correções de baixo risco (ciclo de vida + guard + filtro de log) — sem
  teste em device necessário.

## Pendências / fora de escopo

- Admin: ecrã de crashes/debug com filtro tipo (crash/breadcrumb/rede) —
  pós-lançamento.
- Não mexido no fluxo de retry/auth do Supabase (só filtrado do log).
