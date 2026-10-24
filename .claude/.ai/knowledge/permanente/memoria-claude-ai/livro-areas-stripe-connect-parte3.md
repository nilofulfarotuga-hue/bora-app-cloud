---
id: memoria-claude-ai-livro-areas-stripe-connect-parte3
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-24
zona: verde
confianca: alta
estado: atual
---

# Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases (parte 3 de 3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-stripe-connect-parte3`, origem `claude-ai`, atualizada em 2026-10-24T10:15:53.199855+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas stripe connect parte3 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/stripe-connect.md), copiada a 24/10/2026 11:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

- [stated] A chave `id_ed25519_bora_deploy` existe mesmo em `C:\Users\hermes\.ssh\` (Test-Path=True), mas a pasta `.ssh` tem ACL própria que EXCLUI o utilizador `danil`, mesmo `danil` tendo FullControl na pasta-mãe `C:\Users\hermes`. Sessão do executor: utilizador danil, SEM privilégios de administrador (Get-Acl e icacls também negados). Não há cópia da chave em danil\, Desktop, Downloads nem ProgramData. Só existe `id_ed25519_vps` (essa é da VPS, não do GitHub).
- [stated] O executor RECUSOU-SE a forçar o acesso (mexer nas permissões a partir da pasta-mãe) por iniciativa própria — decisão certa, ficou registada como decisão do Danilo se quiser esse caminho.
- [stated] CHERRY-PICK TESTADO em worktree isolado (não tocou no diretório de trabalho real): 7/7 commits sem UM conflito — be13c8e, 1ec200c, bd9517d, b7d2d94 (a missão), mais 1c0a420 (relatório), 44d8a5f (v8 real do tvde-payment gravada no repo) e a74a321 (as correções v9 que já estão em produção). Os 2 últimos são necessários — sem eles o repo volta a ter o tvde-payment velho. NADA foi publicado ainda.
- [stated] PLANO ESCOLHIDO (Claude.ai, 2026-08-13): tentar primeiro trocar o remote para HTTPS (`https://github.com/nilofulfarotuga-hue/bora-app-cloud.git`) na conta danil e correr `git fetch` — é o caminho mais parecido com o que já funcionava antes nesta conta (login via Git Credential Manager, um clique de "Authorize" numa janela do navegador se pedir, ou nem isso se a sessão ainda estiver em cache). SÓ se isto falhar é que se cria um GitHub Personal Access Token como reserva.

SSH resolvido sozinho, sem nenhum clique do Danilo (2026-08-13, visto por foto do ecrã)
- [stated] Trocar o remote para HTTPS + `git fetch` autenticou sem pedir NADA — já havia credencial guardada no Windows para github.com (utilizador nilofulfarotuga-hue) via Git Credential Manager. Não precisou do token de reserva.
- [stated] O executor detectou sozinho que o ramo de destino (autonomous-night-2026-04-29) mudou desde o teste do cherry-pick: já recebeu o Stripe Connect Fase 1 (o que tirou o medo da "boleia" — resolve-se por si, já é a base agora) mas também mexeu em `admin_dashboard_screen.dart`, ficheiro que os commits desta missão também tocam. Está a re-testar o cherry-pick contra a cabeça nova antes de publicar — decisão cautelosa e certa, ainda sem push feito.
- [stated] AVISO OPERACIONAL: o Claude Code do Danilo mostrou "Próximo do limite de uso semanal — reinicia dom. 16/08 19:00". Vale a pena não abrir sessões extra nesta missão até isso resolver, para não ficar sem motor a meio de um push.

