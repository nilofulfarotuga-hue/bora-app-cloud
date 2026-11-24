# Relatório — radar-fila-2026-11-23

Missão escrita pela Claude.ai (ordem do Danilo de 23/11), executada pelo Claude Code no PC, motor Opus 5.5, das 06:13 às ~08:15 de Lisboa. Registo completo no `e2e_log`, fluxo `radar-fila-2026-11-23`.

## Fiz isto

O radar de vídeos passou a ver o que o Danilo vê. Os 184 vídeos que a Claude.ai pôs na fila (122 do histórico do YouTube dele e 62 da página inicial) foram todos tratados no PC: legenda, resumo pelo Gemini e transcrição completa. A corrida de hoje de madrugada, que fiz à mão no Chrome certo, acrescentou mais 50. No fim ficaram 231 feitos, 2 sem legenda (gravados só com o resumo da descrição), 1 ignorado e nenhum por fazer. Na tabela `radar_videos` estão agora 122 vídeos do histórico e 113 da página inicial, com 231 transcrições completas, e a busca "canal dark com claude" devolve cinco vídeos certos, quatro deles da página inicial dele.

No script `radar_crescimento.py` (pasta `QG\radar-crescimento`, fora do git) entrou o modo `processar-fila`. Segue o mesmo caminho do recolher: legenda em português ou inglês e resumo pelo Gemini. Quando não há legenda, usa o faster-whisper local, no máximo 10 por noite e só com 1500 MB livres; se não der, o vídeo fica como `sem_legenda`. O recolher normal também passa a guardar a transcrição completa. O lançador novo é o `run_fila.ps1`, que corre logo a seguir ao recolher diário e às 03:00 (tarefa nova `RadarFilaBora`). A migração com as portas da fila ficou no ramo. A tranca não me deixou aplicá-la, e foi a Claude.ai que a aplicou em produção.

A recolha da madrugada foi corrigida. A ordem `radar-historico` agora segue a página do livro `radar-recolha-sons-do-ceus` e usa sempre o Chrome e6eec594 (perfil "TikTok Vo Tonico", conta Sons do Céus). A tarefa `BoraRadarHistorico` estava desligada desde 14/11: liguei-a outra vez e mudei-a para as 02:00. A corrida forçada de hoje confirmou a conta certa e leu 525 vídeos do histórico e 143 da página inicial. Ficaram 67 de IA e negócio, dos quais 50 eram novos. O resto era das filhas, música, política e notícias, e foi para fora. No YouTube só li, não carreguei em nada.

A regra "antes de uma tarefa, consulta `radar_buscar` e o playbook do tema" está agora em três sítios. Está no CLAUDE.md do repositório e no ficheiro de regras comum do Claude Code e do Dipsy (é o mesmo ficheiro). Está também na alma do Hermes, na linha 125, com 7 865 bytes. O Hermes gravou-a pelo despacho e outro agente conferiu.

Os 15 playbooks estão no livro, com entre 1 375 e 4 017 caracteres cada. Foram escritos pelo Gemini, sem a API paga do Claude. O Juiz chumbou a primeira versão, porque os passos vinham do campo "ideias", escrito por outro modelo, que inventava coisas como o "Em Dia" e os "clientes B2B". Corrigi a causa: agora o material é o resumo do que cada vídeo diz. Na segunda ronda, o Juiz aprovou dois com correções e chumbou o de delivery. O Refinador aplicou as decisões do Juiz e varreu as regras do Danilo nos outros doze. Fez 8 cortes: routers à frente do Claude Code, ferramentas que precisam de muita memória e propostas em massa (spam). O playbook de delivery ficou curto e diz com franqueza que os vídeos ainda ensinam pouco sobre entregas.

Por autorização do Danilo, passada pela Claude.ai, libertei memória: fechei 8 sessões do Claude Code que estavam paradas desde 17 a 22/11. A RAM livre subiu de 366 para 1 555 MB. Fiquei a funcionar com essa memória, mas 40 minutos depois estava outra vez nos 300 MB, por causa do Chrome das outras sessões.

## Falta isto

Juntar o ramo `ai/2026-11-23-radar-fila` e publicar é da Claude.ai. O ramo leva a migração, a linha no CLAUDE.md, a cópia dos scripts em `docs/radar-fila-2026-11-23` e este relatório. Os ficheiros do PC (o script, os lançadores e a ordem da madrugada) já estão a valer, porque vivem fora do git. As próximas provas automáticas são a corrida das 02:00, a das 03:00 e a do recolher das 18:00.

## Erros que encontrei (no e2e_log como "achado", não corrigidos)

1. Quando já existiam por pesquisa, 16 vídeos do Danilo ficaram com a origem "pesquisa": a página da madrugada não os mete na fila, e por isso perdem o peso extra que a busca dá ao histórico e à página inicial.
2. O recolher diário corre às 18:00 no inverno, não às 19:00, porque a tarefa tem o horário guardado em UTC.
3. A `radar_fila` tem RLS sem políticas, mas mantém as permissões de tabela por defeito para o anon. Hoje isso não abre nada, mas convém retirá-las.
4. O mapa de contas não tem o perfil e6eec594.
5. A memória volta a acabar sozinha, por causa do Windows Terminal (1,9 GB) e dos separadores do Chrome de outras sessões.
6. As ordens fixas vivem fora do git.
7. O Gemini flash-lite deu muitos erros 503 de serviço indisponível. A reserva aguentou.

## Próximo passo

A Claude.ai junta e publica o ramo. Na tarefa das 20:52 ("o que presta hoje"), os playbooks passam a ser reescritos pelo `radar_crescimento.py playbooks`, com o Juiz a ver pelo menos um por dia.
