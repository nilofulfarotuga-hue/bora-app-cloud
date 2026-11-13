---
id: memoria-claude-ai-livro-resumo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-12
zona: verde
confianca: alta
estado: atual
---

# Livro do Bora — resumo para o ChatGPT (regras + erros + índice, sem pessoais), gerado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-resumo`, origem `claude-code`, atualizada em 2026-11-12T23:40:08.551923+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro resumo · memoria claude.ai · claude_ai_memoria

# Livro do Bora — resumo para o ChatGPT (2026-11-12)

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
- Reembolso de cancelamento (regra de 29/10, confirmada 31/10 06:44, substitui a antiga de 80% saldo + 20% tokens): a ESCOLHA é do CLIENTE, bem clara na app: (a) "Carteira Bora" → 100% do valor vai para a carteira como saldo livre, para comprar o que quiser (sem parte em tokens); (b) "Reembolso para a tua conta (MB Way/cartão)" → estorno total pelo mesmo meio. Nunca escolher por ele por defeito escondido. A antiga divisão 80/20 (platform_settings) deixa de valer; a implementação entra na fila das missões.
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
- 30/10 (claude-ai): No token do Supabase do Dipsy escolhi por ele 90 dias e só leitura com escrita em 4 áreas; ele corrigiu: quer acesso total (Full access) e para sempre (Never), "não quero ficar renovando nem apertando permitir, não quero passar raiva". → Quando ele pede acesso para os agentes dele (Dipsy, Claude Code), configura-se total e sem validade; o risco explica-se uma vez, numa linha, e a escolha é dele.
- 30/10 (claude-ai): Dei-lhe a lista do que escolher no formulário do token do Supabase (validade, organização, preset) para ele preencher; ele reclamou irritado: "eu não faço nada, não preencho nada, quem preenche é você ou um agente, eu só aceito e clico no verde". → (repete as de 23/09 e 28/08) Formulário de painel web (Supabase, Google, Apple…) preenche-o o Claude pelo Chrome ou o Claude Code no PC; a ele só fica o botão verde final, com a página já preenchida à frente dele.
- 30/10 (claude-ai): Na resposta ao Jai sobre a entrevista dele no canal de YouTube do Professor Kalinga (10 mil visualizações em menos de 12 h) escrevi "Great talk with Ranjit" só porque o título do vídeo dizia "Ranjit & Jai"; o Jai corrigiu: a conversa é com o Professor Kalinga, e a do Ranjit é a que já está no site dele. → Regra do Danilo (30/10 21:11): antes de escrever sobre um vídeo ou de o pôr no site, primeiro pôr o agente que vê os vídeos a vê-lo e ler o que ele diz (quem fala, de que se fala); nunca escrever só pelo título.
- 31/10 (claude-ai): Os 2 anúncios da Meta (instalar + carrossel do check-in) foram montados por script (fotos + texto plano) e publicados prontos a ligar sem o Danilo os ver; o carrossel só mostrava 5 cartões e ele leu "40" como se fosse só 40 dias; reprovou ("negócio amador não; tem que ver como os grandes fazem; e me manda aqui antes de aprovar"). → Regra: anúncio pago da Meta nunca liga sem ele ver e aprovar no chat as imagens e os textos; antes de criar, estudar os anúncios dos grandes (Uber Eats, Glovo, Bolt, Too Good To Go) e seguir esse padrão; o carrossel do check-in mostra os 30 dias todos (calendário) e cada prémio com nome e foto (2 salgados da Keli ao dia 10, açaí do Goola ao dia 15, limpeza ou lavagem ao dia 30), nunca um número solto que se confunda com dias.
- 31/10 (claude-ai): o livro comum e o resumo dos agentes ainda diziam que o reembolso de cancelamento para a carteira era 80% saldo + 20% tokens → Regra atual (Danilo 29/10 e 31/10 06:44): a escolha e do CLIENTE e tem de estar clara na app: Carteira Bora = 100% saldo livre para comprar o que quiser; MB Way/cartao = estorno total pelo mesmo meio. A divisao 80/20 deixou de valer. Toda pagina, prompt ou resumo que a cite esta desatualizado.
- [stated] 19/10: no prompt do Mid-Day deixei a foto como opcional ("se não houver foto, publica só o link") → regra: matéria de imprensa no site do Jai entra SEMPRE com foto; o prompt manda o Claude Code ir buscá-la ele próprio (foto do artigo online, página do jornal digital/e-paper) — nunca depender de o Danilo arrastar ficheiros
- [stated] 28/10 10:33 (na hora da demonstração da Boom): disse-lhe que as senhas das contas de demonstração estavam no Telegram e não lhas dei; ele não as tinha à mão e reclamou "você tem que me dar a senha" → regra: quando ele pede o login de uma conta de teste/demonstração, dou-lho logo aqui na conversa (e se eu não tiver a senha, reponho uma nova pelo servidor, testo e dou-a); nunca o mandar procurar no Telegram
- [stated] 31/10 06:32: disse-lhe que a voz do Dipsy estava "completa e provada" — a prova de 30/10 foi com um áudio gravado pelo próprio bot; o primeiro áudio real dele (iPhone, 11 s, 06:24) demorou 7 min e o Dipsy respondeu que não entendeu → regra: prova de voz/áudio só conta com um áudio REAL do telemóvel dele (ou, sem ele, um ficheiro de voz do Telegram gravado por telemóvel), medido do fim ao fim; nunca dar por provado o que só passou em teste sintético
- [stated] 31/10 06:47: as peças novas da Meta foram-lhe mostradas sem juiz visual e ele apanhou 3 erros à vista ("o juiz tinha que pegar isso"): metade de outro hambúrguer por baixo do hambúrguer; morango a representar supermercado (mercado = saco/cesto de compras com o nome Continente, nunca uma fruta solta) e colado ao telemóvel; "Restaurantes da Guarda" ilustrado com salgados; calendário com dias 8, 9, 11, 12… em branco quando os tokens continuam todos os dias (ciclo 5,5,10,10,15,15,40 recomeça depois do dia 7) → regra: toda peça de propaganda passa por um juiz com visão (lista: nada cortado/sobreposto, cada imagem = o que a legenda diz, nenhum dia/valor em branco, legível a 200 px) antes de lhe ser mostrada; e um calendário de prémios mostra o que se ganha em TODOS os dias
- 31/10 (claude-ai): Na resposta ao Jai sobre a notícia da Minerva (ele só reencaminhou o link da SportsDunia, sem texto) escrevi "Big news bro 🔥 I'll add this one to the press section of your website", no mesmo tom da mensagem de 06:07 ("10k+ views already, that's huge 🔥 ... says it all 👏"). O Danilo reprovou: não é natural, é exagerado. → Mensagem ao Jai é curta e direta, como o Danilo fala ("ok, isso é legal" + o que vai fazer): sem "big news", "that's huge", elogios nem emojis de festa. Antes de escrever, ver no WhatsApp como os dois falam e seguir esse estilo.
31/10 (quem errou: claude-ai): a melancia do Continente estava na app por unidade (7,14 €) e saiu 9,06 € na balança; o estafeta não conseguiu trocar o preço. Eu tinha dado o peso variável por arrumado a 26/10, mas só o servidor estava feito: o ecrã do estafeta nunca foi feito (o prompt ficou "à espera" e nunca foi colado) e a regra de nomes deixou de fora tudo com "semente" e fruta noutras secções → funcionalidade com servidor + app só está feita quando a parte da app está publicada e provada nas 3; prompt que fica "à espera" é verificado no e2e_log até correr, nunca esquecido; marcar produtos por regra de nomes = rever por amostra o que ficou de fora (fruta, legumes, talho) antes de dar por feito.
31/10 (quem errou: claude-ai): ao marcar a limpeza do Divan para as 18h copiei a tentativa que ele tinha cancelado na app (pacote T2, 4 horas, 45 €) em vez das 3 horas de sempre; o Divan cancelou e a app registou-lhe 45 € de taxa → a limpeza do Divan é de 3 horas por hora (produtos dele, 2 gatos), não o pacote T2; ao marcar uma limpeza por um cliente, seguir o formato das marcações habituais dele, nunca uma tentativa cancelada.
30/10 (quem errou: claude-ai): na mensagem ao Ricardo (cliente Uber, a quem faltava pagar um pouco) escrevi um limite duro ("até uma semana, não deixo acumular mais de 20 €, senão fica pesado para mim"); ele achou grosso → com cliente que deve pouco, a mensagem é leve — diz quanto falta e pergunta quando consegue pagar; o limite vai só como ajuda futura ("se um dia precisares outra vez, posso ajudar, só não com um valor muito alto"), sem números, prazos nem queixas.
31/10 18:29 (quem errou: claude-ai): na resposta ao Ricardo ("o que disseste ontem?") escrevi seco — só "não dá para fazer fiado", a conta e "quando consegues mandar?"; ele achou grosso outra vez (repete o de 30/10) → reto sem ser grosso — lembrar com calma que ajudou porque o cliente pediu e achou que era só até lhe sair o pagamento; dizer que uma vez ou outra ajuda, mas fiado não consegue nem deixa passar de 20 €; a conta vai no fim, sem frase seca de cobrança.
- 31/10 (claude-ai): 31/10: as missões no PC ficaram ~7 h paradas à espera de um Permitir que nunca apareceu ao Danilo; a Claude.ai só registava e voltava a ver de hora a hora. → Pedido de Permitir sem resposta em 15 min = a Claude.ai leva logo ao chat a lista numerada do que falta autorizar e faz por MCP com o "autorizo" dele; o que só o PC faz vai num prompt para ele colar numa sessão nova com "Ignorar permissões".
- 31/10 (claude-code): li "n tem q muar a validade da chave" como "nao tem de mudar" e ate gravei aqui a regra ao contrario; ele queria "nao, TEM QUE mudar a validade" → mensagem curta comecada por "n": ler como "nao, ..." e confirmar o sentido antes de gravar regra; a chave da VPS dos robos (robos-vps-3) fica SEM data de fim, escolha dele
- 01/11 (claude-ai): Devolvi ao Danilo uma lista de 42 pendências a pedir "autorizo" item a item e passei dias sem fechar nada; ele disse "antes estava tão bom, agora é uma palhaçada, você não ficar pedindo permissão para nada" (01/11/2026 19:56) → Quando ele pede, já está autorizado. Nunca devolver listas a pedir autorizo por item: executar tudo de uma vez com vários agentes em paralelo, e só juntar num ÚNICO pedido, no fim, o que mexe em dinheiro irreversível. Ele não clica em nada: eu clico, preencho, publico, crio chaves. Relatório só "fiz isto, falta isto".

