# Fechar o Bora Motorista — 04/11/2026

Missão `fechar-bora-motorista-2026-11-04` (e2e_log, fluxo com o mesmo nome).

## Para o Danilo

Fiz isto. O Bora Motorista desapareceu das apps e do site. Pus um interruptor só, que se chama
"tvde_app_visivel" e já estava desligado no servidor desde as 04:50. A app lê esse interruptor ao
abrir e sempre que volta ao ecrã; enquanto não o consegue ler, esconde tudo. Com ele desligado, o
cliente já não vê o quadrado "Bora Motorista" nem o "Nova categoria", a pesquisa por motorista não
mostra nada, as corridas saíram das Reservas, os avisos de corridas saíram do sininho, o assistente
já não mostra o botão do motorista, e um link antigo ou uma notificação antiga de corrida não abre
nada. Do lado de quem trabalha, os quatro motoristas de carro de passageiros entram agora na home
normal de estafeta (eles já faziam entregas), as ofertas de corrida não aparecem, e o cadastro já
não oferece "Carro — Passageiros" nem o papel "Corridas de passageiros". Não apaguei código nenhum:
está tudo guardado por trás do interruptor, e no dia em que a licença do IMT sair basta ligá-lo.

No painel, a secção passou a chamar-se "Arquivo — Bora Motorista (fechado)". O primeiro ecrã dela é
o interruptor, com o estado e quantas corridas estão guardadas. Os outros ecrãs (corridas,
pagamentos, recibos, acertos, dívidas, motoristas, pedidos de acesso) continuam a abrir para
consulta. Enquanto estiver fechado, o botão de aprovar pedidos de acesso e o de criar corrida de
balcão ficam escondidos, porque esses reabririam o serviço.

No site boraguarda.com tirei a página do Bora Motorista, a cena das viagens do filme da página
inicial, os cartões "Viagens", a foto do ecrã do Bora Motorista (pus a dos Favores), os links
"Viagens" do menu e do rodapé, e os textos de motorista TVDE na página de estafetas e nas perguntas
frequentes. Quem abrir o link antigo /viagens vai parar à página inicial. Já está publicado e
conferido no ar.

No assistente de suporte desliguei as três instruções de corridas (reservas de corrida, ganhos por
corrida e passageiro que não aparece), com cópia guardada.

Não mexi em dinheiro nem em dados: as 339 corridas, pagamentos, vales, planos, acertos e saldos
estão iguais (a última mudança numa corrida é de 02/11, antes de hoje). O código foi enviado para o
servidor e as três publicações acabaram bem: a web está no ar com a versão nova (conferi-a no
navegador), o Android saiu como versão 711 para a Play Store (teste fechado) e o iPhone foi
enviado para a App Store (TestFlight).

Falta isto. O assistente do cliente e o robô de suporte ainda têm o "Bora Motorista" escrito nas
instruções que vivem no servidor deles; desliguei o que estava na base, mas essa parte só muda
editando e publicando as duas funções, e não o fiz hoje para não arriscar partir o suporte. Também
não consegui fazer a prova no emulador Android, porque o PC tinha cerca de 1 GB livre e o emulador
precisa de 3 GB; a prova foi feita na versão web, que é o mesmo código, e nos testes automáticos.

Erros que encontrei pelo caminho, sem corrigir calado: a página /apagar-conta do site estava pronta
desde 02/11 mas nunca tinha sido publicada, e foi junto com esta publicação. Um motorista tem
corridas desta semana (02/11) no extrato de ganhos; ficaram lá porque são dinheiro dele e entram no
acerto como estão. Na carteira de clientes há três linhas antigas que falam de corrida; também são
dinheiro e ficaram. Os textos legais do site (privacidade e termos) ainda dizem "estafetas e
motoristas" de forma genérica, e o aviso de localização da app ainda diz "entregas e corridas";
deixei-os porque são textos legais revistos.

Próximo passo: uma missão pequena para tirar o Bora Motorista das instruções do assistente e do
robô de suporte, e, se quiseres, outra para pôr todos os ecrãs do arquivo do painel só de leitura
(hoje só os dois botões perigosos estão travados).

### PARA O DANILO (decisões só tuas)

1. Tirar "motoristas" dos termos e da privacidade do site (é texto legal: talvez com a advogada).
2. Pôr TODOS os ecrãs do arquivo do painel só de leitura, ou deixar os estornos e cancelamentos
   à mão para algum caso do contabilista.

