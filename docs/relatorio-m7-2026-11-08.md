# Relatório da missão M7 — Stripe, parceiros, radar, leis (08/11/2026)

Sessão Claude Code (Opus 5.5) no PC, worktree `C:\BoraLocal\wt-m7-2026-11-08`, ramo
`ai/2026-11-08-m7-stripe-parceiros-radar-leis`. Modo automático seguro (regra de 05/11): fiz e testei
no ramo; não publiquei nada; quem aplica o SQL, publica as funções e as 3 lojas é a Claude.ai.
Registo passo a passo no e2e_log, fluxo `m7-stripe-parceiros-radar-leis-2026-11-08` (ids 7079 em diante).

## O mais importante: o dinheiro da Stripe não está preso pelo cadastro

Fui ver a conta da empresa pela API da Stripe (só leitura). O cadastro está completo: a Stripe não
pede nada, os pagamentos e os repasses estão ligados e o IBAN do Millennium (acaba em 3905) está lá.
Os 155,79 € estão "pendentes" porque uma conta nova da Stripe segura o primeiro dinheiro uns dias.
Ficam disponíveis assim: 38,63 € amanhã (09/11), 16,33 € a 10/11, 28,31 € a 11/11 e 72,52 € a 12/11.
O motivo de nunca ter caído nada no banco é outro: os repasses estão em MODO MANUAL. Mesmo com
saldo, a Stripe não manda nada ao Millennium sozinha. Para ficar semanal é um clique na página
https://dashboard.stripe.com/settings/payouts (Agenda → Semanal). Isso mexe em levantamentos de
dinheiro, por isso não carreguei: fica para o Danilo.

## Fiz isto

**Stripe da empresa para os parceiros (bloco 1).** Hoje a empresa tem zero contas de parceiros, e as
três funções de cadastro dos parceiros só falavam com a Stripe pessoal. Mudei-as no ramo para saberem
das duas contas, e criei um link de cadastro PERMANENTE (o da Stripe expira em minutos, este pode ir
por WhatsApp e abre sempre um cadastro novo). Há um interruptor novo, `stripe_connect_conta_nova`, que
nasce em "pessoal", por isso nada muda até alguém o virar. O webhook dos parceiros passa a aceitar a
assinatura das duas contas. No painel, o ecrã Pagamentos Connect mostra agora "Stripe pessoal" ou
"Stripe da empresa" em cada conta, e tem o botão "Link permanente de cadastro (WhatsApp)". O SQL ficou
como proposta em `docs/propostas/m7-connect-empresa/01_conta_dona_e_convites.sql`. Provas: 7 testes
novos das funções verdes e as 4 funções compilam (deno, fora do repo).

**Mensagens (bloco 1d).** Estão escritas e NÃO foram enviadas. Como este repositório é público, o
ficheiro com os nomes e o que falta a cada pessoa ficou fora do git, no PC, em
`C:\BoraLocal\privado\m7-2026-11-08\mensagens-m7-2026-11-08.md`. Vi na base o que falta aos 3
estafetas aprovados com entregas (dados fiscais diferentes para cada um). A todos falta também a
autocertificação, uma declaração que eles próprios têm de aceitar na app (DSA e DAC7). Um estafeta já aprovado ainda não
tem na app sítio para preencher isto, porque o ecrã "A minha conta" é da M2 e ainda não está
publicado. Por isso as mensagens pedem para responder pelo WhatsApp, e não mandam ir ao "Perfil".
As dos parceiros (Boom, Goola, Sabores de Casa, Sabores do Brasil) só podem sair depois de o Connect
estar ativo na empresa. A do Hugo sobre o IRS também está lá.

**Pagamentos em falta (bloco 2).** Lista fora do git (repositório público), em
`C:\BoraLocal\privado\m7-2026-11-08\pagamentos-recorrentes-2026-11-08.md`, e no livro (página
`pagamentos-recorrentes`, marcada [PESSOAL] para não ir para o espelho público). Só li, não paguei nada. Mais urgente: o VPS da Hostinger, onde vivem o
Hermes e o Emerson, renova a 13/11 por 21,51 €. Entre julho e setembro o cartão foi recusado 10 vezes
e o VPS expirou a 13/09, por isso vale ver o cartão antes de quinta. O Google One / AI Plus da conta
da Bora tem o pagamento recusado desde 05/11 e vai ser cancelado se o cartão não for atualizado. Os
anúncios Meta gastam 3 a 12 € por dia e são pré-pagos, por isso é preciso carregar antes de o saldo
acabar. A subscrição do Claude teve cobranças recusadas no fim de outubro: o estado real está por
confirmar. Os documentos de motorista da Bolt e da Uber vencem por
volta de 26/11. Em dia: o Supabase (plano Pro) e o domínio boraguarda.com (expira a 27/08/2027, na
Cloudflare). Ficou por ler, porque o Chrome pessoal estava lento: a data da Apple Developer, a fatura
de 1,69 USD da Anthropic, a Cloudflare, o Resend e a Google Cloud.

