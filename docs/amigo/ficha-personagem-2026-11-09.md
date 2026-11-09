# Ficha da personagem — o Amigo (09/11/2026, missão m11-amigo-rosto)

Fonte: o protótipo que o Dipsy fez a 07-08/11 em `C:\Users\danil\Desktop\bora-amigo-teste\`
(`amigo.js`, vídeo `provas/video-amigo.mp4` de 57 s visto a uma imagem por segundo, folha
`provas/folha-expressoes.png`). A personagem é nossa (desenho original do Bora). Inspiração
de expressividade: carinhas de ecrã de animação; nada copiado de nenhum filme.

Imagens de referência (do protótipo, uma por expressão): `ref/dipsy-alegre.png`,
`ref/dipsy-triste.png`, `ref/dipsy-surpreso.png`, `ref/dipsy-pensativo.png`,
`ref/dipsy-confuso.png`, `ref/dipsy-a_falar.png`.

## Corpo e cabeça

- Robozinho de cabeça grande e corpo pequeno. Sistema de coordenadas do desenho: caixa
  `0 -28 300 373` (300 de largura).
- Cabeça: retângulo muito arredondado (x 38–262, y 36–232, raio 86), casca verde em
  degradê vertical `#2BCB63` → `#16A34A` (55 %) → `#13843D`.
- Ecrã da cara: retângulo arredondado (x 56–244, y 54–214, raio 70), fundo escuro em degradê
  radial `#123A24` (centro, um pouco acima do meio) → `#06160D`, contorno `#0E5C2B` de 3.
  Reflexo branco a 10 % no canto de cima à esquerda.
- Orelhas: duas cápsulas laranja `#F97316` (22×52, raio 11) dos lados da cabeça.
- Antena: haste verde-escura `#13843D` (y 40 → 16) com bola laranja `#F97316` de raio 8 e um
  brilho laranja desfocado à volta (mais forte a pensar e a falar). A antena balança devagar.
- Corpo (variante com camisa): tronco verde arredondado (x 96–204, y 236–322, raio 42),
  pescoço `#13843D`, dois pés ovais `#13843D`, braços verdes com mãos brancas redondas
  (contorno `#E5E7EB`), mancha branca oval no peito (35×27). No protótipo havia um cadeado
  laranja no peito; na app o peito leva o logótipo da Bora (`assets/branding/bora_logo.png`,
  sem o alterar), como o Danilo pediu a 09/11. Sombra oval no chão a 13 %.

## Olhos, sobrancelhas e boca

- Olhos: duas formas brancas `#F4FFF7` com brilho (desfoque 2,4) centradas em x 112 e 188,
  y 128; largura 23, altura 30. Cada olho é desenhado por duas curvas (pálpebra de cima e de
  baixo), o que deixa fazer olhos meio fechados, tristes (pálpebra inclinada) e sorridentes
  (pálpebra de baixo a subir, "olhos em arco").
- Pupilas pretas `#06160D` de raio 11,5 com um ponto de brilho branco de 3,6; ficam presas
  dentro do olho e seguem o olhar (até 9 de deslocação).
- Sobrancelhas: traços brancos com brilho, espessura 6,5, pontas redondas, curva para cima;
  sobem, descem e inclinam por expressão.
- Bochechas: duas elipses laranja (15×8) a 55 % da força do "corado" (mais fortes alegre).
- Boca: forma fechada de duas curvas (lábio de cima e de baixo) com fundo castanho-escuro
  `#3B1105`, dentes brancos em cima, língua laranja, e contorno branco com brilho de 4,5.
  Parâmetros: largura, abertura, sorriso (cantos sobem/descem), arredondado (para O/U),
  deslocação e assimetria (boca de lado a pensar ou confuso).
- Símbolos por cima da cabeça: "!" (surpreso), "?" (confuso), "…" (pensativo), laranja,
  aparecem com um pequeno salto e balançam.

## As expressões (alvos dos parâmetros)

