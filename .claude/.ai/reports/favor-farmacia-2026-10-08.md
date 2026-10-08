# Favor da farmácia — passos do estafeta, valor certo, receita por foto, botões do Android (08/10/2026)

Missão do pedido real 74dd4ecc (Cristina, Farmácia Tavares). Claude Code no PC do Danilo, ramo
autonomous-night-2026-04-29. Chefe Opus; leitura de código e varredura de ecrãs feitas por
agentes Sonnet; revisão de contexto limpo por outro agente.

Acessos usados: Supabase do Bora (projeto ojykpzwqrtusfeakzrna) pelo conector MCP; emulador
Android 15 local (emdia35). Nenhuma conta criada, nenhuma palavra-passe escrita.

## O que NÃO ficou feito, logo à cabeça

ESTADO_DO_ENVIO

O ficheiro da folha do Favor no estafeta (errand_execution_sheet.dart) é zona trancada por ter o
fecho do talão. Não lhe toquei. Corrigi tudo por fora e deixei a correção de dentro pronta, num
patch de 51 linhas que aplica limpo: .claude/.ai/missoes/favor-08-10/pronto/errand_execution_sheet.PROPOSTA.patch.
Para entrar precisa da tua mão (a tranca só abre assim).

A tranca também recusou guardar no repositório a cópia da função do talão que a Claude.ai alterou
no servidor a 08/10 (finalize_errand_purchase). A função no ar está certa; só a cópia no repo é
que falta. Atenção: a versão que ficou registada na lista de migrações do servidor não é a que
está no ar (a registada escrevia em total e customer_total, que são colunas geradas; a do ar
escreve em price).

Provas com as contas demo a sério na app (entrar como cliente e estafeta demo e fazer os dois
Favores no emulador): não fiz, porque obrigava-me a escrever a palavra-passe das contas demo numa
app ligada ao servidor de produção, e isso as minhas regras de segurança não deixam. Fiz a mesma
prova pelo servidor, com as mesmas funções que a app chama, numa transação desfeita, e a prova
visual no Android 15 com um Favor de exemplo, sem login. O autoteste dos 3 perfis do CI (que
entra com as contas demo) corre sozinho no envio.

iPhone com o indicador de casa: não há simulador de iPhone neste PC; a prova é o build do CI.

RESTO_DO_RELATORIO
