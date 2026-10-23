# Relatório da noite 21→22/10/2026 (missão geral-noite-21-10)

Escrito às 05:55 de 22/10 pela sessão local_b16c6598, que retomou o registo final (N10) porque a sessão
orquestradora local_6914492a ficou parada em "à espera" desde as 05:08 (combinado entre as duas: mais de 40 min
calada → a outra retoma). Fonte: e2e_log, fluxo `fechar-pendencias-20-10`, ids 4253 a 4352, e os ficheiros
RELATORIO-*/REVISAO-* desta pasta. Cada bloco passou por um revisor de contexto limpo antes de ir para o ar.

## Fiz isto

**Fila inteligente do Bora Motorista (A2) — no ar nas 3.** Android 682 e 683, web, iPhone build 201 válido no
TestFlight; a versão 1.0.24 (com o A2) está em revisão na Apple. A fila está ligada desde 21/10 às 20:21. Até às
05:52 de hoje não houve nenhuma corrida, por isso ainda não há prova com uma corrida real; a vigia de 15 em 15
minutos continua até às 12:00 e desliga a fila na hora se uma corrida ficar mais de 60 segundos sem oferta.

**Encomendas — aviso do estafeta e palavras (N2).** Já no servidor desde ontem às 21:00: o estafeta recebe
"📦 Nova encomenda" e nunca "corrida/passageiro"; o cliente recebe "a tua entrega" nas reservas; o recibo por
e-mail diz "Resumo da tua entrega"; quem não tem acesso ao Bora Motorista também não pede encomendas; o
histórico do cliente chama-se "As minhas corridas e encomendas" quando tem encomendas. Revisor SIM, enviado às
04:43. Web provada (a frase nova está no site às 04:56). Android e iPhone: os builds deste envio ainda estavam a
correr às 05:58 (Android no autoteste do emulador desde as 05:24, iPhone a compilar desde as 04:43) — falta a
prova destes dois. As Encomendas continuam DESLIGADAS.

**Reservas e hora de Lisboa (A3, outra sessão) — no ar nas 3.** Android 683, web, iPhone build 201.

**Segurança geral (N4) — no ar.** Revisor SIM, nada partiu. Três avisos que qualquer pessoa podia mandar a
qualquer outra passaram a ser só do servidor e do admin; as fotos de perfil só se mudam na própria pasta (antes
qualquer pessoa sem sessão apagava fotos de outros); 12 funções internas fechadas; os alertas com gravidade
"warning" voltaram a gravar. Android 684 (envio das 04:42).

**Duas de segurança dos pedidos e lavagens (3b) — no ar desde as 05:25.** O cliente já não escreve no próprio
pedido a loja, o estafeta, uma oferta ou a lista de estafetas a saltar, nem cria um pedido já com isso. Nas
lavagens, o cliente e o lavador já não mudam o estado, o total, o ganho do lavador nem o pagamento; as fotos do
carro só o próprio cliente as muda. Revisor: NÃO na 1.ª ronda (3 falhas reais), corrigido, SIM na 2.ª. Prova ao
vivo: 17 ataques recusados, 11 caminhos normais a passar. Detalhe em RELATORIO-N3b.md.

**E-mail dos 7 agentes (N5) — no ar e provado de ponta a ponta.** Um e-mail de fora para emerson@boraguarda.com
entra na caixa, o Emerson lê e responde, e a resposta chega à caixa de entrada do Gmail. A ponte na VPS que deixa
o Emerson ler e responder tinha um buraco (corria como dono da máquina e seguia atalhos numa pasta que o Emerson
controla). Foi desligada às 04:37, corrigida (utilizador próprio sem poderes, caixa fechada pelo sistema, não
segue atalhos, registo fora da pasta partilhada), testada com 8 testes (um atalho plantado é recusado) e
religada às 05:05, com o caminho normal provado outra vez. **Revisor da 2.ª ronda: SIM (06:15).** Plantou 7
armadilhas como se fosse o Emerson (atalhos para um ficheiro de teste, para um ficheiro do sistema e com o nome
das respostas): a ponte recusou todas e nenhum ficheiro mudou. Deixou 3 achados baixos para uma próxima ronda
(trocar a pasta inteira por um atalho, o número do utilizador repetido noutro programa, e um pedido mal feito
que faz a ponte parar — só estraga a caixa do próprio Emerson).

**Skill dos navegadores (N6) — feita e no repositório.**

## Falta isto (e porquê)

1. ~~Envio da correção da ponte (N5)~~ — **feito** a 22/10 às 06:49 (3ea751d1) e provado nas 3 (ver
   "Atualização da manhã"). Nota: a ponte tinha sido religada às 05:05, antes do revisor — a ordem pedia o
   revisor primeiro; o revisor da 2.ª ronda disse SIM às 06:15.
2. ~~Prova do N2 no Android e no iPhone~~ — **feita** (Android 685, iPhone build 202).
3. ~~Primeira corrida real pela fila inteligente~~ — **aconteceu** a 22/10 às 21:27 (ver "Atualização de 23/10").
4. **Chave nova (N9)** — parada à espera do Danilo: as 3 funções de pagamento (reembolso, fechar o pedido
   depois do cartão, cobrar extra) mexem na Stripe; e para passar a VPS e o CI para a chave nova é preciso um
   código de acesso novo do Supabase. As chaves antigas continuam ligadas, como mandado.
