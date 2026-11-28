# Inventário — missão varrer-pendentes-2026-11-28 (B0 e B1)

Feito a 28/11/2026 pela sessão na nuvem (Claude Code). Linha principal comparada:
`autonomous-night-2026-04-29` em `735a25de` (versionCode 757).

Como foi medido: para cada pedido/ramo simulei a junção com a linha de hoje
(`git merge-tree`) e vi que ficheiros mudariam de facto — compara conteúdo, não
histórico. Para os ramos de 08/11 confirmei também pelo commit `075fcf65`
("as 6 missões de 08/11 juntas", M7, M2, M4, M6, M1, M3) e pelo `e2c6fa60`.

Servidor: o Supabase NÃO foi usado nesta sessão (cada SQL pedia "Permitir" e a
Claude.ai negou; ordem dela às 14:2x). O estado "aplicado" vem do ficheiro da
missão. O que falta conferir/aplicar está em
`docs/missoes/varrer-pendentes-2026-11-28-sql.md`.

Ramos novos desta missão:
- `ai/2026-11-28-pendentes-app` — app com servidor já em produção (publica já).
- `ai/2026-11-28-pendentes-app-sql` — por cima do anterior; precisa do SQL aplicado antes.
- `ai/2026-11-28-pendentes-docs` — só documentos, `[skip ci]`.
- `ai/2026-11-28-reservas-pagamento` — dinheiro, espera o "autorizo".

## Pedidos abertos

| Pedido | O que faz | Já na linha principal? | Servidor | Zona vermelha | Decisão |
|---|---|---|---|---|---|
| #5 paridade | Relatório Glovo/Uber/iFood + 15 melhorias | Não (6 docs) | — | Não | Docs → pendentes-docs; fechar |
| #6 modo automático seguro | Relatório, propostas, mudança da tranca bora-mods, git-guardrails, CI revisao.yml | Docs/propostas já estão; tranca, guardrails e revisao.yml NÃO | — | Mexe nas travas de segurança | Docs que faltavam → pendentes-docs. Tranca/CI ficam no #6 (não mexo em travas sem olho humano) |
| #7 M8 | 6 missões de 08/11 | Sim (075fcf65, e2c6fa60); só faltava 1 doc, já igual | Aplicado na época | Tinha dinheiro (M1), já entrou | Fechar |
| #20 manhã 15/11 | MB WAY sem cobrar a dobrar, nome pelo suporte, robôs | Código TODO já na linha (commits a16e3d9c, 3c2e702c, d00d35bf são antepassados) | editar_perfil e robos_livro aplicados; conteudo_ia_fila não | MB WAY (já entrou no código) | Filas/roteiros do conteúdo IA + correção do Juiz → pendentes-docs; fechar |
| #21 artes farmácias v2 | Imagens v2/v3 | Não | — | Não | → pendentes-docs (sem os workflows ios_*); fechar |
| #32 quando chamar estafeta | Lojas não-comida marcam até 14 dias | Não | Não aplicado | SIM: muda `partner_auto_dispatch_ready_orders` (dispatch) | Fica aberto, pronto (junta sem conflitos). Espera autorizo |
| #33 busca leve | Lupa 400 ms com memória, pesquisa leve | Não | Aplicado (menos vigia_servidor_portugues) | Não | Portado em pendentes-app; fechar |
| #34 receita cartão e MB Way | Pagamento da receita na farmácia | Não | Não aplicado | SIM: cartão/MB Way | Fica aberto (só conflito no TRANCAS.md). Espera autorizo |
| #35 lupa sugestões | Sugestões desde a 1.ª letra, pesquisa sem login | Não | Não aplicado (lupa_sugestoes, pesquisa_dono) | Não | Portado em pendentes-app-sql; fechar a apontar para o novo |
| #37 selo Novo | Selo "Novo" nos atalhos | Não | Aplicado | Não | Portado em pendentes-app; fechar |
| #38 comunidade 24h | Tabelas redes_* e scripts da VPS | Não | Aplicado | Não | Migração → pendentes-app; scripts → pendentes-docs; fechar |
| #39 farmácia peça aqui | Pedir à farmácia parceira primeiro | Não | Aplicado | Não | Portado em pendentes-app; fechar |
| #41 painel aprovações | Botões aprovar com exceção / pedir documentos | Não | Não aplicado | Não | Portado em pendentes-app-sql; fechar a apontar para o novo |
| #43 Hermes diretor 2 | Relatório, scripts VPS, lições nos robôs (2 Edges) | Não | Tabelas das lições já no repo | stripe_ler.py só lê | Edges → pendentes-app; resto → pendentes-docs; fechar |
| #44 robô do Jai | Portas na base para avisos | Não (2 migrações) | jai_robo_portas aplicado; teste_fora_da_quota por confirmar | Não | Migrações → pendentes-app; fechar |
| #55, #56 | — | — | — | — | NÃO MEXER (Claude.ai e PC) |

## Ramos sem pedido

| Ramo | Já na linha principal? | Decisão |
|---|---|---|
| m1-dinheiro-favores | Sim, pelo M8 (código mudou depois na linha, a de hoje manda) | Só 1 linha das métricas → pendentes-docs |
| m2-estafeta-conta-fila | Sim, pelo M8 | Nada a juntar (docs em conflito: fica o de hoje) |
| m3-dipsy-acesso-total | Sim, pelo M8 | Nada a juntar |
| m6-crescimento | Sim, pelo M8 | Nada a juntar |
| m7-stripe-parceiros-radar-leis | Sim, pelo M8 | Nada a juntar |
| m10-publicar | Sim (884e3def equivalente) | Nada a juntar |
| m10-radar | Inventário do radar na linha é mais novo | Nada a juntar |
| 11-amigo-casa | Substituído pela Casa e Manutenção (35d14538, febd4601) | Nada a juntar |
| 11-meta-grupos-casa-amigo | Não | → pendentes-docs |
| 15-devocional-en-es | Não | → pendentes-docs |
| 15-devocional-lucia | Não | → pendentes-docs |
| 15-produtos-celeste-tonico | Não | → pendentes-docs |
| 15-reservas | Não. 3 migrações já aplicadas (15/11); 4 Edges de pagamento por juntar | ZONA VERMELHA → ai/2026-11-28-reservas-pagamento (pedido em rascunho). Docs → pendentes-docs |
| 16-a3-cor-viva | Não | 4 PDF → pendentes-docs |
| 16-dinheiro-dividido | Sim (texto já no strings_en) | Nada a juntar |
| 17-loja-casa-cozinha | Não | → pendentes-docs |
| 17-painel-telefone-topo | Substituído por 60ecd801 (encomendas_telefone_aguardar_card) | Nada a juntar |
| 18-loja-acessorios-telemovel | Não | → pendentes-docs |
| 22-licoes-amigo-ar | Mesmo código que o #43 | Entra com o #43 |
| 22-licoes-suporte-ar | Mesmo código que o #43 | Entra com o #43 |
| 23-radar-fila | Sim (b02756c6; migração com a versão real 20261123064120) | Nada a juntar |
| 15-checkup | Sim (proposta B9 na linha, versão de hoje) | Nada a juntar |
| 17-impressao-foto | Sim | Nada a juntar |
| 26-voz-central-sipuri | Ficaram de fora 3 commits depois do #53 (WhatsApp da Bora, voz-cerebro v14) | → pendentes-app (só servidor e VPS) |

Nota: os ramos baseados no `main` traziam `.github/workflows/ios_aviso_versao.yml`
e `ios_ficha_emdia.yml` velhos; ficaram de fora (a linha de hoje manda).
