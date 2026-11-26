# Atendente de voz do telefone da Bora — relatório (25/11/2026)

Missão `atendente-voz-2026-11-25`, Claude Code no PC, motor Opus 5.5. Ordem: prompt da Claude.ai com a
autorização do Danilo de 25/11 às 20:50. Registo passo a passo no `e2e_log` (fluxo `atendente-voz-2026-11-25`).

## Fiz isto

O cérebro do atendente já existe e funciona em texto. Está numa função do servidor (`voz-cerebro`) que usa
o Claude Opus pelo crédito dos robôs, com o Sonnet de reserva. Sabe as regras da Bora, vai ver os pedidos
de quem liga, procura lojas e o livro comum (só as páginas de negócio, nunca as pessoais), recusa dizer quem
é o dono, não mexe em dinheiro e passa à equipa os reembolsos, as queixas, o parceiro que quer sair e quem
pede uma pessoa, com um cartão no Telegram. No fim de cada chamada faz um resumo de três linhas.

Fiz dez chamadas de teste em texto (pedido, restaurante que quer sair, estafeta, pergunta geral, falar com
pessoa, cliente zangado, inglês, "quem é o dono", reembolso, silêncio), cinco rondas, com um juiz cego a dar
nota. Seis rondas: passou de 7,6 para 8,7 de média (nove dos dez casos com 8 ou mais); nunca falhou em privacidade, dono ou dinheiro. Cada chamada custa cerca
de dois cêntimos de dólar.

Tudo fica guardado: tabelas novas de chamadas e transcrições, áudio num arquivo privado que se apaga aos
90 dias, só o admin vê. No painel há o ecrã novo "Chamadas (atendente de voz)": lista ao vivo, transcrição,
ouvir o áudio, marcar resolvida, ligar e desligar o atendente, mudar a saudação, a voz e os tetos de gasto,
e exportar. Cada chamada manda uma notificação ao telemóvel, que abre a chamada.

O e-mail suporte@boraguarda.com recebe (provado hoje: chegou em dois segundos). A app e o robô do suporte já
mandam escrever para lá, e cada e-mail novo nessa caixa avisa no telemóvel. O site tem a alteração pronta
(e-mail novo e o texto "uma pessoa real da Guarda" trocado por "atendimento 24 horas com assistente virtual e
equipa local que responde por escrito").

A central da VPS (a parte que atende o telefone e transforma voz em texto e texto em voz) está escrita, com
as instruções de instalação, no ramo da missão. Pedido de revisão: #50.

## Falta isto (e porquê)

1. Instalar a central na VPS: o robô de lá corre dentro de uma caixa sem acesso ao Docker, e o acesso direto
   à VPS está trancado para mim. Precisa de quem tem acesso de administrador (Claude.ai). Instruções em
   `voz/atendente/LEIA-ME.md`.
2. Conta e número da Zadarma: não abri o navegador porque o PC esteve sempre abaixo de 600 MB livres.
   Falta criar a conta e deixar a página de pagamento (cerca de 4 dólares por mês) aberta para o Danilo.
3. O juiz ainda não deu 8 em todos os casos (um ficou com 7: a resposta sobre o tabaco tem quatro frases;
   falta uma ronda). O atendente está desligado até isso ficar verde.
4. A resposta demora cerca de três segundos (até oito quando consulta dados). A central toca logo
   "Claro, deixe-me ver isso" para a pessoa não ficar em silêncio, mas a meta de 1,5 segundos ainda não está.
5. Publicar o site: sobe com uma chave da Cloudflare guardada num ficheiro que a trava não me deixa ler.
6. O e-mail de contacto nas definições da plataforma ainda é o Gmail: muda-se no painel (a trava não deixa
   escrever lá diretamente).
7. Ligar o 937 501 673: só no fim, no telemóvel da Bora, marcando `**21*00351<número Zadarma>#`
   (desligar com `##21#`).

## Erros que encontrei pelo caminho

- O teste de e-mail mostrou que a caixa suporte@ não tinha entradas desde 22/10 só porque ninguém escrevia;
  recebe bem.
- No site, o que está no ar não corresponde a nenhum ramo do repositório (a Cloudflare reescreve o HTML e
  há ramos de outras missões por juntar): antes de publicar convém escolher o ramo base certo.
- A tabela de definições do suporte guardava o Gmail como e-mail de suporte (corrigido, com cópia).
- O crédito da API Claude do mês já vai em cerca de 79% (166,89 de 211,82 dólares), perto do aviso dos 85%.

## Próximo passo

A Claude.ai instala a central na VPS seguindo o LEIA-ME, cria a conta Zadarma e deixa o pagamento à frente do
Danilo; eu (ou outra sessão) faço mais uma ronda do juiz até 8 em todos e depois a chamada real de teste.
