# Relatório — missão publica-2026-10-29 (29/10/2026, noite)

Motor Fable 5.1, na sessão "Missão geral Bora 2026-10-28" do PC. Cópia de trabalho `C:\BoraLocal\wt-missao-geral-28-10`,
ramo `missao-geral-2026-10-28`. Registo passo a passo no `e2e_log`, fluxo `publica-2026-10-29` (ids 5272 em diante).
Autorização usada: a do Danilo de 29/10 às 18:02 ("eu autorizo tudo, eu autorizo publicar também, vai publicar já hoje").

## O que ficou no ar

A publicação começou às 18:58 com o trabalho de ontem e de hoje de manhã (41 commits, junção 8a6e930a no ramo de
produção). A web ficou no ar às 19:01 (app.boraguarda.com, versão 1.0.4, build 696). O Android e o iPhone falharam no
primeiro CI, e a culpa não era da app: desde 26/10 "Sou Cliente" entra logo na página inicial sem conta (visitantes sem
conta, ligado no painel), e os dois arneses do CI ainda esperavam o ecrã de login a seguir. Corrigi os dois arneses (vão
pelo Perfil, "Entrar ou criar conta") e fiz a segunda publicação às 20:31 com a arrumação do Bloco B (junção ce2af44c).
A web dessa segunda publicação ficou no ar às 20:34. Android e iPhone: ESTADO_CI_AQUI.

A terceira junção, com o Bloco C (promoções, agendar, modo ocupado, substituição, tudo desligado por interruptor), é a
ESTADO_C_AQUI.

## Fiz isto

Bloco A. O ramo foi para o servidor à primeira (sem caixa da tranca) e juntou-se em produção sem conflitos, duas vezes.
A cópia da migração S1 para o repo foi recusada outra vez pela tranca (lê os nomes das chaves wallet_ e token_ como
tabelas de dinheiro): fica para a Claude.ai pelo GitHub, como o adendo 5 manda. O link curto dos cartazes da Boom
(boraguarda.com/pedir/boom) está no ar e manda para o WhatsApp da Bora nos três aparelhos; o boraguarda.com/baixar já
decidia no servidor para a Play Store e a App Store. O robô da Boom ficou ao vivo para o número do Danilo: a mensagem
dele das 19:03 não tinha resposta porque às 18:47 alguém escreveu à mão, do WhatsApp da Bora, para o número dele, e a
regra "o dono escreveu, robô calado 12 horas" calou-o; limpei o silêncio, tirei da cadeia os motores pagos e mortos,
pus o menu a responder em código sem motor (2,5 s), o aviso "já lhe respondo" aos 3,5 s, e o número de teste deixou de
poder ser calado. A resposta real à mensagem dele saiu às 19:20 e ele testou a seguir por voz e por texto (resposta em
voz aos 14 s; a de texto demorou 23 s numa volta de ferramentas, com o aviso aos 6 s). O robô ficou com a base de
conhecimento da Boom (história, ingredientes dos 14 hambúrgueres, horário, morada, entrega, perguntas frequentes), na
página `boom-robo-conhecimento` do livro, e com os factos da app Bora (instalar, formas de pagamento, BEMVINDO). O post
de lançamento "a Boom chegou à Bora" está escrito em três versões na página `boom-post-lancamento`, sem publicar. O
plano de 14 dias está conferido: os 17 lembretes batem com a página dia a dia, nenhum automático aparece como lembrete,
e pus links em três deles.

Bloco B. Canal de ofertas do estafeta deixa de abrir e fechar de 3 em 3 segundos (revisor independente aprovou). Os
termos: aceitar a versão mais recente cobre as anteriores (aplicado em produção com backup, provado em transação
desfeita). A escolha do reembolso ao cancelar ficou como o Danilo pediu: duas opções grandes, nenhuma marcada, carteira
Bora na hora ou devolver à conta (MB Way na hora, cartão 5 a 10 dias), valor igual nas duas, tokens voltam como tokens,
e o painel mostra a escolha. Favores: "Usar esta morada" procura a morada no mapa e nunca deixa o cliente num beco.
Carrinho sem a frase repetida; reservar numa loja "Em breve" diz "reservas". Os ganhos a 0,00 do estafeta demo não são
erro: os pedidos de teste ficam fora do dinheiro de propósito (provado nas funções do servidor). O vigia de pedidos
presos e site em baixo corre na VPS de 10 em 10 minutos e avisa o Danilo no Telegram só quando o estado muda. Os motores
grátis foram medidos um a um: o Gemini grátis dá só 20 pedidos por modelo e por dia, por isso o Groq ficou à frente
(tabela na página `motores-rotacao-2026-10-29`). O "created→preparing" do order_store NÃO foi removido, de propósito: na
base, o servidor permite ao cliente essas transições nos pedidos de mercado e foi o cliente quem as fez 21 vezes nos
últimos 30 dias; tirá-lo partia o despacho dos mercados (o 42501 da auditoria era só o pedido demo).

