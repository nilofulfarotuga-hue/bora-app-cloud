# Avença — a revisão tinha razão, e o que se fez a seguir (24/09/2026)

> Missão `agente-avenca-qualidade-2026-09-24`. Fluxo do `e2e_log` com o mesmo nome.
> **Continua sem ter sido enviado nada a ninguém.**

## O que estava mal

A revisão do Claude.ai olhou para as 10 amostras da manhã e chumbou **6**. Tinha razão em
todas, e a causa era uma só: **eu casei cada negócio com o primeiro resultado do Google sem
confirmar que era o mesmo negócio.**

| Amostra | O que o Google devolveu |
|---|---|
| JS (café) | a sede do PSD/JSD/TSD da Guarda |
| Bemequer (ginásio) | fechado para sempre |
| Moreira (restaurante) | a aldeia Moreira de Rei |
| Grelhadu's, Flexas Bar, Quinta dos Avelanais | fechados para sempre |

E mesmo as quatro boas tinham publicações que eram **texto de marcação** — *"Foto do espaço
ou do prato do dia"* — em vez de imagens.

## O portão de identidade

Agora, para um negócio entrar, tem de passar as quatro:

1. **Está aberto** — `OPERATIONAL` no Google.
2. **É ele** — o nome do Google parece-se com o do mapa, comparado já sem as palavras de
   género (café, restaurante, cervejaria), com corte em 0,72.
3. **É aqui** — a ficha do Google fica a menos de **2 km** do ponto do mapa e a menos de
   20 km da Guarda.
4. **É do ramo** — o tipo do Google bate certo com a categoria, e há uma lista de tipos que
   nunca podem ser (sede de associação, repartição pública, localidade…).

Quem não passa fica **descartado com o motivo escrito**, não desaparece.

**Resultado nos 126:** 78 passam, **48 descartados** — 13 não eram o mesmo sítio, 12 estavam
fechados, 9 tinham nome diferente, 6 eram de outro ramo, 5 nem sequer eram um negócio.

## Fotos reais, publicações a sério

A função `ficha-google-diagnostico` passou à **v2**: devolve coordenadas, estado, tipos,
horário e os nomes das fotos públicas, e ganhou uma segunda ação que entrega a própria
imagem — a chave da Google continua a nunca sair do servidor.

Cada amostra tem agora as fotos da ficha do negócio na página e **duas publicações em
PNG 1080×1080** feitas com essas fotos.

### Três defeitos meus, apanhados antes do juiz

1. O véu escuro era um desfoque que fazia mancha; numa esplanada ao sol o título branco caía
   sobre fundo a 87 de brilho. Passou a gradiente firme **mais contorno preto no texto**, que
   resolve em qualquer fotografia.
2. A arte dizia **"Cafe · Guarda"**, sem acento, porque a categoria vive sem acentos na base.
3. A segunda peça dizia **"Estamos abertos"** e, por baixo, **"domingo: Encerrado"**. Ia
   buscar a primeira linha do horário sem olhar.

Sobre a última, a regra mudou de fundo: a nota do Google só se gaba com **20 ou mais
avaliações**. O nosso próprio diagnóstico diz que abaixo de 10 é um problema — gabar 9
contradizia a página ao lado.

## O juiz de visão

O Gemini olha para as duas imagens de cada amostra, sem saber quem as fez, e pontua: foto
mesmo do negócio (25), texto legível (25), texto honesto (25), sem pessoas reconhecíveis
(15), ar profissional (10). **Só passa com 85.**

- **Primeira volta:** 7 prontas, 3 chumbadas — LuMiar 58 e Dias dos Santos 63 por cara
  identificável em primeiro plano, CLGF 80 por composição amadora.
- **Segunda volta**, com outra foto da mesma casa: nenhuma das três passou. Saíram da lista,
  com o motivo escrito, e entraram A Petisqueira (97), Cortelha da Burra (100) e Zé da Praça
  (100). A Alameda também foi tentada e chumbou com 70, por pessoas em primeiro plano.

## As dez que ficaram

| Nota | Negócio |
|---|---|
| 100 | Arcada, Lanidor, O Jamie, Café Pissarra, Cortelha da Burra, Zé da Praça |
| 97 | Curt'ó Cheio Café, A Petisqueira |
| 96 | Café o Redondo |
| 93 | Café Dorna |

Das quatro que a revisão tinha aprovado, **três ficaram**. A **LuMiar saiu**: as suas duas
únicas fotografias no Google têm uma cara identificável em primeiro plano, e não há por onde
escolher. Fica no funil, sem amostra.

## Mais duas falhas minhas, da parte da manhã

1. A RPC `prospect_registar` gravava as notas mas **não o estado** — por isso os descartados
   continuavam marcados como novos. Migração nova: passa a aceitar o estado, e **nunca** deixa
   o robô escrever "enviado" nem "cliente". São 52 descartados, 64 novos, 10 com proposta.
2. Cada corrida criava uma proposta nova: havia **53 para 19 negócios**. Ficou uma por
   negócio. Cópia antes de apagar em `bkp_prospect_amostras_20260924` e
   `bkp_prospect_propostas_20260924`.

## Estado final

10 amostras, 10 propostas, **todas em rascunho, zero enviadas**. As páginas verificadas uma a
uma no ar, com as duas imagens e `noindex`.

## O que fica por dizer, com franqueza

As fotografias vêm da ficha pública do Google do próprio negócio. Em algumas aparecem
pessoas ao fundo, pequenas ou de costas — o juiz chumba quando há cara identificável em
primeiro plano, mas isto é julgamento de máquina, não uma garantia legal. Antes de qualquer
envio, vale a pena olhar para as dez imagens.
