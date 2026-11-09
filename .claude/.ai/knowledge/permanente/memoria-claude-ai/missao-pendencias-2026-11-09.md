---
id: memoria-claude-ai-missao-pendencias-2026-11-09
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-09
zona: verde
confianca: alta
estado: atual
---

# Missão pendências 30 dias (09/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `missao-pendencias-2026-11-09`, origem `claude-ai`, atualizada em 2026-11-09T20:54:10.277844+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: missao pendencias 2026 11 09 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5
PORTA: app Claude no PC › Code › Este computador › pasta bora_app › Ignorar permissões › SESSÃO NOVA (worktree própria wt-pend-2026-11-09)
FLUXO e2e_log: pendencias-30-dias-2026-11-09 (um passo por bloco, com prova)
ORQUESTRADOR: invoca o CEO-AI em .claude/skills/ceo-ai/ e a skill protocolo-missao-bora. Um líder + 2 a 4 agentes por bloco, nunca o exército todo.

AUTORIZAÇÃO DO DANILO (literal, 09/11/2026 20:43, na conversa com o Claude.ai, depois da lista numerada dos 15 pendentes):
"1 3 456 9 10 11 13 12 15 ... o Supabase já foi ... tem que ser gratuito"
Vale só para esta missão e só para os blocos abaixo. O peso no cartão (bloco G) tem também o "Autorizo" dele de 26/10 10:16 e a confirmação de 02/11 ("cobra-se a diferença no cartão").

ANTES DE TUDO
1. Ler no livro (claude_ai_memoria): erros-aprendidos, regras-do-danilo, livro-indice, o digest mais recente, regras-operacao-agentes.
2. Ler e2e_log dos fluxos m10-noite-toda-sem-travas-2026-11-08, m11-amigo-rosto-2026-11-09 e pendencias-30-dias-2026-11-09 (o Claude.ai já fez 2 consertos às ~21:00, ver passo erros-fora-scope-1-2).
3. Medir RAM antes de compilar (800 MB livres) e antes do emulador (3 GB).
4. Regra de sempre: diz no e2e_log que função/tabela/ecrã mexes e porquê. Outro erro que encontres pelo caminho: REPORTA no e2e_log e no relatório, não corrijas calado. Nunca apagar dados de produção; backup bkp_<nome>_20261109 antes de mexer em linhas. Toda migração aplicada fica também em supabase/migrations.
5. Travas: usa só as janelas que a M11 usou hoje (DESLIGAR-M11.ps1 e depois RESTAURAR-M10.ps1 com MD5 IGUAL, ver e2e_log m11 passos P2, E5, E6). Abre a janela só para aplicar SQL, publicar Edge e enviar para o servidor, e fecha-a logo. Proibido em qualquer janela: apagar dados, mexer em segredos fora do que o bloco pede, mudar preços/comissões fora dos blocos C e G, mandar mensagens a pessoas, publicar nas redes.

O QUE JÁ ESTÁ FEITO (não refazer, só confirmar se tocares no assunto)
- NIF na caixa: servidor, web e Android no ar; provado na rua hoje pelo Danilo (Continente 18:10 com NIF da Bora, KFC 19:15 com NIF do cliente, os dois com "Dei este NIF na caixa").
- Stripe da empresa: sem nenhum requisito pendente, pagamentos e repasses ativos (repasse semanal à quarta). Links do Connect da Goola e da Sabores de Casa enviados e abertos; a Boom fica por transferência. Nada a fazer aqui.
- Erros fora do scope: (1) enum cancellation_initiator ganhou 'partner'; (2) anon sem privilégios em ofertas_prestador_log; (3) colunas push_* do notify-driver já existem. Falta só o (4), bloco H.
- Robô do talão (catalog_price_update_from_receipt) FUNCIONA: correu hoje às 18:44 e 19:55. O talão do Burger King de 08/11 foi lido pela versão antiga, antes da M1 (23:46). Ver bloco C.
- CRM WhatsApp das PMEs (item 15): NÃO é desta missão. Vai para o Hermes pela tabela despacho, no projeto Supabase grátis bora-crm-pmes já criado.

