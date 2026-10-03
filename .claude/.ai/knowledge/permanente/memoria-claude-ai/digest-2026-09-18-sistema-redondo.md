---
id: memoria-claude-ai-digest-2026-09-18-sistema-redondo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-18
zona: verde
confianca: alta
estado: atual
---

# Claude Code 18/09 — sistema redondo: venda ao peso, Instagram calado, Go no roteador, agentes ligados

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-18-sistema-redondo`, origem `claude-code`, atualizada em 2026-09-18T23:37:10.858307+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 18 sistema redondo · memoria claude.ai · claude_ai_memoria

Venda ao peso está no ar no código (ramo autonomous-night, commits 826e05d1 e 6a61ade9): a função set_product_weight_pricing(product_id, sold_by_weight, kg, motivo) é a única verdade — o parceiro escreve o preço/kg no ecrã Adicionar/Editar produto (interruptor Vendido ao peso) ou o admin no catálogo (ícone da balança, filtro Ao peso), e o servidor monta o grupo obrigatório Escolhe a quantidade (200/300/400/500 g e 1 kg) com percentagens de platform_settings; a porção base 200 g vive em products.price e as outras são múltiplos exactos (1 kg = 5 × base = o €/kg do cartão). O + de qualquer produto com escolha obrigatória abre a ficha (era o bug: MarketProductCard e o cartão do ecrã de loja adicionavam directo). Carrinho/estafeta/detalhe dizem a porção por extenso. Regra §57 em business_rules. Não há produtos unit=kg no Intermarché/Leroy. O aviso do Instagram vinha do ig_auto_dm.py de 10 em 10 min (6/h); ficou desligado enquanto faltar instagram_manage_messages (AVISAR_TELEGRAM_POR_RESPONDER=1 liga, e mesmo assim 1×/dia só com comentário novo); 770 avisos históricos, zero desde as 23:00. O plano Go NÃO é crédito de API: só responde em https://opencode.ai/zen/go/v1 com OPENCODE_GO_KEY e o cabeçalho x-opencode-session; o "glm-5.2 em 0,1 s" do Conselho era o Groq via Motor. O Motor Bora tem agora o fornecedor go (glm-5.2, qwen3.8-max, minimax-m3) no fim da cadeia raciocinio, antes do ollama; auto-teste ordena grátis primeiro; castigo já tinha fim. motor_chamadas.custo_eur + preencher_custos_corridas() (pg_cron 10 min) enchem tokens/custo em agentes_corridas. Agentes: cobrador, qualidade e gestor-parceiros ligados ao relógio 1×/dia com fonte nova no retrato (secções parceiros/cobranca/qualidade em /opt/data/estado-operacao.txt); falam só com ALERTA: na última linha (nunca o mesmo texto em 24 h), SEM NOVIDADE = silêncio; 12 desligados com nota (incl. seguranca sem fonte e lancamentos no PC). Fila do Córtex: prop-1802e906 (TVDE ida-e-volta, vermelha) INTACTA à espera do vai do Danilo na Central; worktree por missão executada na skill protocolo-missao-bora; vetores e skills de marketing arquivadas com nota. Em Dia: a em-dia-tudo já estava fechada por outra sessão (30ede37, CI verde) e a em-dia-vender corre noutra janela — não toquei. Córtex MCP sem OAuth nesta sessão: notas no inbox do Cérebro. Relatório: docs/relatorios/sistema-redondo-2026-09-18.md.
