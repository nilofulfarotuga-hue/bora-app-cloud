# Relatório — missão sistema-conteudo-14-11 (14/11/2026)

Claude Code no PC, Opus 5.5 como maestro, seis ajudantes; o texto em volume foi pelo opencode grátis.
Prova de cada passo no e2e_log (fluxo `sistema-conteudo-14-11`). Ramo: `ai/2026-11-14-sistema-conteudo`.

## Fiz isto

O livro deixou de ir para o repositório público. Criei um repositório privado só para ele, `bora-livro`, e o
espelho da VPS já envia para lá. A pasta do livro e o ficheiro com a chave da TestSprite saíram do repositório
da app, e procurei outras chaves: não há mais nenhuma secreta na árvore atual. O histórico antigo ficou como
estava, como pediste.

Fiz o gancho que obriga a gravar a lição quando o Danilo corrige, e testei-o: a linha de teste ficou no livro.
Pelo caminho encontrei um defeito sério: a cópia do livro que todas as sessões do PC leem ao arrancar estava
parada desde 25 de outubro e cortava precisamente as correções mais recentes. Agora guarda as últimas e
renova-se sozinha de hora a hora.

Reescrevi o orquestrador (CEO-AI v3) com o fluxo real, a entrevista antes de missão grande e a regra do motor.
Arrumei as skills: de 153 para 133, as duplicadas juntas numa só, as que nunca correram arquivadas (nada
apagado), e as descrições curtas. Uma sessão nova gastava 58,3 mil tokens só a arrancar e agora gasta 48,7 mil;
a lista das skills caiu para metade. O gancho de arranque passava do tamanho que o Claude Code aceita e
perdia-se quase todo: agora cabe. O juiz-revisor nunca tinha funcionado por um erro de formato no cabeçalho
(396 vezes "não encontrado"): está consertado e já aparece. Instalei o Context7 para a documentação estar
sempre atual.

O radar passa a mandar-te 5 opções numeradas às 21:30 e percebe quando respondes "1 3 faz". Limpou a fila:
21 duplicados fechados, 98 vídeos mandados fazer em 6 tarefas, e os que ficam têm o motivo escrito. O agente de
segunda corre às 8 da manhã de Lisboa com o Haiku e já fez a corrida de prova. No painel há o ecrã "Caixa de
guardados", com o quadro Sim/Não e o botão "Correr agora", que já funciona.

Na VPS limpei 508 MB só do que se regenera e instalei o motor grátis do CRM de WhatsApp, fechado para dentro,
parado no ecrã do QR sem ligar nenhum número.

Na fábrica de conteúdo ficaram as 4 personagens (Irmã Lúcia, Vô Tonico, Vó Celeste e Malu), cada uma com
ficha, 10 roteiros e um caderno em PDF revisto página a página, e a série gospel da história de Rute pronta
para gerar. Tudo em `C:\BoraLocal\ConteudoIA`.

## Falta isto (e porquê)

O envio para o ramo de produção: a tranca recusa-o ao Claude Code, por isso a Claude.ai junta o ramo de ensaio.
Registar o gancho das correções no `settings.json`: a tranca protege esse ficheiro; a linha exata está em
`docs/propostas/sistema-conteudo-14-11/registar-gancho-aprender.md`. O "Sim" da caixa e do radar no painel
precisa de uma migração pequena que a tranca não me deixou aplicar (`PROPOSTA_20261114_quadro_sim_nao_painel_admin.sql`).
As imagens das 4 personagens: a quota grátis de imagens estava a zero. As duas imagens de prova do Kaggle: a
versão nova está na fila atrás da antiga e deve sair por volta das 18:50 UTC. O Postiz não está instalado na
VPS. O CLAUDE.md global ainda cita os nomes antigos da entrevista; não mexi porque está ligado ao do Dipsy.

## Erros que encontrei

A cópia do livro parada desde 25/10. O gancho de arranque grande demais. O juiz-revisor e mais 9 cabeçalhos
partidos. As regras de bloqueio de escrita do `settings.json` só valem para o Edit, não para o Write (quem
protege de facto é a tranca). A função `log_admin_action` em texto deixa qualquer utilizador com sessão
escrever no registo de auditoria. A ponte do Kaggle diz "espera" e não envia. As 4 imagens da v57 que foram
julgadas chumbaram todas na qualidade.

## Próximo passo

A Claude.ai junta o ramo, aplica a migração do quadro e a linha do gancho, e decide os prompts do filme.

## PARA O DANILO (responde "1 sim, 2 não")

1. Revogar a chave da TestSprite no painel deles (está no histórico público).
2. Criar o endereço crm.boraguarda.com e abrir o CRM do WhatsApp na internet com HTTPS.
3. Ligar o número de WhatsApp do CRM (ler o QR com o telemóvel desse número).
4. Tirar o Hermes 0.17 de recuo da VPS (liberta cerca de 7 GB; o 0.23 corre há 3 dias sem falhas).
5. Criar os canais de YouTube das 4 personagens como contas de marca e os perfis de Instagram, TikTok e a
   Página do Facebook (lista em `C:\BoraLocal\ConteudoIA\CONTAS-PARA-O-DANILO.md`).
6. Instalar o Postiz na VPS para a publicação por API.
