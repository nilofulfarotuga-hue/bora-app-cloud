# Deploy — Barbearia Ouro & Prata (site)

**Data:** 2026-07-21
**URL final:** https://ouro-e-prata.pages.dev/
**Método:** Cloudflare Pages, upload direto via `wrangler` (mesmo método do `bora-site`), token reutilizado de `bora-site/.env`. Projeto Pages `ouro-e-prata` criado de novo — o token já tinha permissão de criação.
**Ficheiros locais:** `C:\Users\danil\Desktop\ouro-e-prata\` (`index.html`, `robots.txt`, `sitemap.xml`, `deploy-cloudflare.sh`). Site é 1 ficheiro HTML self-contained (imagens em base64), sem Supabase, sem ligação ao Bora App.
**Verificação:** fetch fresco pós-deploy → HTTP 200, título e conteúdo corretos, tamanho igual ao ficheiro local.
**Pendente (ação do Danilo):** Google Search Console — adicionar propriedade e verificar por meta tag quando quiser aparecer nas pesquisas do Google.
