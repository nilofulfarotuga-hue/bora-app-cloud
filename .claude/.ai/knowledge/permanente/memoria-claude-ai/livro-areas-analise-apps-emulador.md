---
id: memoria-claude-ai-livro-areas-analise-apps-emulador
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# Ideia do Danilo (08/10/2026) de usar emulador Android + agente de IA para testar bugs do Bora e comparar com iFood/Uber/Glovo; adiada para a semana seguinte

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-analise-apps-emulador`, origem `claude-ai`, atualizada em 2026-10-26T06:18:46.580675+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas analise apps emulador · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/analise-apps-emulador.md), copiada a 26/10/2026 06:18 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: analise-apps-emulador
description: Ideia do Danilo (08/10/2026) de usar emulador Android + agente de IA para testar bugs do Bora e comparar com iFood/Uber/Glovo; adiada para a semana seguinte
sources: [chat]
aliases: [engenharia reversa de apps, emulador agente, comparar apps, teste de bugs com emulador, vídeo do jailbreak]
---

- [stated] 08/10: viu um vídeo de engenharia reversa de apps (emulador Android no PC + agente de IA a navegar, tirar prints e documentar fluxos) e quer isto para melhorar o [[bora-app]]
- [stated] Quer usar para: achar falhas de botões, bugs e problemas de uso no app dele; comparar o Bora com apps como iFood e Uber (o que falta) e construir o que falta no Bora
- [stated] Adiado para a semana que vem por estar com pouco limite; acha que vai precisar de pelo menos o Opus
- [stated] Pediu para guardar e lembrá-lo depois
- [stated] Alcance que quer (08/10): analisar TODAS as funcionalidades do Bora (botões, menus, layout; ex.: o Bora não tem menu, está tudo em quadradinhos no ecrã), depois o mesmo na Uber (incluindo o que o IMT exige da Uber) e no iFood, e depois os melhores apps do mundo, incluindo da China e do Japão, para comparar e construir no Bora o que falta
- [stated] Ordem que ele descreveu: primeiro o Bora, depois Uber, depois iFood, depois os melhores do mundo
- [stated] 17/10: mandou vídeo sobre engenharia reversa (skill REA) e pediu que isto vire método fixo — tudo o que é pago ou trava (filme, Bora, ferramentas) primeiro procura-se no GitHub o que já existe grátis, senão recria-se olhando por fora; quer o Bora "o melhor sistema do mundo" e quer só dizer "faz isso" e sair perfeito
- 17/10 estado: a missão do emulador combinada a 13/10 NUNCA correu (nada no e2e_log). Ferramentas escolhidas na pesquisa de 17/10: navegar o app no emulador = MCP do Maestro (já usado nos testes) ou mobile-mcp; REA (morluto/rea) só para auditar o APK do Bora/Em Dia. Achados e ordem sugerida no Córtex: `paridade-mundo-e-lei-2026-10-17` (inclui obrigações da lei TVDE 59/2026 e prazo 02/12/2026 da diretiva das plataformas)
- [stated] 26/10/2026 05:26: viu o vídeo do Klebson Queiroz "Encontrei no GitHub a IA que clona QUALQUER sistema (testei no iFood)" (youtube.com/watch?v=1j7CABNCBBg; REA + Codex, guia de 19 prompts no Drive dele; o código só vai por WhatsApp, isca de vendas) e quer fazer o mesmo, mas para MELHORAR o Bora (manter estilo e cores), não clonar o iFood
- 26/10 ~05:50 PROMPT REGISTADO: `PROMPT_paridade_rea_2026-10-26.md`, MOTOR OPUS 5.5, colado por mim na sessão "bora-app" (session_015f5LNUcn5Ap5UbyuuhSX5C, Controlo Remoto, modo Automático; antes fiz /compact, contexto 75%→13%), fluxo e run_id e2e_log `paridade-rea-2026-10-26`. Blocos: REA instalado (só fonte oficial) · Chrome à parte com perfil vazio · Glovo, Uber Eats e iFood vistos de fora (sem login/pedido, sem contornar bloqueios, sem ler código deles) · Bora visto igual + 3 sub-agentes a ler o código · comparação · PLANO (máx. 15 itens) e PARAR para eu rever. Plano sai no Córtex na página `paridade-rea-2026-10-26-plano`. Estado: arrancou
