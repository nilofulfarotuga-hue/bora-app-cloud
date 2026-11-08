# Dossier legal do Bora — 08/11/2026

**Não sou advogado. Isto é um mapa para levar ao Hugo e à advogada, não um parecer.**

Feito a 08/11/2026 pela missão M7. Cada tema tem quatro partes: o que a lei diz, o que o Bora tem hoje, o que falta e o risco. Cada frase sobre a lei leva o link da fonte oficial (Diário da República, Portal das Finanças, EUR-Lex, INPI, Livro de Reclamações). O que não consegui confirmar está marcado **POR CONFIRMAR**. O que o Bora tem hoje foi visto no código (caminho:linha, na pasta do repositório) e na base de dados (só leitura, SELECT de 08/11/2026).

Três coisas que encontrei e que pesam mais do que o resto: a Bora tem 22 faturas suas por emitir desde 25/10; a app e o site ainda dizem que o Bora é do Danilo em nome individual (NIF pessoal), e não da empresa; e a marca "Já Está" ainda não está registada, está em prazo de oposição até 29/12/2026.

---

## 1. Plataforma intermediária, quem fatura e IVA

**O que a lei diz.** Quem vende ou presta um serviço tem de passar uma fatura por cada operação, mesmo que o cliente não peça ([Código do IVA, art. 29.º, n.º 1, alínea b)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva29.aspx)). O prazo é até ao 5.º dia útil, ou no próprio dia em que o cliente paga, quando o pagamento coincide com a entrega ([art. 36.º, n.º 1](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva36.aspx)). O dinheiro que a Bora recebe "em nome e por conta" do cliente, guardado em contas de terceiros, não entra no valor sobre o qual a Bora paga IVA ([art. 16.º, n.º 6, alínea c)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva16.aspx)). É isto que deixa a Bora faturar só a parte dela nos parceiros e nos mercados em que compra em nome do cliente. A fatura pode ser feita pelo próprio comprador ou por um terceiro, em nome de quem vende ([art. 29.º, n.º 14](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva29.aspx)): é a autofaturação. Mas só vale com duas condições: um acordo escrito feito antes, entre a Bora e cada estafeta, e a prova de que o estafeta viu e aceitou cada fatura ([art. 36.º, n.º 11](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva36.aspx)). Mesmo assim, o estafeta continua responsável pelo que a fatura diz ([DL 28/2019, art. 5.º, n.º 1](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Decreto_Lei_28_2019.pdf)). As plataformas digitais têm ainda de se registar nas Finanças e comunicar uma vez por ano o que pagaram a cada vendedor ou prestador (DAC7, [Lei 36/2023 e declaração Modelo 61](https://info.portaldasfinancas.gov.pt/pt/apoio_contribuinte/questoes_frequentes/Pages/faqs-00455.aspx)). E se um prestador receber da Bora mais de metade do que ganha no ano, e esse total passar 6 vezes o IAS, a Bora pode ter de pagar uma contribuição à Segurança Social como "entidade contratante" ([Código Contributivo, art. 140.º](https://diariodarepublica.pt/dr/legislacao-consolidada/lei/2009-34514575-114482070)). As taxas de 7% e 10% estão **POR CONFIRMAR** com o Hugo.

**O que o Bora tem hoje.** O modelo foi decidido a 03/11 (página `analise-fiscal-bora-2026-11-03` do livro). Nos restaurantes parceiros, a loja fatura o preço de balcão e a Bora fatura o resto. Nos mercados e Favores, com o NIF do cliente compra-se em nome do cliente; sem NIF é revenda com o NIF da Bora. Nas limpezas, a profissional fatura e a Bora fica com os 15%. A empresa está no IVA normal trimestral. A base já guarda as faturas que a Bora deve emitir (tabela `bora_invoices_pending`). No SELECT de 08/11 há 22 faturas "por lançar", que somam 107,91 €, de 25/10 a 08/11, e nenhuma tem número. No código não encontrei ligação a nenhum programa de faturação certificado; só o TVDE tem uma tabela de faturas com ATCUD (`tvde_invoices`). Os termos do estafeta, em vigor desde 01/11 (tabela `legal_terms_versions`), dizem que é **o próprio estafeta** que passa o recibo do mês à Bora (NIF 519686233) e depois carrega em "Já passei o recibo". Isto não é autofaturação. Mas o livro diz que a 07/10 se decidiu autofaturação.

**O que falta.** Emitir já as faturas atrasadas. Ligar a app a um programa certificado (ver tema 2). Decidir com o Hugo, de uma vez, se os estafetas passam o recibo eles mesmos (como dizem os termos de hoje) ou se é autofaturação. Se for autofaturação, falta o acordo escrito assinado por cada estafeta antes da primeira fatura. Falta também fazer o registo DAC7 e ver com o Hugo a contribuição de entidade contratante.

**Risco.** Alto. Faturas fora de prazo são uma infração fiscal e podem dar coima (os valores estão **POR CONFIRMAR** com o Hugo). Autofaturação sem acordo escrito não cumpre o art. 36.º, n.º 11.

## 2. Recibo ou fatura ao consumidor

**O que a lei diz.** A fatura simplificada pode ser usada na venda de bens por retalhistas a consumidores até 1.000 €, e nos outros casos até 100 € ([CIVA, art. 40.º, n.º 1](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva40.aspx)). O NIF do consumidor é opcional, mas tem de constar na fatura sempre que ele o peça ([art. 36.º, n.º 16](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva36.aspx)). Uma sociedade por quotas tem contabilidade organizada, e quem tem contabilidade organizada só pode faturar com programa certificado pela AT ([DL 28/2019, art. 4.º, n.º 1, alínea c)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Decreto_Lei_28_2019.pdf)). Desde 01/07/2025 pode também usar as aplicações de faturação da própria AT ([mesmo DL, art. 4.º-A](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Decreto_Lei_28_2019.pdf)). Isso serve para poucas faturas à mão, mas não para uma por pedido feita sozinha pela app. A lei proíbe entregar ao cliente, em vez da fatura, um documento de outro tipo para titular a venda ([CIVA, art. 29.º, n.º 19](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva29.aspx)). Qualquer documento que não seja fatura e que se mostre ao cliente tem de dizer "Este documento não serve de fatura" ([Despacho 8632/2014, ponto 1.2](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Despacho_n%C2%BA_8632_2014_03_07.pdf)).

**Resposta curta às perguntas.** Sim: a Bora precisa de programa certificado (ou da aplicação da AT) para faturar comissões, taxas de serviço e entregas. Não: um e-mail gerado pela app, fora de um programa certificado, não pode chamar-se "recibo" nem "fatura". Tem de se chamar, por exemplo, "Resumo do pedido", levar a frase "Este documento não serve de fatura" e mandar, junto ou por link, a fatura verdadeira feita no programa certificado.

**O que o Bora tem hoje.** O recibo do TVDE já diz que não é fatura (`supabase/functions/tvde-recibo-viagem/index.ts:9`, `lib/widgets/tvde/recibo_viagem_sheet.dart:14`). O NIF do cliente já se guarda por pedido (tabela `order_invoice_requests`). A regra que você ditou a 08/11, de mandar um recibo/fatura por e-mail em todo pedido, ainda não está feita: não encontrei nenhuma função que mande esse e-mail nos pedidos normais. A pesquisa de 28/10 do livro estimou o InvoiceXpress em 24 €/mês para 100 documentos, com ligação à app. A outra opção é o programa do Hugo.

**O que falta.** Escolher o programa certificado com o Hugo e ligá-lo à app. O e-mail ao cliente sai como "Resumo do pedido — este documento não serve de fatura", com a fatura certificada anexada.

**Risco.** Alto, se o e-mail sair como "recibo" antes de haver fatura certificada (art. 29.º, n.º 19).

## 3. Dados pessoais (RGPD), o assistente e as promoções

**O que a lei diz.** O [RGPD](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32016R0679) e a [Lei 58/2019](https://diariodarepublica.pt/dr/detalhe/lei/58-2019-123815982) obrigam a dizer ao cliente quem é o responsável pelos dados, para que servem, a quem se passam e por quanto tempo se guardam (RGPD, art. 13.º). Também é preciso avisar quando há criação de perfil. Dados de saúde, como alergias ou uma doença que obrigue a uma dieta, só se tratam com consentimento explícito (art. 9.º). As decisões só automáticas com efeitos importantes têm regras próprias (art. 22.º). Mas o assistente só sugere carrinhos e não decide nada sobre a pessoa, por isso o art. 22.º em princípio não se aplica (**POR CONFIRMAR** com a advogada). O assistente tem de dizer claramente que é uma inteligência artificial ([Regulamento IA, art. 50.º, n.º 1](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024R1689)). O texto publicado diz que esta regra se aplica desde 02/08/2026 (art. 113.º). Fica **POR CONFIRMAR** se o pacote europeu "Omnibus digital" mudou essa data. O marketing direto por e-mail, SMS e "outros tipos de aplicações similares" precisa de consentimento prévio e expresso. A exceção é para clientes, sobre produtos parecidos aos que já compraram, e só se puderem recusar de forma fácil e grátis ([Lei 41/2004, art. 13.º-A, na redação da Lei 46/2012](https://files.dre.pt/1s/2012/08/16700/0481304826.pdf)). A CNPD explica que "expresso" quer dizer um gesto ativo da pessoa ([Diretriz 2022/1](https://www.cnpd.pt/umbraco/surface/cnpdDecision/download/121958)). Fica **POR CONFIRMAR** se houve alteração posterior ao art. 13.º-A.

**O que o Bora tem hoje.** O interruptor "Novidades e promoções" começa desligado (`lib/screens/profile_screen.dart:79` e `:1047-1059`). A pergunta aparece na home (`lib/widgets/pergunta_promocoes.dart:53`, `lib/screens/client_home_screen.dart:101`). O envio em massa filtra quem aceitou (`supabase/functions/execute-broadcast`). Na base, 22 de 251 utilizadores aceitaram e 55 responderam. O cliente vê e apaga a memória do assistente (`lib/screens/client/assistant/assistant_memory_screen.dart:1-3`, `:107`, `:226`). No código o assistente chama-se "Bora Assistente" e não encontrei "Amigo Bora". A saudação é só "Olá! Sou o Bora Assistente." (`supabase/functions/client-assistant/index.ts:142`). A memória guarda, entre outras coisas, "restricao_alimentar" (`supabase/migrations/20261007220000_bora_assistente.sql:175`). As conversas passam pelos motores Gemini e Claude (`client-assistant/index.ts:2-11`). A política de privacidade do site ([boraguarda.com/privacidade](https://boraguarda.com/privacidade), atualizada a 07/09/2026) está em nome pessoal, com o NIF pessoal, e não fala do assistente.

**O que falta.** Mudar a saudação para algo como "Sou o assistente automático da Bora (inteligência artificial)". Pedir consentimento explícito antes de guardar alergias ou dietas. Reescrever a política de privacidade em nome da empresa, com o assistente, a memória, os motores usados e onde ficam os dados. Confirmar que o Gemini e o Claude estão em versões pagas que não treinam com os dados dos clientes (**POR CONFIRMAR**). A Receita do Dia vai também a quem "nunca mexeu" e tem o check-in ativo, mesmo sem ter aceite promoções (`supabase/migrations/20261029152032_receita_do_dia_alvo_alargado_2026_10_29.sql:10-13`). Se for promoção, deve ir só a quem aceitou. A função `push-clientes-alvo` não confere o consentimento (`supabase/functions/push-clientes-alvo/index.ts:1-9`), por isso só deve ser usada para avisos de serviço.

**Risco.** Médio. As coimas do RGPD são altas, mas para uma empresa pequena o risco real é uma queixa de um cliente à CNPD.

## 4. Trabalho dos estafetas

**O que a lei diz.** Desde 2023 o Código do Trabalho presume que existe contrato de trabalho com uma plataforma digital quando se verificam "algumas" destas situações ([art. 12.º-A, Lei 13/2023](https://diariodarepublica.pt/dr/detalhe/lei/13-2023-211340863); [texto publicado](https://files.dre.pt/1s/2023/04/06600/0000200085.pdf)):
- a) a plataforma fixa o pagamento ou põe limites mínimos e máximos;
- b) dá ordens sobre a apresentação ou a conduta do prestador;
- c) controla o trabalho, incluindo em tempo real, ou verifica a qualidade por meios eletrónicos ou por algoritmo;
- d) limita a liberdade de escolher horário, ausências, aceitar ou recusar tarefas, usar substitutos ou trabalhar para outros, por exemplo com castigos;
- e) exerce poder disciplinar, incluindo desativar a conta;
- f) os equipamentos são da plataforma.

