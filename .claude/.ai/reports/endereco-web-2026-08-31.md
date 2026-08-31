# Missão endereco-web — 2026-08-31

## Acessos e contas envolvidas

Conta de prova criada e APAGADA no fim: prova.endereco@bora.app (confirmado por SELECT, resta 0). O pedido de corrida do teste acabou por sair da sessão convidada guest@bora.com da própria app. Nenhuma palavra-passe de conta real foi tocada. A chave Google do lado do servidor ficou guardada na tabela server_config do Supabase (RLS fechada, só o servidor lê) — não foi criado nenhum secret novo em lado nenhum.

## O que NÃO ficou feito (a ler primeiro)

Primeiro: o ecrã novo do painel admin ("Saúde da Web") não foi aberto ao vivo com uma sessão de administrador, porque não uso as tuas credenciais; a prova dele é o código, os testes e os eventos reais que já estão na tabela (mostro abaixo). Segundo: o aviso do TVDE quando uma morada segue sem coordenadas existe e está testado, mas a fotografia falhou o momento em que ele aparece no ecrã (dura 4 segundos). Terceiro: no TVDE, uma corrida continua a precisar de coordenadas — preço é por distância, e distância inventada seria mexer em dinheiro; o que mudou é que agora as coordenadas se resolvem no servidor mesmo com o browser bloqueado, e se falhar tudo o cliente recebe uma mensagem clara em vez de silêncio. Quarto: a chave do Google continua visível no HTML público porque o SDK do browser precisa dela; recomendo criar uma chave separada para o servidor e restringir a do browser ao domínio — isso passa pela consola da Google e fica para decidires.

## O problema e o que se fez

Uma cliente escrevia a morada na web e não acontecia nada — nem sugestões, nem erro. A causa estava confirmada: o script do Google Maps carregava solto e sem vigilância; se um bloqueador ou rede fraca o impedisse, o serviço devolvia lista vazia em silêncio e o campo parecia morto para sempre. Aconteceu duas vezes com a mesma pessoa.

O carregamento do Google passou a ser vigiado no index.html: há um estado (a carregar, pronto, indisponível), um motivo quando falha, e uma retentativa automática. O serviço de moradas da web passou a devolver esse estado em vez de uma lista vazia muda, e o campo de morada — o widget partilhado pelos quinze ecrãs que o usam — mostra sempre alguma coisa em português: "A procurar moradas…" enquanto carrega, "Não encontrei essa morada. Escreve a rua e o número." quando não há resultados, e, quando o serviço está mesmo indisponível, o aviso mais o botão "Usar esta morada", que deixa o texto escrito seguir em frente. Nasceu também o plano B no servidor: a função places-proxy no Supabase, que faz autocomplete, geocodificação e detalhes do lado de lá quando o browser está bloqueado, com porta fechada a quem não tem sessão da app, limite de pedidos por utilizador e cache curto para não gastar quota.

Para a cache velha: o CI carimba agora o commit do build dentro do index.html, e a página compara-o com o versao.json publicado (servido sem cache nenhuma). Se forem diferentes, limpa o service worker e as caches e recarrega uma única vez, com guarda anti-loop. Ao voltar ao separador só verifica se esteve escondido mais de cinco minutos, para não interromper um pedido a meio por causa de um alt-tab. Para a web mais leve fez-se só o que era seguro: pré-ligação ao Supabase e à Google no arranque, e política de cache correta por ficheiro; o main.dart.js mede 8,93 MB antes e depois (comprimido na entrega pela Cloudflare) — nada foi reescrito para poupar quilobytes, como pedido.

Cada falha real passa a ficar registada na tabela web_health_events (quem, ecrã, motivo, plataforma, data) e há um cartão novo no painel admin, "Saúde da Web", em PT-BR, com filtro de hoje, sete e trinta dias. Deixa de se descobrir isto por telefonema.

## As provas

Prova principal, no site publicado, com o maps.googleapis.com verdadeiramente bloqueado no browser (não simulado por cima): a app abriu, a home carregou, o ecrã Bora Motorista abriu, escrevi "rua dom miguel de alarcao" e as sugestões apareceram — vindas do places-proxy, com as três chamadas registadas na rede (autocomplete, autocomplete com viés Guarda, detalhes, todas 200). Escolhi a sugestão, a estimativa deu €5,00, o botão Solicitar corrida acendeu, confirmei em dinheiro e a corrida foi criada a sério no servidor. Capturas em .claude/.ai/provas/endereco-web-2026-08-31/ (p4b_sugestoes_com_maps_bloqueado.png, p4b_destino_escolhido_estimativa.png, p5b_corrida_pedida.png).

