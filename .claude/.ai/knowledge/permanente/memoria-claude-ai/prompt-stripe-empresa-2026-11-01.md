---
id: memoria-claude-ai-prompt-stripe-empresa-2026-11-01
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Prompt — ligar o app à Stripe da empresa (01/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-stripe-empresa-2026-11-01`, origem `claude.ai`, atualizada em 2026-11-02T06:15:59.837089+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt stripe empresa 2026 11 01 · memoria claude.ai · claude_ai_memoria

REGISTO: prompt entregue a 01/11/2026 ~22:15 pela Claude.ai; LANÇADO a 02/11/2026 00:36 pela Claude.ai numa sessão nova do Claude Code no PC (ambiente Remote Control bora-app-cloud · Danilo, motor Fable 5.1, modo Automático) — sessão "Ligar app à Stripe empresa", https://claude.ai/code/session_01HPEpV8TqbMGfAxZbZkrQhU. Arrancou no F0 às 00:37 (provado na página da sessão). Autorização: «Autorizo» do Danilo às 22:03 de 01/11. Fluxo e2e_log: stripe-empresa-2026-11-01. Foi acrescentada uma NOTA DE ARRANQUE (app-fechar já enviou o código; só falta o build do iPhone dela).

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: FABLE (mexe em dinheiro e em produção)
PORTA: Claude Code no PC do Danilo, SESSÃO NOVA, pasta C:\Users\danil\Desktop\projetosflutter\bora_app (repo nilofulfarotuga-hue/bora-app-cloud, branch autonomous-night-2026-04-29), modo "Ignorar permissões".
Invoca primeiro o orquestrador CEO-AI (.claude/skills/ceo-ai/) e segue as skills protocolo-missao-bora e danilo-como-trabalhar.
Fluxo no e2e_log: stripe-empresa-2026-11-01 (uma linha por fase, com prova).

AUTORIZAÇÃO (literal, só para esta missão)
«Autorizo» — Danilo, 01/11/2026 às 22:03, em resposta à pergunta da Claude.ai: "Ainda falta ligar o app à conta nova. Mudar isso mexe em todos os pagamentos do app, por isso só faço com o teu autorizo."
Âmbito: ligar o app à Stripe da empresa — chaves, segredos do servidor, webhook, código das funções e do app, painel admin e publicar nas 3 plataformas. NÃO cobre mudar preços, comissões, taxas, tokens nem nada do Stripe Connect.

CONTEXTO (verificado pela Claude.ai a 01/11/2026)
Desde 01/11/2026 há DUAS contas Stripe:
- EMPRESA — "Bora", Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233, conta acct_1UX67LGWwQxC9wR2. Ativa em produção desde 01/11 às 22:05. Repasses para a conta da empresa no Millennium (termina em 3905), em modo manual. Entra-se com a conta Google boraappbora@gmail.com, no Chrome perfil Bora (deviceId d9e862e0-a5ea-486f-b054-f333ef51b46a — escolher pelo deviceId, nunca pelo nome "Browser 1/2").
- PESSOAL — "bora app", conta acct_1T8MFaGlT3R2jCYp. É a que o app usa hoje para tudo.

Regra do Danilo:
- TVDE / Bora Motorista fica na conta PESSOAL: corridas, pacote ida-e-volta, paragens, planos TVDE, reservas TVDE, mudança de destino, cancelamentos e reembolsos TVDE, gorjeta de corrida TVDE.
- TUDO O RESTO passa para a EMPRESA: entregas (restaurantes, mercados, lojas), Favores, limpeza, lavagem, Casa & Manutenção, marcações (barbearia/beleza), reservas de mesa (pré-pagamento 3 €), gorjetas de entregas, dívida e carteira, diferença de peso, extras e acertos de pedido.
- A conta da empresa começa do ZERO: não copiar clientes, cartões, produtos nem histórico da pessoal. O cliente volta a guardar o cartão no primeiro pagamento.
- Connect fica de fora desta missão: stripe_connect_enabled continua false e as contas Connect que existem ficam onde estão.

O QUE VAIS MEXER E PORQUÊ
- Segredos do Supabase (chaves e webhook da empresa) — para o servidor conseguir cobrar na conta da empresa.
- Edge Functions que tocam na Stripe — para cada pagamento ir para a conta certa (TVDE pessoal, resto empresa) e cada reembolso voltar pela conta onde o dinheiro entrou.
- Tabelas com pagamentos (coluna nova stripe_account) e users (coluna nova stripe_customer_id_empresa) — para saber sempre onde está cada euro.
- Flutter (Android, iPhone, web) — a app tem de abrir o pagamento com a chave da conta certa.
- Painel admin — o Danilo tem de ver e mandar em tudo isto.
- Relatórios da contabilista — a sociedade só pode declarar o que é da empresa; o TVDE nunca entra lá.

FASES

F0 — Pré-voo e inventário (só leitura)
1. git pull, confirmar a branch. Confirmar no e2e_log que a missão app-fechar-2026-11-01 terminou e que o código dela já está no servidor. Se ainda estiver a correr, NÃO arrancar: registar no e2e_log e esperar (verificar de 10 em 10 min).
2. Ler a implementação (não confiar no nome) de TODAS as Edge Functions e RPC/gatilhos SQL que chamam a Stripe, e fazer o mapa função → tipo de pagamento → conta (PESSOAL ou EMPRESA). Lista de partida, a confirmar no código: create-payment-intent, create-mbway-payment-intent, finalize-order-from-intent, stripe-webhook, refund, reprocess-refund, auto-refund-order, client-cancel-order, admin-cancel-order, cancel-order-with-choice, execute-cancellation, charge-extra, cobrar-diferenca-peso, order-edit-settle, pay-debt-standalone, list-saved-cards, manage-saved-cards, create-reservation-payment-intent, create-mbway-reservation-payment-intent, admin-cancel-reservation, create-appointment-payment-intent, create-mbway-appointment-payment-intent, confirm-mbway-appointment-payment, cleaning-checkout, cleaning-request-payment, diag-pagamento-limpeza, carwash-checkout, charge-tip, payments-reconciler, admin-payments, stripe-relatorio-contabilista, fecho-mensal-contabilista, tvde-payment, tvde-plan-payment, tvde-dest-change. Não mexer em stripe-connect-onboard, stripe-connect-webhook nem stripe-connect-admin.
3. A base de cada função é a versão EM PRODUÇÃO (ler pelo MCP do Supabase), não a do repo — o repo já esteve desalinhado de produção (tvde-payment, 13/08). Se divergirem, o repo é ressincronizado a partir de produção antes de mexer.
4. No Flutter: onde se define Stripe.publishableKey, PaymentSheet, cartões guardados, MB Way, e a parte web (Stripe JS).
5. Guardar o mapa em docs/STRIPE_DUAS_CONTAS.md.

F1 — Chaves da EMPRESA (Chrome perfil Bora, deviceId d9e862e0…)
1. Em dashboard.stripe.com/acct_1UX67LGWwQxC9wR2, criar uma chave restrita de produção "bora-app-servidor" só com as permissões que o código usa (PaymentIntents, SetupIntents, Customers, PaymentMethods, Refunds, Charges, leitura de Balance/Payouts para os relatórios). Se algum fluxo precisar de mais, usar a chave secreta padrão e escrever porquê no relatório.
2. Gravar pelo CLI (C:\supabase\supabase.exe secrets set …) como STRIPE_SECRET_KEY_EMPRESA. A chave publicável da empresa (é pública) vai como STRIPE_PUBLISHABLE_KEY_EMPRESA no servidor e no .dart_defines / segredo DART_DEFINES_FILE_B64 do CI.
3. Chaves secretas NUNCA no git, no chat, no Córtex, no e2e_log nem no Obsidian. Se encontrares uma chave secreta escrita num ficheiro do repo, trata-a como exposta: troca-a e reporta.
4. Métodos de pagamento da empresa: comparar com os que a conta pessoal tem ligados e o app usa (cartão, MB Way, Apple Pay/Google Pay se houver) e ligar os mesmos. Se o MB Way ficar "em análise", registar e continuar.
5. Se a Stripe pedir código de dois passos: mandar ao Danilo pelo canal de sempre UMA linha — "Abre o telemóvel e aprova o código da Stripe" — e esperar. Não lhe pedir mais nada.

F2 — Webhook da EMPRESA
1. Na conta da empresa, criar o destino de webhook para https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-webhook-empresa com EXATAMENTE os mesmos eventos que o webhook atual da conta pessoal escuta (ler na pessoal e copiar a lista).
2. Segredo de assinatura → STRIPE_WEBHOOK_SECRET_EMPRESA.
3. Função nova stripe-webhook-empresa (verify_jwt false, assinatura própria) com o MESMO tratamento do stripe-webhook (v38 em produção), por código partilhado em _shared/ — nada de copiar e colar. Usa o cliente Stripe da empresa. Se chegar um PaymentIntent tvde_* à empresa: alerta urgente ao admin e não mexe na corrida.
4. O stripe-webhook antigo continua vivo e intocado para a conta pessoal (TVDE, pagamentos antigos, reembolsos atrasados).

F3 — Servidor: a conta certa em cada pagamento
1. _shared/stripe_contas.ts: stripePara('empresa'|'pessoal'), contaDoFluxo(kind) e a regra "o dinheiro mexe-se sempre na conta onde entrou".
2. Coluna nova stripe_account ('pessoal'|'empresa', default 'pessoal') em todas as tabelas que guardam pagamentos Stripe (orders, payment_drafts, pending_charges, tips, cleaning_bookings, carwash_bookings, reservations, appointments e as da Casa/limpeza que tiverem PaymentIntent; tvde_rides e tvde_subscriptions ficam sempre 'pessoal'). Grava-se no momento em que o PaymentIntent é criado. Tudo o que já existe = 'pessoal'.
3. Reembolsos, capturas, cancelamentos, diferença de peso, extras, reprocessamento e reconciliador usam SEMPRE a conta gravada no pagamento, nunca a "atual". Pedido pago ontem na pessoal é reembolsado na pessoal.
4. Clientes Stripe: coluna nova users.stripe_customer_id_empresa. A users.stripe_customer_id fica para a pessoal (TVDE). list-saved-cards e manage-saved-cards devolvem os cartões da conta do fluxo pedido.
5. Interruptor em platform_settings: stripe_conta_nao_tvde = 'pessoal' até as provas passarem; depois 'empresa'. Voltar a 'pessoal' faz tudo regressar sem novo build.
6. Apps antigas já instaladas só conhecem a chave pessoal: o servidor só cria pagamentos na empresa quando a app diz que sabe lidar com duas contas (campo novo stripe_contas_v2=true). Sem isso, usa a pessoal como hoje. Nenhum cliente com app antiga pode ficar sem conseguir pagar. Reportar se existe forçar atualização (versão mínima) e propor quando a subir.
7. A resposta de criar pagamento passa a devolver publishable_key e stripe_account.
8. Código defensivo: chave da empresa em falta, rede a cair, toque duplo, null → cai para 'pessoal', regista e alerta. Nunca deixar o cliente sem pagar.

F4 — App (Android, iPhone, web)
1. Antes de cada PaymentSheet, confirmação, MB Way ou guardar cartão: Stripe.publishableKey = a chave devolvida pelo servidor (+ applySettings). TVDE continua na pessoal.
2. Cartões guardados da conta certa; depois da mudança, nas entregas aparece normalmente "adicionar cartão", sem erro.
3. Web igual (Stripe JS com a chave certa).
4. Não mudar aparência nem fluxos. Mantém-se a regra de 22/09: o cliente vê e troca o cartão antes de pagar.
5. A tranca (bora-tranca) protege order_store/finalizePurchase. Esta missão tem autorização literal para mexer no código de pagamento (citada acima). Se a tranca recusar mesmo assim, registar no e2e_log com o caminho do ficheiro e saltar esse ponto — não contornar.

F5 — Painel admin (PT-BR, termos técnicos explicados entre parênteses)
1. Página "Stripe — duas contas": que conta usa cada fluxo, o interruptor stripe_conta_nao_tvde (com confirmação), se as chaves existem (nunca mostrar o valor), últimos eventos de cada webhook e link para o painel de cada conta.
2. Em pedidos, pagamentos e reembolsos: coluna "Conta Stripe" (Pessoal/Empresa) e filtro.
3. Relatórios da contabilista (stripe-relatorio-contabilista, fecho-mensal-contabilista, stripe_extrato_contabilista): separar por conta. O da sociedade (Hugo) só leva a conta EMPRESA a partir de 01/11/2026. O TVDE nunca entra no da empresa.

F6 — Provas (sem cobrar cartões reais)
1. Modo de teste da conta da empresa, num ambiente local/emulador: cartão de teste 4242 numa entrega de mercado → pedido criado, webhook da empresa responde 200, stripe_account='empresa'. Reembolso → sai na empresa. Cartão guardado → aparece só onde deve. MB Way de teste. Corrida TVDE de teste continua na pessoal.
2. Pedido antigo pago na pessoal → reembolso em teste vai à pessoal.
3. Em produção, sem cobrar ninguém: criar e cancelar logo um PaymentIntent de 0,50 € na empresa pelo servidor (prova da chave) e ver nos logs o evento real desse cancelamento a chegar ao stripe-webhook-empresa com 200.
4. Só depois disto: stripe_conta_nao_tvde='empresa'. Provar por SELECT.
5. Ver em Android (emulador), iPhone (simulador ou TestFlight) e web (https://app.boraguarda.com) que o ecrã de pagamento abre com a conta certa.

F7 — Publicar
1. flutter analyze sem erros; testes existentes verdes.
2. Juntar o código e enviar para o servidor: git push origin autonomous-night-2026-04-29. O CI publica Play e web e incrementa o versionCode sozinho — nunca mexer nele à mão. Apple pelo caminho de sempre (TestFlight/App Store).
3. Provar as 3 plataformas (número da versão em cada uma). Hoje é domingo, o dia de publicar da semana.

F8 — Fecho
1. Relatório curto, em texto corrido e português de gente: o que ficou feito, o que falta, e outros erros encontrados pelo caminho.
2. Acrescentar o estado final à página stripe-duas-contas do Córtex (tabela claude_ai_memoria), sem chaves. Nota da missão no Obsidian (C:\Users\danil\Desktop\Bora).
3. Mensagem ao Danilo pelo canal de sempre: "A Stripe da empresa já está ligada" ou o que falta, numa linha.
4. /ctx doctor
5. /ctx stats

REGRAS
- Outro erro que encontres pelo caminho: REPORTA, não o corrijas calado.
- Não mexer em preços, comissões, taxas, tokens nem Connect.
- Não apagar dados de produção nem reescrever histórico git publicado.
- Autonomia: não terminar o turno à espera; o que ficar bloqueado regista no e2e_log e salta para o seguinte. O Danilo só é chamado para o código da Stripe no telemóvel, se aparecer.

02/11/2026 06:20 — RETOMA: a sessão antiga (session_01HPEpV8TqbMGfAxZbZkrQhU, Fable) parou e ficou parada. O Danilo mandou continuar numa janela nova com o Opus. Nova sessão: https://claude.ai/code/session_01HPEpVCiQJz5VkNWpbqKu2X (Opus 5.5, ambiente bora-app-cloud · Danilo). Prompt de retoma com: passo 0 = guardar em commit o que ficou na worktree antiga; regras novas = nunca DROP, parado mais de 5 min interrompe e regista; interruptor fica em pessoal até as provas F6; lojas só com ordem do Danilo. A sessão antiga só é arquivada depois de a nova confirmar o passo 0.