| Expressão | Olhos | Sobrancelhas | Boca | Cabeça e braços |
|---|---|---|---|---|
| neutro | abertos 100 % | normais | sorriso leve | direita, braços em baixo |
| alegre | olhos em arco (pálpebra de baixo sobe) | sobem | sorriso grande e aberto, corado forte | sobe um pouco, braço direito acena |
| triste | 72 % e pálpebra inclinada, pupilas maiores a olhar para baixo | caídas e inclinadas | cantos para baixo, estreita | inclina para o lado e desce, braços colados |
| surpreso | 132 % e mais largos, pupilas pequenas | muito altas | "O" redondo e aberto | sobe, braços abertos, "!" |
| pensativo | um olho mais fechado, olhar para cima ao lado | uma sobe, outra desce | pequena, de lado | inclina, mão no queixo, "…" |
| confuso | um olho grande e outro pequeno | desencontradas | torta | inclina para o outro lado, "?" |
| a falar | normais | ligeiramente subidas | segue a voz | aceno leve da cabeça com a voz |
| a ouvir | 108 % atentos | subidas | sorriso leve | inclinada, antena acesa |

## Como está vivo

- Pestanejar: fecha em 55 ms, fica fechado 25 ms, abre em 80 ms; de 2,4 a 5,2 s
  (aleatório); 15 % das vezes pisca duas vezes seguidas. Ao mudar de cara, pisca muitas vezes.
- Olhar: pequenos saltos (sacadas) a cada 0,8–2,6 s; menos amplos a falar, a pensar ou triste.
  A cara inteira desloca-se um pouco para o lado do olhar (paralaxe).
- Respiração: ciclo de 3,8 s; a cabeça sobe e desce 1,6 e o corpo estica 1,4 %.
- Mudança de expressão: cada parte vai para o alvo à sua velocidade (olhos rápidos, cabeça
  lenta) e há uma mola de "encolhe e estica" (antecipação) que dá o salto da mudança: mais
  forte no surpreso e no alegre.
- A falar: a cabeça acena com a força da voz e a antena acende.

## A voz e a boca

- O Dipsy usou o edge-tts (vozes "Natural" da Microsoft pt-PT-RaquelNeural e
  pt-PT-DuarteNeural), por um pequeno servidor no PC que devolve o MP3 e o tempo de cada
  palavra. Precisa de internet e a licença não é comercial (o próprio relatório dele diz que
  para produto é a Azure Speech, que é paga). Não corre na app sem custos, por isso a app usa
  a voz do próprio telemóvel ou navegador, sempre em português de Portugal (nunca pt-BR).
- Boca por som (visemas): cada palavra vira uma lista de formas de boca a partir das letras
  portuguesas (A, E, I, O, U, fechada M/B/P, F/V, L/N/D/T, S/Z/J/X/Ç, R, outras, repouso),
  com regras do português de Portugal ("ão" longo, "e" final quase mudo). A duração de cada
  palavra divide-se pelas formas; perto do fim de uma forma a boca já se prepara para a
  seguinte (coarticulação) e a boca antecipa 35 ms, como os animadores fazem.
- O protótipo acertava a boca pelos tempos de palavra da voz e pelo volume real do som.
- Números medidos pelo Dipsy: atraso boca/som de 0 a 30 ms (Raquel) e 0 a 70 ms (Duarte);
  correlação boca/volume 0,73–0,84; primeira frase 2,1–4,3 s a começar (voz gerada na hora),
  ~57 ms com a frase guardada. Desempenho no PC: 60 imagens/s, 0,3 ms de trabalho por imagem,
  8 MB de memória. No emulador Android: 14,5 imagens/s, mas o código só gasta 0,7 ms por
  imagem (o lento era o desenho por software do emulador).

## O que muda na app (m11)

- O desenho passa para Flutter nativo (pintura própria, sem janela web), com os mesmos
  números do protótipo, para correr igual em Android, iPhone e na web.
- Duas variantes no painel: só a cara, ou cara com camisa e o logótipo da Bora ao peito.
- Na home e em tamanhos pequenos aparece só a cara.
