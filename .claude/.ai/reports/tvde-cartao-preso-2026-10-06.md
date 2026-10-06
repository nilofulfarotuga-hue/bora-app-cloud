# Cartão "Nova corrida" preso depois de aceitar — 06/10/2026

Missão tvde-cartao-preso-apos-aceitar-2026-10-06. Motor Opus, porta Claude Code no PC do Danilo, ramo autonomous-night-2026-04-29. Só app (Flutter). Não se tocou em servidor, despacho, preços nem ganhos.

## O que aconteceu

Corrida 3835a143, a volta do pacote do cliente Martim Cruz, às 18:33 de Lisboa, versão 1.0.4+651. A oferta chegou às 17:33:51 UTC com 40 segundos de prazo. O Danilo aceitou às 17:33:56 e o servidor ficou certo logo ali: motorista a caminho, sem oferta pendente. O ecrã da corrida abriu certo por baixo. Mas o cartão sobreposto ficou por cima mais de um minuto a dizer "Nova corrida — agora", "0s", com o Aceitar a rodar.

## O que os registos do servidor mostraram

O aceite veio do telemóvel do Danilo, uma só vez, pela app (não pelo isolate de segundo plano), antes de a app voltar ao primeiro plano: foi o botão Aceitar da notificação, com a app em segundo plano. A oferta tinha entrado 2 segundos antes pela releitura de 10 em 10 segundos da home, também com a app em segundo plano, e a home empilhou logo o ecrã "Nova corrida" (sem frames, nada se desenhou).

A prova mais importante: depois do aceite, a releitura de 10 em 10 segundos da home continuou a correr o minuto todo. Essa releitura só corre quando o store NÃO tem oferta. Portanto o store estava certo: sem oferta e com a corrida activa. Quem não sabia era o cartão.

## A causa exacta

O ecrã "Nova corrida" avisa o cartão global, no momento em que nasce, de que está aberto (para o cartão não a mostrar duas vezes). Esse aviso acontecia a meio do desenho do ecrã, depois de o cartão global, que está mais acima, já se ter desenhado nesse mesmo frame.

Em modo de teste isso dá um erro ("setState chamado durante o build") — a missão de 01/10 viu-o e deixou-o anotado como defeito antigo. Na app publicada não dá erro: o Flutter salta o cartão global nesse frame e deixa-o marcado como "por redesenhar" para sempre. A partir daí todos os avisos do store eram ignorados. Confirmei isto no código do próprio Flutter (framework.dart, a função que percorre a lista de redesenhos volta atrás só até ao primeiro elemento limpo, e a função que marca para redesenho sai logo se o elemento já estiver marcado).

No caso do Danilo, o primeiro frame depois de a app voltar à frente apanhou o aceite a meio: o cartão desenhou-se com "a aceitar" e sem corrida activa ("agora"), e congelou assim. O relógio do próprio cartão continuou a contar até "0s" e, como o "a aceitar" nunca lhe foi tirado, nunca se fechou.

## O que mudou

Um: o cartão global nunca se redesenha a meio de um desenho. Se o aviso chega a meio, o redesenho fica para o fim desse frame. É a correcção da raiz.

Dois: o ecrã da corrida diz ao cartão global qual corrida está a mostrar, e o cartão nunca desenha como oferta essa corrida, diga o store o que disser.

Três: rede de segurança dentro do próprio cartão. Com o prazo a zero e "a aceitar" há 4 segundos, o cartão pergunta ao servidor de quem é a corrida, de 4 em 4 segundos. Se é dele, fecha em silêncio e relê o estado. Se aos 16 segundos ainda não é dele (passa folgado os 12 segundos máximos do aceite), mostra o aviso honesto e fecha. E quando se despede, o cartão esconde-se sozinho, mesmo que quem o pôs no ecrã não o tire. Nunca fica preso com "0s".

Quatro: quando o realtime traz a corrida da oferta e ela já não está à procura de motorista, ou já é dele, a oferta sai do store na hora. Antes, uma corrida dele já terminada deixava a oferta em memória.

Os três caminhos do aceite (ecrã inteiro, cartão e botão da notificação) já punham a corrida no mesmo store e tiravam a oferta; ficou provado por testes.

