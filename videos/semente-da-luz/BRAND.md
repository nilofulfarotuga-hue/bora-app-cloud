# BRAND — A Semente da Luz (clips D3)
> Fechado 2026-10-07. Cânone em `C:\BoraLocal\BoraStudio\canon` (só leitura). Nada do BoraStudio foi alterado.

## Identidade
- **Estúdio:** cartão "BORA STUDIO / apresenta" — laranja `#FF8C00` sobre noite `#12121C`, bege `#F2E4C6` (igual a `renders/v5/logo.png`).
- **Título:** "A SEMENTE DA LUZ" em Inter 900, dourado `#FFD54F`, espaçamento .06 em, brilho suave; subtítulo "UMA SÉRIE DE ANIMAÇÃO" azul-claro `#CFE8FF`, .3 em.
- **Portal / clarão:** radial dourado `#FFD54F` → azul `#4FC3F7` (o "clarão azul e dourado" do roteiro), anel dourado.
- **Personagens:** recortes de frente das folhas aprovadas `refs/{antony,tabita,tailine,gustavo}_folha.png` (fundo branco removido por colorkey). A folha é a verdade: cabelo, roupa, flores, riscas.

## Cores dos cenários
- Sótão: paredes `#1B120B → #4A3321`, vigas `#6B4A2E`, chão `#3B2A1C`, janela noite `#1E2A52`.
- Casa da avó: parede `#F3E5C8`, chão `#C9955B`, caixas `#D2A775 / #DDB383 / #C89A68`, estante `#A9774A`.

## Tipografia
Inter (900 títulos, 800 nomes, 600 secções em caixa alta espaçada). Legendas: 44 px branco em caixa `rgba(0,0,0,.62)`, nome da personagem em dourado.

## Movimento
- Abertura segue a spec `canon/abertura_serie.md`: teaser frio → **a música entra com o whoosh do portal** → genérico (crianças e papéis em espiral) → cartão do episódio.
- Cut-out: tremer contra o vento (seno 14 Hz × 5 px), inclinação 14°, puxão com `inq` + rotação 160° + escala → 0.08; na casa, pulsar 1,2 % a 22 Hz durante a fala, cabeça 6° para a caixa.
- Créditos: rolo linear 12 s + cartão final 3 s.

## Som
- `saida/tema_abertura_v4.wav` (abertura 0→9,5 s a partir dos 2,5 s; fecho últimos 15 s), `saida/v4/sfx/portal.wav` e `estrondo.wav`, falas reais `saida/v4/voz/s12_1.wav` e `s12_2.wav`.
- Leitos sintetizados: drone Ré menor (abertura/s02), vento filtrado + risers (s02), teclas em Fá + sino (s12). −14 LUFS no mux.
