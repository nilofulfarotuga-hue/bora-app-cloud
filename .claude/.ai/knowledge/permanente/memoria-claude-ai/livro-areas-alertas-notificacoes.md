---
id: memoria-claude-ai-livro-areas-alertas-notificacoes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Alertas do Bora para o Danilo (Telegram + push admin persistente) — o que já dispara, por que caminho, e o que falta

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-alertas-notificacoes`, origem `claude-ai`, atualizada em 2026-10-23T05:40:52.801221+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas alertas notificacoes · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/alertas-notificacoes.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: alertas-notificacoes
description: Alertas do Bora para o Danilo (Telegram + push admin persistente) — o que já dispara, por que caminho, e o que falta
sources: [chat]
aliases: [alertas, avisos Telegram, notificação admin, novo cadastro]
---

Alerta de NOVO CADASTRO (2026-08-02, Claude.ai via MCP)
- [stated] Pedido do Danilo: sempre que QUALQUER pessoa se registar (cliente, estafeta, parceiro, limpador) chegar aviso no Telegram dele — fase de arranque, quer saber na hora.
- [stated] FEITO por MCP (migration `alerta_novo_cadastro_telegram`): função `public.notify_new_signup()` + trigger `trg_notify_new_signup` AFTER INSERT em `public.users`.
- [stated] Caminho reaproveitado (já existia e funciona): `notify_admin_urgent_push()` grava em `admin_notifications` (sininho) e chama a Edge `notify-admin-urgent` v15 → push persistente FCM + Telegram (credenciais no vault via RPC `get_telegram_config`).
- [stated] Mensagem: "🎉 Novo CLIENTE/ESTAFETA-MOTORISTA/PARCEIRO/LIMPADOR(A) registou-se: nome ou email · telefone · email"; deep-link `/admin/users`.
- [stated] Filtro anti-ruído: ignora emails `%@boraapp.test`, `%@test.com`, `e2e_%`, `test_%` — lotes de teste não disparam.
- [stated] Cobre todas as vias de registo porque `public.users` é preenchida pelo trigger `trg_handle_new_auth_user` em `auth.users`.
- [stated] PROVADO 2026-08-02 09:06 com disparo real: resposta `push_success:2, telegram_sent:true` (net._http_response id 3507). Linha de teste apagada de admin_notifications.
- [stated] Ressalva conhecida: enquanto o Danilo não instalar o build novo do app, o push no telemóvel pode aparecer sem corpo (APK antigo vs Edge data-only). O Telegram chega certo de qualquer forma.

Dados de cadastros (2026-08-01/02)
- [stated] Único registo orgânico da madrugada: 1 cliente às 00:12 (jrm1091@hotmail.com) — sem pedido, sem reserva, sem agendamento. O bloco das 18:29 de 01/08 era lote de teste + contas já conhecidas.

⛔ AVISOS DO LOOP PARARAM — regressão reportada 2026-08-11
- [stated] Danilo: antes chegavam mensagens no Telegram quando a tarefa passava a verde e quando travava; desde as ordens desta madrugada NÃO chega nada. Investigar como parte da auditoria do Hermes (candidatos: mudança da cadeia de modelos do Hermes para o plano Go, revogação dos tokens antigos no fecho do cortex-mcp, ou o canal do carteiro)

🔔 CORREÇÃO IMPORTANTE — SIM, HÁ COMO ACORDAR UMA SESSÃO CLAUDE (2026-08-11)
- Eu disse ao Danilo, duas vezes, que "nada consegue acionar a Claude.ai automaticamente". Ele insistiu que tinha de haver forma e ELE TINHA RAZÃO. A resposta já estava no próprio Córtex dele desde 2026-08-01, na proposta `prop-b8d89e98`, e nunca foi construída: as **ROTINAS do Claude Code** (claude.ai/code/routines, research preview, incluídas nos planos pagos) aceitam três gatilhos — horário, **CHAMADA HTTP num endpoint próprio da rotina com bearer token**, e webhook
- Ou seja: o loop/Hermes pode DISPARAR uma sessão Claude por HTTP quando uma ordem fecha ou trava. O que continua a não existir é acordar ESTE fio de conversa no telemóvel — mas isso deixa de ser o ponto: a rotina age e avisa
- Lição para mim: antes de dizer "não há forma", procurar no Córtex e na documentação. Duas vezes dei uma impossibilidade por certa sem verificar

🛎️ ALERTA DE PEDIDO NOVO (2026-08-25, Claude.ai via MCP)
- [stated] REGRA do Danilo: QUALQUER pedido de delivery, de QUALQUER categoria, tem de lhe chegar ao Telegram. Razão dele: está no arranque e pode não ter o telemóvel ligado nem haver ninguém a ver o painel — sem aviso perde-se o pedido; no Telegram (Hermes) ele está sempre.
- [stated] Não existia — a `orders` só tinha alertas de cancelamento a meio da entrega e de reembolso alto. FEITO por MCP (migration `alerta_novo_pedido_telegram_2026_08_25`): `public.notify_new_order_admin()` + trigger `trg_notify_new_order_admin` AFTER INSERT em `public.orders`, a reutilizar o caminho já provado `notify_admin_urgent_push()` (sininho + push FCM + Telegram).
- [stated] Mensagem: "🛎️ PEDIDO NOVO · loja · valor EUR · forma de pagamento · para já OU ENCOMENDA para DD/MM HH:MM · #id"; deep-link `/admin/orders`. Envolvido em EXCEPTION para nunca quebrar a criação do pedido.
- [stated] POR PROVAR: só se confirma com o primeiro pedido real. Se entrar pedido e não chegar nada ao Telegram, investigar (o caminho é o mesmo do alerta de novo cadastro, provado a 2026-08-02).

🛎️ ALERTAS TVDE / LAVAGEM / RESERVAS (2026-09-03, Claude.ai via MCP)
- [stated] Pedido do Danilo: além dos pedidos de comida, quer no Telegram cada pedido de limpeza, de lavagem de carro e, o principal, cada corrida TVDE
- Verificado no banco: limpeza JÁ alertava (`trg_cleaning_notify_admin_new`); TVDE só alertava corridas de convidado; lavagem e reservas não alertavam
- FEITO por MCP (migration `alerta_telegram_tvde_lavagem_reserva_2026_09_03`): triggers AFTER INSERT `trg_notify_new_tvde_ride_admin` (tvde_rides), `trg_notify_new_carwash_admin` (carwash_bookings), `trg_notify_new_reservation_admin` (reservations), todos pelo caminho `notify_admin_urgent_push()` (sininho + push + Telegram), envolvidos em EXCEPTION. Mensagem de teste disparada (id 27a6f6f0). POR PROVAR com o primeiro pedido real de cada tipo

🚨 04/09 O ESTAFETA NÃO RECEBIA AVISO NENHUM DE PEDIDO NOVO — achado e corrigido por mim via MCP
- A Edge `notify-driver` falhava TODOS os envios com `400 INVALID_ARGUMENT` do Firebase: tinha `priority` dentro de `android.notification`, campo que **não existe na API FCM v1**. Entrava pedido e não tocava nada no telemóvel de quem o ia buscar. Corrigido para `notification_priority: 'PRIORITY_MAX'` (o `android.priority: 'high'` uma linha acima está certo, são campos diferentes). Deploy **versão 38**, provado com envio real: passou de `fcm_error` para `{"ok":true}`
- ⚠️ ARMADILHA: a correcção está SÓ em produção. O ficheiro do repo `supabase/functions/notify-driver/index.ts` continua com o bug — o próximo deploy repõe-o. Confirmar antes de qualquer deploy dessa função
- `notify-tvde-driver` foi lida e está limpa (só `android: { priority: 'high' }`, válido). As outras Edge de aviso ficaram por auditar
- TELEGRAM PROVADO VIVO nesse dia (o Danilo achava que estava tudo morto): `telegram_sent:true` às 14:20, 15:52 e 17:19, mais um teste meu às 20:58Z pelo `notify_admin_urgent_push()`. O que não chegava era a mensagem das 18h30 do publicador das redes, que vive na VPS e não na base
- Sinal de que a campanha das redes pega: 16 clientes novos em 7 dias (6 só a 04/09), 3 corridas TVDE na noite de 03/09, e o código BEMVINDO usado 3 vezes — os primeiros resgates desde que existe

💈 MARCAÇÕES DE SERVIÇOS NÃO AVISAVAM NADA (14/09, achado por mim via MCP)
- [stated] REGRA do Danilo: marcação de serviço (barbearia e afins) tem de lhe chegar mensagem, com o NOME e o contacto da pessoa — ele quer saber quem marcou para poder falar com o parceiro sabendo do que fala. Queixou-se de nunca receber nada das marcações da [[ouro-e-prata]].
- Causa: `appointments` era a ÚNICA tabela de dinheiro sem alerta — só tinha `trg_appointments_updated` e `_coming_soon_guard_appointments`. Pedidos, TVDE, limpeza, lavagem, reservas e cadastros novos já avisavam; marcações nunca avisaram desde sempre. Não era o telemóvel nem o Telegram.
- Escrita a migration `alerta_telegram_marcacao_nova_2026_09_14`: `notify_new_appointment_admin()` + `trg_notify_new_appointment_admin` AFTER INSERT, ignora `status='blocked'` (bloqueios de agenda do parceiro), mensagem "💈 MARCACAO NOVA · loja · serviço · cliente (telefone) · valor · dia/hora · pela app/ao balcão", deep-link `/admin/appointments`, pelo caminho provado `notify_admin_urgent_push()`.
- ⚠️ POR CONFIRMAR: o MCP do Supabase caiu no momento de aplicar/verificar — não se sabe se o trigger ficou instalado. PRIMEIRA COISA a fazer na próxima sessão: verificar `trg_notify_new_appointment_admin` em `pg_trigger` e reaplicar se faltar. Prometido ao Danilo que confirmo.

🪪 NOME DO CLIENTE NOS AVISOS (16/09)
- [stated] Queixa do Danilo: no Telegram não chegava o nome da pessoa, só que havia pedido (caso de uma reserva TVDE) — quer ver o nome do cliente nos avisos de pedidos e reservas

