---
id: memoria-claude-ai-livro-areas-bora-app
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 1 de 4 — continua em livro-areas-bora-app-parte2, -parte3, -parte4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-bora-app`, origem `claude-ai`, atualizada em 2026-10-23T05:51:23.729253+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas bora app · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/bora-app.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: bora-app
description: Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones
sources: [backfill]
aliases: [Bora, bora_app, pt.boraapp.bora, bora-app-cloud]
---
- [stated] Multi-vertical Flutter + Supabase + Stripe Live + Firebase FCM platform covering delivery, TVDE ride-hailing, cleaning (Limpeza), reservations, errands (Favores), and markets
- [stated] Supabase project `ojykpzwqrtusfeakzrna`; repo `nilofulfarotuga-hue/bora-app-cloud`; branch `autonomous-night-2026-04-29`; local path `C:\Users\danil\Desktop\projetosflutter\bora_app\`
- [stated] Multi-role architecture: client, driver/estafeta, partner, admin; multi-role estafeta⇄limpeza linkage (drivers/cleaners linked by user_id)

Core engine & rules (foundation, Mar–Apr 2026)
- [stated] Core dispatch engine: Edge Function, Haversine distance, pg_cron, pg_net
- [stated] Wallet system with dual balance (free + tokens)
- [stated] Business rules: partner 10%+5%+5% hybrid; non-partner base+15%; token system (client 3/€, driver +40/+50); cash max €40; bag fees; delivery €2.50 up to 4km + €0.50/km
- [stated] Supermarket catalog ~42,000+ products across Continente, Auchan, Lidl, Mercadona, Pingo Doce, Intermarché
- [stated] Partner merchants: McDonald's, KFC, Burger King, Pizza Hut, Sabores de Casa Açaí, Barbearia Nobre (beauty/services)
- [stated] CEO-AI orchestrator at `.claude/skills/ceo-ai/` — always invoked first in every Claude Code prompt; MODO PROTECÇÃO TOTAL header mandatory
- [stated] Protected zones: `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`, Stripe webhook v17+, RLS on `orders`/`wallets`/`ledger`

Security hardening (Jun 2026)
- [stated] `wallet_credit_refund_full` anon access fixed (REVOKE from PUBLIC, not just anon/authenticated)
- [stated] `receipts` and `order-photos` buckets switched to private
- [stated] 9 SECURITY DEFINER functions revoked from anon (3 HIGH including `admin_delete_business`, `driver_convert_tokens`); RLS enabled on 36 backup tables
- [stated] `protect-admin-app-role` trigger active; admin identity via `app_metadata.role` JWT (not user metadata)

Cancellation system & Favores (Jun 2026)
- [stated] Cancellation motor live as Edge Function `client-cancel-order` v26 (RPC `request_order_cancel` is orphan — ignore)
- [stated] Five cancellation stages: E1 free grace (≤180s, no driver), E2 €1 (>180s, no driver), E3 €2.50 split (driver accepted), E4 100% (post-pickup), E5 blocked (post-finalize for errands); client chooses Stripe refund or wallet (80/20 split)
- [stated] Cancellation admin screens: history, reprocess-refund, tax editing via `admin_update_cancel_setting`
- [stated] Favores v3 fully built including over-budget consent gate, receipt OCR, business autocomplete, `guarda_businesses` table

Loja em múltiplas categorias do cliente (2026-07-21, Claude.ai via MCP + prompt Claude Code)
- [stated] DECISÃO Danilo: uma loja só (mesmo dono, MESMO painel do parceiro, MESMOS produtos) pode aparecer em VÁRIAS categorias do cliente. NÃO é duplicar negócio nem produtos — é só o cliente ver a MESMA loja em 2 secções. Tudo que o parceiro põe aparece nas duas (é o mesmo restaurant_id → catálogo único).
- [stated] Caso vivo: Sabores de Casa Açaí (id 12aa2cbb-01bd-443b-a17e-633c169d4864) fica em Restaurantes (category='restaurant', parceiro) E também em Mercados.
- [stated] Modelo confirmado: restaurantes e mercados são a MESMA tabela restaurants, separados pela coluna category (restaurant/supermarket/store/pharmacy). App cliente lê a tabela DIRETO (RLS restaurants_public_read: approval_status='approved' OR is_admin); NÃO há RPC de listagem nem view → o filtro por secção é no Flutter.
- [stated] FEITO por MCP (migration restaurants_extra_categories_multi_section_2026_07_21): coluna restaurants.extra_categories text[] NOT NULL DEFAULT '{}'. Regra: loja aparece na secção S se category=S OU S = ANY(extra_categories). Sabores set extra_categories='{supermarket}'. Reversível (limpar array / dropar coluna).
- [stated] FEITO Flutter (Claude Code SONNET, 2026-07-21): helper belongsTo(secção) = true por category OU extra_categories, usado em Restaurantes/Supermercados/Lojas/Farmácias. Ficheiros: lib/utils/business_mapper.dart (buildRetailStore passou a aceitar sectionCategory — já não devolve null a restaurante listado em Mercados) + lib/utils/business_opener.dart (novo, router que abre sempre com o layout da categoria PRINCIPAL). Sabores sai nas 2 secções, mesmo restaurant_id, abre como cardápio de restaurante (não grelha de mercado); zero duplicação; painel do parceiro intocado. flutter analyze lib: 0 errors; Juiz CLEAN; versionCode não tocado (CI faz).
- [stated] INFRA: git push por SSH da máquina do Danilo vive a falhar (Permission denied publickey); Claude Code caiu p/ HTTPS + credential.helper=manager + pull --rebase --autostash. CONFIRMAR sempre que o commit entrou no GitHub (senão CI não builda). Vale arrumar a chave SSH de vez.
- [stated] BUG pré-existente (NÃO desta mudança): flutter test → 1 falha em test/order_eta_service_distance_test.dart (esperava 4 distâncias distintas, obteve 2; usa OrderEtaService.distanceKmBetween com LatLng constantes). Possível bug real no cálculo de distância — distância mexe no preço da entrega. A investigar em ordem separada.
- [stated] RECOMENDADO (regra painel admin, ainda NÃO feito): estender admin_update_partner_data (ou novo controlo) pra o Danilo marcar extra_categories de qualquer loja pelo painel, em vez de SQL manual.

Perfil parceiro Serviços — Sobre/Galeria (2026-07-21, ver [[ouro-e-prata]] para o caso vivo)
- [stated] FEITO Flutter (Claude Code SONNET): provider_detail_screen.dart + service_provider_model.dart — avatar da equipa maior (radius 34→44, StaffAvatar ganhou fallback gradiente+iniciais quando a foto falha), secções "Sobre" e "Galeria" (novo gallery_viewer_screen.dart, fullscreen swipe/zoom) e ícones Instagram/Facebook, tudo com fallback silencioso se vazio. Válido pra qualquer parceiro de Serviços.
- [stated] FEITO painel admin: admin_service_provider_detail_screen.dart — card "Sobre" (editar about_text), card "Galeria" (upload/reordenar/apagar, reaproveita Edge Function upload-restaurant-asset com kind:'gallery/photo'), card "Redes sociais". Não mexeu em schema/RLS.
- [stated] flutter analyze no projeto inteiro: 223 issues pré-existentes, 0 erros, nenhum nos ficheiros tocados. NÃO rodou num device real nesta sessão — falta confirmar visualmente.
- [stated] BUGS REAIS encontrados fora do escopo (não corrigidos, reportados): register_partner_screen.dart com formulário quebrado (_formKey nunca é lido — possível falha de validação); refund_choice_dialog.dart com campo _tokenValueCentsX100 nunca lido + imports órfãos.
- [stated] INFRA site institucional: repo PÚBLICO nilofulfarotuga-hue/bora-site (Cloudflare Pages upload direto → bora-site.pages.dev). Assets reutilizáveis em assets/img/: bora_logo.png (logo completo 1376x768), apple-touch-icon.png (ícone quadrado do app), qr-playstore.png (QR real p/ Play Store), google-play-badge.png, og-image.png, screenshot-home.png, e cat_*.png (ícones das categorias). Clonável por HTTPS sem auth (dá p/ puxar o logo do Bora de lá quando preciso).

Notificações do parceiro de Serviços + QR codes (2026-07-28, Claude.ai via MCP)
- [stated] BUG relatado: parceiro de Serviços (barbearia/beleza) não recebia notificação de marcação; delivery recebe persistente e em segundo plano — Danilo quer paridade.
- [stated] CAUSA RAIZ (achada por MCP): (1) notify-service-provider v2 mandava bloco `notification` + data → Android desenhava a notif nativa efémera e o _firebaseMessagingBackgroundHandler do Flutter nunca corria (delivery/notify-partner v21 manda DATA-ONLY, por isso funciona); usava ainda channel_id morto bora_orders_urgent_v2 (app usa v3). (2) NÃO existia trigger nenhum em appointments — ninguém chamava a Edge Function.
- [stated] FEITO por MCP: notify-service-provider v3 deployed (data-only, padrão notify-partner) + trigger trg_appointments_notify_provider em appointments (INSERT ≠ pending_payment e UPDATE de status: pending_payment→confirmed = appointment_new; →cancelled = appointment_cancelled), chama a Edge via net.http_post com service_role key do vault + grava notif in-app.
- [stated] Facto do banco: só 2 de 5 service_providers têm linha em partner_push_tokens (Ouro e Prata 1 activo; Barbearia Nobre e BeUnique zero) → suspeita de que o registo de token FCM só corre no fluxo de restaurante, não no de Serviços. A investigar no Flutter.
- [stated] QR CODES gerados (segno, PNG verde #16A34A, ficheiros entregues): qr-1-baixar-app-playstore.png → play.google.com/store/apps/details?id=pt.boraapp.bora; qr-1b-teste-fechado-playstore.png → play.google.com/apps/testing/pt.boraapp.bora (usar este enquanto não sai do teste fechado); qr-2-cadastro-cliente-web.png → bora-app-web.pages.dev/#/registo-cliente (URL CANÓNICA — não mudar, os cartazes vão impressos com ela; a rota tem de cair direto no registo de CLIENTE, sem o ecrã de escolher perfil).
- [stated] PROMPT entregue (OPUS/Claude Code, PROMPT_servicos_notif_pagamento_horario_qr.md): 4 blocos — A notificações do parceiro Serviços (registo de token + appointment_cancelled + data-only lê title/body de data + deep-link + teste real por adb); B cobrança valor cheio por booking_payment_mode; C slots respeitando pausa de almoço + ecrã do parceiro editar horário + painel admin; D rota web #/registo-cliente + deploy Cloudflare.
- [stated] PENDENTE DE DECISÃO do Danilo: no modo 'full', reembolsar €15 inteiros num cancelamento dentro da janela de 24h é risco maior que devolver €3 — confirmar política com o Gilberto.

Reagendamento em vez de cancelamento + correções (2026-07-28, 2ª rodada)
- [stated] REGRA NOVA do Gilberto (Ouro e Prata): cliente NÃO cancela. Se não puder vir, REAGENDA (escolhe outra data/hora) e o dinheiro já pago fica preso à mesma marcação. Se não reagendar e não aparecer, perde o dinheiro.
- [stated] DESCOBERTA que corrige a 1ª rodada: (a) já existia public._appt_notify_partner() chamada pelas RPCs (client_confirm_appointment_payment etc.) → o trigger criado antes DUPLICAVA push; foi DROPADO. A causa raiz era só a Edge (bloco notification + canal morto). (b) os slots NÃO vêm de service_providers.business_hours — vêm da RPC get_available_slots que lê staff_availability / staff_availability_exceptions; business_hours é só vitrine da ficha.
- [stated] FEITO por MCP (2ª rodada): staff_availability + staff_availability_exceptions ganharam break_start/break_end; get_available_slots reescrita para excluir slots que colidem com a pausa (NULL = sem pausa); horário do Gilberto (staff a074d077-c0a7-4144-b656-fce14bd879e8) gravado dow 1–6 09:00–20:00 pausa 13:00–14:00, domingo is_working=false. Provado: Degradê 45min salta de 12:00 para 14:15.
- [stated] FEITO por MCP: coluna service_providers.booking_cancellation_policy ('refund' default | 'reschedule_only'), Ouro e Prata em reschedule_only; appointments ganhou reschedule_count/original_scheduled_at/last_rescheduled_at; tabela appointment_reschedules (auditoria, com RLS cliente+parceiro); RPC client_reschedule_appointment (mesma linha = mesmo deposit_pi = zero cobrança nova, valida slot via get_available_slots, notifica com kind appointment_rescheduled); client_cancel_appointment passou a rejeitar com cancellation_not_allowed_reschedule_only quando a política é reschedule_only e o depósito está pago; settings appointment_reschedule_min_hours=3, _max_count=2, _max_days=60.
- [stated] PROMPT 2 entregue (PROMPT_2_reagendamento_e_correcoes.md): adendo ao prompt 1 com as duas correções + Bloco E (UI de reagendamento no cliente, kind appointment_rescheduled no parceiro, painel admin, ecrã de horário tem de escrever em staff_availability e não em business_hours).
- [stated] PONTA SOLTA: parceiro cancelar (partner_cancel_appointment) continua permitido em qualquer política — confirmar que reembolsa correctamente o valor cheio no modo 'full'.

Bugs fora do scope resolvidos por MCP (2026-07-28, 3ª rodada)
- [stated] Do relatório do Claude Code ficaram 4 bugs "fora do scope": (1) notify-client hardcoded type='order_status', (2) partner_cancel_appointment não reembolsa, (3) _mapErrorPtPt genérico [já corrigido pelo Code], (4) dois bugs Flutter conhecidos (register_partner_screen.dart:33, refund_choice_dialog.dart:65).
- [stated] FEITO por MCP: notify-client v18 deployed (pass-through de data.type — se vier no body usa esse, senão fallback 'order_status'; delivery inalterado; agora appointment_status/reservation_status chegam ao app tipados correctamente).
- [stated] FEITO por MCP: partner_cancel_appointment reescrita — quando parceiro cancela e deposit_status='paid' + deposit_pi existe, chama Edge refund (Stripe) automaticamente via net.http_post com service_role key do vault; grava deposit_status='refunded'; funciona para modo 'deposit' (€3) e 'full' (preço cheio); notificação ao cliente já diz "Reembolso de EUR X processado". Se o refund automático falhar (vault/valor<50c/exceção) cai para deposit_status='paid' + notify_admin_event 'appointment_partner_cancel_refund_manual' pra Danilo processar manualmente. Fecha a ponta solta do prompt 2 confirmando com o Danilo que refund automático é o certo.
- [stated] PROMPT 3 entregue (PROMPT_3_bugs_flutter_e_push.md, GLM/OpenCode): só os 2 bugs Flutter isolados + push. Curto porque é cirúrgico.
- [stated] Bugs A e B fechados no commit 7dd71f6 (Bug A: _formKey ligada a Form + validate() antes do submit — 0 mudança de comportamento porque nenhum campo tem validator:; Bug B: _tokenValueCentsX100 removido junto com RPC que só o alimentava). flutter analyze limpo. Push confirmado no GitHub.

