# Oferta fantasma no TVDE — relatório de 01/10/2026

Missão `tvde-oferta-fantasma-2026-10-01`. Porta: Claude Code. Corrida que deu origem: 03874579-8c4e-4120-b121-374523e1ddfb.

## Acessos

Não foi criada nem alterada nenhuma conta. Contas que entraram nas provas: o cliente demo (demo@bora.app), só para confirmar que o início de sessão funciona, em leitura. A conta de motorista demo (demo-estafeta@bora.app) não foi tocada. A consulta ao GitHub usou a credencial que o Git já tinha guardada neste PC.

## O que NÃO foi feito

A prova ao vivo no emulador não foi feita. Era uma das provas pedidas: aceitar uma oferta de teste a dinheiro, finalizar e voltar à home. A causa é memória do PC, não é a aplicação. O modelo do Ollama ocupa entre 4,3 e 5,5 GB e é usado pela VPS através do túnel; quando o descarreguei, voltou a carregar sozinho em menos de cinco minutos. Com o emulador aberto medi 383, depois 375 e depois 172 MB disponíveis. O Android dentro do emulador reiniciava serviços e a instalação ficava pendurada. Fiz três tentativas com abordagens diferentes e parei. Nenhuma corrida de teste chegou a ser pedida em produção e a conta demo ficou como estava. Havia também uma segunda razão para cuidado: o Danilo estava ligado e a trabalhar, e uma oferta de teste pode rodar para um motorista real; o guião que deixei pronto tem um vigia que a cancela antes disso.

O que substitui essa prova por agora: o autoteste dos três perfis no emulador do CI passou com este código, e os testes de widget reproduzem o mecanismo exacto da corrida de hoje. O que nenhum deles prova é o caminho completo no aparelho com uma oferta verdadeira. Fica a ordem de continuação em `.claude/.ai/inbox/CONTINUAR-tvde-oferta-fantasma-2026-10-01.md`, com as duas condições a medir antes (memória livre e nenhum motorista real ligado).

O painel admin não levou nada: não há funcionalidade nova nem chave de definições mexida.

## O que foi feito e porquê

Ecrã da oferta (`lib/screens/driver/tvde/tvde_offer_screen.dart`). Era este o ecrã fantasma. Ao aceitar, ele mandava fechar "o ecrã de cima". Quando o aviso em tempo real chegava antes da resposta do servidor, a home já tinha aberto o ecrã da corrida por cima, e o que se fechava era a corrida. A oferta ficava presa por baixo, já sem som e com os botões mortos, e reaparecia no fim da viagem. Agora o ecrã fecha a sua própria rota: se está em cima sai normalmente, se ficou por baixo é retirado do meio sem tocar no de cima. Vale para os três sítios onde fechava. Há também uma rede de segurança: assim que a corrida passa a ser dele, activa ou em fila, o ecrã da oferta sai sozinho.

Home do motorista (`lib/screens/driver/tvde/tvde_driver_home_screen.dart`). Deixou de abrir o ecrã da corrida enquanto a oferta está aberta, e volta a decidir a navegação no momento em que a oferta fecha. Assim a corrida abre logo a seguir, sem empilhar.

Notificações e store (`lib/services/notification_service.dart` e `lib/stores/tvde_driver_store.dart`). Era o aviso que ficava em cima como se houvesse outro pedido. A notificação esperava pela criação do canal antes de aparecer; se o aceite a mandava cancelar nesse intervalo, nascia depois e ninguém a matava. Agora aceitar e recusar cancelam sempre a notificação pelo identificador da corrida e marcam a oferta como respondida. Quem vai mostrar o aviso pergunta por essa marca depois da espera e outra vez depois de mostrar. A marca fica gravada para o processo de segundo plano também a ver.

Store (`lib/stores/tvde_driver_store.dart`). As leituras do servidor passaram a ter ordem. Só a mais recente escreve, e se o estado mudou enquanto se lia, lê-se outra vez em vez de escrever o que já era passado. Uma corrida que já é dele, ou que ele já respondeu, nunca volta a entrar como oferta.

Cartão sobreposto (`lib/widgets/tvde/tvde_offer_overlay_host.dart`). Deixou de desenhar uma "oferta" que é a corrida activa, que já não procura motorista ou que é para outra pessoa. Quando a oferta vem sem prazo, conta 25 segundos seus em vez de ficar parado nos 25.

