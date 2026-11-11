# Amigo Bora passa a saber da Casa e Manutenção — 11/11/2026

Missão `amigo-casa-2026-11-11`, ordem do Danilo às 12:39: "Conserta o amigo". e2e_log fluxo `amigo-casa-2026-11-11`.

Fiz isto. Li o Amigo que está no ar (client-assistant versão 24, igual ao ramo de produção, os 8 ficheiros conferidos). A causa
era dupla: o Amigo não tinha nenhuma ferramenta da Casa, por isso não sabia preços; e quando a pessoa dizia "preciso de…" o
código mandava-o acabar com um Favor (era daí o botão "Pedir um Favor"). Criei o ficheiro `casa.ts` e uma ferramenta nova,
`casa_servicos`, que lê a mesma lista que a app usa (`casa_config`, tabela `casa_servicos` e as definições): o preço sai da
tabela (roupeiro 80,00 € por móvel, televisão 45,00 €, torneira 40,00 €, autoclismo 20,00 € por hora, orçamento com fotos),
mais a regra do material (o profissional leva as ferramentas, o material é do cliente), a garantia de 7 dias e o cancelamento
grátis até 12 horas, sempre lidos das definições. Num trabalho de casa o código já não empurra para Favor, tira os botões de
Favor (a não ser que a pessoa fale de Favor), apaga frases de reserva de mesa ("para quantas pessoas") e põe por baixo da
resposta a ligação "Abrir a Casa e Manutenção para marcar". Essa ligação vai pelo caminho das deixas (`abrir_faixa`, categoria
`casa`), que as apps já publicadas abrem sem versão nova: não é preciso publicar a app, só a função no servidor.

Provas que já fiz: deno test do Amigo 55 de 55 verdes (8 novos da Casa), deno check do index sem erros, anti-trapaça limpo, e a
lista real de produção passada pelo casa.ts dá exatamente os preços pedidos ("quero açaí" não é tratado como Casa).

Falta isto, e porquê. A publicação da função foi recusada duas vezes pela trava (a CLI pede o ficheiro do token, que a trava
não deixa ler; o MCP diz "publica a Claude.ai"). Por isso a função no ar continua a 24 e as provas de conversa no ar
(roupeiro, televisão, pintar a sala, torneira e o açaí → Goola) ficam para depois da publicação. Está tudo no ramo
`ai/2026-11-11-amigo-casa` e na página `entrega-amigo-casa-2026-11-11` do livro, com os passos.

Erro encontrado pelo caminho. A Pintura está DESLIGADA em produção (ofício fase 2, precisa de certificado IMPIC), tal como
Eletricidade, Gás, Pladur, Jardinagem e Mudanças. Por isso "quero pintar a sala" não pode dar "orçamento com fotos" de pintura:
o Amigo passa a dizer que essa área ainda não está disponível, sem a meter noutro serviço. Se os anúncios de hoje falam de
pintura, há aqui um desencontro que é decisão do Danilo.

Próximo passo: a Claude.ai publica o client-assistant (9 ficheiros do ramo, verify_jwt ligado) e corre as 5 conversas com a
conta de teste, na web e no Android.
