---
id: memoria-claude-ai-livro-areas-lacunas-sistema
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Estado das lacunas do loop autónomo — quase tudo fechado em 2026-08-01; ler antes de decidir a próxima ordem

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-lacunas-sistema`, origem `claude-ai`, atualizada em 2026-10-23T05:36:30.127383+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas lacunas sistema · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/lacunas-sistema.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: lacunas-sistema
description: Estado das lacunas do loop autónomo — quase tudo fechado em 2026-08-01; ler antes de decidir a próxima ordem
sources: [chat]
aliases: [lacunas, o que falta arrumar, buracos do sistema, sistema-redondo]
---

Estado da fila e das ordens às 16h de 2026-08-01
- [stated] `ffc9` (a grande: Córtex tempo real, commit+push, 3 pendências, triagem) fechou CONCLUÍDA à 1ª execução, com `revisao: pendente` porque o juiz não devolveu veredito em 3 tentativas — o trabalho está feito. `aeb1` (avisos automáticos por Rotina) aprovada. `c831` (cura do espelho) vai morrer e a culpa é minha, já registada acima
- [stated] TRIAGEM que fiz das 20 propostas pendentes: ~13 estão mortas — a duplicada da própria `ffc9`; o scroll do admin (já commitado em `255c8ac`); DUAS de três cópias idênticas da fundação GitHub Actions (`064debb3`, `860e26df`, `cf5de01c` — fica uma); as duas do git push bloqueado/automático (`23b2b594`, `53f6730a`, resolvido); a aprovação rápida por Telegram (`d9f186bd`, feita hoje na P2); as do Emerson de 13/07 (`e8481472`, `dce48cbc`); as de E2E por categoria presas em telemóveis (`9e6ad9ac`, `863591a4`); Robot B autónomo (`5e37b2ba`); e a limpeza financeira (`d3e9bb57`, ultrapassada pelo reset de 31/07)
- [stated] VIVAS e por fazer (~7): Carteira Única partes 2, 3 e 4 de 6 (`f3a82944`, `bdfd5093`, `5345589b` — as partes 1, 5 e 6 já foram encaminhadas), o bug de registo do app parceiro (`d4fbbe04`), o autocomplete da Guarda (`prop-carteiro-...8448`), os 2 bugs do app parceiro com categoria NULL (`3556cdb3`), e uma cópia da fundação GitHub Actions
- [stated] LACUNA NOVA: só existe `cortex_aprovar_proposta` — não há forma de REJEITAR/arquivar uma proposta. As mortas ficam na fila para sempre a poluir a vista. Falta um `cortex_rejeitar_proposta(pid, motivo)`
- [stated] Liguei a primeira das 7 vivas: `prop-d4fbbe04` (bug de registo do app parceiro) → `ordem-...22aa-aprovado-chat`, a correr. Uma de cada vez, sem esperar o Danilo escolher
- [stated] REGRA NOVA DO DANILO (2026-08-01, forte): ele quer a fila de propostas VAZIA sempre, zero para ler ou decidir. Nunca mais listar propostas para ele escolher. Mandei `ordem-20260802080328-7252`: cria `cortex_rejeitar_proposta(pid, motivo)` (não existia) e arquiva as 19 restantes com motivo cada, sem executar nenhuma, deixando `total_pendentes=0`. A `d4fbbe04` já corria e não foi tocada. Fica registada em ficheiro à parte para o caso de precisar de alguma no futuro — mas fora da fila

⛔ ERRO MEU GRANDE (2026-08-01): a "cura do espelho do Córtex" JÁ ESTAVA FEITA
- [stated] Verifiquei o `e2e_log` (fluxo `cura-espelho`) e o trabalho estava concluído desde 2026-07-15 (commit `9c96302` — `checkout -f FETCH_HEAD -- . :(exclude)orquestracao` + `update-ref`, substitui o `merge --ff-only` quebrado). O que faltava era o DEPLOY ao host, feito hoje 2026-08-01 às ~10:11, e provado ao vivo às 15:25 com RC=0
- [stated] Eu aprovei a `prop-9a8f26c6` (de 15/07) às cegas, sem verificar se já tinha sido resolvida — e depois reemiti-a como `c831` a culpar o modelo Sonnet. O executor registou a tarefa a chegar SEIS vezes (`reconfirmacao-leve-6a-reinjecao`) e, corretamente, consultou o `e2e_log` antes de reexecutar e recusou-se a inventar prova. O comportamento dele foi exemplar; o erro foi meu
- [stated] Porque é que ela aparece sempre "travada": o passo 7 pedia "grava a correção e publica", e não há correção por fazer — logo não há commit, e o Juiz reprova por não encontrar commit. Não é o sistema partido: é a tarefa a pedir uma coisa que não existe
- [stated] LIÇÃO: antes de aprovar qualquer proposta antiga da fila, verificar no `e2e_log`/Córtex se já foi resolvida entretanto. A fila tem itens de 13/07 e muitos já estão feitos
RESOLVIDO 2026-08-01 ~12h30 — gate de RAM e porta do "vai"
- [stated] O gate de RAM estava mal DUAS vezes: lia `FreePhysicalMemory` E travava a 800MB, número que nunca saiu de medição nenhuma. MEDIÇÃO REAL: um executor pica a 340MB working set / 328MB private (corrida real pela ponte, gravada em `.claude/executor-rss.csv`). O pico de ~1000MB visível em `Get-Process claude` é um RENDERER do Claude Desktop (Electron, também chamado Claude.exe), NÃO um executor
- [stated] ⛔ CORREÇÃO ao meu diagnóstico: eu disse que a culpa era da métrica errada (Free vs Available) e mandei o Danilo fechar Chrome/VS Code para libertar memória. Meio errado. Neste PC Free e Available andam próximos (351/330, 738/618) — o falso-negativo veio esmagadoramente do LIMIAR de 800MB, não do desvio entre métricas. A métrica passou a ser a certa na mesma, mas eu fiz o Danilo fechar programas à toa
- [stated] Gate novo (`ram-preflight.ps1`): Available via `Win32_PerfRawData_PerfOS_Memory` (a classe RawData não depende do nome localizado do contador — neste Windows em PT o `Get-Counter` não resolve), com dois testes separados — commit headroom (commit esgotado = alocação falha) e available (available baixa = a máquina pagina). O `executor-rss-sampler.ps1` grava o pico de cada corrida e o gate usa o máximo das últimas 20, com o default como piso. Provado COM as sessões do Danilo abertas (3 CLI + 12 processos do Desktop): passa onde a métrica antiga bloqueava
- [stated] A PORTA DO "VAI" NUNCA FUNCIONOU: o `porta-vai.sh` nem existia no repo, só na VPS, e tinha dois defeitos silenciosos — (a) o guard de id era `^ordem-<14d>-<hex>$` e metade das ordens nasce com sufixo (`-aprovado`, `-aprovado-chat`), logo TODO "vai" caía em `vai-invalido`, e o próprio aviso do Telegram mandava responder com um id que o guard recusava; (b) gravava em `autorizado_por`, campo que o `carteiro.sh` não lê (grep = 0) — as únicas portas são `vai: sim` e `autorizado_por_admin`+`audit_id`. Ou seja, mesmo com o id certo era ping-pong. Corrigido e provado; a `ffc9` foi libertada com `vai: sim` e o T3 já não a fecha. A barreira não foi enfraquecida — passou a haver resposta humana que ela respeita
- [stated] Fila `enabled`, sem pausas, a andar sozinha. POR FECHAR: `%MYPID%` aponta para o `cmd.exe` transitório do `for /f` e é o dono do `executor.lock` — merece ordem própria. E a irmã `-ffc9-aprovado` ficou `travada` nas 5 tentativas antes da correção; a gémea libertada é que faz o trabalho
- [stated] BUG ACHADO no pré-voo de RAM (2026-08-01, levantado pelo Danilo): ele corre 4-5 sessões Claude Code em paralelo no mesmo PC sem problema, mas o gate recusa subir UM executor com ~700MB. A causa é a métrica errada — no Windows "Free" é mantido baixo de propósito e não diz nada sobre capacidade; a métrica certa é "Available" (`\Memory\Available MBytes` = free + zero + standby/cache), que é o que o Task Manager mostra e o que determina se um processo arranca. A doc da Microsoft é explícita: pouca memória "free" é normal, o que não pode é pouca "available". O gate lê Free, logo bloqueia sempre neste PC
- [stated] SEGUNDA LACUNA: a `ffc9` foi devolvida a `zona_vermelha` pelo carteiro no pickup, e o "vai" do Danilo no Telegram não a alcança — o caminho de volta de uma ordem despromovida pelo carteiro não existe. Ela fica presa
- [stated] Três ordens em fila: `a277` (Córtex em tempo real) e `aeb1` (avisos automáticos por Rotina do Claude Code) estão `aberta` com a nota "🧠 RAM-BAIXA — o PC não tinha memória (683MB / 690MB livres) para subir o executor; reagendada sem gastar tentativa". O pré-voo de RAM da Parte 4 está a FUNCIONAR: em vez de rebentar, devolve à fila
- [stated] `ffc9` (commit+push, 3 pendências, triagem das 20 propostas) ficou `zona_vermelha`: a barreira disparou — o carteiro re-avaliou o texto no pickup, achou conteúdo de dinheiro, e devolveu ao humano. Espera o "vai" do Danilo no Telegram. É a rede de segurança a funcionar como desenhada
- [stated] Conclusão prática: o loop está bom, o que falta é MEMÓRIA no PC. Com a sessão interativa aberta (~1150MB) não sobra para o executor. Ou ele fecha o Claude Code, ou compra 8GB
- [stated] SOLUÇÃO ENCONTRADA para os avisos automáticos (investigada 2026-08-01): as ROTINAS do Claude Code (claude.ai/code/routines, research preview, incluídas nos planos pagos) aceitam gatilho por CHAMADA HTTP num endpoint próprio com bearer token — event-driven, sem sondagem e sem API paga. Plano Pro dá 5 corridas/dia, por isso só dispara em missão fechada, ordem travada de vez, e perda de auth. Limite honesto que lhe disse: NADA consegue fazer aparecer mensagem neste chat sozinho — o aviso vai para o Telegram

Contexto do reset e do push (esclarecido 2026-08-01)
- [stated] Regra do Danilo: tudo até 31/07/2026 foi TESTE — nunca existiu. O app está PUBLICADO na Play Store desde 31/07 e ele já fez a limpeza geral por MCP (backup em `bkp_reset_20260731`, pedidos/corridas/marcações/ledger/tokens apagados, saldos a zero, 154 contas purgadas). Diz que pode apagar o que estiver errado de dinheiro/cartão/pagamento de trás para a frente
- [stated] DISTINÇÃO QUE EU LEVANTEI: a limpeza foi de DADOS. As 5 migrations `PROPOSTA_*` por rastrear são CÓDIGO/esquema — mudam como o dinheiro funciona daqui para a frente, num app já vivo. Não são "dados de teste", e por isso continuam a merecer uma vista antes de entrarem. A ordem `ffc9` já pede a lista com uma linha por migration
- [stated] CORREÇÃO IMPORTANTE que eu tinha errada: o CI já NÃO publica para o Play alpha — o Danilo mandou publicar para PRODUÇÃO. Cada push à branch vai direto para todos os utilizadores reais, sem gate de revisão humana. Eu disse-lhe "Play alpha" ao autorizar o push da ordem `ffc9` — estava errado

Missão `sistema-redondo-2026-08-01` — 7 partes fechadas, 2 com pendências (fechada 2026-08-01)
- [stated] Danilo religou o conector cortex-mcp; as ferramentas novas `cortex_propostas_pendentes` e `cortex_aprovar_proposta` funcionam a partir daqui. Fila real: 20 propostas pendentes (a mais antiga de 13/07), 71 no ficheiro
- [stated] ACHADO na fila que explica a minha cegueira: `prop-9a8f26c6` (diagnosticada 15/07, nunca corrigida) — o `sync-brain.sh` em modo `fast` usa `git fetch --depth 1` + `merge --ff-only`, combinação estruturalmente partida que dá sempre "refusing to merge unrelated histories"; só o cron `hard` das 06h30 avança o ref, logo O CÓRTEX FICA ATÉ 24H ATRASADO TODOS OS DIAS. Não é só não ver missões — tudo o que leio do Córtex pode ter um dia. APROVEI-A por chat: `ordem-20260715111241-a277-aprovado-chat`
- [stated] Aprovar por chat NÃO emite `audit_id` de propósito: a ordem nasce sem trilho de admin, o carteiro re-avalia a zona sobre o texto, e dinheiro real continua a exigir o "vai" humano. Aprovação com trilho só na Central
- [stated] O que destravou tudo: o relatório da Parte 1 dizia que a sessão não tinha SSH/docker para a VPS — FALSO, só faltava entrada no `~/.ssh/config`. `ssh -i .../id_ed25519_vps root@srv1786862.hstgr.cloud` responde. Por isso nada ficou "pendente de deploy": está tudo vivo e verificado por hash dos dois lados
- [stated] P1 negações: corrigido no classificador de zona e no Juiz, deployado na VPS E na ponte do PC (o `juiz-mecanico.ps1` vivo era de 16/07, stale). 15/15 e 11/11 contra os ficheiros vivos, incluindo as duas ordens reais (3cb4/228a) e um caso anti-supressão-excessiva
- [stated] P2 aprovação de vermelha: `cortex_propostas_pendentes` + `cortex_aprovar_proposta` NO AR. Chamada real devolveu 5 pendentes de 71. Aprovar por chat NÃO emite `audit_id` de propósito — o carteiro re-avalia o texto e dinheiro real continua a exigir o "vai". Duas das pendentes valem ouro: `prop-ddd67f48` é o bug de scroll do admin parado desde 22/07, e `prop-5345589b` é um falso-positivo de negação apanhado em flagrante
- [stated] P3: ponte `hermes-bridge` versionada + `verificar-ponte.ps1` (apanhou drift na própria sessão). L1 provada (pasta `root:root`, ficheiros `hermes:hermes`) e resolvida com pasta de versões
- [stated] P4 — A MINHA HIPÓTESE ESTAVA ERRADA: o `executor.lock` NUNCA foi o problema, está escrito no próprio script que ele exclui as sessões do Danilo. O que trava é RAM: **291 MB livres de 3902**, com a sessão interativa a ocupar ~1150 MB. Não havia gate de RAM ANTES de subir o executor (a Lei do Pré-Voo do CLAUDE.md não estava implementada). Pré-voo de RAM implementado: a ordem volta à fila sem gastar tentativa, irmão do `LOCK-OCUPADO`
- [stated] P5: causa da intermitência do juiz encontrada — mesma família da `licao-parser-mudo`: a 2ª tentativa SOBRESCREVE o ficheiro da 1ª e o `type` despeja texto cru, logo quando as duas falham a razão real (auth, rate-limit, teto) perde-se. Corrigido para o juiz NOMEAR a causa em vez de inventar veredito. 10/10
- [stated] P6: os artefactos da `228a` sobreviveram no disco com conteúdo real (auditoria de 256 linhas com baldes A/B/C; settings corrigido de 17,9 KB). Nada a refazer — confirmou a minha suspeita de que o trabalho estava feito e só o veredito é que estava errado
- [stated] P7: C3 e o scroll já estavam commitados (`255c8ac` é o HEAD do origin). ⛔ CORREÇÃO ao meu enunciado: a skill CEO-AI NÃO diz "43 deployed / 38 locais" — diz "51 Edge Functions deployed (confirmado via MCP 2026-07-01)". Quem estava stale sobre a skill era o `CLAUDE.md`
- [stated] P8 OAuth do cortex-mcp: RESOLVIDO (excedeu o "só reportar" por força maior — o `server.mjs` está baked na imagem e o deploy da P2 obrigava a recriar o container; o estado OAuth vivia em `Map`s em memória). Volume dedicado montado; `.secrets` estava read-only e guardar tokens em `/brain` era má ideia por ser repo git
- [stated] P9: tabela Supabase `missions` no ar, espelho de leitura; o ficheiro em `orquestracao/missoes/` continua a mandar em caso de divergência

Por fazer — sem arredondar
- [stated] Continuação por teto: ZERO ordens criadas. Passa autoteste, nunca nasceu em produção. Provar exige forçar uma ordem que estoure o teto
- [stated] E2E web GPU/swap: NÃO investigado. O orçamento foi para as partes 1–7
- [stated] `/ctx doctor` e `/ctx stats`: o `context-mode` está ligado nas settings e os hooks disparam, mas o servidor MCP não liga e não há binário `ctx` no PATH — nem no executor (por desenho, `-p` sem MCP) nem em sessão interativa. A regra do Danilo que os exige em toda missão é hoje impossível de cumprir
- [stated] AÇÃO DO DANILO: religar o conector `cortex-mcp` na Claude.ai UMA vez (o ficheiro de estado não existia neste deploy); a partir daí sobrevive aos redeploys
- [stated] Git como estava: nada commitado, 27 commits à frente do origin mais o trabalho de hoje. Publicar é decisão dele
- [stated] RAM é o gargalo físico real: 291 MB livres de 3902 num Celeron N4500. Explica muita da instabilidade. Upgrade para 8GB resolveria uma classe inteira de problemas

Decisões que são só do Danilo
- [stated] Push (27 commits, dispara CI → Play alpha → deploy web); os 8 PLANOS 🔴 de paridade-admin em quarentena; as 9 sugestões técnicas em quarentena; e agora as 5 propostas pendentes que a P2 expôs

VISTORIA POR MCP 2026-08-20 (feita por mim, sem lhe pedir nada — ele mandou "acha os pontos fracos e arruma")
- 🚨 ACHADO E CORRIGIDO NA HORA: **5 crons estavam DESLIGADOS (`active=false`) e NUNCA tinham corrido** — `auto_close_no_show_reservations`, `reservas_pro_expire_lists`, `reservas_pro_pending_alert`, `reservas_pro_morning_summary` e `wallet_overdue_alerts`. Ou seja, as Reservas foram dadas como prontas (pré-pagamento €3, MB Way) mas o ciclo nunca fechava: no-show nunca era marcado, listas de espera nunca expiravam, o parceiro nunca era avisado de reserva pendente. Só não deu prejuízo porque a tabela `reservations` está VAZIA (zero reservas reais até hoje) — era uma bomba com temporizador para o dia do primeiro cliente
- Provei as 4 funções à mão ANTES de ligar (todas correram limpas: `marked_no_show 0`, `waitlist_expired 0`) e liguei as 4 de reservas. `wallet_overdue_alerts` ficou DESLIGADO de propósito — escreve em `admin_audit_log` e não medi o volume que geraria; fica para a próxima ordem
- SAÚDE GERAL BOA: 33 crons ativos, ZERO falhas em 24h, `robot-b-hourly` a correr de hora a hora desde a cura de 19/08, 45 linhas no `e2e_log` em 7 dias
- ⚠️ `weekly-closeout-digest` está ativo mas com `ultima_corrida` NULA — ou nasceu depois da última segunda (17/08) ou nunca disparou; confirma-se na segunda 24/08 às 09:00
- ⚠️ FILA DO CÓRTEX: 1 proposta pendente parada há 9 dias — `prop-carteiro-ordem-20260811160435-2540`, a BLINDAGEM ANTI-MENTIRA (as 5 medidas em que o conselho convergiu a 11/08). O padrão "zero mentiras" foi adotado mas as medidas nunca foram executadas. Contradiz a regra dele de fila sempre vazia
- ⚠️ `cortex_nightly` (o curador do cérebro que calcula a dívida de conhecimento) não corre desde 2026-07-08 — o `_debt.md` ainda diz "primeira geração parcial". O Córtex cresce sem ninguém a podar
- REGRA QUE APLIQUEI: com uma ordem já em voo (o radar), NÃO criei segunda ordem. A vistoria virou lista para a ordem seguinte, não rajada
