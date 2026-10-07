# Beat grid — D1 Bora "Pedido a caminho" · 25 s · 120 bpm (1 tempo = 0,5 s · 1 compasso = 2 s)
> A única fonte dos tempos. `index.html` (seek) e `audio.js` leem daqui. Tom: Sol maior (G–Em–C–D), sinos + pluck,
> kick nos tempos 1 e 3, hats nos contratempos, baixo na fundamental.

| t (s) | compasso | o que aparece | texto no ecrã | som |
|---|---|---|---|---|
| 0.00 | 1 | fundo claro; logo Bora (mascote na mota) salta ao centro com overshoot 5 % | — | kick + **pop** (logo) · música arranca |
| 1.00 | 1.3 | pílula verde-claro desliza por baixo do logo | "Entregas rápidas em Portugal" | pluck G4 |
| 2.00 | 2 | **corte** → logo encolhe para o canto; telemóvel (captura real: grelha da home) entra da direita | caption: "Escolhe no app" | **whoosh** + kick |
| 3.00 | 2.3 | dedo toca no tile "Restaurantes"; tile faz bounce | — | **pop** |
| 3.50 | 2.4 | ecrã muda para a lista de pratos (UI reconstruída com os componentes da app) | "Restaurantes" · pratos com "exemplo" | pluck B4 |
| 5.00 | 3.3 | dedo toca "Adicionar"; botão verde comprime; badge do carrinho salta "1" | — | **pop** + bell D5 |
| 6.00 | 4 | **corte** → cartão branco grande com check verde a desenhar-se (stroke) | "Pedido confirmado" | **ding** A5 + kick |
| 7.00 | 4.3 | linha 2 aparece por baixo | "A loja já está a preparar" | pluck G4 |
| 8.00 | 5 | no telemóvel: barra de estado do pedido avança 2 passos | "Preparar → Estafeta a caminho" | hats |
| 9.00 | 5.3 | **corte** → o telemóvel sai, o mapa da Guarda (SVG) abre com zoom de 1.0 → 1.35 | — | **whoosh** (descendente) + kick |
| 9.50 | 5.4 | pino da loja salta | "Loja" | **pop** |
| 10.00 | 6 | a mota (SVG, verde Bora, capacete branco, caixa com B) arranca pela Rua 31 de Janeiro; câmara segue com atraso | caption: "O estafeta sai da loja" | kick forte + arpejo de sinos (G–B–D) em cada tempo |
| 12.00 | 7 | passa pela Praça Velha / Sé (rótulos desenhados) | — | sinos continuam |
| 13.00 | 7.3 | caption troca | "…e atravessa a Guarda" | pluck |
| 14.00 | 8 | balão ETA sobre a mota | "4 min" → "2 min" (16.0) | hats + bell |
| 16.00 | 9 | mota chega ao pino da casa; trava com pequeno derrapar; pino salta | "Casa" | **pop** + kick |
| 16.50 | 9.2 | notificação no estilo da app desce do topo | "O teu pedido chegou 🛵" (sem emoji — ícone de sino) | **ding** E6 |
| 17.25 | 9.3 | caption | "Entregue à porta" | pluck |
| 18.50 | 10.2 | **corte** → fundo branco limpo; mapa sai com fade rápido | — | **whoosh** |
| 18.75 | 10.3 | linha 1 grande | "Olá!" | bell G5 |
| 19.50 | 10.4 | linha 2 grande | "O que precisas hoje?" | pluck + kick |
| 20.50 | 11.2 | cartão laranja (o único laranja do ecrã) salta com o código | "Código BEMVINDO" · "5 € no primeiro pedido" | **pop** + **ding** |
| 22.00 | 12 | **corte** → fundo verde Bora; título | "Instala a Bora" | kick + acorde G |
| 22.50 / 22.75 / 23.00 | 12.2–12.3 | 3 badges saltam em sequência | "Google Play" · "App Store" · "app.boraguarda.com" | **pop** ×3 (subindo G4-B4-D5) |
| 23.50 | 12.4 | logo Bora pequeno em baixo | — | acorde final G (resolve) |
| 24.00–25.00 | 13 | tudo parado; música cai em cauda | — | cauda do acorde, sem corte seco |

## Beats da música (para o `audio.js`)
- Kick: tempos 1 e 3 de cada compasso (t = 0, 1, 2, …) de 0 a 23; mais forte em 10.0 e 16.0.
- Hat fechado: contratempos (t = 0.25, 0.75, …) de 2 a 23.
- Baixo: fundamental do acorde no tempo 1 de cada compasso (G2, E2, C2, D2 em ciclo de 4 compassos).
- Sinos (arpejo G4-B4-D5-G5): só entre 10.0 e 16.0, um por tempo.
- Pad suave: acordes G-Em-C-D de 2 em 2 s desde 0 até 24, resolve em G em 22.0 com fade até 25.
