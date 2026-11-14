---
name: modo-automatico
description: "Modo automático seguro em qualquer projeto: analisar, fazer, testar e corrigir num ramo ai/AAAA-MM-DD-descricao, abrir pedido de revisão e NÃO publicar (publica o Claude.ai). Usar em todo o trabalho técnico."
---

# Modo automático seguro

> Escrita a 05/11/2026 (missão `modo-automatico-seguro-2026-11-05`). O Danilo só fala contigo.
> Nunca lhe devolvas passos, comandos ou ficheiros para ler. A segurança vem das travas, não de perguntas.

## Regra de ouro

**Tu fazes e testas. Tu não publicas.** Quem verifica em Android, iPhone e web, e publica, é o Claude.ai.

Publicar é: juntar ao ramo principal, deploy, publicar site, enviar para a loja Android ou iOS, Edge
Function em produção, migration em produção, ou qualquer mudança em produção que altere o negócio.
Isto passa à frente da regra antiga "toda a sessão acaba com o envio para o servidor".

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
6. **Entregar:** commit, envio só do ramo de ensaio, com destino escrito, e pedido de revisão com o que
   foi feito, os testes e o resultado, e os ficheiros mudados.

   ```bash
   git push origin ai/AAAA-MM-DD-descricao
   gh pr create --base <ramo-principal> --title "..." --body "..."
   ```

7. **Registar** no `e2e_log` e no Córtex.
8. **Relatório curto** em texto corrido: "fiz isto, falta isto".

Erro encontrado pelo caminho: conserta na hora se estiver no âmbito, senão reporta. Nunca cales.

## Testes por tipo de projeto

- **Flutter:** `flutter analyze`, `flutter test`, build. Respeita o portão de memória (800 MB).
- **Web:** lint, build e ligações.
- **Supabase:** SQL, RLS, funções e SELECT de prova. Migrations só em ambiente local; sem ele, fica
  a proposta pronta em `docs/propostas` e aplica-a o Claude.ai.
- **Stripe:** só modo de teste, webhooks e idempotência.
- **Obsidian:** ligações e estrutura. Ler, não reorganizar.
- **Sem repositório remoto:** ramo local e testes locais; diz no relatório que não há pedido de revisão.

## As travas

Bloqueiam sem perguntar, mesmo em "Ignorar permissões". Ficheiro: `~/.claude/hooks/trava-modo-automatico.mjs`.
Se esse ficheiro não existir, a trava ainda não foi ligada e **estas regras valem à mesma**.

- DELETE, DROP e TRUNCATE em produção. O ambiente local fica livre; destino que não se consegue
  identificar conta como produção.
- `git push --force`, reescrever história, apagar ramos remotos ou backups.
- Envio para qualquer ramo que não seja `ai/AAAA-MM-DD-descricao`.
- Transferências, levantamentos e payouts do Stripe ao vivo.
- Ler, escrever, gravar ou mostrar chaves, segredos e `.env`. Usa só variáveis de ambiente. Antes de
  cada commit a trava procura segredos no que vai gravado.
- Publicar, tal como definido em cima.
- Escrita direta em pedidos, carteiras, ledger e tokens: usa só as funções e RPC que já existem no banco.

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