BLOCO A — NIF no cartão principal do mapa (loja não-parceira)
Porquê: hoje o estafeta só vê o NIF se abrir "Ver compras" ou no ecrã do talão. No Favor já aparece no cartão principal. Tem de aparecer igual nas compras de restaurante e loja não-parceira (McDonald's, Burger King, KFC, mercados), para não passar na caixa.
O quê: lib/screens/driver_map_screen.dart, cartão principal (perto da linha 1846, onde está o do Favor): mostrar DriverInvoiceNifCard quando a loja não é parceira e o serviceType é storeShopping ou restaurant, de driverAccepted até isPurchaseFinalized. Sem caixa obrigatória aqui (a caixa continua no talão). O servidor decide se aparece (driver_order_invoice_nif); não mexer na regra do servidor.
Prova: teste de widget novo + os testes m10_nif_caixa_app_test. Atenção: esses 6 testes ficam vermelhos no Flutter 3.47 do PC por causa do aviso do ListTile; corre a suíte com o Flutter 3.41.2 do CI (o mesmo do build_android.yml). Se continuarem vermelhos no 3.41.2, é erro a sério: reporta.

BLOCO B — Comprovativo semanal diz sempre "MB Way" (item 4)
Porquê: hoje o comprovativo da Boom saiu "Enviado por MB Way" quando foi transferência bancária.
O quê: settlement_receipts passa a guardar o meio (copiar payment_reference do acerto no gatilho _settlement_receipt_enqueue, para parceiros, estafetas, limpeza, lavagem e prestadores). supabase/functions/settlement-receipt/index.ts, função comprovativoHtml (linha ~200) e o push: escrever o meio certo ("transferência bancária", "MB Way para <número>", "Stripe"). Sem meio conhecido: "Pagamento efetuado", sem inventar.
Painel: ao marcar pago, o meio escolhido tem de ir para payment_reference (ver admin_set_partner_settlement_status e as irmãs).
Prova: pré-visualizar o HTML de 3 casos sem enviar email a ninguém.

BLOCO C — Burger King: extras mais caros ao balcão (item 3)
Porquê: o Danilo mandou a 08/11 corrigir o catálogo do BK pela regra dele (talão mais caro corrige sozinho, só SUBIR). O menu em si bate certo; o que está barato na app são os EXTRAS (ex.: "EXTRA BACON 2 FATIAS" 2,50 € ao balcão contra 0,91 € na app, talão a244493e-5a85-4e20-ae01-ed6e20ebab62).
O quê:
1. Correr catalog_price_update_from_receipt nesse talão (fica 1 pendente para o painel) e correr de novo o ocr-receipt no talão do McDonald's de 08/11 (3b47bc38-2602-4365-80d6-879ebc556bff, nunca foi lido).
2. Extras do BK: guardar ao preço de BALCÃO (o sistema soma a margem sozinho; nunca guardar com margem, ver o erro corrigido hoje no Pôr do Sol). Só subir, nunca descer. Preço final na app nunca acima do Glovo da Guarda (regra de 05/09 e 23/10); onde o Glovo for mais barato que o balcão, fica no custo. Backup antes.
3. O robô passa a criar linha "pendente" em catalog_price_updates (para o ecrã de correções do painel) quando um EXTRA sai mais caro no talão, além do aviso que já dá. Não aplicar extras sozinho.
⚠️ ISTO MEXE EM PREÇOS: só os extras do BK com a regra acima. Nada noutras lojas.

BLOCO D — Casa: ficha do Danilo (item 5)
Copiar a data de nascimento da ficha de estafeta do Danilo (drivers.user_id 4f61dd31-5e9e-4a7c-a557-7d53d2ceded7) para a ficha da Casa (casa_profissionais ad8e790d-7519-4366-9565-257f816babd1), com registo em log_admin_action. O IBAN e a autocertificação são dele: NÃO preencher. No fim, dizer no relatório o que falta para aprovar (deve ficar só IBAN e autocertificação). Casa continua desligada.

BLOCO E — Entrar com Google (item 9)
Hoje não existe (pubspec sem google_sign_in; o ecrã de registo mostra "em configuração" atrás de SOCIAL_AUTH_ENABLED; auth.identities só tem email).
1. Google Cloud, projeto boraapp-d2bea, pelo Chrome da Bora (deviceId d9e862e0-a5ea-486f-b054-f333ef51b46a): ecrã de consentimento (externo, nome Bora, só email/profile/openid, sem verificação paga) e 3 IDs de cliente OAuth: Web (com segredo, redirect do Supabase), Android (pacote pt.boraapp.bora, SHA-1 da chave de assinatura da Play E da chave de upload) e iOS (bundle da app).
2. Supabase Auth: ligar o fornecedor Google com o ID e o segredo Web (segredo só no painel/CLI, nunca em ficheiro do repo).
3. App: botão "Continuar com Google" no login e no registo do cliente (PT-PT), Android, iPhone e web; conta nova com Google passa pelos mesmos termos (TermsGate) e perfil do cliente. Estafeta e parceiro continuam como estão.
4. Painel admin (PT-BR): ver por que método cada cliente entrou.
Se algum passo exigir o Danilo (código no telemóvel, ecrã de verificação da Google), deixa a página à frente dele e regista em e2e_log; segue com o resto.

BLOCO F — Chave do Google Maps (item 10)
Porquê: a chave AIzaSyBYLjK1... está no web/index.html e no AndroidManifest.xml, sem restrição, e nem sequer é de nenhum projeto do Danilo. É também ela que faz a trava barrar commits.
1. No projeto boraapp-d2bea criar 3 chaves NOVAS com restrição: Android (pt.boraapp.bora + SHA-1 Play e upload), iOS (bundle) e Web (referenciadores app.boraguarda.com, boraguarda.com, bora-app-web.pages.dev, localhost). Cada uma só com as APIs que o código usa (fazer grep primeiro: Maps SDK Android/iOS, Maps JavaScript, Places, Geocoding, Directions).
2. Quotas diárias por API dentro do grátis (tem de ficar gratuito): nada pode passar o escalão grátis do mês.
3. Trocar no código sem escrever chaves em lib/: Android por placeholder do manifesto lido de propriedade do Gradle/segredo do CI, web injetada no build pelo CI a partir de segredo, iOS no AppDelegate pelo mesmo caminho. Segredos novos no GitHub (MAPS_KEY_ANDROID, MAPS_KEY_IOS, MAPS_KEY_WEB).
4. Prova antes de publicar: mapa, morada (autocomplete) e rota a funcionar no emulador Android, na web e no simulador do iPhone do CI. Se o mapa partir em algum, volta atrás nesse e reporta. A chave antiga fica onde está nas versões antigas; não se apaga nada.

BLOCO G — Diferença do peso no cartão (item 11)
Porquê: produto ao quilo que sobe na balança e cliente que pagou com cartão: cobra-se a diferença no mesmo cartão (autorizado 26/10, confirmado 02/11).
1. Provar ponta a ponta em MODO DE TESTE da Stripe (chaves de teste, cartão de teste da Stripe), nunca com cartão real: pedido não-parceiro com produto ao quilo, estafeta sobe o peso, cobrança da diferença, recibo, painel.
2. Só com a prova verde: weight_adjust_card_charge_enabled = true. Regista o antes e o depois.
3. Limite de 30% para cima continua. MB Way: a Bora assume (não muda).

BLOCO H — Erro (4) do despacho TVDE + migração dos consertos
1. tvde_dispatch_sweep grava o evento sem_motorista mesmo quando a corrida continua (com o reforço TVDE ligado). Corrigir só esse registo, sem mudar quem recebe a corrida. É zona de despacho: proposta, prova em rollback, e só depois aplicar.
2. Pôr no repo a migração dos 2 consertos que o Claude.ai aplicou hoje (enum cancellation_initiator com 'partner'; revoke all em ofertas_prestador_log para anon): supabase/migrations/20261109210000_erros_fora_scope.sql, idempotente.

BLOCO I — Voz do Amigo no iPhone (item 13), tem de ser grátis
Porquê: o Safari do iPhone nem sempre tem voz pt-PT e o Amigo fica mudo.
1. Usar o projeto Google bora-juiz (gen-lang-client-0518472552), que já tem faturação: ligar a API Text-to-Speech, chave ou conta de serviço só para essa API.
2. Edge Function nova amigo-voz: texto → áudio pt-PT (nunca voz do Brasil), cache em Storage das frases repetidas, teto diário de caracteres em platform_settings (valor por defeito muito abaixo do grátis mensal: 1 milhão de caracteres Neural2 / 4 milhões Standard) e quota diária na própria Google para nunca cobrar. Passou o teto: a app volta à voz do aparelho, sem erro.
3. App: o Amigo usa a voz do aparelho quando há pt-PT; senão usa a amigo-voz. Painel admin (PT-BR): consumo do dia e do mês e o teto editável.
4. Prova: WebKit com emulação de iPhone e emulador Android.

BLOCO J — Publicar nas 3 e mandar o iPhone à Apple (item 1)
1. Gate do Juiz completo (anti_trapaca primeiro, analyze 0 erros, suíte verde no 3.41.2).
2. Enviar para o servidor só os ficheiros desta missão (git add por caminho).
3. Android (produção), web (app.boraguarda.com) e iPhone. A Apple aprovou a 1.0.39 hoje às 17:18 UTC, por isso o ios_publicar.py tem agora de criar a versão seguinte com a build nova e submetê-la. Confirma no CI que ficou WAITING_FOR_REVIEW. Se não submeter sozinho, corre o build-ios à mão com enviar=true e submeter_revisao=true.
4. Provar as 3: versão no ar e o texto novo no main.dart.js da web.

FECHO
- Relatório em TEXTO CORRIDO, curto, "fiz isto, falta isto", com os erros encontrados fora do scope. Fica em docs/relatorio-pendencias-2026-11-09.md e vai ao Telegram do Danilo.
- digest-2026-11-09-pendencias no livro; nota no Obsidian (C:\Users\danil\Desktop\Bora).
- Se algum bloco travar 15 min, salta-o, regista, segue com o seguinte; nunca terminar o turno à espera.
- /ctx doctor
- /ctx stats

