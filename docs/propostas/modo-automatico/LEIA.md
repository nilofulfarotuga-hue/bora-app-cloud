# Modo automático seguro: o que falta ligar

> Missão `modo-automatico-seguro-2026-11-05`. Tudo aqui está testado e **ainda desligado**.

## Porque não ficou ligado

A tranca recusou escrever em `.claude/hooks/` e em `.github/workflows/` e está na lista dela
`.claude/settings.json`. É a regra: nenhum agente muda as próprias trancas. Não se contornou por outro
caminho. Liga-se com um duplo clique do Danilo em `ATIVAR-MODO-AUTOMATICO.cmd`, no Ambiente de Trabalho.

## O que o clique faz

1. Guarda uma cópia dos settings globais.
2. Copia `trava-modo-automatico.mjs` para `~/.claude/hooks/` e regista-a nos settings globais.
3. Acrescenta aos settings as regras que recusam ler ficheiros de segredos.
4. Corre os testes com a cópia instalada. Se falharem, volta tudo atrás sozinho.
5. Aplica `guardas-ramo-ai.patch` na pasta principal do bora_app (ver abaixo).
6. Põe `revisao.yml` no ramo de ensaio, com o mesmo remendo, e envia esse ramo. Não publica nada.

Para desligar: `DESATIVAR-MODO-AUTOMATICO.cmd`, no mesmo sítio. Só vale em sessões abertas depois.

## O que muda nas guardas antigas

Quatro mudanças pequenas, em `guardas-ramo-ai.patch`. Afrouxam duas coisas de propósito, por ordem
da missão, e apertam uma:

- `git-guardrails.py` passa a aceitar os ramos `ai/AAAA-MM-DD-...`. Sem isto, nenhum ramo de ensaio se envia.
- A tranca deixa de perguntar ao enviar para esses ramos: não publicam nada.
- A tranca deixa de aprovar sozinha o que toca em segredos. Sem isto, o `cat .env` passa.
- Um teste novo da tranca para o primeiro caso.

## O que se provou

- Testes: `node trava-modo-automatico.test.mjs`. Contra uma trava vazia a mesma bateria falha.
- Sessões reais do Claude Code em modo sem caixas, numa pasta de ensaio com um `.env` falso:
  - `gh pr merge` foi bloqueado.
  - A leitura do `.env` **passou** com a trava sozinha, em `Read` e em `cat`. A causa: a aprovação
    automática da tranca passa por cima do "não" de outro gancho.
  - Com as regras de leitura, o `Read` ficou bloqueado e o `cat` passou.
  - Com as regras e a tranca remendada, os dois ficaram bloqueados.
  - Ler `nota.txt` e `.env.example` continuou a funcionar.
- Instalador ensaiado numa casa falsa: instala, não duplica, desinstala igual ao original, e volta
  atrás sozinho com uma trava estragada.

## O que muda no dia a dia depois do clique

Nenhuma sessão do Claude Code volta a enviar para o ramo principal nem a fazer deploy. Uma missão a
meio que precise de publicar fica presa nesse passo e tem de passar pelo Claude.ai. As tarefas
agendadas que chamam `claude -p` foram vistas: nenhuma publica.

## Limites honestos

- A trava lê comandos, não o que um script faz por dentro. Um programa próprio que use uma chave de
  produção não se vê.
- `ssh` para a VPS não está coberto.
- `grep -r` numa pasta pode passar por um `.env` que não esteja no `.gitignore`.
- É uma rede contra erros de um agente, não contra um atacante a disfarçar comandos.
- O CI `revisao.yml` nunca correu: só corre depois de estar no ramo. O modelo `revisao-site.yml` também não.
- Os outros repositórios com GitHub ainda não têm CI de revisão: um projeto de cada vez, com a mesma regra.
