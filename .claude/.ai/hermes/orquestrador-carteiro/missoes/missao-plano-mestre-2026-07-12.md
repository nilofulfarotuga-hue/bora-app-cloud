--- missão ---
id: missao-plano-mestre-2026-07-12
titulo: Plano mestre A-E (pós-reengenharia da esteira)
estado: pendente
criada: 2026-07-12
nota_humana: SEGURA — NÃO disparada. Danilo arranca com `carteiro.sh --iniciar-missao missao-plano-mestre-2026-07-12`. A disparar, dispara A+B (paralelo). Encadeia sozinha até E. Telegram só em: missão concluída / dinheiro / passo travado. Task C = PROPOSE-ONLY (prepara, espera "vai").
--- passos ---
passo: A | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: pendente | tarefa: Limpar disco C: ate >=25GB livres (gradle caches, TEMP do utilizador, gravacoes E2E com mais de 2 dias — NUNCA codigo/config/dados). Diagnosticar por que os avisos Telegram do Hermes pararam hoje e corrigir. Localizar a service-account key dos testadores em Downloads (boaapp-*.json) e coloca-la no caminho que o script dos testadores 12x14d espera. Relatorio curto em .claude/.ai/knowledge/inbox/.
passo: B | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: pendente | tarefa: Estabilidade adb/USB: desligar USB selective suspend (AC+DC) no esquema de energia ativo via powercfg; fixar a autorizacao adb dos 2 telemoveis (incluindo N75LTG5X5DSKDMV4) via adb kill-server/start-server reusando o adbkey; provar 30 min sem queda. Relatorio curto em inbox/.
passo: C | modelo: OPUS | paralelo: nao | depende: - | propose_only: sim | estado: pendente | tarefa: Bug TVDE paragem adicional: (1) autocomplete de morada cortado/nao clicavel na folha de parada; (2) corrida nao finaliza (erro nos dois lados, cliente e motorista); (3) notificacao A2 silenciosa em foreground. ATENCAO: mexe em tvde_finish_ride, perto de tokens/slots (zona vermelha). Prepara o diagnostico e a proposta de fix mas NAO apliques nem commites. Relatorio com a proposta em inbox/.
passo: D | modelo: SONNET | paralelo: nao | depende: - | propose_only: nao | estado: pendente | tarefa: Website oficial (repo bora-site / Cloudflare Pages): adicionar categoria Limpeza + seccao Porque o Bora. O prompt detalhado ja existe no Cortex/inbox — procurar e executar. Relatorio curto em inbox/.
passo: E | modelo: SONNET | paralelo: nao | depende: A,B,C | propose_only: nao | estado: pendente | tarefa: Teste E2E COMPLETO ate 1 pedido real chegar a tabela orders — todos os fluxos (cliente, restaurante, mercado, favor, estafeta). SO arranca com A, B e C concluidas. Relatorio em inbox/. E a ultima.
--- fim ---
