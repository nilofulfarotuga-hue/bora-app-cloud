# 07 — ESTADO ATUAL E PENDÊNCIAS (snapshot 2026-07-22)

> Este capítulo envelhece rápido. Confirmar sempre o estado vivo por MCP (Supabase `orders`/`e2e_log`, Córtex) antes de assumir.

## Onde o projeto está

- **Todos os bloqueadores de launch fechados.** App `pt.boraapp.bora` no track fechado alpha com 12 testadores (PrimeTestLab). CI publica direto no alpha a cada push (primeiro build correto = 383; builds recentes na casa dos ~487).
- **Candidatura de acesso à produção do Play submetida em 22/07/2026 00:27** — Google a rever, resposta em até 7 dias (às vezes mais). Requisito cumprido: 12 testadores × 14 dias de engajamento real.
- Conta demo pro Play Console: `demo@bora.app` / `BoraDemo2026!`.
- Web app no ar: bora-app-web.pages.dev (auto-deploy ativo).
- Fechados recentemente: dispatch engine, hardening de segurança, chat bidirecional, MB Way Reservas/Serviços, paridade fast-food, 1.754 produtos não-parceiros, TVDE pagamento+€8+paradas, motor de conhecimento C1/C2/C4, multi-secção de lojas, perfil rico de Serviços + painel.

## Pendências do Danilo (humanas)

- Testar build novo no device (categorias de lojas, mapa TVDE em `--profile`, perfil Serviços visualmente).
- Rodar os prompts entregues: publicar site BeUnique; verificação Google Search Console (Ouro e Prata); E2E swap VPS.
- Mandar mensagens de onboarding (Bruna/BeUnique após publicar; dono do Sabores).
- Sync Obsidian.

## Pendências técnicas abertas (por área)

- **TVDE**: hook `activate_roundtrip` (€8-online); flip definitivo já feito?—confirmar `aguarda_pagamento` ativo pós-APK; RPC `tvde_mark_noshow`; cron `tvde_expire_roundtrip_credits`; painel admin do €8 (acerto semanal, alerta ida-cash); 4 strings PT-BR; push da volta mostra €0 (cosmético); autocomplete parada; notificação A2 foreground.
- **Painel admin**: controlo `extra_categories` de qualquer loja (hoje só SQL); controlo abrir/fechar TVDE pra todos (Danilo mandou esperar); C3 do motor de conhecimento.
- **Bugs reais reportados fora de escopo (não corrigidos)**: `register_partner_screen.dart` — `_formKey` nunca lido (validação possivelmente quebrada); `refund_choice_dialog.dart` — campo morto + imports órfãos; `test/order_eta_service_distance_test.dart` falha (esperava 4 distâncias distintas, obteve 2 — possível bug real no cálculo de distância, que mexe no preço da entrega; investigar em ordem separada).
- **Limpeza**: 2 bookings presas (cleaner_id=null); E2E device pendente.
- **E2E web**: aguarda swap na VPS + `flutter drive` (run_id WEB-E2E-2026-07-21-B).
- **Infra**: chave SSH do PC quebrada (workaround HTTPS ativo — vale arrumar de vez); pc_judge falha dentro do C4; BoraGitPushBridge quebrada e inofensiva — decisão: NÃO mexer.
- **No PC, não commitado (outra tarefa)**: deep link password-recovery (AndroidManifest/Info.plist) + 5 migrations PROPOSTA_*.

## Em design / aguardando plano

- **Robot B v4** (3 níveis de autonomia).
- **Favores v3** está construído; o que aguardava PLANO era a evolução (conferir no Córtex antes de mexer).

## Backlog pós-launch

Reservas Mesa Pro; Takeaway Pro; Tap to Pay/SoftPOS; estafeta sinaliza produto em falta; Lidl/Mercadona via AJUDANTE; white-label; Bora SP; Bora Business.
