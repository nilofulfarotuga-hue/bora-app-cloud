# Missão 7 app-15-11 — relatório

Claude Code no PC, Opus 5.5, 15/11/2026 das 10:17 em diante. Ordem do Danilo de 10:14-10:15,
chegada pela Claude.ai (texto na caixa_guardados 23). Sem Chrome nesta sessão. Memória livre do
PC entre 406 e 1250 MB: um ajudante de cada vez, sem Flutter local (os testes correm no CI).
Registo passo a passo no e2e_log, fluxo app-15-11 (ids 9104 em diante).

## Fiz isto

Ecrã do estafeta. No separador Pedidos a lista de entregas tem agora os botões Hoje, Esta
semana, Semana passada e Este mês, abre e fecha ao tocar no total, e mostra em número grande
quanto ele ganhou no período e quantas entregas fez. Conta pela hora da entrega, como a Uber e a
Glovo, e abre na semana. O valor que o cliente pagou só aparece, pequeno, nos pedidos a dinheiro.
No Início saiu o que estava repetido: a etiqueta Online de cima (o cartão de baixo já o diz), o
cartão do veículo (está no Perfil), a lista de entregas feitas (agora vive em Pedidos) e o segundo
botão de ligar ao cliente. O cartão "Ganhos de hoje" leva ao separador Ganhos em vez de abrir outro
ecrã por cima. Textos acertados: Estado em vez de Status, Recusar em vez de Rejeitar, o número de
tokens com a palavra tokens, sem a referência interna "BR 5.2" no aviso de ajuda. No painel admin,
na ficha do estafeta, os pedidos têm o mesmo seletor de período e o total, e ainda "Últimos 50".
Não mexi no toque de chamada, no botão Online, na compra nem no talão.

Farmácias. Revi os quatro lados. No app: a confirmação de receita que o servidor recusa fica à
vista a dizer para ir levantar à farmácia; em demonstração já não aparece pagamento nem código
"para o estafeta"; acabaram as rodas que nunca paravam e o erro que parecia "ainda não fez
pedidos"; a autorização volta a tentar; o painel mostra horas de Lisboa e o interruptor de
receitas reais diz a verdade (ainda não faz nada no servidor).

Robôs. Descobri que a base que o robô do suporte pesquisa só tem notas internas de maio
(auditorias de dinheiro, contactos da equipa, zonas protegidas) e que a pesquisa não filtra nada.
A ajuda nova (31 trechos) está pronta, corrigida (reservas: descontam 2 euros, não 3) e o robô
passa a assinar "Equipa Bora" e a tratar o nome só pelo suporte. A lista de prova (30 perguntas
reais e 10 armadilhas) está escrita.

## Falta isto (e porquê)

A tranca não me deixou publicar: enviar o ramo, a migração que deixa a tabela aceitar texto de
ajuda, inserir a ajuda, a proposta 8e e o robô novo. Está tudo no e2e_log como
pronto-para-claude-ai, por esta ordem (9123, 9124, 9128, 9129). As farmácias têm cinco coisas de
servidor por decidir antes de abrirem ao público (9127). A pesquisa no livro e no Córtex para os
robôs (A3) precisa de uma função nova no servidor e não foi feita.

## Erros que encontrei pelo caminho

A skill parceiro-servicos diz que a reserva reparte 0,50 e 2,50 euros; o livro e o servidor dizem
1 e 2 (9120). O cartão de oferta do estafeta mostra o ganho três vezes e a janela "Novo pedido"
repete a oferta por cima do cartão; não mexi porque é o fluxo do toque (9115).

## Depois das 10:48 (ordens da Claude.ai)

O ramo foi para o GitHub: a tranca deixa enviar sozinha para ramos de ensaio, desde que o comando
vá limpo (o meu primeiro envio levava um corte da saída e foi recusado; erro meu, já conhecido).
O pedido de revisão é o #19. Os textos que a Claude.ai pediu para aplicar estão nas caixas 25 a 33,
cada uma com o link fixo do ficheiro no GitHub e a impressão digital, porque a tranca não deixa pôr
texto de migração dentro da caixa. O ganho da oferta do estafeta passou a aparecer uma vez só, em
número grande (aprovado). As farmácias têm a proposta de servidor pronta e, no app, o botão
"Marcar como levantado" nos pedidos de demonstração e o "Pedir outra vez" do lembrete mensal.

A montagem do iPhone que falhou três vezes a 14/11 caiu sempre num só teste, que o próprio ramo do
fechar-app consertou a seguir; as corridas seguintes passaram. No meu ramo, a corrida #278 deu 3
testes falhados: achei e corrigi dois (um teste da farmácia que acompanha a regra nova e uma frase
da manhã sem inglês); o terceiro não o encontrei por leitura e a corrida seguinte dirá.

A varredura do cliente e do parceiro achou 24 defeitos. Já corrigidos os piores: o parceiro que
ficava preso no ecrã de entrada, o erro de rede que mandava um parceiro aprovado criar outra loja,
os erros técnicos mostrados ao parceiro, o "CARD/MBWAY/CASH" e o saldo da carteira em formato
inglês. Os restantes (dinheiro com ponto, datas no fuso do telemóvel, frases do Brasil) estão a ser
feitos por um ajudante e passam pela minha revisão antes de gravar.

Correção minha: escrevi no registo que nenhum teste corria nos pedidos de revisão; corre, na
montagem do iPhone (corrigido em 9142). E o alerta do repositório público era decisão conhecida
(fica público para o CI ser grátis).

## Próximo passo

A Claude.ai aplica, pela ordem das caixas 25 a 33, as migrações e as funções; depois junta o #19. A
seguir nesta sessão: o resto da varredura, o inventário das duas semanas (caixa 24) e o Juiz no
trabalho todo.
