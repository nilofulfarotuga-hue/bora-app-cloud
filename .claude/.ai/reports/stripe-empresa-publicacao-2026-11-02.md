# Relatório — Stripe da empresa: app nova publicada (02/11/2026, 08:15–10:15)

Missão `stripe-empresa-2026-11-01`, continuação (Claude Code, Opus). Autorizações: «Autorizo»
01/11 22:03; «Hoje, é urgente» e «Sim, obrigar a atualizar» 02/11 07:58.

## Para o Danilo (texto corrido)

Fiz isto: publiquei a app nova com as duas contas Stripe. A web já está no ar com ela desde as
08:41 (app.boraguarda.com). O Android foi enviado para o Google Play, com o versionCode 706, e o
teste automático dos três perfis passou; agora é o Google a pôr a versão nas lojas. Antes de
publicar acrescentei a bandeira das duas contas ao MB Way dos pedidos, que faltava, e confirmei
que a Claude.ai mudou só as duas linhas combinadas no ficheiro dos pedidos. O analisador não deu
erros e os testes passaram.

Falta isto: no iPhone, a versão nova (1.0.35, compilação 224) chegou à Apple e está no TestFlight,
mas não foi submetida para revisão, porque a Apple ainda tem a versão 1.0.34 à espera de
revisão. A Claude.ai tem de tratar disso no painel da Apple: ou tira a 1.0.34 da fila e submete
com a 224, ou espera que a 1.0.34 seja aprovada e submete a seguir. O interruptor já está em
"empresa" desde as 09:00 (foi a Claude.ai, com a tua ordem). Obrigar a atualizar ainda não está
ligado; só depois de a Apple aprovar, para quem tem iPhone não ficar sem a app.

Erros que encontrei pelo caminho: o servidor já diz aos iPhones que há uma versão nova (a 224),
mas ela ainda não está na loja; quem tem iPhone pode ver o aviso "há atualização" e não encontrar
nada novo (o aviso fecha-se com "Agora não"; já acontecia com a 223 de manhã). A prova automática
da folha do cartão no iPhone não corre porque faltam no GitHub as chaves de teste da Stripe (era
assim antes).

Próximo passo: a Claude.ai submete o iPhone à Apple; quando a Apple aprovar, liga-se o "obrigar
a atualizar" nas três.

## Prova (e2e_log, fluxo `stripe-empresa-2026-11-01`, passos C1 a C6)

- C1: `payment_service.dart:292` MB Way com `StripeContas.marcar`; varredura: 19 chamadas com
  bandeira, 6 sem que não precisam (conta gravada ou procura nas duas), 1 era o order_store.
- C2a: só o `autonomous-night-2026-04-29` publica; o ramo da missão só corre o olho-golden.
- C3: c76c18be = só 2+/2− em `order_store.dart`; analyze 13 ficheiros 0 erros; 24 testes verdes.
- C4b: push 2e00f125..c76c18be às 08:38:58 UTC; fiscal de segredos limpo.
- C6a web: `versao.json` = c76c18be, run 253; `main.dart.js` com `stripe_contas_v2` ×12.
- C6b Android: run 41414614512 verde; "Upload to Google Play (internal + alpha + production)"
  verde; versionCode 706.
- C6c iPhone: run 41414614612 verde; IPA 1.0.35 build 224 "UPLOAD SUCCEEDED"; não submetida
  (1.0.34 WAITING_FOR_REVIEW).