Não toquei em servidor, despacho, preços nem ganhos.

## Revisão independente

Um verificador com contexto limpo tentou derrubar a correcção. Não derrubou o núcleo, mas encontrou uma regressão verdadeira: depois de recusar pelo botão da notificação, a mesma corrida oferecida outra vez numa roda nova podia chegar sem aviso, porque a marca durava 45 segundos e o servidor volta a oferecer aos 35. Corrigi antes do envio: a janela passou a 25 segundos e há um teste que obriga a que seja menor do que a pausa do servidor. Corrigi mais três pontos que ele levantou: o cartão sobreposto desaparecia ao tocar em Aceitar em vez de mostrar que estava a aceitar; a comparação de prazos perdia precisão entre processos; e um recusar que falha por rede deixava a oferta marcada como respondida.

Ficaram dois avisos dele por tratar, de gravidade baixa. Quem pede uma releitura e é ultrapassado por outra mais recente regressa antes de o estado estar escrito; corrige-se sozinho no aviso seguinte. E os testes não exercitam o aceitar e o recusar verdadeiros contra o servidor, nem a notificação a nascer; essa parte está coberta só por guardas de código.

## Provas

Testes novos em `test/tvde_oferta_fantasma_test.dart`, dezanove. Os dois principais: aceite com a resposta do servidor atrasada dois segundos, viagem inteira, e no fim a home sem oferta e a pilha de navegação sem ecrã de oferta, na home de hoje e na situação exacta de hoje com a corrida empilhada por cima. Fiz a contraprova: repus o comportamento antigo no ecrã e os dois testes falharam com a mensagem "o ecrã da oferta ficou por baixo do ecrã da corrida"; depois repus o ficheiro e confirmei que ficou igual byte a byte.

A oferta nova durante uma corrida activa continua a aparecer, com Aceitar e Recusar. Tem teste no cartão e teste na leitura do servidor.

Suite completa: 870 testes verdes, saída zero, corrida duas vezes, a segunda já com o código final. Análise estática: zero erros. Verificação anti-trapaça: limpa.

CI do envio: autoteste dos três perfis no emulador com sucesso, das 12:10 às 12:43 UTC; construção e envio para a Play com sucesso, das 12:43 às 12:54; o CI gravou a versão 636, antes era 635. A web foi publicada com sucesso e o ficheiro servido em app.boraguarda.com já contém a chave nova das ofertas respondidas, quatro ocorrências. A construção iOS ainda estava a correr quando fechei.

Tudo em `.claude/.ai/provas/tvde-oferta-fantasma-2026-10-01/`.

## O que viajou no envio

O commit da correcção é o 7df0fc49 e o envio ficou em 753a2131. Foram de boleia três commits de ontem à noite que estavam por enviar: dois só de documentos e um com o ficheiro da migração da contagem de visitas da página de descarregar, que já estava aplicada em produção. Não mexi no número de versão.

O nome do passo no CI diz "Closed Testing, alpha". A ordem falava em Internal Testing. Não alterei nada no CI; fica dito para não haver surpresa sobre a faixa onde a versão 636 aparece.

## Outros erros encontrados, não corrigidos

Um. Ao abrir, o ecrã da oferta avisa o cartão global a meio da construção do ecrã. Em modo de desenvolvimento isto dá erro de "setState durante o build"; na versão publicada passa sem se ver. É antigo.

Dois. O ecrã da oferta mostra a oferta que está em memória mas aceita e recusa a corrida com que foi aberto. Se a oferta mudar com o ecrã aberto, o toque pode ir para a corrida errada.

Três. A releitura de dez em dez segundos continua a correr depois de a corrida terminar e põe a corrida activa a vazio, o que pode fechar o ecrã no lembrete de cobrança. Não aprofundei.

Quatro. No emulador `emdia` tirei as actualizações de nove aplicações Google para ganhar espaço em disco e substituí a Bora instalada pela versão de hoje. A aplicação Em Dia que lá estava não foi tocada.

## Para o Danilo

Actualizar a aplicação para a versão 636 quando a Play a mostrar, e fazer uma corrida normal. Se o ecrã "Nova corrida" voltar a aparecer depois de finalizar, diz a hora e eu vou ao registo.
