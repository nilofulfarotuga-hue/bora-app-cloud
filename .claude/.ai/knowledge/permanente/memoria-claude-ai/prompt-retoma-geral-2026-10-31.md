---
id: memoria-claude-ai-prompt-retoma-geral-2026-10-31
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# PROMPT ÚNICO 31/10/2026 — parar, limpar a RAM e retomar todas as missões (Casa, motor Claude, Dipsy, lembretes)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-retoma-geral-2026-10-31`, origem `claude-ai`, atualizada em 2026-10-31T09:08:25.313932+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt retoma geral 2026 10 31 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️ (Danilo, 31/10/2026 09:10: "parar tudo, recuperar a RAM, retomar tudo o que não foi feito e terminar o que está a correr"). MOTOR: Opus 5.5. PORTA: esta sessão, PC do Danilo, pasta bora_app (C:\Users\danil\Desktop\projetosflutter\bora_app), modo Ignorar permissões. Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/ e a skill protocolo-missao-bora. Fluxo e2e_log: retoma-geral-2026-10-31. REGRAS DESTA MISSÃO: nunca terminar o turno à espera do Danilo; o que estiver bloqueado salta-se, regista-se e segue-se; o Danilo NÃO quer carregar em botões a toda a hora — por isso NÃO apliques migrações na base de PRODUÇÃO a meio dos blocos: deixa-as como ficheiros SQL no ramo e junta TODAS as que precisarem da tranca num único passo final "PUBLICAR", para ele dar UM só "Permitir"; quando esse passo chegar, manda-lhe UMA mensagem pelo WhatsApp da Bora (937 501 673 → 351931992662) a dizer "abre a sessão X na app e carrega em Permitir" e continua com o resto entretanto. Preços, comissões, ganhos e Stripe só como proposta (precisam do "autorizo"). Reporta outros erros em vez de os corrigir calado. Regista cada bloco no e2e_log e no fim relatório + digest no Córtex + mensagem final ao Danilo pelo Telegram do Dipsy em texto e áudio.

BLOCO 0 — PARAR E LIMPAR A RAM (primeiro de tudo, 15 min). (a) Vê o que está a correr: Get-Process ordenado por memória; sessões do Claude Code abertas (processos claude/node com o cwd); Chromes (perfil Bora d9e862e0 e pessoal 5b260cdd) e quantos separadores; emuladores Android; janelas antigas de PowerShell; ponte do Telegram do Dipsy (~/.dsh/telegram/ponte.py) e Dipsy web (porta 3080). (b) A sessão "Meta ads 2026-10-30" (session_01HPEpV9MUQ1XHGwsDJXBvQH) é a única que ainda produz: se o e2e_log meta-anuncios-2026-10-30 já tiver o passo G3-urls, ela acabou — pode ser fechada; se não tiver, NÃO a mates: deixa-a acabar e fecha só o resto. (c) Fecha com segurança: sessões do Claude Code paradas há mais de 30 min sem turno (Harness, Casa, Bora, Jai, Boom — confirma pelo claude.ai/code que estão "terminou a resposta" ou presas numa pergunta), emuladores parados, PowerShells órfãos, separadores de Chrome sem uso (deixa só o WhatsApp da Bora e o da Meta se a sessão dela ainda trabalhar). Nunca fechar a ponte do Telegram nem o servidor de voz. (d) Mede MB livres antes e depois, regista no e2e_log (passo 0-ram, com a lista do que fechaste), e cria ~/.dsh/limpar-ram.ps1 (reutilizável, com a mesma lista de exclusões) e uma tarefa agendada do Windows que o corre de hora a hora quando a RAM livre < 500 MB.

BLOCO 1 — CASA & MANUTENÇÃO (retomar). Estado: a sessão casa-manutencao-2026-10-30 ficou presa a 30/10 22:03 na tranca da migração casa_01 (ramo casa-manutencao-2026-10-30, worktree bridge-cse_01HPEpV9pGSbJhE24V5mLDaj, ESPEC.md e casa_01_papel_e_tabelas.sql já escritos). Lê por SQL as páginas claude_ai_memoria prompt-casa-manutencao-2026-10-30, casa-manutencao-proposta e casa-manutencao-pesquisa-2026-10-29, e o e2e_log casa-manutencao-2026-10-30 (ids 5510 e 5513). Continua no MESMO ramo (ou cria um worktree novo a partir dele se o antigo estiver preso): servidor (migrações como ficheiros, sem aplicar), app cliente/prestador em PT-PT, painel admin em PT-BR com autoridade total, categoria nasce DESLIGADA, provas no emulador só se a RAM deixar (senão testes de widget + capturas por golden), chave do cartão/MB Way fica como proposta. Fecha com commit no ramo; a migração vai para o passo PUBLICAR.

BLOCO 2 — MOTOR CLAUDE PRIMEIRO. Só se ainda não houver sessão a correr com isto (SELECT no e2e_log fluxo motor-claude-31-10 com passo diferente de 'fila'); se já houver, salta e regista. Senão, executa o prompt da página claude_ai_memoria prompt-motor-claude-2026-10-31 como um bloco desta missão (mesmas regras: medir RAM, adiar o Flutter se preciso).

BLOCO 3 — DIPSY MELHOR QUE O CLAUDE CODE. Executa o prompt da página claude_ai_memoria prompt-dipsy-melhor-2026-10-31 (decisões do Danilo das 06:31: Creator Mode, segurança da rede, comandos novos, engenharia reversa só nos nossos apps, app de Windows com telemetria desligada, guarda nos executores automáticos, limpeza de RAM, lembretes da VPS). A voz com áudio real já ficou corrigida e provada às 08:16 (e2e_log 5586); falta a lentidão: o whisper local gasta sempre os 45 s antes de o Gemini entrar — com RAM < 1,5 GB vai direto ao Gemini (objetivo: "Ouvi" em < 15 s).

BLOCO 4 — LEMBRETES DO DANILO NA VPS. A rotina /opt/data/rotinas/lembretes_danilo.py não enviou o diário de 30/10 09:30 (lembretes_danilo id 4) nem o urgente id 21; confirma se os de hoje (ids 5 e 6, 09:30) saíram; se não, causa raiz nos logs da VPS, corrigir, provar e registar.

BLOCO 5 — PUBLICAR (um clique só do Danilo). Junta num único passo: migração casa_01 e as outras da Casa, e o push dos ramos retidos pela tranca (gorjetas-taxa-2026-10-30 docs, dsh docs, casa) — tudo SEM publicar a categoria Casa aos clientes (nasce desligada) e sem versão nova nas lojas hoje (a publicação nas 3 lojas é a semanal). Antes de pedir o clique, manda-lhe a mensagem pelo WhatsApp da Bora com o nome exato da sessão e o botão. Depois do clique, prova por SELECT e pelo CI.

FECHO: relatório .claude/.ai/reports/retoma-geral-2026-10-31.md (cópia em Desktop\Bora\prompts), digest no Córtex, /ctx doctor e /ctx stats, mensagem final ao Danilo (texto + áudio pelo Dipsy) com: o que ficou feito, o que ficou retido e porquê, RAM antes/depois.
