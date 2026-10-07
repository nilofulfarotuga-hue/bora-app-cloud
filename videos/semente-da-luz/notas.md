# Notas do loop — D3 A Semente da Luz (4 clips)

## Volta 1 — 2026-10-07 (frames-chave 854×480 dos 4 clips)
| critério | nota | porquê |
|---|---|---|
| ritmo | 7 | abertura: as crianças entravam de fora do ecrã e quase não se viam; fecho: rolo ok |
| legibilidade | 4 | **as personagens não apareciam nas 2 cenas** (elementos `position:absolute` sem `top/left` ficavam na posição estática, por baixo do SVG do cenário → fora do palco); legenda do s12 ocupava o ecrã inteiro (mesma causa) |
| marca (cânone) | 8 | recortes das folhas aprovadas (cabelo, flores da Tabita, polo às riscas do Gustavo), cartão BORA STUDIO do v5, azul+dourado do portal, nomes do elenco, atribuições obrigatórias |
| som | 8 | tema real de abertura (9,5/10 do juiz) a entrar com o `portal.wav` real; `estrondo.wav` real; falas reais s12_1/s12_2 |
| parece IA? | 7 | os fundos vectoriais são simples e honestos; o portal é um gradiente radial com blur (aceitável: é o "clarão azul e dourado" do roteiro) |
**Corrigido:** `.el { left:0; top:0 }` em todos os clips; crianças da abertura começam visíveis nas margens e são puxadas em 2,6 s; rótulo "A SEMENTE DA LUZ" do fecho só nos primeiros 2,8 s (deixava de se ler por cima do rolo); legenda com `top:auto`.

## Volta 2 — frames 3.4/4.6/6.0/7.4 (abertura), 0.7/2.6/4.0/6.5 (s02), 0.6/2.0/5.4/7.2 (s12), 4.6/9.5 (abertura 9:16)
ritmo 8 · legibilidade 8 · cânone 8 · som 8 · IA? 8 → render final dos 4 clips nas duas proporções.

## Limites honestos (abaixo de 10 e porquê)
- Os recortes são **estáticos** (sem boca/olhos animados): "falar" é um pulsar de 1,2 %. É o que as folhas permitem sem redesenhar.
- O s02 não tem falas (no roteiro v7, s02 é só acção + o cão); o cão Vento não tem folha aprovada → não aparece.
- O nome do Episódio 1 não existe no roteiro v7 (só "Episódio 1") → o cartão fica "Episódio 1".
