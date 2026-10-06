---
id: memoria-claude-ai-digest-2026-10-06-jai-formatura-fix
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-06
zona: verde
confianca: alta
estado: atual
---

# Digest 06/10 — jai-site: data da compra do Guarda FC corrigida no artigo da formatura

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-06-jai-formatura-fix`, origem `claude-code`, atualizada em 2026-10-06T11:19:55.901152+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 06 jai formatura fix · memoria claude.ai · claude_ai_memoria

O artigo da graduação do Jai (jaiagarwala.com/graduation-laliga-business-school e as versões /pt/, /es/ e /hi/) passou a dizer julho de 2026 para a compra do Guarda FC. A data oficial da assinatura é 19/07/2026, dada pelo Jai a 31/08; agosto (11/08) foi só o anúncio público. "Poucas semanas antes" passou a "poucos meses antes", porque de 19/07 a 01/10 são 74 dias. A fonte é graduation/gerar.mjs: corre-se com node e o build-langs.mjs copia as páginas para os caminhos públicos. Publica-se com deploy.ps1 (wrangler); o deploy foi o 643fbded. As 4 páginas estão a 200, com julho no HTML servido, e o ficheiro de verificação da Google está intacto. O IndexNow aceitou nas 3 portas e o lastmod do sitemap ficou 2026-10-06. Commit local 9244291 (o repo não tem remoto). Um verificador com contexto limpo aprovou 5/5. FALTA: (1) "Request indexing" no Search Console — esta sessão não tinha a extensão do Chrome, por isso ficou bloqueado; (2) a página principal (storyP2) e o media kit (mkP2) ainda dizem "agosto de 2026" para a compra, nas 4 línguas. Isso vem do primeiro commit (25/08) e espera a ordem do Danilo. Decisões fechadas: a legenda do Alejandro fica "of LaLiga Business School", sem cargo; "Non-official diploma" não pede nada. A mensagem para o grupo "Jai personal team" (v2, em provas/) não foi enviada; quem envia é o Danilo. Lição: o Bash deste PC arranca sem PATH — usar export PATH="/usr/bin:/bin:/mingw64/bin:$PATH".