**Radar e briefs (bloco 3).** Li as 30 propostas pendentes do Córtex. Arquivei 11: 3 porque ficaram
feitas e 8 porque eram repetidas ou fora de foco. As outras 19 ficaram na fila, cada uma com o nome
da missão, em `docs/radar/triagem-propostas-2026-11-08.md`. Ficou feito: o banco de formatos de reels
com os ganchos "troquei X por Y", a métrica de sucesso obrigatória em todo agente novo, o guia de uma
página "Perfil Google da tua loja", e o cartaz A5 do QR com a lista de 10 sítios (só IPG, residências
e campus estão confirmados; imprimir fica contigo). A trava que barra comandos perigosos já existe no
PC desde 05/11; falta a da VPS, que foi para a fila. Os vídeos do radar ficaram no livro
(`ideias-videos-danilo`); o melhor é auditar o nosso próprio APK e site com o REA, que foi para a fila.
Os GIFs do ChatGPT não testei esta noite, porque o Chrome pessoal estava ocupado e a memória do PC
estava baixa.

**Plano de 14 dias (bloco 4).** Balanço honesto em `docs/plano-14-dias/` e no livro (`plano-14-dias-2`):
20 pedidos entregues e 68 contas novas no período, quase tudo depois de a Boom abrir a 02/11;
nenhum angariador, nenhuma das 16 lojas abordada, o IPG sem resposta. Plano novo de 09/11 a 22/11
com 3 lojas por dia pelo WhatsApp da Bora, com texto humano e devagar, e cada texto passa por ti antes
de sair. Correção: há anúncios Meta a correr (carregaste 56 € entre 31/10 e 06/11).

**Leis (bloco 5).** O dossier está em `docs/legal/dossier-leis-2026-11-08.md` e no livro (`leis-bora`),
com a fonte oficial em cada ponto. Não sou advogado: é um mapa para levar ao Hugo e à advogada. Há três
coisas que pesam mais. Primeiro, a Bora tem 22 faturas suas por emitir desde 25/10, num total de
107,91 €, e nenhuma tem número. Segundo, a app e o site ainda dizem que o Bora é teu, em nome
individual e com o NIF pessoal, e não da empresa. Terceiro, a marca "Já Está" ainda não está
registada: é o pedido n.º 778820 no INPI, publicado a 29/10, e pode haver oposição até 29/12/2026.
Os resumos do ChatGPT: o DL 212/2026 existe (saiu a 04/11 e baixa o IRS de 2026); os 18% de IRC em
2027 já estão na Lei 64/2025 e não dependem do Orçamento. As 10 ações por ordem: (1) emitir as 22
faturas e ligar um programa de faturação certificado, e o email ao cliente passa a dizer "não serve
de fatura"; (2) pôr a empresa na app, no site e nos termos; (3) o Livro de Reclamações em destaque, e
tirar o link da plataforma europeia de litígios, que fechou; (4) escolher um só modelo de recibos dos
estafetas (recibo deles ou autofaturação com acordo escrito) antes de 01/12; (5) alinhar os termos com
a decisão fiscal de 03/11; (6) preparar o prazo de 02/12 da diretiva das plataformas; (7) alergénios
(só 1 dos 250 pratos dos parceiros os tem); (8) o assistente diz que é IA, pede consentimento antes
de guardar alergias, e a Receita do Dia só vai a quem aceitou promoções; (9) pacote para o Hugo
(DAC7, Segurança Social, IRS 2026, IRC 2027); (10) vigiar oposições à marca até 29/12.

**Menu (bloco 6).** Proposta em `docs/design/navegacao-2026-11-08.md`, com o desenho em
`navegacao-2026-11-08-mockup.html`. O cliente fica com 4 separadores claros, o estafeta com uma barra
em baixo (Mapa, Pedidos, Ganhos, Conta) e a mira de centrar a meio do ecrã do lado direito, e o
parceiro com 5 separadores com texto. Não implementei, porque mexe no ecrã do estafeta, que é da M2.
Fica para a M8.