A plataforma só afasta a presunção se provar que o prestador trabalha com autonomia efetiva (n.º 4). A [Diretiva (UE) 2024/2831](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024L2831) tem de ser transposta até **02/12/2026** (art. 29.º). Pede o seguinte: proibição de tratar dados emocionais e conversas privadas (art. 7.º); informação escrita sobre os sistemas automáticos (art. 9.º); explicação e uma pessoa de contacto para qualquer decisão automática; motivo escrito em suspensões e encerramentos; e resposta a um pedido de revisão em duas semanas (art. 11.º). Não encontrei a lei portuguesa de transposição publicada. A proposta "Trabalho XXI" está **POR CONFIRMAR**.

**O que o Bora tem hoje.** Já estão escritos o documento "Como o Bora decide" (`docs/legal/gestao-algoritmica-prestadores.md`, ecrã `lib/screens/prestador/como_o_bora_decide_screen.dart`) e a política de suspensão com revisão humana em 7 dias (`docs/legal/politica-suspensao-revisao-humana.md`). Recusar uma oferta não tem castigo, não há horário nem exclusividade, e suspender ou fechar uma conta é sempre decisão de uma pessoa. Mas há dois sinais da lista que existem por natureza do negócio. O primeiro: a Bora fixa o pagamento por entrega (3,80 € + 0,20 €/km), que é a alínea a). O segundo: o GPS em tempo real enquanto está online e as notas dos clientes que geram avisos à equipa, que é a alínea c). Os termos do estafeta de 01/11 dizem "sem contrato de trabalho" e "independente".

