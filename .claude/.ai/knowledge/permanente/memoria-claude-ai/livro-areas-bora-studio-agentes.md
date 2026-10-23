---
id: memoria-claude-ai-livro-areas-bora-studio-agentes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Sistema de fiscais/agentes do Bora Studio — estado, falhas descobertas e método de validação (continuação de filme-animacao)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-bora-studio-agentes`, origem `claude-ai`, atualizada em 2026-10-23T05:38:23.658086+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas bora studio agentes · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/bora-studio-agentes.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: bora-studio-agentes
description: Sistema de fiscais/agentes do Bora Studio — estado, falhas descobertas e método de validação (continuação de filme-animacao)
sources: [chat]
aliases: [fiscais, agentes de visão, meta-juiz]
---

## Descoberta decisiva 30/07 — os fiscais de visão NÃO funcionavam
- DeepEval 4.1.4 instalado; meta-juiz construído (12 casos de defeito plantado com gravidade conhecida, confirmados visíveis antes de usar)
- RESULTADO: **2/12**. Falharam: crop 5/10/15% e pan 5/10/15% (nenhum dos 6), cabelo mudado 30/60/**100%** (nenhum dos 3), duas Tailines lado a lado. Passaram só: rosto trocado, e o caso limpo (não inventar defeito)
- CAUSA (não é limiar): os fiscais RECITAM A FICHA em vez de olhar a imagem. Cabelo todo branco → "cabelo castanho claro, longo, ondulado" → APROVADO. Duas Tailines → "apenas uma Tailine visível" → APROVADO. Viés de confirmação assado no prompt: dá-se a descrição esperada e pergunta-se "bate?"
- A correção óbvia (descrever às cegas primeiro, depois comparar) NÃO chegou: continuou 2/12
- CONSEQUÊNCIA: as REPROVAÇÕES da auditoria dos 125 continuam válidas (o que achou, achou). Mas as APROVAÇÕES não valem nada — os 70 clipes "limpos" nunca foram verificados de facto. Reauditar depois de os fiscais funcionarem
- Os fiscais de enquadramento/movimento nunca recebiam o frame de referência para comparar — falha estrutural
- BOA NOTÍCIA: a métrica GEOMÉTRICA apanha os 6 casos de enquadramento com precisão de 3pp e passou 8/8. Para enquadramento o instrumento certo não é o Gemini, é geometria

## Decisão do Claude: TRÊS métodos, não um
1. GEOMETRIA para enquadramento e movimento — já provado, elimina a versão Gemini
2. COMPARAÇÃO IMAGEM-A-IMAGEM (ficha e frame lado a lado, nunca ficha em texto) para identidade, cabelo, duplicado, figurino. Justificação: `rosto_trocado` foi o ÚNICO caso de visão que passou, e é o único que compara duas imagens. É a 5ª vez que o princípio central do projeto se confirma — trava-se/verifica-se com imagem, nunca com palavras
3. PERGUNTA ABERTA E CEGA para os de imagem única (escala, forma planetária, anatomia, população, expressão): nunca mencionar o esperado. "Quantas crianças aparecem?" em vez de "só há uma criança, certo?". A pergunta que contém a resposta esperada convida à confirmação

## Inventário dos agentes (30/07)
- 24 construídos em 7 ficheiros; 21 já emitiram veredictos reais
- 14 fiscais de visão em visao.py (1 chamada Gemini por peça, logo 12 chamadas validam os 14)
- 6 fiscais estáticos deterministas, custo zero: idade_escolaridade, figurino_sussurrador, props_por_era, teologia, continuidade_historia (bloqueantes), presenca (revisão)
- 4 próprios: fiscal_lipsync, fiscal_audio (único validado por medida física), fiscal_dialogo, metrica_enquadramento (validado R31)
- FALTAM 11, dos quais 9 SÓ podem existir depois da montagem (continuidade entre planos/figurino/cenário, coerência do local, eixo e olhar, física, ritmo, mistura de áudio, sincronia da fala). Obrigatórios antes da entrega: supervisor de cena e DIRETOR FINAL


## O RELÓGIO — loop autónomo da noite (esquematizado 30/07)
- [stated] Danilo quer autonomia TOTAL a noite toda até o Ep1 estar pronto: alguém tem de ir ver o Kaggle de 10 em 10 min (ele próprio disse que 30 min é muito) e agir logo que termine
- DESENHO ESCOLHIDO: TIQUE SEM ESTADO, não processo residente. O Task Scheduler do Windows acorda scripts/relogio.py de 10 em 10 min; ele lê o producao.db, decide UMA ação, executa, escreve, e morre. Razão: um processo residente MORRE por OOM no PC de 4GB — já aconteceu 2x e ninguém relançou. O que vive 10 segundos não morre de fome
- Deteção de encravado: RUNNING acima de 2x o tempo esperado = aviso; acima de 3x = cancela e relança uma vez; se repetir, salta o lote. Nunca fica preso no mesmo erro (2 tentativas e segue)
- Guarda de quota: para de lançar aos 28h de 30h e acorda o Danilo. Nunca chega a zero
- Log escreve linha em TODO tique, mesmo quando não há novidade — senão não se distingue "tudo bem" de "morri"
- Duas filas: GPU (serial, o Kaggle só corre 1 sessão) = 58 planos → decupagem v6 → vozes → música → RVC → lip-sync S2V → montagem. CPU (paralela) = reescrever os 14 fiscais pelos 3 métodos → revalidar com o meta-juiz → frames v6 via Gemini → reauditar os 70 "limpos"
- Só acorda o Danilo se: quota acabou · decisão de gosto · erro estrutural · EPISÓDIO PRONTO
- Artifact: PROMPT-RELOGIO-NOITE.md (a colar quando o executor acabar o que está a fazer)

## O REPRESENTANTE DO DANILO + hierarquia (31/07, correção final dele)
- [stated] "Eu não vou entrar pra NADA. Quem vai fazer a minha parte é um agente. Eu só vou pegar o vídeo final." Nem finalistas de voz chegam a ele
- ADENDO-REPRESENTANTE-E-CHEFIA.md: agentes/representante_danilo.py = o CLIENTE dentro do estúdio, com veto final. Decide com base em canon/gosto_danilo.md — modelo de gosto extraído de TODAS as decisões/reprovações do histórico (criança soa a criança de DESENHO; tudo se compara visualmente com os 4 protagonistas; vilão com presença de adulto; julgamento em ecrã grande; gestos sim/enquadramento não; lugar público tem gente; diversão pesa tanto quanto correção; o mundo faz sentido). Documento VIVO: cada reação do Danilo ao episódio final vira entrada nova → o Representante converge pro gosto dele a cada episódio
- Representante decide com OLHOS/OUVIDOS (R24), nunca rebaixa critério — manda refazer. Resolve sozinho as vozes pendentes (meninos, Luara, Tabita provisória, resto da mesa)
- HIERARQUIA: CHEFE DE ESTÚDIO (dono do resultado, responde ao Representante) · SUBCHEFE DE QUALIDADE (comanda fiscais + AUDITORIA CRUZADA: amostragem de peças aprovadas verificadas por caminho independente; discordância = investigar o fiscal) · SUBCHEFE DE PRODUÇÃO (animador/ponte/relógio/quota) · AUDITOR DO AUDITOR (meta-juiz semanal com defeitos plantados NOVOS — fiscal que passa sempre no mesmo teste decorou o teste; padrão Red Queen/Co-Evolving Critics 2026) · BATEDOR (vasculha o mundo semanal — arXiv/HF/GitHub trending; máx 3 recomendações acionáveis; nunca troca ferramenta a meio de episódio sem A/B) · POLIDOR DE ROTEIRO (máx 5 melhorias pequenas por episódio, nunca reescreve sozinho)
- Fundamentos publicados: Multi-Agent Evolve (Proposer/Solver/Judge, +4,5% sem supervisão humana), SAGE 4 agentes, Co-Evolving Critics (o crítico evolui com a política senão fica cego), FilmAgent/AniME/MovieAgent
- FLUXO FINAL: ...montagem → supervisores de cena → auditoria cruzada → DIRETOR FINAL vê o episódio inteiro → REPRESENTANTE vê com o gosto do Danilo → só se AMBOS aprovarem → entrega. PRECISA_DANILO reservado a: episódio pronto · quota esgotada · conflito que o gosto genuinamente não resolve (1 linha + recomendação)
- Cada reação do Danilo ao vídeo final vira entrada no gosto_danilo.md — é assim que ele deixa de corrigir a mesma coisa duas vezes

## PROMPT MESTRE entregue (31/07) — consolida tudo
- PROMPT-MESTRE-BORA-STUDIO.md SUBSTITUI o PROMPT-ESTUDIO-COMPLETO e o ADENDO-REPRESENTANTE-E-CHEFIA (Danilo nunca colou os dois — pediu cruzamento num só, enorme). Danilo estava sem limite de sessão; agora voltou
- F0 INVENTÁRIO obrigatório antes de construir (não reconstruir os ~24 agentes/infra que existem) · F1 BÍBLIAS por departamento (padrão da conversa dele c/ ChatGPT, adotado: World/Character/Prop/Style/Camera/Lighting/Voice/Music/Humor/Continuity/Physics/Production) · F2 Representante+gosto_danilo · F3 hierarquia (Chefe/Subchefes/Auditor-do-Auditor/Batedor/Polidor) · F4 os 4 agentes NOVOS exigidos: DIRETOR FINAL COM DESPACHO (assiste o episódio inteiro, encontra todos os erros, despacha correção automática ao departamento responsável com plano+timestamp+evidência, loop até zero bloqueantes), EDITOR/montador (cortar é grátis, gerar custa GPU), VERIFICADOR DE ASSETS (hash+inspeção visual: o ficheiro no disco É o aprovado?), OPERADOR DE IMAGEM Gemini/Nano Banana (gera cenário/prop/expressão em falta, sempre com âncora de imagem, retry na quota) · F5 padrões do ChatGPT adotados: EVENTOS no quadro (mudança na bíblia dispara reverificação sozinha), tarefas com dependências, MÉTRICAS por agente (precisão medida, queda = investigação), PÓS-MORTE de erro (docs/posmortes/ — causa, que fiscal deixou passar, que regra nasceu; R01-R31 passam a nascer daí) · F6 retomar produção só depois do meta-juiz validar os novos
- Do material ChatGPT: adotado bíblias/métricas/pós-morte; o resto já existia melhor no nosso sistema

## Bloqueio Gemini + estado 31/07 (tarde)
- ⚠️ PRECISA_DANILO: API Gemini BLOQUEADA por faturação ao nível do projeto Google (403 "Lightning dunning decision is deny", projeto 765097014497) — nem listar modelos funciona. Perde-se: fiscais de visão, olhos/ouvidos do Representante, geração de imagem. Não se perde: GPU Kaggle + fiscais de código puro. Caminhos: (A) criar chave NOVA grátis no AI Studio (aistudio.google.com, free tier sem cartão, ~2 min) e trocar no .env; (B) resolver billing em console.cloud.google.com/billing
- gosto_danilo.md criado: 26 princípios, cada um com a reprovação real de origem. Representante não rebaixa critério ("nenhum serve" em vez do menos mau)
- R36 gravada: instrumento tem de DISCRIMINAR, não só passar teste sintético (ouvido acústico p/ vozes: extração de formantes dava "68 anos" p/ todos os 36; LPC melhorou mas instável — vozes NÃO foram escolhidas com instrumento sem confiança)
- Música: 3 tentativas — acestep não existe no PyPI; git clone sem verificar import; pip install -e DEPOIS do processo arrancar (sys.path em cache — verificou num subprocesso, passou lá, falhou no processo real). Lição: verificar no sítio errado é não verificar. 3ª a correr
- Mudos TODOS animados (0 por animar); 34 falados esperam vozes. Editor é o único agente novo que não depende do Gemini — autorizado avançar
- Bíblias/hierarquia/3 dos 4 agentes novos ficaram por construir À ESPERA do Gemini (decisão certa: construir o que não pode correr é trabalho a fingir)

## Ideias do ChatGPT — triadas 31/07 (não perder)
ADOTADO AGORA (resolvem dor real, feitos em paralelo sem parar produção):
- ROTEAMENTO DE MODELOS COM QUEDA AUTOMÁTICA: generalizar agentes/modelos.py (que já escolhe por exercício) para cadeia de provedores por tarefa (visão/áudio/imagem/texto); se der 429 ou 404 cai pro seguinte sem parar o tique; grátis primeiro; registar sempre qual provedor serviu. Motivo: hoje o estúdio PAROU quando a quota do Gemini acabou
- ARQUITETO DO ESTÚDIO: agente semanal que não produz nada — lê quadro/logs/métricas e responde "há agentes redundantes? há gargalo? há trabalho desperdiçado?", máx 3 recomendações com evidência. Motivo: a escuta gastava quota por ordem alfabética em personagens com nota 100 enquanto o Gustavo (sem voz) ficava no fim — é exatamente o que ele devia ter apanhado

GUARDADO PARA O EPISÓDIO 2 (bom, mas reescrever agora atrasava o Ep1):
- GRAFO DE CONHECIMENTO único: personagem→objeto→cena→plano→voz→roupa, para uma mudança propagar sozinha a todos os agentes (ex.: mochila muda de cor → figurinista, storyboard, animador e continuidade sabem na hora). As 12 bíblias já cobrem ~80% disto
- BIBLIOTECA DE ESTILOS reutilizável (catálogo "Disney 3D", "Pixar", etc. que qualquer agente invoca)
- Departamentos como SKILLS independentes (/cast, /storyboard, /animate, /music, /render) em vez de prompt gigante — facilita trocar modelo sem mexer no resto
- Orçamento como regra do sistema: cada agente estima custo/tempo ANTES de começar

NÃO ADOTADO (arquitetura sem prova, não resolvem problema atual): mercado interno de agentes com leilão de confiança · "DNA" por elemento (Visual/Voice/Animation/Emotion/Personality/Lore/Memory/Relationship DNA)

NOTA DE PRINCÍPIO: o que funcionou neste projeto foi apanhado da realidade a duro (3 métodos de fiscal, validação por defeito plantado, ficha nasce da imagem) — cada regra custou um erro real. Empilhar arquitetura nova sem prova afasta o Ep1. Prioridade fixa: regenerar 150 falas → animar 34 falados → canções → mistura → montagem → Diretor Final → episódio

## Encravamento silencioso 01/08 — "bater não é trabalhar"
- Estúdio parado ~2h45 e o LOG PARECIA TRABALHO: as batidas escreviam "avancei o CPU: arquiteto_semanal" mas o Arquiteto responde "já corri hoje, sou semanal" e volta à fila. O avanço de CPU pegava só na PRIMEIRA pendente → ficou preso nele para sempre. Corrigido: percorre a fila até achar trabalho a sério, e quem espera é dito como espera
- Segunda avaria: 4 tarefas presas em `a_correr` de uma era anterior (musica_acestep, rvc_cancoes, lipsync_s2v, montagem_final) — nada corria, e o selector só escolhe `pendente`. Fila viva no papel, morta na prática
- SINAL DE DIAGNÓSTICO (vale para o Danilo e para o Arquiteto): se o log do relógio repetir a MESMA LINHA 3x seguidas, está parado — mesmo que a linha diga que avançou. Arquiteto passou de semanal a diário enquanto o Ep1 não sair
- Tempos esperados: kernel na fila 1-5min (>30 encravado) · RVC 2 canções 15-25min (>60) · animar 15 planos de canção 35-50min (>90) · montagem final 10-20min (>45)
- Estado: 168/190 clipes. Faltam 15 de canção + 7 dependentes, todos à espera do RVC
- Música RESOLVIDA (4ª tentativa): causa real era OOM na GPU, mascarada 3 corridas por um fallback para `acestep.cli` que NUNCA existiu ("alternativa que nunca funcionou não é rede de segurança, é venda nos olhos"). Curas: expandable_segments, pipeline carregado 1x, empty_cache entre faixas, faixas de 30s, faixa de prova antes das 19
- R37 gravada: quando se gera média, mede-se a SAÍDA CONTRA A ENTRADA, não contra zero — 10 das 150 falas existiam, abriam e tinham som mas duravam 19s para 27 caracteres (XTTS estica com texto curto + referência longa). Nenhuma verificação apanhou porque todas perguntavam "existe? abre? tem som?". Ritmo medido nas boas: 0,8s + 0,16s/caractere
- Medida do zumbido estava PARTIDA e quase passava por limpa: delta 0,0 dB exato nas 11 faixas (dois `-af` no mesmo comando ffmpeg, o segundo apaga o primeiro → comparava cada faixa consigo própria). Mesmo padrão do ouvido acústico que dava 68 anos a todos: instrumento que devolve sempre o mesmo número não está a medir. Depois de corrigido: criacao_epico -8,3dB e final_esperanca -7,0dB no passa-alto duplo → tratados com filtrar-primeiro-nivelar-depois; espalho caiu de 5,7 para 2,2 dB
- [stated] 31/08, REGRA DELE (disse corrigindo sugestão de meter créditos no Higgsfield): o motor de geração de vídeo/imagem é o próprio Bora Studio — nunca sugerir serviços pagos de geração; quando faltar uma capacidade, o caminho é procurar no mundo uma ferramenta GRATUITA e integrá-la no sistema do Bora Studio. Vale também para trabalho de clientes (ex.: filmes de imóveis das maquetes de sites)
