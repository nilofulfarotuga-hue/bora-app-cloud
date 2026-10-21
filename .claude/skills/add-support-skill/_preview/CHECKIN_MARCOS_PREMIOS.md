---
name: CHECKIN_MARCOS_PREMIOS
category: faq
mode: read_only
requires_human_handoff: false
allowed_tools: []
version: 1
fontes:
  - Regras do Danilo de 20/10/2026 (MISSAO fechar-pendencias-2026-10-20, Bloco D)
  - platform_settings checkin_marco_* (valores no painel admin)
---
# CHECKIN_MARCOS_PREMIOS

**Quando usar:** um cliente pergunta pelos prémios do check-in diário: o que ganha aos 10, 15 ou
30 dias seguidos, onde vê o prémio, como o usa, porque não apareceu, porque diz "guardado" ou
"falta 1 pedido", ou quanto tempo vale. Ex.: "fiz 10 dias e não vejo os salgados", "como uso o
prémio do açaí?", "o que é o prémio dos 30 dias?", "porque o meu prémio está guardado?".

**Tools:** [] (resposta direta, não chamar tools). Responder em PT-PT, curto e simples.

## As regras (não prometer nada além disto)
- Conta a sequência de dias seguidos de check-in. Falhar um dia faz a sequência voltar ao dia 1
  e os prémios recomeçam. Depois do dia 30 a sequência recomeça no dia 1.
- Os prémios da semana (Dia 1 a Dia 7) continuam iguais; os marcos juntam-se a eles.
- **10 dias seguidos:** 2 salgados grandes da Keli, na loja Sabores do Brasil (coxinha ou
  esfirra, à escolha). O cliente paga só a entrega e as taxas.
- **15 dias seguidos:** um Goola Bowl (o açaí mais barato do Goola), com 3 acompanhamentos à
  escolha. Os extras pagam-se à parte. O cliente paga só a entrega e as taxas.
- **30 dias seguidos:** o cliente escolhe 2 horas de limpeza em casa ou uma lavagem do carro só
  por fora. Não paga nada por esse serviço.
- Só ganha quem tem o telemóvel confirmado no perfil (o mesmo que o check-in diário pede).
- Cada prémio vale 30 dias, é só para a própria pessoa (não se passa a outra) e há um prémio de
  cada marco por sequência.

## Onde se vê e como se usa
- Ao chegar ao marco aparece uma notificação e o prémio fica em **"Os meus prémios"** (perfil,
  ou a seta do cartão do check-in na página inicial, que abre a vista do mês com os marcos).
- Prémio de produto: em "Os meus prémios" toca em **"Usar"**; abre a loja certa com o prémio no
  carrinho a 0,00 €. Escolhe os sabores ou os acompanhamentos e faz o pedido como sempre. Na
  loja certa o carrinho também mostra o prémio para aplicar.
- Prémio dos 30 dias: toca em **"Escolher"**, escolhe limpeza ou lavagem e marca o dia e a
  morada. A limpeza marca-se com pelo menos 12 horas de antecedência.
- Se o pedido ou a marcação não chegarem a acontecer, o prémio volta a ficar disponível (se
  ainda estiver dentro do prazo).

## Estados que o cliente pode ver
- **"Guardado"**: neste mês já se deram todos os prémios de 30 dias. O dele fica guardado e
  fica disponível no início do mês seguinte (a app diz a data).
- **"Falta 1 pedido para desbloquear o prémio"**: o prémio dos 30 dias pede pelo menos 1 pedido
  feito e entregue nos últimos 30 dias. Assim que fizer um pedido, o prémio desbloqueia sozinho
  (pode demorar até 1 hora). Se não houver pedido em 30 dias, o prémio perde-se.
- **"Expirado"**: passaram os 30 dias sem o usar.

## Regras
- Não inventar prémios, valores nem prazos. Os valores certos estão na app ("Os meus prémios" e
  a vista do mês).
- Não dar prémios no chat nem prometer exceções.

## Escalar quando
- O cliente diz que chegou ao marco e o prémio não aparece em "Os meus prémios" passada 1 hora,
  ou o prémio desapareceu sem ter sido usado → [HANDOFF_HUMAN] (o admin pode dar o prémio à mão).
- O pedido com o prémio deu erro na loja certa → [HANDOFF_HUMAN].
