# Decisor Jev — relatório da missão jev-decisor-2026-09-23

## Acessos

Base de dados de produção Supabase ojykpzwqrtusfeakzrna. Conta TypeSafe: nenhuma criada (ver abaixo). Conta alvo para a criar: boraappbora@gmail.com com "Continue with Google". Criado nesta sessão: a Edge Function decidir (versão 4), a tabela decisoes, sete definições decisor_ em platform_settings, seis funções na base (decisor_chave_typesafe, decisor_modo, decisor_itens_pendentes, decisor_preencher_resultados, admin_decisor_resumo, admin_decisor_set_modo) e a tarefa agendada decisor-varrer, de 30 em 30 segundos. Nenhuma chave nova foi criada e nenhuma chave ficou no repositório.

## O que NÃO foi feito

Primeiro, a conta e a chave do Jev não existem. Esta missão correu numa sessão na nuvem, sem o Chrome do PC e sem o perfil Bora, e a rede daqui bloqueia o site da TypeSafe. Não houve forma de abrir a consola. Está tudo pronto do lado da Bora: no dia em que a chave for posta no Vault com o nome typesafe_api_key, o decisor passa a usar o Jev sozinho, sem mexer em código.

Segundo, a comparação lado a lado entre o Jev e o Gemini não aconteceu. Fiz as vinte chamadas reais, com casos reais anonimizados, mas o Jev não tinha chave e a chave Gemini do Supabase estava sem quota. Só uma das vinte teve resposta, e errou.

Terceiro, o modo ativo só existe para o Robot B. Para a escolha do estafeta, ligar o decisor ao motor de despacho é zona protegida, por isso fica só a observar. Para o risco de falta nas marcações e para o suporte, ainda não há uma ação definida, e por isso também só observam.

Quarto, não copiei o relatório para a pasta do Ambiente de Trabalho, porque esta sessão não tem acesso ao PC. O relatório está na raiz do repositório. O resumo em duas frases foi pelo Telegram, pelo bot da Bora, e chegou (mensagem 8317).

## O que ficou a funcionar

O decisor é uma porta única, a Edge Function decidir. Recebe uma pergunta pequena de um de três tipos: escolher uma opção, dar uma nota numa escala, ou responder sim ou não. Recebe também o estado da situação. Devolve sempre a mesma coisa: a resposta, a confiança, as probabilidades de cada opção, o motor que respondeu e quanto tempo demorou. Tenta primeiro o Jev. Sem chave ou com erro, passa ao Gemini com o mesmo formato, a tentar três modelos por ordem. Cada decisão fica gravada na tabela decisoes, com os tokens e o custo. Mais tarde, a base escreve lá o que aconteceu de verdade, para se medir se acertou. Só o painel admin lê a tabela; só o servidor escreve nela.

As quatro regras estão ligadas em modo sombra, que decide e regista mas não manda em nada. A primeira escolhe o melhor estafeta ou motorista quando um pedido ou uma corrida tem dois ou mais candidatos livres. Usa a distância à recolha, os trabalhos aceites nos últimos sete dias, a avaliação e a carga atual. Os estafetas saem para fora só como estafeta_1, estafeta_2 e assim por diante. A segunda dá uma nota de risco de falta a cada marcação de serviço nova. A terceira pergunta se vale a pena abrir cada sugestão nova do Robot B, olhando para o que o Danilo fez antes com sugestões da mesma categoria. A quarta pergunta, a cada mensagem nova no suporte, se a conversa deve passar a humano. A tarefa agendada corre a cada 30 segundos e responde bem. A prova é a resposta real da base: ok, nada pendente, em 172 milésimos.

Nenhuma destas regras mexe em preços, taxas, comissões, tokens, pagamentos ou no motor de despacho. A única ação real do decisor é no Robot B, e só se for ligado o modo ativo. Nesse caso arquiva como rejeitada uma sugestão nova com menos de 25 por cento de probabilidade de valer a pena. Esse limiar também está nas definições.

