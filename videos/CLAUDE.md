# Motion Studio — regras da casa (videos/)
> Escrito 2026-10-07 (missão "vídeos de propaganda em motion graphics puro"). Vale para tudo dentro de `videos/`.

## O que é isto
Vídeos de propaganda feitos **só com HTML/CSS/SVG/JS** num único `index.html` por projeto, animados **por tempo**
com uma função global `seek(t)` (t em segundos) que coloca a cena exactamente no instante t. Nada corre em tempo real:
o Playwright headless chama `seek(i/30)` frame a frame e tira screenshot; o ffmpeg cola os frames e o áudio.
**Proibido:** Remotion, Hyperframes, qualquer skill de vídeo, gravação de ecrã em tempo real, tiles de mapas de terceiros,
ícones de stock, imagens geradas por IA no lugar de capturas reais.

## Pipeline (ferramentas em `_tools/`)
| passo | ferramenta | nota |
|---|---|---|
| render de frames | `node _tools/render.js --html <proj>/index.html --w 1920 --h 1080 --dur 25 --out <proj>/frames_16x9 [--draft]` | lotes de 300 frames; fecha o browser entre lotes (PC de 4 GB) |
| áudio | `node <proj>/audio.js` → `out/<nome>_audio.wav` | síntese pura em Node (sine/noise/envelope) a partir do beat grid; ffmpeg faz loudnorm + mix |
| mux | `node _tools/mux.js --frames <dir> --audio <wav> --out <mp4> [--w --h]` | H.264, yuv420p, 30 fps, AAC 192k, `-shortest` |
| prova | `ffprobe` → `out/ffprobe.txt` + 3 frames lidos como imagem | duração, fps, resolução, stream de áudio |

Rascunho = `--draft` (viewport 854×480 ou 480×854, JPEG). Final = PNG a 1920×1080 e 1080×1920.
O `index.html` tem um **palco fixo** (1920×1080 ou 1080×1920 escolhido pela proporção do viewport) escalado com
`transform: scale()` para caber no viewport — assim o rascunho e o final são o mesmo desenho.

## (a) Qualidade de render
- Resolução exacta: 1920×1080 (16:9) e 1080×1920 (9:16). Nunca "quase".
- Sem frames caídos: o número de frames = `round(dur × 30)`; o render confirma a contagem no fim.
- Áudio alinhado ao frame: todos os eventos sonoros nascem do mesmo beat grid (`beatgrid.md`) que o `seek(t)` usa;
  o beat grid é a única fonte dos tempos. Um corte visual em t=4.00 tem o seu som em t=4.00, não "perto".
- Fontes carregadas do disco (`assets/fonts/Inter-VariableFont.ttf` do repo) por `@font-face`; `document.fonts.ready`
  é esperado antes do primeiro frame.
- Imagens (capturas, logos) pré-carregadas antes do primeiro frame — o render espera `window.__ready === true`.

## (b) Aparência — anti "cara de IA"
- **Cores e fontes reais da marca.** Bora: verde `#16A34A`, laranja `#F97316`, Inter, 1 laranja por ecrã (a acção
  principal). Em Dia: o semáforo (`#16A34A` em dia / `#F97316` a vencer / `#DC2626` passou), fundo `#F6F7F4`, texto
  `#111827`, Inter, cantos 16. Semente da Luz: o cânone em `C:\BoraLocal\BoraStudio\canon` (nomes, folhas, tema musical).
- Logos reais: `bora_app/assets/branding/bora_logo.png` (mascote na mota + BORA), `em_dia/assets/branding/icon.png`.
- **Nada de:** gradientes roxos/azuis genéricos, glow neon, partículas flutuantes, "glassmorphism" aleatório, ícones de
  stock, fotos de banco, texto com sombra 3D, fontes decorativas. Fundo claro e limpo como a app.
