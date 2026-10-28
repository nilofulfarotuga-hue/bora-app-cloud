---
id: memoria-claude-ai-pesquisa-fatura-nif-2026-10-28
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# Fatura com NIF, produto em falta e entrega grátis nos parceiros — pesquisa e decisões (28/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `pesquisa-fatura-nif-2026-10-28`, origem `claude-ai`, atualizada em 2026-10-28T11:54:56.128698+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: pesquisa fatura nif 2026 10 28 · memoria claude.ai · claude_ai_memoria

# Fatura com NIF, produto em falta e entrega grátis — 28/10/2026

Pedido do Danilo (28/10 11:18), depois de falar com o Emanuel (Boom! Burger): como faturar se o cliente pedir NIF (loja fatura o balcão e a Bora o resto? ou a loja fatura o total?), cancelar só um produto em falta, entrega grátis acima de um valor (dá lucro?), campo do NIF na app, "verificar todas as questões de contabilidade para fazer certinho". Frase dele: "Ele vai pôr o NIF dele com o valor do balcão. E o restante, quem faria nós."

## O que diz a lei e o que fazem os outros
- Glovo PT (DECO): a loja é a vendedora e fatura os produtos; a Glovo só fatura a entrega e as taxas dela. O NIF põe-se em Conta > Dados de faturação e vai para a loja. Há reclamações de clientes a exigir a fatura com NIF das taxas da Glovo.
- Uber Eats PT: o restaurante fatura a comida; os estafetas prestam o serviço à Uber, que emite as faturas em nome deles por um fornecedor certificado (FONOA); a Uber cobra 23% de IVA nas suas taxas.
- IVA art. 53.º (DL 35/2025): isento quem não passou 15 000 € de volume de negócios no ano anterior; vale também para sociedades; no início de atividade conta a estimativa do ano; a saída do regime está no art. 58.º.
- Programa de faturação certificado é obrigatório para quem tem (ou tem de ter) contabilidade organizada, além de quem passa 50 000 € ou já usa programa (DL 28/2019). Uma Lda tem sempre contabilidade organizada: a empresa da Bora não pode faturar à mão no Portal.
- OCC (PT21664): entrega feita pelo próprio restaurante é acessória da refeição (13%). Entrega de plataforma é serviço da plataforma.
- InvoiceXpress: 100 documentos/mês = 24 €/mês (20 €/mês no anual), API em todos os planos.

## Decisão (o que se disse ao Danilo)
- Fica o modelo da Goola: a loja parceira fatura ao cliente o preço de balcão (= "Recebes" do painel; na Boom bate certo produto a produto) e a Bora fatura ao cliente o resto. Com NIF, as duas levam o NIF. Somadas dão o que o cliente pagou.
- Errado: a loja faturar o valor final (pagava imposto sobre dinheiro da Bora; Bora ficava com dinheiro sem fatura).
- Legal mas pior para a loja: modelo Uber (loja fatura o preço da app, Bora fatura-lhe comissão) — paga mais IVA e, com a Bora isenta, não recupera nada.
- A loja fatura por pedido ao cliente, não uma fatura por semana à Bora.
- A partir de 01/11/2026: a entrega passa a ser serviço da Bora e entra na fatura da Bora; o estafeta passa o recibo do mês à Bora (NIF 519686233) — é a autofaturação "como a Glovo/Uber" decidida a 07/10, posta em prática. Efeito: o volume da Bora cresce (limite de 15 000 € do art. 53.º chega mais cedo).

## Produto em falta
Já existe: painel do parceiro, pedido, "Marcar em falta" (order_edit_enabled=true; usado 1 vez em produção). Devolve sozinho (cartão por Stripe, carteira, ou menos a cobrar em dinheiro) e avisa cliente e estafeta. "Acrescentar produto" para trocar (o cliente aceita ou recusa).

## Entrega grátis
Hoje só funciona em NÃO parceiros (pricing_calculate_loja): McDonald's 20 €, Burger King e Continente 30 €. Contas na Boom (lucro da Bora por pedido, preço da app): 30 € a 4 km = +0,76 € cartão / +1,49 € dinheiro; 25 € = -0,13 € cartão; 20 € = -1,01 € cartão. Proposta: grátis a partir de 30 € só na taxa base de 2,50 € (km acima de 4 continuam a pagar-se; estafeta recebe igual). Distâncias reais (120 dias): mediana 4,0 km, 95% abaixo de 5,6 km. Espera "autorizo 30".

## Aplicado por MCP (28/10)
- Migração fatura_nif_cliente_2026_10_28: nif_pt_valido; client_billing_profile; order_invoice_requests (estafeta não vê; realtime); RPCs client_billing_get/save, client_set_order_invoice, partner_pedidos_fatura, admin_order_invoice_set, admin_client_billing_set; _bora_invoice_upsert com NIF e, a partir de 01/11, valor = receita; taxas de cancelamento com fatura (_bora_invoice_cancel_fees; a de 13/10, 2,50 €, entrou); driver_monthly_invoice_summary a partir de novembro com cliente Bora NIF 519686233.
- legal_terms_versions 'cliente' e 'estafeta' 2026-11-01.
- Provas (desfeitas): cliente guarda/lê NIF, NIF errado recusado, pedido cancelado TARDE_DEMAIS, outro cliente PEDIDO_NAO_E_TEU, parceiro Boom vê NIF e 24,50 €, estafeta vê 0.

## Falta
- App (adendo 4 no Claude Code do PC): campo NIF no checkout e perfil, NIF e valor a faturar no painel do parceiro, recibo do estafeta, admin. Colado 28/10 ~12:53; o Claude Code do PC pediu /login.
- Decisões do Danilo: "autorizo 30" (entrega grátis Boom); programa certificado (o do Hugo ou InvoiceXpress); nome da empresa (tem o nome dele) nas faturas; confirmar com o Hugo se a empresa ficou no art. 53.º.
- Fecho mensal: o total a declarar de outubro (receita própria) não bate com a soma das faturas da Bora (o que sobra depois do estafeta).

