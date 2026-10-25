---
name: proposta-diaria
description: A linha de produção das propostas da Guarda. Dado APENAS o nome de um negócio (idealmente já em alvos.csv), executa a ronda completa - recolhe e diagnostica (Bloco B), constrói a maquete premium (Bloco C), prova e publica em proposta-<slug>.boraguarda.com (Bloco D) e escreve a peça de venda SEM enviar nada (Bloco E). Triggers - "proposta para X", "faz a maquete do X", "próximo alvo", "corre a linha de propostas".
metadata:
  type: procedural
  zona: verde
  origem: missao propostas-3-por-dia, 2026-08-31
  execucoes: 3
  sucessos: 3
  falhas: 0
  ultima_execucao: 2026-08-31
---

# PROPOSTA DIÁRIA — a linha que faz 3 negócios por dia

> Nascida na missão `propostas-3-por-dia` (2026-08-31), onde correu inteira
> para Herdade do Mondego, Imoaugusto e Quinta do Rio Noémi.
> Regra-mãe: **nunca mais contacto vazio. Primeiro mostra-se, depois fala-se.**
> Método-pai: skill `site-premio` (repo bora-site) — nenhum passo do funil se salta.
> **NADA SE ENVIA A NINGUÉM.** As mensagens escrevem-se em ficheiro; o envio é do Danilo.

## Onde vive tudo

