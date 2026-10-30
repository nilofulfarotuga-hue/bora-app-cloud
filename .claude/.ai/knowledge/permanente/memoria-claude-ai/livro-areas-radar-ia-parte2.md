---
id: memoria-claude-ai-livro-areas-radar-ia-parte2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos (parte 2 de 3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-radar-ia-parte2`, origem `claude-ai`, atualizada em 2026-10-30T15:15:54.302199+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas radar ia parte2 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/radar-ia.md, parte 2 de 3 — começa em livro-areas-radar-ia, continua em livro-areas-radar-ia-parte3), copiada a 30/10/2026 15:15 (hora de Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

🎬 23/08 ACHADO TRAZIDO POR ELE (transcrição de vídeo sobre o "Comfy MCP") — veredito meu, registado no Córtex em `radar-ia-2026-34`
- [stated] Colou a transcrição e perguntou se dá para encaixar no sistema dele e se é grátis; pediu para NÃO fazer prompt, só deixar guardado o que há a fazer para quando se mexer no Studio
- O QUE É (fonte primária): `comfy-mcp` da Comfy Org, lançado 11/08/2026, MCP oficial aberto que deixa Claude Code/Desktop/Cursor/ChatGPT conduzir o ComfyUI — instala modelos, valida e corre workflows, gera imagem/vídeo/áudio/3D/upscale. Docs em docs.comfy.org/agent-tools/mcp
- ❌ NÃO ADOTAR, por duas razões independentes: (1) HARDWARE — o servidor local exige ComfyUI vivo com GPU em 127.0.0.1:8188; o PC é Celeron 4GB sem placa, e o autor do vídeo corre numa RTX 3050 8GB dizendo que está "no mínimo". A única variante sem placa é a Comfy Cloud e EXIGE SUBSCRIÇÃO PAGA (créditos avulso não chegam). (2) DESENHO — o Studio já faz isto headless no Kaggle/Colab/Lightning com Wan 2.2 e relógio de 15 min; ComfyUI é GUI de nós, era reintroduzir trabalho manual. Mesmo raciocínio que arquivou o VoiceBox a 04/08: interessa o motor, nunca a janela
- ❌ NANO BANANA (segundo achado da mesma mensagem): já é dele, é o operador de imagem do Studio. O "Nano Banana Video" com conector MCP (nanobananavideo.com/mcp) existe mas gera por créditos e o uso comercial sem marca de água é pago — rejeitado pela regra do preço. FACTO a não voltar a confundir: o Nano Banana é modelo de IMAGEM, não gera vídeo
- ✅ O ÚNICO PEDAÇO QUE VALE E É GRÁTIS: upscale em DUAS passadas, a segunda dedicada só ao rosto — é ordem de operações, não ferramenta, e faz-se nos kernels grátis sem ComfyUI. Detalhe e condições em [[filme-animacao]]

💰 02/09 RADAR-DINHEIRO (segundo radar do batedor)
- [stated] Danilo colou transcrição de vídeo brasileiro (Pulso Social, postagem automática em grupos do Facebook) e pediu: analisar, pôr o sistema a ver mais vídeos deste estilo para achar formas de ele ganhar dinheiro, usar o grupo de WhatsApp para anunciar o Bora, e mais jeitos de ganhar além dos sites (só teve um resultado até agora); "preciso ganhar dinheiro de algum jeito"; quer modo automático, ele só confirma
- Veredito meu: NÃO instalar Pulso Social (afiliado + robô de Facebook = risco de bloqueio da conta do Bora); única ideia aproveitável = 3 imagens + 3 textos diferentes, um por grupo
- [stated] PROMPT REGISTADO: `PROMPT_radar_dinheiro_2026-09-02.md`, entregue 02/09, MOTOR OPUS, janela Pro, sessão `radar-dinheiro`. Scope: script `/opt/data/scripts/radar-dinheiro.sh` copiado do radar-ia.sh, quarta 09:00 Lisboa, yt-dlp legendas + readpage, regras duras a rejeitar ferramenta paga/afiliado/robô de redes, saída Telegram + `/opt/data/radar-dinheiro/AAAA-SS.md` + Córtex. Estado: entregue como ficheiro; nada disparado

🎥 17/09 RADAR DOS VÍDEOS DO HISTÓRICO DELE (3.ª vez que pede varredura de vídeos)
- [stated] Quer que o sistema veja os vídeos do HISTÓRICO do YouTube dele (falou de 500 a 1000), faça um resumão e diga o que FALTA no sistema dele; pediu também para "inventar alguma coisa". CRYPTO/Bitcoin fica FORA por ordem expressa dele. Temas que quer: IA, agentes, Claude Code/ChatGPT/Gemini, vender sites, ganhar dinheiro
- [stated] Disse que tinha começado a correr um prompt meu e parou por acabarem os créditos, e esqueceu-se de retomar
- ✅ VERIFICADO por mim no Córtex (caixa `hermes-reporte`): o `radar-dinheiro.sh` do prompt de 02/09 FOI instalado e ESTÁ VIVO — correu 16/09 (semana 2026-38, gemini-3.6-flash, 9 vídeos, 4 artigos, entregue no Telegram). A linha acima "entregue como ficheiro; nada disparado" está SUPERADA
- 🚨 BURACO REAL DOS DOIS RADARES: a corrida de 16/09 diz "9 vídeos vistos (0 com legenda real)" — estão a opinar pelo TÍTULO. Causa: correm na VPS e o YouTube recusa legendas a IP de datacenter sem cookies
- SOLUÇÃO desenhada: correr no PC dele com `yt-dlp --cookies-from-browser chrome` — histórico pelo atalho `:ythistory`, legendas por `--write-auto-subs`; grátis e sem chave nenhuma
- DESENHO QUE BAIXA O CUSTO (o que faz isto ser possível com mil vídeos): "nomes primeiro, resumo só do que é novo" — extrair só nomes de ferramentas/repos/modelos das legendas, cruzar com `INVENTARIO.md` (o que ele já tem e o que já foi rejeitado), e só os candidatos NOVOS vão a modelo (Ollama local, de noite). Claude entra só no veredito final
- [stated] PROMPT REGISTADO: `PROMPT_radar_video_historico_2026-09-17.md`, entregue 17/09, MOTOR SONNET, SESSÃO NOVA no Claude Code, pasta bora-app-cloud, run_id `radar-video-2026-09-17`. Scope: B0 inventário com hardware MEDIDO (não assumir os 4 GB do PC velho) · B1 histórico por yt-dlp+cookies · B2 filtro de tema · B3 legendas a sério · B4 extração de nomes · B5 leitura a fundo só dos novos, teto 200/noite, retomável · B6 relatório com máx. 10 achados + 3 ideias novas + nota de voz no Telegram · B7 tarefa agendada 02:00 e corrigir os dois radares da VPS para dizerem "sem legenda" em vez de opinar. Estado: entregue como ficheiro, por colar

🎬 17/09 VEREDITO DO VÍDEO QUE ELE COLOU ("10 skills e ferramentas para o agente Hermes") — ⚠️ o Hermes do vídeo é o da Nous Research, NÃO é o Emerson dele
- ✅ ADOTADOS (só registados como proposta no Córtex, cada um espera janela própria): (1) WORKTREE/pasta por missão, ideia tirada do Superpowers — dor provada: o mesmo prompt colado em duas janelas custou meia sessão, e a missão de 19/08 apareceu com 106 ficheiros mexidos por outros processos; entra como reforço de skill que já existe, nunca como plugin · (2) ACABAR O CÓRTEX EM VETORES no Supabase — a função `match_cortex_knowledge` foi criada pelo ChatGPT dele a 12/09 direto na produção e ficou SEM TABELA; é o mesmo valor do "Codebase Memory MCP" do vídeo mas com infra que ele já paga · (3) 5-6 SKILLS DE MARKETING EM PORTUGUÊS (página que converte, SEO local, email frio, anúncios) — nunca importar pacotes de 49 skills em inglês
- ✅ JÁ DELE mas mal explicado no vídeo: o Agent-Reach é TRANSCRIÇÃO de áudio, não extractor (confirma o achado de 21/08) — e é isso que resolve os vídeos sem legenda, com o `faster-whisper` LOCAL do PC (áudio por `yt-dlp -x`, teto 30/noite, NUNCA Groq/OpenAI pagos)
- ❌ REJEITADOS com motivo, para não voltar a discutir: **Caveman** (só corta a SAÍDA, o próprio vídeo admite que não toca input nem raciocínio; e é pior para ele, que OUVE as respostas) · **GJ Code** (3.ª ferramenta igual às duas que já tem, e o argumento principal — entrar com a conta Claude por fora — é proibido pelos ToS da Anthropic desde 04/04/2026, foi por isso que o OpenCode perdeu esse login) · **Open Montage** (mesma armadilha do ComfyUI: GPU + modelos pagos; a única parte boa, pré-visualização com custo antes de gastar, faz-se de graça no Studio) · **Defuddle** (já há readpage/Jina + trafilatura desde 21/08) · **humanizadores em inglês** (faz-se em casa, em PT) · **marketplace de APIs pago** do fim do vídeo
- ⚠️ REGRA PARA ESTES VÍDEOS: os números de estrelas do GitHub vinham inflacionados e o próprio autor admitiu não ter testado uma das skills — confirmar na fonte primária antes de dar valor a um achado de vídeo
- ESTADO CORRIGIDO da missão radar-video: ele JÁ tinha colado o prompt principal quando eu lhe mandei o ficheiro atualizado, e ficou chateado com isso ("você tinha que mandar só um adendo"). O resto seguiu como ADENDO em texto literal para a MESMA janela: whisper local no B3, os 3 achados a registar por `cortex_propor`, e a lista de já-rejeitados para o `INVENTARIO.md` do B0

🧠 24/09 JEV (TypeSafe AI) — o "Jedi"/"JEV" do voice-to-text é isto; não voltar a procurar outro nome
- [stated] Viu vários vídeos (Facebook/YouTube) sobre o Jev e quer incluí-lo no Hermes e "no sistema todo" se for útil; pediu a minha opinião e o ponto de situação antes de mexer
- Estado real (verificado por SELECT em e2e_log e digest no Córtex, 23/09): missão `jev-decisor-2026-09-23` correu em sessão cloud e fechou — Edge Function `decidir` (Jev → Gemini de reserva), tabela `decisoes`, 4 regras em SOMBRA (`platform_settings decisor_*_modo`), cron `decisor-varrer`, ecrã admin "Decisões (Jev)" em `/admin/decisoes`. FALTA: a chave da TypeSafe (acesso antecipado limitado; conta a criar no Chrome dele — ordem `.claude/.ai/inbox/CONTINUAR-jev-decisor-2026-09-23.md`) e a reserva Gemini do Supabase está morta (quota/503, derruba também o Robot B)
- Veredito meu: adotar só onde a tarefa é DECIDIR (Porteiro do Telegram, despachante de bots, triagem IG/WhatsApp, as 4 regras em sombra, filtro dos radares) — nunca para código, texto, reels ou juiz; Gemini fica sempre de reserva

📹 24/09 RADAR DIÁRIO DE CRESCIMENTO NAS REDES (4.ª vez que pede vídeos; irritado por "nunca ter tido resposta")
- [stated] Quer ~20 vídeos NOVOS do YouTube por dia sobre como crescer/viralizar no Instagram/Facebook e como ganhar dinheiro/marketing, guardados num sítio, e que isso vire regras que os robôs de conteúdo do Bora e do Em Dia seguem para melhorar sozinhos; disse que não tem muitos contactos em Portugal, por isso o crescimento tem de vir disto, não da rede pessoal dele
- Missão `radar-videos-crescimento-2026-09-24` colada na sessão "PC do Danilo" (recolha no PC por causa das legendas, tabela radar_videos, playbook-redes no Córtex, robôs e fiscal a ler o playbook, Telegram 20:00). Estado: na fila, por provar

📹 04/10 RADAR DE VÍDEOS (5.ª vez que pede)
- [stated] 04/10: disse que não via resultado nenhum do agente de vídeos; quer que procure também como ganhar dinheiro com IA, projetos e automação — tudo o que ele conversa com o Claude — e a partir das sugestões da página inicial do YouTube dele ("o YouTube já sabe os vídeos de que eu gosto")
- [stated] 04/10 noite: regra permanente — tudo o que ele conversa com o Claude vira tema para o radar pesquisar vídeos; quer o radar a ver vídeos de como fazer desenho animado com IA de graça, sem placa de vídeo, por várias formas (para acabar o filme das filhas, [[filme-animacao-v3]], "mais de dois meses a tentar e sai sempre uma bosta")
- [stated] 04/10 noite: o Jev "pode deixar, depois nós vemos" — fica para depois (o banco recusou o cartão para o crédito da TypeSafe)

🔍 17/10 RADAR CALOU O REA (6.ª reclamação de vídeos)
- [stated] 17/10: queixou-se de que o radar não lhe falou da moda da engenharia reversa (REA)
- Causa provada por SELECT em radar_videos: >10 vídeos REA nota 8-9 entre 12/10 e 17/10; um ficou "novo" a 13/10 (reduzido a "auditar o nosso APK") e os restantes foram marcados "ja_temos" sem nada feito; o passo "aprende" deixava de fora por ter 70 termos. Prompt da tarefa agendada "Radar de vídeos: o que presta hoje" (trig_01HyoFVDdR2xe42uYRbZVuhN) reescrito a 17/10: veredito novo 'pendente'; 'ja_temos' só com prova; regra da MODA (3+ vídeos nota ≥8 em 7 dias vão sempre na mensagem, com estado feito/pendente); troca de termo quando há 70; lente de engenharia reversa (ferramenta paga → procurar equivalente grátis no GitHub)

🔎 21/10 VERIFICAÇÃO DO RADAR (7.ª vez que pede: "vai a fundo no GitHub, ferramentas pagas copiadas de graça")
- MEDIDO em radar_videos: o radar corre todos os dias (20-41 vídeos/dia, quase todos com legenda real) e desde 17/10 já usa o veredito "pendente". Pendentes fortes que continuam SEM nada feito: REA (npx rea-agents setup, só no NOSSO APK/site — proposta de 13/10), rececionista de voz por IA para PMEs (13/10), Claude Dashboards/Motion (11/10), Orca (09/10), Jev alternativa aberta (08/10), Flow "último fotograma"/Extend e ferramenta no Flow (filme)
- CONFIRMADO NA FONTE 21/10 (dois "clones grátis" do radar): (1) **OmniRoute** (github.com/diegosouzapw/OmniRoute, `npm i -g omniroute`, porta 20128, junta 40+ fornecedores com tier grátis e roda sozinho quando um cai) — é proxy/router → PROIBIDO no Claude Code pela regra ferramenta de 13/09 e ToS; único encaixe possível é na VPS para os agentes automáticos (regra 26/09 "cai um, rotaciona para o outro"); por decidir, não instalado. (2) **DeskcommCRM** (github.com/melgarafael/DeskcommCRM, MIT, do Rafael Melgaço): CRM + agentes de IA no WhatsApp, white-label por variáveis de ambiente, instala numa VPS com 1 comando, 7 contentores, 2-4 GB RAM, WhatsApp por QR (WAHA, risco de bloqueio) ou API oficial da Meta, precisa chave de IA (OpenRouter/Anthropic/OpenAI). Candidato real para o pacote "atendente WhatsApp" vendido a PMEs — pendente de janela própria, não cabe junto do Hermes sem medir RAM da VPS
- Pippit (Story Studio, créditos grátis diários) entrou como degrau novo a medir no prompt do filme de 21/10
- [stated] 23/10/2026: pediu o OmniRoute "geral" (Claude Code, Hermes, talvez robô do Bora) porque fica parado quando acaba o limite. Decidido por mim: OmniRoute na VPS só com chaves de API/grátis sem conta, para Hermes, 5 bots, torre e juiz; reserva do PC = OpenCode apontado ao OmniRoute (lançador SEM-LIMITE.cmd); fora: conta Claude, ChatGPT/Codex por login e Gemini por cookie (termos, risco de banir contas), Claude Code intocado, robôs do app só relatório. PROMPT REGISTADO: `PROMPT_omniroute_2026-10-23.md`, MOTOR OPUS, app Claude no PC › Code › bora_app › Ignorar permissões, fluxo e2e_log `omniroute-23-10`. Estado: entregue

🤖 29-30/10 "DIPSY" = o DeepSeek Harness (dsh) instalado no PC dele (ele diz "Gipsy/Dipsy/Hermes" por voz; missão "DeepSeek Harness installation", sessão própria dele)
- [stated] O Dipsy tem de saber de tudo do sistema e ser igual ou melhor que o Claude Code: Córtex e livro comum nele, todos os plugins/MCPs que o Claude Code tem (Supabase, Gmail pessoal e da Bora, "tudo e mais um pouco"), as 50 melhores ferramentas adaptadas ao sistema dele
- [stated] Regra dele: cada missão fica na sua própria sessão do Claude Code; a sessão do Harness é paralela à da Bora e não se mistura

