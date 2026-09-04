# BLOCO C — Visibilidade jaiagarwala.com (2026-09-05)

Missão manual · Modo Protecção Total · projeto `jai-site` (não é o bora_app; caminho
`C:\BoraLocal\projetosflutter\jai-site`, junção `C:\BoraLocal\QG\site-jai`).
Regras do `radar-jai/REGRAS.md` respeitadas: nenhuma consulta automática ao Google para
medir posição, nenhuma edição na Wikipédia, nada publicado em nome do Jai sem aprovação.

## TAREFA 1 — Medição real (fetch ao vivo, sem JS)

| Item | Medido | Prova |
|---|---|---|
| URLs no sitemap | **12** | `curl https://jaiagarwala.com/sitemap.xml` → 12 `<loc>` |
| /pt /es /hi | **Estáticas e indexáveis** (geradas em build, não trocam só no browser) | HTML cru sem JS: `<html lang="pt">`/`es`/`hi`; corpo em PT tem 3× "acionista maioritário" |
| hreflang | **Correcto** em todas as páginas (en/pt/es/hi/x-default), incl. nas próprias páginas /pt/ /es/ /hi/, não só na home | visto no `<head>` servido de `/pt/` |
| llms.txt | **Existe, HTTP 200** | `curl -o /dev/null -w "%{http_code}"` → 200 |
| robots.txt | **Permite 16 User-agents**, incluindo GPTBot, ClaudeBot, PerplexityBot, Google-Extended, Bingbot, CCBot, Applebot-Extended, meta-externalagent | HTTP 200, 16 linhas `User-agent:` |
| Bing Webmaster | **Sem acesso ao painel nesta sessão** (sem MCP/login). Evidência local: chave IndexNow `6443874a594d4ff28f826cf921cbcb94.txt` **ao vivo, HTTP 200**, conteúdo confere. Relatórios anteriores (31/08 e 01/09) documentam ligação feita via import do GSC e sitemap "Success" com 12 URLs — não reconfirmado ao vivo por falta de acesso ao painel agora. |
| IndexNow | Chave viva confirmada; submissão de teste feita agora (ver Bloco 2) devolveu **HTTP 200** | `curl -X POST https://api.indexnow.org/indexnow` |

## TAREFA 2 — Correcções aplicadas (sem tráfego artificial ao Google)

**Defeito real encontrado:** a tag `<title>` da home nunca era traduzida — /pt/, /es/ e
/hi/ serviam sempre `"Jai Agarwal — Sports Entrepreneur · Football Club Owner"` em inglês
no separador do browser e nos resultados de pesquisa, apesar do resto da página estar em
PT/ES/HI. Corrigido:
- `index.html`: `<title>` passou a `data-i18n="metaTitle"`.
- Nova chave `metaTitle` em `i18n/pt.json`, `es.json`, `hi.json`.
- **Prova ao vivo pós-deploy:**
  - EN: `Jai Agarwal — Sports Entrepreneur · Football Club Owner`
  - PT: `Jai Agarwal — Empresário do Desporto · Proprietário de Clube de Futebol`
  - ES: `Jai Agarwal — Emprendedor Deportivo · Propietario de Club de Fútbol`
  - HI: `जय अग्रवाल — स्पोर्ट्स उद्यमी · फ़ुटबॉल क्लब मालिक`
- `gallery.html` e `media-kit.html` já tinham o `<title>` correcto (gallery via
  `data-i18n="gpgTitle"`; media-kit é `noindex` de propósito, não afecta SEO).
- **Deploy:** `powershell -File deploy.ps1` → Cloudflare Pages, sucesso, 279 ficheiros
  (27 novos, resto já em cache), `https://918da478.jai-agarwal.pages.dev`, domínio
  `jaiagarwala.com` confirmado a servir a versão nova.
- **IndexNow disparado** para as 8 URLs alteradas (home + galeria ×4 línguas) →
  `HTTP 200` de `api.indexnow.org` (propaga a Bing e afins; Google não participa neste
  protocolo, logo não é "consulta ao Google").
- robots.txt / llms.txt / hreflang já estavam correctos — nada a corrigir aí.

## TAREFA 3 — Sub-grelha dos 6 Shorts na galeria

Adicionada secção "The Shorts" em `gallery.html`, entre os vídeos com o Ranjit Bajaj e o
rodapé da página. Mesma "facade" já usada na home (zero pedidos ao YouTube antes do
clique; só depois `youtube-nocookie.com`). 5 miniaturas oficiais novas descarregadas de
`i.ytimg.com/vi/<id>/maxresdefault.jpg` (fetch estático de imagem, não pesquisa) e
guardadas self-hosted em `assets/youtube/` (a 6ª já existia, `ranjit-short-poster.webp`).
IDs: `5p-W0tAxP68`, `SlAwnsI5plw`, `WfYJR0nHdxk`, `e-F7yWj-9BA`, `YngXG5bqLzQ`,
`VsxooNBOBRM` (lista herdada de `RELATORIO_jai-site-youtube_2026-08-18.md`).
CSS novo (`.shorts`, `.shortcard*`) e handler genérico em `script.js`. Traduzido nas 4
línguas via `i18n/*.json` (chaves `shEyebrow/shHead/shSub/shYt1..6`).
**Prova ao vivo:** `gallery` serve 18 ocorrências de `shortcard`;
`assets/youtube/SlAwnsI5plw.jpg` → HTTP 200.

