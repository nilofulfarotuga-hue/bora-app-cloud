# BRAND — Bora (vídeos D1 "Pedido a caminho" e "Bora Assistente")
> Fechado 2026-10-07 depois do render final. Tudo vem do repo `bora_app`; nada inventado.

## Logo
- `assets/branding/bora_logo.png` — mascote (capacete branco, mota verde, caixa com "B" laranja) + "BORA" (BO verde, RA laranja).
  Tem fundo branco, por isso vive sempre sobre branco (palco branco ou cartão branco no CTA verde).
- `web/icons/Icon-512.png` — ícone da app (usado na notificação e no cabeçalho do chat).
- **A mota é a marca.** Nunca carro.

## Tipografia
- Inter (`assets/fonts/Inter-VariableFont.ttf`), pesos 500 (subtítulos), 700 (UI), 800/900 (títulos, letter-spacing −0.02 a −0.03 em).
- Títulos: 96–160 px em 1080p. Subtítulos 36–40 px. UI do telemóvel: 15–22 px (× 1.25 no palco).

## Cores
| uso | hex |
|---|---|
| verde Bora (acções, pins, fundo do CTA) | `#16A34A` |
| verde escuro (texto sobre verde-claro) | `#15803D` |
| verde-claro (pílulas, fundos de chip) | `#DCFCE7` |
| laranja (UM por ecrã: badge do carrinho, cartão BEMVINDO, botão "Encher o carrinho") | `#F97316` |
| texto | `#111827` · secundário `#6B7280` |
| fundo da app / ecrã do telemóvel | `#F6F7F4` · palco branco `#FFFFFF` |
| mapa | fundo `#EDF1E8`, quarteirões `#E2E7DD`, ruas brancas com casing `#D3D9CD`, jardim `#CBE7CF` |
| badges de loja | `#0B0F14` |

## Componentes
- Cartões brancos, cantos 16 (UI) / 28–32 (palco), sombra `0 2px 8px rgba(15,23,42,.06)` (UI) e `0 30px 80px rgba(15,23,42,.16)` (palco).
- Telemóvel: moldura `#0B0F14`, cantos 56, ecrã cantos 46, ilha de 120×30.
- Toque: círculo branco translúcido com anel verde (escala 1.4 → 1 → 0.8 → 1.1 e some).

## Movimento
- 120 bpm. Cortes só nos tempos. Entradas com `pop` (overshoot ≈ 4 %), saídas com `in` (cúbico) em 0.2–0.3 s.
- Um elemento entra de cada vez; os badges do CTA entram em sequência de 0.25 s.
- Mota: segue uma rota SVG com `getPointAtLength`, inclina 1.2° com o tempo, trava com −6° em decaimento; rodas giram pelo comprimento percorrido. Câmara com atraso (`io` 1.3 s) e zoom 1.0 → 1.35.
- Mapa: Guarda desenhada (Sé, Praça Velha, Rua 31 de Janeiro, Jardim José de Lemos, Av. Cidade de Salamanca, Torre de Menagem), sem tiles.

## Som
- Sol maior, kick nos tempos 1 e 3, hats nos contratempos, baixo na fundamental, pad + teclas no contratempo, sinos em arpejo na viagem.
- SFX: `pop` (seno 900→250 Hz, 90 ms) em cartões/toques, `whoosh` (ruído filtrado) nos cortes, `ding` (sino A5/E6) em confirmações, `tick` na digitação.
- Loudness −14 LUFS / −1 dBTP (`loudnorm` no mux).

## O que é reconstruído (não é captura)
Lista de pratos, barra de estado do pedido, chat do Assistente e cartões de loja: desenhados com os componentes acima; preços sempre marcados "exemplo".
