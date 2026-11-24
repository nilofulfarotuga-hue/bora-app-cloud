# Quem faz a missão publica (24/11/2026)

Ordem do Danilo, 24/11 às 07:47: "Eu quero que o Claude Code publique. Você dá uma missão para ele, ele faz
toda a missão, ele verifica toda a missão e publica, quando tiver certeza que está tudo certo. O Claude Code,
o Hermes e o Gypsy têm que publicar também. Não para em nada."

Substitui a regra de 05/11 ("o Claude Code faz e testa, publica o Claude.ai").

## O que muda

| Quem | Antes | Agora |
|---|---|---|
| Claude Code (trava global v2) | push só para `ai/`; juntar, deploy, migration e Edge Function recusados | push normal passa; deploy, migration e Edge Function passam; o ramo principal recebe código só pelo `publicar-pedido.mjs` |
| bora-tranca (pasta principal) | push, migration, DDL e deploy recusados ("publica o Claude.ai") | seguem e ficam no registo; o que é dinheiro continua recusado |
| Dipsy (dsh-bora 0.4.0) | push, migração e deploy perguntavam ao Danilo pelo Telegram | push de `ai/` passa; migração e deploy normais passam; push direto ao principal é barrado; dinheiro continua a perguntar |
| Hermes | (sem trava de publicar) | regra escrita no `SOUL-base.md` e no livro: publica pelo mesmo script |

## O que continua travado (não tem volta ou é dinheiro)

- Apagar dados de produção (DELETE, TRUNCATE, DROP de tabela, schema ou coluna), apagar ramos, versões e backups.
- `git push --force`, reescrever história, `supabase db push` em produção (aplicaria tudo de uma vez).
- Ler ou escrever segredos e `.env`.
- Dinheiro: funções, RLS e settings de dinheiro, Edge Functions de pagamento, `pricing_service`, Stripe ao vivo
  (transferências e payouts nunca). Isto continua a precisar do "autorizo" do Danilo.
- Push direto ao ramo principal, `gh pr merge` e juntar pela API: o caminho é o script, que confere o CI.

## O script de publicar

`node .claude/tools/publicar/publicar-pedido.mjs <número> [--esperar-ci]`

1. O pedido tem de estar aberto e vir deste repositório.
2. Todos os testes automáticos do commit exato têm de estar acabados e verdes (`--esperar-ci` espera até 150 min).
3. Junta numa pasta à parte (merge normal, sem forçar) e envia. Conflito ou ramo que mudou: recusa.
4. Acompanha as corridas de publicação (Android, web, iPhone) e sai com 3 se alguma ficar vermelha.

Testes: `node .claude/tools/publicar/publicar-pedido.test.mjs` (12 casos, remoto local e `gh` falso, sem rede).

## Provas feitas antes de pedir o clique

- Trava v2: `node trava-modo-automatico.test.mjs` → 153 a bloquear, 107 a deixar, 0 falhas (25 casos passaram de
  "bloqueia" para "deixa": todos são publicar; 18 casos novos a bloquear, entre eles as Edge Functions de dinheiro).
- Guarda do Dipsy 0.4.0: 319 testes, 0 falhas.
- Remendo da tranca: aplica sobre a tranca do PC como ficou a 05/11 (remendos `guardas-ramo-ai` e
  `guardas-sem-pergunta`); `tranca.ts` e o teste compilam. Os testes da tranca só correm dentro do Claude Code.

## Como se liga

Duplo clique do Danilo em `ATIVAR-PUBLICAR-SOZINHO.cmd` (Ambiente de Trabalho). Vai buscar estes ficheiros ao
GitHub sem mexer na pasta de trabalho, guarda cópias, instala, corre os testes e volta atrás sozinho se falharem.
Registo em `~\.claude\publicar-sozinho-instalacao.log` e estado em `~\.claude\publicar-sozinho-estado.json`.
Para voltar atrás: `DESATIVAR-PUBLICAR-SOZINHO.cmd`.

## Limites honestos

- A trava lê comandos, não o que um script faz por dentro: é uma rede contra erros, não contra quem a quer enganar.
- O script confia nos testes que o repositório tem. Repositório sem testes no GitHub só publica com
  `--sem-ci-testado-local`, e isso fica escrito no commit.