**Motorista → entregas (bloco 7).** O cliente já via o estafeta a deslizar no mapa. Juntei o que o
Bora Motorista tem: a hora de chegada ao lado dos minutos ("Chega em ~15 min · às 19:45") e o aviso
"Estafeta já chegou para levantar o pedido" quando o estafeta está a menos de 150 m da loja. A
avaliação já não trava (tem "saltar" e só pergunta 2 vezes); mudei o botão para "Agora não". A lista
completa, com o que vale a pena e quanto custa, está em `docs/design/paridade-motorista-delivery-2026-11-08.md`.
A fila inteligente e a compensação por cancelamento tardio mexem em despacho e dinheiro, por isso
ficam à espera do teu "autorizo".

**Contradições no livro (bloco 8).** Encontrei 14. Acrescentei 15 linhas "SUPERADO em…" em 9 páginas,
sem apagar nada. Lista em `docs/livro-divergencias-2026-11-08.md`. Ficam 7 correções para a Claude.ai
fazer na memória dela, e duas decisões tuas: se o TVDE se apaga ou fica só fechado, e quem paga as
taxas do repasse automático das lojas.

**Concorrência (bloco 9).** Tabela de 15 temas no livro (`comparativo-concorrencia-2026-11`). Das 5
melhorias pequenas, apliquei 4 no ramo: a hora de chegada, "tua morada" em vez de "sua morada",
"Agora não" e "Loja aberta/Loja fechada" no parceiro em vez de ONLINE/OFFLINE. A 5.ª ("Entrega" passar
a "Pedidos" na barra do cliente) tem testes que dependem do texto e fica para a M8.

## Falta isto (e porquê)

1. **Pôr os repasses da Stripe em semanal.** Um clique teu na página dos repasses; mexe em
   levantamentos, por isso não carreguei.
2. **Ativar o Connect na Stripe da empresa e aceitar as responsabilidades da plataforma.** É decisão
   tua, tal como fizeste a 06/08 na conta pessoal. Depois disso, a Claude.ai cria o webhook dos
   parceiros na empresa, aplica o SQL, publica as 4 funções e vira o interruptor. Só então os links
   de cadastro funcionam e as mensagens aos parceiros podem sair. Atenção: a chave da empresa que está
   no servidor (`STRIPE_SECRET_KEY_EMPRESA`) é uma chave RESTRITA criada a 02/11 para pagamentos. Antes
   de virar o interruptor, confirmar que tem as permissões de Connect (Accounts, Account Links e Login
   Links em escrita). Se não tiver, as funções respondem com erro e nenhum parceiro fica afetado, porque
   o interruptor continua em "pessoal".
3. **Enviar as mensagens.** Os textos estão prontos e esperam o teu "sim" a todas juntas.
4. **Publicar a app** (hora de chegada, aviso de chegada à loja, textos, painel). Quem publica é a
   Claude.ai, depois de rever o ramo. O ramo ficou só no PC, porque a tranca não deixou enviá-lo para o
   GitHub ("publica o Claude.ai"). A Claude.ai envia-o e abre o pedido de revisão.
5. **Testes completos.** Corri a análise e os testes dos ficheiros que mudei. A bateria inteira
   (163 ficheiros) não coube, porque a memória do PC estava em 305 a 741 MB com outras missões a
   compilar. Passa antes da publicação.

## Erros que encontrei pelo caminho

- As três funções `stripe-connect-*` que estão no servidor são as de 06/08. O repositório tem uma
  mudança de 16/10 (chave nova do servidor) que nunca foi publicada; vai junto com esta.
- O ecrã de pagamento mostra 2,50 € de taxa no não-parceiro, mas o servidor cobra 0,99 €. Já estava
  reportado; é zona protegida e não mexi.
- O agente `parceiro-servicos` diz que a reserva é 0,50 € Bora + 2,50 € parceiro, e o livro diz
  1 € + 2 €. Falta confirmar no servidor qual está certo antes de corrigir.
- O `CLAUDE.md` (secção 10) e o livro dizem que a marca "Já Está" está registada no INPI. Não está:
  é o pedido 778820, à espera de oposições até 29/12. Fica para a Claude.ai corrigir a regra (o
  `CLAUDE.md` vale para todas as sessões).
- 22 faturas da Bora estão por emitir desde 25/10 (107,91 €). É assunto do Hugo, e é o ponto 1 das leis.
- O Google One/AI Plus da conta da Bora tem o pagamento recusado (emails de 05, 07 e 08/11) e vai ser
  cancelado se o cartão não for atualizado.
- O `flutter pub get` mexe sozinho no `analysis_options.yaml` e nos ficheiros gerados de
  Linux, macOS e Windows. Repus tudo antes de gravar.

## Próximo passo

Primeiro, o clique nos repasses da Stripe, para o dinheiro começar a cair no Millennium.
Depois, ativar o Connect na empresa. Com isso a Claude.ai fecha o resto e os parceiros recebem o link.