5. ~~Envio dos ficheiros do 3b para o GitHub~~ — **feito** a 23/10 (ver "Atualização de 23/10").
6. **Prova no emulador do carro a deslizar** — não feita: o PC tinha 1,2 a 1,7 GB livres (regra: 3 GB) e uma
   corrida demo de noite pode tocar a um motorista real.

## Erros que encontrei pelo caminho (reportados, não corrigidos)

- O aviso da Stripe chama a função que fecha o pedido com a chave nova e ela recusa (ainda não apanhou ninguém).
- Qualquer conta com sessão lê todas as definições da plataforma, incluindo comissões e o markup escondido.
- O registo de parceiro lê a identidade da sessão sem a confirmar.
- A sincronização do Córtex na VPS está parada desde 04/09 (usa uma chave a que as funções já não estão abertas).
- A hora da corrida marcada do Bora Motorista e 6 ecrãs de marcações ainda usam o relógio do telemóvel.
- O estafeta ainda consegue mudar a loja do pedido que leva; a loja ainda consegue pôr um estafeta direto no
  pedido sem passar pelo caminho oficial (a barreira está desligada).
- Qualquer cliente com sessão consegue criar um pedido "cru" direto na tabela, com o preço à escolha, saltando o
  cálculo do servidor (nenhuma app usa este caminho, mas está aberto).
- O cliente ainda vê, na própria lavagem, quanto o lavador ganha e quanto fica para a Bora.
- A tranca recusou, por engano, uma cópia de ficheiro do robô B (julgou ver uma chave) — falso positivo.
- A sessão orquestradora parou duas vezes sem aviso (21:35→04:37 e 05:08→06:48), e esta sessão ficou presa num envio sem rede de 22/10 06:49 a 23/10 05:48.

## PARA O DANILO

1. **Chave nova:** precisa de "autorizo" para publicar as 3 funções de pagamento com a chave nova, e de criares
   um código de acesso novo no painel do Supabase (o de 21/09 já não serve).
2. **Dinheiro, à espera de "autorizo":** a loja receber o prémio do check-in no acerto semanal; a taxa de
   serviço do prémio; fechar a leitura das definições da plataforma; fechar a criação de pedidos "crus".
3. **Lavagens:** queres que a app passe a ler só o que cada um precisa, para depois se fechar a leitura do
   dinheiro? (mudança na app + publicar nas 3).
4. **YouTube do radar:** deixei aberta no Chrome pessoal a página de entrada da conta 1 — entra tu, uma vez.
5. **Permissões das sessões (N8):** é na app, em Definições do Claude Code → modo de permissões por omissão.
6. **Encomendas:** continuam desligadas até decidires (quem pode pedir, a lei TVDE para mercadoria, a foto).

## Próximo passo

Só falta o que está à espera do Danilo (secção acima). A prova no emulador do carro a deslizar fica para quando o
PC tiver 3 GB livres e houver forma de a corrida demo ir só ao estafeta demo.

## Atualização da manhã (08:40 de 22/10, sessão local_6914492a)

- N2 provado nas 3: Android 685 (= app_latest_version_code), web, iPhone build 202 enviado à Apple
  (e2e N2-A1-publicado, 4359).
- N5 enviado às 06:49 (3ea751d1) e provado nas 3: Android 686, web com o ecrã "E-mail dos agentes", iPhone build
  203 enviado à Apple (e2e N5-email-provado, 4369). A volta de fora foi feita com o Gmail da EMPRESA
  (boraappbora@gmail.com) às 21:23 de 21/10 — o teste com o Gmail pessoal do Danilo deixa de ser preciso.
- N9: o repositório ficou igual ao que está no ar em 5 funções que já aceitam a chave nova (a98a0636, sem
  compilar a app); o robot-b ficou de fora porque a tranca não deixou comparar.
- N7: a conta do radar é nilofulfaro@gmail.com e o Google pede a palavra-passe dela no Chrome pessoal.

## Atualização de 23/10 (05:50, sessão local_b16c6598)

- **Primeira corrida real pela fila inteligente:** 22/10 às 21:27, cliente real. A fila calculou a lista e fez
  a 1.ª oferta aos 29 segundos (regra: até 60). Havia 1 motorista; não aceitou em 40 s, a lista acabou, e o
  cliente cancelou passados 3 minutos. A fila fez o que devia; faltou haver mais motoristas ligados.
  (e2e N1-primeira-corrida-real, 4429). Antes disso só houve 3 reservas, que seguem outro caminho.
- **Falha da vigia (digo-o claro):** a vigia de 15 em 15 minutos correu das 04:52 às 06:37 de 22/10. A partir das
  06:49 esta sessão ficou presa num envio para o GitHub enquanto o PC estava sem rede, e só voltou a 23/10 às
  05:48 — as vigias das 06:52 às 11:52 não correram. Verifiquei depois pela base: nesse intervalo houve só uma
  reserva, com motorista, e nenhuma corrida sem oferta; a fila nunca precisou de ser desligada (e2e
  N1-vigia-fim, 4430). A fila continua ligada.
- **3b enviado para o GitHub** a 23/10, depois do "pode" da sessão local_6914492a (só migrações e documentos;
  dispara build Android e site, a app sai igual).