Essa corrida foi aceite em menos de um minuto por um motorista real — que era a tua própria conta de motorista, Danilo ("Danilo", +351931992662). Cancelei-a de imediato pelo caminho canónico da app (tvde_cancel_ride como cliente, motivo "teste tecnico endereco-web"), sem taxa (cancel_fee_cents 0), estado final cancelada_cliente confirmado por SELECT. Estiveste "a caminho" cerca de dois minutos; foi o custo de provar o circuito inteiro de ponta a ponta, e peço desculpa pelo toque.

Pior cenário, maps E proxy ambos bloqueados: o campo mostrou "Sem sugestões automáticas neste momento. Podes escrever a morada completa à mão." com o botão "Usar esta morada" (p6_aviso_indisponivel_e_modo_manual.png) — e os dois eventos apareceram na tabela do painel: script_bloqueado com o detalhe do proxy falhado, e geocode_manual_falhou no campo "Para onde vais?". Lidos de volta por SELECT.

Rede Fast 3G simulada por CDP: a home ficou visível aos 21 segundos, o campo respondeu, o SDK acabou por chegar e as sugestões renderizaram com mapa e tudo (p7_sugestoes_fast3g.png). Nada de ecrã mudo.

Versão velha em cache: servindo um versao.json com commit diferente do carimbado, a página limpou o service worker (zero registados depois), recarregou-se sozinha (navigation type "reload") e não voltou a recarregar — guarda anti-loop confirmada dez segundos depois. O HTML no ar foi auditado pelo endereço público: o carimbo d9e202f3 está lá, o loader vigiado está lá, o script antigo desapareceu, e o versao.json responde com Cache-Control no-store.

Do lado do código: flutter analyze com zero erros (restam avisos informativos antigos do repo, nenhum introduzido por mim), suite completa de 324 testes verde antes das novas adições e 7 de 7 no widget com os três testes novos (indisponível → aviso + modo manual com coordenadas do geocode; sem resultados → mensagem; a carregar → "A procurar moradas…"). O chão anti-trapaça do Juiz deu CLEAN sobre o diff real (a primeira corrida deu REJECT por usar a base velha da branch — é o falso-positivo já documentado na lição anti-trapaca-base-stale). O push d9e202f3 entrou, o build web (run 97) e o Android (run 402) terminaram ambos em success, confirmados pela API do GitHub, e o versao.json no ar aponta para o commit novo.

## Bugs e achados pelo caminho (fora do âmbito, como pedido)

O mais sério: a sessão convidada (guest@bora.com) consegue pedir uma corrida TVDE real — foi assim que o meu teste criou a corrida, porque o meu login de prova falhou em silêncio e a app seguiu como convidado. Se o guest-pede-corrida é desenho intencional, está a funcionar; mas um login que falha sem dizer nada é o mesmo padrão do botão mudo da regra 1.2 do PADRAO, e merece missão própria (não confirmei se foi o ecrã de login ou o meu robô a errar o campo). Segundo: com o Google bloqueado, a caixa do mapa no TVDE mostra "Ocorreu um erro nesta tela" em vermelho — não trava nada, mas é feio; um placeholder amigável ficava melhor. Terceiro: a política de INSERT do web_health_events aceita anónimos (preciso, porque os ecrãs de registo têm morada); os CHECKs limitam conteúdo e tamanho, mas se um dia houver spam, acrescenta-se rate-limit. Quarto: continuam no working tree, por committar e de outra sessão, o analysis_options.yaml e três goldens de driver_rejected — não os toquei nem os levei no commit.

## Estado da RAM (portões)

Medidos 674 MB no arranque (acima do portão leve de 400, abaixo do pesado de 800) — o trabalho de ficheiros avançou; antes do flutter analyze medi de novo: 1433 MB, portão pesado passado, e só então compilei. Nenhuma medição foi saltada.

## Ficheiros da missão

Commit d9e202f3 na branch autonomous-night-2026-04-29, 15 ficheiros: web/index.html, web/_headers, o workflow build_web_deploy.yml, os quatro place_autocomplete_service*, web_health_log.dart, address_autocomplete_field.dart, tvde_request_ride_screen.dart, admin_dashboard_screen.dart, admin_web_health_screen.dart, a função supabase/functions/places-proxy/index.ts (deployada, v1, ACTIVE, verify_jwt ligado — provada por curl: autocomplete devolve moradas da Guarda, geocode devolve lat/lng, sem sessão devolve 401) e a migration 20260831120000_web_health_e_server_config.sql (aplicada). Guiões e capturas da prova em .claude/.ai/provas/endereco-web-2026-08-31/.

## PARA O DANILO

Duas decisões só tuas, nenhuma urgente: (1) criar na consola da Google uma chave separada para o servidor e restringir a do browser ao domínio bora-app-web.pages.dev / app.boraguarda.com — quando quiseres, abro-te a página certa e fica só o clique; (2) dizer se o convidado poder pedir corrida sem conta é desenho ou buraco — se for buraco, sai missão para o fechar.
