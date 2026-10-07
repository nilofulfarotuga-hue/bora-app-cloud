# CONTINUAR — tvde-oferta-sobreposta (o que ficou de fora a 21/09, 01:45)

Relatório da missão: `.claude/.ai/reports/tvde-oferta-sobreposta-2026-09-20.md` · e2e_log 2092–2097 · digest `digest-2026-09-21-tvde-oferta-sobreposta` em `claude_ai_memoria`.

## 1. Subir a Edge `notify-tvde-driver` v17 (pela CLI, a partir do ficheiro em disco)
- O ficheiro está no repo (`supabase/functions/notify-tvde-driver/index.ts`, sha256 `e435b2b7fb6157712295c3458802d5ea470260ecb9287f254591863cae5e769f`); no ar está a v16.
- `.supabase-token.env` dá **401**. Precisa de `npx -y supabase@2 login` num terminal real (o Danilo carrega em Authorize) — depois:
  `npx -y supabase@2 functions deploy notify-tvde-driver --project-ref ojykpzwqrtusfeakzrna`
- Prova: MCP `get_edge_function` → `version` 17, `verify_jwt` true; corpo do push com `driverEarn`, `actions: 'accept,reject'`, `offerExpiresAt`.
- Nunca por retranscrição (MCP `deploy_edge_function` com o conteúdo colado).

## 2. Provar os botões da notificação no aparelho
- Só com os motoristas reais OFFLINE (confirmar por SELECT: `drivers` com `is_online` e `last_heartbeat_at > now()-90s` vazio, fora o demo).
- Emulador: `-gpu host -memory 3072 -cores 3`, RAM do PC ≥ 1,5 GB livres. App em segundo plano (HOME). Corrida sintética conforme `provas/tvde-oferta-sobreposta-2026-09-20/emulador/cenario.sql` (todos os reais em `tried_driver_ids`), `adb shell am broadcast -a com.google.android.intent.action.GTALK_HEARTBEAT` para o FCM entregar já.
- Recusar: abrir o shade (`cmd statusbar expand-notifications`), tocar em "❌ Recusar", procurar `[NOTIF ACTION]` e `recusar headless` no logcat e o evento `rejected_by` no servidor; **cancelar a corrida por SQL no mesmo segundo** (`status='cancelada_cliente'`).
- Aceitar: nova sintética, tocar em "✅ Aceitar" → a app abre → `tvdeResponderOfertaGlobal` → corrida activa/fila.
- Se o isolate de fundo não correr (sem rasto no logcat), trocar o Recusar para `showsUserInterface: true` (uma linha em `tvdeOfferNotificationActions`) — decisão do Danilo no relatório.

## 3. Captura do painel admin (opcional)
- Só a conta do Danilo é admin. Com a sessão dele (magic link `admin/generate_link`, logout `scope=local` no fim) fotografar "Corridas ao vivo" com uma corrida em `solicitada`: "Oferta a tocar a … · expira em …" e o botão "Forçar nova roda".

## Regra que fica (gravada na memória)
Com um motorista real online, uma corrida sintética em `solicitada` cancela-se por SQL no próprio segundo em que expira ou é recusada, e nunca fica viva se o emulador puder cair — a 21/09 às 00:50 uma foi parar ao Danilo.