- 01/11 (claude-ai): às 20:19 mandei ao Jai a conta da semana com 214 € (28 € da semana + os 186 € de 24/10 "ainda em aberto"), mas ele já tinha pago os 186 € no cartão, no telemóvel do Danilo, a 27/10 (Stripe 27/10 16:50, 186,00 €). A nota só dizia "sem registo de pagamento nas conversas" e eu tratei isso como dívida. O Danilo: "já recebi pelo aeroporto, o dele é só essa semana, você mandou errado" → antes de cobrar um saldo antigo, confirmar na Stripe (stripe_extrato_contabilista) e no WhatsApp se já foi pago; "sem registo" não é "por pagar"; na dúvida, perguntar ao Danilo antes de enviar.
- 01/11 (claude-ai): Mandei ao Jai (01/11 20:19) a conta da semana a dizer que os 186 € de 24/10 ainda estavam em aberto, só pela memória — ele já tinha pago por cartão a 27/10 (Stripe 16:50). O Jai ligou ao Danilo e teve de sair uma correção com pedido de desculpa. → Antes de mandar qualquer conta ou cobrança a alguém, confirmar o que já foi pago na BASE e na Stripe (payments/stripe_extrato_contabilista, orders pagos, ledger) — nunca só pela memória. Mandar só o que está mesmo por pagar.
- 01/11 (claude-ai): 01/11 21:10: no relatório final disse que a mensagem para o Hugo e o resumo da Stripe estavam "na página mensagem-hugo-2026-11-01 do livro", em vez de os escrever aqui no chat; ele tinha pedido o relatório detalhado da Stripe e a mensagem ao Hugo para conferir → quando ele pede relatório, resumo ou mensagem para conferir, vai SEMPRE escrito por inteiro aqui no chat, detalhado; o livro e o Córtex são só cópia para os agentes, nunca o sítio para onde o mando ler
- 02/11 (claude-ai): (não é erro) registo: Bora Motorista fechado a 02/11/2026 06:00 por ordem do Danilo → TVDE de passageiros está DESLIGADO desde 02/11/2026 06:00 (tvde_passageiros_enabled=false). Só volta a ligar com ordem dele.
- 02/11 (claude-ai): 02/11 14:55: disse ao Danilo que a Casa estava desligada (casa_enabled=false) sem ver que a conta dele boraappbora estava na lista de testadores; ele abriu a web e viu a Casa publicada, mal acabada → antes de dizer que uma categoria está desligada, ver também quem a vê por exceção (casa_testadores, contas demo) e dizer isso; quando ele quer desligar, desligar para todos, incluindo os testadores
- 02/11 (claude-ai): 02/11 17:57 (pedido da Dona Isabel, Continente): o pão avulso da padaria (Pão Bola de Mistura) estava por unidade sem opção de trocar o preço na balança — a marcação ao quilo de 26/10 e 31/10 só apanhou fruta, legumes e talho → pão avulso da padaria dos mercados (bolas, bijou, pão do dia sem embalagem) também é ao quilo; ao marcar produtos ao quilo, rever TODAS as secções de balcão (fruta, legumes, talho, peixaria, padaria, charcutaria ao corte), não só a fruta

- 03/11 14:05 (Danilo corrigiu): na análise fiscal mandei perguntar ao Hugo se o IVA normal foi "por opção" e propus passar a empresa a isenta, quando já estava falado (28/10 o Hugo disse que não compensa o art. 53.º e o Danilo respondeu "ok, fica no normal" = regime normal escolhido, 5 anos); e deixei de fora tudo o que já conversámos sobre os parceiros. REGRA: antes de qualquer análise de assunto já falado, puxar TODAS as conversas antigas do tema (cada vertical: parceiros, não-parceiros, Favores, limpeza, serviços) e partir do que lá ficou decidido; nunca voltar a propor o que ele já fechou.
- 03/11 14:23 (Danilo corrigiu): ele disse "você vai mandar esse texto aí" sobre as perguntas ao Hugo e eu abri o WhatsApp pessoal para enviar no grupo Contabilidade; ele parou-me: "não é pra enviar nada pra ninguém, é pra você fazer e me dar aqui a resposta". REGRA: "manda/faz o texto" sobre mensagens para terceiros = escrever o texto aqui no chat; só envio quando ele disser claramente "envia/manda para ele" depois de ver o texto.
- [stated] 03/11 14:47: no mercado, a fazer a compra para o Vansh, pediu "o NIF da empresa" e eu dei o da Bora (519686233); era o da Guarda FC SAD (518256430) → regra: compra ou serviço para o Vansh/Guarda FC = NIF da SAD; ler sempre o contexto do pedido antes de escolher qual "empresa"
- 03/11 (claude-ai): 03/11 20:14: ele pediu missão para o "DeepC/Gypsy" e eu li Gypsy como ChatGPT, lancei a missão no Claude Code e ele mandou parar → Gypsy/Gipsy/DeepC/Deep Sea = o Dipsy (DeepSeek Harness), NÃO o ChatGPT. Quando ele diz que a missão é para o Dipsy, não a lanço no Claude Code; o Dipsy faz tudo (roteiro e arte incluídos). O Dipsy hoje não publica nem sai da lista de sites do Bora: dizer isso ANTES de agir e perguntar nada, só dar o caminho.
- 04/11 (claude-ai): disse que a Izilda não conseguia agendar corrida "por não ter pedido de acesso", sem ver que ela tinha acesso e sem lembrar que a 01/11 ele mandou fechar o Bora Motorista para todos a partir de 02/11 06:00 (nunca tinha sido aplicado; saíram mais 6 corridas) → ordem de fechar/desligar uma categoria é aplicada no dia e hora que ele disser e provada por SELECT; antes de explicar porque um cliente não consegue usar algo, ver o acesso real dele e as decisões recentes sobre essa categoria.
- 04/11 (claude-ai): 04/11 11:13: li os avisos de ontem no Telegram e disse-lhe que o Divan ainda devia os 10,77 € do Favor dos pellets — o caso tinha sido fechado a 03/11 13:31 (o Divan pagou-lhe direto) e eu não puxei a conversa nem o e2e_log → aviso antigo do Telegram não é dívida; antes de dizer que alguém deve, ler a conversa do assunto e o e2e_log do pedido.
- 04/11 (claude-ai): 04/11 11:23: mensagem em inglês a dizer que o Fred só volta na terça e só ele pode pagar; respondi "espero pelo Fred na terça" sem ver no recibo-jogador-gfc que os 440,02 € já tinham sido pagos a 03/11 → mensagem sobre pagamento = ver primeiro se a conta já está paga; se está, a resposta diz que já recebi e não há nada a pagar.
- 04/11 (claude-ai): 04/11 11:24: escrevi a tradução da mensagem do Vansh e da resposta entre ferramentas e ela não lhe apareceu no ecrã; ele só viu o cartão em inglês e irritou-se → as duas traduções ("O Vansh falou" e "O que eu estou a responder") vão sempre por mensagem visível antes do cartão, ou como texto final depois da última ferramenta; nunca soltas no meio das ferramentas.
- 05/11 (claude-ai): 05/11 20:16: disse que os pedidos do McDonald's e do Jyosmi não tinham talão registado e calculei o lucro com o preço de balcão da app; ele tinha registado o talão do McDonald's com foto — a minha consulta com várias instruções devolveu só o resultado da última e não vi a tabela order_receipts_v2 → ver sempre uma consulta de cada vez (ou conferir que vieram todos os resultados) e, antes de dizer que falta talão, ler order_receipts_v2 e o bucket receipts; lucro de pedido não-parceiro usa o valor do TALÃO (driver_typed_total_cents), nunca o preço da app.
- 07/11 18:42 (Claude.ai): disse que o Valdemir devia €3,24 (banco: €1,77 pendente + €1,47 calculado) sem ver se já tinha pago; ele corrigiu "já pagou tudo, não deve nada" → dívida de motorista só se lista se a conversa confirmar; o banco mostra "pendente" mesmo quando o Danilo já recebeu à mão. Ao responder "quanto deve", dizer o que o banco mostra e perguntar se já pagou, ou ler as conversas antigas primeiro.
- 08/11 18:00 (claude-ai): pedido do Burger King sem NIF do cliente; eu disse-lhe "fatura sem NIF / consumidor final" e ele corrigiu "você tinha falado que era o NIF da Bora" → regra (conversa de 03/11): cliente deu NIF → talão com o NIF do cliente; cliente SEM NIF → consumidor final, NUNCA o NIF da Bora (regra mudada pelo Danilo a 10/11, NIF da Bora tirado do sistema); compra para o Vansh/Guarda FC → NIF da SAD. Antes de dizer que NIF pôr, ler as conversas antigas sobre o tema.
- [stated] 08/11 18:59: recusei forçar a entrega do pedido do Divan sem o código de 4 dígitos (disse que passava por cima da proteção da app); ele corrigiu: "eu sou o dono, é pra forçar e pronto" → regra: quando o Danilo manda finalizar/forçar um pedido, finaliza-se pela via oficial (RPC admin), sem exigir o código; o Dipsy e o Claude Code também têm de conseguir. Tirar as limitações, não inventar mais.
08/11 (quem errou: claude-ai): entreguei 6 missões sem cobrir tudo o que ele ditou (Stripe da empresa/parceiros/WhatsApp, vídeos do radar, briefs, pagamentos, plano de 14 dias, leis, menu, motorista→delivery) e o LEIA-ME sem dizer "não colar"; ele colou-o como missão e disse "você não ouviu tudo, ler palavra por palavra" → regra: antes de entregar, ler a mensagem dele frase a frase e marcar cada pedido num bloco (checklist 1:1); ficheiro de instruções leva no topo "NÃO colar".
08/11 (quem errou: claude-ai): no pedido do McDonald's voltei a oferecer mandar ao Hugo a pergunta do NIF; ele irritou-se: "não é para mandar" → regra: dúvida do NIF não vai ao Hugo; respondo eu direto, com a lei, sem propor envios.
08/11 (quem errou: claude-ai): listei os 186 € do Jai (24/10) como dívida; ele corrigiu "já está pago" → regra (repete 20/10 e 07/11): conta do Jai/Vansh só se lista como em aberto depois de confirmar na conversa recente que não foi paga; o livro fica desatualizado.
08/11 (quem errou: claude-ai): na M9 pus "texto para o Danilo mandar ao Jai" e "mandar o recibo dos 36 €"; ele corrigiu: "não é pra mandar mensagem nenhuma pro Jai" → regra: a missão do Jai é trabalho por trás (Wikipédia, Google, site, radar); nenhuma mensagem, recibo ou resumo vai ao Jai a não ser que o Danilo mande explicitamente.
- 09/11 (hermes): 09/11 (hermes): ouvi 'endia' por voz e assumi que era do Bora → 'Endia' = Em Dia (app de contas/impostos, pasta em_dia, e-mail/site emdia.boraguarda.com). Publicações do Em Dia NÃO levam a marca Bora; regras em emdia-grupos-facebook (máx 4/dia, 1 por grupo/semana, parar ao 1.º aviso).
09/11 (quem errou: claude-ai): ele mandou o email "do Emanuel" e eu perguntei se era o da Boom ou o do Vamos Já; irritou-se ("puxa o contexto") → regra: a conta da Boom estava à espera do email do dono (login provisório desde 27/10); ler o contexto e agir sem perguntar.
09/11 (quem errou: claude-ai): perguntou quanto o Valdemir tinha a receber e eu respondi com o fecho semanal; era o pedido de salgados da Keli que ele tinha acabado de pegar → regra: "quanto X recebe" = ver primeiro o pedido em curso de hoje.
09/11 (quem errou: claude-ai): disse quanto a Keli recebe sem ler a conversa de fecho com ela (24/08) → regra: valor a pagar a um parceiro = ler primeiro o que foi combinado no fecho e o esquema de preço da loja.
- 09/11 (hermes): Missao Em Dia no Facebook ficou parada: a ordem de publicar vinha num ficheiro e o filtro de seguranca do Claude Code recusou escrever o texto (ja tinha acontecido 30/09 e 06/11) → Ordem de publicar nos grupos tem de ir escrita DIRETAMENTE no prompt do claude -p (com o nome do Danilo, a data e 'PODE PUBLICAR ... no grupo X'), nunca so num ficheiro; assim passou a 09/11 15:13. Lancar no PC por ssh como utilizador danil (nao 'hermes') + schtasks /IT, em segundo plano. Posts em grupos privados ficam Pendentes ate o admin aprovar.
09/11 (quem errou: claude-ai): aceitei a troca do cliente do KFC (Durum Kebab) sem ver se existia, e não existia → regra: troca ou sugestão de produto de cadeia não-parceira só depois de confirmar no Glovo da Guarda (ou Uber Eats); no catálogo do Bora só fica o que lá existe