Estado real a 2026-09-14 (Claude.ai por MCP) — CORRIGE linhas antigas deste ficheiro
- [stated] Danilo quer cadastrar-se a SI PRÓPRIO primeiro, como MOTORISTA, numa conta Connect separada da conta do Bora, com IBAN de outra conta bancária (a conta da plataforma, do banco novo, fica com o que sobra do Bora) — e usa esse cadastro como treino para depois fazer os outros estafetas e parceiros. Substitui o plano de começar pelo Gilberto da [[ouro-e-prata]].
- CONTA DELE ATIVA (14/09, verificado por mim na Stripe live): `acct_1U1RpKGdkGTRCF27` com details_submitted, charges_enabled e payouts_enabled true, transfers active, termos aceites e IBAN de OUTRA conta bancária dele (Millennium BCP) registado — era exactamente o que ele queria. Continuam `disabled` e por preencher só [[goola-acai]] `acct_1U9JSJGaqvfVyyow` (company: pede NIPC, dados do dono e IBAN) e [[ouro-e-prata]] `acct_1U1RnZGtdmD8LsOp`. Colunas stripe_account_id/status existem em drivers, restaurants, service_providers e cleaners.
- CADEIA PROVADA PONTA A PONTA: o `stripe-connect-webhook` apanhou o account.updated sozinho e `drivers.stripe_account_status` passou a 'enabled' sem ninguém tocar em nada.
- Pendente na conta dele: `individual.verification.document` em eventually_due (a Stripe vai pedir foto do documento; ainda não trava nada) e a morada ficou com o nº 12 quando é o 14 — decidi NÃO mexer agora para não reabrir verificação, e corrigir as duas coisas juntas quando o documento for pedido.
- `stripe_connect_enabled` continua FALSE e a Fase 2 (transferência automática no fecho semanal) continua por fazer — mesmo com o cadastro terminado o acerto continua manual/MB Way. [stated] Ele quer o repasse automático a funcionar já na semana seguinte; avisei que ligar mexe em dinheiro a sério e fica à espera da palavra dele.
- O conector Stripe da Claude.ai VOLTOU a ter a conta LIVE (acct_1T8MFaGlT3R2jCYp, livemode true) — já dá para ler contas e requisitos por MCP. O MCP NÃO expõe account_links (PostAccountLinks não existe), MAS há caminho que FUNCIONA e é só meu, sem executor: Edge `tmp-connect-link` (criada 14/09, segredo `[REMOVIDO]`), chamada por `net.http_post` com a service_role key de `vault.decrypted_secrets`, resposta lida em `net._http_response`. O Account Link da Stripe expira em ~5 MINUTOS, por isso a v2 da função (verify_jwt FALSE) tem também um CONVITE PERMANENTE por GET: `https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/tmp-connect-link?a=<acct_>&k=<chave>`, em que a chave são os 16 primeiros hex de SHA-256("<acct_>|<segredo>") — devolvida no campo `convite_key` do POST. Gera um link fresco a cada toque, logo pode ser enviado por mensagem ao parceiro (a do [[goola-acai]] é [REMOVIDO]). Testado a funcionar.
- LIMITE DA STRIPE a não voltar a tentar: em contas Express com recolha pela Stripe, a plataforma SÓ pode pré-preencher `business_profile` (nome, url, mcc, contactos de apoio). `company`, `email` e o IBAN são recusados ("not authorized to edit"/"does not have the required permissions") — o NIPC, a morada, os dados do dono e o IBAN têm mesmo de ser metidos pela própria pessoa no formulário, mesmo quando já os temos na ficha da loja.
- CAMPO "website" do onboarding: a resposta certa para TODA a gente (estafetas e parceiros) é `boraguarda.com` — é a plataforma de onde vem o dinheiro, como o motorista da Uber que põe uber.com. Ele confundiu-se a pensar que era um site dele; explicado.

Quem paga a taxa da Stripe — decisão por parceiro (2026-09-14)
- [stated] A regra antiga "a taxa da Stripe é sempre cobrada ao parceiro/estafeta" NÃO é uniforme: ao [[goola-acai]] NÃO cobra taxa de Stripe nenhuma (considera-a já incluída na comissão); ao Gilberto da [[ouro-e-prata]] cobra, por enquanto, SÓ a taxa de transferência para a conta dele — o resto do valor do serviço vai todo para o Gilberto.
- [stated] O serviço ao Gilberto fica GRÁTIS por agora; daqui a cerca de um mês, com a coisa mais desenvolvida, é que combina com ele o preço mensal.

Stripe nova da empresa (24/10/2026)
- [stated] Decidiu abrir uma Stripe NOVA em nome da empresa (Unipessoal Lda) e passar para lá TODAS as categorias — começa um ciclo novo, tudo o que passar a partir daí vale a sério e tem de ficar registado direitinho. A Stripe atual (no nome pessoal dele) continua, mas só para o Bora Motorista (TVDE), que NÃO passa por agora
- [stated] A Stripe da empresa tem de ser TOTALMENTE separada da conta pessoal (login e email próprios, sem ligação nenhuma) e sem levar histórico, clientes ou cartões da conta pessoal — começa do zero. Não abriu ainda (24/10: "por enquanto não vou fazer")
- [stated] Para o email das contas da empresa decidiu usar, por enquanto, o domínio do Bora (boraguarda.com) em vez de criar um Gmail novo
