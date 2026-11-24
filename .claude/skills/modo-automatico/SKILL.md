---
name: modo-automatico
description: "Modo automático em qualquer projeto: analisar, fazer, testar e corrigir num ramo ai/AAAA-MM-DD-descricao, abrir pedido de revisão, esperar os testes verdes e PUBLICAR com o publicar-pedido.mjs, conferindo nas 3. Usar em todo o trabalho técnico."
---

# Modo automático

> Escrita a 05/11/2026 (missão `modo-automatico-seguro-2026-11-05`). Mudada a 24/11/2026 por ordem do Danilo:
> "Eu quero que o Claude Code publique. Você dá uma missão para ele, ele faz toda a missão, ele verifica toda a
> missão e publica, quando tiver certeza que está tudo certo. O Claude Code, o Hermes e o Gypsy têm que publicar
> também. Não para em nada." O Danilo só fala contigo. Nunca lhe devolvas passos, comandos ou ficheiros para ler.

## Regra de ouro

**Tu fazes, testas e publicas.** A missão só acaba publicada e conferida em Android, iPhone e web.

Publicar é: juntar ao ramo principal, deploy, publicar site, enviar para a loja Android ou iOS, Edge
Function em produção, migration em produção. Tudo isso é teu, com três condições:

1. **Certeza antes de publicar:** testes locais (tabela abaixo) e os testes automáticos do pedido de revisão
   todos verdes. Teste vermelho = encontrar a causa e corrigir; nunca apagar, saltar ou enfraquecer o teste.
2. **Código no ramo principal só pelo script** `node .claude/tools/publicar/publicar-pedido.mjs <número>`: confere o CI
   verde do commit exato, junta sem forçar e acompanha a publicação. Push direto ao ramo principal é recusado.
3. **Dinheiro continua a ser do Danilo:** preços, comissões, ganhos, Stripe, tokens, carteiras, RLS de dinheiro
   e funções de pagamento só com `AUTORIZO` dele no prompt (ver "Dinheiro"). As travas recusam o resto.

## Ciclo de cada tarefa

1. **Ler:** memória, Córtex, `erros-aprendidos` e as regras do projeto. Ver `git status`.
2. **Isolar:** ramo exclusivo num worktree, sem mexer no trabalho que o Danilo já tem. Sempre com
   `--no-track`: sem isso o ramo novo fica a seguir o de produção e um `git push` sem destino vai lá parar.

   ```bash
   git fetch origin
   git worktree add --no-track -b ai/AAAA-MM-DD-descricao C:/BoraLocal/wt-descricao origin/<ramo-principal>
   ```

3. **Fazer** a tarefa.
4. **Testar** conforme o projeto (tabela abaixo). Comando sem erro não é prova: prova é SELECT,
   `e2e_log` ou teste que mostra o resultado.
5. **No máximo 3 tentativas por problema.** Se continuar a falhar, descarta o worktree, volta ao estado
   anterior sozinho e reporta a causa.
6. **Entregar:** commit, envio do ramo de ensaio com destino escrito, e pedido de revisão com o que
   foi feito, os testes e o resultado, e os ficheiros mudados.

   ```bash
   git push origin ai/AAAA-MM-DD-descricao
   gh pr create --base <ramo-principal> --title "..." --body "..."
   ```

7. **Publicar:** espera os testes automáticos do pedido e publica. O script recusa com teste vermelho, com
   testes a correr (usa `--esperar-ci` para esperar) e com conflitos; junta, envia e acompanha as 3.

   ```bash
   node .claude/tools/publicar/publicar-pedido.mjs <número> --esperar-ci
   ```

   Migrations e Edge Functions que não são de dinheiro: aplica-as tu (MCP `apply_migration`,
   `deploy_edge_function`) e põe o mesmo ficheiro no repo com a versão que o servidor gravou.