## Provas

- Juiz anti-trapaça: `CLEAN` (base origin/autonomous-night-2026-04-29, 33 ficheiros, +14 casos).
- `flutter analyze` nos ficheiros mudados: nenhum aviso novo (os que aparecem já existiam).
- `flutter test` completo: 263 ficheiros, 2879 casos, 0 falhas (JSON lido caso a caso).
- Teste novo `test/bora_motorista_fechado_test.dart` + casos "fechado" em
  `client_reservations_screen_test.dart` e `tvde_oferta_sobreposta_test.dart`.
- Envio: `faf0b8ac..ee71173f` no ramo autonomous-night-2026-04-29 (só o commit da missão).
- Web no ar: `main.dart.js` com `tvde_app_visivel`; Playwright como visitante: entrada,
  home e pesquisa (motorista, tvde, corrida) em `capturas/fechar-bora-motorista-2026-11-04/`.
- Site: deploy Cloudflare `da8f53b2`; `/`, `/estafetas`, `/faq`, `/entregas`, `/mais`,
  `/apagar-conta`, `/sitemap.xml` com 0 menções; `/viagens` e `/viagens.html` → 301 para `/`.
  Commit `f89945e` no ramo `fechar-bora-motorista-2026-11-04` do bora-site (enviado ao GitHub).
- Servidor: `select count(*) from tvde_rides` = 339; `users.tvde_access` = 0;
  `tvde_app_visivel` = false; skills desligadas 3, cópia `bkp_support_skills_tvde_20261104` = 3.
- Lojas: texto público da App Store (pt, 1.0.36) e da Play Store (pt_PT) com 0 menções de
  TVDE/motorista/corrida/viagem — não estão no repo (sem fastlane/metadata).
- CI do commit ee71173f, todos `success`: web (run 41786626475, publicado em app.boraguarda.com);
  Android (run 41786626442: autoteste 3 perfis + AAB enviado à Play Store, teste fechado alpha;
  o CI subiu o versionCode para 711, commit fff10bbc); iPhone (run 41786626437: simulador +
  IPA assinado enviado ao App Store Connect/TestFlight); olho-golden (41786626441).

## Levantamento — onde se via o Bora Motorista

Cliente: ladrilhos "Bora Motorista" e "Nova categoria" (`client_home_screen.dart`); ladrilho
"Enviar Encomenda" pelo motor TVDE (`tvde_encomendas_enabled`); pesquisa (`global_search_screen.dart`,
dica, chip e atalho "motorista"); faixas/ligações `motorista`/`tvde` (`utils/home_destino.dart`);
botão `abrir_tvde` do assistente (`assistant_cards.dart`, `assistant_chat_screen.dart`); corridas
marcadas/feitas no separador Reservas e atalho "Motorista" (`client_reservations_screen.dart`);
retoma da corrida ao abrir a app (`retoma_corrida_tvde.dart`) e depois de pagar na web
(`retoma_pagamento_web.dart`); avisos `tvde_*`/`ride_*` no sininho (`in_app_notifications_service.dart`);
textos "corridas" no perfil e na entrada (`profile_screen.dart`, `role_screen.dart`). Todos os ecrãs
de `screens/client/tvde/` (pedir, acompanhar, histórico, reservas, planos, ida e volta, queixas,
avaliação, recibos) só se abriam a partir destes pontos.

Estafeta/motorista: entrada no modo TVDE para `carro_passageiros` (`main.dart`); cartão de oferta
de corrida por cima de tudo (`tvde_offer_overlay_host.dart`); ganchos das notificações de oferta,
reserva e "a caminho" (`main.dart`); cadastro "Carro — Passageiros" (`driver_signup_screen.dart`) e
"Carro (viagens / TVDE)" (`driver_role_apply_screen.dart`); papel "Corridas de passageiros"
(`caixa_de_papeis.dart`, `trabalhar_no_bora_screen.dart`); textos "corridas" (`trocar_de_papel.dart`,
`ganhos_screen.dart`). Os ecrãs de `screens/driver/tvde/` (home TVDE, agenda, oferta, corrida,
conformidade, ficha legal, fiscalização) só se abriam pela home TVDE.

Parceiro: nada do TVDE.

Ficou de propósito: `web/viagem.html` e `web/fiscalizacao.html` da app web e `verificar/` do site
(páginas públicas com código de corrida ou de motorista, sem links); a página `viagens.html` do site
fica no repositório, fora da publicação.