- Pasta de trabalho: `C:\BoraLocal\projetosflutter\propostas\`
- Ferramentas: `propostas\ferramentas\` (capturar, descarregar_site, sacar_fotos_booking,
  medir_lcp, folha_contacto, embutir_imagens, video_kenburns, segunda_ronda, publicar)
- Referências de nicho + design systems: repo bora-site em `referencias/`
  (`DESIGN-SYSTEM-turismo-rural.md`, `DESIGN-SYSTEM-imobiliaria-premium.md`,
  subpastas `nicho-*` para o fiscal)
- Fiscal visual: bora-site `tools/fiscal-visual/fiscal.py`
- Gerador de PDF: bora-site `tools/proposta/proposta.py`
- Python: `%LOCALAPPDATA%\Programs\Python\Python312\python.exe` · ffmpeg: `C:\BoraLocal\BoraStudio\_bin\ffmpeg.exe`
- Tokens Cloudflare: `.env` do repo bora-site (Pages + DNS) — NUNCA committar
- Fila de alvos: `propostas\alvos.csv` — marca `contactado`/`estado` para nunca repetir

## A ronda, passo a passo

### 0. Escolher o alvo e abrir a pasta
1. Lê `alvos.csv`; escolhe o primeiro `na fila` (ou o nome que a ordem der).
2. Cria `propostas\<slug>\{antes,media,site,prova,venda}`.
3. Lê a skill `site-premio` inteira + o DESIGN-SYSTEM do nicho. Corre o
   classificador (§2) e escreve as 4 linhas de saída.

### 1. Recolher sem inventar (Bloco B)
- `descarregar_site.py <url> <slug>\antes\site 12` — HTML + imagens + inventário.
  (Se der 429, refazer devagar com pausas de 15-25s — a Herdade precisou.)
- `capturar.py` em todas as páginas → `antes\antes-*-{1440,390}[-full].png`.
- Booking/Airbnb/Google Maps pelo painel do browser: nota, nº avaliações,
  tipologias, preço, 5 melhores citações COM nome e origem (guardar também as
  em inglês — são a prova do cliente estrangeiro). Booking: versão .en-gb.html
  dá as citações EN. Google Maps: /maps funciona sem sessão; /search dá captcha.
- Fotos: galeria do Booking via JS no painel (IDs+hash) → `sacar_fotos_booking.py`;
  imagens do site do próprio; logótipo SEMPRE do site oficial (SVG > PNG grande;
  cuidado: o eGO serve um placeholder "WEB LOGO" — verificar com os olhos).
- `medir_lcp.py <url>` → peso e LCP do antes.
- Auditoria legal/técnica por grep ao HTML: livroreclamacoes, cookies/RGPD,
  JSON-LD, hreflang, og:image, favicon, redes sociais, telefones, emails.
- Escreve `diagnostico.md`: o que está mal e o que custa em dinheiro,
  em português simples. Factos só com fonte; conflitos ficam "POR CONFIRMAR".

### 2. Construir (Bloco C)
- Escreve o prompt longo (`prompt-<slug>.md`) ANTES de qualquer HTML.
- `folha_contacto.py` para escolher fotos COM OS OLHOS; nunca associar foto a
  quarto/casa sem o site do cliente o confirmar.
- Template `site\index-template.html` com placeholders `__IMG_x__` (+ width/
  height automáticos), manifesto `imagens-mapa.json`, `embutir_imagens.py`
  → index.html self-contained (WebP base64; alvo < 2 MB).
- Obrigatórios: PT+EN (4 línguas se o cliente já as tiver), formulário-WhatsApp
  (wa.me com mensagem pronta), secção honesta da comissão (~15%, contas de
  exemplo), avaliações reais com nome e origem, JSON-LD do nicho, noindex +
  robots Disallow + `_headers` X-Robots-Tag, 404, favicon, og.jpg real,
  marca de água "Proposta — Bora", rodapé com livroreclamacoes.pt e link
  discreto boraguarda.com/trabalhos.
- Vídeo: `video_kenburns.py <out> <fotos...> --dur 3.4` (JÁ corrigido: uma
  frame por foto; com -loop saíam 30 minutos e 128 MB). Guarda-rail: >1 MB e
  <25 MB. Vídeo em `assets/video/` com poster real — NUNCA base64.

### 3. Provar e publicar (Bloco D)
- Servidor local: preview `propostas` (launch.json) → localhost:8765.
- `fiscal.py <url-local> --nome proposta-<slug> --ref referencias\nicho-<nicho>`
  — compara captura contra captura. Corrigir os médios (contraste AA, alvos
  44px, letra ≥13px no telemóvel, width/height, links mortos, canonical) —
  o `segunda_ronda.py` já aplica esta família de correções.
- SEGUNDA RONDA É OBRIGATÓRIA: rever com o prompt na mão, corrigir, re-embutir.
- Publicar: `publicar.ps1 -Projeto proposta-<slug> -Pasta <site> -Dominio
  proposta-<slug>.boraguarda.com` (cria projeto Pages + wrangler deploy +
  domínio + CNAME proxied; usa Invoke-RestMethod — curl.exe parte o JSON).
- Auditar SÓ uns segundos DEPOIS, pelo domínio final, ao CONTEÚDO (nunca ao
  código de resposta): nome do cliente no HTML, noindex meta+header, vídeo
  >1MB vivo, og.jpg, robots, 404 próprio, wa.me, livro de reclamações.
- `capturar.py` no domínio final → `prova\depois-*.png`; `medir_lcp.py` → LCP
  do depois; compor antes/depois lado a lado (1440 e 390) em `prova\`.
- `prova\CHECKLIST.md` assinada — se um item estiver vermelho, corrige e
  volta a provar. Não se reporta "feito" com vermelhos.

### 4. Peça de venda (Bloco E) — escrever, NÃO enviar
- `venda\proposta.json` → `python tools\proposta\proposta.py` → PDF (SEM preço).
- Vídeo vertical 20-30s (1080×1920): scroll do antes vs scroll do depois a
  partir das capturas -390-full (`video_vertical.py`), sem caras nem narração.
- `PARA_ENVIAR.md`: link da maquete, ficha de contacto (email/telefone/
  WhatsApp/pessoa certa/melhor hora) e as 3 mensagens (email, WhatsApp,
  Instagram) — falar do negócio DELE, uma frase sobre o problema, o link,
  fecho leve. Zero linguagem de vendedor, zero preço.

### 5. Fecho da ronda
- Atualiza `alvos.csv` (estado=maquete-no-ar + data).
- `git add -A && git commit` no repo propostas NO MESMO DIA.
- Regista no Córtex (`cortex_reportar`) com o link da maquete.
- Telemetria: incrementa execucoes/sucessos neste frontmatter.

## Cicatrizes desta linha (não repetir)

- **curl.exe + JSON no Windows = corpo sem aspas** → Invoke-RestMethod.
- **zoompan com -loop/-t** multiplica frames → vídeo de 30 min/128 MB.
- **Logo do eGO pode ser o placeholder "WEB LOGO"** — confirmar com os olhos.
- **Sites pequenos (nginx) dão 429** a crawl rápido — pausas de 15-25s.
- **Instagram sem sessão esconde seguidores; o Facebook mostra.**
- **Google /search dá captcha ao browser automatizado; /maps funciona** —
  e captcha NUNCA se contorna: muda-se de fonte.
- **O painel do browser tira screenshots em branco depois de scroll por JS**
  — verificar pelo DOM ou pelo fiscal, não insistir no screenshot.
- Screenshots de referência com banner de cookies: tratar_cookies só RECUSA;
  se não houver botão de recusa, esconder overlays só para a foto.

## Para o Danilo

Esta skill não decide preços nem envia mensagens. O que sai dela fica em
`propostas\<slug>\PARA_ENVIAR.md` e `venda\*.pdf` — abrir, escolher, mandar.