Ficheiros: lib/widgets/tvde/tvde_offer_overlay_host.dart, lib/stores/tvde_driver_store.dart, lib/screens/driver/tvde/tvde_ride_active_screen.dart e o teste novo test/tvde_cartao_preso_test.dart.

## Provas

O teste novo tem 16 casos e passa todo. Com o comportamento antigo (correcções desligadas à mão e repostas depois), falham 9, incluindo o erro "setState chamado durante o build", que é a causa. Os outros 7 passam também com o código antigo e é isso que se espera: provam que o store já fazia a parte dele.

Suite TVDE: 354 testes verdes, incluindo os da oferta fantasma de 01/10, os da sobreposição de 20/09, os do "é dele" de 04/10 e as fotos de referência do cartão.

Suite completa: 1017 verdes e 1 vermelho, uma foto de referência do painel admin que falhou por o Windows ter o ficheiro aberto (erro 1224, conhecido); corrida sozinha passa 3 de 3. Não tem a ver com esta mudança.

Análise do projeto: 0 erros. Anti-trapaça: limpo, mais 21 casos de teste.

Painel admin: nada novo a criar (não há definição nova). O ecrã das corridas TVDE lê o estado directamente do servidor, que esteve sempre certo, por isso continua a mostrar a corrida como aceite.

Registos: e2e_log 3045, 3046 e 3047.

## O que não se fez e porquê

A prova ao vivo no emulador não se fez. Havia dois motoristas reais ligados (o próprio Danilo, a meio de corridas, e o Valdemir), e um pedido de teste seria oferecido a eles. A regra é não fazer pedidos sintéticos com motoristas reais ligados.

## Outros erros vistos (reportados, não corrigidos)

O cartão de oferta de RESERVA tem a mesma forma de ficar à espera ("a aceitar") sem rede de segurança própria. Com a raiz corrigida já não congela, mas não lhe pus a pergunta ao servidor dos 4 segundos, para ficar dentro do pedido.

O envio do iPhone do push anterior desta tarde (build-ios 170) ficou vermelho porque a Apple não acabou de processar a build em 40 minutos. É do lado da Apple, não do código.

## Verificador independente

Um verificador com contexto limpo tentou derrubar a correcção. Confirmou a causa no código do Flutter e que nada tocou em zonas protegidas. Apanhou um erro e dois riscos, todos corrigidos antes do push, cada um com teste que falha na versão anterior: o realtime tirava a oferta sem avisar o ecrã (o cartão ficava com o Aceitar vivo até ao próximo aviso); o cartão, ao despedir-se, limpava qualquer oferta do store e podia apagar uma oferta nova; e a desistência aos 16 segundos podia dizer "foi para outro" numa corrida dele com a rede lenta — agora fecha em silêncio.

## Publicação

Commits no ramo de produção: b7e529be (correcção) e 0fc4b0da (achados do verificador). Subiram sozinhos, sem levar trabalho de outras sessões (feito numa pasta de trabalho separada a partir do remoto). O CI subiu o número da versão sozinho; não se mexeu no pubspec.

Play Store: CI Android número 504, verde (autoteste de 3 perfis no emulador verde, envio para teste interno, fechado e produção). versionCode 654, lido de volta no servidor (platform_settings.app_latest_version_code = 654) e commit do CI "bump versionCode to 654".

Apple: CI iPhone número 171, verde. Versão 1.0.12, build 171. O registo diz "UPLOAD SUCCEEDED", a Apple deu a build como VALID, a versão 1.0.12 foi criada, ligada à build e submetida para revisão; o estado lido de volta é "WAITING_FOR_REVIEW", com lançamento automático depois da aprovação. Já está no TestFlight.

Web: CI web número 198, verde. O bora-app-web.pages.dev responde 200 e o versao.json diz commit 0fc4b0da, corrida 198; o index.html leva o mesmo commit.

## O que falta

A revisão da Apple (horas a um dia) — sai sozinha quando aprovarem. A prova ao vivo num telemóvel, na próxima corrida real do Danilo, já com a versão 654 (Android) ou 1.0.12 (iPhone).

Nota de arrumação: o ramo local da pasta do PC continua com os 4 commits de documentos de outra sessão por subir e com os meus dois commits (bcb474f9 e 13aed4ff, iguais aos que subiram com outro número). Quando essa sessão juntar com o remoto, entra limpo.
