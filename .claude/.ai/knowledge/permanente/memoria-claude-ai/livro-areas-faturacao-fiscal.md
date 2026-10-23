---
id: memoria-claude-ai-livro-areas-faturacao-fiscal
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# [PESSOAL] Modelo fiscal/faturação do Bora em Portugal — o que declara nas Finanças, autofaturação dos estafetas, contabilista da sociedade (indicado pelo Cauã)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-faturacao-fiscal`, origem `claude-ai`, atualizada em 2026-10-23T05:40:52.801221+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas faturacao fiscal · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/faturacao-fiscal.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: faturacao-fiscal
description: Modelo fiscal/faturação do Bora em Portugal — o que declara nas Finanças, autofaturação dos estafetas, contabilista da sociedade (indicado pelo Cauã)
sources: [chat]
aliases: [faturação, fiscal, IVA, contabilista, intermediário, quem emite a fatura]
---

- [stated] 2026-08-06: Danilo quer confirmar com contabilistas (a dele e a do dono do [[mister-kebab]]) se o modelo do [[bora-app]] é fiscalmente correto em Portugal. Preparou duas mensagens: uma para o dono do restaurante explicar o modelo, outra para a contabilista com perguntas diretas.
- [stated] Posição que ele quer defender: o Bora é INTERMEDIÁRIO, não compra nem revende os produtos — divulga na app, intermedia a venda, o pagamento e a entrega.
- [stated] Perguntas em aberto que ele quer respondidas: (1) o modelo é legal/correto em PT? (2) quem emite a fatura ao cliente final — restaurante ou Bora? (3) o Bora declara só a comissão ou o valor total recebido? (4) como funciona o IVA neste modelo? (5) existe regime específico para marketplaces?
- [stated] Danilo levantou a dúvida por sua iniciativa depois de configurar o [[stripe-connect]] (onde aceitou ser quem cobra o cliente e quem responde por reembolsos) — desconfiou que isso pudesse contradizer a posição de intermediário.
- [stated] Consequência assumida: a resposta dos contabilistas define como programar a faturação, a liquidação ao parceiro e o que entra como receita da plataforma. Fica pendente até haver resposta.
- [stated] 2026-08-06: Danilo pediu para eu próprio ir à lei portuguesa e resolver a classificação fiscal, em vez de depender só da resposta do contabilista — quer que a mensagem ao contabilista já leve a conclusão pronta.
- [stated] 2026-08-06: email enviado à contabilista com a conclusão (mandatário em nome próprio) pedindo confirmação; decidiu esperar a resposta antes de construir qualquer coisa (fatura, software, contabilidade).
- [stated] 2026-08-06: decidiu que a trava de recibo verde do motorista/estafeta deve ser MENSAL, não semanal.
- [stated] 2026-08-06: quer um agente que junte os fechos do mês (repasses, recibos, faturas, extrato) e envie automaticamente por email à contabilista todo dia 1, sem ele tocar em nada.
- [stated] 2026-08-06: quer também um agente/automação para capturar o NIF do cliente quando ele pedir no checkout.
- [stated] 12/08 CORREÇÃO IMPORTANTE do Danilo: ele **TEM atividade aberta** nas Finanças, e aberta precisamente para trabalho deste tipo (sites/serviços). Eu tinha assumido o contrário e disse-lhe que não podia faturar — estava errado. Ele PODE emitir recibo/fatura; a decisão de não passar fatura ao Guarda FC foi escolha dele naquele caso concreto, não uma impossibilidade. Não voltar a dizer-lhe que não tem como faturar
- [stated] 29/09 DECISÃO: nas Finanças declara SÓ o que o Bora lucra (as comissões/taxas), nunca a mercadoria; e o **TVDE fica de fora** da declaração do Bora — só entram delivery e as outras verticais. Vai pedir ao Claude Code para entrar no PC dele, no Portal das Finanças, e fazer isso — depois de ter os números do mês puxados
- PROMPT REGISTADO: `PROMPT_fecho_mensal_2026-09-29.md`, MOTOR OPUS 4.7, sessão nova `fecho-mensal-2026-09` na pasta bora-app-cloud — fecho mensal automático (RPC `admin_monthly_closeout`, extrato mensal por parceiro por email dia 1, ecrã `/admin/fecho-mensal`, bloco "para as Finanças" por rubrica). Estado: entregue 29/09, por colar/correr
- Números de setembro/2026 (verificados por SQL 29/09, TVDE fora): clientes pagaram 371,40 € em 17 entregas + 12 € barbearia; receita própria do Bora 96,21 €; estafetas 87,93 €; lucro 8,28 €. Custo dos não-parceiros = talão em `order_receipts_v2.driver_typed_total_cents` (`orders.final_purchase_value` NÃO é o talão). Todos os acertos de setembro aos parceiros já pagos
FINAL WRITE
- [stated] 29/09 (supera a espera pela contabilista de 06/08): "esquece contabilista" — quer que eu resolva pela lei portuguesa, sem contabilista. Tem uma pessoa de confiança (não contabilista) que lhe lança todos os meses nas Finanças o que ele fez; ela deixa o Portal das Finanças aberto no PC e eu (Claude) preencho os recibos lá
- [stated] 29/09 DECIDIU mudar o modelo a partir de outubro/2026: cada estafeta passa recibo verde do que ganhou no mês e o Bora só declara a sua comissão/taxas. Em setembro nenhum estafeta passou recibo
- [stated] 29/09: tem DUAS atividades abertas no nome dele — uma de estafeta e outra de "negócio online"; o dinheiro do Bora é lançado na do negócio online. A pessoa que lhe lança as Finanças ainda não sabia que ele tem o Bora (a mensagem de 29/09 é a primeira vez que lho explica); é ela que lhe pergunta todos os meses quanto faturou
- [stated] 07/10 CORREÇÃO: ainda não lançou nada do Bora nas Finanças pela atividade dele — a receita do Bora ainda quase não existe; começa a declarar a partir do mês seguinte (novembro/2026)
- [stated] 07/10 (supera o "esquece contabilista" de 29/09): vai abrir a sociedade do Bora com um contabilista (contacto indicado pelo Cauã da [[sabores-de-casa]]), que aceitou preparar e acompanhar a empresa; pediu-lhe tudo por escrito. Não terá funcionários — estafetas, motoristas e lojas são parceiros independentes
- [stated] 07/10 DECISÃO: estafetas passam a ser faturados por AUTOFATURAÇÃO (o Bora emite as faturas em nome deles com acordo escrito, como a Glovo/Uber Eats) — supera o recibo verde passado à mão por cada estafeta decidido a 29/09
- [stated] 07/10: aceitou os honorários do contabilista (100 €/mês, a atualizar com a evolução da empresa) e decidiu avançar com a abertura da sociedade; já desconta Segurança Social como independente (atividade aberta, TVDE), por isso não quer ordenado de gerente nem o mínimo de gerente
- [stated] 07/10: como trabalhador independente está isento de IVA; perguntou ao contabilista se a sociedade nova fica também isenta
- [stated] 07/10: recusou, por ser complicado demais, o modelo de compra nos mercados com fatura em nome/NIF de cada cliente
- [stated] 07/10: a sociedade do Bora vai ser constituída pela advogada Dra. Cristina Escaleira (contacto passado pelo contabilista da DC Consultores); custo indicado 220 € de conservatória + 150 € de honorários dela
- [stated] 09/10: assinou o contrato e pagou a advogada; o contrato ficou com capital social de 10.000 € em dinheiro, a entregar até ao fim do primeiro exercício — ele não contava com esse valor e questionou-o (ainda por resolver com a advogada); faltam RCBE e conta bancária da empresa
- [stated] 20/10: vai abrir a conta bancária da empresa no Millennium (já tem conta pessoal lá); da advogada só tem o email, nenhum documento da empresa em papel — pediu resposta curta
FINAL WRITE
- [stated] 21/10: quem lhe vai abrir a conta da empresa no Millennium é o gerente José Ferrão (Sucursal Guarda Vasco da Gama, jose.ferrao@millenniumbcp.pt); combinou mandar-lhe os documentos da empresa por email e passar na agência para deixar o cartão de residência
- [stated] 21/10: recebeu do contabilista o comprovativo do início de atividade da sociedade nas Finanças e mandou-o ao José Ferrão (Millennium) para a conta da empresa
- [stated] 22/10: o contabilista da sociedade é o Hugo Carvalho (DC Consultores), que criou um grupo de WhatsApp "Contabilidade" com o escritório e está a preparar a ata da remuneração do gerente; o Danilo passa recibos verdes do TVDE à frota

