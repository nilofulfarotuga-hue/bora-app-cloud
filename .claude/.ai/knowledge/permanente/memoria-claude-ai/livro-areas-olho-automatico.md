---
id: memoria-claude-ai-livro-areas-olho-automatico
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Os 3 "olhos" que veem as telas do Bora sem humano (golden tests, juiz de visão Gemini, Firebase Test Lab) — estado, armadilhas e o que falta

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-olho-automatico`, origem `claude-ai`, atualizada em 2026-10-23T05:40:25.497254+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas olho automatico · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/olho-automatico.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: olho-automatico
description: Os 3 "olhos" que veem as telas do Bora sem humano (golden tests, juiz de visão Gemini, Firebase Test Lab) — estado, armadilhas e o que falta
sources: [chat]
aliases: [olho automático, F-OLHO, golden tests, juiz de visão, vision_findings, Test Lab]
---

Nasceu da pergunta do Danilo (16/08): "sem monitor, sem cabo, sem eu clicar — tem que ter algum jeito de ver a tela e avaliar".

- [stated] CAMADA 1 — fábrica de fotos (test/golden/): o Flutter renderiza cada tela EM MEMÓRIA no PC, sem emulador, em 3 tamanhos + variante teclado; overflow/estouro FALHA o teste sozinho. Workflow olho_golden.yml corre em QUALQUER branch com test/** (o build da app só dispara na branch de produção — usar isso para exercitar o olho sem publicar). Já apanhou um estouro verdadeiro no 1.º run e o defeito plantado de propósito
- [stated] CAMADA 2 — juiz de visão: .claude/juiz/vision_judge.py olha as fotos e classifica verde/amarelo/vermelho; grava em vision_findings (RLS admin). Corre local/manual, NÃO no CI. Chave Gemini em backend/.env (gitignored), nível gratuito → precisa de pausa entre imagens (8s) e ainda assim apanha 429 em corridas grandes
- [stated] CAMADA 3 — Firebase Test Lab (testlab_robo.yml, projeto boraapp-d2bea): o Robo do Google clica no app inteiro sozinho em telemóveis reais, filma e reporta crashes; cota grátis diária. FALTA o papel "Firebase Test Lab Admin" na service account (único bloqueio; APIs testing+toolresults já tratadas)
- vision_findings ganhou por MCP (Claude.ai, 17/08) as colunas status / nota_revisao / revisto_em — usar sempre daqui para a frente; run_ref carimba a versão do harness (v2-apptheme-iconfont em diante; corridas antigas têm run_ref nulo)

ARMADILHA JÁ PAGA (não repetir o diagnóstico): "blocos brancos em vez de texto" nos goldens NÃO é bug da app quando o título/tagline/rodapé saem com texto perfeito no mesmo ficheiro — é o harness sem fidelidade. Foi resolvido em 2 passos: (1) a fábrica passou a usar o AppTheme.lightTheme REAL em vez de um ThemeData mínimo e a carregar MaterialIcons+Roboto do SDK (ícones □ resolvidos, provado a correr no CI Linux); (2) o que sobrou é BUG REAL — os estilos de botão têm fontFamily: null, que no telemóvel cai no Roboto do sistema e no teste não resolve nada. Ou seja: os botões da app nunca usaram o Inter da marca.
- [stated] Fix aplicado e EM PRODUÇÃO (17/08, vc532, CI 3× verde): fontFamily 'Inter' nos estilos de botão — bora_primary_button.dart, app_theme.dart (elevated + outlined) e ainda bora_accent_button.dart, um 4.º ficheiro que só apareceu na verificação (o driver_rejected usava-o e continuava em bloco). Harness carimbado v3-botoes-inter. Prova: PNGs regenerados dos 3 grupos antes vermelhos (role, driver_rejected, driver_pending) com botões legíveis, vistos um a um
- VEREDITO DO JUIZ ficou POR DAR nessa corrida: o free-tier do Gemini esgotou-se de tanto correr no mesmo dia (429 em backoff, 9 min sem output). É limite de plano, não de código — o juiz reportou honesto em vez de fingir verde. A quota do nível gratuito renova por dia: basta correr `python .claude/juiz/vision_judge.py` no dia seguinte para o carimbo automático
- Lição de método: um olho que grita lobo sem lobo perde credibilidade — falso-positivo trata-se marcando status='falso_positivo' com a prova, e o harness arranja-se; nunca baixar o alarme sem explicar

