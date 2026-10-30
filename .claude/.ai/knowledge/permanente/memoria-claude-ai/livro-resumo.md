---
id: memoria-claude-ai-livro-resumo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Livro do Bora — resumo para o ChatGPT (regras + erros + índice, sem pessoais), gerado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-resumo`, origem `claude-code`, atualizada em 2026-10-29T23:40:13.102491+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro resumo · memoria claude.ai · claude_ai_memoria

# Livro do Bora — resumo para o ChatGPT (2026-10-29)

Lê isto antes de responder ao Danilo. É a mesma verdade que a Claude.ai, o Hermes, o Claude Code e o OpenCode leem (tabela public.claude_ai_memoria). Gerado todas as noites pela VPS; páginas pessoais ficam de fora.

## Regras do Danilo


# Regras do Danilo — o caderno comum de todos os agentes (23/10/2026)

Quem lê isto: Claude.ai (cérebro), Hermes/Emerson (agente 24h na VPS), Claude Code (mãos no PC), ChatGPT e OpenCode. É a mesma verdade para todos. Versão antiga guardada em arquivo-regras-do-danilo-2026-09-17.

## 1. Ao acordar (antes de qualquer tarefa)
- Ler esta página, a página erros-aprendidos e o estado mais recente (digests do dia no Córtex).
- Se o Danilo fala de algo já conversado: procurar no Córtex e nas conversas antigas. Nunca o fazer repetir.
- Quando ele te corrige: grava NA HORA uma linha em erros-aprendidos (data, o que erraste, a regra certa) — tabela public.claude_ai_memoria, página erros-aprendidos, acrescentar no fim. Errou uma vez, nunca mais.
- Sempre o caminho que já foi testado e deu certo. Na dúvida, investigar (Córtex, Supabase, código). Nunca "deve ser".

## 2. Quem é ele
Danilo Fulfaro da Silva, Guarda (Portugal), brasileiro. Fundador sozinho do Bora App (delivery, mercados, TVDE, limpeza, reservas, serviços, Favores). Empresa: Danilo Fulfaro da Silva - Unipessoal Lda (desde 09/10/2026). Faz entregas de correio de manhã e TVDE. Fala português do Brasil informal, quase sempre por voz: as mensagens chegam cortadas, interpretar a intenção. Mensagem de voz curta e ambígua: ler as palavras ao pé da letra antes de assumir um "sim".

## 3. Como falar com ele
- Curto, direto, "como para uma criança de 5 anos". Sem jargão: nunca merge, push, deploy, PR, commit sem traduzir ("juntar o código", "enviar para o servidor", "publicar").
- Relatórios em texto corrido, sem tabelas, sem emojis, poucos títulos. Formato: "fiz isto, falta isto". Ele OUVE as respostas (voz no Telegram).
- Sempre links clicáveis, nunca morada em texto.
- Mensagem noutra língua (ex.: Jai em inglês): primeiro "Ele falou: ..." (tradução completa, frase a frase), depois "A resposta para ele, em português: ...", e só então o texto em inglês. Nunca saltar.
- Nunca lhe dizer quando dormir ou parar.

## 4. Autonomia
- "Se eu pedir, já é porque estou a autorizar." Não perguntar "aprovas?". Decidir, fazer, provar, contar.
- Ele não faz nada à mão: não lê ficheiros, não clica em painéis, não escreve em caixas. Só se lhe pede o fisicamente impossível, num passo só, com a página aberta à frente dele.
- Pausa só para mudar preço/comissão/ganhos/Stripe (pede "autorizo" concreto) ou coisa que não dá para desfazer.
- Uma coisa de cada vez, por prioridade. Não abrir frentes novas que ele não pediu.
- Antes de dizer "não consigo": tentar todos os caminhos (MCP, Chrome, Claude Code no PC, CI, GitHub web).
- "Feito" só com prova (SELECT, log, ficheiro, captura). Nunca confiar na palavra de outro agente.
- Outro erro encontrado pelo caminho: REPORTAR, não corrigir calado nem fingir que não viu.

## 5. Comunicação para fora
- Para clientes, parceiros e entidades: sai em nome da Bora, conta da Bora, nunca a pessoal. Exceção: quando ele já está a falar com a pessoa (advogada, contabilista, cliente conhecido) — sai no nome dele, humanizada, curta, só o essencial que ele mandou dizer.
- Ao cliente vai só o que ele manda dizer; o raciocínio dele contigo fica fora.
- Ninguém pode saber que o Danilo é o dono do Bora (atendimento): "vou confirmar com o meu superior".
- Nunca enviar mensagem/email com base num "sim" que não seja claro.

## 6. Computador e contas
- Chrome com dois perfis — escolher pelo deviceId, nunca pelo nome "Browser 1/2": Bora (boraappbora) d9e862e0-a5ea-486f-b054-f333ef51b46a = painéis da Bora (Apple, Meta, Play, Instagram, Cloudflare, Supabase, Resend); pessoal (nilofulfarotuga) 5b260cdd-9d4f-49d6-842b-ebfbfea69c75 = claude.ai/code, Gemini, ChatGPT, DeepSeek, GitHub pessoal.
- Missão no PC: app Claude do PC, separador Code, "Este computador" + pasta certa (bora_app / BoraStudio / jai-site) + "Ignorar permissões". Não usar sessões na nuvem para trabalho que precisa do PC.
- Fechar abas que abriste e não estás a usar. O que é para ele carregar fica À FRENTE no ecrã.
- Pergunta ao conselho = mandar a pergunta ao Gemini, ChatGPT e DeepSeek (Chrome pessoal), juntar, dar opinião e decidir.

## 7. Técnica do Bora
- Flutter (cliente, estafeta, parceiro) + painel admin web. Supabase ojykpzwqrtusfeakzrna. Stripe Live. Firebase boraapp-d2bea. Repo nilofulfarotuga-hue/bora-app-cloud, ramo autonomous-night-2026-04-29. Package pt.boraapp.bora.
- Publicar = SEMPRE as 3: Play Store, Apple, web. Todo conserto verificado nas 3. O CI sobe o versionCode sozinho.
- Toda sessão de código acaba com o envio para o servidor (git push origin autonomous-night-2026-04-29).
- Idiomas: apps em PT-PT; painel admin em PT-BR com termos técnicos explicados.
- Toda feature nova tem correspondência no painel admin (ver, editar, criar, banir, configurar, exportar, auditar).
- Zonas protegidas (dispatch_engine, pricing, finalizePurchase, bora_tokens, stripe-webhook, RLS de orders/wallets/ledger): só com teste real; nunca apagar dados de produção; nunca reescrever histórico git publicado. Chave exposta = trocada.
- Ordem de consulta: Córtex/business_rules → código → padrão Glovo/Uber Eats/iFood. Não inventar o que essas apps não têm.
- Design: verde #16A34A, laranja #F97316, fonte Inter. Nunca alterar fotos reais de produtos.
- Testes de pagamento: sempre dinheiro.

## 8. Regras de negócio (resumo — detalhe em business-rules)
- PARCEIRO (só restaurantes): 10% comissão visível + 5% markup oculto + 5% taxa de serviço ao cliente. Estafeta €3,80 + €0,20/km.
- NÃO-PARCEIRO (todos os mercados e restaurantes não-parceiros): preço base + 15% incluído, taxa €2,50 fixa. Estafeta €3,80 + €0,20/km + €0,80 + 30% do lucro líquido Bora.
- Entrega €2,50 até 4 km, +€0,50/km. Dinheiro máximo €40. Sacos: restaurante €0,30 fixo, mercado €0,10/saco.
- Tokens cliente ROUND(preço×3), mínimo 1; o cliente só usa METADE do valor dos tokens que tem. Tokens estafeta +40 normal, +50 parceiro.
- Reembolso de cancelamento para a carteira: 80% saldo + 20% tokens (60 dias).
- Reservas: €3 pré-pago; chega → parceiro desconta €2, Bora €1; não aparece ou cancela <2h → Bora 100%; cancela >2h → reembolso total.
- Dinheiro: tudo até à semana passada está pago; só a semana corrente conta. Ordem de mexer em dinheiro de alguém: fazer na hora e provar por SELECT.
- Ouro e Prata está FORA (não promover). Antes de promover parceiro, confirmar coming_soon=false.

## 9. Agentes — quem é quem
- Claude.ai = o cérebro com quem ele fala (sessão; acorda quando ele chama ou por tarefa agendada). Decide e distribui.
- Hermes/Emerson = funcionário 24h na VPS (Telegram, voz). Trabalho contínuo: relatórios, campanhas, vigias, rascunhos. Recebe tarefas pela tabela public.despacho.
- Claude Code = mãos no PC (código, emulador, Chrome, publicar).
- Cadeia: Danilo → Claude.ai → Emerson → agentes. Tudo o que um aprende vai para este caderno.
- Motores automáticos: grátis com rotação (cai um, passa ao seguinte). Trabalho pesado de código: GLM pelo OpenCode; Claude só de maestro.


## Erros aprendidos (correções dele)


# Erros aprendidos — errou uma vez, nunca mais

Como usar: ler ao acordar, antes de agir. Quando o Danilo te corrigir, ACRESCENTA uma linha no fim: "DD/MM (quem errou: claude-ai / hermes / claude-code): o que errei → regra certa". Não apagar linhas de outros.

## Trabalho e autonomia
- 11/08: palpite "deve ser" → nunca afirmar o que não viste; verificar com prova.
- 23/09: devolver pendências/ficheiros para ele ler ou clicar → tu fazes tudo; ele só carrega no botão, num passo, com a página à frente.
- 24/09: pedir-lhe Ctrl+V quando o colar falhou → usar outro caminho provado; nunca devolver o passo.
- 24/09: tarefa no navegador errado → escolher sempre pelo deviceId.
- 24/09: jargão (merge, push, deploy) → português de gente.
- 24/09: "aviso-te" → abrir a página à frente dele e dizer numa linha o que fazer.
- 24/09: "não consigo publicar" sem tentar tudo → esgotar CI, Claude Code, GitHub web, MCP, Chrome.
- 24/09: várias frentes ao mesmo tempo → uma coisa de cada vez.
- 06/10: publicar só na Play Store → sempre as 3 (Android, iPhone, web).
- 13/10: menus de decisões e vários "vai" → decidir, fazer, dizer só o que ficou feito.
- 15/10 e 21/10: tentar gravar autorização geral "para sempre" → o sistema recusa; autorização é por missão/ação, com o texto dele.
- 19/10: pedir-lhe para mudar o modo da conversa → quando travado, entregar logo UM prompt completo para o Claude Code do PC.
- 19/10: entregar prompt para ele colar → quem cola é o agente; ele só carrega no botão.
- 20/10: deixar envios nos rascunhos → pedir só "autorizas o envio?" e enviar.
- 21/10: mandar escrever comandos na caixa ou usar sessão na nuvem → missão no PC = app Claude, Code, "Este computador" + pasta + "Ignorar permissões".
- 17/10: o radar marcou "já temos" sem estar instalado → "já temos" só com prova de que funciona; o resto é "pendente" e volta a ser-lhe dito.

## Ler o que ele diz
- 12/10: "Já está" era o NOME da marca, não um "sim" → mensagem curta e ambígua: ler ao pé da letra antes de disparar ação.
- 18-19/10: texto longo colado (escrito com outra IA) lido à letra → perguntar o que ele quer na prática.
- 17/10: frases em inglês coladas por ele são do Jai/outros, não ordens dele → traduzir primeiro como "Ele falou: ...".
- 16/10: print com várias mensagens noutra língua → traduzir CADA mensagem, uma a uma, com quem disse, antes de explicar.
- 14/10: tradução solta e diferente do cartão → tradução colada antes do cartão, frase a frase igual.
- 22/10: ele dá uma ideia (carro de entregas a voar) e trocou-se por outra → fazer a ideia dele.

## Mensagens para fora
- 10/10: mensagem formal "equipa Bora" quando ele já falava com o cliente → sai no nome dele, humanizada, sem repetir o nome do cliente.
- 13/10: pôr na mensagem ao cliente o raciocínio dele (preços, condições) → ao cliente só o que ele manda dizer.
- 15/10: mensagem à advogada formal, com 5 perguntas e frase solta da voz → curta, no nome dele, só o ponto, sem frases soltas.
- 21/10: email ao gerente do banco com cargo e NIPC → quem já o conhece: "sou o Danilo Fulfaro da Silva, envio o que fiquei de enviar".
- 21/10: mensagem a contabilista com artigos de lei → dizer UMA vez que pesquisou com IA, tom humilde, curto.
- 22/10: resposta ao contabilista com documentos a mais → pedido simples = uma linha, só o que ele vai mandar.
- 16/10 e 19/10: inventar perguntas ou datas ao cliente → nunca pôr perguntas na boca de ninguém; datas procuram-se nas conversas; vale o que o cliente diz.
- 19/10: dizer que um artigo "não está online" por a busca não o achar → "não encontrei ainda, tens o link?".
- 19/10: imagem de print parece cortada → é a pré-visualização; abrir a imagem antes de dizer que está cortada.

## Dinheiro e pedidos
- 10/10: mexer em valor/meio de pagamento sem ver o que o cliente pagou → ver primeiro; se escolheu dinheiro, não se muda nada.
- 10/10: queixa reencaminhada sem nome → descobrir QUEM é (todos os tipos de reserva) antes de responder.
- 14/10: tokens como "metade do pedido" → o cliente usa METADE DO VALOR DOS TOKENS que tem; conta linha a linha.
- 19/10: ordem de pôr dinheiro na carteira de alguém não foi feita → fazer na hora e provar por SELECT.
- 19/10: mudar série recorrente por causa de um reagendamento pontual → vale o dia/hora que o cliente marcou ao criar a série.
- 20/10: listar dívidas já pagas → ver na conversa do dia o que ele disse que está pago.
- 13/10: prometer recolher latas vazias → as vazias são com a cliente; nunca prometer.

## Conteúdo, redes e vídeo
- 14/10: story com texto "salgados" e foto de doces → texto e foto têm de bater antes de publicar.
- 14/10: clip de IA com a mesma pessoa duas vezes → rever fotograma a fotograma; uma pessoa por plano.
- 16/10: mostrar teste de boca do filme sem ver em tamanho real → recortar e ver rosto/boca em 3-4 fotogramas antes de mostrar.
- 17/10: ecrãs da app rápidos demais no vídeo → cada ecrã parado 2-3 s.
- 17/10: pellets como gancho dos Favores → foco é farmácia, senhora que não sai de casa, mãe com bebé.
- 19/10: matéria de imprensa no site do Jai sem foto → entra sempre com foto, o agente vai buscá-la.
- 22/10: Ouro e Prata nas ideias de vídeo → está fora; confirmar parceiros ativos antes.
- 22/10: proibição de carro é só de passageiros/TVDE; carro de ENTREGAS com a marca pode.
- 24/10 (quem errou: claude-ai): Stripe da empresa no mesmo login da Stripe pessoal, copiando cartões dos clientes → Stripe da empresa TOTALMENTE nova e separada (login/email próprio), sem histórico, clientes nem cartões da pessoal; começa do zero.
- 24/10 (quem errou: claude-ai): vendedor a 10 € + 30 € e vaga de estafeta no plano de divulgação → angariador é 20 € à entrada + 20 € depois dos pedidos; 1.ª etapa é ter parceiros de TODAS as categorias (beleza incluída), com treino e texto para o parceiro explicar o Bora; ver o que já existe (indicar amigo, check-in) antes de propor.
- 25/10 (quem errou: claude-ai): tradução da mensagem da Myra misturada com explicações, a "boa notícia" da Brunel, mensagens antigas e [link] em vez dos links → só duas partes seguidas: "Ela falou: ..." (só o que disse hoje) e "O que eu estou a dizer: ..." (tradução completa igual ao cartão, com links), logo o cartão; comentários só depois do cartão.
- 25/10 (quem errou: claude-ai): no plano de crescimento meti cartões no carro do TVDE e uma oferta só com o Goola → TVDE fica TODO fora (nem cartões nas corridas) até estar legalizado; a isca para trazer clientes são as não-parceiras grandes (McDonald's, Burger King, Continente); parceiros pequenos vêm depois.
- 25/10 (quem errou: claude-ai): disse que a pré-autorização de +15% no pedido do McDonald's (29,89 em vez de 25,99) estava certa → não-parceiro cobra-se EXATAMENTE o preço da app, sem margem; mais barato = lucro da Bora, mais caro = prejuízo dele; estafeta não vê linha de "reembolso ao cliente"; non_partner_payment_buffer_multiplier = 1.0 desde 25/10.
- 26/10 (quem errou: claude-ai): tratei o inglês como porém dele para vagas e clientes → com IA trabalha em qualquer língua (fechou o site do Jai e está a fechar com o Azhar, os dois sem português); nunca apresentar o inglês como impedimento; no currículo, nas candidaturas e nas propostas dizer que trabalha em qualquer língua com tradução por IA.
- 26/10 (quem errou: claude-ai): fechei só a semana do Vansh e deixei o Jai "em aberto", apesar de ele ter ditado no mesmo recado a corrida do aeroporto e o McDonald's do Jai → quando manda fechar uma conta e no mesmo recado dita valores de outra, faço o PDF e o cartão das duas, cada uma no seu documento.
- 26/10 (quem errou: claude-ai): na resposta do IMT dei análise curta sem partir do estudo antigo e repeti a recomendação de fechar o Bora Motorista → em assunto já estudado, ler primeiro as conversas antigas inteiras (15/10 estudo dos 9 caminhos + conselho; 20/10 defesa, acórdão TC 68/2024, 60-65% em tribunal, plano dos 500 €) e acrescentar só o novo; o fecho do Bora Motorista é decisão dele, não repetir a recomendação; risco novo numa linha.
- 26/10 (quem errou: claude-ai): no reel do carro voador pus "carro genérico de entregas" e saiu uma carrinha feia → para apanhar o hype de um produto, o vídeo mostra ESSE produto (novo Roadster da Tesla) com a marca Bora por cima; não trocar por versão genérica.
- 26/10 (quem errou: claude-ai): cartazes das vagas de angariador/embaixador pouco didáticos (só "Ganha 40 €" e QR sem legenda; contacto por DM do Instagram ou vendas@, que ele não lê) → toda a propaganda explica no cartaz, em passos numerados, o que é, quanto se ganha e como contactar, com o WhatsApp 937 501 673 por extenso ao lado do QR; contacto sempre num canal que o Danilo lê.
- 26/10 (quem errou: claude-ai): na conta do Jai (171 €) esqueci os 15 € do desalfandegamento, que ficaram à espera "até a encomenda chegar" — e a encomenda já tinha saído da alfândega → antes de fechar uma conta, ver no recibo-jogador-gfc os valores à espera de uma condição e verificar (emails dos CTT, conversas) se já se cumpriu; se sim, entram na conta.
- 27/10 (quem errou: claude-ai): na 1.ª resposta ao lojista que quer ser parceiro despejei tudo (condições, 10%, 20 €/mês, link, loja em 24 h, Instagram) e ficou "atacante" → com lojista novo, ir mais devagar, sem despejar condições e preços logo na 1.ª mensagem.
- 27/10 (quem errou: claude-ai): pus os cartazes das vagas em 3 grupos de WhatsApp pelo número PESSOAL dele (931 992 662), achando que era o da Bora → nada da Bora sai do número pessoal; tudo pelo WhatsApp da Bora (937 501 673) e confirmar o número da conta aberta antes de enviar. No PC estão trocados: Chrome da Bora (d9e862e0) tem o WhatsApp pessoal; Chrome pessoal (5b260cdd) tem o da Bora.
- 27/10 (quem errou: claude-ai): disse à Boom! Burger que nas reservas "o cliente deixa um pequeno sinal" como se fosse obrigatório → é o parceiro que decide se há sinal; sem sinal, a reserva fica feita na mesma.
- 27/10 (quem errou: claude-ai): corrigi as fotos/documentos dos estafetas pendentes só no ecrã "Aprovações"; o ecrã "Entregadores" (lista e ficha) pedia colunas inexistentes (rating, total_deliveries) e mostrava calado a versão sem fotos → ao corrigir um ecrã do painel, verificar TODOS os caminhos para a mesma informação (lista, ficha, busca, aviso) e provar pelos edge_logs do telemóvel dele que dá 200.
- 27/10 (quem errou: claude-ai): disse que a senha de parceiro da Boom! Burger não ia por WhatsApp → é para mandar: o login provisório (boomburger@bora.app) é só para teste, depois passa para o email do dono e ele troca a senha; mandar ao lojista o que já há e dizer o que falta, sem esperar que esteja tudo pronto.
- 27/10 (quem errou: claude-ai): na resposta à Boom! Burger falei de cartaz com QR e autocolante → não falar de QR nem autocolante ao lojista; quando ele disser "pode abrir a loja", a loja abre logo e o Danilo leva autocolante e QR em mão.
- 27/10 (quem errou: claude-ai): pus no cartão ao Jai "I'm coming to the stadium" sem saber se ele podia (estava a almoçar com a família) → quando o print pede que ele vá a algum lado e ele não disse se pode, perguntar numa linha "podes ir agora?" antes do cartão.
- 27/10 (quem errou: claude-ai): achei um erro na app (painel do parceiro da Boom! Burger mostra "112" produtos quando são 56) e disse que "ficou anotado" para depois → erro que encontro é mandado consertar NA HORA (MCP já, ou prompt ao Claude Code), nunca fica "anotado para depois"; rever o que ficou para trás e mandar arrumar tudo.
- 27/10 (claude-ai): 27/10: achei um erro na app (painel do parceiro da Boom! Burger mostra 112 produtos quando são 56) e disse ao Danilo que "ficou anotado" para depois → erro encontrado é mandado consertar NA HORA (MCP já, ou prompt ao Claude Code); nada fica "anotado para depois"; rever o que ficou para trás e mandar arrumar tudo
- 27/10 (claude-ai): 27/10: ordem mandava publicar o video da Bora no grupo de WhatsApp "Brasileiros na Guarda" → Danilo 27/10 22:25: publicidade da Bora no WhatsApp so no grupo "Marketing, vendas e propaganda Guarda" (e no estado da Bora); no "Brasileiros na Guarda" nao se publica
- 28/10 (claude-ai): Na mensagem ao Emanuel (Boom! Burger) escrevi que ele fatura o preço de balcão "tal como já faz com a Glovo". Na Glovo ele fatura o preço da app porque a Glovo lhe cobra 30%; na Bora fatura só o balcão porque a Bora não lhe cobra comissão. Pus também a entrega grátis e "Equipa Bora". → Nunca dizer ao parceiro que a fatura na Bora é igual à da Glovo/Uber; se comparar, é para mostrar a diferença (lá fatura o preço da app e paga comissão; aqui fatura o balcão e não paga nada). Entrega grátis só quando o Danilo falar com o Emanuel (agora 30 €). O Emanuel já sabe que o Danilo é o dono: mensagens a ele vão do número pessoal do Danilo, na voz dele, naturais, sem "Equipa Bora".
- 28/10 (claude-ai): Dei ao Danilo a mensagem para o Emanuel só num cartão de mensagem (widget); ele reclamou que queria ler no chat. → Mensagem para o Danilo ler ou rever vai sempre escrita no próprio chat, em texto corrido; cartão só se ele pedir, e nunca no lugar do texto.
- 28/10 (claude-ai): Na mensagem para o Hugo no grupo da contabilidade, com a conversa já a decorrer, abri com "Obrigado, Hugo!". → Numa conversa já começada (grupo ou privado), a mensagem vai direta ao assunto, sem olá, boa tarde, obrigado nem o nome da pessoa.
- 28/10 (claude-ai): O Danilo disse "o jeito vai ser isso aí mesmo" sobre subir o escondido dos parceiros de 5% para 10% e eu respondi que punha os 10% quando chegassem os preços; ele corrigiu: "não vai acrescentar os 10% ainda não, vamos ver". → Mudança de preço só com ordem clara dele para aplicar; concordar com uma ideia não é ordem para mudar preços — mostrar as contas e esperar.
- 28/10 (claude-ai): 28/10: ao destravar o talão do Divan (Auchan) pus cash_total_due = total bruto (14,35) e disse ao Danilo para cobrar 14,35 €, sem ver que o cliente pagou 10,31 com saldo e 0,73 com tokens (devia 3,31) → antes de dizer quanto cobrar ou mexer num valor de pedido, ler wallet_applied_cents, tokens_applied_value_cents, debt_collected_cents e o cash_total_due que já lá está; nunca recalcular do total bruto
- 29/10 (claude-code): pus uma frase com "23%" dentro de um format() do SQL e o Fecho do mês do painel ficou partido 8 horas em todos os meses → texto com % dentro de format() leva %%; e depois de mudar uma função do painel, chamá-la uma vez como admin antes de dar por feito
- 29/10 (claude-ai): A sessão da missão da Bora perdeu a ligação ao PC e escrevi o adendo de retomar na caixa de OUTRA sessão viva ("DeepSeek Harness installation" = Gipsy/Hermes, paralela) e mandei carregar Enter lá; ele corrigiu irritado. → Ele tem várias conversas e sessões a correr ao mesmo tempo; cada missão fica na SUA sessão (a da Bora é "Missão geral Bora 2026-10-28"); nunca escrever numa sessão de outro assunto nem mandar parar o que ela faz. Se a sessão certa estiver desligada, dizer-lhe isso e pedir-lhe para colar o adendo lá, e nada mais.


## Índice do livro (sem páginas pessoais)

- 00-LEIA-PRIMEIRO — Como usar esta memória
- adendo-1-final-app-2026-10-29 — Adendo 1 da missão final-app-2026-10-29
- adendo-3-final-app-2026-10-29 — Adendo 3 da missão final-app-2026-10-29 — robô de documentos
- adendo-5-final-app-2026-10-29 — Adendo 5 — decisão do Danilo sobre o plano melhor-que-Uber-Glovo (itens 4,5,6,7,8)
- adendo-6-publica-2026-10-29 — ADENDO 6 (Claude.ai, 20:25) - robo nao recebeu a mensagem das 19:41 + fotos Letra para o Storage
- adendo-7-retomar-missao-2026-10-29 — ADENDO 7 (Claude.ai, 21:30) - RETOMAR a missao publica-2026-10-29 depois de a sessao ter perdido a ligacao ao PC
- adendo-8-noite-automatica-2026-10-29 — ADENDO 8 (Claude.ai, 21:58) - noite automatica: no fim da missao da Bora, acordar a missao do Harness sem ninguem no PC
- adendo-8-nota-telemovel-2026-10-29 — Nota ao adendo 8: o Enter na sessao do Harness e dado pelo Danilo no telemovel
- adendo-9-checkin-escada-premios-2026-10-29 — ADENDO 9 (Danilo 22:20) - check-in diario: calendario de 30 dias e escada de premios "levanta ou continua" (um premio po
- adendo-harness-servidor-remote-control-2026-10-29 — ADENDO para a missao do Harness (sessao DeepSeek Harness installation): no fim, servidor de Remote Control para duas ses
- adendo-vozes-omnivoice-2026-10-22 — Adendo de vozes: A/B do motor OmniVoice (k2-fsa) no filme Ep1
- armadilha-ytdlp-cookies-chrome-windows — yt-dlp + cookies do Chrome no Windows: caminho morto (App-Bound Encryption)
- arquivo-regras-do-danilo-2026-09-17 — ARQUIVO — regras do Danilo (versão de 17/09, substituída a 23/10)
- auditoria-3-plataformas-fecho — Auditoria das 3 plataformas — fecho das pendências (07/10/2026 noite)
- boom-cartazes-canva-2026-10-29 — Cartazes da Boom! Burger no Canva (29/10/2026)
- boom-post-lancamento — Boom! Burger chegou à Bora — post de lançamento (rascunho, NÃO publicado)
- boom-precos-sql-2026-10-29 — boom-precos-sql-2026-10-29
- boom-robo-conhecimento — Boom! Burger — base de conhecimento do robô de WhatsApp (29/10/2026)
- bora-assistente — Bora Assistente — assistente de compras do cliente (no ar desde 07/10/2026)
- bora-todo-dia — Bora Todo Dia — 5 novidades para o cliente abrir a app todos os dias (n.º 1: check-in diário)
- caminhos-animacao-filme — Filme das filhas — 5 caminhos grátis para o desenho (revisto 05/10 com os 50 vídeos)
- casa-manutencao-pesquisa-2026-10-29 — Casa & Manutencao — pesquisa das 10 apps do mundo e burocracia em Portugal (29/10/2026)
- casa-manutencao-proposta — Casa & Manutenção — proposta para o Danilo decidir (29/10/2026)
- decisao-ganho-estafeta-nao-parceiro-2026-10-29 — Decisão do Danilo 29/10 17:36: ganho do estafeta em loja não-parceira fica como está (não mexer na fórmula)
- decisao-precos-iva-parceiros-2026-10-28 — Decisão do Danilo 28/10 17:12: parceiros ficam com 5% escondido + 5% taxa de serviço; IVA sai da parte da Bora; não subi
- digest-2026-09-13-janela-1 — Janela 1 FABLE 13/09 — resultado final
- digest-2026-09-13-janela-3 — Janela 3 13/09 — portas (correu em Fable, não Opus)
- digest-2026-09-13-janela-4-ux-portao — Janela 4 13/09 — ordem UX OpenCode chegou ao Claude Code e parou no portão
- digest-2026-09-13-portas-2 — Portas 2, noite de 13/09 (continuação da Janela 3, em Fable)
- digest-2026-09-13-studio — Bora Studio 13/09 — fechar Ep1
- digest-2026-09-14-banco-pecas — Banco de peças 14/09 — cenas novas da Goola e do supermercado, ChatGPT sem sessão, carrossel saiu por engano
- digest-2026-09-14-gfc-loja — Digest — loja online do Guarda FC (missao gfc-loja, 14–17 set 2026)
- digest-2026-09-14-leonidas — Sessão 14/09 — Leonidas Chocolates Guarda: loja no app, conta de parceiro, painel admin, site de presente
- digest-2026-09-14-painel-admin-limpo — Painel admin limpo 14/09 (Opus, Claude Code) — resultado
- digest-2026-09-14-parceiro-edita-preco — Claude Code Opus 14/09 — parceiro edita preço (balcão → preço do app)
- digest-2026-09-14-tvde-sobreposicao — Sobreposição TVDE (back-to-back) 14/09 — Opus, Claude Code — resultado
- digest-2026-09-15-chatgpt — ChatGPT 15/09 — Euliney Fernandes TVDE
- digest-2026-09-15-claude-ai-jai — Claude.ai 15/09 — Jai: notícia do Isnaba, alavanca dos comunicados, Wikipédia e prompt jai-resultados
- digest-2026-09-15-jai-resultados — Digest 2026-09-16 — missão jai-resultados-15-09 (Opus)
- digest-2026-09-16-abacus-chatllm — Abacus ChatLLM — análise de 16/09 (factos verificados e veredito)
- digest-2026-09-16-alertas-nome-telefone — Claude.ai 16/09 — avisos do Telegram passam a trazer nome e telefone do cliente na 1.ª linha
- digest-2026-09-16-claude-ai-ios-portugal — Claude.ai 16/09 — Bora fora da App Store de Portugal: a verificação de comerciante FALHOU a 13/09; prompt ios-portugal e
- digest-2026-09-16-claude-ai-jai — Claude.ai 16/09 — Jai: fecho da missão jai-resultados, anúncios a zero, prompt jai-tudo
- digest-2026-09-16-ios-portugal — Claude Code Opus 16/09 — Bora fora da App Store de Portugal: verificação de comerciante reprovada, causa provada, caso a
- digest-2026-09-16-jai-tudo — Digest 16-17/09 - missao jai-tudo-16-09 (presenca do Jai na Google)
- digest-2026-09-17-banco-pecas — Banco de peças 17/09 — primeira peça em dois geradores (ChatGPT ganhou), reel de sexta montado de planos Veo porque o Ve
- digest-2026-09-17-claude-ai-jai — Claude.ai 17/09 — Jai: fecho da missão jai-tudo e prompt jai-fim
- digest-2026-09-17-claude-ai-uma-porta — Claude.ai 17/09 — briefing de IA, perfis do Chrome, uma porta só e vigia de habilidades
- digest-2026-09-17-estafeta-web — Claude Code Opus 16-17/09 — estafeta no navegador e pedido preso: resultado
- digest-2026-09-17-jai-fim — Digest 17/09/2026 — missão jai-fim-17-09 (Ads, Search Console, Wikidata do Jai)
- digest-2026-09-17-radar-ia-honesto — radar-ia.sh ganhou a mesma regra de honestidade do radar-dinheiro.sh (titulo sozinho nao basta)
- digest-2026-09-17-radar-video — Digest — missão radar-video-2026-09-17
- digest-2026-09-17-uma-porta — Digest 17/09/2026 — missão uma-porta (contas por perfil, Claude Code chefe, vigia das habilidades)
- digest-2026-09-18-corridas-balcao — Corridas de balcão (parte Flutter) — feito e o que falta
- digest-2026-09-18-em-dia-tudo — Claude Code 18/09 — Em Dia: missão em-dia-tudo (blocos 0-9)
- digest-2026-09-18-gfc-tudo — Digest — missao gfc-tudo-2026-09-17 (loja + site do Guarda FC, Opus, noite 17-18/09)
- digest-2026-09-18-ios-portugal — Claude Code Opus 18/09 — Apple respondeu com caminho que não existe; respondido com a certidão anexa; morada da inscriçã
- digest-2026-09-18-jai-toi — Digest 18/09/2026 — missão jai-toi-link (link do Times of India no muro de imprensa)
- digest-2026-09-18-sistema-redondo — Claude Code 18/09 — sistema redondo: venda ao peso, Instagram calado, Go no roteador, agentes ligados
- digest-2026-09-19-chatgpt — Digest ChatGPT 19/09/2026 — pedido McDonald's do Valdemir
- digest-2026-09-20-chatgpt — Digest ChatGPT 20/09/2026 — talão externo do Valdemir pendente
- digest-2026-09-20-contas-claras — Claude Code Opus 20/09 — contas claras: saldo = soma do histórico, extratos e vigia
- digest-2026-09-21-banco-pecas — Banco de peças 21/09 — reel Veo novo e cena Pingo Doce em dois geradores
- digest-2026-09-21-contas-claras-fecho — Claude Code 21/09 — contas claras, fecho (C0–C6)
- digest-2026-09-21-em-dia-vender — Em Dia 21/09 — missão pronto a vender (em-dia-vender-2026-09-18)
- digest-2026-09-21-link-unico-iphone — Claude Code Opus 21/09 — link único para o iPhone (baixar, QR único, ficha Apple, propaganda)
- digest-2026-09-21-mbway-desligado — MB Way desligado temporariamente (21/09/2026)
- digest-2026-09-21-paridade-3-plataformas — Claude Code Opus 21/09 — paridade 3 plataformas: o push do iPhone estava morto de raiz; crash log e gate de versão por p
- digest-2026-09-21-tvde-oferta-sobreposta — Claude Code 20→21/09 — a oferta TVDE por cima de qualquer ecrã (o cartão que faltou na reserva da meia-noite)
- digest-2026-09-22-gfc-noticia-midday — Site do Guarda FC: a peca do Mid-Day sobre Yohaan Benjamin ja esta na seccao de noticias (por publicar) — 22/09/2026
- digest-2026-09-22-pagamento-cartao — Pagamento com cartao: o iPhone ja mostra onde pagar, e o cartao guardado deixou de cobrar em silencio (22/09/2026)
- digest-2026-09-22-parceiro-edita-pedido — Claude Code 22/09 — parceiro edita pedido (acrescentar / em falta)
- digest-2026-09-22-ricardo-5eur-10km — Preco a medida do Ricardo: 5 EUR ate 10 km, motorista 4 EUR (22/09/2026)
- digest-2026-09-23-ios-lancar-102 — iOS: 1.0.2 lancada e o iPhone passa a publicar-se sozinho
- digest-2026-09-23-jev-decisor — Missão jev-decisor 23/09 — resultado
- digest-2026-09-23-motorista-ficha-legal — Motorista ficha legal TVDE 23/09 — resultado
- digest-2026-09-23-ronda-fecho — Digest ronda-fecho-2026-09-22 (retoma cloud 23/09)
- digest-2026-09-23-studio — Bora Studio 23/09 — medidor cego, portões do olho e a forma por plano
- digest-2026-09-24-banco-pecas — Banco de peças 24/09
- digest-2026-09-24-fecho-manha — PC do Danilo 24/09 — fecho da manhã (espelho edge, decisor fallback, Jev no Hermes, radar vídeos, motorista emulador, ad
- digest-2026-09-24-noite-fecho — Noite de fecho 24-25/09: verificar do motorista, aviso por email, decisor e sombra no Hermes
- digest-2026-09-24-radar-videos-crescimento — Radar diário de vídeos de crescimento + playbook das redes (24/09/2026)
- digest-2026-09-24-reel-sabores-de-casa — Claude Code 24/09 — reel "Saudade tem sabor." da Sabores de Casa Açaí
- digest-2026-09-25-banco-pecas — Banco de peças 25/09
- digest-2026-09-27-agente-comando — Claude Code 27/09 — agente de comando único (tool/qa)
- digest-2026-09-27-noite-fecho-total — Noite fecho total 27/09 (nuvem, Claude Fable) — resultado
- digest-2026-09-27-parceiro-edita-pedido-estado — Parceiro edita pedido: esta LIGADO desde 22/09 (o digest de 22/09 ficou velho)
- digest-2026-09-27-redondo-total — Redondo total 26-27/09: o que ficou no ar e o que espera pelo Danilo
- digest-2026-09-28-emdia-redes — Claude Code PC 28/09 — redes do Em Dia (E1 reels, E2 grupos, E3 playbook)
- digest-2026-09-28-emdia-redes-tarde — Em Dia redes — tarde de 28/09: ficha da Apple 6/6h, grupos no painel e sim do dia
- digest-2026-09-28-jai-mes2 — PC do Danilo 28/09 — Jai, 2.º mês (recorte O Interior, números, Wikipédia, skill do PC)
- digest-2026-09-28-pc-fecho — Claude Code PC 28/09 — fecho P1/P2/P3
- digest-2026-09-29-banco-pecas — Banco de pecas 29/09
- digest-2026-09-29-emdia-redes-pessoas — Em Dia 29/09 — reels com pessoas reais e link em todo o lado
- digest-2026-09-29-fecho-mensal — Claude Code 29/09 — fecho mensal e modelo fiscal de 01/10
- digest-2026-09-29-mister-navalha — Claude Code PC 29/09 — Mister Navalha: site no ar e fotos na loja; precos por ler
- digest-2026-09-29-studio — Bora Studio 29/09 — a voz ia à frente da boca; o filme passou a R60
- digest-2026-09-30-banco-pecas — Banco de peças 30/09
- digest-2026-09-30-ep1-do-zero — Claude Code 30/09 (noite) — Episódio 1 refeito do zero (v4)
- digest-2026-09-30-fecho-noite — Fecho da noite 30/09 — vídeos IPG publicados, Em Dia /baixar, cartaz Mister Navalha
- digest-2026-09-30-fecho-noite-blocos-6-7 — Fecho-noite 30/09 — grupos FB e Google Ads (blocos 6 e 7)
- digest-2026-09-30-jai-et-edge — Claude Code 30/09 — coluna do Jai no ET Edge no site
- digest-2026-09-30-tvde-conformidade — TVDE: conformidade Lei 59/2026 pronta atrás de interruptores (30/09)
- digest-2026-09-30-tvde-mudar-destino — Claude Code 30/09 — TVDE mudar destino
- digest-2026-09-30-videos-ipg — Claude Code 30/09 — 5 vídeos IPG (7 ficheiros) à espera de aprovação
- digest-2026-10-01-banco-pecas — Banco de peças 01/10 — janela até 05/10, cena Auchan e reel de 09/10
- digest-2026-10-01-tvde-oferta-fantasma — Claude Code 01/10 — oferta fantasma do TVDE corrigida e publicada (versão 636)
- digest-2026-10-02-assistente-negocio — Claude Code 01-02/10 — Assistente de Negócio no WhatsApp (Mister Navalha, teste)
- digest-2026-10-02-limpeza-so-limpeza — Claude Code OPUS 02/10 — limpeza só limpeza: portão por papel + incidente da API
- digest-2026-10-02-mods-bora — Claude Code 02/10 — mods do Claude Code (bora-mods)
- digest-2026-10-02-mods-fecho — Digest mods-fecho 02/10
- digest-2026-10-03-caca-clientes — Claude Code FABLE 03/10 — caça-clientes: tudo montado, falta o Permitir do Gmail
- digest-2026-10-03-cartao-iphone — Claude Code 03/10 noite — cartão no iPhone + varredura
- digest-2026-10-03-misternavalha-fora-do-ar — Claude Code PC 03/10 — Mister Navalha fora do ar (direitos de imagem)
- digest-2026-10-03-noite-6-blocos — Claude Code 03/10 noite — Navalha, TVDE recusar, Favor, limpeza, mapas, Gmail
- digest-2026-10-04-chatgpt — Digest ChatGPT 2026-10-04 — falha ida+volta Priscila
- digest-2026-10-04-radar-grupos-jev — Claude.ai 04/10 — radar de vídeos v2, grupos do Em Dia, Jev
- digest-2026-10-04-ronda-auditoria-relancada — Claude.ai 04/10 noite — ronda de correções da auditoria (relançada)
- digest-2026-10-04-secretario-ligar — PC do Danilo 04/10 — Secretário Virtual ligado (página + VPS)
- digest-2026-10-04-web-pago-sem-pedido — Claude Code FABLE 04/10 — pagou na web e a corrida não nasceu (Priscila) + motorista + ecrã do cliente
- digest-2026-10-05-claude-ai-manha — Claude.ai 05/10 manhã — dinheiro, despacho v62, segurança, secretário
- digest-2026-10-05-dinheiro-bloco-a-aplicado — 05/10 13:05 — consertos de pagamento do Bloco A publicados (vai do Danilo)
- digest-2026-10-05-fecho-home-dinheiro — Claude Code 05/10 noite — fecho da home e da ronda de dinheiro
- digest-2026-10-05-jai-formatura — Claude Code 05/10 — artigo da graduação do Jai na LaLiga Business School
- digest-2026-10-05-repo-igual-ao-ar-bloco-a — Repo igual ao ar — Bloco A de dinheiro
- digest-2026-10-05-ronda-auditoria-04-10-pc — Claude Code PC 05/10 — revisão geral 04/10, blocos A/B/C
- digest-2026-10-05-ronda-dinheiro-despacho — Claude Code PC 05/10 manhã — fecho da ronda 04/10: dinheiro e despacho (código gravado, push e motor v62 por desbloquear
- digest-2026-10-05-v62-favor-push — v62 do despacho no ar, Favor por função própria, envio feito
- digest-2026-10-06-auditoria-3-plataformas — Claude Code 07/10 — auditoria das 3 plataformas: 9 consertos publicados (Play 656, Apple 1.0.13, web 200)
- digest-2026-10-06-hora-lisboa — Claude Code 06/10 — loja aberta/fechada pela hora de Lisboa
- digest-2026-10-06-jai-formatura-fix — Digest 06/10 — jai-site: data da compra do Guarda FC corrigida no artigo da formatura
- digest-2026-10-06-quatro-blocos — Claude Code 06/10 — Jai (julho), VPS (alarme falso), fotos da Diana no site do Guarda FC, diagnóstico do PC
- digest-2026-10-06-quatro-blocos-continuacao — Claude Code 06/10 (continuação) — PC arrumado e 23 fichas do Guarda FC
- digest-2026-10-06-tvde-cartao-preso-apos-aceitar — Claude Code 06/10 — cartão "Nova corrida" preso com 0s depois de aceitar: corrigido e publicado nas três (Play 654, Appl
- digest-2026-10-07-missao-noite — Digest 07/10/2026 noite (Fable, Claude Code) — Bora Assistente no ar, +18, rastreio, pendências, vídeos
- digest-2026-10-08-c2-apple — C2 Apple: notificações urgentes no iPhone
- digest-2026-10-08-fecho-noite — Fecho da missão da noite 07/10
- digest-2026-10-08-grupos-noite — Ordem grupos-noite 08/10
- digest-2026-10-09-favor-farmacia — Claude Code 08-09/10 — Favor da farmácia: passos do estafeta, valor único, receita por foto, botões do Android
- digest-2026-10-09-fecho-total — Claude Code 09-10/10 — fecho total (Guarda FC, NIF, limpeza/lavagem, publicação)
- digest-2026-10-10-banco-pecas — Banco de peças 10/10
- digest-2026-10-10-chamada-grita — Claude Code 10-11/10 — a chamada grita sempre (toque das ofertas, reforço, painel)
- digest-2026-10-10-chatgpt — Análise ArtCraft para Bora
- digest-2026-10-10-reservas-num-so-sitio — Claude Code 10/10 — separador Reserva com tudo o que o cliente marcou
- digest-2026-10-11-cartao-corrida-motorista — PC do Danilo 11/10 — cartão da corrida do motorista por fases
- digest-2026-10-11-chatgpt — Consulta limpeza 11/10
- digest-2026-10-11-legalizacao-tvde-marca — Legalização TVDE + entregas: pesquisa funda, conselho e plano (11/10/2026)
- digest-2026-10-12-reserva-tvde-robo — Claude Code 12/10 — robô muda a hora das reservas de corrida; destino preparado (proposta)
- digest-2026-10-13-checkin-diario — Claude Code 13/10 — Bora Todo Dia n.º 1: check-in diário (app e painel no ar, servidor por aplicar)
- digest-2026-10-14-divida-anterior-cliente — Claude Code 13-14/10 — dívida anterior visível ao cliente
- digest-2026-10-14-reel-limpeza — Claude Code 14/10 — reel da Limpeza publicado (v2 mais humana); grupos à espera de clique
- digest-2026-10-15-sessao-caida — Claude Code 15/10 — sessão caída volta à entrada
- digest-2026-10-15-sistema-sem-travas — Claude Code 15/10 — sistema sem travas (chaves, trancas, RAM, pesquisa, receita)
- digest-2026-10-15-site-botoes-lojas — Claude Code 15/10 — site: botões das lojas iPhone/Android
- digest-2026-10-15-tvde-pedir-nunca-trava — Claude Code 14-15/10 — pedir corrida nunca trava (caso Stela)
- digest-2026-10-16-chave-nova-edge — Chave nova 16/10 — Edge Functions a aceitar a sb_secret (Opus)
- digest-2026-10-16-chave-nova-fecho-mcp — Chave nova 16/10 — fecho pelo MCP (portões, robot-b) e o que falta
- digest-2026-10-16-chave-nova-sem-partir — Claude Code 16/10 — chave nova sem partir: blocos 1-6 preparados, publicação à espera do token
- digest-2026-10-16-claude-ai-filme-adendo-boca — Claude.ai 16/10 14:55 — boca reprovada pelo Danilo, adendo colado na missão, sessões arquivadas
- digest-2026-10-16-claude-ai-filme-prompt — Claude.ai 16/10 — prompt da missão Ep1 perfeito dia e noite (entregue ao Danilo)
- digest-2026-10-16-ep1-perfeito — Digest Bora Studio — Ep1 perfeito dia e noite (v5), 16/10/2026
- digest-2026-10-17-cancelamento-tardio-app — Claude Code 17/10 — cancelamento tardio TVDE na app, no motorista e no painel (publicado nas 3)
- digest-2026-10-17-reel-favores — Claude Code 17/10 — reel dos Favores (produzido, NÃO publicado)
- digest-2026-10-17-reel-favores-publicado — Claude.ai 17/10 — reel dos Favores PUBLICADO (substitui o digest de 16:28 que diz NAO publicado)
- digest-2026-10-19-jai-midday — Claude Code 19/10 — entrevista do Jai no mid-day no site
- digest-2026-10-19-limpeza-semanal-pagamento — Claude Code 19/10 — limpeza semanal só chama depois de pago
- digest-2026-10-21-geral-noite — Digest 21/10 noite — geral das pendências e prompt da noite
- digest-2026-10-21-retoma-fable — Digest 21/10/2026 — retoma Fable do Ep1 perfeito (Claude Code no PC)
- digest-2026-10-21-sem-pedir-permissao — Claude.ai 21/10 — sem pedir permissão a cada passo (como funciona de verdade)
- digest-2026-10-22-cadastro-estafeta — Cadastro do estafeta: fotos chegam e aprovação mostra tudo — 22/10 (Claude Code, Opus)
- digest-2026-10-22-geral-noite — Noite 21→22/10 — geral-noite (fila, encomendas, segurança, e-mail dos agentes)
- digest-2026-10-23-jai-brunel — Claude Code 23/10 — artigo da Brunel no site do Jai
- digest-2026-10-23-livro-comum — Digest — livro comum, skills numa pasta só, caça-clientes em loop (feito a 25/10)
- digest-2026-10-23-omniroute — Claude Code 23/10 — OmniRoute na VPS (agentes nunca param)
- digest-2026-10-23-omniroute-ronda2 — Claude Code 23/10 — OmniRoute sem OpenCode Go (2.a ronda)
- digest-2026-10-23-radar-videos-0810 — Digest: radar de vídeos 08/10 (AEO e filme)
- digest-2026-10-24-angariadores — Claude Code 24/10 noite — angariadores (definições, anúncio, grupos)
- digest-2026-10-24-geral-sabado — Missão geral de sábado 24-26/10 (Claude Code, Opus) — 7 blocos feitos
- digest-2026-10-25-angariadores-publicado — Digest 25/10 tarde — vídeo do angariador publicado
- digest-2026-10-25-angariadores-video — Digest 25/10 — vídeo do angariador (bloco 3)
- digest-2026-10-25-commits-orfaos-docs-papeis — Revisão 25/10 — dois commits de 22/10 só no PC, publicados nas 3 plataformas
- digest-2026-10-25-tres-tarefas-noite — Digest — sem margem não-parceiro, botão chamar entregador já, nome do cliente e valor real da caixa (25/10 noite)
- digest-2026-10-26-guarda-primeiro — Claude Code 26/10 — Guarda primeiro: anúncio Meta e embaixador IPG
- digest-2026-10-26-paridade-rea — Digest 26/10 — paridade REA
- digest-2026-10-26-plano-14-dias-dia3 — Claude.ai 26/10 — plano de 14 dias "A Guarda tem tudo no Bora", ponto do dia 3
- digest-2026-10-27-boom-burger — Digest 27/10 — Boom! Burger: demonstração pronta e consertos no ramo
- digest-2026-10-27-boom-burger-2 — Boom! Burger — fotos, preços e cartaz (27/10/2026)
- digest-2026-10-27-boom-burger-3 — 27/10 10:00 — resposta ao 1.º interessado nas vagas + estado Boom! Burger
- digest-2026-10-27-boom-burger-4 — 27/10 10:20 — Boom! Burger recebeu site/loja/painel + 1.ª angariadora (Anna Beatriz)
- digest-2026-10-27-boom-burger-5 — Boom! Burger 27/10 tarde — consertos no servidor + adendo 3
- digest-2026-10-27-boom-burger-contrato — 27/10 10:47 — contrato de parceria enviado à Boom! Burger
- digest-2026-10-27-boom-burger-precos-demo — 27/10 15:35 — preços da Boom! Burger + demonstração de 28/10 às 11:00
- digest-2026-10-27-plano-14-dias-dia4 — Plano 14 dias — dia 4 (27/10/2026)
- digest-2026-10-27-reel-tesla-bora — Digest 27/10 — reel do novo Roadster com o emblema Bora
- digest-2026-10-27-vagas-1o-interessado — 27/10 08:20 — 1.º interessado nas vagas (angariador/embaixador) + estado Boom! Burger
- digest-2026-10-28-missao-geral — Missão geral 28/10 (estafeta, reembolsos, Boom, robô, erros) — parcial, parada pelo limite do motor
- digest-2026-10-29-candidatos-documentos — Candidatos e documentos — 29/10 (Claude.ai)
- digest-2026-10-29-final-app — Digest 29/10/2026 — missão final-app (Fable 5.1)
- digest-2026-10-29-publica — Digest — missão publica-2026-10-29 (29/10 noite, Fable 5.1)
- digest-2026-10-29-telegram-robo-login — Avisos "travou de vez" no Telegram (29/10) — causa, o que foi arrumado e o que falta
- em-dia-ios-copiar-pipeline-bora — Em Dia / iOS: nao escrever o CI do zero, copiar o da Bora que ja funciona
- em-dia-iphone-identificador — Em Dia / iPhone: identificadores da Apple (bundle id, app id, SKU)
- em-dia-play-classificacao-conteudo — Em Dia / Play: respostas da classificacao IARC e o que muda quando as assinaturas abrirem
- em-dia-site-bloqueios-apple — Em Dia / site: tres coisas no site que chumbam a revisao da Apple
- emdia-grupos-facebook — Em Dia — publicações em grupos de Facebook
- engenharia-reversa — Engenharia reversa — método do Danilo para clonar o que já existe (pedido 17/10/2026)
- engenharia-reversa-achados-2026-10-17 — Engenharia reversa — achados da pesquisa mundial de 17/10/2026 (REA, filme, navegador)
- erros-aprendidos — Erros aprendidos — o caderno de correções do Danilo (todos os agentes leem ao acordar e acrescentam quando ele corrige)
- estado-2026-09-13 — Estado do Bora a 13/09/2026 (auditoria da Claude.ai depois de 3-4 dias sem Claude)
- fecho-2026-10-17-cancelamento-tardio — Fecho 17/10 — cancelamento tardio TVDE: publicado nas 3 plataformas (estado final do prompt prompt-cancelamento-tardio-2
- habilidades-propostas — Habilidades propostas pelo vigia (dinheiro/publicacao) — a Claude.ai decide
- ideias-pendentes-decisao-danilo — Ideias grandes à espera da decisão do Danilo (29/10/2026)
- ideias-videos-danilo — Ideias tiradas dos vídeos que o Danilo manda
- livro-areas-alertas-notificacoes — Alertas do Bora para o Danilo (Telegram + push admin persistente) — o que já dispara, por que caminho, e o que falta
- livro-areas-analise-apps-emulador — Ideia do Danilo (08/10/2026) de usar emulador Android + agente de IA para testar bugs do Bora e comparar com iFood/Uber/
- livro-areas-arandelas-quadros-jai — Trabalho de montar as arandelas de vidro e pendurar os quadros em casa do [[jai-agarwal]] — e o material que ficou a fal
- livro-areas-assistente-cliente — Ideia do Danilo de um assistente virtual de IA para o cliente dentro do Bora App (compras por conversa, comparar preços,
- livro-areas-assistente-cliente-ia — Ideia do Danilo (out/2026) de um assistente virtual com IA para o cliente dentro do Bora App — o que ele quer; ler antes
- livro-areas-auditoria-pagamentos — Missão "auditoria geral" pedida 15/08 — unificar pagamentos num jeito só; achados da Fase 1 (dados MCP) e estado das fas
- livro-areas-auditoria-pagamentos-parte2 — Missão "auditoria geral" pedida 15/08 — unificar pagamentos num jeito só; achados da Fase 1 (dados MCP) e estado das fas
- livro-areas-auditoria-pagamentos-parte3 — Missão "auditoria geral" pedida 15/08 — unificar pagamentos num jeito só; achados da Fase 1 (dados MCP) e estado das fas
- livro-areas-auditoria-pagamentos-parte4 — Missão "auditoria geral" pedida 15/08 — unificar pagamentos num jeito só; achados da Fase 1 (dados MCP) e estado das fas
- livro-areas-beunique — BeUnique Beauty & Academy (salão beleza, Guarda) — negócio NÃO fechou; loja desligada do app a 28/08. Histórico do que c
- livro-areas-boom-burger — Boom! Burger (hamburgueria artesanal da Guarda) — loja que o Danilo quer ganhar como parceira do Bora desde 27/10/2026; 
- livro-areas-bora-app — Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 1 de 4 — continua
- livro-areas-bora-app-parte2 — Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 2 de 4)
- livro-areas-bora-app-parte3 — Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 3 de 4)
- livro-areas-bora-app-parte4 — Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 4 de 4)
- livro-areas-bora-compras-online — Categoria nova no Bora com lojas externas "Bora China" (AliExpress) e "Bora Europa" — o que o Danilo quer (out/2026)
- livro-areas-bora-studio-agentes — Sistema de fiscais/agentes do Bora Studio — estado, falhas descobertas e método de validação (continuação de filme-anima
- livro-areas-bora-todo-dia — Ideia do Danilo (10/10/2026) para fazer os clientes abrirem o Bora App todos os dias — receitas, notificação diária, jog
- livro-areas-buzz-conselho-modelos — Conselho de modelos (local e remoto), motores do plano Go, app Buzz e robôs Gemini do app — estado atual e regras
- livro-areas-carteiro-e-juiz — Como o loop funciona hoje (carteiro, juiz, cadeia de motores, rotina de despertar) e as armadilhas provadas — ler ANTES 
- livro-areas-casa-manutencao — Ideia do Danilo (29/10/2026) de uma categoria "Casa & Manutenção" / marido de aluguel no Bora App (eletricista, pladur, 
- livro-areas-catalogo-restaurantes-glovo — Regra do Danilo para o catálogo das cadeias não-parceiras (Burger King, McDonald's, KFC…) no Bora — espelhar o Glovo; le
- livro-areas-chamada-estafeta-rotacao — Regra do Danilo (10/10/2026) para a chamada de pedidos ao estafeta no Bora — toque que grita sempre e ordem de rotação/c
- livro-areas-conectores-claude-ai — Conectores MCP da Claude.ai do Danilo — estado, senhas, e a REGRA de verificar o conselho antes de responder
- livro-areas-conselho-ias — Conselho de IAs pelo Chrome do PC (Gemini, ChatGPT, DeepSeek + Claude juiz) — fluxo fixo do Danilo desde 09/10/2026; ler
- livro-areas-contas-claras — Missão "contas claras" (20/09) — extratos de dinheiro compreensíveis para estafetas, motoristas, parceiros e o Danilo, e
- livro-areas-contas-parceiros — Como se calcula e se paga o dinheiro das lojas parceiras do Bora (ledger vs registo do pedido), erros corrigidos a 22/09
- livro-areas-cortex-bora — Córtex Bora orchestration system — MCP-connected knowledge base + autonomous loop (carteiro/Claude Code/Juiz/Telegram)
- livro-areas-divulgacao-bora — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte2 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte3 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte4 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-em-dia-app — Nova app do Danilo "Em Dia" (assistente do trabalhador independente a recibos verdes + carro + organizador entra/sai din
- livro-areas-empresa-agentes — Missão "empresa de agentes" (07/09) — o que o Danilo pediu depois do vídeo do Grok Bot (mais agentes, melhor que o vídeo
- livro-areas-encomendas-festa — Categoria nova "Encomendas para Festa" (bolos, salgados, doces por encomenda com data marcada) + abordagem à doceira da 
- livro-areas-endereco-web-cliente — Campo de morada do cliente na WEB do [[bora-app]] — cliente presa sem conseguir escrever endereço (31/08), causa achada 
- livro-areas-entrada-login-bora — Portas de entrada do [[bora-app]] (cliente, estafeta, parceiro) — regras que o Danilo fixou e prompt de auditoria entreg
- livro-areas-favores-paragem-casa — Regra do Danilo para Favores (errands) com "passar em casa primeiro" no bora-app — o que o estafeta tem de ver; ler ante
- livro-areas-fechar-pendencias-missao — Super-missão "fechar pendências" (20/10/2026) do bora-app — blocos 0,B,C,D,A1,A2,A3,E,H,I,J,G, o que já fechou e o promp
- livro-areas-fecho-semanal — Regras do Danilo para o acerto semanal do [[bora-app]] (recibos automáticos, comprovativo ao marcar pago, cobrança autom
- livro-areas-filme-animacao — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 1 de 4 — continua e
- livro-areas-filme-animacao-parte2 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 2 de 4)
- livro-areas-filme-animacao-parte3 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 3 de 4)
- livro-areas-filme-animacao-parte4 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 4 de 4)
- livro-areas-filme-animacao-v3 — Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz", prom
- livro-areas-ganhar-dinheiro-ia — Objetivo do Danilo de ganhar dinheiro com IA em modo automático (ele só comanda) — o que quer, o que escolheu e o que fi
- livro-areas-ganhos-prestador — Ganhos do prestador no [[bora-app]] — total do dia em qualquer ecrã e a fórmula do estafeta em loja não-parceira (fica c
- livro-areas-gibi-biblia-criancas — Animated Bible storytelling project for Danilo's daughters (characters Tuca and Lumi), pivoting to comic book (Gibi) for
- livro-areas-goola-acai — Goola Açaí (quiosque no La Vie Guarda) — parceiro fechado do Bora App; modelo de preço acordado, loja montada e categori
- livro-areas-gorjeta — Regra do Danilo para a gorjeta/gratificação no Bora (entregas e TVDE, copiar a Uber) — ler antes de mexer em gorjetas
- livro-areas-guarda-fc — Guarda FC — negócio do site fechado (clube com loja €1.700 + site pessoal €250; pago €1.550, falta €400), contrato, domí
- livro-areas-guarda-fc-monetizacao — Intenção do Danilo de monetizar o Guarda FC para além do site — pedido de análise 18/08 e ideias que ele próprio pôs em 
- livro-areas-guarda-fc-site-historico — Histórico técnico da construção do site do Guarda FC (v1 a v6) e do sistema de agentes de Telegram — ler antes de mandar
- livro-areas-habilidades-claude-code — Sistema de habilidades formais (.claude/skills/) do Danilo nos repos do Bora — quais existem, onde vivem, e o histórico 
- livro-areas-happy-site — Site pessoal do Jai Agarwal (jaiagarwala.com) — NO AR desde 15/08; regras vivas, estado atual e pendências; histórico té
- livro-areas-happy-site-historico — Histórico técnico da construção do site pessoal do Jai (v1→ronda1, 11-16/08) — ler antes de mexer a fundo no jai-site
- livro-areas-happy-site-parte2 — Site pessoal do Jai Agarwal (jaiagarwala.com) — NO AR desde 15/08; regras vivas, estado atual e pendências; histórico té
- livro-areas-happy-site-parte3 — Site pessoal do Jai Agarwal (jaiagarwala.com) — NO AR desde 15/08; regras vivas, estado atual e pendências; histórico té
- livro-areas-happy-site-parte4 — Site pessoal do Jai Agarwal (jaiagarwala.com) — NO AR desde 15/08; regras vivas, estado atual e pendências; histórico té
- livro-areas-henrique-esfihas — Henrique (esfihas, Guarda) — prospect novo do [[bora-app]], abordagem para entrar como parceiro de comida com loja monta
- livro-areas-hermes-agent — Hermes Agent infrastructure — VPS, PC bridge, ferramentas reais, e cadeia de modelos (migrado para o plano Go em 2026-08
- livro-areas-historia-dinossauros-lucifer — História infantil nova (dinossauros + guerra no céu/queda de Lúcifer + criação/Adão e Eva) que o Danilo quer transformar
- livro-areas-home-cliente-faixas — Home do app cliente do Bora — faixas de propaganda clicáveis, mais pedidos e lupa que acha tudo (pedido do Danilo, 05/10
- livro-areas-jai-agarwal-site — Jai Agarwal's personal brand site (jaiagarwala.com) — multilingual EN/PT/HI/ES site with gallery, press wall, streaming 
- livro-areas-jai-google-presenca — Mensalidade fechada com o Jai (139€/mês) para gerir a presença dele na Google — termos acordados, o que está incluído e 
- livro-areas-lacunas-sistema — Estado das lacunas do loop autónomo — quase tudo fechado em 2026-08-01; ler antes de decidir a próxima ordem
- livro-areas-lancamento-ios — Lançamento do Bora no iPhone/App Store — decisão e autorização total do Danilo (07/09), o caminho escolhido (conta indiv
- livro-areas-lavagem-auto — Serviço próprio de lavagem de carros com recolha e entrega dentro do Bora App — modelo, serviços e preços que o Danilo d
- livro-areas-leonidas-chocolates — Loja de chocolates Leonidas (Guarda), indicada pelo Cauê do Goola — aberta no Bora a 01/10 como loja não-parceira (balcã
- livro-areas-limite-pagamento-dinheiro — Limite de €40 em pagamento a dinheiro no [[bora-app]] — onde vive mesmo (4 sítios hardcoded) e prompt entregue para o to
- livro-areas-limpeza-vertical — Bora App Limpeza (cleaning) vertical — Helpling-style booking and dispatch
- livro-areas-livro-comum — "Livro comum" — o Danilo quer que Claude.ai, Hermes/Emerson, Claude Code e ChatGPT saibam todos o mesmo (tudo sobre ele 
- livro-areas-lojas-takeaway-guarda — Restaurantes da Guarda (sushi, pizzarias, churrasqueira) que o Danilo quer montar no Bora como lojas não-parceiras de ta
- livro-areas-luan-pladur — Luan Almeida (pladur/obras, Guarda) — prospect que chegou pelo WhatsApp a 04/10; Danilo ofereceu site grátis e pensar nu
- livro-areas-marca-ja-esta — Nome novo da marca da app do Danilo ("Já Está", substitui "Bora") — ler antes de falar de nome, marca, logótipo, domínio
- livro-areas-marketing-parceiros — Propaganda do Bora com parceiros — recrutamento de parceiros e regra dos cartazes com QR para as lojas (Mister Navalha, 
- livro-areas-mercadona-reabrir-loja — Plano do Danilo de reabrir a loja Mercadona no Bora só com perfumaria/cosmética/higiene — o que ele mandou guardar e ond
- livro-areas-metodo-sites — Método obrigatório para construir QUALQUER site (referência → design system → prompt → build → prémio) + agente classifi
- livro-areas-mini-site-business — Parallel mini-site web-dev business for local clients using a cinematic HTML/Cloudflare Pages workflow
- livro-areas-missao-fable-13-09 — Auditoria de 13/09 depois de 3-4 dias sem Claude (limite esgotado) — o que se achou (Apple aprovou, 2 pedidos com proble
- livro-areas-missao-voar — Missão grande pós-PC-novo (prompt-missao-voar.md, 30/08) — fases, decisões do Danilo e estado; ler antes de retomar qual
- livro-areas-mister-kebab — Mr Kebab & Restaurant (Guarda) — novo parceiro de Restaurantes fechado por Danilo; montar loja no app (catálogo via Glov
- livro-areas-mister-navalha — Barbearia Mister Navalha (Guarda, Ernando) — parceiro de Serviços do Bora: site de presente, assistente de WhatsApp e co
- livro-areas-modina-bazar — Modina Bazar (mercado brasileiro/asiático/africano, Guarda) — prospect novo, proposta de adesão como mercado não-parceir
- livro-areas-natur-house — Natur House Guarda (loja de produtos para emagrecer, Rua Mouzinho da Silveira, perto do La Vie) — loja NÃO-PARCEIRA aber
- livro-areas-negocio-sites-portugal — Plano de dinheiro do negócio de sites em Portugal — preços reais do mercado PT, ganchos legais que só existem cá, nichos
- livro-areas-nunca-mais-travar — Missões "nunca-mais-travar" e "paridade-auto-vs-manual" (2026-07-31) — por que o loop travava e o que já foi provado; le
- livro-areas-olho-automatico — Os 3 "olhos" que veem as telas do Bora sem humano (golden tests, juiz de visão Gemini, Firebase Test Lab) — estado, arma
- livro-areas-onboarding-estafetas — Regras do Danilo para candidatos a prestador do Bora (estafeta, limpeza, lavagem): aprovação, documentos em falta, fila 
- livro-areas-orchestration-loop — Autonomous orchestration loop — Claude.ai → Córtex → carteiro → Claude Code PC → Juiz → Telegram
- livro-areas-ouro-e-prata — Parceiro de Serviços Barbearia Ouro e Prata (Guarda) — perfil rico no app + mini-site cinematográfico externo
- livro-areas-pagamento-cartao-cliente — Regras do Danilo para o pagamento com cartão do lado do cliente no [[bora-app]] — escolher/trocar de cartão antes de pag
- livro-areas-painel-admin — Painel admin do Bora — o que o Danilo diz que está confuso, as armadilhas provadas (contadores em UTC, pedidos de demo n
- livro-areas-painel-conhecimento-jai — Projeto de identidade digital do [[jai-agarwal]] para a Google (painel de conhecimento) — o que o Jai pediu e a posição 
- livro-areas-partsflow — PartsFlow — site/catálogo de peças de telemóvel que o Danilo fez para o Azhar (Karachi LCD, Lisboa)
- livro-areas-plano-especial-cliente — Preços de corridas TVDE feitos à medida de um cliente concreto (fora dos planos semanal/quinzenal/mensal) — regra do Dan
- livro-areas-play-store-release — Bora App release pipeline nas 3 plataformas (Play Store/Android, iOS/App Store, web) — CI/CD, regras de paridade, histór
- livro-areas-por-do-sol — Pôr do Sol Kebab & Pizza House (Rua Formosa, Guarda) — loja NÃO-PARCEIRA no Bora, encomenda por takeaway; telefone, preç
- livro-areas-precos-catalogo-nao-parceiro — Regras que o Danilo fixou para o preço base dos produtos de lojas não-parceiras do [[bora-app]] (robot do talão + qual a
- livro-areas-produtos-peso-variavel — Regra do Danilo (26/10/2026) para produtos ao quilo nos mercados do [[bora-app]] — o estafeta troca o preço e o cliente 
- livro-areas-prospecao-sites-clubes — Campanha de venda de sites a clubes de futebol portugueses (a partir do caso Guarda FC) — o que o Danilo pediu, critério
- livro-areas-radar-ia — Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) 
- livro-areas-recibo-cliente-produto-falta — Regras que o Danilo fixou para mexer no conteúdo de um pedido já feito (produto em falta, acrescentar produto) e para o 
- livro-areas-regras-lancamento-categorias — Regras fixas do Danilo para lançar QUALQUER categoria, loja ou serviço novo no Bora — ler ANTES de planear ou montar pro
- livro-areas-sabores-de-casa — Sabores de Casa Açaí (mercado BR + açaí, Guarda) — parceiro no app + mini-site cinematográfico de presente (esquema Ouro
- livro-areas-semente-da-luz — "A Semente da Luz" — biblical animated children's series (Kaggle GPU, Wan 2.2 I2V, multi-agent quality system)
- livro-areas-sistema-sem-travas — Pedido do Danilo (15/10/2026) para o sistema ficar automático sem pedir permissão a cada passo — auditoria das trancas n
- livro-areas-stripe-connect — Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata 
- livro-areas-stripe-connect-parte2 — Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata 
- livro-areas-stripe-connect-parte3 — Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata 
- livro-areas-talao-nao-parceiro — Ecrã do talão do estafeta em pedidos não-parceiros do [[bora-app]] — o que o Danilo exige do fluxo e o prompt entregue a
- livro-areas-taxa-cancelamento-pedido — Regras do Danilo para cancelamento de pedidos de entrega do bora-app — taxa de cancelamento, reembolso ao MB Way/cartão 
- livro-areas-tokens-cliente — Regras do Danilo para o cliente usar tokens a pagar pedidos no Bora — ler antes de mexer em desconto de tokens, checkout
- livro-areas-tvde-cancelamento-tardio — Regra do Danilo (17/10/2026) para o cliente que cancela uma corrida TVDE depois dos 3 minutos — cobra a corrida inteira 
- livro-areas-tvde-central-corridas — Central de corridas do Danilo para clientes que ligam por telefone (sem app) — regra de ficar no core do Bora, fila entr
- livro-areas-tvde-fila-atribuicao — Fila inteligente de atribuição de motoristas do TVDE (tempo de estrada, nota, aceitação) e canal ao vivo do carro — pedi
- livro-areas-tvde-historico — Histórico detalhado do TVDE já superado/cumprido (builds de jul/2026, categoria por aprovação) — ler só quando for preci
- livro-areas-tvde-mapa-navegacao — Mapa/navegação do motorista e o que o CLIENTE vê durante a corrida (carro, ETA, avaliação) — causas achadas e estado; co
- livro-areas-tvde-operador-proprio — Legalização do TVDE — empresa de operador própria (hipótese) e legalizar o Bora Motorista no IMT; decisões e ordem que o
- livro-areas-tvde-pacote-ida-volta — Regra do Danilo para o ganho dos motoristas no pacote ida-e-volta do TVDE do [[bora-app]] — ler antes de mexer no preço 
- livro-areas-tvde-pagamento-mbway — Regra do Danilo para o pagamento MB Way nas corridas TVDE (tocar ao motorista assim que o cliente paga) e o prompt entre
- livro-areas-tvde-preco-fixo — Regra do Danilo para o preço das corridas TVDE do Bora — preço fixo fechado ao pedir; ler antes de mexer em tarifa, fim 
- livro-areas-tvde-presenca-online — Regra do Danilo para o estado online do motorista no TVDE do Bora (só o botão desliga) e o estado da regra de GPS parado
- livro-areas-tvde-reserva-agendada — Reserva de corrida agendada no TVDE (estilo Uber Reserve) — regras que o Danilo definiu, o que o banco já tem e o desenh
- livro-areas-tvde-sobreposicao — Regra do Danilo para sobreposição de corridas TVDE (back-to-back estilo Uber) — ler antes de mexer em despacho, oferta o
- livro-areas-tvde-vertical — Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments (parte 1 de 4 — continua em livro-areas-tvde-verti
- livro-areas-tvde-vertical-parte2 — Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments (parte 2 de 4)
- livro-areas-tvde-vertical-parte3 — Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments (parte 3 de 4)
- livro-areas-tvde-vertical-parte4 — Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments (parte 4 de 4)
- livro-areas-whatsapp-loja — Regras fixas do Danilo para o atendimento automático do WhatsApp da loja — ler antes de mexer nesse atendimento
- livro-claude-code-aprendeu — O que o Claude Code aprendeu sozinho (memória automática do PC), cópia
- livro-claude-md-detalhe — Detalhe dos CLAUDE.md (repo e global) antes do corte de 23/10/2026
- livro-faxina-2026-10-25 — Faxina do livro 2026-10-25 (proposta do escriba + revisão do critico; nada apagado)
- livro-hermes-aprendeu — O que o Hermes aprendeu sozinho (MEMORY.md + USER.md), cópia noturna
- livro-hermes-skills — Skills do Hermes (as que criou + lista das de fábrica), cópia noturna
- livro-hermes-soul-detalhe — Alma antiga do Hermes (SOUL.md de 611 linhas) antes do corte de 23/10/2026
- livro-porta-unica — Livro — porta única: como ligar qualquer IA ao livro (MCP do Córtex ou LIVRO.md com senha)
- livro-resumo — Livro do Bora — resumo para o ChatGPT (regras + erros + índice, sem pessoais), gerado
- livro-topics-communication — How Danilo communicates and the language conventions across his tools
- livro-topics-erros-aprendidos — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir em qualquer área onde
- livro-topics-erros-aprendidos-parte2 — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir em qualquer área onde
- livro-topics-erros-aprendidos-parte3 — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir em qualquer área onde
- livro-topics-prioridades — Como o Danilo decide prioridades no negócio — foco dos próximos meses e regras de desempate quando duas coisas competem 
- livro-topics-regras-motores-e-prompts — Regras do Danilo sobre que motor/ferramenta usar (Fable, Opus, ChatGPT, GLM, Gemini, OpenCode) e sessões no Chrome — ler
- lojas-takeaway-precos — Lojas de takeaway por telefone: Bora (não-parceiro) contra Glovo e Uber Eats, Guarda, 29/10/2026
- maiores-18-verificacao-idade — Maiores de 18 — tabaco e álcool com verificação de idade na entrega (aplicado 07/10/2026)
- mapa-sessoes-contas — Mapa de sessões e contas — que conta está em que sítio (provado no ecrã a 17/09/2026)
- mensagem-hugo-pendente-2026-10-29 — Mensagem para o Hugo (grupo Contabilidade) preparada 29/10 17:40 — por enviar quando o Danilo disser
- mercadona-reabrir-loja — Mercadona Guarda — reabrir só com perfumaria/cosmética/higiene (preparado 14-15/10/2026)
- motores-rotacao-2026-10-29 — Motores gratis em rotacao - medicoes e cadeias (29/10/2026)
- paridade-mundo-2026-10-29 — Paridade do mundo, segunda volta (Rappi, DoorDash, Zomato, Meituan) 29/10/2026
- paridade-mundo-e-lei-2026-10-17 — Bora vs Uber/Glovo/iFood/Bolt/Grab/Meituan + obrigações da lei em Portugal (pesquisa 17/10/2026)
- paridade-rea-2026-10-26 — Paridade REA 26/10 — Glovo, Uber Eats, iFood e Bora vistos de fora (resumo)
- paridade-rea-2026-10-26-plano — PLANO de melhorias do Bora (paridade REA 26/10) — à espera da revisão da Claude.ai
- paridade-uber-ifood-2026-10-13 — Paridade Bora vs Uber/Uber Eats/iFood + REA (vídeos de 13/10)
- perfil — Quem é o Danilo
- pesquisa-assistente-cliente-2026-10-07 — Pesquisa mundial para o assistente de compras IA do cliente (base da missão que vem depois do +18)
- pesquisa-fatura-nif-2026-10-28 — Fatura com NIF, produto em falta e entrega grátis nos parceiros — pesquisa e decisões (28/10/2026)
- plano-14-dias-dia6-a-14 — Plano de 14 dias — do dia 6 ao dia 14 (29/10 a 06/11/2026)
- plano-melhor-que-uber-glovo-2026-10-29 — Plano "100% melhor que a Uber e a Glovo" — volta ao mundo 29/10/2026
- playbook-redes-emdia — Playbook das redes — Em Dia (28/09)
- prompt-auditoria-3-plataformas-2026-10-06 — Prompt de missão: auditoria das 3 plataformas (06/10)
- prompt-boom-burger-2026-10-27 — PROMPT Boom! Burger — loja parceira + site premium (27/10/2026)
- prompt-boom-burger-2026-10-27-texto-completo — PROMPT Boom! Burger — texto completo (27/10/2026)
- prompt-boom-burger-adendo3-2026-10-27 — Prompt ADENDO 3 Boom! Burger (27/10 17:06) — consertar já o que ficou para trás
- prompt-boom-burger-adendo4-2026-10-28 — PROMPT Boom! Burger — adendo 4 (fatura com NIF + entrega grátis preparada), 28/10/2026
- prompt-cancelamento-tardio-2026-10-17 — Prompt: cancelamento tardio TVDE — app, painel e publicação nas 3 plataformas (17/10) — estado: a correr
- prompt-final-app-2026-10-29 — Prompt missao final-app-2026-10-29
- prompt-maiores-18-2026-10-07 — Prompt: verificação de idade +18 (tabaco/álcool) — estado: PRONTO, NÃO LANÇADO (bloqueado: publica nas lojas, falta o Da
- prompt-missao-da-noite-2026-10-07 — Prompt MISSÃO DA NOITE 07/10 (FABLE) — Bora Assistente (prioridade) + fechar +18 + Gmail caça-clientes + Apple Foco + GP
- prompt-missao-geral-2026-10-28 — PROMPT missão geral 28/10 (Divan + Boom + robô WhatsApp + cartazes + erros), parte 1/2
- prompt-missao-geral-2026-10-28-parte2 — PROMPT missão geral 28/10, parte 2/2 (blocos 1 a F, resumo)
- prompt-peso-variavel-2026-10-26 — PROMPT missão peso variável (26/10/2026) — para o Claude Code do PC
- prompt-publica-e-fecha-2026-10-29 — Prompt: publicar hoje + arrumação + Bloco 11 + reembolsos (29/10 18:20)
- prompt-publica-e-fecha-2026-10-29-adendo-1 — Adendo 1 ao prompt publica-e-fecha (29/10 18:40): motores do robô em grátis com rotação
- prompt-publica-e-fecha-2026-10-29-adendo-2 — Adendo 2 ao prompt publica-e-fecha (29/10 18:55): motores grátis do OpenCode em rotação + link /pedir/boom do site
- prompt-publica-e-fecha-2026-10-29-adendo-3 — Adendo 3 (29/10 19:08): escolha do reembolso bem clara para o cliente na app
- prompt-publica-e-fecha-2026-10-29-adendo-4 — Adendo 4 (29/10 19:10): robô WhatsApp da Boom AO VIVO para o teste do Danilo, resposta na hora, super inteligente
- prompt-publica-e-fecha-2026-10-29-adendo-5 — Adendo 5 (29/10 19:18): revisão da conversa do dia — o que ainda faltava
- prompt-talao-confirmar-loja-saldo-2026-10-28 — PROMPT 28/10 — Confirmar do talão, nome da loja, dinheiro a cobrar com saldo/tokens, reembolso no cancelamento (100% sal
- prompt-talao-confirmar-loja-saldo-2026-10-28-bloco-d — Adenda 18:30 ao prompt de 28/10 (talão Auchan/Divan): Bloco D novo — reembolso no cancelamento
- radar-2026-10-05 — Radar de vídeos 05/10 — filme (5 caminhos) e negócio
- radar-2026-10-06 — Radar de vídeos 06/10 — negócio e reforços para o filme
- radar-2026-10-07 — Radar de vídeos 07/10 — skills, mods do Claude Code e regras de reels
- radar-2026-10-08 — Radar de vídeos 08/10 — Haiku 5.5, destravar o Jev, AEO e boca sincronizada com voz própria no Flow
- radar-2026-10-09 — Radar de vídeos 09/10 — Hermes+Orca, Biblioteca de Anúncios para caçar clientes, métricas hook/hold dos reels
- radar-2026-10-10 — Radar de vídeos 10/10 — caça-clientes por negócios sem site, novidades dos recibos verdes 2026, Flow em cenas de 10 s pa
- radar-2026-10-11 — Radar de vídeos 11/10 — depoimento da Mister Navalha como prova de venda, Claude Motion para o Em Dia, tela verde nos re
- radar-2026-10-12 — Radar de vídeos 12/10 — validar emails no caça-clientes, mini-amostras no Upwork, Reddit para o Em Dia, ElevenLabs como 
- radar-2026-10-13 — Radar de vídeos 13/10 — REA para auditar a segurança do Bora e do Em Dia, rececionista de voz e resgate de orçamentos pa
- radar-2026-10-14 — Radar de vídeos 14/10 — corte automático nos reels, 2,5 palavras/s nas falas e prompts de movimento de 3 coisas para o f
- radar-2026-10-15 — Radar de vídeos 15/10 — OpenCode 2.0 no telemóvel, Free LLM API e skills só leitura
- radar-2026-10-16 — Radar de vídeos 16/10 — Hermes a vigiar o Bora, momento mágico de 10 s no Em Dia, carrosséis com movimento
- radar-2026-10-17 — Radar de vídeos 17/10 — REA continua pendente (12 vídeos), 15 pendentes à vista, rececionista de voz e diagnóstico nas I
- radar-2026-10-18 — Radar de vídeos 18/10 — REA continua pendente (+3 vídeos), CRM WhatsApp aberto white-label, sites grátis no Cloudflare; 
- radar-2026-10-19 — Radar de vídeos 19/10 — REA chega a 17 vídeos e continua pendente; rececionista de voz grátis com n8n; recolha das 02:00
- radar-2026-10-20 — Radar de vídeos 20/10 — prazo 31/10 da declaração trimestral (Em Dia); REA na missão de hoje mas ainda não arrancou; rec
- radar-2026-10-21 — Radar de vídeos 21/10 — REA arrancou hoje (N4, em curso); marketing orgânico de apps vira moda; recolha das 02:00 bloque
- radar-2026-10-22 — Radar de vídeos 22/10 — REA feito (auditoria N4); Claude Duet e Upwork MCP novos; recolha das 02:00 bloqueada 5.º dia
- radar-2026-10-23 — Radar de vídeos 23/10 — 60 revistos; Em Dia calculadoras, classificador grátis e QR do Bora propostos; Claude Duet e pac
- radar-2026-10-24 — Radar de vídeos 24/10 — 40 revistos; OmniRoute já feito; carrossel animado em código aprovado; licenças da Câmara e Wan 
- radar-2026-10-26 — Radar de vídeos 26/10/2026 — 40 revistos, 5 novos, 11 pendentes
- radar-2026-10-27 — Radar de vídeos 27/10/2026 — 40 revistos, 6 novos, 14 pendentes
- radar-2026-10-28 — Radar de vídeos 28/10/2026 — 40 revistos, 6 novos, 7 pendentes
- radar-2026-10-29 — Radar de vídeos 29/10/2026 — 20 revistos, 4 novos, 3 pendentes
- reembolsos-b2-00-leia-me — reembolsos-b2-00-leia-me
- reembolsos-b2-01-shared-cobranca — reembolsos-b2-01-shared-cobranca
- reembolsos-b2-ef-admin-cancel-order — reembolsos-b2-ef-admin-cancel-order
- reembolsos-b2-ef-auto-refund-order — reembolsos-b2-ef-auto-refund-order
- reembolsos-b2-ef-cancel-order-with-choice — reembolsos-b2-ef-cancel-order-with-choice
- reembolsos-b2-ef-client-cancel-order — reembolsos-b2-ef-client-cancel-order
- reembolsos-b2-ef-execute-cancellation — reembolsos-b2-ef-execute-cancellation
- reembolsos-b2-ef-reprocess-refund-e-refund — reembolsos-b2-ef-reprocess-refund-e-refund
- reembolsos-b2-ordem — reembolsos-b2-ordem
- reembolsos-b2-sql-tokens — reembolsos-b2-sql-tokens
- reembolsos-dashboard-passos — Reembolsos (Bloco 2) — passos para publicar pelo painel do Supabase (29/10/2026)
- regras-do-danilo — Regras do Danilo — versão 23/10/2026 (vale para Claude.ai, Hermes/Emerson, Claude Code, ChatGPT, OpenCode)
- regras-operacao-agentes — O que podes e o que não podes fazer no Bora em produção (ChatGPT, OpenCode, Hermes, Claude Code)
- regras-reels-radar-2026-10-04 — Regras de reels Em Dia e Bora (radar 04/10)
- relatorio-boom-burger-2026-10-27 — Boom! Burger — demonstração e consertos (27/10/2026, noite)
- relatorio-semanal-reels-2026-10-29 — Relatório semanal dos reels - 2026-10-29
- resposta-contabilista-iva-2026-10-28 — Resposta do Hugo (DC Consultores): IVA normal trimestral, programa de faturação, modelo aceite — 28/10/2026
- resposta-contabilista-iva-parte2-2026-10-28 — Hugo (15:54-15:55): faturas emitidas pelo escritório, não ficar no art. 53.º, IVA não mexe na margem — e as contas de ou
- robo-documentos-2026-10-29 — Robô fiscal de documentos — relatório (adendo 3, 29/10/2026)
- seguranca-auditoria-2026-10-21 — Auditoria de seguranca do app (21/10, agente N4)
- sistema-motores-e-portas — Quem faz o quê — uma porta só (atualizado 17/09/2026)
- skills-indice — Índice das skills da pasta comum (Claude Code, Hermes, Claude.ai) — uma linha cada
- sql-modo-demo-2026-10-27 — SQL do modo demonstracao (Boom! Burger) para o Claude.ai aplicar
- tokens-metade-do-saldo-2026-10-14 — Tokens do cliente: metade do saldo + desconto chega à cobrança (14/10/2026)
- whatsapp-a-discutir — WhatsApp — o que ainda está por discutir com o Danilo (esqueleto desligado)