09/11 (quem errou: claude-ai): ao Ricardo (adiantado até dia 30) pus o preço por dia (4,23 €) → regra: ao cliente vai só o total somado e arredondado (segunda a sábado, sem domingo), nunca o preço por dia

09/11 (quem errou: claude-ai): liguei a Casa com o ladrilho só "Casa" e ícone simples na versão do iPhone; ele: "faz tudo pelo meio" → regra: categoria nova só se dá por publicada com o nome completo (ex.: "Casa e Manutenção") e o ícone 3D cartoon igual aos outros, visto nas 3 plataformas

09/11 (quem errou: claude-ai): pedi-lhe para ligar a Casa no painel após o classificador travar → regra: com a ordem dele, refazer eu pelas funções do painel; nunca lhe devolver o passo

10/11 (quem errou: claude-ai): NIF no talão (regra de 10/11, substitui a de 08/11): cliente pediu NIF → talão com o NIF do cliente; cliente SEM NIF → consumidor final, NUNCA o NIF da Bora (tirado do sistema a 10/11); compra para o Vansh/Guarda FC → NIF da SAD. Antes de dizer que NIF pôr, ler as conversas antigas sobre o tema

10/11 (quem errou: claude-ai): escrevi ao Hugo que estafetas e limpadoras são todos isentos de IVA → regra: uns são isentos, outros não (passam o limite); nunca dizer que todos são isentos

10/11 (quem errou: claude-ai): buraco de segurança no banco — dentro de função SECURITY DEFINER o current_user é SEMPRE o dono (postgres), por isso a guarda "current_user in ('postgres','service_role')" deixava qualquer sessão autenticada ler o resumo da Stripe e os prestadores com NIF, email e ganhos. Regra: guarda dessas funções usa is_admin()/role do JWT e, para ligação direta, session_user = 'postgres'; nunca current_user

11/11 08:01 (quem errou: claude-ai): depois de ele já ter colado o prompt, mandei-lhe uma versão nova inteira → regra: prompt entregue não se refaz; o que mudar vai num ADENDO curto aqui no chat, para a mesma sessão
- 11/11 (claude-code): 11/11: as travas ficaram abertas desde 10/11 18:50 (DESLIGAR-M11 corrido e nunca fechado com RESTAURAR-M10) → quem abre a janela das travas fecha-a na mesma sessão com RESTAURAR-M10 e prova os MD5; a sessão seguinte compara os MD5 de hoje com bak-20261108-m10 antes de começar e reporta se estiverem abertas
11/11 10:05 (quem errou: claude-ai): disse-lhe que faltava o Livro de Reclamações e o Hermes 0.23 — já estavam feitos (registo submetido 11/11 09:00 com o NIPC; Hermes 0.23.1 no ar desde 10/11 19:15) → regra: antes de listar pendências, ler o e2e_log MAIS RECENTE de cada assunto, não o registo antigo que ficou "pendente"
11/11 14:21 (quem errou: claude-ai): à farmácia (Rita Grilo) escrevi "não cobramos comissão" e "montamos a partir do catálogo da Glovo" → regra: parceiro novo = 3 primeiros meses sem taxa, depois 10% dos produtos (Glovo ~30%); nunca dizer que copiamos da Glovo; mensagem curta, natural e a puxar para fechar
11/11 14:56 (quem errou: claude-ai): tratei os 10% como a única margem com a farmácia → regra: farmácia = esquema da Boom para o cliente (15% no produto + 5% de serviço) e, depois dos 3 meses grátis, a farmácia paga ainda 10% do que vender pela app
11/11 15:18 (quem errou: claude-ai): pus os remédios com receita sem comissão e a receita desligada até para ele → regra: os 10% cobram-se em tudo (receita incluída), só depois dos 3 meses; para apresentar, fica tudo ligado só na conta de cliente dele
- 11/11 (claude-code): 10/11 18:40: abri a janela das travas e lancei uma sessão para a usar; a minha vez ficou à espera e a janela ficou aberta até 11/11 de manhã (~13 h); a sessão só arrancou no dia seguinte, com a tranca aberta em memória, e teve de ser parada → abrir a janela das travas só mesmo antes de a usar e fechá-la (RESTAURAR-M10, MD5 igual) no mesmo turno; nunca a deixar aberta à espera de CI, Danilo ou agentes; antes de acabar um turno confirmar as travas por MD5; arquivar as sessões lançadas numa janela depois de usadas
- [stated] 12/11 06:14 (Claude.ai, de /topics/erros-aprendidos-2.md): na revisão diária do WhatsApp dei-lhe um resumo curto ("Boom 662", "resolvido") sem explicar o que era cada caso; ele: "vai mais a fundo, explica direito" → regra: em cada caso dizer em português simples quem é (nome, nunca só o número), o que perguntou, o que o robô respondeu e o que falta; "662" é o número pessoal dele (931 992 662)
- [stated] 12/11 06:22 (Claude.ai, de /topics/erros-aprendidos-2.md): falei em "religar o envio automático" sem explicar o que era, e disse que o cliente ficava "a andar em círculos" por o robô o mandar para o WhatsApp 937 501 673 — errado: esse é o WhatsApp da Bora e é ele que lá responde à mão → regra: nunca usar nomes internos (envio automático, porta, tenant) sem dizer o que fazem; o robô mandar o cliente para o WhatsApp da Bora está certo