- Capturas de ecrã **reais** da app (Playwright no app web) dentro de uma moldura de telemóvel desenhada em CSS.
- A mota é a marca da Bora. **Nunca carro** (TVDE/boleias são de fora).
- Mapa da Guarda: desenhado em SVG (ruas simplificadas, praça, parque), sem tiles.
- Movimento: easings de UI real (`cubic-bezier(0.2,0.8,0.2,1)` / spring curto), overshoot ≤ 6 %, nada a flutuar sem
  razão. Cada elemento entra por um motivo (um toque, um corte na batida) e sai antes do próximo.

## (c) Som sincronizado
- Música sintetizada na batida (100–120 bpm; Em Dia mais lento, ~92). Kick/baixo nos tempos, sinos/plucks nas
  entradas de texto, hats nos contratempos.
- Efeitos nos cortes: `whoosh` em transições de cena, `pop` quando um cartão/elemento salta para o ecrã, `ding` em
  confirmações (pedido confirmado, "em dia"), `tick` em digitação. Cada um alinhado ao grid.
- Fecho: a música resolve no último acorde junto do CTA; nunca corta a seco.
- Loudness alvo −14 LUFS (ffmpeg `loudnorm`), pico −1 dBTP.

## (d) LOOP OBRIGATÓRIO de avaliação
1. Render de rascunho (`--draft`, 480p).
2. Ler 6–8 frames-chave como imagem + conferir a duração dos beats contra o `beatgrid.md`.
3. Notas 1–10 em: **ritmo · legibilidade · marca · som · "parece IA?"** (10 = não parece nada).
4. Corrigir os 3 piores pontos; repetir até **tudo ≥ 8**. Só então render final nas duas proporções.
5. Cada volta fica em `<proj>/notas.md` (data, notas, o que se mudou).

## Estrutura por projeto
```
videos/<projeto>/
  index.html        o vídeo (palco responsivo 16:9 / 9:16, seek(t))
  audio.js          gera out/<nome>_audio.wav a partir do grid
  beatgrid.md       tabela segundo a segundo (o que aparece, texto, som)
  referencias.md    2 referências de linguagem visual (nunca copiar conteúdo)
  notas.md          as voltas do loop de avaliação
  BRAND.md          logo, tipografia, cores, estilo de movimento (no fim)
  assets/           capturas reais, logos, LISTA.md
  out/              <nome>_16x9.mp4, <nome>_9x16.mp4, ffprobe.txt
```

## Memória (PC de 4 GB)
- Um browser de cada vez; o render relança o Chromium a cada 300 frames.
- Rascunho sempre antes do final; os frames do rascunho apagam-se depois de avaliados.
- Frames finais apagam-se depois do MP4 provado pelo ffprobe (são regeneráveis).

## Lições desta missão (2026-10-07) — cicatrizes
- **`position:absolute` sem `top/left` fica na posição estática.** Se houver um SVG/div em fluxo antes (o cenário), o
  elemento cai por baixo dele e sai do palco. Em todos os clips: `.el { position:absolute; left:0; top:0 }`.
- **Transform de base + transform de animação:** o `apply()` substitui `style.transform`; um `translateX(-50%)` do CSS
  perde-se. Guardar em `el.dataset.base` (centrar) antes de animar.
- **CSS `left` + lerp a partir do mesmo valor = deslocação dupla** (o carro do Em Dia nasceu em −520 duas vezes).
- **ffmpeg 9:** `-vsync` já não existe → `-fps_mode vfr`. `drawtext` sem fontconfig falha no Windows (não usar).
  Vários `-i` com vários outputs: cada output apanha o *melhor* stream, não o "seu" — um `ffmpeg` por imagem.
- **Logo com fundo branco** (bora_logo.png) só vive sobre branco; palco branco ou cartão branco.
- **App web sem sessão não chega à home** (convidado partido em produção): a home vem do golden real da app.
- Render 1080p PNG: ≈110 s por 750 frames (16:9) neste PC; 9:16 ≈140 s. Rascunho 480p: ≈26 s.
