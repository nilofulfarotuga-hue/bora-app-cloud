# BRAND — Em Dia (vídeo D2)
> Fechado 2026-10-07. Fonte: `C:\BoraLocal\projetosflutter\em_dia\lib\config\app_theme.dart` + `app_colors.dart` + goldens reais.

## Logo
- `assets/branding/icon.png` — calendário verde com check (cantos 52 no palco). Não há wordmark: o nome escreve-se em Inter 900 `#15803D`.

## Tipografia
- Inter em tudo (`AppTheme.fonte = 'Inter'`, lição do Bora: nunca `fontFamily: null`). Títulos 80–120 px, 800/900; subtítulos 36–40 px, 500.

## Cores — o semáforo é a gramática
| uso | hex |
|---|---|
| em dia (resolvido, check, botões) | `#16A34A` · escuro `#15803D` · claro `#DCFCE7` · wash `#F0FDF4` |
| a vencer (chips, prazos próximos) | `#F97316` · claro `#FFEDD5` |
| passou (prazo passado) | `#DC2626` · claro `#FEE2E2` |
| fundo | `#F6F7F4` · superfície `#FFFFFF` · superfície 2 `#F1F3EF` · divisor `#E5E7EB` |
| texto | `#111827` · secundário `#6B7280` · subtil `#9CA3AF` |
| info / cadeado Pro | `#2563EB` / `#7C3AED` (não usados no vídeo) |

Regra: o laranja só aparece como "a vencer" e vira verde quando fica resolvido (chips 3.33 → 4.67 s). Nunca como decoração.

## Componentes
- Cantos 16; sombra `0 2px 8px rgba(15,23,42,.08)`.
- Ecrãs reais dos goldens (1170×2532) dentro da moldura `#0B0F14`; deslizam como tabs (0.5 s, `soft`).
- Notificação no estilo do push real (`pushCarro`).
- Carro 2D verde `#16A34A` com vidros `#DCFCE7` e etiqueta "TVDE" — o Em Dia é para motoristas TVDE, por isso o carro aqui é correcto (a regra "nunca carro" é da Bora).

## Movimento
- 90 bpm, tranquilo: easing `soft` (quártico) nas entradas, `pop` só nos chips/badges. Um ecrã por frase (bar 1 / 2.5 / 4 / 5.5 / 7 / 8).
- Contador 0 → 989,70 € em 1,5 s com ticks.
- Fecho parado 2,5 s antes do CTA.

## Som
- Fá maior (Fmaj7–Am7–Dm7–B♭maj7), teclas arpejadas 1 nota/tempo, kick macio no tempo 1, hats em escova, pluck nas captions, sino quando o check aparece. −14 LUFS.

## CTA
Google Play (`pt.emdia.app`) + `app.emdia.boraguarda.com` + "Mês grátis para experimentar" (trial de 30 dias é do servidor). Sem App Store até a Apple aprovar.
