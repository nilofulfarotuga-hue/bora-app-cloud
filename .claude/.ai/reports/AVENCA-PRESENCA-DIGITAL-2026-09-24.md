# Presença Digital Bora — preparação da avença (24/09/2026)

> Missão `agente-avenca-preparacao-2026-09-24`. Fluxo do `e2e_log` com o mesmo nome.
> **Nada foi enviado a ninguém. Nenhum produto ou preço foi criado no Stripe.**

## A ideia, em três linhas

A Bora já faz para si própria, todos os dias e por robô, aquilo que os negócios da Guarda
pagam a agências para fazer: publicações no Instagram e Facebook, um mini-site, a ficha do
Google tratada e atendimento por WhatsApp. Vender isso por **149 € por mês, sem
fidelização**, é uma linha de dinheiro que usa máquinas que já existem e já estão pagas.
Referência de mercado em Portugal: 150 a 600 € por mês.

## O que ficou pronto

| | Número |
|---|---|
| Negócios encontrados (raio 20 km da Guarda) | 126 |
| Sem site | 97 |
| Fichas do Google conferidas uma a uma | 45 |
| Amostras completas, com link único | 10 |
| Rascunhos de proposta | 10 |

## O erro que esta missão apanhou a tempo

A primeira pontuação saiu só do **OpenStreetMap** e estava errada de alto a baixo. O
"melhor candidato" era o **Restaurante Belo Horizonte**, marcado como sem site e sem
telefone. Na ficha do Google tem site, telefone, horário, 10 fotografias e **1112
avaliações com 4,6 estrelas**.

Se as propostas tivessem saído nessa lista, a primeira coisa que aquelas pessoas liam era a
Bora a dizer-lhes que não têm presença online — sobre um negócio com mais avaliações do que
a própria Bora. **Das 45 fichas conferidas, 12 estavam completas.** Eram 12 portas fechadas
na cara, e ficámos a dever isso a uma conferência de dois minutos.

Por isso a pontuação passou a sair da **ficha real do Google**, e só depois disso é que se
escolheram os 10.

## Como se faz, por dentro

1. **`prospectar.py`** — pergunta ao OpenStreetMap (a base de mapas pública) que negócios
   existem num raio de 20 km: restaurantes, cafés, cabeleireiros, oficinas, pneus, ginásios,
   clínicas, alojamentos. Só fichas com nome. Guarda em `prospects_presenca`.
2. **`enriquecer.py`** — para os melhores, pergunta ao Google o que a ficha tem mesmo, pela
   Edge Function nova **`ficha-google-diagnostico`** (a chave da Google fica do lado do
   servidor e nunca sai). Volta a pontuar com a verdade: metade oportunidade, metade
   conseguirmos falar com eles — um negócio sem forma de contacto não é oportunidade, é uma
   parede.
3. **`amostras.py`** — escreve, para cada um dos 10, uma página privada em
   `boraguarda.com/avenca/<token>/` com: o que o Google mostra hoje, o mini-site que a Bora
   lhe faria, e **duas publicações já escritas**. Regista a amostra e deixa a proposta em
   **rascunho**.

As páginas têm `noindex` e não estão ligadas de lado nenhum do site: só lá chega quem tiver
o link. Um token inventado devolve 404.

## Custo real

A conferência das 45 fichas gastou **45 chamadas à Places API**, cerca de **1,44 €** na
conta Google do Danilo. É o único dinheiro que esta missão gastou, e comprou a informação
que evitou as 12 propostas falsas.

## O que está guardado, e onde

- **Base:** `prospects_presenca`, `prospect_amostras`, `prospect_propostas` (RLS: só o admin
  lê; quem escreve é o robô, por chave no Vault).
- **Painel admin (PT-BR):** secção **Avenças** — a lista com pontuação, a amostra e o texto
  da proposta de cada um. **Não tem botão de enviar, de propósito.**
- **Provas:** `.claude/.ai/provas/agente-avenca-preparacao-2026-09-24/`.

## Para o Danilo decidir

1. **Ler dois ou três rascunhos** na secção Avenças e dizer se o tom serve. Estão escritos
   em nome da Bora, em português de Portugal, curtos, e a dizer "fizemos isto para vocês,
   vejam" — nunca "sou o Danilo".
2. **Como chegar lá.** Dos 10, seis têm telefone na ficha. Os outros quatro só com visita.
3. **Só depois disso** é que se fala de enviar seja o que for. Enquanto não disseres, fica
   tudo em rascunho.