Bloco C, tudo desligado por interruptor e em paralelo por quatro agentes. Modo ocupado do parceiro (migração aplicada;
+10/+20/+30 no painel do parceiro, tempo maior para o cliente, ecrã admin; o despacho só muda com a proposta revista).
Agendar com a loja fechada (seletor de dia e janela de 30 minutos, separador Agendados do parceiro, ecrã admin;
migração no repo por aplicar; quatro propostas à parte, incluindo a peça do create_order que hoje recusa pedidos com a
loja fechada). Promoções com preço riscado e linha "preço mais baixo dos últimos 30 dias" (migração no repo por
aplicar; a troca de preço no servidor é só proposta, com a regra de dinheiro escrita para o Danilo confirmar: comissão,
markup e taxa de serviço calculam-se sobre o preço promocional). Substituição escolhida antes de pagar (migração
aplicada; seletor no checkout, estafeta vê a escolha, admin também; "tirar e devolver" ao meio original é só proposta).
O pedido em grupo (item 8) fica no CONTINUAR com o desenho pronto.

Bloco D. O CLI do Supabase funciona no PC mas não há token em lado nenhum: bloqueado. Os passos exatos para a Claude.ai
publicar as seis funções de reembolso pelo painel do Supabase estão na página `reembolsos-dashboard-passos`.

## Ficou desligado por interruptor, e porquê

partner_busy_mode_enabled, scheduled_orders_enabled (e scheduled_orders_revisor_ok), promotions_enabled e
substitution_choice_enabled: todos a falso, porque mexem no despacho (5 e 6) ou no dinheiro (4 e 7) e o Danilo quer o
revisor independente e a sua confirmação antes de ligar. Os interruptores de IA do adendo 4 (etiquetas por IA, resumo de
avaliações por IA) continuam desligados até teste com sessão de parceiro. O robô de documentos continua em sombra.

## Erros que encontrei pelo caminho

CI: o emulador do runner também congelou (adb offline, um fotograma de 97 s) além do arnês errado. Vigia: do lado da
VPS o site respondia 403 ao Python (Cloudflare) — corrigido com agente de navegador. Robô: o Groq cai às vezes para o
Gemini lite numa volta de ferramentas e a resposta chega aos 20 segundos; o timeout de 45 s do motores.py deixa o
cliente à espera; não mudei para não reiniciar o serviço enquanto o Danilo testava. O horário da Boom no adendo diz
19h15-23h e a base diz até 22h15 (o robô segue a base). O teste de paridade do painel apanhou a chave nova do modo
ocupado (alinhado).

## Precisa do Danilo (cada coisa com a página pronta)

1. Dizer "autorizo publicar as 6 funções de reembolso": a Claude.ai faz pelo painel do Supabase com ele a carregar no
   botão (página `reembolsos-dashboard-passos`).
2. Confirmar a regra de dinheiro das promoções antes de ligar (docs/propostas/missao-geral-2026-10-28/C4_promocoes/00_LEIA-ME.md).
3. Dizer "pode postar" ao post de lançamento da Boom (página `boom-post-lancamento`), com a loja aberta a 02 ou 03/11.
4. Decidir sobre a privacidade: o robô da Boom corre em motores grátis (Gemini e Groq) que podem treinar com as
   conversas (regra 14 do AGENTS.md).
5. Permissões da Meta (instagram_manage_insights, read_insights, ads_read) e o token da Supabase CLI, quando quiser.

## Para a Claude.ai

Copiar a migração S1 para o repo pelo GitHub (depois desta missão fechar). Aplicar por MCP as migrações
20261029200700_c5_agendar_pedidos.sql e 20261029200800_c4_promocoes.sql (já no repo). Revisor independente das
propostas de despacho C5 e C6 antes de ligar. Publicar as seis funções de reembolso quando o Danilo autorizar.

## Próximo passo

CONTINUAR-final-app-2026-10-29.md tem a lista do que sobrou (pedido em grupo, propostas, migrações, motores.py).