8. **Conferir nas 3:** Android (Play), iPhone (App Store/TestFlight) e web. Corrida vermelha = causa, conserto,
   novo pedido. Só aí a missão acabou.
9. **Registar** no `e2e_log` e no Córtex.
10. **Relatório curto** em texto corrido: "fiz isto, publiquei, confirmei nas 3" ou "falta isto e porquê".

Erro encontrado pelo caminho: conserta na hora se estiver no âmbito, senão reporta. Nunca cales.

## Testes por tipo de projeto

- **Flutter:** `flutter analyze`, `flutter test`, build. Respeita o portão de memória (800 MB).
- **Web:** lint, build e ligações.
- **Supabase:** SQL, RLS, funções e SELECT de prova. Antes de aplicar em produção: cópia `bkp_` do que muda,
  prova numa transação desfeita quando der, e depois `apply_migration`. A de dinheiro fica pronta em
  `docs/propostas` com o pedido de "autorizo".
- **Stripe:** só modo de teste, webhooks e idempotência.
- **Obsidian:** ligações e estrutura. Ler, não reorganizar.
- **Sem repositório remoto:** ramo local e testes locais; diz no relatório que não há pedido de revisão.

## As travas

Bloqueiam sem perguntar, mesmo em "Ignorar permissões". Ficheiro: `~/.claude/hooks/trava-modo-automatico.mjs`
(versão 2 de 24/11: publicar passa; instalação em `docs/propostas/publicar-sozinho-2026-11-24/`).
Se esse ficheiro não existir, **estas regras valem à mesma**.

- DELETE, TRUNCATE e DROP que leva dados (tabela, schema, coluna) em produção. DROP de trigger, função,
  policy ou índice dentro de uma migration passa. Destino que não se consegue identificar conta como produção.
- `git push --force`, reescrever história, apagar ramos remotos, versões publicadas ou backups.
- Push direto ao ramo principal, `gh pr merge` e juntar pela API: usa o `publicar-pedido.mjs`.
- `supabase db push` em produção (aplicaria todas as migrations do repo de uma vez): usa `apply_migration`.
- Transferências, levantamentos e payouts do Stripe ao vivo.
- Ler, escrever, gravar ou mostrar chaves, segredos e `.env`. Usa só variáveis de ambiente. Antes de
  cada commit a trava procura segredos no que vai gravado.
- Escrita direta em pedidos, carteiras, ledger e tokens: usa só as funções e RPC que já existem no banco.
- A `bora-tranca` continua a recusar o que é dinheiro (funções, RLS e settings de dinheiro, Edge Functions de
  pagamento, `pricing_service`, `.github/workflows`).

Bloqueio de trava ou da tranca: **não contornes**, nem por outra ferramenta nem por outro caminho.
Regista no `e2e_log` com estado `bloqueado`, em `docs/TRANCAS.md`, e segue com o resto.

Antes de qualquer migration ou mudança de dinheiro cria ponto de restauro (`bkp_<nome>_AAAAMMDD`, com
RLS ligada). Nunca apagues dados de produção.

## Dinheiro

Podes mexer no que a app já faz com dinheiro (cobranças, reembolsos, tokens, comissões, preços,
carteiras, Stripe) **só** quando o prompt da tarefa trouxer `AUTORIZO: <operação, projeto, ambiente, limites>`
do Danilo.

- Vale só para essa tarefa e esse âmbito. Nunca é permanente e nunca se alarga por interpretação.
- Preços e comissões só com ordem clara.
- Sem `AUTORIZO` no prompt: podes ler, analisar e desenvolver em teste, mas não mudar regras de dinheiro.
- Nunca escrevas em settings, `CLAUDE.md` ou skill que um pedido do Danilo é autorização permanente.

## Como falar com o Danilo

Português claro, sem jargão, texto corrido, para ouvir em voz alta. Não lhe peças para ler nem para
aprovar. Só lhe pedes o que uma trava exige humano, num passo, com a página aberta à frente dele.
