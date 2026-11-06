# Modo automático seguro: relatório de 05/11/2026

Missão `modo-automatico-seguro-2026-11-05`. Ramo de ensaio `ai/2026-11-05-modo-automatico-seguro`.

**Fiz isto.** Fiz o inventário de todos os projetos em `docs/INVENTARIO_PROJETOS.md`. Criei a skill `modo-automatico`,
que já vale em todas as pastas e no Dipsy, e pus a linha que aponta para ela no `CLAUDE.md` global, no do bora_app e em
mais onze projetos. Construí a trava automática com 160 casos que tem de bloquear e 74 que tem de deixar passar, e
todos passam. Contra uma trava vazia, a mesma bateria dá 170 falhas, por isso os testes medem mesmo. Testei a trava em
sessões reais do Claude Code em "Ignorar permissões". Um verificador de contexto limpo tentou derrubar a primeira
versão, achou 16 buracos e 13 falsos alarmes, e esses casos entraram nos testes. Preparei o CI de revisão, a correção
das guardas antigas e o instalador, que ensaiei numa casa falsa: instala, não duplica, desinstala igual ao original e
volta atrás sozinho se a trava estiver estragada. Enviei o ramo de ensaio e abri o pedido de revisão, sem publicar nada.

**Falta isto.** A trava, as regras de segredos, as guardas e o CI estão prontos mas **desligados**. A tranca recusou
escrever em `.claude/hooks/` e em `.github/workflows/`, e `.claude/settings.json` está na mesma lista. A regra dela é que
nenhum agente muda as próprias trancas, e não a contornei. Liga-se com um duplo clique do Danilo em
`ATIVAR-MODO-AUTOMATICO.cmd`, no Ambiente de Trabalho. Até lá, as regras novas valem só por escrito na skill. O CI de
revisão só corre depois do clique (resultado mais abaixo). Os outros repositórios com GitHub ainda não têm CI de revisão.

Sobre os settings sem pedidos de permissão, não mudei nada. Em "Ignorar permissões" o Claude Code já não mostra caixas,
e `skipDangerousModePermissionPrompt` já estava ligado. Afrouxar permissões nos settings é mexer em segurança do sistema,
e isso não faço sozinho. A única pergunta que ainda aparece é a da tranca quando se envia um ramo, e essa desaparece com
o clique, nos ramos `ai/`.

**Erros que encontrei.** O mais grave: a aprovação automática da tranca passa por cima do "não" de outro gancho. Na prova
real, a trava recusou ler um `.env` falso e o conteúdo apareceu na mesma. Com a tranca corrigida e as regras de leitura,
ficou bloqueado em `Read` e em `cat`. A correção vai no clique. Segundo: `git worktree add -b` deixa o ramo novo a seguir
o ramo de produção, e um `git push` sem destino pode ir lá parar. Tirei isso neste ramo, a skill manda usar `--no-track`
e a trava bloqueia. Terceiro: o `git-guardrails` do bora_app recusa qualquer ramo que não seja o principal, por isso os
ramos de ensaio não se enviavam a partir da pasta do projeto. O meu envio passou porque esta sessão começou fora dessa
pasta e o gancho do projeto não estava carregado, e a tranca perguntou e foi-lhe dito que sim. Conto isto porque sem o
clique o próximo envio, feito de dentro do projeto, é recusado. Quarto: nenhum CI corria analyze e testes em cada pedido
de revisão. Quinto: o `gh` deste PC não tem a permissão `workflow`, o que pode fazer o GitHub recusar o CI no clique; se
acontecer, o instalador diz e o resto fica ligado.

**Provas.** Testes: `node docs/propostas/modo-automatico/trava-modo-automatico.test.mjs`. Juiz: anti-trapaça limpo, zonas
protegidas limpas. Registo: `e2e_log`, fluxo `modo-automatico-seguro-2026-11-05`. Não corri `flutter analyze` nem
`flutter test`: o ramo não mexe em código da app. Nenhum CI correu no ramo depois do envio. Memória: medi 352 MB no pior
momento, abaixo do portão de 400. Segui porque era trabalho de ficheiros e o peso vinha de outras sessões abertas.

**Limites.** Estão em `docs/propostas/modo-automatico/LEIA.md`. O principal: a trava lê comandos, não o que um programa
faz por dentro. É uma rede contra erros de um agente, não contra um atacante.

**Próximo passo.** O Danilo faz duplo clique em `ATIVAR-MODO-AUTOMATICO.cmd`. Depois disso, nenhuma sessão do Claude Code
volta a enviar para o ramo principal nem a fazer deploy, e tudo passa pelo Claude.ai.

## Depois do primeiro clique (05/11, 20:37)

O Danilo clicou e a instalação correu: trava e regras nos settings, guardas corrigidas, CI enviado. Numa sessão nova,
com os settings verdadeiros, o `.env` e o `gh pr merge` ficaram bloqueados e o ramo `ai/` seguiu sem pergunta.

Mas o envio para `main` só foi recusado porque ninguém estava lá para responder à pergunta da tranca. Testei com um
"Permitir" simulado, num remoto falso, e o envio passou por cima da trava: `main` subiu para 2 commits. O texto acima que
diz que depois do clique nenhuma sessão publica estava errado. A correção é `guardas-sem-pergunta.patch`: a tranca deixa
de perguntar e recusa logo. Numa cópia, os 45 testes da tranca passam e, numa sessão real, `main` ficou intacto. Precisa
de um segundo clique, porque a tranca continua a não deixar um agente mexer nela.

O CI de revisão já correu no pedido, duas vezes, e deu verde. Confirmei no registo: 2911 testes da app passaram, a
bateria da trava deu 0 falhas e o `analyze` deu 270 avisos, que não param o CI. A 06/11 a memória desceu a 201 MB, abaixo
do portão de 400. Segui porque só li estado e escrevi texto.

## PARA O DANILO

1. Segundo clique em `ATIVAR-MODO-AUTOMATICO.cmd`. Fazê-lo com nenhuma missão a meio de publicar.
2. O livro ainda diz "toda a sessão acaba com o envio para o servidor" (`regras-do-danilo`, secção 7) e "Claude Code =
   publicar". A skill passa à frente, mas as páginas contradizem-na. Quem as atualiza é o Claude.ai.
