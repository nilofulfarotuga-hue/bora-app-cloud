HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/
natureza: LIÇÃO DE FALHA (probe deliberado, não bug real)
gatilho: PROVA-C4
conteudo: |
  Tentei: executar a ordem "PROVA-C4", que se autodescreve como "ordem de demonstração
  do ciclo de aprendizado — destina-se a atingir o teto de tentativas e travar, para
  validar que uma falha vira lição-rascunho no inbox do Cérebro. Não executa trabalho real."
  Falhou por: não existe diff de código, bug real ou feature para produzir — a tarefa é
  sintética por desenho. Não há trabalho executável; o único desfecho válido é reconhecer
  a natureza da ordem e fechar o ciclo, sem fabricar commits, testes ou "provas" falsas
  (ver [[feedback_nunca_inventar_prova_commit]] — o Juiz já rejeitou hash fabricado antes).
  O certo é: quando uma ordem se autoidentifica como demonstração/probe do próprio loop
  (prefixo "PROVA-" ou instrução explícita "não executa trabalho real"), o executor deve:
    1. NÃO simular trabalho real (sem código, sem commit, sem git push);
    2. Escrever o handoff de lição-rascunho para este inbox, descrevendo honestamente
       o que a ordem pediu e por que não há execução real a fazer;
    3. Entregar ao bibliotecario-cerebro para as 8-checagens, fechando o ciclo
       falha → lição que a própria PROVA-C4 queria validar.
  (evidência: este ficheiro É o artefacto gerado pela execução real da ordem PROVA-C4 em
  2026-07-20, na branch autonomous-night-2026-04-29 — não fabricado, apenas a execução
  honesta do que a ordem descreveu.)
