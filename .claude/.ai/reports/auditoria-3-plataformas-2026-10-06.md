# Auditoria das três plataformas — 06/10 (corrida a 07/10/2026)

Missão auditoria-3-plataformas-2026-10-06, pela página prompt-auditoria-3-plataformas-2026-10-06. Porta Claude Code no PC do Danilo. Motor: a página pedia Fable com Opus de reserva; esta sessão corre em Opus e não consegue trocar o próprio motor, por isso o chefe foi Opus e a investigação só de leitura foi para agentes. Trabalho numa pasta separada (C:\BoraLocal\_auditoria-3p, a partir do remoto), porque a pasta principal estava atrás e tinha trabalho por gravar de outras sessões.

## Acessos usados

Supabase pelo MCP (projeto ojykpzwqrtusfeakzrna): leituras, provas em transacção desfeita e uma migração. GitHub pela credencial do Git (fechar o pedido #1 e ler o CI). Cloudflare pelo token das Pages do bora-site (definição de cache da zona boraguarda.com). Nenhuma conta nova, nenhuma senha usada.

## O que NÃO foi feito (primeiro)

Não se mexeu em dinheiro, despacho, preços, ganhos nem RLS. Ficou só proposto no Córtex (proposta prop-3b74506b): o valor do vale ida-e-volta no aviso de paragem (notify-tvde-driver, stop_added); o plano TVDE com preço pela rota; o dispatch_gps_fresh_seconds_entregas que está a 172800 desde 05/10 e devia voltar a 900; o link partilhado de loja que abre sem configurar o carrinho (mexe no preço que se calcula no cliente); e a protecção do log_admin_action, que NÃO pode levar a verificação de admin lá dentro porque cerca de cem funções a chamam, incluindo do cliente e do parceiro.

Não se fez a prova ao vivo em telemóvel ou emulador: havia motoristas reais ligados e nada disto se prova sem pedidos reais. Não se ligou a autorização "Time Sensitive Notifications" do iPhone (precisa do portal da Apple e de perfil novo; pôr a chave sem isso parte o build do iPhone). Não se acertou o app_latest_version_code_ios (precisa de saber que build está na loja e decidir quando avisar). O som no Safari do painel do parceiro e da oferta TVDE ficou por fazer: precisa de um leitor de áudio partilhado e desbloqueado no primeiro toque, não de um remendo. Avisos na web para cliente e parceiro (botão "Ativar notificações") é funcionalidade nova, ficou registada. O ecrã do chat da limpeza ainda lê o store dentro do dispose (o mesmo defeito que se corrigiu no botão a 03/10) — visto, reportado, não corrigido por estar fora da lista.

Achado do verificador que não se corrigiu, por ser antigo e mais fundo: o geolocator guarda um único fluxo de GPS por app; enquanto a home do motorista está a ouvir, o ecrã da corrida recebe esse mesmo fluxo com as definições da home (15 s, sem as suas 3 m / 700 ms). O conserto certo é o ecrã da corrida voltar a subscrever depois de a home largar o GPS, provado com um aparelho. Fica na continuação.

## Linha de base e suite

Antes de mexer: suite completa na produção 383708b4, 1037 testes, todos verdes. Depois dos consertos: 1055 testes, todos verdes (mais 18). Análise sem erros; os dois avisos que aparecem no mapa da entrega são antigos. Anti-trapaça limpo sobre os 13 commits (mais 21 casos de teste). Cada conserto tem teste que falha com o código antigo (provado repondo o ficheiro antigo).

## Bloco 1 — o CI de 05/10

Os três commits que falharam a 05/10 (4f434d3a, aedb956b, 744fe903) estão dentro da produção, e o último publicado antes desta missão (4a6dc611, versão 655) ficou verde nas três: Android 505, iPhone 172, web 199. Nada desse dia ficou só numa plataforma.

## Bloco 2 — erros reais dos telemóveis (debug_crash_logs)

Painel da corrida que rebentava no fim da corrida. "Null check operator" ao montar a DraggableScrollableNotification, 27 vezes entre as versões 635 e 654 (desde 01/10, dia a seguir a entrar o botão SOS). Causa: no ecrã da corrida o SOS só existe enquanto a corrida não acabou e estava, na mesma pilha, antes do painel arrastável, os dois sem chave; quando o SOS saía, o Flutter encaixava o painel no lugar dele, montava um painel novo com o mesmo controlador e o velho, ao sair, desligava-o — a actualização seguinte rebentava e o painel ficava cinzento. Conserto: chave no painel e no SOS (e0d01173). Prova: réplica da pilha que rebenta sem chave e mantém o mesmo painel com chave, e guarda no ecrã real. Confirmado pelo verificador no código do Flutter 3.41.2 e 3.47.2.

Câmara do mapa mexida depois de o mapa sair (versão 644): com a corrida vazia o ecrã troca o mapa por um ecrã vazio, mas a seta e o GPS continuavam a mexer a câmara do mapa velho. Conserto: larga o controlador e pára a seta nesse ramo, e apanha o erro de um controlador morto (570d68cf).

GPS com serviço em primeiro plano recusado pelo Android em fundo (telemóvel do Danilo, Android 16, quatro vezes de 26/09 a 03/10, sempre segundos depois de terminar uma corrida). O ecrã da corrida devolvia o GPS à home, que o religava com o serviço com a app em fundo e a permissão só "enquanto se usa"; o Android recusa e o Flutter só regista o erro, e o GPS que alimenta o despacho ficava calado até reabrir a app. Conserto: regra única (com "sempre" pode sempre; com "enquanto se usa" só com a app à frente), e quem ligou o GPS sem serviço por estar em fundo religa-o ao voltar à frente — home TVDE, ecrã da corrida, home do estafeta e mapa da entrega (58032b57, 989312e0). O verificador apanhou que dois religares seguidos podiam deixar uma subscrição de GPS órfã; ficou protegido com um contador de gerações e a verificação de ecrã montado (40c76977).

"RenderFlex overflowed" de 77 e 48 pixels: só em emulador e simulador do CI na versão 649, nenhum desde a 650 — já resolvido. "Null check" no iPhone (1.0.6, build 148): era o dispose do botão do chat da limpeza, corrigido a 03/10.

## Bloco 3 — ramos fora da produção e pedido #1

Pedido #1 fechado sem juntar, com nota: as três partes (aviso do admin só com dados, canais em falta, faixa de produção no CI) já estão na produção, confirmadas por mim no código. GitHub respondeu 201 ao comentário e 200 ao fecho; lido de volta: fechado, sem merge. Ramos: nenhum conserto de código provado está em falta; o que falta é dinheiro (foi para proposta) ou opcional (rascunho local da ida ao mercado, arranque mais rápido da web). Os doze ramos analise-* e o ramo local empresa-agentes não têm nada para a produção. Relatório completo em provas/auditoria-3-plataformas-2026-10-06/ramos-e-pr1.md.

## Bloco 4 — continuações do inbox

Arquivadas (a0a69eda): fable-13-09, noite-fecho-2026-09-24, tvde-oferta-sobreposta-2026-09-21 e a ordem do iPhone automático. A ios-portugal também está resolvida (a app está na App Store portuguesa, versão 1.0.11) mas ficou no sítio porque outra sessão tem alterações por gravar nela. Continuam com coisas por fazer: hora-lisboa (horários especiais e outros), missao-noite-2026-10-03 (o OAuth do Gmail tem de ser publicado ATÉ 10/10 — criei a ordem ordem-20261007111613-ede9), contas-claras e ronda-dinheiro-despacho (restos de dinheiro). Relatório completo em provas/auditoria-3-plataformas-2026-10-06/continuacoes.md.

## Bloco 5 — paridade Android, iPhone e web

Aviso ao parceiro quando o admin força a loja aberta ou fechada, ou muda o horário: nunca chegava. A função do servidor usava "extensions.net.http_post" (o Postgres lê isso como outra base de dados; o erro era engolido e não saía pedido nenhum) e a chave anónima (o notify-partner responde 403). Passou a usar o endereço e a chave de serviço do cofre. Provado em transacção desfeita antes de aplicar: antiga 0 pedidos, nova 1 pedido com papel de serviço. Aplicada em produção como migração 20261007105848 e guardada no repositório (0f27c5a8). O verificador apanhou a outra metade: no Android o aviso é só de dados e a app não conhecia este tipo; passou a desenhá-lo como os outros avisos persistentes do parceiro (91719b66). No iPhone e na web já aparecia.

Web: cada publicação apagava a subscrição de avisos de quem abrisse a app a seguir, porque o index.html desregistava todos os service workers, incluindo o do Firebase. Passou a deixar o do Firebase (cb4e77fa). Prova: o script verdadeiro corrido em Node com dois service workers falsos — antes saíam os dois, agora só o do Flutter.

Web, domínio principal: o app.boraguarda.com servia o código da app com 4 horas de cache no navegador (definição da zona Cloudflare), por isso quem voltava à app nesse tempo corria a versão velha. Mudei a zona para respeitar os cabeçalhos da origem. Antes: max-age=14400. Depois: no-cache no main.dart.js, no flutter_bootstrap.js e na página; o site boraguarda.com continua a responder 200. Reverte-se com o mesmo pedido e o valor 14400. Prova em provas/auditoria-3-plataformas-2026-10-06/cache-boraguarda.txt.

Android: o botão de e-mail do suporte não fazia nada (o Android 11 ou superior diz "não" ao mailto sem declaração no manifesto). Passou a abrir directo e, sem app de e-mail, mostra o endereço (376cea28).

iPhone: o GPS da corrida TVDE e do mapa da entrega usava definições simples, que param com a app em fundo. Passou a pedir localização em fundo, como o GPS "online" já fazia (989312e0). Nota honesta do verificador: na corrida TVDE, enquanto a home está a ouvir, o fluxo é o da home (que no iPhone já tinha fundo); o ganho real é no mapa da entrega e quando a corrida é a dona do GPS.

Verificado e certo: chaves do Info.plist, chave do Maps no iPhone (o CI escreve-a e pára se faltar), cache do bora-app-web.pages.dev.

## Painel admin

Nenhum conserto criou definição nova nem estado novo. O painel não foi tocado.

## Verificador independente

Um verificador de contexto limpo tentou derrubar os consertos: confirmou sete e apanhou um erro (o aviso do parceiro não aparecia no Android) e um risco (GPS órfão), os dois corrigidos antes do push, e o achado antigo do fluxo de GPS partilhado, que ficou para a continuação.

## Publicação

Empurrado para o ramo de produção (898a7b4f para 8bf8ccda, 13 commits, só lib, test, web, a migração e documentos; nada de outras sessões viajou). O CI subiu o número sozinho; não se mexeu no pubspec. As três plataformas acabaram verdes.

Play Store: CI Android número 506, verde (autoteste dos 3 perfis no emulador verde, envio para teste interno, fechado e produção). versionCode 656, lido de volta no servidor (platform_settings.app_latest_version_code = 656, era 655) e commit do CI "bump versionCode to 656".

Apple: CI iPhone número 173, verde. Versão 1.0.13, build 173. O registo diz "UPLOAD SUCCEEDED", a Apple deu a build como VALID, a versão 1.0.13 foi criada, ligada à build e submetida; estado lido de volta "WAITING_FOR_REVIEW", lançamento automático depois da aprovação. No mesmo registo, a 1.0.12 de ontem (com o conserto do cartão preso) aparece já "READY_FOR_SALE".

Web: CI web número 200, verde. bora-app-web.pages.dev e app.boraguarda.com respondem 200 com o versao.json do commit 8bf8ccda (corrida 200), o index leva o mesmo commit e a regra nova do service worker, e o código sai com no-cache nos dois domínios.

## Para o Danilo

Ligar "Time Sensitive Notifications" no App ID da Apple (para as ofertas tocarem no iPhone em modo Foco) — preparado na continuação, precisa do portal. Decidir quando se liga o aviso de "versão nova" no iPhone (app_latest_version_code_ios está a 0). As propostas de dinheiro estão no Córtex (prop-3b74506b). O OAuth do Gmail tem de ser publicado até 10/10 (ordem ordem-20261007111613-ede9).

## Registos

e2e_log 3063 a 3095 e o passo fim. Continuação em .claude/.ai/inbox/CONTINUAR-auditoria-3-plataformas-2026-10-06.md. Provas em .claude/.ai/provas/auditoria-3-plataformas-2026-10-06/.
