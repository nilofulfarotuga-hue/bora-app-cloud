---
id: memoria-claude-ai-digest-2026-09-22-gfc-noticia-midday
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Site do Guarda FC: a peca do Mid-Day sobre Yohaan Benjamin ja esta na seccao de noticias (por publicar) — 22/09/2026

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-22-gfc-noticia-midday`, origem `claude-code`, atualizada em 2026-09-22T19:14:36.449829+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 22 gfc noticia midday · memoria claude.ai · claude_ai_memoria

MISSAO gfc-noticia-midday (Bloco B), Claude Code Opus 5, pasta C:\BoraLocal\projetosflutter\guarda-fc-site, ramo loja-2026-09-14, commit bf60a10. e2e_log fluxo gfc-noticia-midday, ids 2210-2218. Relatorio: RELATORIO_gfc-noticia-midday_2026-09-22.md; provas em provas/gfc-noticia-midday-2026-09-22/.

O QUE E: o Jai pediu (WhatsApp, 22/09) que a materia do jornal indiano Mid-Day sobre Yohaan Benjamin entrasse no site dele e no do clube. O Bloco A (pasta jai-site) ja a pos em jaiagarwala.com. Este Bloco B poe a mesma peca no site do Guarda FC.

TESTE DO JAI (31/08: no site do clube so entra material do proprio Guarda FC): PASSA. O artigo ("Mumbai teen Benjamin, 19, pressing the right buttons", Ronan Carvalho, 22/09/2026) diz que o jogador assinou recentemente pelo Guarda FC; "Guarda" aparece 18 vezes no HTML arquivado.

COMO SE FAZ UMA NOTICIA NESTE SITE (para quem vier a seguir): edita-se data/noticias.json (entrada com slug, data, destaque, imagem, jogoId, fonte e titulo/resumo/corpo nos 4 idiomas pt/en/es/hi) e, se for cobertura de imprensa, tambem data/imprensa.json (orgao, autor, data, url, titulo, citacao nos 4 idiomas). Depois corre-se "node tools/build.mjs", que gera noticia/<slug>.html e o sitemap. O muro de imprensa da clube.html mostra os artigos pela ORDEM DO ARRAY (nao ordena), a lista de noticias ordena por data decrescente.

NUNCA EM DESTAQUE — a armadilha: o destaque da home (app.js linha 349) pega a noticia com destaque:true MAS, se nenhuma tiver, cai em noticias[0]. Logo nao basta por destaque:false: a entrada tem de ir para o FIM do array. Foi o que se fez (posicao 16 de 16) e provou-se pelo DOM da home local (destaque continua a ser antevisao-jornada-4-camacha).

IMAGEM: nenhuma, de proposito (imagem:null). A unica foto do artigo e do Mid-Day (terceiros); o clube nunca publicou foto deste jogador; e o cartao desenhado pelo site (tools/cartao.py) so serve noticias com jogoId. Ja havia duas noticias no site com imagem:null, portanto o layout aguenta. Zero imagens de IA.

ESTADO: NAO PUBLICADO. Commit local, sem git push e sem deploy-cloudflare.sh. Atencao para os outros motores: push para o ramo principal dispara sozinho o deploy Cloudflare (.github/workflows/atualizacao.yml). guardafcsad.com continua sem esta noticia ate o Danilo autorizar.

DOIS AVISOS: (1) Yohaan Benjamin NAO consta de data/plantel.json (20 jogadores) e o clube nao fez comunicado sobre ele — se e mesmo jogador do Guarda FC, o plantel do site esta incompleto; confirmar com o clube. (2) o ramo principal esta 30 commits atras do ramo de trabalho loja-2026-09-14, ou seja o que esta no ar e mais antigo do que o repositorio local.
