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
religada às 05:05, com o caminho normal provado outra vez.

**Skill dos navegadores (N6) — feita e no repositório.**

## Falta isto (e porquê)

1. **Revisor da 2.ª ronda da ponte do e-mail (N5).** A ponte foi religada às 05:05, antes de o revisor de
   contexto limpo ver a correção (a ordem pedia o revisor primeiro). A sessão que tinha o N5 parou a seguir.
   Os ficheiros estão no ramo `agentes-email-21-10`, por enviar.
2. **Prova do N2 no Android e no iPhone** — builds ainda a correr às 05:58.
3. **Primeira corrida real pela fila inteligente** — ainda não houve nenhuma corrida.
4. **Chave nova (N9)** — parada à espera do Danilo: as 3 funções de pagamento (reembolso, fechar o pedido
   depois do cartão, cobrar extra) mexem na Stripe; e para passar a VPS e o CI para a chave nova é preciso um
   código de acesso novo do Supabase. As chaves antigas continuam ligadas, como mandado.
5. **Envio dos ficheiros do 3b para o GitHub** — vão disparar um build Android e o site (a app sai igual, só com
   número novo); combinado para ir depois do último envio da outra sessão.
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
- A sessão orquestradora parou duas vezes sem aviso (21:35→04:37 e desde as 05:08).

## PARA O DANILO

1. **Chave nova:** precisa de "autorizo" para publicar as 3 funções de pagamento com a chave nova, e de criares
   um código de acesso novo no painel do Supabase (o de 21/09 já não serve).
2. **Dinheiro, à espera de "autorizo":** a loja receber o prémio do check-in no acerto semanal; a taxa de
   serviço do prémio; fechar a leitura das definições da plataforma; fechar a criação de pedidos "crus".
3. **Lavagens:** queres que a app passe a ler só o que cada um precisa, para depois se fechar a leitura do
   dinheiro? (mudança na app + publicar nas 3).
4. **YouTube do radar:** deixei aberta no Chrome pessoal a página de entrada da conta 1 — entra tu, uma vez.
5. **Permissões das sessões (N8):** é na app, em Definições do Claude Code → modo de permissões por omissão.
6. **Teste do e-mail com o teu Gmail pessoal:** só com o teu sim na conversa.
7. **Encomendas:** continuam desligadas até decidires (quem pode pedir, a lei TVDE para mercadoria, a foto).

## Próximo passo

A vigia da fila continua até às 12:00 (resumo no e2e_log, passo N1-vigia-fim). Lançar o revisor da 2.ª ronda da
ponte do e-mail, confirmar os builds Android e iPhone do N2, e enviar o ramo do 3b.