## TAREFA 4 — Estrutura de podcast (multi-episódio, esqueleto sem áudio/vídeo)

Criado `/podcast/` (hub) + página própria por convidado — `aaryaan-mishra.html`,
`aveka-singh.html`, `mal-benning.html` — todas com selo "Coming soon", placeholder onde
o áudio/vídeo entra quando gravado, e link de volta ao hub. `deploy.ps1` actualizado para
incluir a pasta `podcast/` no deploy. Link "Podcast" acrescentado ao menu principal
(`index.html`, `gallery.html`), propaga automaticamente às versões /pt/ /es/ /hi/ via
`build-langs.mjs` (aponta sempre para `/podcast/`, que por agora só existe em inglês).
**Decisão deliberada:** as 4 páginas levam `<meta name="robots" content="noindex,follow">`
— sem episódios reais ainda é "thin content"; indexar isto agora prejudicaria, não ajudaria,
a posição do site. Tira-se o noindex quando o primeiro episódio for publicado.
**Prova ao vivo:** `/podcast/` → 200; `/podcast/aaryaan-mishra`, `/podcast/aveka-singh`,
`/podcast/mal-benning` → 200 (Cloudflare redirige `.html`→sem extensão com 308, destino
200); `<meta name="robots" content="noindex,follow">` confirmado servido.

**Guião de Aaryaan Mishra (partilhado pela Myra):** procurado em
`C:\BoraLocal\Bora\Projetos\`, `C:\BoraLocal\Bora\missoes\`, no vault Obsidian, no Cérebro
do bora_app (`.claude/.ai/knowledge`) e no próprio `jai-site` — **não encontrado em nenhum
sítio acessível**. A única pista foi uma menção a "Aaryaan" em
`bora_app/.claude/bora-live.log`, mas esse ficheiro está **bloqueado em exclusivo por
outro processo em execução** (nem leitura partilhada foi possível) — não foi possível
confirmar o conteúdo. Fica registado como POR CONFIRMAR na própria página do episódio
(`podcast/aaryaan-mishra.html`), a preencher quando o guião chegar.

## TAREFA 5 — Google Ads (144-763-8091)

**Sem acesso: painel do Google Ads.** Não há nenhum MCP de Google Ads ligado nesta sessão
(confirmado pela lista de servidores disponíveis — só Stripe/Supabase/Gmail/Calendar/
Drive/Canva/higgsfield/nano-banana/Cortex/Conselho). Não foi feita nenhuma pesquisa real
no Google pelo nome do Jai, e nada foi tocado na campanha (nem seria, mesmo com acesso,
sem confirmar primeiro que não está em revisão). Para o número de impressões, é preciso
que o Danilo (ou quem tiver a conta 144-763-8091 aberta) leia directamente no painel, ou
ligue o MCP do Google Ads numa sessão futura.

## TAREFA 6 — Parado à espera de terceiros

1. **Foto original sem edições — Commons Ticket 2026083110015863**: à espera do **Jai**
   enviar o ficheiro original (sem cortes/filtros) + confirmar a licença CC BY-SA por
   email VRT. Não foi encontrado localmente um registo com este número de ticket exacto;
   o que existe (`RELATORIO-zerar-tudo-jai-2026-09-01.md`) confirma que o mesmo processo
   de confirmação VRT continua em aberto do lado do Jai.
2. **Link do LinkedIn para o `sameAs`**: **já não está pendente — já está aplicado.**
   Verificado ao vivo: o JSON-LD de `index.html` já traz
   `https://www.linkedin.com/in/jai-agarwal-a8b30342b` no array `sameAs`, aplicado a
   31/08 (ver `2026-08-31-jai-visibilidade-relatorio.md`, ponto 4). Nada para o Danilo
   fazer aqui.
3. **guardafcsad.com devolve 401** — confirmado agora com fetch real:
   `HTTP/1.1 401 Unauthorized` (Cloudflare, `Server: cloudflare`). Continua a impedir
   preencher o campo "Website" da empresa no Crunchbase e o `P856` no item do clube no
   Wikidata. Espera pela **advogada/equipa do clube** destrancarem o site (já registado
   em relatório anterior como pendente para "quarta/quinta" — sem confirmação de que já
   aconteceu).

## Resumo do que ficou NO AR (tudo com prova acima)
- `<title>` traduzido nas 4 línguas (bug real corrigido).
- Sub-grelha de 6 Shorts na galeria, 4 línguas, facade sem pedidos prévios ao YouTube.
- `/podcast/` com 3 páginas de convidado prontas para receber episódios, noindex até lá.
- IndexNow disparado para as URLs alteradas (200).
- Deploy único via `deploy.ps1` → Cloudflare Pages → domínio `jaiagarwala.com` a servir
  tudo o que está listado acima, confirmado por fetch pós-deploy.

## Log
`node .claude/.ai/cortex-mcp/_insert_e2e_log.js tudo-05-09 bloco-c-jai bloco-c ok
.claude/.ai/reports/BLOCO-C-visibilidade-jai-2026-09-05.md executor-opus`
