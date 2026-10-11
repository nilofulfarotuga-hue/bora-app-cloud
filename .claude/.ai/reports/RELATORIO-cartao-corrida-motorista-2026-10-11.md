---
data: 2026-10-11
sessao: PC do Danilo (Claude Code)
scope: cartao-corrida-motorista
estado: FEITO — publicado nas 3 (Play 664, web, Apple build 183 / 1.0.17 em revisão)
commit: a1e7eddf
---

# Cartão da corrida do motorista por fases (11/10/2026)

## O que NÃO foi feito (primeiro)

- O título da reserva ainda por confirmar diz "A caminho da recolha", como a ordem pedia;
  o revisor achou que choca com o botão "Vou a caminho". Ficou como a ordem mandou.
- O "Navegar" em viagem com paragem leva ao DESTINO, não à paragem (é o `_navigate` de
  sempre — a ordem mandou não mexer). Reportado em baixo.
- A foto antiga da oferta sobreposta (`test/golden/tvde_oferta_sobreposta_test.dart`) ainda
  desenha o painel velho por baixo da oferta. Não falha; não mexi.
- Prova no iPhone real e na web com uma corrida verdadeira: não há corrida de teste
  permitida em produção. A prova de ecrã foi no emulador Android, com o ecrã verdadeiro e
  uma corrida de exemplo num store falso, sem escrever no banco.

## O que mudou no telemóvel do motorista

- O botão da fase (Cheguei ao passageiro / Iniciar viagem / Finalizar viagem / Vou a
  caminho) está sempre visível, fixo no fundo. A gaveta assenta por cima dele.
- O topo da gaveta diz a fase do lado do motorista:
  - a caminho: "A caminho da recolha · nome", e só a morada de recolha em grande;
  - chegou: "À espera de nome", o cronómetro de espera e a morada de recolha;
  - em viagem: "A levar nome ao destino", e só o destino em grande (ou a próxima paragem).
- O tempo aparece uma vez só ("Chegas em ~X min" / "Chegada em ~X min"; com paragem,
  "Chegada ao destino em ~X min"). O ganho ao lado: "Ganhas €X".
- "Navegar" passou a botão pequeno ao lado da morada.
- A gaveta: recolhida mostra o topo inteiro (já não fica uma linha cortada); abre até 88%
  do ecrã ou até ao fim do conteúdo; abre e fecha com um toque no topo ou arrastando.
  Ao mudar de fase volta à posição recolhida.
- Lá dentro, aberta: passageiro com mensagem e ligar, quanto cobrar em dinheiro, balcão,
  pacote ida-e-volta, mudança de destino, paragens, próxima corrida, devolver reserva e
  "Viagem: recolha → destino". Nada se perdeu.
- Não mexi em valores, ganho, cobrança, `tvde_finish_ride`, despacho nem RPCs.

## Provas

- `flutter analyze`: 0 erros. No ficheiro do ecrã fica só uma nota antiga (no cancelar).
- Testes: 1224 verdes. 19 testes novos (título por fase, cabeçalho, botão fixo, gaveta,
  arrasto com o ecrã a redesenhar-se).
- Revisor de contexto limpo: à primeira REJEITOU — arrastar com o dedo era cancelado
  quando o ecrã se redesenhava (o Flutter compara as paragens da gaveta por identidade).
  Corrigido; o teste novo chumbava (0.234) e passa. Segunda volta: ACEITA.
- Emulador Android 15, barra de 3 botões, ecrã verdadeiro: 8 capturas em
  `bora_app/.claude/.ai/provas/cartao-corrida-motorista-2026-10-11/capturas_android_tres_botoes/`.
  Gaveta aberta com o dedo em todas as fases (ex.: 0.233 → 0.591) e fechada com um toque.
  O servidor recusou as posições de teste (42501) — nada gravado.
- 16 fotos em memória (390 e 320 px), sem estouro: `test/golden/_fotos/tvde_corrida_motorista_*.png`.

## Publicação

Push `e412ba71..a1e7eddf` no ramo `autonomous-night-2026-04-29` às 20:38 (só o commit
desta missão viajou). As 4 corridas do CI acabaram verdes:

- **Android / Play**: autoteste dos 3 perfis verde; AAB enviado (internal + alpha +
  produção). Prova: `app_latest_version_code = 664` na base (antes 663) e commit do CI
  `6bac7616 bump versionCode to 664`.
- **Web**: `app.boraguarda.com` e `bora-app-web.pages.dev` servem o mesmo bundle
  (sha `e2f6e754ae8e`, com e sem quebra-cache) com as frases novas ("A caminho da
  recolha", "Chegas em ~") e sem a velha ("Recolha em ~").
- **iPhone / Apple**: simulador verde; IPA enviado. No App Store Connect (leitura pela
  API): build **183** carregado às 21:38 UTC, estado `VALID` (TestFlight); versão
  **1.0.17** criada às 21:42 UTC, `WAITING_FOR_REVIEW`, lançamento automático depois
  da aprovação.
- Fotos (`olho-golden`): verde.

O teste de corrida a sério (no telemóvel, com passageiro, em dinheiro) fica para a
próxima corrida real — a app nova chega pela Play (664) e, no iPhone, quando a Apple
aprovar a 1.0.17.

## Outros erros encontrados (não corrigidos)

1. "Navegar" em viagem com paragens abre a navegação até ao destino e salta as paragens.
2. Com o nome do passageiro em falta, o topo diz "À espera do passageiro" duas vezes
   (título e cronómetro).
3. Logo a seguir a mudar de fase, o tempo pode mostrar por segundos o número da rota
   anterior, até a rota nova chegar (já era assim).
4. A foto antiga da oferta sobreposta ainda mostra o painel velho por baixo.
5. **Grave, fora desta missão (achado do bibliotecário):** entre 07/10 20:39 e 08/10 01:16
   (UTC), 7 escritas do Córtex com caminho "undefined" ("cortex(mcp): claude.ai atualizou
   undefined") gravaram a página `missao-noite-2026-10-07` por cima de 7 ficheiros do
   Cérebro: `00_BORA_DNA.md`, `2026-05-08_anthropic_dreaming_autodream.md`,
   `BLOQUEADORES_RESOLVIDOS_2026-06-12.md`, `CONTEXT.md` (19 KB perdidos), `INDEX.md`,
   `PROTOCOLO.md`, `_arquivo/MAPA_migracao_MEMORY_2026-07-01.md`. O commit `9d333a9d`
   também apagou `orquestracao/vigia-vps.sh`. O `INDEX.md` foi reposto (versão de 05/10 +
   a linha da lição nova). Os outros 6 e o script continuam estragados: restaurar os 7 de
   uma vez foi recusado pelo classificador e não se insistiu. A causa (o Córtex grava com
   caminho "undefined") não está corrigida e pode repetir-se.

## PARA O DANILO

- Restaurar os 6 ficheiros do Cérebro e o `vigia-vps.sh` estragados a 07–08/10: cada um
  volta à versão de antes do seu commit (`git restore --source=<commit>^ -- <ficheiro>`).
  Precisa da tua palavra ("restaura o Cérebro") porque o sistema recusou fazê-lo sozinho.
- Reserva por confirmar: queres o título "A caminho da recolha" (como pediste) ou
  "Reserva · nome", para não chocar com o botão "Vou a caminho"?