## Índice do livro (sem páginas pessoais)

- 00-LEIA-PRIMEIRO — Como usar esta memória
- adendo-1-final-app-2026-10-29 — Adendo 1 da missão final-app-2026-10-29
- adendo-12-robo-boom-revisao-2026-10-30 — ADENDO 12 (Claude.ai, 30/10 06:25) - robo da Boom, revisor diario do WhatsApp da loja e fotos do Emanuel
- adendo-13-ios-fotos-vps-2026-10-30 — ADENDO 13 (Claude.ai, 30/10 07:00) - teste do iPhone da publicacao 5, fotos do Emanuel, memoria do whatsapp-cerebro, cop
- adendo-3-final-app-2026-10-29 — Adendo 3 da missão final-app-2026-10-29 — robô de documentos
- adendo-5-final-app-2026-10-29 — Adendo 5 — decisão do Danilo sobre o plano melhor-que-Uber-Glovo (itens 4,5,6,7,8)
- adendo-6-publica-2026-10-29 — ADENDO 6 (Claude.ai, 20:25) - robo nao recebeu a mensagem das 19:41 + fotos Letra para o Storage
- adendo-7-retomar-missao-2026-10-29 — ADENDO 7 (Claude.ai, 21:30) - RETOMAR a missao publica-2026-10-29 depois de a sessao ter perdido a ligacao ao PC
- adendo-8-noite-automatica-2026-10-29 — ADENDO 8 (Claude.ai, 21:58) - noite automatica: no fim da missao da Bora, acordar a missao do Harness sem ninguem no PC
- adendo-8-nota-telemovel-2026-10-29 — Nota ao adendo 8: o Enter na sessao do Harness e dado pelo Danilo no telemovel
- adendo-9-checkin-escada-premios-2026-10-29 — ADENDO 9 (Danilo 22:20) - check-in diario: calendario de 30 dias e escada de premios "levanta ou continua" (um premio po
- adendo-harness-servidor-remote-control-2026-10-29 — ADENDO para a missao do Harness (sessao DeepSeek Harness installation): no fim, servidor de Remote Control para duas ses
- adendo-infra-2026-11-01 — Adendo à missão infra-claude-tudo-2026-11-01 (B10-B14: site /baixar, Meta ads, cartazes A3, grupos Facebook + Em Dia, st
- adendo-m10-radar-videos-2026-11-08 — ADENDO 1 à M10 (08/11 23:21) — radar de vídeos e varredura mundial, para a sessão m10 ler e executar
- adendo-vozes-omnivoice-2026-10-22 — Adendo de vozes: A/B do motor OmniVoice (k2-fsa) no filme Ep1
- analise-fiscal-bora-2026-11-03 — Análise fiscal do Bora (entregas e serviços, sem TVDE) + conselho Gemini/ChatGPT/DeepSeek — 03/11/2026
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
- comparativo-concorrencia-2026-11 — Bora contra Glovo, Uber Eats, Bolt Food e iFood (novembro 2026)
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
- digest-2026-10-30-adendo-13-ios — Missão publica 30/10 — adendo 13: iPhone relançado, cérebro do WhatsApp alinhado
- digest-2026-10-30-conta-vansh-jai — Contas de 30/10 — Vansh, Jai e Ricardo (juntar à memória)
- digest-2026-10-30-dsh-harness — Claude Code 30/10 — DeepSeek Harness (dsh) instalado com o mesmo livro do Claude Code
- digest-2026-10-30-gorjetas-claude-ai — Digest 30/10 — gorjetas: taxa da Stripe e gorjeta junto da compra (Claude.ai)
- digest-2026-10-30-gorjetas-taxa — Claude Code 30/10 — gorjetas com a taxa, robô da Boom e publicação 7
- digest-2026-10-30-jai-kalinga — Claude Code 30/10 — entrevista do Jai no canal Professor Kalinga no site do Jai
- digest-2026-10-30-meta-anuncios — Meta anúncios 30/10 (Claude Code, Opus) — 2 campanhas publicadas e desligadas à espera dos 25 €
- digest-2026-10-30-remote-control-e-dsh-fecho — Claude Code 30/10 — Remote Control caído desde 28/10 e fecho do dsh
- digest-2026-10-31-conta-vansh — Conta do Vansh — compra no Continente 31/10
- digest-2026-10-31-jai-sportsdunia — Digest 31/10/2026 — artigo da SportsDunia no site do Jai
- digest-2026-10-31-jai-sportsdunia-e-fatura-139 — Jai 31/10: SportsDunia, estilo das mensagens e fatura dos 139
- digest-2026-10-31-meta-anuncios-g4 — Meta anúncios 31/10 — criativos refeitos, juiz ≥ 9, 4 anúncios LIGADOS
- digest-2026-10-31-publicar-retoma — Claude Code 31/10 — publicar a retoma (base, alertas, envio)
- digest-2026-11-01-app-fechar — Digest 01-02/11/2026 — missão app-fechar (Casa, peso, convidado, online, limpeza, assistente, robô, revisão humana)
- digest-2026-11-01-assistente-cliente-claude — Digest 01/11 — Bora Assistente com Claude primeiro + 3 melhorias de 10/10; stories em breve
- digest-2026-11-01-conta-jai-186-pago — Conta do Jai — 186 € de 24/10 já pagos; semana de 26/10 = 28 € (juntar à memória)
- digest-2026-11-01-fechar-tudo-claude-ai — Digest 01/11 noite — Claude.ai fechou a lista de pendências com 9 agentes em paralelo + missão no PC
- digest-2026-11-01-fecho-pendentes — Digest 01/11 — fecho dos pendentes (peso ao quilo, robô v30, limpeza, porteiro) publicado nas 3
- digest-2026-11-01-infra-claude-tudo — Digest 01/11/2026: Claude sem ração em todos os robôs, Dipsy pelo porteiro, VPS arrumada, Bora Bastidores
- digest-2026-11-01-mercadona-reaberta — Digest 01/11/2026 — Mercadona reaberta só com beleza e higiene
- digest-2026-11-02-chaves-varredura — Digest 02/11 — varredura das chaves (Claude Code PC)
- digest-2026-11-02-stripe-empresa — Digest 02/11/2026 — missão stripe-empresa (duas contas Stripe)
- digest-2026-11-02-stripe-retoma — Stripe duas contas — retoma Opus 02/11 — resultado
- digest-2026-11-02-travadas-infra — Claude Code 02/11 — travadas da infra (site, gorjeta, artes, grupos, anuncios)
- digest-2026-11-02-zerar — Claude Code 02/11 — zerar: chave nova no servidor, série de limpeza devolve, peso no cartão pronto (desligado), arrumaçõ
- digest-2026-11-03-boom-continua — Digest 03/11 — Boom e Fuku continua (PC)
- digest-2026-11-03-boom-hamburguer-mes — Digest 03/11 — Boom hambúrguer do mês (retoma)
- digest-2026-11-03-fuku-anuncio — Digest 03/11 — anúncio do Fuku Sushi na Meta publicado
- digest-2026-11-04-checkin-desconto-mercadona — Digest 04/11 tarde — check-in desconto e aviso Mercadona
- digest-2026-11-04-checkin-escada-premios — Digest 04/11 — escada de prémios do check-in
- digest-2026-11-04-checkin-premios-fecho — Digest 04/11 — check-in prémios e Favor (fecho)
- digest-2026-11-04-fechar-bora-motorista — Claude Code 04/11 — Bora Motorista fechado nas apps, no painel e no site
- digest-2026-11-05-modo-automatico-seguro — Claude Code 05/11 — modo automático seguro (por ligar)
- digest-2026-11-05-robo-suporte — Digest 05/11 — robô do suporte inteligente
- digest-2026-11-08-m1 — Digest 08/11 — M1 dinheiro dos Favores, recibo, NIF, gorjeta e talões
- digest-2026-11-08-m10 — M10 08-09/11 — noite toda sem travas: Bloco 1 no ar, app publicada 2x nas 3, Bloco 2 e radar
- digest-2026-11-08-m2 — Missão m2 08/11 — A minha conta do estafeta, fila de espera, faixa e mira
- digest-2026-11-08-m3 — Digest 08/11 — m3: Dipsy com internet registada e pergunta antes de dinheiro
- digest-2026-11-08-m4 — Digest 08/11 — m4 Amigo Bora v1 + adendo suporte (não publicado)
- digest-2026-11-08-m6 — Digest 08/11 — M6 crescimento, Hermes, porteiro, redes, Jyosmi, restaurante do dia
- digest-2026-11-08-m7 — Digest 08/11/2026 — missão M7 (Stripe, parceiros, radar, leis)
- digest-2026-11-08-m8 — Digest M8 08/11 noite: 6 missoes juntas e testadas, nada publicado
- digest-2026-11-08-m9 — M9 08/11: Jai a fundo — anúncios parados pela verificação, radar com pitch e cobertura de fundo, Wikipédia preparada
- digest-2026-11-08-missao-domingo — Digest 08/11 — super-missão de domingo
- digest-2026-11-09-entrega-filme-dipsy — Digest 09/11 — entrega da missão do filme ao Dipsy
- digest-2026-11-09-m11 — M11 — Amigo com rosto, talões no Drive, pesquisa inteligente e Casa (09/11/2026)
- digest-2026-11-09-pendencias — Digest 09/11 — missão pendências (Claude Code)
- digest-2026-11-09-volta-deposito-kfc — Claude Code 09/11 — depósito Volta e robô do talão do KFC
- digest-2026-11-10-fechar-tudo — Digest fechar-tudo 10/11 (sessão do PC)
- digest-2026-11-10-fecho-contabilista — Digest 10/11/2026 — fecho ao contabilista com as regras do Hugo (Claude Code)
- digest-2026-11-10-pagar-na-loja — Digest 10/11/2026 — missão pagar-na-loja (estafeta paga a loja parceira na recolha)
- digest-2026-11-11-amigo-casa — Digest 11/11 — Amigo com a Casa e Manutenção (por publicar)
- digest-2026-11-11-editar-perfil — Digest 11/11 — Editar perfil do cliente
- digest-2026-11-11-farmacias — Digest 11/11 — farmácias da Sé e Teixeira (receita, lojas escondidas)
- digest-2026-11-11-fechar-tudo — Digest 11/11 — fechar-tudo (lote 2, Amigo, R7, sites, LRE, publicação 726/727)
- digest-2026-11-11-meta-grupos — Digest 11/11 — Meta, grupos, Casa, Amigo e "A Guarda toda numa app"
- digest-2026-11-11-propaganda-casa-amigo — Digest 11/11 - propaganda Casa e Amigo (blocos 0 e 1)
- dipsy-j1-em-dia-semana-2026-11-10 — Missão do Dipsy dipsy-j1-em-dia-semana-2026-11-10
- dipsy-j2-em-dia-calculadoras-2026-11-10 — Missão do Dipsy dipsy-j2-em-dia-calculadoras-2026-11-10
- dipsy-j3-animacao-estudio-2026-11-10 — Missão do Dipsy dipsy-j3-animacao-estudio-2026-11-10
- dipsy-j4-crm-whatsapp-2026-11-10 — Missão do Dipsy dipsy-j4-crm-whatsapp-2026-11-10
- dipsy-j4b-crm-instalar-2026-11-11 — Missão do Dipsy dipsy-j4b-crm-instalar-2026-11-11
- diretiva-plataformas-2024-2831 — Diretiva (UE) 2024/2831 trabalho em plataformas — o que obriga o Bora, estado em Portugal, o que está feito e checklist 
- dsh-como-usar — Como usar o Dipsy (dsh)
- dsh-como-usar-novidades-2026-10-31 — Dipsy: o que ficou novo a 31/10 (complemento da pagina dsh-como-usar)
- duvidas-dipsy-filme — Dúvidas do Dipsy na missão do filme (Ep1) — ele acrescenta no fim; o Claude.ai responde em respostas-claude-ai-filme
- em-dia-ios-copiar-pipeline-bora — Em Dia / iOS: nao escrever o CI do zero, copiar o da Bora que ja funciona
- em-dia-iphone-identificador — Em Dia / iPhone: identificadores da Apple (bundle id, app id, SKU)
- em-dia-play-classificacao-conteudo — Em Dia / Play: respostas da classificacao IARC e o que muda quando as assinaturas abrirem
- em-dia-site-bloqueios-apple — Em Dia / site: tres coisas no site que chumbam a revisao da Apple
- embeddings-supabase-2026-11-03 — Motor grátis de vetores com Gemini de reserva — 03-04/11 Claude Code
- emdia-grupos-facebook — Em Dia — publicações em grupos de Facebook
- engenharia-reversa — Engenharia reversa — método do Danilo para clonar o que já existe (pedido 17/10/2026)
- engenharia-reversa-achados-2026-10-17 — Engenharia reversa — achados da pesquisa mundial de 17/10/2026 (REA, filme, navegador)
- entrega-amigo-casa-2026-11-11 — Entrega para a Claude.ai: publicar o Amigo com a Casa e Manutenção (11/11)
- entrega-amigo-casa-2026-11-11-patch — Remendo do client-assistant (Amigo + Casa e Manutenção) 11/11 — git apply sobre origin/autonomous-night-2026-04-29 b8af9
- entrega-editar-perfil-2026-11-11 — Entrega: Editar perfil do cliente — migrações por aplicar e ordem de publicação
- erro-2026-11-02-whatsapp-conversa-eu — Erro 02/11: artes mandadas para a conversa "Eu" do WhatsApp pessoal
- erros-aprendidos — Erros aprendidos — o caderno de correções do Danilo (todos os agentes leem ao acordar e acrescentam quando ele corrige)
- estado-2026-09-13 — Estado do Bora a 13/09/2026 (auditoria da Claude.ai depois de 3-4 dias sem Claude)
- fecho-2026-10-17-cancelamento-tardio — Fecho 17/10 — cancelamento tardio TVDE: publicado nas 3 plataformas (estado final do prompt prompt-cancelamento-tardio-2
- fecho-outubro-2026 — Fecho de outubro/2026 (em nome individual) — por prestador, o que cada um faz, email corrigido
- habilidades-propostas — Habilidades propostas pelo vigia (dinheiro/publicacao) — a Claude.ai decide
- ideias-pendentes-decisao-danilo — Ideias grandes à espera da decisão do Danilo (29/10/2026)
- ideias-videos-danilo — Ideias tiradas dos vídeos que o Danilo manda
- jai-entrevista-kalinga-mensagem — Mensagem ao Jai — entrevista do Professor Kalinga já no site (30/10/2026)
- jai-sportsdunia-mensagem — Confirmação para o Jai — artigo da SportsDunia no site (31/10/2026)
- legal-gestao-algoritmica-prestadores — Como o Bora decide — informação sobre sistemas automáticos (Diretiva 2024/2831, art. 9.º-11.º) — texto para a app, v2026
- legal-politica-suspensao-revisao-humana — Política de suspensão e revisão humana (nenhuma suspensão automática; motivo+quem+data; revisão por pessoa em 7 dias) — 
- leis-bora — Leis do Bora — o que a lei diz e o que falta (08/11/2026)
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
- livro-areas-bora-todo-dia — Check-in diário e "Bora Todo Dia" do Bora App — tokens por dia, marcos com prémios de parceiros (10/15/30 dias) e a regr
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
- livro-areas-deposito-volta — Depósito Volta (0,10 € por lata/garrafa de plástico) no Bora — regra do Danilo para cobrar ao cliente e a missão de 09/1
- livro-areas-divulgacao-bora — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte2 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte3 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-divulgacao-bora-parte4 — Divulgação do Bora App ao público — site oficial (bora-site, agora um só, a crescer para várias páginas), vídeos de apre
- livro-areas-em-dia-app — Nova app do Danilo "Em Dia" (assistente do trabalhador independente a recibos verdes + carro + organizador entra/sai din
- livro-areas-empresa-agentes — Missão "empresa de agentes" (07/09) — o que o Danilo pediu depois do vídeo do Grok Bot (mais agentes, melhor que o vídeo
- livro-areas-encomendas-festa — Categoria nova "Encomendas para Festa" (bolos, salgados, doces por encomenda com data marcada) + abordagem à doceira da 
- livro-areas-encomendas-festa-parte2 — Categoria nova "Encomendas para Festa" (bolos, salgados, doces por encomenda com data marcada) + abordagem à doceira da 
- livro-areas-endereco-web-cliente — Campo de morada do cliente na WEB do [[bora-app]] — cliente presa sem conseguir escrever endereço (31/08), causa achada 
- livro-areas-entrada-login-bora — Portas de entrada do [[bora-app]] (cliente, estafeta, parceiro) — regras que o Danilo fixou e prompt de auditoria entreg
- livro-areas-entrega-longa-distancia — Decisão do Danilo (05/11/2026) sobre entregas a mais de ~10 km (caso Porto da Carne) e o escalão de km que ele propôs e 
- livro-areas-estudio-imagem — Plano do Danilo (06/11/2026) de melhorar o negócio de imagem/estúdio com as novidades de imagem do briefing diário — ret
- livro-areas-farmacias-guarda — Grupo de 2 farmácias da Guarda (contacto Rita Grilo) que quer entrar no Bora — condições que o Danilo mandou oferecer e 
- livro-areas-favores-paragem-casa — Regra do Danilo para Favores (errands) com "passar em casa primeiro" no bora-app — o que o estafeta tem de ver; ler ante
- livro-areas-fechar-pendencias-missao — Super-missão "fechar pendências" (20/10/2026) do bora-app — blocos 0,B,C,D,A1,A2,A3,E,H,I,J,G, o que já fechou e o promp
- livro-areas-fecho-semanal — Regras do Danilo para o acerto semanal do [[bora-app]] (recibos automáticos, comprovativo ao marcar pago, cobrança autom
- livro-areas-filme-animacao — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 1 de 4 — continua e
- livro-areas-filme-animacao-parte2 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 2 de 4)
- livro-areas-filme-animacao-parte3 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 3 de 4)
- livro-areas-filme-animacao-parte4 — Série cristã infantil "A Semente da Luz" — cânone, elenco, e estado da produção do Episódio 1 (parte 4 de 4)
- livro-areas-filme-animacao-v3 — Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz", prom
- livro-areas-filme-animacao-v3-parte2 — Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz" (part
- livro-areas-filme-animacao-v3-parte3 — Continuação de filme-animacao a partir da 3.ª reprovação (31/08) — estado da produção v3 do Ep1 "A Semente da Luz" (part
- livro-areas-ganhar-dinheiro-ia — Objetivo do Danilo de ganhar dinheiro com IA em modo automático (ele só comanda) — o que quer, o que escolheu e o que fi
- livro-areas-ganhos-prestador — Ganhos do prestador no [[bora-app]] — total do dia em qualquer ecrã e a fórmula do estafeta em loja não-parceira (fica c
- livro-areas-gibi-biblia-criancas — Animated Bible storytelling project for Danilo's daughters (characters Tuca and Lumi), pivoting to comic book (Gibi) for
- livro-areas-goola-acai — Goola Açaí (quiosque no La Vie Guarda) — parceiro fechado do Bora App; modelo de preço acordado, loja montada e categori
- livro-areas-gorjeta — Regras do Danilo para a gorjeta no Bora (entregas e TVDE): no carrinho vai junto do pagamento, paga depois desconta a ta
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
- livro-areas-hermes-agent-parte2 — Hermes Agent infrastructure — VPS, PC bridge, ferramentas reais, e cadeia de modelos (migrado para o plano Go em 2026-08
- livro-areas-historia-dinossauros-lucifer — História infantil nova (dinossauros + guerra no céu/queda de Lúcifer + criação/Adão e Eva) que o Danilo quer transformar
- livro-areas-home-cliente-faixas — Home do app cliente do Bora — faixas de propaganda clicáveis, mais pedidos e lupa que acha tudo (pedido do Danilo, 05/10
- livro-areas-jai-agarwal-site — Jai Agarwal's personal brand site (jaiagarwala.com) — multilingual EN/PT/HI/ES site with gallery, press wall, streaming 
- livro-areas-jai-google-presenca — Mensalidade fechada com o Jai (139€/mês) para gerir a presença dele na Google — termos acordados, o que está incluído e 
- livro-areas-jai-google-presenca-parte2 — Mensalidade fechada com o Jai (139€/mês) para gerir a presença dele na Google — termos acordados, o que está incluído e 
- livro-areas-jai-google-presenca-parte3 — Mensalidade fechada com o Jai (139€/mês) para gerir a presença dele na Google — termos acordados, o que está incluído e 
- livro-areas-lacunas-sistema — Estado das lacunas do loop autónomo — quase tudo fechado em 2026-08-01; ler antes de decidir a próxima ordem
- livro-areas-lancamento-ios — Lançamento do Bora no iPhone/App Store — decisão e autorização total do Danilo (07/09), o caminho escolhido (conta indiv
- livro-areas-lavagem-auto — Serviço próprio de lavagem de carros com recolha e entrega dentro do Bora App — modelo, serviços e preços que o Danilo d
- livro-areas-leonidas-chocolates — Loja de chocolates Leonidas (Guarda), indicada pelo Cauê do Goola — aberta no Bora a 01/10 como loja não-parceira (balcã
- livro-areas-limite-pagamento-dinheiro — Limite de €40 em pagamento a dinheiro no [[bora-app]] — onde vive mesmo (4 sítios hardcoded) e prompt entregue para o to
- livro-areas-limpeza-vertical — Bora App Limpeza (cleaning) vertical — Helpling-style booking and dispatch
- livro-areas-livro-comum — "Livro comum" — o Danilo quer que Claude.ai, Hermes/Emerson, Claude Code e ChatGPT saibam todos o mesmo (tudo sobre ele 
- livro-areas-lojas-takeaway-guarda — Restaurantes da Guarda (sushi, pizzarias, churrasqueira) não-parceiros de takeaway por telefone no Bora — escolhidos e e
- livro-areas-luan-pladur — Luan Almeida (pladur/obras, Guarda) — prospect que chegou pelo WhatsApp a 04/10; Danilo ofereceu site grátis e pensar nu
- livro-areas-marca-ja-esta — Nome novo da marca da app do Danilo ("Já Está", substitui "Bora") — ler antes de falar de nome, marca, logótipo, domínio
- livro-areas-marketing-parceiros — Propaganda do Bora com parceiros — recrutamento de parceiros e regra dos cartazes com QR para as lojas (Mister Navalha, 
- livro-areas-mercadona-reabrir-loja — Plano do Danilo de reabrir a loja Mercadona no Bora só com perfumaria/cosmética/higiene — o que ele mandou guardar e ond
- livro-areas-metodo-sites — Método obrigatório para construir QUALQUER site (referência → design system → prompt → build → prémio) + agente classifi
- livro-areas-mini-site-business — Parallel mini-site web-dev business for local clients using a cinematic HTML/Cloudflare Pages workflow
- livro-areas-missao-domingo-noite — Missão grande de domingo à noite (08/11/2026) para terminar o que falta no Bora — lista de pendências que o Danilo vai d
- livro-areas-missao-domingo-noite-parte2 — Missão grande de domingo à noite (08/11/2026) para terminar o que falta no Bora — lista de pendências que o Danilo vai d
- livro-areas-missao-domingo-noite-parte3 — Missão grande de domingo à noite (08/11/2026) para terminar o que falta no Bora — lista de pendências que o Danilo vai d
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
- livro-areas-play-store-release-parte2 — Bora App release pipeline nas 3 plataformas (Play Store/Android, iOS/App Store, web) — CI/CD, regras de paridade, histór
- livro-areas-por-do-sol — Pôr do Sol Kebab & Pizza House (Rua Formosa, Guarda) — loja NÃO-PARCEIRA no Bora, encomenda por takeaway; telefone, preç
- livro-areas-precos-catalogo-nao-parceiro — Regras que o Danilo fixou para o preço base dos produtos de lojas não-parceiras do [[bora-app]] (robot do talão + qual a
- livro-areas-produtos-peso-variavel — Regra do Danilo (26/10/2026) para produtos ao quilo nos mercados do [[bora-app]] — o estafeta troca o preço e o cliente 
- livro-areas-prospecao-sites-clubes — Campanha de venda de sites a clubes de futebol portugueses (a partir do caso Guarda FC) — o que o Danilo pediu, critério
- livro-areas-radar-ia — Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) 
- livro-areas-radar-ia-parte2 — Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) 
- livro-areas-radar-ia-parte3 — Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) 
- livro-areas-recibo-cliente-produto-falta — Regras que o Danilo fixou para mexer no conteúdo de um pedido já feito (produto em falta, acrescentar produto) e para o 
- livro-areas-refinador — Agente de refinamento (Refinador) que o Danilo pediu a 11/11/2026 — última revisão de conteúdos e código depois do Juiz,
- livro-areas-regras-lancamento-categorias — Regras fixas do Danilo para lançar QUALQUER categoria, loja ou serviço novo no Bora — ler ANTES de planear ou montar pro
- livro-areas-robo-suporte — Robô do suporte dentro da app Bora (support-chatbot) — o que o Danilo quer dele, caso da Jennifer (Boom! Burger) e missã
- livro-areas-sabores-de-casa — Sabores de Casa Açaí (mercado BR + açaí, Guarda) — parceiro no app + mini-site cinematográfico de presente (esquema Ouro
- livro-areas-semente-da-luz — "A Semente da Luz" — biblical animated children's series (Kaggle GPU, Wan 2.2 I2V, multi-agent quality system)
- livro-areas-sistema-sem-travas — Pedido do Danilo (15/10/2026) para o sistema ficar automático sem pedir permissão a cada passo — auditoria das trancas n
- livro-areas-stripe-connect — Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata 
- livro-areas-stripe-connect-parte2 — Stripe Connect Express no Bora (parte 2 de 3 — continua em livro-areas-stripe-connect-parte3)
- livro-areas-stripe-connect-parte3 — Stripe Connect Express no Bora (parte 3 de 3)
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
- livro-areas-whatsapp-loja — Regras fixas do Danilo para o atendimento automático do WhatsApp da loja — ler antes de mexer nesse atendimento (parte 1
- livro-areas-whatsapp-loja-parte2 — Regras fixas do Danilo para o atendimento automático do WhatsApp da loja — ler antes de mexer nesse atendimento (parte 2
- livro-claude-code-aprendeu — O que o Claude Code aprendeu sozinho (memória automática do PC), cópia
- livro-claude-md-detalhe — Detalhe dos CLAUDE.md (repo e global) antes do corte de 23/10/2026
- livro-faxina-2026-10-25 — Faxina do livro 2026-10-25 (proposta do escriba + revisão do critico; nada apagado)
- livro-faxina-2026-11-01 — Faxina do livro 2026-11-01 (proposta do escriba + revisão do critico; nada apagado)
- livro-faxina-2026-11-08 — Faxina do livro 2026-11-08 (proposta do escriba + revisão do critico; nada apagado)
- livro-hermes-aprendeu — O que o Hermes aprendeu sozinho (MEMORY.md + USER.md), cópia noturna
- livro-hermes-skills — Skills do Hermes (as que criou + lista das de fábrica), cópia noturna
- livro-hermes-soul-detalhe — Alma antiga do Hermes (SOUL.md de 611 linhas) antes do corte de 23/10/2026
- livro-porta-unica — Livro — porta única: como ligar qualquer IA ao livro (MCP do Córtex ou LIVRO.md com senha)
- livro-resumo — Livro do Bora — resumo para o ChatGPT (regras + erros + índice, sem pessoais), gerado
- livro-topics-communication — How Danilo communicates and the language conventions across his tools
- livro-topics-erros-aprendidos — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir (cheio: continua em e
- livro-topics-erros-aprendidos-2 — Continuação de erros-aprendidos (o 1.º ficheiro encheu) — erros que o Danilo corrigiu a partir de 12/11/2026; ler junto 
- livro-topics-erros-aprendidos-parte2 — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir (cheio: continua em e
- livro-topics-erros-aprendidos-parte3 — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir (cheio: continua em e
- livro-topics-erros-aprendidos-parte4 — Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir (cheio: continua em e
- livro-topics-erros-aprendidos-parte5 — Registo de erros que o Danilo já corrigiu (parte 5 — sem uso: o ficheiro agora tem 4 partes)
- livro-topics-prioridades — Como o Danilo decide prioridades no negócio — foco dos próximos meses e regras de desempate quando duas coisas competem 
- livro-topics-regras-motores-e-prompts — Regras do Danilo sobre que motor/ferramenta usar (Fable, Opus, ChatGPT, GLM, Gemini, OpenCode) e sessões no Chrome — ler
- lojas-takeaway-precos — Lojas de takeaway por telefone: Bora (não-parceiro) contra Glovo e Uber Eats, Guarda, 29/10/2026
- maiores-18-verificacao-idade — Maiores de 18 — tabaco e álcool com verificação de idade na entrega (aplicado 07/10/2026)
- mapa-sessoes-contas — Mapa de sessões e contas — que conta está em que sítio (provado no ecrã a 17/09/2026)
- mensagem-hugo-2026-11-01 — Mensagem ao Hugo (WhatsApp, grupo Contabilidade) — fecho de outubro e Stripe desde o início (CORRIGIDA 01/11 21:30)
- mensagem-hugo-pendente-2026-10-29 — Mensagem para o Hugo (grupo Contabilidade) preparada 29/10 17:40 — por enviar quando o Danilo disser
- mercadona-reabrir-loja — Mercadona Guarda — reabrir só com perfumaria/cosmética/higiene (preparado 14-15/10/2026)
- meta-anuncios-2026-10-30-textos — Textos finais dos 2 anúncios Meta de 30/10/2026 (Instala e pede + Check-in diário)
- meta-anuncios-2026-10-31-adendo-revisao — Adendo G-REVISÃO dos anúncios Meta (31/10 06:52) — correções do Danilo + juiz visual
- meta-anuncios-2026-10-31-criativos — Anúncios Meta 31/10 — criativos finais (juiz ≥ 9) e porque o anúncio antigo não deu pedidos
- missao-dipsy-filme-ep1-2026-11-09 — Missão do Dipsy: acabar o filme das meninas (Ep1 Haja Luz) perfeito, plano a plano, motores grátis (09/11/2026)
- missao-pendencias-2026-11-09 — Missão pendências 30 dias (09/11/2026)
- motor-claude-2026-10-31 — Motor Claude 31/10 - estado final (Bloco 2 da retoma-geral)
- motores-rotacao-2026-10-29 — Motores gratis em rotacao - medicoes e cadeias (29/10/2026)
- paridade-mundo-2026-10-29 — Paridade do mundo, segunda volta (Rappi, DoorDash, Zomato, Meituan) 29/10/2026
- paridade-mundo-e-lei-2026-10-17 — Bora vs Uber/Glovo/iFood/Bolt/Grab/Meituan + obrigações da lei em Portugal (pesquisa 17/10/2026)
- paridade-rea-2026-10-26 — Paridade REA 26/10 — Glovo, Uber Eats, iFood e Bora vistos de fora (resumo)
- paridade-rea-2026-10-26-plano — PLANO de melhorias do Bora (paridade REA 26/10) — à espera da revisão da Claude.ai
- paridade-uber-ifood-2026-10-13 — Paridade Bora vs Uber/Uber Eats/iFood + REA (vídeos de 13/10)
- pedido-claude-ai-farmacias-2026-11-11-servidor — Pedido do PC: publicar o servidor das farmácias (11/11)
- pendencias-2026-11-01 — Pendências dos últimos 30 dias (lista numerada dada ao Danilo a 01/11 ~19:35)
- perfil — Quem é o Danilo
- pesquisa-assistente-cliente-2026-10-07 — Pesquisa mundial para o assistente de compras IA do cliente (base da missão que vem depois do +18)
- pesquisa-checkin-2026-11-10 — Pesquisa do check-in diário — como fazem os melhores (10/11/2026)
- pesquisa-fatura-nif-2026-10-28 — Fatura com NIF, produto em falta e entrega grátis nos parceiros — pesquisa e decisões (28/10/2026)
- plano-14-dias-2 — Plano de 14 dias, parte 2 (09/11 a 22/11/2026)
- plano-14-dias-dia6-a-14 — Plano de 14 dias — do dia 6 ao dia 14 (29/10 a 06/11/2026)
- plano-melhor-que-uber-glovo-2026-10-29 — Plano "100% melhor que a Uber e a Glovo" — volta ao mundo 29/10/2026
- playbook-redes-emdia — Playbook das redes — Em Dia (28/09)
- prompt-amigo-casa-2026-11-11 — Prompt: o Amigo Bora tem de saber da Casa e Manutenção (11/11/2026)
- prompt-auditoria-3-plataformas-2026-10-06 — Prompt de missão: auditoria das 3 plataformas (06/10)
- prompt-boom-burger-2026-10-27 — PROMPT Boom! Burger — loja parceira + site premium (27/10/2026)
- prompt-boom-burger-2026-10-27-texto-completo — PROMPT Boom! Burger — texto completo (27/10/2026)
- prompt-boom-burger-adendo3-2026-10-27 — Prompt ADENDO 3 Boom! Burger (27/10 17:06) — consertar já o que ficou para trás
- prompt-boom-burger-adendo4-2026-10-28 — PROMPT Boom! Burger — adendo 4 (fatura com NIF + entrega grátis preparada), 28/10/2026
- prompt-boom-continua-2026-11-03 — Prompt continuação Boom (03/11 12:20) — R, D, G, M, H, I, J, T
- prompt-boom-hamburguer-mes-2026-11-02 — Prompt missão Boom hambúrguer do mês (02/11/2026)
- prompt-boom-hamburguer-mes-adendo1-2026-11-03 — Adendo 1 (03/11 07:50): carrinho esquecido, anúncio da Boom, autorização de promoções, números dos anúncios, próximo anú
- prompt-boom-hamburguer-mes-retoma-2026-11-03 — Retoma da missão Boom hambúrguer do mês (03/11/2026)
- prompt-cancelamento-tardio-2026-10-17 — Prompt: cancelamento tardio TVDE — app, painel e publicação nas 3 plataformas (17/10) — estado: a correr
- prompt-casa-manutencao-2026-10-30 — Prompt: missão Casa & Manutenção (categoria nova, decisões do Danilo 30/10/2026)
- prompt-connect-empresa-2026-11-04 — Prompt — Connect na Stripe da empresa e repasse automático às lojas (04/11/2026)
- prompt-conversas-ao-vivo-2026-11-12 — Missão conversas ao vivo dos robôs + robô esperto (12/11/2026)
- prompt-dipsy-melhor-2026-10-31 — Missão Dipsy "melhor que o Claude Code" (31/10/2026) — decisões do Danilo 06:31
- prompt-favor-diferenca-mbway-2026-11-03 — Prompt Favor com compra a mais: MB Way da diferença (03/11 13:35)
- prompt-fechar-tudo-2026-11-10 — Prompt da missão fechar-tudo 10/11/2026
- prompt-fecho-pendentes-2026-10-31 — Prompt "fecho-pendentes" (31/10 22:10) — peso ao quilo, suporte com Claude, 4 pagamentos, 3 commits antigos, limpeza 5 m
- prompt-final-app-2026-10-29 — Prompt missao final-app-2026-10-29
- prompt-fuku-anuncio-2026-11-03 — Prompt missão anúncio Fuku Sushi na Meta (03/11/2026 20:30)
- prompt-gorjetas-taxa-2026-10-30 — Prompt — gorjetas: taxa da Stripe na gorjeta paga depois e gorjeta do carrinho junto da compra (30/10/2026)
- prompt-jai-site-sportsdunia-2026-10-31 — Prompt jai-site SportsDunia 31/10
- prompt-maiores-18-2026-10-07 — Prompt: verificação de idade +18 (tabaco/álcool) — estado: PRONTO, NÃO LANÇADO (bloqueado: publica nas lojas, falta o Da
- prompt-manha-2026-11-02-ignorar-permissoes — Prompt para a sessão do PC em "Ignorar permissões" (02/11): o que o classificador travou na infra (B10-B13, B15)
- prompt-meta-anuncios-2026-10-30 — Prompt: 2 anúncios novos da Meta (instalar app + carrossel do check-in) e dados da empresa na Meta (30/10/2026)
- prompt-meta-grupos-casa-amigo-2026-11-11 — Prompt PC: anúncios Meta + grupos da Casa e do Amigo + renovar login do loop (11/11/2026 13:55)
- prompt-missao-da-noite-2026-10-07 — Prompt MISSÃO DA NOITE 07/10 (FABLE) — Bora Assistente (prioridade) + fechar +18 + Gmail caça-clientes + Apple Foco + GP
- prompt-missao-geral-2026-10-28 — PROMPT missão geral 28/10 (Divan + Boom + robô WhatsApp + cartazes + erros), parte 1/2
- prompt-missao-geral-2026-10-28-parte2 — PROMPT missão geral 28/10, parte 2/2 (blocos 1 a F, resumo)
- prompt-motor-claude-2026-10-31 — Prompt Motor Claude 31/10: robôs usam primeiro o crédito da API do Claude (plano Ultra) e depois a rotação grátis
- prompt-peso-variavel-2026-10-26 — PROMPT missão peso variável (26/10/2026) — para o Claude Code do PC
- prompt-propaganda-casa-amigo-2026-11-11 — Prompt: propaganda Casa e Manutenção + Amigo Bora, grupos e 2 anúncios Meta (11/11/2026)
- prompt-publica-e-fecha-2026-10-29 — Prompt: publicar hoje + arrumação + Bloco 11 + reembolsos (29/10 18:20)
- prompt-publica-e-fecha-2026-10-29-adendo-1 — Adendo 1 ao prompt publica-e-fecha (29/10 18:40): motores do robô em grátis com rotação
- prompt-publica-e-fecha-2026-10-29-adendo-2 — Adendo 2 ao prompt publica-e-fecha (29/10 18:55): motores grátis do OpenCode em rotação + link /pedir/boom do site
- prompt-publica-e-fecha-2026-10-29-adendo-3 — Adendo 3 (29/10 19:08): escolha do reembolso bem clara para o cliente na app
- prompt-publica-e-fecha-2026-10-29-adendo-4 — Adendo 4 (29/10 19:10): robô WhatsApp da Boom AO VIVO para o teste do Danilo, resposta na hora, super inteligente
- prompt-publica-e-fecha-2026-10-29-adendo-5 — Adendo 5 (29/10 19:18): revisão da conversa do dia — o que ainda faltava
- prompt-publicar-retoma-2026-10-31 — Prompt PUBLICAR da retoma (31/10 20:00) — itens 2, 3 e 4 autorizados pelo Danilo 19:53
- prompt-refinador-v1-2026-11-11 — Prompt: instalar o Refinador Bora (agente de refinamento, chefe de 7 lentes + cético) — 11/11/2026
- prompt-retoma-geral-2026-10-31 — PROMPT ÚNICO 31/10/2026 — parar, limpar a RAM e retomar todas as missões (Casa, motor Claude, Dipsy, lembretes)
- prompt-robo-suporte-inteligente-2026-11-05 — Missão robô do suporte super inteligente (05/11/2026)
- prompt-stripe-empresa-2026-11-01 — Prompt — ligar o app à Stripe da empresa (01/11/2026)
- prompt-talao-confirmar-loja-saldo-2026-10-28 — PROMPT 28/10 — Confirmar do talão, nome da loja, dinheiro a cobrar com saldo/tokens, reembolso no cancelamento (100% sal
- prompt-talao-confirmar-loja-saldo-2026-10-28-bloco-d — Adenda 18:30 ao prompt de 28/10 (talão Auchan/Divan): Bloco D novo — reembolso no cancelamento
- prompt-zerar-2026-11-02 — Prompt "zerar" (02/11 15:10): chaves antigas, série de limpeza devolve, peso cobra no cartão + arrumações
- proposta-m1-2026-11-08-edge-favor-cobrar-diferenca — M1 08/11 — Edge favor-cobrar-diferenca (index.ts, verify_jwt=false)
- proposta-m1-2026-11-08-edge-recibo-pedido-cliente — M1 08/11 — Edge nova recibo-pedido-cliente (index.ts, verify_jwt=false)
- proposta-m1-2026-11-08-edge-taloes-copia-diaria — M1 adendo 1 — Edge nova taloes-copia-diaria (index.ts; verify_jwt=false)
- proposta-m1-2026-11-08-edge-taloes-zip-mes — M1 adendo 1 — Edge nova taloes-zip-mes (index.ts; verify_jwt=false)
- proposta-m1-2026-11-08-edge-upload-receipt — M1 adendo 1 — Edge upload-receipt v2 (index.ts completo; nunca substitui, confirma no servidor)
- proposta-m1-2026-11-08-leia-primeiro — M1 08/11 — guia para aplicar e publicar (Claude.ai), com o adendo 1 dos talões
- proposta-m1-2026-11-08-patch-charge-tip — M1 08/11 — remendo charge-tip (taxa proporcional das gorjetas junto)
- proposta-m1-2026-11-08-patch-fecho-mensal — M1 adendo 1 — remendo fecho-mensal-contabilista (talões do mês no email)
- proposta-m1-2026-11-08-patch-notify-client — M1 08/11 — remendo notify-client (toque persistente)
- proposta-m1-2026-11-08-sql-01 — M1 08/11 — SQL 01 diferenças MB Way + entregue sem código
- proposta-m1-2026-11-08-sql-02 — M1 08/11 — SQL 02 aprovação com tecto + finalize remendado
- proposta-m1-2026-11-08-sql-03 — M1 08/11 — SQL 03 NIF ao estafeta + recibo por email
- proposta-m1-2026-11-08-sql-04 — M1 08/11 — SQL 04 gorjeta, ganho do dia, robô do talão
- proposta-m1-2026-11-08-sql-07 — M1 adendo 1 — SQL 07 talões guardados para sempre
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
- radar-2026-10-31 — Radar de vídeos 31/10/2026 — 40 revistos, 3 novos, 14 pendentes
- radar-2026-11-01 — Radar de vídeos 01/11/2026 — 40 revistos, 2 novos, 21 pendentes
- radar-2026-11-02 — Radar de vídeos 02/11/2026 — 40 revistos, 9 novos, 10 pendentes
- radar-2026-11-03 — Radar de vídeos 03/11/2026 — 20 revistos, 4 novos, 5 pendentes
- radar-2026-11-04 — Radar de vídeos 04/11/2026 — 40 revistos, 5 novos, 8 pendentes
- radar-2026-11-05 — Radar de vídeos 05/11/2026 — 25 revistos, 2 novos, 8 pendentes
- radar-2026-11-06 — Radar de vídeos 06/11/2026 — 40 revistos, 4 novos, 20 pendentes
- radar-2026-11-07 — Radar de vídeos 07/11/2026 — 40 revistos, 8 novos, 20 pendentes
- radar-2026-11-08 — Radar de vídeos 08/11/2026 — 40 revistos, 1 novo, 13 pendentes
- radar-2026-11-09 — Radar de vídeos 09/11/2026 — 40 revistos, 4 novos, 15 pendentes
- radar-2026-11-11 — Radar de vídeos 11/11/2026 — 40 revistos, 8 novos, 12 pendentes
- radar-2026-11-12 — Radar de vídeos 12/11/2026 — 40 revistos, 2 novos, 13 pendentes
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
- regra-gmail-links-embrulhados — REGRA para todos os agentes: emails com links NUNCA pelo conector Gmail (embrulha os links em google.com/url)
- regras-checkin-v2-2026-10-30 — Check-in v2 — regras decididas pelo Danilo a 30/10/2026 (escada grande única + escada pequena mensal, só com compra)
- regras-do-danilo — Regras do Danilo — versão 23/10/2026 (vale para Claude.ai, Hermes/Emerson, Claude Code, ChatGPT, OpenCode)
- regras-operacao-agentes — O que podes e o que não podes fazer no Bora em produção (ChatGPT, OpenCode, Hermes, Claude Code)
- regras-reels-radar-2026-10-04 — Regras de reels Em Dia e Bora (radar 04/10)
- relatorio-boom-burger-2026-10-27 — Boom! Burger — demonstração e consertos (27/10/2026, noite)
- relatorio-m1-dinheiro-favores-2026-11-08 — Relatório M1 08/11 (fiz isto, falta isto)
- relatorio-semanal-reels-2026-10-29 — Relatório semanal dos reels - 2026-10-29
- relatorio-semanal-reels-2026-11-02 — Relatório semanal dos reels - 2026-11-02
- relatorio-semanal-reels-2026-11-09 — Relatório semanal dos reels - 2026-11-09
- resposta-claude-ai-farmacias-2026-11-11-servidor — Resposta da Claude.ai ao pedido do PC: servidor das farmacias NAO aplicado (11/11 17:00)
- resposta-contabilista-iva-2026-10-28 — Resposta do Hugo (DC Consultores): IVA normal trimestral, programa de faturação, modelo aceite — 28/10/2026
- resposta-contabilista-iva-parte2-2026-10-28 — Hugo (15:54-15:55): faturas emitidas pelo escritório, não ficar no art. 53.º, IVA não mexe na margem — e as contas de ou
- respostas-claude-ai-filme — Respostas do Claude.ai às dúvidas do Dipsy no filme (Ep1)
- robo-documentos-2026-10-29 — Robô fiscal de documentos — relatório (adendo 3, 29/10/2026)
- seguranca-auditoria-2026-10-21 — Auditoria de seguranca do app (21/10, agente N4)
- sistema-motores-e-portas — Quem faz o quê — uma porta só (atualizado 17/09/2026)
- skills-indice — Índice das skills da pasta comum (Claude Code, Hermes, Claude.ai) — uma linha cada
- sql-modo-demo-2026-10-27 — SQL do modo demonstracao (Boom! Burger) para o Claude.ai aplicar
- stripe-declaracao-2026-11-01 — Stripe do Bora desde o início — extrato para o contabilista (01/11/2026)
- stripe-duas-contas — Duas contas Stripe — empresa e pessoal (01/11/2026)
- tokens-metade-do-saldo-2026-10-14 — Tokens do cliente: metade do saldo + desconto chega à cobrança (14/10/2026)
- whatsapp-a-discutir — WhatsApp — o que ainda está por discutir com o Danilo (esqueleto desligado)

