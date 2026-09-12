# Hermes — Acesso web via Chrome

Chrome do sistema configurado para uso autónomo do Hermes.

- **Binário:** `C:\Program Files\Google\Chrome\Application\chrome.exe`
- **Versão:** 146.0.7680.178 · **Node:** v24.14.1
- **Env (em `.claude/settings.local.json`):** `CHROME_PATH`, `CHROME_BIN`,
  `PUPPETEER_EXECUTABLE_PATH`, `PUPPETEER_SKIP_DOWNLOAD=true`

## Ordem de preferência para pesquisa web

1. **WebSearch** (tool nativa) — pesquisa rápida, já permitida.
2. **ctx_fetch_and_index** (context-mode) — buscar + indexar página sem encher o contexto.
3. **Chrome headless** — quando é preciso renderizar JS / scraping dinâmico.

## Chrome headless — comandos diretos

```bash
# HTML renderizado (DOM já com JS executado)
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu \
  --no-sandbox --dump-dom "https://site.com"

# Screenshot
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu \
  --no-sandbox --screenshot=/c/Users/danil/Downloads/shot.png \
  --window-size=1280,1024 "https://site.com"

# PDF
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu \
  --no-sandbox --print-to-pdf=/c/Users/danil/Downloads/page.pdf "https://site.com"
```

## Playwright / Puppeteer (scraping com lógica)

Usar o Chrome do sistema, **sem** descarregar Chromium:

```js
// Playwright — usa o canal 'chrome' instalado
const { chromium } = require('playwright');
const browser = await chromium.launch({ channel: 'chrome', headless: true });

// Puppeteer — lê PUPPETEER_EXECUTABLE_PATH automaticamente do env
const browser = await puppeteer.launch({ headless: 'new' });
```

Instalar driver Playwright só quando necessário: `npx playwright install chrome`
(o binário Chrome já existe; isto instala apenas o conector).

## Notas

- Reversível: remover o bloco `env` e as 2 permissões em `settings.local.json` desliga tudo.
- Não usar para login em contas / áreas autenticadas sem aprovação do Danilo.