No painel admin há um ecrã novo, Decisões (Jev), no grupo dos robôs, ao lado de Motores e Agentes. Mostra quanto custou hoje, com tokens e custo por motor. Diz se o Jev já tem chave. Tem um interruptor por regra: desligado, sombra e, só no Robot B, ativo. Cada mudança fica no registo de auditoria. Tem ainda a lista das últimas 200 decisões, com filtros por tipo, motor e regra, a confiança, as probabilidades, e se acertou ou errou quando já se sabe.

## Custo e limites reais do Jev

Li a documentação oficial pela própria base de dados, porque daqui o site está bloqueado. O modelo atual é o jev-1.13.0, e o nome jev-latest aponta para ele. Custa 42 dólares por mil milhões de tokens de entrada, ou seja, 4 cêntimos de dólar por milhão. Os tokens de saída não se pagam. Os limites são 250 mil tokens por segundo e 1200 pedidos por minuto, e a TypeSafe avisa que podem mudar sem aviso. Cada pedido aceita até 64 mil tokens. A própria TypeSafe avisa que o Jev funciona melhor em inglês, por isso as perguntas do decisor vão em inglês e os dados vão como estão. Com o volume de hoje, o custo diário do Jev fica abaixo de um cêntimo.

## Provas

A migração está no repositório como supabase/migrations/20260923150000_decisor_jev.sql e foi aplicada na produção. A leitura de volta confirmou: segurança de linha ligada na tabela decisoes; os anónimos não leem a tabela; ninguém de fora do servidor chama a função da chave; os quatro interruptores estão em sombra; a tarefa agendada número 86 está ativa.

Nos testes, o ecrã novo tem dez casos e todos passam. A análise do projeto inteiro dá zero erros, e os 247 avisos antigos são de outros ficheiros. A suite completa passou 768 testes em 768. O chão anti-batota do Juiz deu limpo, e o verificador de zonas protegidas não encontrou nenhuma no diff.

As vinte chamadas reais usaram dez sugestões do Robot B, cinco aplicadas e cinco rejeitadas. Usaram também quatro marcações com desfecho conhecido e seis conversas de suporte, quatro que foram a humano e duas que não. O Jev não respondeu a nenhuma, por falta de chave. O Gemini respondeu a uma, com o modelo 3.5-flash-lite, em 19,6 segundos. Disse que não valia a pena abrir uma sugestão que o Danilo tinha aplicado, e por isso errou. As outras dezanove falharam no Google. O 3.5-flash-lite não respondeu dentro de 20 segundos. O 3.1-flash-lite deu primeiro "muita procura" e depois "quota excedida". O 3-flash-preview deu "quota excedida". O resultado real ficou gravado em todas as vinte. O ficheiro .claude/.ai/provas/jev-decisor-2026-09-23/repetir_b5.sql repete tudo quando houver chave, e o provas_b5.md tem a consulta para ler Jev e Gemini lado a lado.

## Encontrado fora do âmbito

O Robot B usa a mesma chave Gemini e levou erro 503, de muita procura, em seis das oito execuções de hoje, entre as 8 e as 14 horas UTC. Isto quer dizer que o Robot B quase não está a diagnosticar nada hoje. Além disso, o modelo gemini-2.5-flash-lite já responde 404 a esta chave. Não corrigi nada disto.

## Para o Danilo

Nada técnico. Deixei uma ordem de continuação em .claude/.ai/inbox/CONTINUAR-jev-decisor-2026-09-23.md para uma sessão com o Chrome do PC. Essa sessão entra em console.typesafe.ai com o Google do boraappbora@gmail.com, que já está iniciado, e cria a chave. Grava-a no Vault e repete as vinte provas lado a lado. Só te toca se a TypeSafe pedir cartão ou palavra-passe; nesse caso a página fica aberta à tua espera.

Uma decisão é tua, quando houver números: ligar o modo ativo do Robot B, para as sugestões fracas nem chegarem à tua caixa.
