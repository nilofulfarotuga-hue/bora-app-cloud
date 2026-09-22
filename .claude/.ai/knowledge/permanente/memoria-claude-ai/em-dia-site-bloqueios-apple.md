---
id: memoria-claude-ai-em-dia-site-bloqueios-apple
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Em Dia / site: tres coisas no site que chumbam a revisao da Apple

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `em-dia-site-bloqueios-apple`, origem `claude-ai`, atualizada em 2026-09-22T11:49:48.072619+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: em dia site bloqueios apple · memoria claude.ai · claude_ai_memoria

Encontrado a 22/09/2026 ao preencher a ficha da App Store. Sao todas edicoes no site (repo em-dia-app, pasta site/), nao na app. NENHUMA foi corrigida por mim: nao tenho o repo e e trabalho do executor.

1. O SITE DIZ QUE O IPHONE E SO BROWSER
Em emdia.boraguarda.com esta escrito: "Android pela Play Store. iPhone e computador pelo browser, sem instalar nada." Dois problemas: (a) fica errado assim que a app de iPhone existir; (b) o revisor da Apple le o URL de suporte, e uma pagina que diz que a versao de iPhone e um site convida a recusa pela diretriz 4.2 (funcionalidade minima / app que e so um invólucro de site). Tem de passar a mencionar a app de iPhone, e a pagina de suporte nao deve empurrar o utilizador de iPhone para o browser.

2. O SITE VENDE PLANOS QUE NAO ESTAO A VENDA
O site anuncia "Gratis 30 dias com tudo aberto. Sem cartao." e tres planos: Gratis, Pro, Familia/Frota. Mas regras_legais.planos_a_venda = 'nao' e a build nao vende nada. O revisor procura a compra, nao a encontra, e recusa ou pede esclarecimento. O site tem de passar a dizer o mesmo que regras_legais.promessa_gratis_texto: por agora esta tudo aberto, nao se paga nada, e quando as assinaturas abrirem ha aviso com 30 dias.

3. A POLITICA DE PRIVACIDADE FALA DA GOOGLE PLAY
Em emdia.boraguarda.com/privacidade esta: "A Google Play trata o pagamento. Nos so recebemos o comprovativo tecnico da compra e o estado da assinatura." Numa app da Apple isto esta errado duas vezes: nao ha pagamento nenhum por agora, e quando houver em iOS quem trata e a App Store. Tem de ficar neutro quanto a loja, ou nomear as duas.

MAIS UMA COISA, ESSA NO CODIGO (nao no site)
Por ITSAppUsesNonExemptEncryption = false no Info.plist do iOS. A Em Dia so usa HTTPS, que e encriptacao isenta. Sem esta chave, o App Store Connect pergunta pela conformidade de exportacao a CADA envio de build e bloqueia o TestFlight ate alguem responder a mao.