**O que a Bora deve evitar.** Turnos ou horas obrigatórias. Baixar alguém na fila por recusar. Exclusividade ou proibir trabalhar para a Glovo ou a Uber. Uniforme ou mochila obrigatória (**POR CONFIRMAR** se hoje se exige). Bloqueios automáticos por notas. Mínimos de entregas.

**O que a Bora pode fazer.** Preço por entrega publicado antes de aceitar. Liberdade total de recusar e de desligar. Trabalhar noutras apps. Veículo próprio. Revisão humana de tudo o que for castigo.

**O que falta.** Guardar provas de autonomia (recusas sem efeito, estafetas que trabalham noutras apps, ninguém obrigado a horários). Entregar o documento "Como o Bora decide" a cada prestador e registar a entrega. Rever com a advogada se o preço fixo e as notas chegam para ativar a presunção.

**Risco.** Médio a alto. Com pelo menos as alíneas a) e c) presentes, um tribunal ou a ACT pode presumir contrato de trabalho, e aí a prova da autonomia cabe à Bora.

## 5. Direitos do consumidor

**O que a lei diz.** Livro de Reclamações: todos os fornecedores têm de ter o formato eletrónico. Quem tem site tem de mostrar o acesso à plataforma "em local visível e de forma destacada", e a resposta à reclamação tem de sair em 15 dias úteis ([DL 156/2005, art. 5.º-B, na redação do DL 74/2017](https://files.dre.pt/1s/2017/06/11800/0314103157.pdf); [versão consolidada](https://diariodarepublica.pt/dr/legislacao-consolidada/decreto-lei/2005-34431675); [perguntas frequentes oficiais](https://www.livroreclamacoes.pt/Inicio/PerguntasFrequentes)). Litígios: a empresa tem de informar as entidades de resolução alternativa de litígios a que está vinculada e o site delas ([Lei 144/2015, art. 18.º, na redação do DL 102/2017](https://files.diariodarepublica.pt/1s/2017/08/16200/0497404978.pdf); [lei](https://diariodarepublica.pt/dr/detalhe/lei/144-2015-70215248)). A plataforma europeia de litígios em linha (ODR) foi fechada a 20/07/2025 ([Regulamento (UE) 2024/3228, art. 1.º e 2.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024R3228)). Compras à distância: antes de pagar, o cliente tem de saber quem é o fornecedor, incluindo a denominação social, a morada, o telefone e o e-mail ([DL 24/2014, art. 4.º, n.º 1, alínea a), republicado pela Lei 10/2023](https://files.dre.pt/1s/2023/03/04500/0001100039.pdf)). Num mercado em linha também tem de saber como se ordenam os resultados e se quem vende é profissional (art. 4.º-A). O direito de livre resolução de 14 dias tem exceções: bens que se estragam ou ficam rapidamente fora de prazo (art. 17.º, n.º 1, alínea d)); restauração e transporte de bens com data marcada (alínea k)); e serviços já prestados por inteiro, com pedido expresso do cliente (alínea a) e art. 15.º). Preços: quando se anuncia uma redução, tem de se mostrar o preço mais baixo dos 30 dias anteriores ([DL 109-G/2021, que alterou o DL 138/90 e o DL 70/2007](https://files.dre.pt/1s/2021/12/23801/0000200052.pdf)).

**O que o Bora tem hoje.** A app tem o link do Livro de Reclamações, os centros de arbitragem e o aviso da Lei 144/2015 (`lib/config/legal_identity.dart:31-55`). Mas está só em Perfil > "Sobre / Informação legal" (`lib/screens/profile_screen.dart:1060-1070`, `lib/screens/legal_info_screen.dart:185-211`), e no ecrã de queixas do TVDE. O aviso de livre resolução no pagamento já trata das exceções (`lib/widgets/checkout_legal_notice.dart:33` e `:36`). O preço mais baixo dos 30 dias nas promoções já está feito (`lib/models/promocao.dart:33`, `:161-171`). O botão de denunciar conteúdo existe (`lib/widgets/bora_denunciar.dart:20-48`).

Os problemas encontrados:
- A página inicial de [boraguarda.com](https://boraguarda.com/) não tem o link do Livro de Reclamações (verificado a 08/11).
- A identidade do fornecedor na app é a pessoal: "Danilo Fulfaro da Silva, empresário em nome individual", NIF pessoal (`lib/config/legal_identity.dart:17-20`, mostrada em `lib/screens/legal_info_screen.dart:90-108`). O mesmo acontece em `docs/legal/informacao-legal.html` e nos [termos](https://boraguarda.com/termos) e na [privacidade](https://boraguarda.com/privacidade) do site, de 07/09/2026.
- Na base, `platform_settings` tem `plataforma_denominacao` e `plataforma_nif` vazios.
- A app ainda tem o link da plataforma ODR, que já fechou (`lib/config/legal_identity.dart:49-51`).
- Não encontrei explicação de como se ordenam as lojas e os produtos (DL 24/2014, art. 4.º-A).

**O que falta.** Pôr a empresa (Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233, sede) em todo o lado. Pôr o Livro de Reclamações em destaque na página inicial do site e num sítio fácil da app, como a ajuda ou o rodapé do ecrã principal. Confirmar que a empresa está registada como operador na [plataforma do Livro de Reclamações](https://www.livroreclamacoes.pt/Operador/registooperadores) (**POR CONFIRMAR**). Tirar o link ODR. Escrever um texto curto sobre como se ordenam os resultados. Confirmar qual centro de arbitragem é competente para a Guarda: o de Coimbra anunciou em 25/07/2024 que alargou a sua área ([centrodearbitragemdecoimbra.com](https://www.centrodearbitragemdecoimbra.com/)), e se não abranger a Guarda é o [CNIACC](https://www.cniacc.pt/pt/) (**POR CONFIRMAR**). Nas limpezas marcadas para os 14 dias seguintes, ver com a advogada se o aviso chega ou se é preciso uma caixa a marcar com o pedido expresso (art. 15.º).

**Risco.** Médio. O mais visível é o nome errado do fornecedor e a falta do Livro no site, que se vêem numa inspeção de cinco minutos.

## 6. Comida vendida à distância: alergénios e álcool

**O que a lei diz.** Nos alimentos pré-embalados vendidos à distância, a informação obrigatória tem de estar disponível antes de a compra terminar. Tem de estar na própria app ou noutro meio "claramente identificado", sem custo para o cliente ([Regulamento (UE) 1169/2011, art. 14.º, n.º 1](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32011R1169)). Nos pratos não pré-embalados, como os dos restaurantes, os alergénios são sempre obrigatórios (art. 44.º, n.º 1, alínea a)) e seguem a mesma regra do "antes de comprar" (art. 14.º, n.º 2). Portugal tem regras próprias sobre como se dá essa informação nos não pré-embalados (DL 26/2016); a forma exata está **POR CONFIRMAR** no texto do DR. Álcool: é proibido vender ou disponibilizar bebidas alcoólicas a menores de 18 anos, e em caso de dúvida pede-se documento ([DL 50/2013, alterado pelo DL 106/2015](https://diariodarepublica.pt/dre/detalhe/decreto-lei/50-2013-260432); [ficha oficial de fiscalização](https://www2.gov.pt/fichas-tecnicas-fiscalizacao/alcool)). Fica **POR CONFIRMAR** com a advogada se a regra, escrita para locais públicos e abertos ao público, se aplica à entrega em casa. Pedir o documento na entrega é de qualquer forma o mais seguro.

**O que o Bora tem hoje.** A ficha do produto mostra os alergénios quando estão preenchidos. Quando não estão, diz "Consulte o estabelecimento para informações sobre alergénios" (`lib/screens/product_detail_screen.dart:379-419`). Na base, só 1 dos 250 produtos dos parceiros tem alergénios preenchidos (1 em 58.738 no total). Os termos do parceiro (28/10) põem os alergénios como responsabilidade da loja. Existe ecrã no painel para isto (`lib/screens/admin/admin_alergenos_screen.dart`). No álcool está bem: há 5.009 produtos marcados "maior de 18", a ficha mostra o aviso e o estafeta pede documento (`lib/screens/product_detail_screen.dart:373-378`). Procurei nomes de bebidas sem a marca e só apareceram falsos positivos (chouriço de vinho, cálices).

**O que falta.** Pedir a cada loja parceira a lista dos 14 alergénios por prato e preenchê-la. Até lá, trocar o "Consulte o estabelecimento" por um contacto concreto e grátis antes de pagar (telefone da loja ou da Bora). Fica **POR CONFIRMAR** com a advogada se isso chega. Outra pergunta para a advogada: no modo "revenda" (cliente sem NIF), a Bora passa a ser ela a vendedora dos produtos do supermercado. Se for assim, as obrigações de informação dos pré-embalados passam a ser dela, e o catálogo dos mercados não tem essa informação.

**Risco.** Médio a alto nos restaurantes, porque um caso de alergia grave é o pior cenário possível. Baixo no álcool.

## 7. Lojas parceiras (P2B) e serviços digitais (DSA)

**O que a lei diz.** O [Regulamento P2B (UE) 2019/1150](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32019R1150) pede que as cláusulas para as lojas sejam simples, fáceis de encontrar e com os motivos de suspensão (art. 3.º). Mudanças nos termos avisam-se com 15 dias, também pelo art. 3.º. A suspensão leva motivo escrito, e o fim da parceria avisa-se com 30 dias e por escrito (art. 4.º). É preciso explicar o que decide a ordem das lojas (art. 5.º). As pequenas empresas não são obrigadas a ter sistema interno de reclamações nem mediadores (art. 11.º, n.º 5, e art. 12.º). O [DSA, Regulamento (UE) 2022/2065](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32022R2065), dispensa as micro e pequenas empresas de várias coisas. Ficam de fora: as regras extra das plataformas (secção 3, art. 19.º), a rastreabilidade dos comerciantes (secção 4, art. 29.º) e os relatórios de transparência (art. 15.º, n.º 2). Continua a aplicar-se: ponto de contacto para utilizadores e autoridades (art. 11.º e 12.º), regras de moderação nos termos (art. 14.º), botão para denunciar conteúdo ilegal (art. 16.º) e motivo escrito quando se restringe um utilizador (art. 17.º).

**O que o Bora tem hoje.** Os termos do parceiro (versão 2026-10-28) já têm o NIPC, são iguais para todos, dão aviso de 15 dias em mudanças e de 30 dias com razões por escrito no fim da parceria, e não têm fidelização. O botão de denunciar existe (`lib/widgets/bora_denunciar.dart`). A política de suspensão cobre também as lojas (`docs/legal/politica-suspensao-revisao-humana.md`, ponto 8).

**O que falta.** Uma frase sobre como se ordenam as lojas na app (P2B, art. 5.º). Uma lista curta dos motivos que podem levar a desligar uma loja (art. 3.º, n.º 1, alínea c)). Uma frase nos termos do cliente sobre como se trata uma denúncia (DSA, art. 14.º e 16.º).

**Risco.** Baixo.

## 8. TVDE (Bora Motorista, fechado ao público desde 04/11)

**O que a lei diz.** O regime é a [Lei 45/2018](https://diariodarepublica.pt/dr/detalhe/lei/45-2018-115991688), alterada e republicada pela [Lei 59/2026](https://diariodarepublica.pt/dr/detalhe/lei/59-2026-1161801432) ([texto publicado](https://files.diariodarepublica.pt/1s/2026/08/16400/0000300044.pdf)), em vigor desde 01/09/2026. O estudo de 11/10 (página `digest-2026-10-11-legalizacao-tvde-marca`) leu a versão anterior. Os números dos artigos citados nesse estudo estão **POR CONFIRMAR** no texto republicado.

**O que ficou em aberto.**
- Não há licença do IMT de operador de plataforma. No livro estão 167 corridas feitas sem licença até 11/10.
- O pedido de licença precisa de marca registada, e a "Já Está" ainda não está (ver tema 9).
- O estudo de 11/10 diz que no TVDE só se pode pagar eletronicamente, e a app aceitava dinheiro (**POR CONFIRMAR** no texto novo).
- Na base, `plataforma_denominacao`, `plataforma_nif`, `plataforma_sede` e `plataforma_licenca_imt` estão vazios.
- O TVDE continua na Stripe pessoal (`lib/screens/admin/admin_stripe_contas_screen.dart:127`).

**O que falta.** Manter fechado até haver licença em nome da empresa. Pedir à advogada que avalie o risco das corridas já feitas. As coimas de 5.000 € a 44.000 € citadas a 11/10 estão **POR CONFIRMAR** no texto novo.

**Risco.** Baixo enquanto estiver fechado. Alto se reabrir sem licença.

## 9. Marca "Já Está"

**O que vi no INPI a 08/11/2026** ([pesquisa de marcas do INPI](https://servicosonline.inpi.justica.gov.pt/pesquisas/main/marcas.jsp?lang=PT), processo 778820; [Boletim da Propriedade Industrial](https://inpi.justica.gov.pt/Boletim-da-Propriedade-Industrial)): marca nacional n.º 778820, "JÁ ESTÁ", sinal misto, requerente DANILO FULFARO DA SILVA - UNIPESSOAL LDA, classes 39 e 42. O pedido foi feito a 12/10/2026 e publicado no Boletim a 29/10/2026. A fase atual é "pedido – aguarda oposição", até **29/12/2026**. Ou seja: **ainda não está registada**. O `CLAUDE.md` do repositório diz "registada no INPI", o que está errado: é um pedido em curso.

Na mesma pesquisa aparecem marcas parecidas em vigor. A "JÁ ESTÁ" n.º 380401, 380402 e 380406, de 2004, abrange várias classes, incluindo a 9 (aplicações). Há também a "JÁ ESTÁ!" n.º 746988, de 2025, na classe 41, e frases com "e já está" nas classes 35 e 36. O estudo de 11/10 do livro também encontrou "Bora Mobility" (marca da UE, classes 9, 39, 42 e 45), que é um risco para o nome "Bora". Não consegui reconfirmar este ponto porque o TMview bloqueou o acesso (**POR CONFIRMAR**).

**O que falta.** Corrigir no livro e no `CLAUDE.md` que a marca é um pedido e não um registo. Vigiar se aparece oposição até 29/12. Ver com a advogada ou com um agente oficial da propriedade industrial se vale a pena proteger as classes 9 e 35.

**Risco.** Médio, até 29/12.

## 10. Os dois resumos do ChatGPT

**"O DL 212/2026 baixou o IRS de 2026": CONFIRMADO.** O Decreto-Lei n.º 212/2026 saiu no Diário da República n.º 214/2026, 1.ª série, a 04/11/2026 ([texto no Portal das Finanças](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/decreto-lei-212-2026.pdf)). Altera o art. 68.º do Código do IRS e baixa as taxas dos primeiros seis escalões. Aplica-se aos rendimentos de 2026, com efeitos desde 1 de janeiro, e entrou em vigor no dia seguinte à publicação. É IRS pessoal (seu), não da empresa. A tabela nova de taxas por escalão não a copiei (**POR CONFIRMAR** no DR). O passo certo é pedir ao Hugo a simulação do seu IRS de 2026.

**"IRC de 18% em 2027 só se o Orçamento passar a 24/11": ERRADO na condição.** A taxa de 18% para 2027 já está na lei: Lei 64/2025, de 7 de novembro, norma transitória do art. 3.º, n.º 3 ([Código do IRC, art. 87.º, no Portal das Finanças](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/CIRC_2R/Pages/irc87.aspx)). As taxas são 19% em 2026, 18% em 2027 e 17% a partir de 2028. Para as PME, os primeiros 50.000 € de lucro pagam 15% desde 2026 (art. 87.º, n.º 2). Não depende do Orçamento de 2027, que o Governo apresentou a 08/10/2026 ([portugal.gov.pt](https://portugal.gov.pt/pt/gc25/comunicacao/noticias/oe-2027-um-portugal-mais-preparado-com-mais-rendimento-e-investimento)). A data de 24/11 para a votação final não a encontrei em fonte oficial (**POR CONFIRMAR**). A taxa do interior (12,5% na Guarda, EBF art. 41.º-B) está **POR CONFIRMAR** com o Hugo.

---

## 10 ações por prioridade

1. **Faturação da Bora a funcionar.**
   - O quê: emitir já as 22 faturas em atraso (107,91 €, desde 25/10), escolher o programa certificado (o do Hugo ou o InvoiceXpress) e ligá-lo à app, uma fatura por pedido. O e-mail ao cliente sai como "Resumo do pedido — Este documento não serve de fatura", com a fatura certificada anexada.
   - Quem: Hugo (programa e faturas atrasadas), app (ligação e e-mail).
   - Porquê: [CIVA art. 29.º, n.º 1, alínea b), e n.º 19](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva29.aspx); [art. 36.º, n.º 1](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva36.aspx); [DL 28/2019, art. 4.º](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Decreto_Lei_28_2019.pdf); [Despacho 8632/2014, ponto 1.2](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Despacho_n%C2%BA_8632_2014_03_07.pdf).
   - Urgência: **esta semana.**

2. **A empresa em todo o lado.**
   - O quê: trocar "Danilo Fulfaro da Silva, empresário em nome individual, NIF pessoal" por "Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233" e a sede. Isto vale para a app (`lib/config/legal_identity.dart:17-20`), para o `docs/legal/informacao-legal.html`, para os termos e a privacidade do site, e para os campos vazios de `platform_settings`.
   - Quem: app; você aprova o texto; a advogada revê os termos.
   - Porquê: [DL 24/2014, art. 4.º, n.º 1, alínea a)](https://files.dre.pt/1s/2023/03/04500/0001100039.pdf); [RGPD, art. 13.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32016R0679).
   - Urgência: **esta semana.**

3. **Livro de Reclamações em destaque.**
   - O quê: link na página inicial de boraguarda.com e num sítio fácil da app; confirmar o registo da empresa na plataforma; responder às reclamações em 15 dias úteis; tirar o link da plataforma ODR, que já fechou (`lib/config/legal_identity.dart:49-51`).
   - Quem: app (site e app); você confirma o registo, com a página aberta.
   - Porquê: [DL 156/2005, art. 5.º-B](https://files.dre.pt/1s/2017/06/11800/0314103157.pdf); [Regulamento (UE) 2024/3228](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024R3228).
   - Urgência: **esta semana.**

4. **Recibos dos estafetas: um modelo só.**
   - O quê: decidir se o estafeta passa ele o recibo à Bora (como dizem os termos de 01/11) ou se é autofaturação (decisão do livro de 07/10). Se for autofaturação, cada estafeta assina o acordo escrito antes de 01/12, que é quando chegam os recibos de novembro.
   - Quem: Hugo decide; a advogada escreve o acordo; a app recolhe a assinatura.
   - Porquê: [CIVA art. 29.º, n.º 14](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva29.aspx) e [art. 36.º, n.º 11](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva36.aspx).
   - Urgência: **este mês.**

5. **Termos do cliente iguais ao modelo fiscal.**
   - O quê: os termos de 01/11 dizem que nos não-parceiros "os produtos são comprados em seu nome" e que sem NIF a fatura sai "consumidor final". A decisão de 03/11 é outra: com NIF, compra em nome do cliente; sem NIF, revenda pela Bora; nunca "consumidor final" nas compras.
   - Quem: Hugo confirma o modelo; a advogada escreve; a app publica a versão nova.
   - Porquê: [CIVA art. 16.º, n.º 6, alínea c)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva16.aspx); [DL 24/2014, art. 4.º](https://files.dre.pt/1s/2023/03/04500/0001100039.pdf).
   - Urgência: **este mês.**

6. **Estafetas e o prazo de 02/12.**
   - O quê: entregar a cada prestador o documento "Como o Bora decide" e registar a entrega; guardar provas de autonomia (recusas sem efeito, sem horário, trabalho noutras apps); confirmar que nada exige farda, mochila ou mínimos; rever com a advogada o efeito do preço fixo e das notas.
   - Quem: app (entrega e registo); advogada.
   - Porquê: [Código do Trabalho, art. 12.º-A](https://diariodarepublica.pt/dr/detalhe/lei/13-2023-211340863); [Diretiva (UE) 2024/2831, art. 9.º, 11.º e 29.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024L2831).
   - Urgência: **este mês.**

7. **Alergénios nos restaurantes.**
   - O quê: pedir às lojas parceiras os 14 alergénios por prato (hoje só 1 de 250 está preenchido); até lá, mostrar antes de pagar um contacto grátis para perguntar; levar à advogada a dúvida dos pré-embalados no modo revenda.
   - Quem: você (pedido às lojas); app (ecrã); advogada.
   - Porquê: [Regulamento (UE) 1169/2011, art. 14.º e 44.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32011R1169).
   - Urgência: **este mês.**

8. **Assistente e promoções dentro da lei.**
   - O quê: a saudação diz que é um assistente automático (IA); consentimento explícito antes de guardar alergias ou dietas; política de privacidade nova, com o assistente e os motores; confirmar que o Gemini e o Claude não treinam com os dados; Receita do Dia e `push-clientes-alvo` só para quem aceitou promoções.
   - Quem: app; advogada revê a política.
   - Porquê: [RGPD, art. 9.º e 13.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32016R0679); [Regulamento IA, art. 50.º](https://eur-lex.europa.eu/legal-content/PT/TXT/?uri=CELEX:32024R1689); [Lei 41/2004, art. 13.º-A](https://files.dre.pt/1s/2012/08/16700/0481304826.pdf).
   - Urgência: **este mês.**

9. **Pacote para o Hugo.**
   - O quê:
     - registo DAC7 (Modelo 61) e comunicação anual dos prestadores, com o prazo exato a confirmar;
     - contribuição de entidade contratante à Segurança Social;
     - simulação do seu IRS de 2026 com o DL 212/2026;
     - confirmar que o IRC de 2027 já é 18% por lei e se a empresa tem direito aos 12,5% do interior;
     - confirmar se a escolha do IVA normal prende a empresa por vários anos.
   - Quem: Hugo.
   - Porquê: [Lei 36/2023 / Modelo 61](https://info.portaldasfinancas.gov.pt/pt/apoio_contribuinte/questoes_frequentes/Pages/faqs-00455.aspx); [Código Contributivo, art. 140.º](https://diariodarepublica.pt/dr/legislacao-consolidada/lei/2009-34514575-114482070); [DL 212/2026](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/decreto-lei-212-2026.pdf); [CIRC, art. 87.º](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/CIRC_2R/Pages/irc87.aspx).
   - Urgência: **este mês** (o DAC7 de 2026 fecha em janeiro).

10. **Marca e TVDE.**
    - O quê: corrigir no livro e no `CLAUDE.md` que a "Já Está" é um pedido e não um registo; vigiar oposições até 29/12; ver com a advogada as classes 9 e 35. O TVDE fica fechado até haver licença do IMT em nome da empresa, e a advogada avalia as corridas já feitas sem licença.
    - Quem: você e a advogada (marca e TVDE); app (correção do livro).
    - Porquê: [INPI, processo 778820](https://servicosonline.inpi.justica.gov.pt/pesquisas/main/marcas.jsp?lang=PT); [Lei 45/2018, republicada pela Lei 59/2026](https://diariodarepublica.pt/dr/detalhe/lei/59-2026-1161801432).
    - Urgência: **pode esperar**, com o limite de 29/12 para a marca.

---

## POR CONFIRMAR (lista única)

- Valores das coimas por faturas fora de prazo (Hugo).
- Taxas de 7% e 10% da Segurança Social como entidade contratante (Hugo).
- Prazo exato da comunicação DAC7 (Hugo).
- Se a escolha do IVA normal prende a empresa por vários anos (Hugo).
- Taxa do IRC do interior, 12,5% (Hugo).
- Tabela nova de taxas do IRS por escalão (Diário da República).
- Data de 24/11 para a votação final do Orçamento de 2027.
- Se o pacote "Omnibus digital" mudou a data do art. 50.º do Regulamento IA.
- Se o art. 13.º-A da Lei 41/2004 foi alterado depois de 2012.
- Se o Gemini e o Claude usados pelo assistente são versões que não treinam com os dados dos clientes.
- Se o art. 22.º do RGPD se aplica ao assistente.
- Lei portuguesa de transposição da Diretiva 2024/2831 ("Trabalho XXI").
- Se hoje se exige farda ou mochila aos estafetas.
- Registo da empresa como operador na plataforma do Livro de Reclamações.
- Centro de arbitragem competente para a Guarda (Coimbra ou CNIACC).
- Se o aviso de livre resolução chega nas limpezas ou se é preciso pedido expresso marcado.
- Forma exata da informação de alergénios no DL 26/2016.
- Se o contacto antes de pagar chega para os alergénios.
- Responsabilidade da Bora pelos pré-embalados no modo revenda.
- Se a regra do álcool (DL 50/2013) se aplica à entrega em casa.
- Números dos artigos da Lei 45/2018 depois da republicação pela Lei 59/2026, incluindo o pagamento só eletrónico e as coimas.
- Marca "Bora Mobility" (o TMview bloqueou o acesso).

Provas desta pesquisa: SELECTs de 08/11/2026 no projeto Supabase `ojykpzwqrtusfeakzrna` (`legal_terms_versions`, `bora_invoices_pending`, `products`, `users`, `platform_settings`); pesquisa no INPI pelo serviço público de pesquisa de marcas (processo 778820, fase "pedido – aguarda oposição", 29/10 a 29/12/2026); textos legais lidos nos links acima a 08/11/2026.
