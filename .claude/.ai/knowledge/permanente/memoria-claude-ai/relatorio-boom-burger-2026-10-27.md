---
id: memoria-claude-ai-relatorio-boom-burger-2026-10-27
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-27
zona: verde
confianca: alta
estado: atual
---

# Boom! Burger — demonstração e consertos (27/10/2026, noite)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `relatorio-boom-burger-2026-10-27`, origem `claude-code`, atualizada em 2026-10-27T21:56:35.664479+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: relatorio boom burger 2026 10 27 · memoria claude.ai · claude_ai_memoria

# Boom! Burger — demonstração e consertos (27/10/2026, noite)

Missão boom-burger-2026-10-27, adendos 2 a 6. Escrito pelo Claude Code. Registo passo a passo no e2e_log, fluxo boom-burger-2026-10-27.

## Fiz isto

A demonstração de amanhã às 11:00 está pronta e provada. Fiz seis pedidos de ensaio, pela máquina e pela própria app na web: o cliente de demonstração pede, o painel da Boom recebe e aceita com 10 minutos, só o estafeta de demonstração recebe a oferta, ele recolhe, confirma a idade quando há cerveja, mete o código e o pedido fecha como "demonstração concluída, sem custo". Nenhum estafeta a sério foi chamado. Nada entrou em ganhos, extratos, faturas, fecho semanal, tokens, check-in nem avisos ao admin. Um cliente normal continua a ver "Em breve" e não consegue pedir. A janela ficou gravada para amanhã das 10:30 às 12:00, hora de Lisboa, e desliga-se sozinha: quando a gravei, o pedido de ensaio que ainda estava aberto fechou sozinho sem custo. O telemóvel 1 usa a página boomburger.boraguarda.com/demo/ (na app normal o cliente não consegue pedir numa loja "Em breve"); mostra o menu com os preços da app, o pedido a andar e o código de entrega. As contas de demonstração foram enviadas ao Danilo pelo Telegram, com a explicação dos três telemóveis.

Os preços do dono estão nos 56 produtos (Clássico 10,90 € na loja dá 12,72 € na app). O Duplo Smash ficou com esse nome, o Terra e Mar ficou de fora e o King Elvis está preparado com a foto do dono, fora da loja até chegar o preço.

Consertos da app, todos guardados no ramo consertos-boom-2026-10-27 (8 commits, 38 ficheiros), sem publicar:
- O "112 Total" no painel do parceiro e o menu que podia aparecer a dobrar: duas cargas corriam ao mesmo tempo. Agora não. O teste novo dava 112 antes do conserto e 56 depois.
- Pausa do dia: o parceiro e o admin já põem e tiram a pausa de cada dia, e a loja diz "Fechada, abre às 19h00" ou "abre amanhã às …".
- Feriados: a app passa a respeitar os dias especiais como o servidor (no Natal diz "Fechada hoje").
- Dados fiscais do parceiro: botão "Dados fiscais" no painel do parceiro, que diz o que falta para a loja poder abrir; cartão "Dados fiscais (DAC7)" na ficha do parceiro no admin; e quando o admin tenta tirar o "Em breve" sem os dados, aparece o que falta em vez de um erro técnico. Provado numa loja de demonstração, nunca na Boom.
- Termos do parceiro, versão de 28/10, com o texto do contrato e sem nome nem morada. O parceiro tem de os aceitar ao entrar no painel; o admin tem uma lista com quem aceitou e um botão para registar uma aceitação recebida por WhatsApp ou email.
- Fotos: as seis cervejas Letra e a Água das Pedras já têm a foto oficial do fabricante.
- As migrações de hoje estão todas no repositório, iguais às do servidor.

## Falta isto

- O sinal das reservas por loja está só preparado, num ramo à parte (consertos-boom-f5-sinal), porque mexe em pagamentos: a função da Stripe, o cancelamento e as faltas. Só se aplica com "autorizo F5".
- Apagar a função de teste produto_e_maior_18_v2_teste: o pedido foi recusado. Fica para o Claude.ai.
- Publicar: espera o "publica". A prova na web dos consertos (painel com 56 e a pausa) faz-se na web publicada, depois de publicar.
- Quatro sobremesas sem foto (bolo de chocolate com pistáchio, brownie, cheesecake de caramelo salgado, palitos de Nutella). Não estão no WhatsApp, na Glovo nem no Facebook público.

## Erros que encontrei pelo caminho

- Consertados logo: no fim da demonstração o cliente recebia "Pedido cancelado" (agora não); guardar o horário no painel admin apagava os feriados da loja (nenhuma loja os tinha, não se perdeu nada); a app ignorava os feriados.
- Erro meu: num ensaio, um clique ligou as reservas da Boom. Repus em desligado um minuto depois. Ficou a configuração de reservas que a app cria por omissão (mesas, turnos), que os clientes não veem.
- Reportados, não mexidos: o formulário dos dados fiscais pede sempre a data de nascimento, mesmo a empresas; quando o parceiro grava, a data da autocertificação é carimbada de novo; o servidor aceita o nome comercial como nome legal; os termos também vão aparecer aos parceiros de serviços (barbearias) e às lojas pendentes.
- O primeiro commit do ficheiro dos termos ainda tem o nome da empresa no histórico do ramo (nunca enviado). Ao publicar, copiam-se só os ficheiros, nunca o histórico do ramo.

## Próximo passo

Amanhã: a demonstração às 11:00. Pedir ao dono as fotos das quatro sobremesas, o preço do King Elvis e os dados fiscais (NIF, IBAN, data de nascimento se for em nome individual, autocertificação). Quando o Claude.ai escrever "publica": copiar para o ramo de produção só os 38 ficheiros do ramo consertos-boom-2026-10-27 (lista: diferença entre origin/autonomous-night-2026-04-29 e consertos-boom-2026-10-27), juntar num commit só, enviar, provar Android, iPhone e web, e repetir a demonstração na web publicada antes das 10:30.

## PARA O DANILO

- Autorizar ou não o sinal das reservas por loja (F5). Mexe em pagamento.
- Se é urgente publicar os consertos antes da demonstração. A demonstração funciona sem publicar.

