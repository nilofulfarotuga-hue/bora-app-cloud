# Modo automático seguro: como se liga

> Missão `modo-automatico-seguro-2026-11-05`. Primeiro clique do Danilo a 05/11 às 20:37: trava, regras,
> guardas e CI ligados. Falta um segundo clique para `guardas-sem-pergunta.patch`: sem ele, um "Permitir"
> na pergunta da tranca ainda publica. O instalador é o mesmo e pode correr as vezes que for preciso.

## Porque não se liga sozinho

A tranca recusou escrever em `.claude/hooks/` e em `.github/workflows/` e está na lista dela
`.claude/settings.json`. É a regra: nenhum agente muda as próprias trancas. Não se contornou por outro
caminho. Liga-se com um duplo clique do Danilo em `ATIVAR-MODO-AUTOMATICO.cmd`, no Ambiente de Trabalho.

## O que o clique faz

1. Guarda uma cópia dos settings globais.
2. Copia `trava-modo-automatico.mjs` para `~/.claude/hooks/` e regista-a nos settings globais.
3. Acrescenta aos settings as regras que recusam ler ficheiros de segredos.
4. Corre os testes com a cópia instalada. Se falharem, volta tudo atrás sozinho.
5. Aplica `guardas-ramo-ai.patch` e `guardas-sem-pergunta.patch` na pasta principal do bora_app (ver abaixo).
6. Põe `revisao.yml` no ramo de ensaio, com os mesmos remendos, e envia esse ramo. Não publica nada.

Para desligar: `DESATIVAR-MODO-AUTOMATICO.cmd`, no mesmo sítio. Só vale em sessões abertas depois.

## O que muda nas guardas antigas

Dois remendos. O primeiro, `guardas-ramo-ai.patch`, afrouxa duas coisas de propósito, por ordem da missão:

- `git-guardrails.py` passa a aceitar os ramos `ai/AAAA-MM-DD-...`. Sem isto, nenhum ramo de ensaio se envia.
- A tranca deixa de perguntar ao enviar para esses ramos: não publicam nada.
- A tranca deixa de aprovar sozinha o que toca em segredos. Sem isto, o `cat .env` passa.

O segundo, `guardas-sem-pergunta.patch`, aperta:

- `git push` fora de `ai/`, migrations, mudanças de estrutura e deploy de Edge Functions passam a ser
  recusados, em vez de perguntar. Sem isto, um "Permitir" passa por cima da trava e publica.
- A exceção são as cópias `bkp_`, que têm de continuar a funcionar: são o ponto de restauro.
- A lista de segredos que a tranca não aprova sozinha fica igual à da trava.
- Os testes da tranca mudam com isto: 45 passam.

## O que se provou

- Testes: `node trava-modo-automatico.test.mjs`, 160 casos a bloquear e 74 a deixar passar. Contra uma
  trava vazia a mesma bateria dá 170 falhas.
- Um verificador de contexto limpo tentou derrubar a primeira versão com 524 entradas e achou 16 buracos
  e 13 falsos alarmes. Os casos dele entraram nos testes; o que ficou de fora está nos limites abaixo.
- Sessões reais do Claude Code em modo sem caixas, numa pasta de ensaio com um `.env` falso:
  - `gh pr merge` foi bloqueado.
  - A leitura do `.env` **passou** com a trava sozinha, em `Read` e em `cat`. A causa: a aprovação
    automática da tranca passa por cima do "não" de outro gancho.
  - Com as regras de leitura, o `Read` ficou bloqueado e o `cat` passou.
  - Com as regras e a tranca remendada, os dois ficaram bloqueados.
  - Ler `nota.txt` e `.env.example` continuou a funcionar.
  - Depois do primeiro clique, com um "Permitir" simulado, o envio para `main` **passou** por cima da
    trava num remoto falso. Com `guardas-sem-pergunta.patch`, foi recusado e o ramo `ai/` seguiu.
- Instalador ensaiado numa casa falsa: instala, não duplica, desinstala igual ao original, e volta
  atrás sozinho com uma trava estragada.

## O que muda no dia a dia depois do clique

Nenhuma sessão do Claude Code volta a enviar para o ramo principal nem a fazer deploy. Uma missão a
meio que precise de publicar fica presa nesse passo e tem de passar pelo Claude.ai. As tarefas
agendadas que chamam `claude -p` foram vistas: nenhuma publica.

## Limites honestos

- A trava lê comandos, não o que um script faz por dentro. Um programa próprio que use uma chave de
  produção não se vê, nem um `fetch` escrito em código.
- `ssh` para a VPS não está coberto: o que corre lá dentro não se lê.
- `grep -r` numa pasta pode passar por um `.env` que não esteja no `.gitignore`.
- Um alvo guardado numa variável não se resolve: `foreach ($d in "backups") { Remove-Item $d }` passa.
- `git reset --hard` e `git clean -f` ficam com a tranca, que já os recusa.
- Qualquer projeto Supabase fora da lista `PROJETOS_ENSAIO` conta como produção. A lista está vazia:
  um ramo de ensaio do Supabase só funciona depois de o Danilo o acrescentar à mão.
- É uma rede contra erros de um agente, não contra um atacante a disfarçar comandos.
- O CI `revisao.yml` nunca correu: só corre depois de estar no ramo. O modelo `revisao-site.yml` também não.
- Os outros repositórios com GitHub ainda não têm CI de revisão: um projeto de cada vez, com a mesma regra.
