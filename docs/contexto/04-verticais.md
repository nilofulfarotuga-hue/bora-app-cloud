# 04 — VERTICAIS EM DETALHE

## Delivery (restaurantes + mercados)

- Fluxo: draft (`payment_drafts`) → pagamento → webhook cria ordem → dispatch (Edge Function, Haversine, cron) → estafeta → entrega. Chat bidirecional com push. CollectBadge unificado (delivery/TVDE/limpeza).
- Catálogo: ~42.000+ produtos de supermercado importados (Continente, Auchan, Lidl, Mercadona, Pingo Doce, Intermarché) — 1.754 produtos de 5 lojas não-parceiras na última leva. Fonte: crawlers Glovo/Uber (só categorias estáveis — ver cap. 03).
- Parceiros fast-food com paridade Glovo: McDonald's, KFC, Burger King, Pizza Hut.
- Multi-secção: `extra_categories` permite a mesma loja em Restaurantes E Mercados (caso vivo: Sabores de Casa Açaí). Abre sempre com o layout da categoria principal.

## TVDE (ride-hailing)

- Dispatch: `bora_dispatch_maintenance()` (bug COALESCE que causou 1.526 falhas já corrigido), sweep cron 15s, TTL de oferta, rotação de motoristas.
- Notificação de oferta: foreground service com notificação persistente rica (FLAG_INSISTENT, BigText, botões Aceitar/Recusar). CallKit/ConnectyCube REMOVIDOS permanentemente — nunca voltar. Overlay `flutter_overlay_window` abandonado (bug inter-isolate); se precisar, próxima tentativa é `system_alert_window`.
- Onboarding de permissões: notificações obrigatórias; overlay/bateria opcionais pós-online.
- Pagamento: `tvde_request_ride` é UMA função de 9 args (as 2 overloads foram fundidas — isso corrigiu um PGRST 404 que bloqueava TODAS as corridas). EF `tvde-payment` v4 (`confirm_ride_payment`, `charge_stop`, `confirm_stop_payment` com auto-refund). EF `notify-tvde-driver` v5. Corridas cartão/MB Way nascem `aguarda_pagamento`.
- €8 ida-e-volta: end-to-end confirmado em teste real (cash), aviso ao motorista ("recebes €4; os €8 do cliente não são teus"), volta grátis reconhecida, vale com validade visível. `tvde_create_roundtrip_credit_cash(uuid)` pro cash. Falta: hook `activate_roundtrip` pra liberar a ida €8-ONLINE quando o €8 paga (a ida não tem PI próprio — `confirm_ride_payment` não consegue flipá-la).
- Settlement `tvde_finish_ride`: cash normal inalterado; online/coberto(plano)/pré-pago creditam o motorista via balance; €8-cash detectado pelo crédito sem PI (ida deve €4 à Bora, volta recebe €3,50); só paradas CASH contam como recolhidas em mão.
- Mapa: rotação heading-up contínua (motorista e cliente). Otimização estilo Waze ~90% feita (removido echo realtime da própria posição, in-flight guard nas Directions, RepaintBoundary) — confirmação final em device com `--profile`.
- Pendências TVDE: RPC `tvde_mark_noshow`; cron `tvde_expire_roundtrip_credits()`; 4 strings PT-BR "Aguardando..." fora do fluxo de pagamento; push da oferta mostra €0 na volta (cosmético); autocomplete cortado na parada adicional; notificação A2 silenciosa em foreground; painel admin do €8 (fila de acerto semanal, alerta ida-cash sem vale).
- Acesso: aberto a todos temporariamente (migration `tvde_open_category_to_all_clients_temp_2026_07_21`; 19 clientes com `tvde_access=true`). REVERT quando pedido: `ALTER users.tvde_access SET DEFAULT false` + `UPDATE users SET tvde_access=false WHERE id NOT IN (SELECT client_id FROM tvde_access_requests WHERE status='aprovado')` (restaura os 2 genuinamente aprovados). O interruptor real é `users.tvde_access` — a chave `platform_settings.tvde_enabled` era inerte e foi apagada. Falta controlo "abrir/fechar pra todos" no painel (Danilo mandou NÃO montar agora).
- Kill switch `tvde_card_payments_enabled` aguarda teste em device real.
- ATENÇÃO: parada em corrida cartão/MB Way cobra €2 REAIS (Stripe live) — testar paradas em CASH.

## Limpeza

Implementação Helpling completa: agendado, preços fixos T0–T4+, dispatch por disponibilidade do profissional, 85/15, materiais +€3, recorrência –10%, chat, KYC, dupla avaliação, admin completo. Multi-role estafeta⇄limpador fechado (por `user_id`). Bugs de candidato corrigidos (geocoding commit `6a5d74a`; MIME HTTP 400 commit `9185112` — ambos client-side, bucket/RLS estavam certos). Duas bookings presas (cleaner_id=null, zero availability) confirmadas via MCP. Aguarda E2E em device.

## Reservas

Pré-pagamento €3 (ver cap. 03). MB Way ativo. Pós-launch: Reservas Mesa Pro best-in-class (~15–25h).

## Favores (Errands)

v3 construída por completo: Normal €6 / Expresso €10, gate de consentimento over-budget, OCR de talão, autocomplete de negócios (`guarda_businesses`), auto-catálogo "Lojas de Favores". Cancelamento E5 bloqueia pós-finalize.

## Serviços (marcações)

- Parceiros em `service_providers`. Perfil rico: avatar grande com fallback gradiente+iniciais, secção Sobre (`about_text`), Galeria (`gallery_urls`, viewer fullscreen swipe/zoom em `gallery_viewer_screen.dart`), ícones Instagram/Facebook — tudo com fallback silencioso se vazio.
- Painel admin correspondente: `admin_service_provider_detail_screen.dart` — editar Sobre, gerir galeria (upload via EF `upload-restaurant-asset` kind `gallery/photo`, reordenar, apagar), redes sociais.
- Parceiros vivos: Barbearia Nobre (1º), Barbearia Ouro e Prata, BeUnique Beauty & Academy (ver cap. 05).
- MB Way ativo em Serviços.
